import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import type { ReservationPropertyContext } from "./reservation-contract.ts";

type ApiClient = {
  auth: { getUser(): Promise<{ data: { user: { id: string } | null }; error: { status?: number; name?: string } | null }> };
  schema(name: "api"): {
    rpc(name: string, args?: Record<string, unknown>): Promise<{ data: unknown; error: { code?: string } | null }>;
  };
};

export class ReservationApiError extends Error {
  constructor(readonly code: string) { super(code); }
}

export async function createReservation(input: unknown, idempotencyKey: string): Promise<unknown> {
  const client = await getApiClient();
  await requireActiveActor(client);
  const created = await callRpc(client, "create_reservation", {
    p_input: input,
    p_idempotency_key: idempotencyKey,
  });
  if (!isRecord(created) || typeof created.reservation_id !== "string") {
    throw new ReservationApiError("PROVIDER_UNAVAILABLE");
  }
  return callRpc(client, "get_reservation", { p_reservation_id: created.reservation_id });
}

export async function listReservableProperties(): Promise<Array<ReservationPropertyContext & { default_custodian: "owner" | "manager" }>> {
  const client = await getApiClient();
  await requireActiveActor(client);
  const data = await callRpc(client, "list_reservable_property_contexts");
  if (!Array.isArray(data)) throw new ReservationApiError("PROVIDER_UNAVAILABLE");
  return data.flatMap((value) => {
    if (!isRecord(value) || !isUuid(value.id) || typeof value.name !== "string"
        || !Number.isSafeInteger(value.max_guests) || Number(value.max_guests) < 1
        || !isLocalTime(value.default_check_in) || !isLocalTime(value.default_check_out)
        || !["owner", "manager"].includes(String(value.default_custodian))) return [];
    return [{
      id: value.id,
      name: value.name,
      max_guests: Number(value.max_guests),
      default_check_in: value.default_check_in,
      default_check_out: value.default_check_out,
      default_custodian: value.default_custodian as "owner" | "manager",
    }];
  });
}

async function getApiClient(): Promise<ApiClient> {
  const { url, publishableKey } = getSupabasePublicConfig();
  const cookieStore = await cookies();
  const secureCookies = process.env.NODE_ENV === "production";
  return createServerClient(url, publishableKey, {
    auth: { flowType: "pkce", detectSessionInUrl: false, persistSession: true, autoRefreshToken: false },
    cookieOptions: { path: "/", sameSite: "lax", secure: secureCookies, httpOnly: true },
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (items) => {
        for (const { name, value, options } of items) {
          cookieStore.set(name, value, { ...options, path: "/", sameSite: "lax", secure: secureCookies, httpOnly: true });
        }
      },
    },
  }) as unknown as ApiClient;
}

async function requireActiveActor(client: ApiClient): Promise<void> {
  let userResult;
  try { userResult = await client.auth.getUser(); }
  catch { throw new ReservationApiError("PROVIDER_UNAVAILABLE"); }
  if (userResult.error) {
    if ([401, 403].includes(userResult.error.status ?? 0) || userResult.error.name === "AuthSessionMissingError") {
      throw new ReservationApiError("UNAUTHENTICATED");
    }
    throw new ReservationApiError("PROVIDER_UNAVAILABLE");
  }
  if (!userResult.data.user) throw new ReservationApiError("UNAUTHENTICATED");
  const active = await callRpc(client, "is_my_session_active");
  if (active !== true) throw new ReservationApiError("UNAUTHENTICATED");
}

async function callRpc(client: ApiClient, name: string, args?: Record<string, unknown>): Promise<unknown> {
  let result;
  try { result = await client.schema("api").rpc(name, args); }
  catch { throw new ReservationApiError("PROVIDER_UNAVAILABLE"); }
  if (result.error) {
    const status = result.error.code === "28000" ? "UNAUTHENTICATED"
      : ["42501"].includes(result.error.code ?? "") ? "FORBIDDEN"
        : ["P0002"].includes(result.error.code ?? "") ? "NOT_FOUND"
          : ["22023"].includes(result.error.code ?? "") ? "VALIDATION_ERROR"
            : ["23505", "23P01", "40001"].includes(result.error.code ?? "") ? "CONFLICT"
              : "PROVIDER_UNAVAILABLE";
    throw new ReservationApiError(status);
  }
  return result.data;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
function isLocalTime(value: unknown): value is string { return typeof value === "string" && /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value); }
