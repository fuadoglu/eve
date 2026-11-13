import assert from "node:assert/strict";
import test from "node:test";
import { POST as requestEmailLink } from "../../../src/app/api/v1/auth/email-link/route.ts";
import { POST as confirmEmailLink } from "../../../src/app/api/v1/auth/confirm/route.ts";

test("OpenAPI email-link route validates input and applies private noindex headers", async () => {
  const previous = process.env.APP_BASE_URL;
  process.env.APP_BASE_URL = "https://eve.example";
  try {
    const response = await requestEmailLink(new Request("https://eve.example/api/v1/auth/email-link", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: "invalid" }),
    }));
    assert.equal(response.status, 422);
    assert.equal(response.headers.get("cache-control"), "private, no-store");
    assert.equal(response.headers.get("referrer-policy"), "no-referrer");
    assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  } finally {
    if (previous === undefined) delete process.env.APP_BASE_URL;
    else process.env.APP_BASE_URL = previous;
  }
});

test("OpenAPI confirm route rejects invalid input before constructing Supabase", async () => {
  const response = await confirmEmailLink(new Request("https://eve.example/api/v1/auth/confirm", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token_hash: "short", verification_type: "email" }),
  }));
  assert.equal(response.status, 422);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
});
