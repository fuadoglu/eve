import "server-only";
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import type { ReservationWriteOperation } from "./reservation-at10-http.ts";

type Client = {
  auth: { getUser(): Promise<{ data: { user: { id: string } | null }; error: { status?: number; name?: string } | null }> };
  schema(name: "api"): { rpc(name: string, args?: Record<string, unknown>): Promise<{ data: unknown; error: { code?: string } | null }> };
};
class ApiError extends Error { constructor(readonly code: string) { super(code); } }

export const patchReservation: ReservationWriteOperation = (id, input, key) => writeReservation("patch_reservation", id, input, key);
export const transitionReservation: ReservationWriteOperation = (id, input, key) => writeReservation("transition_reservation", id, input, key);

export async function getReservation(id: string): Promise<unknown> {
  const client = await getClient();
  await requireActiveSession(client);
  return rpc(client, "get_reservation", { p_reservation_id: id });
}

async function writeReservation(operation: "patch_reservation" | "transition_reservation", id: string, input: unknown, key: string): Promise<unknown> {
  const client = await getClient();
  await requireActiveSession(client);
  const ack = await rpc(client, operation, { p_reservation_id: id, p_input: input, p_idempotency_key: key });
  if (!isRecord(ack) || Object.keys(ack).some((field) => !["reservation_id", "version", "replayed"].includes(field))
      || ack.reservation_id !== id || !isPositiveInteger(ack.version) || typeof ack.replayed !== "boolean") {
    throw new ApiError("PROVIDER_UNAVAILABLE");
  }
  return rpc(client, "get_reservation", { p_reservation_id: id });
}

async function getClient(): Promise<Client> {
  const { url, publishableKey } = getSupabasePublicConfig();
  const jar = await cookies();
  const secure = process.env.NODE_ENV === "production";
  return createServerClient(url, publishableKey, {
    auth: { flowType: "pkce", detectSessionInUrl: false, persistSession: true, autoRefreshToken: false },
    cookieOptions: { path: "/", sameSite: "lax", secure, httpOnly: true },
    cookies: { getAll: () => jar.getAll(), setAll: (items) => { for (const { name, value, options } of items) jar.set(name, value, { ...options, path: "/", sameSite: "lax", secure, httpOnly: true }); } },
  }) as unknown as Client;
}
async function requireActiveSession(client: Client): Promise<void> {
  let result;
  try { result = await client.auth.getUser(); } catch { throw new ApiError("PROVIDER_UNAVAILABLE"); }
  if (result.error) {
    if ([401, 403].includes(result.error.status ?? 0) || result.error.name === "AuthSessionMissingError") throw new ApiError("UNAUTHENTICATED");
    throw new ApiError("PROVIDER_UNAVAILABLE");
  }
  if (!result.data.user) throw new ApiError("UNAUTHENTICATED");
  if (await rpc(client, "is_my_session_active") !== true) throw new ApiError("UNAUTHENTICATED");
}
async function rpc(client: Client, name: string, args?: Record<string, unknown>): Promise<unknown> {
  let result;
  try { result = await client.schema("api").rpc(name, args); } catch { throw new ApiError("PROVIDER_UNAVAILABLE"); }
  if (result.error) {
    const code = result.error.code;
    throw new ApiError(code === "28000" ? "UNAUTHENTICATED" : code === "42501" ? "FORBIDDEN" : code === "P0002" ? "NOT_FOUND"
      : code === "22023" ? "VALIDATION_ERROR" : ["23505", "23P01", "40001"].includes(code ?? "") ? "CONFLICT" : "PROVIDER_UNAVAILABLE");
  }
  return result.data;
}
function isRecord(v: unknown): v is Record<string, unknown> { return typeof v === "object" && v !== null && !Array.isArray(v); }
function isPositiveInteger(v: unknown): v is number { return typeof v === "number" && Number.isSafeInteger(v) && v > 0; }
