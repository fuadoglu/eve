import {
  SessionRateLimitError,
  SessionUnauthorizedError,
  type SessionProvider,
} from "./session-contract.ts";

export async function requireActiveSession(provider: SessionProvider): Promise<string> {
  const userId = await provider.getCurrentUserId();
  if (!userId || !(await provider.isCurrentSessionActive())) throw new SessionUnauthorizedError();
  return userId;
}

export async function handleCurrentSessionLogout(
  request: Request,
  provider: SessionProvider | (() => Promise<SessionProvider>),
): Promise<Response> {
  const body = await parseEmptyJson(request);
  if (!body.ok) {
    if (body.status === 403) return errorResponse(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
    return errorResponse(body.status, "VALIDATION_ERROR", "Sorğu forması düzgün deyil.");
  }

  let sessionProvider: SessionProvider;
  try {
    sessionProvider = await resolveProvider(provider);
    await requireActiveSession(sessionProvider);
    await sessionProvider.signOutCurrentSession();
  } catch (error) {
    return mapError(error);
  }
  return ackResponse();
}

export async function handleLogoutAllSessions(
  request: Request,
  provider: SessionProvider | (() => Promise<SessionProvider>),
): Promise<Response> {
  const body = await parseEmptyJson(request);
  if (!body.ok) {
    if (body.status === 403) return errorResponse(403, "FORBIDDEN", "Sorğu bu mənbədən qəbul edilmir.");
    return errorResponse(body.status, "VALIDATION_ERROR", "Sorğu forması düzgün deyil.");
  }

  let sessionProvider: SessionProvider;
  try {
    sessionProvider = await resolveProvider(provider);
    await requireActiveSession(sessionProvider);
    await sessionProvider.revokeAllSessions();
    try {
      await sessionProvider.signOutAllSessions();
    } catch (error) {
      // The app cutoff is already active. Clear this browser's cookie too, but
      // keep the provider failure visible so the client never claims completion.
      try { await sessionProvider.signOutCurrentSession(); } catch { /* fail closed at the app cutoff */ }
      return mapError(error);
    }
  } catch (error) {
    return mapError(error);
  }
  return ackResponse();
}

async function resolveProvider(
  provider: SessionProvider | (() => Promise<SessionProvider>),
): Promise<SessionProvider> {
  return typeof provider === "function" ? provider() : provider;
}

async function parseEmptyJson(
  request: Request,
): Promise<{ ok: true } | { ok: false; status: 400 | 422 | 403 }> {
  const origin = request.headers.get("origin");
  if (origin === null) return { ok: false, status: 403 };
  try {
    if (new URL(origin).origin !== new URL(request.url).origin) return { ok: false, status: 403 };
  } catch {
    return { ok: false, status: 403 };
  }
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
    return { ok: false, status: 400 };
  }
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return { ok: false, status: 400 };
  }
  if (!isRecord(body) || Object.keys(body).length !== 0) return { ok: false, status: 422 };
  return { ok: true };
}

function ackResponse(): Response {
  return jsonResponse(200, {
    data: { accepted: true },
    meta: { request_id: crypto.randomUUID() },
  });
}

function mapError(error: unknown): Response {
  if (error instanceof SessionUnauthorizedError) {
    return errorResponse(401, "UNAUTHENTICATED", "Sessiya yoxdur, bitib və ya ləğv edilib.");
  }
  if (error instanceof SessionRateLimitError) {
    return errorResponse(429, "RATE_LIMITED", "Bir az gözləyib yenidən cəhd edin.", error.retryAfterSeconds);
  }
  return errorResponse(503, "PROVIDER_UNAVAILABLE", "Sessiya xidməti hazırda əlçatan deyil.");
}

function errorResponse(status: number, code: string, message: string, retryAfterSeconds?: number): Response {
  const headers = privateHeaders();
  if (retryAfterSeconds !== undefined) headers.set("Retry-After", String(retryAfterSeconds));
  return new Response(JSON.stringify({
    error: { code, message, request_id: crypto.randomUUID() },
  }), { status, headers });
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
