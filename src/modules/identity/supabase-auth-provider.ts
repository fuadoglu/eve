import "server-only";

import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabasePublicConfig } from "../../lib/env/supabase-public.ts";
import {
  AuthLinkRejectedError,
  AuthProviderUnavailableError,
  AuthRateLimitError,
} from "./auth-handlers.ts";
import type { AuthProvider } from "./auth-contract.ts";

export async function createSupabaseAuthProvider(): Promise<AuthProvider> {
  const { url, publishableKey } = getSupabasePublicConfig();
  const cookieStore = await cookies();
  const secureCookies = process.env.NODE_ENV === "production";
  const supabase = createServerClient(url, publishableKey, {
    auth: {
      flowType: "pkce",
      detectSessionInUrl: false,
      persistSession: true,
      autoRefreshToken: false,
    },
    cookieOptions: {
      path: "/",
      sameSite: "lax",
      secure: secureCookies,
      httpOnly: true,
    },
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value, options } of cookiesToSet) {
          cookieStore.set(name, value, {
            ...options,
            path: "/",
            sameSite: "lax",
            secure: secureCookies,
            httpOnly: true,
          });
        }
      },
    },
  });

  return {
    async requestEmailLink(email, redirectUrl) {
      const { error } = await supabase.auth.signInWithOtp({
        email,
        options: {
          shouldCreateUser: true,
          emailRedirectTo: redirectUrl,
        },
      });
      if (!error) return;
      const status = error.status ?? 0;
      if (status === 429) throw new AuthRateLimitError();
      if (status === 401 || status === 403 || status >= 500 || status === 0) {
        throw new AuthProviderUnavailableError();
      }
      // Normalize provider-side 4xx results: they can depend on the account's
      // existing sign-in methods, so they must not reveal account existence.
    },
    async confirmEmailLink(tokenHash) {
      let error;
      try {
        ({ error } = await supabase.auth.verifyOtp({
          token_hash: tokenHash,
          type: "email",
        }));
      } catch (error) {
        throw new AuthProviderUnavailableError();
      }
      if (!error) return;
      const status = error.status ?? 0;
      if (status === 429) throw new AuthRateLimitError();
      if (status === 401 || status === 403 || status >= 500 || status === 0) {
        throw new AuthProviderUnavailableError();
      }
      throw new AuthLinkRejectedError();
    },
  };
}
