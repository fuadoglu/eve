import "server-only";

import { createHash, randomBytes } from "node:crypto";

const INVITE_TOKEN_BYTES = 32;
const INVITE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{43,256}$/;

export type ManagerInviteToken = Readonly<{
  rawToken: string;
  tokenHash: string;
}>;

/** Create the one-time raw token for the delivery adapter and its DB-safe hash. */
export function createManagerInviteToken(): ManagerInviteToken {
  const rawToken = randomBytes(INVITE_TOKEN_BYTES).toString("base64url");
  return { rawToken, tokenHash: hashManagerInviteToken(rawToken) };
}

/** Hash a token received from an authenticated acceptance request. */
export function hashManagerInviteToken(rawToken: string): string {
  if (typeof rawToken !== "string" || !INVITE_TOKEN_PATTERN.test(rawToken)) {
    throw new TypeError("invalid_manager_invite_token");
  }
  return createHash("sha256").update(rawToken, "utf8").digest("hex");
}
