import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import { ExpenseProposalError } from "./expense-proposal-error.ts";

type Client = {
  auth: { getUser(): Promise<{ data: { user: { id: string } | null }; error: { status?: number; name?: string } | null }> };
  schema(name: "api"): { rpc(name: string, args?: Record<string, unknown>): Promise<{ data: unknown; error: { code?: string } | null }> };
};

export async function createExpenseProposal(input: unknown, key: string): Promise<unknown> {
  const { url, publishableKey } = getSupabasePublicConfig();
  const store = await cookies();
  const secure = process.env.NODE_ENV === "production";
  const client = createServerClient(url, publishableKey, {
    auth: { flowType: "pkce", detectSessionInUrl: false, persistSession: true, autoRefreshToken: false },
    cookieOptions: { path: "/", sameSite: "lax", secure, httpOnly: true },
    cookies: { getAll: () => store.getAll(), setAll: (items) => {
      for (const { name, value, options } of items) store.set(name, value, { ...options, path: "/", sameSite: "lax", secure, httpOnly: true });
    } },
  }) as unknown as Client;
  let user;
  try { user = await client.auth.getUser(); } catch { throw new ExpenseProposalError("PROVIDER_UNAVAILABLE"); }
  if (user.error || !user.data.user) throw new ExpenseProposalError("UNAUTHENTICATED");
  const active = await rpc(client, "is_my_session_active");
  if (active !== true) throw new ExpenseProposalError("UNAUTHENTICATED");
  return rpc(client, "create_expense_proposal", { p_input: input, p_idempotency_key: key });
}

async function rpc(client: Client, name: string, args?: Record<string, unknown>): Promise<unknown> {
  let result;
  try { result = await client.schema("api").rpc(name, args); } catch { throw new ExpenseProposalError("PROVIDER_UNAVAILABLE"); }
  if (result.error) {
    const code = result.error.code;
    if (code === "28000") throw new ExpenseProposalError("UNAUTHENTICATED");
    if (code === "42501") throw new ExpenseProposalError("FORBIDDEN");
    if (code === "P0002") throw new ExpenseProposalError("NOT_FOUND");
    if (["22023", "23514"].includes(code ?? "")) throw new ExpenseProposalError("VALIDATION_ERROR");
    if (["23505", "40001"].includes(code ?? "")) throw new ExpenseProposalError("CONFLICT");
    throw new ExpenseProposalError("PROVIDER_UNAVAILABLE");
  }
  return result.data;
}
