import { parseRealtorBalance, parseRealtorSettlement, parseSettlementInput } from "./realtor-settlement-contract.ts";
import { getAppBaseUrl } from "../../lib/env/supabase-public.ts";

export type ReadBalance = (reservationId: string) => Promise<unknown>;
export type WriteSettlement = (reservationId: string, input: unknown, key: string) => Promise<unknown>;

export async function handleRealtorBalanceGet(request: Request, reservationId: string, read: ReadBalance): Promise<Response> {
  if (!isUuid(reservationId)) return error(404, "NOT_FOUND", "Rezervasiya tapılmadı.");
  if (!sameOrigin(request)) return error(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
  try {
    const balance = parseRealtorBalance(await read(reservationId));
    if (!balance) throw new Error("realtor_balance_invalid");
    return json(200, { data: balance, meta: { request_id: crypto.randomUUID() } });
  } catch (cause) { return mapError(cause); }
}

export async function handleRealtorSettlementPost(request: Request, reservationId: string, write: WriteSettlement): Promise<Response> {
  if (!isUuid(reservationId)) return error(404, "NOT_FOUND", "Rezervasiya tapılmadı.");
  if (!sameOrigin(request)) return error(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
    return error(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil.");
  }
  const key = request.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(key)) return error(400, "VALIDATION_ERROR", "Təkrar sorğu açarı düzgün deyil.");
  let body: unknown;
  try { body = await request.json(); } catch { return error(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil."); }
  const input = parseSettlementInput(body);
  if (!input) return error(422, "VALIDATION_ERROR", "Hesablaşmanın məlumatlarını yoxlayın.");
  try {
    const settlement = parseRealtorSettlement(await write(reservationId, input, key));
    if (!settlement || settlement.reservation_id !== reservationId) throw new Error("realtor_settlement_invalid");
    return json(201, { data: settlement, meta: { request_id: crypto.randomUUID() } });
  } catch (cause) { return mapError(cause); }
}

function isUuid(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function sameOrigin(request: Request): boolean {
  const canonical = getAppBaseUrl().url;
  const host = request.headers.get("host");
  if (!host) return false;
  try { if (new URL(`${new URL(canonical).protocol}//${host}`).host !== new URL(canonical).host) return false; } catch { return false; }
  const origin = request.headers.get("origin");
  if (origin !== null) { try { return new URL(origin).origin === origin && new URL(origin).origin === new URL(canonical).origin; } catch { return false; } }
  if (request.headers.get("sec-fetch-site") === "cross-site") return false;
  if (request.headers.get("x-eve-same-origin") === "1" || request.headers.get("sec-fetch-site") === "same-origin") return true;
  const referer = request.headers.get("referer");
  try { return referer !== null && new URL(referer).origin === new URL(canonical).origin; } catch { return false; }
}
function mapError(cause: unknown): Response {
  const code = typeof cause === "object" && cause !== null && "code" in cause && typeof cause.code === "string" ? cause.code : "PROVIDER_UNAVAILABLE";
  const status = code === "UNAUTHENTICATED" ? 401 : code === "FORBIDDEN" ? 403 : code === "NOT_FOUND" ? 404
    : code === "VALIDATION_ERROR" ? 422 : code === "CONFLICT" ? 409 : 503;
  const message = code === "UNAUTHENTICATED" ? "Sessiya yoxdur, bitib və ya ləğv edilib."
    : code === "FORBIDDEN" ? "Bu əməliyyat üçün maliyyə icazəsi yoxdur."
      : code === "NOT_FOUND" ? "Rezervasiya tapılmadı."
        : code === "VALIDATION_ERROR" ? "Hesablaşmanın məlumatlarını yoxlayın."
          : code === "CONFLICT" ? "Balans dəyişib və ya təkrar sorğu açarı fərqli əməliyyat üçün istifadə olunub."
            : "Realtor hesablaşma xidməti hazırda əlçatan deyil.";
  return error(status, code, message);
}
function error(status: number, code: string, message: string): Response { return json(status, { error: { code, message, request_id: crypto.randomUUID() } }); }
function json(status: number, value: unknown): Response { return new Response(JSON.stringify(value), { status, headers: {
  "Content-Type": "application/json; charset=utf-8", "Cache-Control": "private, no-store", "Referrer-Policy": "no-referrer", "X-Robots-Tag": "noindex, nofollow",
} }); }
