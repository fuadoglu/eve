import { handleMediaAccess } from "@/modules/media/media-access-handlers.ts";
import { getAuthenticatedMediaSource, getMediaSigningSecret } from "@/modules/media/supabase-media-access.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: Request, context: { params: Promise<{ id: string }> }): Promise<Response> {
  try {
    const [{ id }, { createSupabaseSessionProvider }] = await Promise.all([
      context.params, import("@/modules/identity/supabase-auth-provider.ts"),
    ]);
    return handleMediaAccess(request, id, await createSupabaseSessionProvider(), getAuthenticatedMediaSource, getMediaSigningSecret());
  } catch {
    return unavailable();
  }
}

function unavailable(): Response {
  return new Response(JSON.stringify({ error: { code: "PROVIDER_UNAVAILABLE", message: "Media xidməti hazırda əlçatan deyil.", request_id: crypto.randomUUID() } }),
    { status: 503, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "private, no-store", "Referrer-Policy": "no-referrer", "X-Robots-Tag": "noindex, nofollow" } });
}
