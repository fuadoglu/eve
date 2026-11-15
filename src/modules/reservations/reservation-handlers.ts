import { parseReservationEnvelope } from "./reservation-contract.ts";

export type ReservationCreateOperation = (input: unknown, idempotencyKey: string) => Promise<unknown>;

export async function handleReservationCreate(request: Request, create: ReservationCreateOperation): Promise<Response> {
  if (!isSameOriginRequest(request)) return errorResponse(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
    return errorResponse(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil.");
  }
  const key = request.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(key)) return errorResponse(400, "VALIDATION_ERROR", "Təkrar sorğu açarı düzgün deyil.");
  let input: unknown;
  try { input = await request.json(); }
  catch { return errorResponse(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil."); }
  if (!isRecord(input)) return errorResponse(422, "VALIDATION_ERROR", "Rezervasiya məlumatları düzgün deyil.");
  try {
    const data = await create(input, key);
    const envelope = parseReservationEnvelope({ data, meta: { request_id: crypto.randomUUID() } });
    return jsonResponse(201, envelope);
  } catch (error) {
    const code = isRecord(error) && typeof error.code === "string" ? error.code : "PROVIDER_UNAVAILABLE";
    const status = code === "UNAUTHENTICATED" ? 401 : code === "FORBIDDEN" ? 403 : code === "NOT_FOUND" ? 404
      : code === "VALIDATION_ERROR" ? 422 : code === "CONFLICT" ? 409 : 503;
    return errorResponse(status, code, publicMessage(code));
  }
}

function sameOrigin(origin: string, requestUrl: string): boolean {
  try { return new URL(origin).origin === new URL(requestUrl).origin; }
  catch { return false; }
}
function isSerializedOrigin(origin: string): boolean {
  try { return new URL(origin).origin === origin; }
  catch { return false; }
}
function isSameOriginRequest(request: Request): boolean {
  if (request.headers.has("origin")) {
    const origin = request.headers.get("origin");
    return origin !== null && isSerializedOrigin(origin) && sameOrigin(origin, request.url);
  }
  const fetchSite = request.headers.get("sec-fetch-site");
  if (fetchSite === "cross-site") return false;
  if (fetchSite === "same-origin") return true;
  const referer = request.headers.get("referer");
  return referer !== null && sameOrigin(referer, request.url);
}
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
function publicMessage(code: string): string {
  if (code === "UNAUTHENTICATED") return "Sessiya yoxdur, bitib və ya ləğv edilib.";
  if (code === "FORBIDDEN") return "Bu evdə rezervasiya yaratmaq icazəsi yoxdur.";
  if (code === "NOT_FOUND") return "Ev tapılmadı və ya giriş icazəsi yoxdur.";
  if (code === "VALIDATION_ERROR") return "Rezervasiya məlumatlarını yoxlayın.";
  if (code === "CONFLICT") return "Bu tarixlərdə evin tutumu artıq mövcud deyil və ya təkrar sorğu açarı fərqli məlumatla istifadə olunub.";
  return "Rezervasiya xidməti hazırda əlçatan deyil.";
}
function errorResponse(status: number, code: string, message: string): Response {
  return jsonResponse(status, { error: { code, message, request_id: crypto.randomUUID() } });
}
function jsonResponse(status: number, value: unknown): Response {
  return new Response(JSON.stringify(value), { status, headers: {
    "Content-Type": "application/json; charset=utf-8", "Cache-Control": "private, no-store",
    "Referrer-Policy": "no-referrer", "X-Robots-Tag": "noindex, nofollow",
  } });
}
