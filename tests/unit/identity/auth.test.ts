import assert from "node:assert/strict";
import test from "node:test";
import {
  parseConfirmEmailInput,
  parseEmailLinkInput,
} from "../../../src/modules/identity/auth-contract.ts";
import {
  AuthLinkRejectedError,
  AuthProviderUnavailableError,
  AuthRateLimitError,
  handleEmailLinkConfirmation,
  handleEmailLinkRequest,
  type AuthProvider,
} from "../../../src/modules/identity/auth-handlers.ts";
import { renderConfirmationLanding } from "../../../src/app/auth/confirm/confirmation-page.ts";

const provider: AuthProvider = {
  async requestEmailLink() {},
  async confirmEmailLink() {},
};

function jsonRequest(path: string, body: unknown): Request {
  return new Request(`https://eve.example${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

test("email link input trims but does not change the email identity", () => {
  assert.deepEqual(parseEmailLinkInput({ email: "  A.User+tag@Example.az  " }), {
    email: "A.User+tag@Example.az",
    redirect_path: "/today",
  });
  assert.equal(parseEmailLinkInput({ email: "a@example.az", redirect_path: "https://attacker.example" }), null);
  assert.equal(parseEmailLinkInput({ email: "a@example.az", owner_id: "attacker" }), null);
  assert.equal(parseEmailLinkInput({ email: "not-email" }), null);
  assert.equal(parseEmailLinkInput({ email: `a${"x".repeat(250)}@example.az` }), null);
});

test("confirmation input only accepts an email token and the fixed redirect", () => {
  assert.deepEqual(parseConfirmEmailInput({ token_hash: "a".repeat(32), verification_type: "email" }), {
    token_hash: "a".repeat(32),
    verification_type: "email",
    redirect_path: "/today",
  });
  assert.equal(parseConfirmEmailInput({ token_hash: "short", verification_type: "email" }), null);
  assert.equal(parseConfirmEmailInput({ token_hash: "a".repeat(32), verification_type: "recovery" }), null);
  assert.equal(parseConfirmEmailInput({ token_hash: "a".repeat(32), verification_type: "email", redirect_path: "//attacker" }), null);
});

test("request endpoint returns a neutral 202 without echoing email or claiming delivery", async () => {
  let receivedEmail = "";
  let receivedRedirect = "";
  const fakeProvider: AuthProvider = {
    async requestEmailLink(email, redirectUrl) { receivedEmail = email; receivedRedirect = redirectUrl; },
    async confirmEmailLink() {},
  };
  const response = await handleEmailLinkRequest(
    jsonRequest("/auth/email-link", { email: " owner@example.az ", redirect_path: "/today" }),
    fakeProvider,
    "https://eve.example/auth/confirm?redirect_path=%2Ftoday",
  );
  const payload = await response.json();
  assert.equal(response.status, 202);
  assert.equal(receivedEmail, "owner@example.az");
  assert.equal(receivedRedirect, "https://eve.example/auth/confirm?redirect_path=%2Ftoday");
  assert.deepEqual(payload.data, { accepted: true, resend_after_seconds: 60, link_ttl_seconds: 900 });
  assert.doesNotMatch(JSON.stringify(payload), /owner@example\.az/);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
});

test("invalid request is rejected before provider initialization", async () => {
  let providerCreated = false;
  const response = await handleEmailLinkRequest(
    jsonRequest("/auth/email-link", { email: "bad", redirect_path: "/today" }),
    async () => { providerCreated = true; return provider; },
    "https://eve.example/auth/confirm",
  );
  assert.equal(response.status, 422);
  assert.equal(providerCreated, false);
});

test("provider throttling returns 429 with Retry-After and no provider details", async () => {
  const fakeProvider: AuthProvider = {
    async requestEmailLink() { throw new AuthRateLimitError(60); },
    async confirmEmailLink() {},
  };
  const response = await handleEmailLinkRequest(
    jsonRequest("/auth/email-link", { email: "owner@example.az" }),
    fakeProvider,
    "https://eve.example/auth/confirm",
  );
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("retry-after"), "60");
  assert.equal((await response.json()).error.code, "RATE_LIMITED");
});

test("provider transport failure is generic and does not expose its message", async () => {
  const fakeProvider: AuthProvider = {
    async requestEmailLink() { throw new AuthProviderUnavailableError(); },
    async confirmEmailLink() {},
  };
  const response = await handleEmailLinkRequest(
    jsonRequest("/auth/email-link", { email: "owner@example.az" }),
    fakeProvider,
    "https://eve.example/auth/confirm",
  );
  assert.equal(response.status, 503);
  assert.doesNotMatch(await response.text(), /owner@example\.az|AuthProviderUnavailableError/);
});

test("confirm verifies only on explicit POST and returns the fixed session result", async () => {
  let confirmedToken = "";
  const fakeProvider: AuthProvider = {
    async requestEmailLink() {},
    async confirmEmailLink(tokenHash) { confirmedToken = tokenHash; },
  };
  const tokenHash = "synthetic-token-hash-1234567890";
  const response = await handleEmailLinkConfirmation(
    jsonRequest("/auth/confirm", { token_hash: tokenHash, verification_type: "email" }),
    fakeProvider,
  );
  const responseText = await response.clone().text();
  assert.equal(response.status, 200);
  assert.equal(confirmedToken, tokenHash);
  assert.deepEqual((await response.json()).data, { authenticated: true, redirect_path: "/today" });
  assert.doesNotMatch(responseText, /synthetic-token-hash/);
});

test("expired and replayed token failures use one neutral 410 response", async () => {
  const fakeProvider: AuthProvider = {
    async requestEmailLink() {},
    async confirmEmailLink() { throw new AuthLinkRejectedError(); },
  };
  const response = await handleEmailLinkConfirmation(
    jsonRequest("/auth/confirm", { token_hash: "synthetic-token-hash-1234567890", verification_type: "email" }),
    fakeProvider,
  );
  const responseText = await response.clone().text();
  assert.equal(response.status, 410);
  assert.equal((await response.json()).error.code, "LINK_EXPIRED");
  assert.doesNotMatch(responseText, /synthetic-token-hash/);
});

test("confirmation landing GET is no-store and does not auto-submit or expose token markup", async () => {
  const response = renderConfirmationLanding(`x"><script>alert(1)</script>`);
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.match(response.headers.get("content-security-policy") ?? "", /default-src 'none'/);
  assert.match(html, /addEventListener\("submit"/);
  assert.match(html, /history\.replaceState/);
  assert.doesNotMatch(html, /value="x"><script>alert/);
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
});
