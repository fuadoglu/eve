import {
  SessionProviderUnavailableError,
  SessionRateLimitError,
  SessionUnauthorizedError,
  type SessionProvider,
} from "./session-contract.ts";

type ProviderError = { status?: number; code?: string; name?: string };
export type SessionProviderClient = {
  auth: {
    getUser(): Promise<{ data: { user: { id: string } | null }; error: ProviderError | null }>;
    signOut(options: { scope: "local" | "global" }): Promise<{ error: ProviderError | null }>;
  };
  schema(name: "api"): {
    rpc(name: "is_my_session_active" | "revoke_my_sessions"): Promise<{
      data: unknown;
      error: ProviderError | null;
    }>;
  };
};

export function createSessionProvider(client: SessionProviderClient): SessionProvider {
  return {
    async getCurrentUserId() {
      let result: Awaited<ReturnType<SessionProviderClient["auth"]["getUser"]>>;
      try {
        result = await client.auth.getUser();
      } catch {
        throw new SessionProviderUnavailableError();
      }
      if (result.error) throw mapAuthError(result.error);
      return result.data.user?.id ?? null;
    },
    async isCurrentSessionActive() {
      const { data, error } = await client.schema("api").rpc("is_my_session_active");
      if (error) throw new SessionProviderUnavailableError();
      return data === true;
    },
    async signOutCurrentSession() {
      const { error } = await client.auth.signOut({ scope: "local" });
      if (error) throw mapProviderError(error);
    },
    async revokeAllSessions() {
      const { data, error } = await client.schema("api").rpc("revoke_my_sessions");
      if (error) throw new SessionProviderUnavailableError();
      if (data !== true) throw new SessionProviderUnavailableError();
    },
    async signOutAllSessions() {
      const { error } = await client.auth.signOut({ scope: "global" });
      // Supabase documents 401/403/404 as successful global sign-out results.
      if (error && ![401, 403, 404].includes(error.status ?? 0)) {
        throw mapProviderError(error);
      }
    },
  };
}

function mapAuthError(error: ProviderError): Error {
  if (error.status === 429) return new SessionRateLimitError();
  if (error.name === "AuthSessionMissingError" || (error.status ?? 0) >= 400 && (error.status ?? 0) < 500) {
    return new SessionUnauthorizedError();
  }
  return new SessionProviderUnavailableError();
}

function mapProviderError(error: ProviderError): Error {
  if (error.status === 429) return new SessionRateLimitError();
  if ([401, 403].includes(error.status ?? 0)) return new SessionUnauthorizedError();
  return new SessionProviderUnavailableError();
}
