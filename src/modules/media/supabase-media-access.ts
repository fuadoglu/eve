import "server-only";

import { createClient } from "@supabase/supabase-js";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import { getSupabaseSecretKey } from "../../lib/env/supabase-server.ts";
import { validatePrivateMediaSource, type MediaAccessSource } from "./media-proxy-contract.ts";

type ApiClient = {
  schema(name: "api"): {
    rpc(name: string, args: Record<string, unknown>): Promise<{ data: unknown; error: { code?: string } | null }>;
  };
};

export class MediaAccessNotFoundError extends Error {}
export class MediaAccessExpiredError extends Error {}
export class MediaAccessUnavailableError extends Error {}
export class MediaAccessRateLimitError extends Error {}

export async function getAuthenticatedMediaSource(actorUserId: string, mediaId: string): Promise<MediaAccessSource> {
  const result = await callRpc("get_media_actor_source_for_server", {
    p_actor_user_id: actorUserId, p_media_id: mediaId,
  });
  return parseSource(result, mediaId);
}

export async function getScopedMediaSource(tokenHash: string, mediaId: string): Promise<MediaAccessSource> {
  const result = await callRpc("get_media_scoped_source_for_server", {
    p_link_token_hash: tokenHash, p_media_id: mediaId,
  });
  return parseSource(result, mediaId);
}

export async function exchangeScopedLink(tokenHash: string): Promise<{ resource_type: "task" | "inspection" | "guest_guide"; expires_at: string }> {
  const value = await callRpc("exchange_scoped_link_for_server", { p_link_token_hash: tokenHash });
  if (!isRecord(value) || !["task", "inspection", "guest_guide"].includes(value.resource_type as string)
      || typeof value.expires_at !== "string" || !Number.isFinite(Date.parse(value.expires_at))) {
    throw new MediaAccessUnavailableError();
  }
  return value as { resource_type: "task" | "inspection" | "guest_guide"; expires_at: string };
}

export async function fetchPrivateMedia(source: MediaAccessSource): Promise<Response> {
  const { url } = getSupabasePublicConfig();
  const secret = getSupabaseSecretKey();
  const objectUrl = new URL(`/storage/v1/object/${encodeURIComponent(source.bucket)}/${encodeURIComponent(source.object_key)}`, url);
  let response: Response;
  try {
    response = await fetch(objectUrl, {
      method: "GET", headers: { apikey: secret, Authorization: `Bearer ${secret}` },
      cache: "no-store", redirect: "error",
    });
  } catch { throw new MediaAccessUnavailableError(); }
  if (response.status === 404) throw new MediaAccessNotFoundError();
  if (response.status !== 200 || !response.body) {
    try { await response.body?.cancel(); } catch { /* response body may already be closed */ }
    throw new MediaAccessUnavailableError();
  }
  const contentLength = response.headers.get("content-length");
  if (!contentLength || !/^\d+$/.test(contentLength) || Number(contentLength) !== source.size_bytes) {
    try { await response.body.cancel(); } catch { /* fail closed if the upstream body cannot be canceled */ }
    throw new MediaAccessUnavailableError();
  }
  return response;
}

export function getMediaSigningSecret(): string {
  return getSupabaseSecretKey();
}

function parseSource(value: unknown, expectedId: string): MediaAccessSource {
  if (!validatePrivateMediaSource(value, expectedId)) throw new MediaAccessNotFoundError();
  return value;
}

async function callRpc(name: string, args: Record<string, unknown>): Promise<unknown> {
  let result: { data: unknown; error: { code?: string } | null };
  try { result = await getApiClient().schema("api").rpc(name, args); }
  catch { throw new MediaAccessUnavailableError(); }
  if (result.error) {
    if (["P0002", "42501"].includes(result.error.code ?? "")) throw new MediaAccessNotFoundError();
    if (result.error.code === "P4100") throw new MediaAccessExpiredError();
    if (result.error.code === "PGR01") throw new MediaAccessRateLimitError();
    throw new MediaAccessUnavailableError();
  }
  return result.data;
}

function getApiClient(): ApiClient {
  const { url } = getSupabasePublicConfig();
  return createClient(url, getSupabaseSecretKey(), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  }) as unknown as ApiClient;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
