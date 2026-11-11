export type SupabasePublicConfig = {
  url: string;
  publishableKey: string;
};

function required(value: string | undefined, name: string): string {
  if (!value || value.trim() === "") {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  if (value !== value.trim()) {
    throw new Error(`Environment variable ${name} must not contain surrounding whitespace`);
  }

  return value;
}

export function validateSupabasePublicConfig(
  urlValue: string | undefined,
  publishableKeyValue: string | undefined,
): SupabasePublicConfig {
  const rawUrl = required(urlValue, "NEXT_PUBLIC_SUPABASE_URL");
  const publishableKey = required(
    publishableKeyValue,
    "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY",
  );

  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL must be a valid HTTP(S) URL");
  }

  const localHosts = new Set(["localhost", "127.0.0.1", "[::1]"]);
  const isLocalHttp = url.protocol === "http:" && localHosts.has(url.hostname);
  if (url.protocol !== "https:" && !isLocalHttp) {
    throw new Error("NEXT_PUBLIC_SUPABASE_URL must use HTTPS except for a local project");
  }

  if (url.pathname !== "/" || url.username || url.password || url.search || url.hash) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL must not contain a path, credentials, query, or fragment",
    );
  }

  return {
    url: url.toString().replace(/\/$/, ""),
    publishableKey,
  };
}

export function getSupabasePublicConfig(): SupabasePublicConfig {
  return validateSupabasePublicConfig(
    process.env.NEXT_PUBLIC_SUPABASE_URL,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );
}
