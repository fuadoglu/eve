import { handleMediaFinalize } from "../../../../../../modules/media/media-handlers.ts";
import { finalizeMediaUpload } from "../../../../../../modules/media/supabase-media-finalizer.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request, context: { params: Promise<{ id: string }> }): Promise<Response> {
  const { id } = await context.params;
  try {
    const { createSupabaseSessionProvider } = await import("../../../../../../modules/identity/supabase-auth-provider.ts");
    const session = await createSupabaseSessionProvider();
    return handleMediaFinalize(request, id, session, finalizeMediaUpload);
  } catch {
    return new Response(JSON.stringify({
      error: { code: "PROVIDER_UNAVAILABLE", message: "Media xidməti hazırda əlçatan deyil.", request_id: crypto.randomUUID() },
    }), { status: 503, headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "private, no-store",
      "Referrer-Policy": "no-referrer",
      "X-Robots-Tag": "noindex, nofollow",
    } });
  }
}
