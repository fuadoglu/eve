import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import { isDateTime, isUuid, parseRentEntry, type RentEntry } from "./rent-entry-contract.ts";
import { RentEntryApiError } from "./rent-entry-api-error.ts";

type ApiClient = {
  auth: { getUser(): Promise<{ data: { user: { id: string } | null }; error: { status?: number; name?: string } | null }> };
  schema(name: "api"): { rpc(name: string, args?: Record<string, unknown>): Promise<{ data: unknown; error: { code?: string } | null }> };
};

export async function createRentEntry(reservationId: string, input: unknown, idempotencyKey: string): Promise<unknown> {
  const client = await getApiClient();
  await requireActiveActor(client);
  const result = await callRpc(client, "create_rent_entry", {
    p_reservation_id: reservationId, p_input: input, p_idempotency_key: idempotencyKey,
  });
  const entry = parseRentEntry(stripOptionalNulls(result));
  if (!entry) throw new RentEntryApiError("PROVIDER_UNAVAILABLE");
  return entry;
}

export async function listRentEntries(reservationId: string, cursor: string | null, limit: number): Promise<unknown> {
  const client = await getApiClient();
  await requireActiveActor(client);
  const after = cursor ? decodeCursor(cursor) : null;
  const result = await callRpc(client, "list_reservation_rent_entries", {
    p_reservation_id: reservationId, p_after_at: after?.occurred_at ?? null,
    p_after_id: after?.id ?? null, p_page_size: limit + 1,
  });
  if (!Array.isArray(result)) throw new RentEntryApiError("PROVIDER_UNAVAILABLE");
  const rows = result.map((value) => parseRentEntry(stripOptionalNulls(value)));
  if (rows.some((entry) => entry === null)) throw new RentEntryApiError("PROVIDER_UNAVAILABLE");
  const entries = rows as RentEntry[];
  const hasMore = entries.length > limit;
  const items = entries.slice(0, limit);
  return { items, next_cursor: hasMore ? encodeCursor(items[items.length - 1]!) : null };
}

function encodeCursor(entry: RentEntry): string {
  return Buffer.from(JSON.stringify([entry.occurred_at, entry.id]), "utf8").toString("base64url");
}
function stripOptionalNulls(value: unknown): unknown {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return value;
  const row = { ...(value as Record<string, unknown>) };
  for (const key of ["contact_id", "original_id", "note"]) if (row[key] === null) delete row[key];
  return row;
}
function decodeCursor(value: string): { occurred_at: string; id: string } {
  try {
    const decoded: unknown = JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
    if (!Array.isArray(decoded) || decoded.length !== 2 || !isDateTime(decoded[0]) || !isUuid(decoded[1])) throw new Error();
    return { occurred_at: decoded[0], id: decoded[1] };
  } catch { throw new RentEntryApiError("VALIDATION_ERROR"); }
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
  let userResult;
  try { userResult = await client.auth.getUser(); } catch { throw new RentEntryApiError("PROVIDER_UNAVAILABLE"); }
  if (userResult.error) {
    if ([401, 403].includes(userResult.error.status ?? 0) || userResult.error.name === "AuthSessionMissingError") throw new RentEntryApiError("UNAUTHENTICATED");
    throw new RentEntryApiError("PROVIDER_UNAVAILABLE");
  }
  if (!userResult.data.user) throw new RentEntryApiError("UNAUTHENTICATED");
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
