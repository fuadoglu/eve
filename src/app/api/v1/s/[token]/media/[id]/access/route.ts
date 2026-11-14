import { handleScopedMediaAccess } from "@/modules/media/media-access-handlers.ts";
import { getMediaSigningSecret, getScopedMediaSource } from "@/modules/media/supabase-media-access.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request, context: { params: Promise<{ token: string; id: string }> }): Promise<Response> {
  try {
    const { token, id } = await context.params;
    return handleScopedMediaAccess(request, token, id, getScopedMediaSource, getMediaSigningSecret());
  } catch {
    return new Response(JSON.stringify({ error: { code: "PROVIDER_UNAVAILABLE", message: "Media xidməti hazırda əlçatan deyil.", request_id: crypto.randomUUID() } }),
      { status: 503, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "private, no-store", "Referrer-Policy": "no-referrer", "X-Robots-Tag": "noindex, nofollow" } });
  }
}
