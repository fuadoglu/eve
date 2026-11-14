export const MEDIA_PROXY_TTL_SECONDS = 300;
export const MEDIA_PROXY_CONTENT_PATH = "/api/v1/media";
export const SCOPED_MEDIA_PROXY_PATH = "/api/v1/s";

export type MediaAccessSource = {
  id: string;
  classification: string;
  bucket: string;
  object_key: string;
  mime: string;
  size_bytes: number;
  link_expires_at?: string;
};

const BUCKETS: Record<string, string> = {
  private_guest: "eve-private-guest",
  private_receipt: "eve-private-receipt",
  private_inspection: "eve-private-inspection",
  private_task: "eve-private-task",
  private_inventory: "eve-private-inventory",
};

export function validatePrivateMediaSource(value: unknown, expectedId: string): value is MediaAccessSource {
  if (!isRecord(value)) return false;
  return value.id === expectedId && typeof value.classification === "string"
    && BUCKETS[value.classification] === value.bucket && value.object_key === expectedId
    && typeof value.mime === "string"
    && ["image/jpeg", "image/png", "image/webp", "video/mp4", "audio/webm", "audio/mp4", "application/pdf"].includes(value.mime)
    && Number.isSafeInteger(value.size_bytes) && Number(value.size_bytes) > 0
    && Number(value.size_bytes) <= 104857600
    && (value.link_expires_at === undefined || typeof value.link_expires_at === "string");
}

export async function hashScopedLinkToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function createMediaProxyUrl(input: {
  baseUrl: string;
  mediaId: string;
  signingSecret: string;
  token?: string;
  linkExpiresAt?: string;
  nowSeconds?: number;
}): Promise<{ url: string; expiresAt: string }> {
  const nowSeconds = input.nowSeconds ?? Math.floor(Date.now() / 1000);
  let expiresAtSeconds = nowSeconds + MEDIA_PROXY_TTL_SECONDS;
  let scopeHash = "account";
  let path = `${MEDIA_PROXY_CONTENT_PATH}/${input.mediaId}/content`;
  if (input.token !== undefined) {
    scopeHash = await hashScopedLinkToken(input.token);
    const linkExpiry = input.linkExpiresAt ? Math.floor(Date.parse(input.linkExpiresAt) / 1000) : NaN;
    if (!Number.isSafeInteger(linkExpiry) || linkExpiry <= nowSeconds) throw new TypeError("invalid_link_expiry");
    expiresAtSeconds = Math.min(expiresAtSeconds, linkExpiry);
    path = `${SCOPED_MEDIA_PROXY_PATH}/${encodeURIComponent(input.token)}/media/${input.mediaId}/content`;
  }
  const expiresAt = new Date(expiresAtSeconds * 1000).toISOString();
  const signature = await signProxy(input.signingSecret, input.mediaId, expiresAtSeconds, scopeHash);
  const url = new URL(path, input.baseUrl);
  url.searchParams.set("exp", String(expiresAtSeconds));
  url.searchParams.set("sig", signature);
  return { url: url.toString(), expiresAt };
}

export async function verifyMediaProxySignature(input: {
  mediaId: string;
  expiresAtSeconds: number;
  signature: string;
  signingSecret: string;
  scopeHash?: string;
  nowSeconds?: number;
}): Promise<boolean> {
  const now = input.nowSeconds ?? Math.floor(Date.now() / 1000);
  if (!Number.isSafeInteger(input.expiresAtSeconds) || input.expiresAtSeconds <= now
      || input.expiresAtSeconds > now + MEDIA_PROXY_TTL_SECONDS
      || !/^[A-Za-z0-9_-]{43}$/.test(input.signature)) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(input.signingSecret),
    { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  const signatureBytes = fromBase64Url(input.signature);
  const signatureBuffer = new ArrayBuffer(signatureBytes.byteLength);
  new Uint8Array(signatureBuffer).set(signatureBytes);
  return crypto.subtle.verify("HMAC", key, signatureBuffer,
    new TextEncoder().encode(signatureMessage(input.mediaId, input.expiresAtSeconds, input.scopeHash ?? "account")));
}

async function signProxy(secret: string, mediaId: string, expiresAt: number, scopeHash: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key,
    new TextEncoder().encode(signatureMessage(mediaId, expiresAt, scopeHash)));
  return toBase64Url(new Uint8Array(signature));
}

function signatureMessage(mediaId: string, expiresAt: number, scopeHash: string): string {
  return `eve-media-proxy:v1:${mediaId}:${expiresAt}:${scopeHash}`;
}

function toBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function fromBase64Url(value: string): Uint8Array {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(base64 + "=".repeat((4 - base64.length % 4) % 4));
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
