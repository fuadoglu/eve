import { requireActiveSession } from "../identity/session-handlers.ts";
import { SessionRateLimitError, SessionUnauthorizedError, type SessionProvider } from "../identity/session-contract.ts";
import { MediaValidationError } from "./media-validation.ts";
import {
  MediaFinalizeConflictError,
  MediaFinalizeNotFoundError,
  MediaFinalizeUnavailableError,
  type MediaFinalizeResult,
} from "./supabase-media-finalizer.ts";

export type MediaFinalizeOperation = (input: {
  actorUserId: string;
  mediaId: string;
  idempotencyKey: string;
}) => Promise<MediaFinalizeResult>;

export async function handleMediaFinalize(
  request: Request,
  mediaId: string,
  sessionProvider: SessionProvider,
  finalize: MediaFinalizeOperation,
): Promise<Response> {
  if (!isUuid(mediaId)) return errorResponse(400, "VALIDATION_ERROR", "Fayl identifikatoru düzgün deyil.");
  const bodyResult = await parseEmptyJson(request);
  if (!bodyResult.ok) {
    if (bodyResult.status === 403) return errorResponse(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
    return errorResponse(bodyResult.status, "VALIDATION_ERROR", "Sorğu forması düzgün deyil.");
  }
  const idempotencyKey = request.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(idempotencyKey)) {
    return errorResponse(400, "VALIDATION_ERROR", "Təkrar sorğu açarı düzgün deyil.");
  }

  try {
    const actorUserId = await requireActiveSession(sessionProvider);
    const data = await finalize({ actorUserId, mediaId, idempotencyKey });
    return jsonResponse(200, { data, meta: { request_id: crypto.randomUUID() } });
  } catch (error) {
    if (error instanceof SessionUnauthorizedError) return errorResponse(401, "UNAUTHENTICATED", "Sessiya yoxdur, bitib və ya ləğv edilib.");
    if (error instanceof SessionRateLimitError) return errorResponse(429, "RATE_LIMITED", "Bir az gözləyib yenidən cəhd edin.", error.retryAfterSeconds);
    if (error instanceof MediaValidationError) return errorResponse(422, "VALIDATION_ERROR", "Fayl növü, ölçüsü və ya müddəti qəbul edilmir.");
    if (error instanceof MediaFinalizeNotFoundError) return errorResponse(404, "NOT_FOUND", "Fayl tapılmadı və ya bu əməliyyata giriş yoxdur.");
    if (error instanceof MediaFinalizeConflictError) return errorResponse(409, "CONFLICT", "Sorğu açarı başqa fayl məlumatı ilə istifadə edilib.");
    if (error instanceof MediaFinalizeUnavailableError) return errorResponse(503, "PROVIDER_UNAVAILABLE", "Media xidməti hazırda əlçatan deyil.");
    return errorResponse(503, "PROVIDER_UNAVAILABLE", "Media xidməti hazırda əlçatan deyil.");
  }
}

async function parseEmptyJson(request: Request): Promise<{ ok: true } | { ok: false; status: 400 | 403 | 422 }> {
  const origin = request.headers.get("origin");
  if (origin === null) return { ok: false, status: 403 };
  try {
    if (new URL(origin).origin !== new URL(request.url).origin) return { ok: false, status: 403 };
  } catch { return { ok: false, status: 403 }; }
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
    return { ok: false, status: 400 };
  }
  let body: unknown;
  try { body = await request.json(); } catch { return { ok: false, status: 400 }; }
  if (!isRecord(body) || Object.keys(body).length !== 0) return { ok: false, status: 422 };
  return { ok: true };
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function errorResponse(status: number, code: string, message: string, retryAfterSeconds?: number): Response {
  const headers = privateHeaders();
  if (retryAfterSeconds !== undefined) headers.set("Retry-After", String(retryAfterSeconds));
  return new Response(JSON.stringify({ error: { code, message, request_id: crypto.randomUUID() } }), { status, headers });
}

function jsonResponse(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), { status, headers: privateHeaders() });
}

function privateHeaders(): Headers {
  return new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "private, no-store",
    "Referrer-Policy": "no-referrer",
    "X-Robots-Tag": "noindex, nofollow",
  });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
