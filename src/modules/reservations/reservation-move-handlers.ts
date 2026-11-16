import { parseReservationEnvelope } from "./reservation-contract.ts";
import { parseReservationMoveInput } from "./reservation-change-contract.ts";
import { isSameOriginRequest } from "./reservation-handlers.ts";

export type ReservationMoveOperation = (
  reservationId: string,
  input: unknown,
  idempotencyKey: string,
) => Promise<unknown>;

export async function handleReservationMove(
  request: Request,
  reservationId: string,
  move: ReservationMoveOperation,
): Promise<Response> {
  if (!isSameOriginRequest(request)) return errorResponse(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
  if (!isUuid(reservationId)) return errorResponse(404, "NOT_FOUND", "Rezervasiya tapılmadı.");
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
    return errorResponse(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil.");
  }
  const key = request.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(key)) {
    return errorResponse(400, "VALIDATION_ERROR", "Təkrar sorğu açarı düzgün deyil.");
  }
  let input: unknown;
  try { input = await request.json(); }
  catch { return errorResponse(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil."); }
  let parsed: ReturnType<typeof parseReservationMoveInput>;
  try { parsed = parseReservationMoveInput(input); }
  catch { return errorResponse(422, "VALIDATION_ERROR", "Rezervasiya köçürmə məlumatlarını yoxlayın."); }
  try {
    const data = await move(reservationId, parsed, key);
    const envelope = parseReservationEnvelope({ data, meta: { request_id: crypto.randomUUID() } });
    if (envelope.data.id !== reservationId) throw new TypeError("reservation_move_result_mismatch");
    return jsonResponse(200, envelope);
  } catch (error) {
    const code = isRecord(error) && typeof error.code === "string" ? error.code : "PROVIDER_UNAVAILABLE";
    const status = code === "UNAUTHENTICATED" ? 401 : code === "FORBIDDEN" ? 403 : code === "NOT_FOUND" ? 404
      : code === "VALIDATION_ERROR" ? 422 : code === "CONFLICT" ? 409 : 503;
    const message = code === "UNAUTHENTICATED" ? "Sessiya yoxdur, bitib və ya ləğv edilib."
      : code === "FORBIDDEN" ? "Mənbə və hədəf evdə rezervasiya dəyişmək icazəsi yoxdur."
        : code === "NOT_FOUND" ? "Rezervasiya tapılmadı və ya giriş icazəsi yoxdur."
          : code === "VALIDATION_ERROR" ? "Rezervasiya köçürmə məlumatlarını yoxlayın."
            : code === "CONFLICT" ? "Rezervasiya dəyişib və ya hədəf ev həmin tarixlərdə boş deyil. Yeniləyib təkrar yoxlayın."
              : "Rezervasiya xidməti hazırda əlçatan deyil.";
    return errorResponse(status, code, message);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
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
