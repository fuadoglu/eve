import { parseRentEntry, parseRentEntryCreate, type RentEntryPage } from "./rent-entry-contract.ts";
import { getAppBaseUrl } from "../../lib/env/supabase-public.ts";

export type RentEntryCreateOperation = (reservationId: string, input: unknown, key: string) => Promise<unknown>;
export type RentEntryListOperation = (reservationId: string, cursor: string | null, limit: number) => Promise<unknown>;

export async function handleRentEntryGet(request: Request, reservationId: string, list: RentEntryListOperation): Promise<Response> {
  if (!isUuid(reservationId)) return errorResponse(404, "NOT_FOUND", "Rezervasiya tapılmadı.");
  if (!isSameOriginRequest(request)) return errorResponse(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
  const params = new URL(request.url).searchParams;
  const limitValue = params.get("limit") ?? "30";
  if (!/^(?:[1-9]|[1-9][0-9]|100)$/.test(limitValue) || [...params.keys()].some((key) => !["cursor", "limit"].includes(key))) {
    return errorResponse(400, "VALIDATION_ERROR", "Səhifə parametrləri düzgün deyil.");
  }
  const cursor = params.get("cursor");
  if (cursor !== null && (cursor.length > 512 || !/^[A-Za-z0-9_-]+$/.test(cursor))) {
    return errorResponse(400, "VALIDATION_ERROR", "Səhifə davam açarı düzgün deyil.");
  }
  try {
    const result = await list(reservationId, cursor, Number(limitValue));
    if (!isPage(result)) throw new Error("rent_page_invalid");
    return jsonResponse(200, { data: result, meta: { request_id: crypto.randomUUID() } });
  } catch (error) { return mapError(error); }
}

export async function handleRentEntryPost(request: Request, reservationId: string, create: RentEntryCreateOperation): Promise<Response> {
  if (!isUuid(reservationId)) return errorResponse(404, "NOT_FOUND", "Rezervasiya tapılmadı.");
  if (!isSameOriginRequest(request)) return errorResponse(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
    return errorResponse(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil.");
  }
  const key = request.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(key)) return errorResponse(400, "VALIDATION_ERROR", "Təkrar sorğu açarı düzgün deyil.");
  let value: unknown;
  try { value = await request.json(); } catch { return errorResponse(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil."); }
  const input = parseRentEntryCreate(value);
  if (!input) return errorResponse(422, "VALIDATION_ERROR", "Pul əməliyyatının məlumatlarını yoxlayın.");
  try {
    const entry = parseRentEntry(await create(reservationId, input, key));
    if (!entry || entry.reservation_id !== reservationId) throw new Error("rent_entry_invalid");
    return jsonResponse(201, { data: entry, meta: { request_id: crypto.randomUUID() } });
  } catch (error) { return mapError(error); }
}

function isPage(value: unknown): value is RentEntryPage {
  if (!isRecord(value) || !Array.isArray(value.items) || value.items.length > 100
      || !(value.next_cursor === null || typeof value.next_cursor === "string")) return false;
  return value.items.every((item) => parseRentEntry(item) !== null);
}
function isUuid(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function isSameOriginRequest(request: Request): boolean {
  const canonicalOrigin = getAppBaseUrl().url;
  const host = request.headers.get("host");
  if (!host) return false;
  try { if (new URL(`${new URL(canonicalOrigin).protocol}//${host}`).host !== new URL(canonicalOrigin).host) return false; }
  catch { return false; }
  const origin = request.headers.get("origin");
  if (origin !== null) { try { return new URL(origin).origin === origin && new URL(origin).origin === new URL(canonicalOrigin).origin; } catch { return false; } }
  if (request.headers.get("sec-fetch-site") === "cross-site") return false;
  if (request.headers.get("x-eve-same-origin") === "1" || request.headers.get("sec-fetch-site") === "same-origin") return true;
  const referer = request.headers.get("referer");
  try { return referer !== null && new URL(referer).origin === new URL(canonicalOrigin).origin; } catch { return false; }
}
function mapError(error: unknown): Response {
  const code = isRecord(error) && typeof error.code === "string" ? error.code : "PROVIDER_UNAVAILABLE";
  const status = code === "UNAUTHENTICATED" ? 401 : code === "FORBIDDEN" ? 403 : code === "NOT_FOUND" ? 404
    : code === "VALIDATION_ERROR" ? 422 : code === "CONFLICT" ? 409 : 503;
  const message = code === "UNAUTHENTICATED" ? "Sessiya yoxdur, bitib və ya ləğv edilib."
    : code === "FORBIDDEN" ? "Bu əməliyyat üçün maliyyə icazəsi yoxdur."
      : code === "NOT_FOUND" ? "Rezervasiya tapılmadı."
        : code === "VALIDATION_ERROR" ? "Pul əməliyyatının məlumatlarını yoxlayın."
          : code === "CONFLICT" ? "Bu təkrar sorğu açarı fərqli əməliyyat üçün istifadə olunub."
            : "Pul qeydləri xidməti hazırda əlçatan deyil.";
  return errorResponse(status, code, message);
}
function errorResponse(status: number, code: string, message: string): Response { return jsonResponse(status, { error: { code, message, request_id: crypto.randomUUID() } }); }
function jsonResponse(status: number, value: unknown): Response { return new Response(JSON.stringify(value), { status, headers: {
  "Content-Type": "application/json; charset=utf-8", "Cache-Control": "private, no-store", "Referrer-Policy": "no-referrer", "X-Robots-Tag": "noindex, nofollow",
} }); }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
