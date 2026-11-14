export type TaskShareResult = {
  link_id: string;
  url: string;
  expires_at: string;
  whatsapp_url: string | null;
  message: string;
  delivery_state: "not_tracked";
};

export type ClipboardWriter = Pick<Clipboard, "writeText">;

/** Use the fixed WhatsApp web entry point; never interpolate an untrusted host. */
export function createWhatsAppShareUrl(message: string): string {
  if (!message.trim() || message.length > 3000) throw new TypeError("invalid_task_share_message");
  const url = new URL("https://wa.me/");
  url.searchParams.set("text", message);
  return url.toString();
}

/** Clipboard success is acknowledged only after the browser promise resolves. */
export async function copyTaskShareMessage(
  clipboard: ClipboardWriter | null | undefined,
  message: string,
): Promise<"copied" | "unavailable"> {
  if (!clipboard || !message.trim()) return "unavailable";
  try {
    await clipboard.writeText(message);
    return "copied";
  } catch {
    return "unavailable";
  }
}

export function formatTaskShareExpiry(value: string, locale = "az-AZ"): string {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) return "";
  return new Intl.DateTimeFormat(locale, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}
