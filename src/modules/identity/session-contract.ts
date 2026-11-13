export type SessionProvider = {
  getCurrentUserId(): Promise<string | null>;
  isCurrentSessionActive(): Promise<boolean>;
  signOutCurrentSession(): Promise<void>;
  revokeAllSessions(): Promise<void>;
  signOutAllSessions(): Promise<void>;
};

export class SessionUnauthorizedError extends Error {
  constructor() {
    super("session required or revoked");
  }
}

export class SessionRateLimitError extends Error {
  readonly retryAfterSeconds: number;

  constructor(retryAfterSeconds = 60) {
    super("session provider rate limited");
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

export class SessionProviderUnavailableError extends Error {
  constructor() {
    super("session provider unavailable");
  }
}
