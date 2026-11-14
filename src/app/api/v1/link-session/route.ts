import { handleLinkSession } from "@/modules/media/media-access-handlers.ts";
import { exchangeScopedLink } from "@/modules/media/supabase-media-access.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request): Promise<Response> {
  try { return await handleLinkSession(request, exchangeScopedLink); }
  catch {
    return new Response(JSON.stringify({ error: { code: "PROVIDER_UNAVAILABLE", message: "Keçid xidməti hazırda əlçatan deyil.", request_id: crypto.randomUUID() } }),
      { status: 503, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "private, no-store", "Referrer-Policy": "no-referrer", "X-Robots-Tag": "noindex, nofollow" } });
  }
}
