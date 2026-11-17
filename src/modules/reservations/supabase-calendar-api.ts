import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabasePublicConfig } from "@/lib/env/supabase-public.ts";
import type { CalendarPropertyOption } from "./calendar-contract.ts";

type ApiClient = {
  auth: { getUser(): Promise<{ data: { user: { id: string } | null }; error: { status?: number; name?: string } | null }> };
  schema(name: "api"): { rpc(name: string, args?: Record<string, unknown>): Promise<{ data: unknown; error: { code?: string } | null }> };
};

export class CalendarApiError extends Error {
  constructor(readonly code: string) { super(code); }
}

export async function getCalendar(input: { from: string; to: string; propertyIds: string[] }): Promise<unknown> {
  const client = await getApiClient();
  await requireActiveActor(client);
  return callRpc(client, "get_calendar", {
    p_from: input.from,
    p_to: input.to,
    p_property_ids: input.propertyIds,
  });
}

export async function listCalendarPropertyOptions(): Promise<CalendarPropertyOption[]> {
  const client = await getApiClient();
  await requireActiveActor(client);
  const items: CalendarPropertyOption[] = [];
  let afterId: string | null = null;
  for (let page = 0; page < 100; page += 1) {
    const result = await callRpc(client, "list_calendar_property_options", {
      p_after_id: afterId,
      p_page_size: 100,
    });
    if (!Array.isArray(result)) throw new CalendarApiError("PROVIDER_UNAVAILABLE");
    const parsed = result.flatMap((row) => {
      if (!isRecord(row) || !isUuid(row.property_id) || !isUuid(row.owner_account_id)
          || typeof row.owner_display_name !== "string" || row.owner_display_name.length < 1
          || typeof row.name !== "string" || row.name.length < 1
          || typeof row.area !== "string") return [];
      return [{ id: row.property_id, owner_account_id: row.owner_account_id,
        owner_display_name: row.owner_display_name, name: row.name, area: row.area }];
    });
    items.push(...parsed);
    if (result.length < 100) return items;
    const last = result[result.length - 1];
    if (!isRecord(last) || !isUuid(last.property_id) || last.property_id === afterId) {
      throw new CalendarApiError("PROVIDER_UNAVAILABLE");
    }
    afterId = last.property_id;
  }
  throw new CalendarApiError("PROVIDER_UNAVAILABLE");
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
  catch { throw new CalendarApiError("PROVIDER_UNAVAILABLE"); }
  if (userResult.error) {
    if ([401, 403].includes(userResult.error.status ?? 0) || userResult.error.name === "AuthSessionMissingError") {
      throw new CalendarApiError("UNAUTHENTICATED");
    }
    throw new CalendarApiError("PROVIDER_UNAVAILABLE");
  }
  if (!userResult.data.user) throw new CalendarApiError("UNAUTHENTICATED");
  const active = await callRpc(client, "is_my_session_active");
  if (active !== true) throw new CalendarApiError("UNAUTHENTICATED");
}

async function callRpc(client: ApiClient, name: string, args?: Record<string, unknown>): Promise<unknown> {
  let result;
  try { result = await client.schema("api").rpc(name, args); }
  catch { throw new CalendarApiError("PROVIDER_UNAVAILABLE"); }
  if (result.error) {
    const code = result.error.code;
    throw new CalendarApiError(code === "28000" ? "UNAUTHENTICATED"
      : code === "42501" ? "FORBIDDEN"
        : code === "P0002" ? "NOT_FOUND"
          : code === "22023" ? "VALIDATION_ERROR"
            : "PROVIDER_UNAVAILABLE");
  }
  return result.data;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
