import "server-only";

import { createServerClient } from "@supabase/ssr";
import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import { getSupabaseSecretKey } from "../../lib/env/supabase-server.ts";
import { TaskLinkApiError } from "./task-link-http.ts";
import { deriveTaskLinkToken, sha256 } from "./task-link-token.ts";

type RpcError = { code?: string } | null;
type ApiClient = { schema(name: "api"): { rpc(name: string, args?: Record<string, unknown>): Promise<{ data: unknown; error: RpcError }> } };
type UserClient = ApiClient & { auth: {
  getUser(): Promise<{ data: { user: { id: string } | null }; error: { status?: number } | null }>;
  getSession(): Promise<{ data: { session: { access_token: string } | null }; error: { status?: number } | null }>;
} };

export async function createTaskShareLink(taskId: string, expiresAt: string | null, key: string): Promise<unknown> {
  const { actorId, sessionId } = await authenticatedClient();
  const canonicalTaskId = taskId.toLowerCase();
  const token = deriveToken(actorId.toLowerCase(), canonicalTaskId, key);
  const hash = sha256(token);
  const requestHash = sha256(JSON.stringify({ task_id: canonicalTaskId, expires_at: expiresAt }));
  const result = await rpc(serverClient(), "create_task_link", {
    p_actor_user_id: actorId, p_session_id: sessionId,
    p_task_id: canonicalTaskId, p_token_hash: hash,
    p_idempotency_key_hash: sha256(key), p_request_hash: requestHash,
    p_expires_at: expiresAt,
  });
  if (!isRecord(result) || !isUuid(result.link_id) || typeof result.expires_at !== "string"
    || !Number.isFinite(Date.parse(result.expires_at)) || typeof result.replayed !== "boolean") {
    throw new TaskLinkApiError("PROVIDER_UNAVAILABLE");
  }
  return { ...result, token };
}

export async function revokeTaskShareLink(linkId: string): Promise<unknown> {
  const { actorId, sessionId } = await authenticatedClient();
  const result = await rpc(serverClient(), "revoke_task_link", {
    p_actor_user_id: actorId, p_session_id: sessionId, p_link_id: linkId,
  });
  if (!isRecord(result) || result.accepted !== true) throw new TaskLinkApiError("PROVIDER_UNAVAILABLE");
  return result;
}

export async function readScopedTask(tokenHash: string): Promise<unknown> {
  return rpc(serverClient(), "read_scoped_task_for_server", { p_link_token_hash: tokenHash });
}

export async function transitionScopedTask(tokenHash: string, input: {
  expected_version: number; action: "accept" | "report_done"; claimed_name: string;
  note?: string; media_ids?: string[];
}, key: string): Promise<unknown> {
  return rpc(serverClient(), "transition_scoped_task_for_server", {
    p_link_token_hash: tokenHash,p_expected_version: input.expected_version,
    p_action: input.action,p_idempotency_key: key,p_claimed_name: input.claimed_name,
    p_note: input.note ?? null,p_media_ids: input.media_ids ?? [],
  });
}

async function authenticatedClient(): Promise<{ actorId: string; sessionId: string }> {
  const { url, publishableKey } = getSupabasePublicConfig();
  const jar = await cookies();
  const secure = process.env.NODE_ENV === "production";
  const client = createServerClient(url, publishableKey, {
    auth: { flowType: "pkce", detectSessionInUrl: false, persistSession: true, autoRefreshToken: false },
    cookieOptions: { path: "/", sameSite: "lax", secure, httpOnly: true },
    cookies: { getAll: () => jar.getAll(), setAll: (items) => {
      for (const { name, value, options } of items) jar.set(name, value, { ...options, path: "/", sameSite: "lax", secure, httpOnly: true });
    } },
  }) as unknown as UserClient;
  let user;
  try { user = await client.auth.getUser(); } catch { throw new TaskLinkApiError("PROVIDER_UNAVAILABLE"); }
  if (user.error || !user.data.user) throw new TaskLinkApiError("UNAUTHENTICATED");
  if (await rpc(client, "is_my_session_active") !== true) throw new TaskLinkApiError("UNAUTHENTICATED");
  let session;
  try { session = await client.auth.getSession(); } catch { throw new TaskLinkApiError("PROVIDER_UNAVAILABLE"); }
  if (session.error || !session.data.session) throw new TaskLinkApiError("UNAUTHENTICATED");
  const sessionId = sessionIdFromJwt(session.data.session.access_token, user.data.user.id);
  if (!sessionId) throw new TaskLinkApiError("UNAUTHENTICATED");
  return { actorId: user.data.user.id, sessionId };
}

function serverClient(): ApiClient {
  const { url } = getSupabasePublicConfig();
  return createClient(url, getSupabaseSecretKey(), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  }) as unknown as ApiClient;
}

async function rpc(client: ApiClient, name: string, args?: Record<string, unknown>): Promise<unknown> {
  let result;
  try { result = await client.schema("api").rpc(name, args); }
  catch { throw new TaskLinkApiError("PROVIDER_UNAVAILABLE"); }
  if (result.error) {
    const code = result.error.code;
    throw new TaskLinkApiError(code === "28000" ? "UNAUTHENTICATED" : code === "42501" ? "FORBIDDEN"
      : code === "P0002" ? "NOT_FOUND" : code === "P4100" ? "LINK_EXPIRED"
        : code === "22023" ? "VALIDATION_ERROR" : ["23505", "40001"].includes(code ?? "") ? "CONFLICT"
          : "PROVIDER_UNAVAILABLE");
  }
  return result.data;
}

function deriveToken(actorId: string, taskId: string, key: string): string {
  const secret = process.env.EVE_SCOPED_LINK_HMAC_KEY;
  if (!secret || !/^[0-9a-f]{64}$/.test(secret)) throw new TaskLinkApiError("PROVIDER_UNAVAILABLE");
  return deriveTaskLinkToken(secret, actorId, taskId, key);
}
function sessionIdFromJwt(jwt: string, actorId: string): string | null {
  if (typeof jwt !== "string" || jwt.length > 10000) return null;
  const parts = jwt.split(".");
  if (parts.length !== 3 || !/^[A-Za-z0-9_-]+$/.test(parts[1])) return null;
  try {
    const claims: unknown = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
    if (!isRecord(claims) || claims.sub !== actorId || claims.role !== "authenticated"
      || !isUuid(claims.session_id)) return null;
    return claims.session_id;
  } catch { return null; }
}
function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
