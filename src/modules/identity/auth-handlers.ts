import {
  EMAIL_LINK_REDIRECT_PATH,
  EMAIL_LINK_RESEND_SECONDS,
  EMAIL_LINK_TTL_SECONDS,
  parseConfirmEmailInput,
  parseEmailLinkInput,
  type AuthProvider,
} from "./auth-contract.ts";

export async function handleEmailLinkRequest(
  request: Request,
  provider: AuthProvider | (() => Promise<AuthProvider>),
  confirmationUrl: string,
): Promise<Response> {
  if (!isJsonRequest(request)) return errorResponse(400, "VALIDATION_ERROR", "Sorğu forması düzgün deyil.");
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "VALIDATION_ERROR", "Sorğu forması düzgün deyil.");
  }
  const input = parseEmailLinkInput(body);
  if (!input) return errorResponse(422, "VALIDATION_ERROR", "Email ünvanını yoxlayın.");

  let authProvider: AuthProvider;
  try {
    authProvider = typeof provider === "function" ? await provider() : provider;
  } catch {
    return errorResponse(503, "PROVIDER_UNAVAILABLE", "Giriş xidməti hazırda əlçatan deyil.");
  }
  try {
    await authProvider.requestEmailLink(input.email, confirmationUrl);
  } catch (error) {
    if (error instanceof AuthRateLimitError) {
      return errorResponse(429, "RATE_LIMITED", "Bir az gözləyib yenidən cəhd edin.", error.retryAfterSeconds);
    }
    return errorResponse(503, "PROVIDER_UNAVAILABLE", "Giriş xidməti hazırda əlçatan deyil.");
  }

  // The 202 acknowledges the request, never email delivery or account existence.
  return jsonResponse(202, {
    data: {
      accepted: true,
      resend_after_seconds: EMAIL_LINK_RESEND_SECONDS,
      link_ttl_seconds: EMAIL_LINK_TTL_SECONDS,
    },
    meta: { request_id: crypto.randomUUID() },
  });
}

export async function handleEmailLinkConfirmation(
  request: Request,
  provider: AuthProvider | (() => Promise<AuthProvider>),
): Promise<Response> {
  if (!isJsonRequest(request)) return errorResponse(400, "VALIDATION_ERROR", "Sorğu forması düzgün deyil.");
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return errorResponse(400, "VALIDATION_ERROR", "Sorğu forması düzgün deyil.");
  }
  const input = parseConfirmEmailInput(body);
  if (!input) return errorResponse(422, "VALIDATION_ERROR", "Keçid məlumatı düzgün deyil.");

  let authProvider: AuthProvider;
  try {
    authProvider = typeof provider === "function" ? await provider() : provider;
  } catch {
    return errorResponse(503, "PROVIDER_UNAVAILABLE", "Giriş xidməti hazırda əlçatan deyil.");
  }
  try {
    await authProvider.confirmEmailLink(input.token_hash);
  } catch (error) {
    if (error instanceof AuthRateLimitError) {
      return errorResponse(429, "RATE_LIMITED", "Bir az gözləyib yenidən cəhd edin.", error.retryAfterSeconds);
    }
    if (error instanceof AuthProviderUnavailableError) {
      return errorResponse(503, "PROVIDER_UNAVAILABLE", "Giriş xidməti hazırda əlçatan deyil.");
    }
    return errorResponse(410, "LINK_EXPIRED", "Bu keçid artıq aktiv deyil.");
  }

  return jsonResponse(200, {
    data: { authenticated: true, redirect_path: EMAIL_LINK_REDIRECT_PATH },
    meta: { request_id: crypto.randomUUID() },
  });
}

export class AuthRateLimitError extends Error {
  readonly retryAfterSeconds: number;

  constructor(retryAfterSeconds = EMAIL_LINK_RESEND_SECONDS) {
    super("rate limited");
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

export class AuthProviderUnavailableError extends Error {
  constructor() {
    super("auth provider unavailable");
  }
}

export class AuthLinkRejectedError extends Error {
  constructor() {
    super("email link rejected");
  }
}

function isJsonRequest(request: Request): boolean {
  return request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() === "application/json";
}

function jsonResponse(status: number, payload: unknown, retryAfterSeconds?: number): Response {
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "private, no-store",
    "Referrer-Policy": "no-referrer",
  });
  if (retryAfterSeconds !== undefined) headers.set("Retry-After", String(retryAfterSeconds));
  return new Response(JSON.stringify(payload), { status, headers });
}

function errorResponse(status: number, code: string, message: string, retryAfterSeconds?: number): Response {
  return jsonResponse(status, {
    error: { code, message, request_id: crypto.randomUUID() },
  }, retryAfterSeconds);
}
