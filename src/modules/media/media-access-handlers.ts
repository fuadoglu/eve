import { requireActiveSession } from "../identity/session-handlers.ts";
import { SessionRateLimitError, SessionUnauthorizedError, type SessionProvider } from "../identity/session-contract.ts";
import {
  createMediaProxyUrl, hashScopedLinkToken, verifyMediaProxySignature,
  type MediaAccessSource,
} from "./media-proxy-contract.ts";
import {
  MediaAccessExpiredError, MediaAccessNotFoundError, MediaAccessRateLimitError, MediaAccessUnavailableError,
} from "./supabase-media-access.ts";

type ResolveActorSource = (actorId: string, mediaId: string) => Promise<MediaAccessSource>;
type ResolveScopedSource = (tokenHash: string, mediaId: string) => Promise<MediaAccessSource>;
type ExchangeToken = (tokenHash: string) => Promise<{ resource_type: "task" | "inspection" | "guest_guide"; expires_at: string }>;
type FetchObject = (source: MediaAccessSource) => Promise<Response>;

export async function handleMediaAccess(request: Request, mediaId: string, session: SessionProvider,
  resolve: ResolveActorSource, signingSecret: string): Promise<Response> {
  if (!isUuid(mediaId)) return errorResponse(400, "VALIDATION_ERROR");
  try {
    const actorId = await requireActiveSession(session);
    const source = await resolve(actorId, mediaId);
    const signed = await createMediaProxyUrl({ baseUrl: request.url, mediaId, signingSecret });
    return jsonResponse(200, { data: { media_id: mediaId, url: signed.url, expires_at: signed.expiresAt } });
  } catch (error) { return mapError(error); }
}

export async function handleScopedMediaAccess(request: Request, token: string, mediaId: string,
  resolve: ResolveScopedSource, signingSecret: string): Promise<Response> {
  if (!isToken(token) || !isUuid(mediaId)) return errorResponse(404, "NOT_FOUND");
  try {
    const tokenHash = await hashScopedLinkToken(token);
    if (getCookie(request, "eve_scope") !== tokenHash) return errorResponse(404, "NOT_FOUND");
    const source = await resolve(tokenHash, mediaId);
    if (!source.link_expires_at) throw new MediaAccessNotFoundError();
    const signed = await createMediaProxyUrl({
      baseUrl: request.url, mediaId, signingSecret, token, linkExpiresAt: source.link_expires_at,
    });
    return jsonResponse(200, { data: { media_id: mediaId, proxy_url: signed.url,
      expires_at: signed.expiresAt, access_mode: "revalidated_proxy" } });
  } catch (error) { return mapError(error); }
}

export async function handleLinkSession(request: Request, exchange: ExchangeToken): Promise<Response> {
  const body = await parseTokenBody(request);
  if (!body.ok) return errorResponse(body.status, body.status === 403 ? "FORBIDDEN" : "VALIDATION_ERROR");
  try {
    const tokenHash = await hashScopedLinkToken(body.token);
    const link = await exchange(tokenHash);
    const now = Date.now();
    const expiryMs = Date.parse(link.expires_at);
    if (!Number.isFinite(expiryMs) || expiryMs <= now) throw new MediaAccessNotFoundError();
    const maxAge = Math.max(1, Math.floor((expiryMs - now) / 1000));
    const secure = new URL(request.url).protocol === "https:" ? "; Secure" : "";
    const headers = privateHeaders();
    const cookiePath = `/api/v1/s/${encodeURIComponent(body.token)}/`;
    headers.set("Set-Cookie", `eve_scope=${tokenHash}; Path=${cookiePath}; Max-Age=${maxAge}; HttpOnly; SameSite=Strict${secure}`);
    return new Response(JSON.stringify({ data: { resource_type: link.resource_type, expires_at: link.expires_at },
      meta: { request_id: crypto.randomUUID() } }), { status: 200, headers });
  } catch (error) { return mapError(error); }
}

export async function handleAuthenticatedMediaContent(request: Request, mediaId: string,
  session: SessionProvider, resolve: ResolveActorSource, signingSecret: string, fetchObject: FetchObject): Promise<Response> {
  if (!isUuid(mediaId)) return errorResponse(404, "NOT_FOUND");
  try {
    const actorId = await requireActiveSession(session);
    const signature = await verifyProxyRequest(request, mediaId, signingSecret, "account");
    if (!signature) return errorResponse(404, "NOT_FOUND");
    const source = await resolve(actorId, mediaId);
    return streamSource(source, await fetchObject(source));
  } catch (error) { return mapError(error); }
}

export async function handleScopedMediaContent(request: Request, token: string, mediaId: string,
  resolve: ResolveScopedSource, signingSecret: string, fetchObject: FetchObject): Promise<Response> {
  if (!isToken(token) || !isUuid(mediaId)) return errorResponse(404, "NOT_FOUND");
  try {
    const tokenHash = await hashScopedLinkToken(token);
    if (getCookie(request, "eve_scope") !== tokenHash) return errorResponse(404, "NOT_FOUND");
    const signature = await verifyProxyRequest(request, mediaId, signingSecret, tokenHash);
    if (!signature) return errorResponse(404, "NOT_FOUND");
    const source = await resolve(tokenHash, mediaId);
    return streamSource(source, await fetchObject(source));
  } catch (error) { return mapError(error); }
}

async function verifyProxyRequest(request: Request, mediaId: string, secret: string, scopeHash: string) {
  const url = new URL(request.url);
  const expText = url.searchParams.get("exp") ?? "";
  const sig = url.searchParams.get("sig") ?? "";
  if (!/^\d{1,12}$/.test(expText)) return false;
  return verifyMediaProxySignature({ mediaId, expiresAtSeconds: Number(expText), signature: sig,
    signingSecret: secret, scopeHash });
}

function streamSource(source: MediaAccessSource, upstream: Response): Response {
  const upstreamLength = upstream.headers.get("content-length");
  if (!upstream.body || upstream.status !== 200 || !upstreamLength
      || !/^\d+$/.test(upstreamLength) || Number(upstreamLength) !== source.size_bytes) {
    try { void upstream.body?.cancel(); } catch { /* already closed */ }
    throw new MediaAccessUnavailableError();
  }
  let received = 0;
  const reader = upstream.body.getReader();
  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const chunk = await reader.read();
        if (chunk.done) {
          if (received !== source.size_bytes) controller.error(new Error("media_stream_size_mismatch"));
          else controller.close();
          reader.releaseLock();
          return;
        }
        received += chunk.value.byteLength;
        if (received > source.size_bytes) {
          await reader.cancel();
          controller.error(new Error("media_stream_size_overflow"));
          reader.releaseLock();
          return;
        }
        controller.enqueue(chunk.value);
      } catch {
        controller.error(new Error("media_stream_unavailable"));
        try { reader.releaseLock(); } catch { /* stream already released */ }
      }
    },
    async cancel(reason) { try { await reader.cancel(reason); } finally { try { reader.releaseLock(); } catch { /* closed */ } } },
  });
  const headers = privateHeaders();
  headers.set("Content-Type", source.mime);
  headers.set("Content-Length", String(source.size_bytes));
  headers.set("Content-Disposition", "inline");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Cross-Origin-Resource-Policy", "same-origin");
  headers.set("Content-Security-Policy", "default-src 'none'; sandbox");
  return new Response(body, { status: 200, headers });
}

async function parseTokenBody(request: Request): Promise<{ ok: true; token: string } | { ok: false; status: 400 | 403 | 422 }> {
  const origin = request.headers.get("origin");
  if (!origin) return { ok: false, status: 403 };
  try { if (new URL(origin).origin !== new URL(request.url).origin) return { ok: false, status: 403 }; }
  catch { return { ok: false, status: 403 }; }
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") return { ok: false, status: 400 };
  let value: unknown;
  try { value = await request.json(); } catch { return { ok: false, status: 400 }; }
  if (!isRecord(value) || Object.keys(value).length !== 1 || typeof value.token !== "string" || !isToken(value.token)) {
    return { ok: false, status: 422 };
  }
  return { ok: true, token: value.token };
}

function getCookie(request: Request, name: string): string | null {
  const cookie = request.headers.get("cookie") ?? "";
  for (const part of cookie.split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return rest.join("=") || "";
  }
  return null;
}

function isToken(value: string): boolean { return value.length >= 43 && value.length <= 256 && /^[A-Za-z0-9_-]+$/.test(value); }
function isUuid(value: string): boolean { return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function errorResponse(status: number, code: string): Response {
  return new Response(JSON.stringify({ error: { code, message: status === 404 ? "Fayl tapılmadı və ya giriş icazəsi yoxdur." : "Sorğu qəbul edilmədi.", request_id: crypto.randomUUID() } }),
    { status, headers: privateHeaders() });
}
function jsonResponse(status: number, payload: Record<string, unknown>): Response {
  return new Response(JSON.stringify({ ...payload, meta: { request_id: crypto.randomUUID() } }), { status, headers: privateHeaders() });
}
function mapError(error: unknown): Response {
  if (error instanceof SessionUnauthorizedError) return errorResponse(401, "UNAUTHENTICATED");
  if (error instanceof SessionRateLimitError) {
    const response = errorResponse(429, "RATE_LIMITED");
    response.headers.set("Retry-After", String(error.retryAfterSeconds));
    return response;
  }
  if (error instanceof MediaAccessNotFoundError) return errorResponse(404, "NOT_FOUND");
  if (error instanceof MediaAccessExpiredError) return errorResponse(410, "LINK_EXPIRED");
  if (error instanceof MediaAccessRateLimitError) {
    const response = errorResponse(429, "RATE_LIMITED");
    response.headers.set("Retry-After", "60");
    return response;
  }
  return errorResponse(503, "PROVIDER_UNAVAILABLE");
}
function privateHeaders(): Headers {
  return new Headers({ "Content-Type": "application/json; charset=utf-8", "Cache-Control": "private, no-store",
    "Referrer-Policy": "no-referrer", "X-Robots-Tag": "noindex, nofollow" });
}
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
