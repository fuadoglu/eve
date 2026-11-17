import { getCalendar, CalendarApiError } from "@/modules/reservations/supabase-calendar-api.ts";
import { parseCalendarEnvelope, parseCalendarQuery } from "@/modules/reservations/calendar-contract.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const input = parseCalendarQuery(url.searchParams);
  if (!input) {
    return errorResponse(400, "VALIDATION_ERROR", "Təqvim sorğusunun forması düzgün deyil.");
  }

  try {
    const data = await getCalendar(input);
    const envelope = parseCalendarEnvelope({ data, meta: { request_id: crypto.randomUUID() } });
    // Keep the documented OpenAPI Calendar DTO intact. The UI adapter reduces
    // it to fields needed for rendering; this endpoint does not rewrite DTOs.
    return privateResponse(200, { data, meta: envelope.meta });
  } catch (error) {
    if (error instanceof CalendarApiError) {
      const status = error.code === "UNAUTHENTICATED" ? 401
        : error.code === "FORBIDDEN" ? 403
          : error.code === "NOT_FOUND" ? 404
            : error.code === "VALIDATION_ERROR" ? 422 : 503;
      return errorResponse(status, error.code, publicMessage(error.code));
    }
    return errorResponse(503, "PROVIDER_UNAVAILABLE", "Təqvim məlumatını yükləmək mümkün olmadı.");
  }
}

function publicMessage(code: string): string {
  switch (code) {
    case "UNAUTHENTICATED": return "Davam etmək üçün Eve hesabınıza daxil olun.";
    case "FORBIDDEN": return "Bu evin təqviminə baxmaq icazəniz yoxdur.";
    case "NOT_FOUND": return "Seçilmiş evlərdən birinin təqvimi tapılmadı.";
    case "VALIDATION_ERROR": return "Tarix aralığını və ev seçimlərini yoxlayın.";
    default: return "Təqvim məlumatını yükləmək mümkün olmadı. Bağlantını yoxlayıb yenidən cəhd edin.";
  }
}

function errorResponse(status: number, code: string, message: string): Response {
  return privateResponse(status, { error: { code, message, request_id: crypto.randomUUID() } });
}

function privateResponse(status: number, body: unknown): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "private, no-store",
      "Referrer-Policy": "no-referrer",
      "X-Robots-Tag": "noindex, nofollow",
    },
  });
}
