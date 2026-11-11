import "server-only";

/**
 * Elevated Supabase credential. Use only in server operations that perform
 * their own explicit authorization checks; never use it for user-scoped access.
 */
export function getSupabaseSecretKey(): string {
  const secretKey = process.env.SUPABASE_SECRET_KEY;
  if (!secretKey || secretKey.trim() === "") {
    throw new Error("Missing required environment variable: SUPABASE_SECRET_KEY");
  }

  if (secretKey !== secretKey.trim()) {
    throw new Error("Environment variable SUPABASE_SECRET_KEY must not contain surrounding whitespace");
  }

  return secretKey;
}
