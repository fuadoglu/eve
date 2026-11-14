import "server-only";

import { createClient } from "@supabase/supabase-js";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import { getSupabaseSecretKey } from "../../lib/env/supabase-server.ts";
import { MediaValidationError, validateMediaBytes, type MediaKind, type ValidatedMedia } from "./media-validation.ts";

export type MediaFinalizeResult = {
  id: string;
  property_id: string;
  kind: MediaKind;
  classification: string;
  status: "validated";
  size_bytes: number;
  version: number;
  created_at: string;
  updated_at: string;
};

type PendingMediaSource = {
  id: string;
  classification: string;
  bucket: string;
  object_key: string;
  mime: string;
  max_size_bytes: number;
  duration_seconds: number | null;
};

type ApiClient = {
  schema(name: "api"): {
    rpc(name: string, args: Record<string, unknown>): Promise<{ data: unknown; error: { code?: string } | null }>;
  };
  storage: {
    from(bucket: string): {
      download(path: string): Promise<{ data: Blob | null; error: { statusCode?: string } | null }>;
    };
  };
};

export class MediaFinalizeNotFoundError extends Error {}
export class MediaFinalizeConflictError extends Error {}
export class MediaFinalizeUnavailableError extends Error {}

export async function finalizeMediaUpload(input: {
  actorUserId: string;
  mediaId: string;
  idempotencyKey: string;
}): Promise<MediaFinalizeResult> {
  const source = await loadPendingSource(input.actorUserId, input.mediaId);
  const client = getApiClient();
  let downloaded: { data: Blob | null; error: { statusCode?: string } | null };
  try {
    downloaded = await client.storage.from(source.bucket).download(source.object_key);
  } catch {
    throw new MediaFinalizeUnavailableError();
  }
  if (downloaded.error || !downloaded.data) {
    if (downloaded.error?.statusCode === "404" || !downloaded.error && !downloaded.data) {
      throw new MediaFinalizeNotFoundError();
    }
    throw new MediaFinalizeUnavailableError();
  }
  if (downloaded.data.size > source.max_size_bytes) throw new MediaValidationError("size_limit");

  let bytes: Uint8Array;
  try { bytes = new Uint8Array(await downloaded.data.arrayBuffer()); }
  catch { throw new MediaFinalizeUnavailableError(); }
  const kind = kindForMime(source.mime);
  let verified: ValidatedMedia;
  try {
    verified = validateMediaBytes({
      kind,
      declaredMime: source.mime,
      maxSizeBytes: source.max_size_bytes,
      declaredDurationSeconds: source.duration_seconds,
      bytes,
    });
  } catch (error) {
    if (error instanceof MediaValidationError) throw error;
    throw new MediaFinalizeUnavailableError();
  }

  let result: { data: unknown; error: { code?: string } | null };
  try {
    result = await client.schema("api").rpc("finalize_media_upload_for_server", {
      p_actor_user_id: input.actorUserId,
      p_media_id: input.mediaId,
      p_mime: verified.mime,
      p_size_bytes: verified.sizeBytes,
      p_duration_seconds: verified.durationSeconds === null ? null : Math.ceil(verified.durationSeconds),
      p_sha256: verified.sha256,
      p_idempotency_key: input.idempotencyKey,
    });
  } catch {
    throw new MediaFinalizeUnavailableError();
  }
  if (result.error) {
    if (result.error.code === "23505") throw new MediaFinalizeConflictError();
    if (["42501", "P0002", "55000", "22003"].includes(result.error.code ?? "")) {
      throw new MediaFinalizeNotFoundError();
    }
    throw new MediaFinalizeUnavailableError();
  }
  if (!isMediaFinalizeResult(result.data)) throw new MediaFinalizeUnavailableError();
  return result.data;
}

async function loadPendingSource(actorUserId: string, mediaId: string): Promise<PendingMediaSource> {
  const client = getApiClient();
  let result: { data: unknown; error: { code?: string } | null };
  try {
    result = await client.schema("api").rpc("get_media_finalize_source_for_server", {
      p_actor_user_id: actorUserId,
      p_media_id: mediaId,
    });
  } catch {
    throw new MediaFinalizeUnavailableError();
  }
  if (result.error) {
    if (["42501", "P0002"].includes(result.error.code ?? "")) throw new MediaFinalizeNotFoundError();
    throw new MediaFinalizeUnavailableError();
  }
  if (!isPendingMediaSource(result.data, mediaId)) throw new MediaFinalizeNotFoundError();
  return result.data;
}

function getApiClient(): ApiClient {
  const { url } = getSupabasePublicConfig();
  return createClient(url, getSupabaseSecretKey(), {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  }) as unknown as ApiClient;
}

function kindForMime(mime: string): MediaKind {
  if (mime.startsWith("image/")) return "image";
  if (mime === "video/mp4") return "video";
  if (mime === "audio/mp4" || mime === "audio/webm") return "audio";
  if (mime === "application/pdf") return "document";
  throw new MediaValidationError("mime_mismatch");
}

function isPendingMediaSource(value: unknown, expectedId: string): value is PendingMediaSource {
  if (!isRecord(value)) return false;
  const buckets: Record<string, string> = {
    public_property: "eve-public-property", public_guide: "eve-public-guide",
    private_guest: "eve-private-guest", private_receipt: "eve-private-receipt",
    private_inspection: "eve-private-inspection", private_task: "eve-private-task",
    private_inventory: "eve-private-inventory",
  };
  return value.id === expectedId && typeof value.classification === "string"
    && buckets[value.classification] === value.bucket && isAllowedBucket(value.bucket)
    && value.object_key === expectedId
    && ["image/jpeg", "image/png", "image/webp", "video/mp4", "audio/webm", "audio/mp4", "application/pdf"].includes(value.mime as string)
    && Number.isSafeInteger(value.max_size_bytes) && Number(value.max_size_bytes) > 0
    && Number(value.max_size_bytes) <= 104857600
    && (value.duration_seconds === null || Number.isSafeInteger(value.duration_seconds));
}

function isMediaFinalizeResult(value: unknown): value is MediaFinalizeResult {
  if (!isRecord(value)) return false;
  return typeof value.id === "string" && typeof value.property_id === "string"
    && ["image", "video", "audio", "document"].includes(value.kind as string)
    && typeof value.classification === "string" && value.status === "validated"
    && Number.isSafeInteger(value.size_bytes) && Number.isSafeInteger(value.version)
    && typeof value.created_at === "string" && typeof value.updated_at === "string";
}

function isAllowedBucket(bucket: unknown): bucket is string {
  return typeof bucket === "string" && [
    "eve-public-property", "eve-public-guide", "eve-private-guest", "eve-private-receipt",
    "eve-private-inspection", "eve-private-task", "eve-private-inventory",
  ].includes(bucket);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
