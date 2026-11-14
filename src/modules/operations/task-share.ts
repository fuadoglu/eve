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
export function createWhatsAppShareUrl(message: string): string | null {
  if (!message.trim() || message.length > 3000) return null;
  const url = new URL("https://wa.me/");
  url.searchParams.set("text", message);
  const value = url.toString();
  return value.length <= 2048 ? value : null;
}

export function buildTaskShareMessage(message: string, taskUrl: string): string {
  const text = message.trim();
  const link = taskUrl.trim();
  if (!text) return link.slice(0, 3000);
  if (!link || text.includes(link)) return text.slice(0, 3000);
  const complete = `${text}\n${link}`;
  return complete.length <= 3000 ? complete : link.slice(0, 3000);
}

/** Clipboard success is acknowledged only after the browser promise resolves. */
export async function copyTaskShareMessage(
  clipboard: ClipboardWriter | null | undefined,
  message: string,
): Promise<"copied" | "unavailable"> {
  if (!clipboard || !message.trim() || message.length > 3000) return "unavailable";
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
