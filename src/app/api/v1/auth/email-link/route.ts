import { getAppBaseUrl } from "../../../../../lib/env/supabase-public.ts";
import { handleEmailLinkRequest } from "../../../../../modules/identity/auth-handlers.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request): Promise<Response> {
  let confirmationUrl: string;
  try {
    const { url } = getAppBaseUrl();
    confirmationUrl = new URL("/auth/confirm?redirect_path=%2Ftoday", url).toString();
  } catch {
    return Response.json(
      { error: { code: "PROVIDER_UNAVAILABLE", message: "Giriş xidməti hazırda əlçatan deyil.", request_id: crypto.randomUUID() } },
      { status: 503, headers: privateResponseHeaders() },
    );
  }

  const response = await handleEmailLinkRequest(request, async () => {
    const { createSupabaseAuthProvider } = await import("../../../../../modules/identity/supabase-auth-provider.ts");
    return createSupabaseAuthProvider();
  }, confirmationUrl);
  applyPrivateHeaders(response);
  return response;
}

function privateResponseHeaders(): HeadersInit {
  return {
    "Cache-Control": "private, no-store",
    "Referrer-Policy": "no-referrer",
    "X-Robots-Tag": "noindex, nofollow",
  };
}

function applyPrivateHeaders(response: Response): void {
  response.headers.set("Cache-Control", "private, no-store");
  response.headers.set("Referrer-Policy", "no-referrer");
  response.headers.set("X-Robots-Tag", "noindex, nofollow");
}
