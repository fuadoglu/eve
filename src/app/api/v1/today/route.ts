import { getToday, TodayApiError } from "@/modules/today/supabase-today-api.ts";
import { parseTodayEnvelope } from "@/modules/today/today-contract.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const localDates = url.searchParams.getAll("local_date");
  const ownerAccountIds = url.searchParams.getAll("owner_account_id");
  if (localDates.length > 1 || ownerAccountIds.length > 1) {
    return errorResponse(400, "VALIDATION_ERROR", "Sorğu parametrlərini yoxlayın.");
  }

  const localDate = localDates[0] ?? null;
  const ownerAccountId = ownerAccountIds[0] ?? null;
  if ((localDate !== null && !isCalendarDate(localDate))
    || (ownerAccountId !== null && !isUuid(ownerAccountId))) {
    return errorResponse(400, "VALIDATION_ERROR", "Sorğu parametrlərini yoxlayın.");
  }

  try {
    const data = await getToday({ localDate, ownerAccountId });
    const envelope = parseTodayEnvelope({ data, meta: { request_id: crypto.randomUUID() } });
    return jsonResponse(200, envelope);
  } catch (error) {
    const code = error instanceof TodayApiError ? error.code : "PROVIDER_UNAVAILABLE";
    const status = code === "UNAUTHENTICATED" ? 401 : code === "FORBIDDEN" ? 403
      : code === "NOT_FOUND" ? 404 : code === "VALIDATION_ERROR" ? 422 : 503;
    return errorResponse(status, code, publicMessage(code));
  }
}

function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function publicMessage(code: string): string {
  if (code === "UNAUTHENTICATED") return "Gündəlik planı açmaq üçün yenidən daxil olun.";
  if (code === "FORBIDDEN") return "Bu gündəlik plana giriş icazəsi yoxdur.";
  if (code === "NOT_FOUND") return "Seçilmiş evlər üzrə gündəlik plan tapılmadı.";
  if (code === "VALIDATION_ERROR") return "Sorğu parametrlərini yoxlayın.";
  return "Bugünkü planı yükləmək mümkün olmadı. Bir az sonra yenidən yoxlayın.";
}

function errorResponse(status: number, code: string, message: string): Response {
  return jsonResponse(status, { error: { code, message, request_id: crypto.randomUUID() } });
}

function jsonResponse(status: number, value: unknown): Response {
  return new Response(JSON.stringify(value), { status, headers: {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "private, no-store",
    "Referrer-Policy": "no-referrer",
    "X-Robots-Tag": "noindex, nofollow",
  } });
}
