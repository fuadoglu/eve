import { getAppBaseUrl } from "../../lib/env/supabase-public.ts";
import { parseExpenseProposal, parseExpenseProposalInput } from "./expense-proposal-contract.ts";
import { ExpenseProposalError } from "./expense-proposal-error.ts";

export type CreateExpenseProposal = (input: unknown, key: string) => Promise<unknown>;

export async function handleExpenseProposalPost(request: Request, create: CreateExpenseProposal): Promise<Response> {
  if (!sameOrigin(request)) return error(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json")
    return error(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil.");
  const key = request.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(key))
    return error(400, "VALIDATION_ERROR", "Təkrar sorğu açarı düzgün deyil.");
  let body: unknown;
  try { body = await request.json(); } catch { return error(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil."); }
  const input = parseExpenseProposalInput(body);
  if (!input) return error(422, "VALIDATION_ERROR", "Xərc təklifi və paylama məlumatlarını yoxlayın.");
  try {
    const result = parseExpenseProposal(await create(input, key));
    if (!result) throw new ExpenseProposalError("PROVIDER_UNAVAILABLE");
    return json(201, { data: result, meta: { request_id: crypto.randomUUID() } });
  } catch (cause) {
    const code = cause instanceof ExpenseProposalError ? cause.code : "PROVIDER_UNAVAILABLE";
    const status = code === "UNAUTHENTICATED" ? 401 : code === "FORBIDDEN" ? 403
      : code === "NOT_FOUND" ? 404 : code === "VALIDATION_ERROR" ? 422
        : code === "CONFLICT" ? 409 : 503;
    return error(status, code, status === 503 ? "Xərc xidməti hazırda əlçatan deyil." : "Xərc təklifi qəbul edilmədi.");
  }
}

function sameOrigin(request: Request): boolean {
  const app = new URL(getAppBaseUrl().url);
  const host = request.headers.get("host");
  if (!host || host !== app.host || request.headers.get("sec-fetch-site") === "cross-site") return false;
  const origin = request.headers.get("origin");
  if (origin) { try { return new URL(origin).origin === app.origin; } catch { return false; } }
  if (request.headers.get("x-eve-same-origin") === "1" || request.headers.get("sec-fetch-site") === "same-origin") return true;
  const referer = request.headers.get("referer");
  try { return referer !== null && new URL(referer).origin === app.origin; } catch { return false; }
}
function error(status: number, code: string, message: string): Response {
  return json(status, { error: { code, message, request_id: crypto.randomUUID() } });
}
function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: {
    "Content-Type": "application/json; charset=utf-8", "Cache-Control": "private, no-store",
    "Referrer-Policy": "no-referrer", "X-Robots-Tag": "noindex, nofollow",
  } });
}
