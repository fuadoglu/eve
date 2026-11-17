import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import { parseRealtorBalance, parseRealtorSettlement } from "./realtor-settlement-contract.ts";
import { RentEntryApiError } from "./rent-entry-api-error.ts";

type ApiClient = {
  auth: { getUser(): Promise<{ data: { user: { id: string } | null }; error: { status?: number; name?: string } | null }> };
  schema(name: "api"): { rpc(name: string, args?: Record<string, unknown>): Promise<{ data: unknown; error: { code?: string } | null }> };
};

export async function getRealtorBalance(reservationId: string): Promise<unknown> {
  const client = await getApiClient();
  await requireActiveActor(client);
  const result = await callRpc(client, "get_realtor_balance", { p_reservation_id: reservationId });
  const balance = parseRealtorBalance(stripOptionalNulls(result));
  if (!balance) throw new RentEntryApiError("PROVIDER_UNAVAILABLE");
  return balance;
}

export async function recordRealtorSettlement(reservationId: string, input: unknown, key: string): Promise<unknown> {
  const client = await getApiClient();
  await requireActiveActor(client);
  const result = await callRpc(client, "record_realtor_settlement", {
    p_reservation_id: reservationId, p_input: input, p_idempotency_key: key,
  });
  const settlement = parseRealtorSettlement(stripOptionalNulls(result));
  if (!settlement) throw new RentEntryApiError("PROVIDER_UNAVAILABLE");
  return settlement;
}

function stripOptionalNulls(value: unknown): unknown {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return value;
  const row = { ...(value as Record<string, unknown>) };
  for (const key of ["contact_id"]) if (row[key] === null) delete row[key];
  return row;
}
async function getApiClient(): Promise<ApiClient> {
  const { url, publishableKey } = getSupabasePublicConfig();
  const cookieStore = await cookies();
  const secureCookies = process.env.NODE_ENV === "production";
  return createServerClient(url, publishableKey, {
    auth: { flowType: "pkce", detectSessionInUrl: false, persistSession: true, autoRefreshToken: false },
    cookieOptions: { path: "/", sameSite: "lax", secure: secureCookies, httpOnly: true },
    cookies: { getAll: () => cookieStore.getAll(), setAll: (items) => {
      for (const { name, value, options } of items) cookieStore.set(name, value, { ...options, path: "/", sameSite: "lax", secure: secureCookies, httpOnly: true });
    } },
  }) as unknown as ApiClient;
}
async function requireActiveActor(client: ApiClient): Promise<void> {
  let result;
  try { result = await client.auth.getUser(); } catch { throw new RentEntryApiError("PROVIDER_UNAVAILABLE"); }
  if (result.error) {
    if ([401, 403].includes(result.error.status ?? 0) || result.error.name === "AuthSessionMissingError") throw new RentEntryApiError("UNAUTHENTICATED");
    throw new RentEntryApiError("PROVIDER_UNAVAILABLE");
  }
  if (!result.data.user) throw new RentEntryApiError("UNAUTHENTICATED");
  const active = await callRpc(client, "is_my_session_active");
  if (active !== true) throw new RentEntryApiError("UNAUTHENTICATED");
}
async function callRpc(client: ApiClient, name: string, args?: Record<string, unknown>): Promise<unknown> {
  let result;
  try { result = await client.schema("api").rpc(name, args); } catch { throw new RentEntryApiError("PROVIDER_UNAVAILABLE"); }
  if (result.error) {
    const code = result.error.code;
    if (code === "28000") throw new RentEntryApiError("UNAUTHENTICATED");
    if (code === "42501") throw new RentEntryApiError("FORBIDDEN");
    if (code === "P0002") throw new RentEntryApiError("NOT_FOUND");
    if (code === "22023") throw new RentEntryApiError("VALIDATION_ERROR");
    if (["23505", "40001"].includes(code ?? "")) throw new RentEntryApiError("CONFLICT");
    throw new RentEntryApiError("PROVIDER_UNAVAILABLE");
  }
  return result.data;
}
