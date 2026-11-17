import { parseReservationEnvelope } from "./reservation-contract.ts";
import { isSameOriginRequest } from "./reservation-handlers.ts";

export type ReservationWriteOperation = (reservationId: string, input: unknown, idempotencyKey: string) => Promise<unknown>;
const MAX_MINOR = Number.MAX_SAFE_INTEGER;

export async function handleReservationPatch(request: Request, id: string, patch: ReservationWriteOperation): Promise<Response> {
  return handleWrite(request, id, patch, parsePatch, "Rezervasiya məlumatlarını yoxlayın.");
}

export async function handleReservationTransition(request: Request, id: string, transition: ReservationWriteOperation): Promise<Response> {
  return handleWrite(request, id, transition, parseTransition, "Rezervasiya keçid məlumatlarını yoxlayın.");
}

async function handleWrite(request: Request, id: string, operation: ReservationWriteOperation,
  parse: (value: unknown) => unknown, validationMessage: string): Promise<Response> {
  if (!isSameOriginRequest(request)) return error(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
  if (!isUuid(id)) return error(404, "NOT_FOUND", "Rezervasiya tapılmadı.");
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
    return error(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil.");
  }
  const key = request.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(key)) return error(400, "VALIDATION_ERROR", "Təkrar sorğu açarı düzgün deyil.");
  let raw: unknown;
  try { raw = await request.json(); } catch { return error(400, "VALIDATION_ERROR", "Sorğunun formatı düzgün deyil."); }
  let input: unknown;
  try { input = parse(raw); } catch { return error(422, "VALIDATION_ERROR", validationMessage); }
  try {
    const data = await operation(id, input, key);
    const envelope = parseReservationEnvelope({ data, meta: { request_id: crypto.randomUUID() } });
    if (envelope.data.id !== id) throw new TypeError("reservation_write_result_mismatch");
    return json(200, envelope);
  } catch (cause) {
    const code = isRecord(cause) && typeof cause.code === "string" ? cause.code : "PROVIDER_UNAVAILABLE";
    const status = code === "UNAUTHENTICATED" ? 401 : code === "FORBIDDEN" ? 403 : code === "NOT_FOUND" ? 404
      : code === "VALIDATION_ERROR" ? 422 : code === "CONFLICT" ? 409 : 503;
    const message = code === "UNAUTHENTICATED" ? "Sessiya yoxdur, bitib və ya ləğv edilib."
      : code === "FORBIDDEN" ? "Bu evdə rezervasiya dəyişmək icazəsi yoxdur."
        : code === "NOT_FOUND" ? "Rezervasiya tapılmadı və ya giriş icazəsi yoxdur."
          : code === "VALIDATION_ERROR" ? validationMessage
            : code === "CONFLICT" ? "Rezervasiya dəyişib və ya bu əməliyyat hazırda mümkün deyil. Yeniləyib təkrar yoxlayın."
              : "Rezervasiya xidməti hazırda əlçatan deyil.";
    return error(status, code, message);
  }
}

function parsePatch(value: unknown): Record<string, unknown> {
  const allowed = ["expected_version", "guest_name", "guest_phone", "guest_count", "check_in", "check_out", "check_in_time", "check_out_time", "total_minor", "capacity_override_confirmed", "commission", "note", "free_stay"];
  if (!isRecord(value) || !hasOnly(value, allowed) || !positiveInt(value.expected_version) || Object.keys(value).length < 2) throw new TypeError("invalid_patch");
  if (("guest_name" in value && (typeof value.guest_name !== "string" || [...value.guest_name].length < 1 || [...value.guest_name].length > 150))
    || ("guest_phone" in value && value.guest_phone !== null && (typeof value.guest_phone !== "string" || !/^\+[1-9][0-9]{7,14}$/.test(value.guest_phone)))
    || ("guest_count" in value && (!positiveInt(value.guest_count) || value.guest_count > 1000))
    || ("check_in" in value && !calendarDate(value.check_in)) || ("check_out" in value && !calendarDate(value.check_out))
    || ("check_in_time" in value && !localTime(value.check_in_time)) || ("check_out_time" in value && !localTime(value.check_out_time))
    || ("total_minor" in value && !minor(value.total_minor)) || ("capacity_override_confirmed" in value && typeof value.capacity_override_confirmed !== "boolean")
    || ("commission" in value && value.commission !== null && !isCommission(value.commission))
    || ("note" in value && (typeof value.note !== "string" || [...value.note].length > 2000))
    || ("free_stay" in value && typeof value.free_stay !== "boolean")) throw new TypeError("invalid_patch");
  if (value.total_minor === 0 && value.free_stay !== true) throw new TypeError("zero_price_requires_free_stay");
  if (typeof value.check_in === "string" && typeof value.check_out === "string" && value.check_out <= value.check_in) throw new TypeError("invalid_interval");
  return value;
}

function parseTransition(value: unknown): Record<string, unknown> {
  if (!isRecord(value) || !hasOnly(value, ["expected_version", "action", "reason", "new_check_out", "new_total_minor", "financial_decision", "free_stay"])
    || !positiveInt(value.expected_version) || !["confirm", "cancel", "no_show", "check_in", "check_out", "release_remaining_days"].includes(String(value.action))
    || ("reason" in value && (typeof value.reason !== "string" || [...value.reason].length > 2000))
    || ("new_check_out" in value && !calendarDate(value.new_check_out)) || ("new_total_minor" in value && !minor(value.new_total_minor))
    || ("free_stay" in value && (value.action !== "release_remaining_days" || value.free_stay !== true || value.new_total_minor !== 0))) throw new TypeError("invalid_transition");
  if (value.action === "release_remaining_days" && (!calendarDate(value.new_check_out) || !minor(value.new_total_minor)
    || value.new_total_minor === 0 && value.free_stay !== true)) throw new TypeError("invalid_release");
  if ("financial_decision" in value) {
    const decision = value.financial_decision;
    if (value.action !== "cancel" && value.action !== "no_show" || !isFinancialDecision(decision)) throw new TypeError("invalid_financial_decision");
  }
  return value;
}

function isFinancialDecision(value: unknown): boolean {
  if (!isRecord(value) || !hasOnly(value, ["mode", "rent_refunds", "deposit_returns", "commission_keep_minor"])) return false;
  if (value.mode === "keep_as_is") return Object.keys(value).length === 1;
  if (value.mode !== "adjust" || Object.keys(value).length < 2) return false;
  const adjustments = (items: unknown) => Array.isArray(items) && items.length >= 1 && items.length <= 100 && items.every((item) =>
    isRecord(item) && hasOnly(item, ["original_id", "amount_minor"]) && isUuid(String(item.original_id)) && positiveInt(item.amount_minor) && minor(item.amount_minor));
  return (!("rent_refunds" in value) || adjustments(value.rent_refunds)) && (!("deposit_returns" in value) || adjustments(value.deposit_returns))
    && (!("commission_keep_minor" in value) || minor(value.commission_keep_minor));
}
function isCommission(v: unknown): boolean {
  if (!isRecord(v) || !hasOnly(v, ["contact_id", "kind", "fixed_minor", "basis_minor", "percentage_basis_points"]) || !isUuid(String(v.contact_id))) return false;
  if (v.kind === "fixed") return positiveInt(v.fixed_minor) && !("percentage_basis_points" in v)
    && (!("basis_minor" in v) || minor(v.basis_minor));
  return v.kind === "percentage" && positiveInt(v.percentage_basis_points) && v.percentage_basis_points <= 10000
    && !("fixed_minor" in v) && (!("basis_minor" in v) || minor(v.basis_minor));
}
function positiveInt(v: unknown): v is number { return typeof v === "number" && Number.isSafeInteger(v) && v >= 1 && v <= MAX_MINOR; }
function minor(v: unknown): v is number { return typeof v === "number" && Number.isSafeInteger(v) && v >= 0 && v <= MAX_MINOR; }
function calendarDate(v: unknown): v is string { if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return false; const d = new Date(`${v}T00:00:00.000Z`); return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === v; }
function localTime(v: unknown): v is string { return typeof v === "string" && /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(v); }
function isUuid(v: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v); }
function isRecord(v: unknown): v is Record<string, unknown> { return typeof v === "object" && v !== null && !Array.isArray(v); }
function hasOnly(v: Record<string, unknown>, keys: string[]): boolean { return Object.keys(v).every((k) => keys.includes(k)); }
function error(status: number, code: string, message: string): Response { return json(status, { error: { code, message, request_id: crypto.randomUUID() } }); }
function json(status: number, body: unknown): Response { return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "private, no-store", "Referrer-Policy": "no-referrer", "X-Robots-Tag": "noindex, nofollow" } }); }
