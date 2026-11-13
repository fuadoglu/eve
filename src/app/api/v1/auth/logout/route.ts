import { handleCurrentSessionLogout } from "../../../../../modules/identity/session-handlers.ts";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(request: Request): Promise<Response> {
  return handleCurrentSessionLogout(request, async () => {
    const { createSupabaseSessionProvider } = await import("../../../../../modules/identity/supabase-auth-provider.ts");
    return createSupabaseSessionProvider();
  });
}
