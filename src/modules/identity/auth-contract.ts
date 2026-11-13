export const EMAIL_LINK_TTL_SECONDS = 900;
export const EMAIL_LINK_RESEND_SECONDS = 60;
export const EMAIL_LINK_REDIRECT_PATH = "/today" as const;

export type EmailLinkInput = {
  email: string;
  redirect_path: typeof EMAIL_LINK_REDIRECT_PATH;
};

export type ConfirmEmailInput = {
  token_hash: string;
  verification_type: "email";
  redirect_path: typeof EMAIL_LINK_REDIRECT_PATH;
};

export type AuthProvider = {
  requestEmailLink(email: string, redirectUrl: string): Promise<void>;
  confirmEmailLink(tokenHash: string): Promise<void>;
};

export function parseEmailLinkInput(value: unknown): EmailLinkInput | null {
  if (!isRecord(value) || !onlyKeys(value, ["email", "redirect_path"])) return null;
  if (typeof value.email !== "string") return null;
  const email = value.email.trim();
  if (email.length === 0 || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/u.test(email)) return null;
  if (value.redirect_path !== undefined && value.redirect_path !== EMAIL_LINK_REDIRECT_PATH) return null;
  return { email, redirect_path: EMAIL_LINK_REDIRECT_PATH };
}

export function parseConfirmEmailInput(value: unknown): ConfirmEmailInput | null {
  if (!isRecord(value) || !onlyKeys(value, ["token_hash", "verification_type", "redirect_path"])) return null;
  if (
    typeof value.token_hash !== "string"
    || value.token_hash.length < 16
    || value.token_hash.length > 512
    || /\s/u.test(value.token_hash)
    || value.verification_type !== "email"
    || (value.redirect_path !== undefined && value.redirect_path !== EMAIL_LINK_REDIRECT_PATH)
  ) return null;
  return {
    token_hash: value.token_hash,
    verification_type: "email",
    redirect_path: EMAIL_LINK_REDIRECT_PATH,
  };
}

export function escapeHtmlAttribute(value: string): string {
  return value.replace(/[&<>"']/gu, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character] ?? character);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function onlyKeys(value: Record<string, unknown>, allowed: string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}
