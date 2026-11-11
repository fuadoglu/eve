import assert from "node:assert/strict";
import test from "node:test";
import { validateSupabasePublicConfig } from "../../src/lib/env/supabase-public.ts";
import { getSupabaseSecretKey } from "../../src/lib/env/supabase-server.ts";

function withSecretKey<T>(value: string | undefined, run: () => T): T {
  const previous = process.env.SUPABASE_SECRET_KEY;
  if (value === undefined) {
    delete process.env.SUPABASE_SECRET_KEY;
  } else {
    process.env.SUPABASE_SECRET_KEY = value;
  }

  try {
    return run();
  } finally {
    if (previous === undefined) {
      delete process.env.SUPABASE_SECRET_KEY;
    } else {
      process.env.SUPABASE_SECRET_KEY = previous;
    }
  }
}

test("accepts HTTPS project URL and returns normalized public config", () => {
  assert.deepEqual(
    validateSupabasePublicConfig(
      "https://project.supabase.co/",
      "sb_publishable_example",
    ),
    {
      url: "https://project.supabase.co",
      publishableKey: "sb_publishable_example",
    },
  );
});

test("accepts HTTP only for a local Supabase project", () => {
  assert.equal(
    validateSupabasePublicConfig(
      "http://127.0.0.1:54321",
      "sb_publishable_example",
    ).url,
    "http://127.0.0.1:54321",
  );
});

test("rejects a missing public key", () => {
  assert.throws(
    () => validateSupabasePublicConfig("https://project.supabase.co", ""),
    /NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY/,
  );
});

test("rejects a non-local HTTP URL", () => {
  assert.throws(
    () => validateSupabasePublicConfig("http://project.supabase.co", "sb_publishable_example"),
    /must use HTTPS/,
  );
});

test("rejects URLs with embedded credentials", () => {
  assert.throws(
    () => validateSupabasePublicConfig(
      "https://user:password@project.supabase.co",
      "sb_publishable_example",
    ),
    /credentials/,
  );
});

test("rejects a project URL with an extra path", () => {
  assert.throws(
    () => validateSupabasePublicConfig(
      "https://project.supabase.co/extra",
      "sb_publishable_example",
    ),
    /must not contain a path/,
  );
});

test("requires the privileged key only when server code requests it", () => {
  withSecretKey(undefined, () => {
    assert.throws(() => getSupabaseSecretKey(), /SUPABASE_SECRET_KEY/);
  });
});

test("returns the privileged key without logging or transforming it", () => {
  withSecretKey("sb_secret_example", () => {
    assert.equal(getSupabaseSecretKey(), "sb_secret_example");
  });
});

test("rejects whitespace around the privileged key", () => {
  withSecretKey(" sb_secret_example ", () => {
    assert.throws(() => getSupabaseSecretKey(), /surrounding whitespace/);
  });
});
