import { handleEmailLinkConfirmation } from "../../../../../modules/identity/auth-handlers.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request): Promise<Response> {
  const response = await handleEmailLinkConfirmation(request, async () => {
    const { createSupabaseAuthProvider } = await import("../../../../../modules/identity/supabase-auth-provider.ts");
    return createSupabaseAuthProvider();
  });
  response.headers.set("Cache-Control", "private, no-store");
  response.headers.set("Referrer-Policy", "no-referrer");
  response.headers.set("X-Robots-Tag", "noindex, nofollow");
  return response;
}
