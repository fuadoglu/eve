import { createHash } from "node:crypto";

export class TaskLinkApiError extends Error {
  readonly code: string;
  constructor(code: string) { super(code); this.code = code; }
}

export type CreateTaskLink = (taskId: string, expiresAt: string | null, key: string) => Promise<unknown>;
export type RevokeTaskLink = (linkId: string) => Promise<unknown>;
export type ReadScopedTask = (tokenHash: string) => Promise<unknown>;
export type TransitionScopedTask = (tokenHash: string, input: {
  expected_version: number; action: "accept" | "report_done"; claimed_name: string;
  note?: string; media_ids?: string[];
}, key: string) => Promise<unknown>;

export async function handleCreateTaskLink(request: Request, taskId: string, create: CreateTaskLink): Promise<Response> {
  if (!isUuid(taskId)) return fail(404, "NOT_FOUND");
  const parsed = await parseMutation(request, ["expires_at"]);
  if (!parsed.ok) return parsed.response;
  const expires = parsed.body.expires_at;
  if (expires !== undefined && (typeof expires !== "string" || !Number.isFinite(Date.parse(expires)))) return fail(422, "VALIDATION_ERROR");
  try {
    const value = await create(taskId, expires ?? null, parsed.key);
    if (!isRecord(value) || !isUuid(value.link_id) || typeof value.expires_at !== "string"
      || typeof value.token !== "string" || !isToken(value.token)) throw new TaskLinkApiError("PROVIDER_UNAVAILABLE");
    const url = new URL(`/s/${encodeURIComponent(value.token)}`, request.url).toString();
    const message = "Tapşırığı Eve-də açın.";
    const whatsapp = `https://wa.me/?text=${encodeURIComponent(`${message}\n${url}`)}`;
    return json(201, { link_id: value.link_id, url, expires_at: value.expires_at,
      whatsapp_url: whatsapp.length <= 2048 ? whatsapp : null, message, delivery_state: "not_tracked" });
  } catch (error) { return mapped(error); }
}

export async function handleRevokeTaskLink(request: Request, linkId: string, revoke: RevokeTaskLink): Promise<Response> {
  if (!isUuid(linkId)) return fail(404, "NOT_FOUND");
  const parsed = await parseMutation(request, []);
  if (!parsed.ok) return parsed.response;
  try {
    const result = await revoke(linkId);
    if (!isRecord(result) || result.accepted !== true) throw new TaskLinkApiError("PROVIDER_UNAVAILABLE");
    return json(200, { accepted: true });
  } catch (error) { return mapped(error); }
}

export async function handleReadScopedTask(request: Request, token: string, read: ReadScopedTask): Promise<Response> {
  const hash = scopeHash(request, token);
  if (!hash) return fail(404, "NOT_FOUND");
  if (new URL(request.url).search) return fail(400, "VALIDATION_ERROR");
  try { return json(200, parseScopedTask(await read(hash))); }
  catch (error) { return mapped(error); }
}

export async function handleTransitionScopedTask(request: Request, token: string,
  action: "accept" | "report_done", transition: TransitionScopedTask): Promise<Response> {
  const hash = scopeHash(request, token);
  if (!hash) return fail(404, "NOT_FOUND");
  const parsed = await parseMutation(request, action === "accept"
    ? ["expected_version", "claimed_name"] : ["expected_version", "claimed_name", "note", "media_ids"]);
  if (!parsed.ok) return parsed.response;
  const { expected_version, claimed_name, note, media_ids } = parsed.body;
  if (!Number.isSafeInteger(expected_version) || (expected_version as number) < 1
    || typeof claimed_name !== "string" || claimed_name.trim().length < 1 || claimed_name.length > 100
    || (note !== undefined && (typeof note !== "string" || note.length > 2000))
    || (media_ids !== undefined && (!Array.isArray(media_ids) || media_ids.length > 20
      || new Set(media_ids).size !== media_ids.length || media_ids.some((id) => !isUuid(id))))) return fail(422, "VALIDATION_ERROR");
  try {
    const result = await transition(hash, {
      expected_version: expected_version as number, action, claimed_name,
      ...(note === undefined ? {} : { note: note as string }),
      ...(media_ids === undefined ? {} : { media_ids: media_ids as string[] }),
    }, parsed.key);
    return json(200, parseScopedTask(result));
  } catch (error) { return mapped(error); }
}

async function parseMutation(request: Request, allowed: string[]): Promise<
  { ok: true; body: Record<string, unknown>; key: string } | { ok: false; response: Response }
> {
  const origin = request.headers.get("origin");
  try { if (!origin || new URL(origin).origin !== new URL(request.url).origin) return { ok: false, response: fail(403, "FORBIDDEN") }; }
  catch { return { ok: false, response: fail(403, "FORBIDDEN") }; }
  const key = request.headers.get("idempotency-key") ?? "";
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(key)) return { ok: false, response: fail(400, "VALIDATION_ERROR") };
  if (request.headers.get("content-type")?.split(";")[0]?.trim().toLowerCase() !== "application/json")
    return { ok: false, response: fail(400, "VALIDATION_ERROR") };
  let body: unknown;
  try { body = await request.json(); } catch { return { ok: false, response: fail(400, "VALIDATION_ERROR") }; }
  if (!isRecord(body) || Object.keys(body).some((key) => !allowed.includes(key)))
    return { ok: false, response: fail(422, "VALIDATION_ERROR") };
  return { ok: true, body, key };
}

function scopeHash(request: Request, token: string): string | null {
  if (!isToken(token)) return null;
  const expected = createHash("sha256").update(token).digest("hex");
  const cookie = (request.headers.get("cookie") ?? "").split(";").map((part) => part.trim())
    .find((part) => part.startsWith("eve_scope="))?.slice("eve_scope=".length);
  return cookie === expected ? expected : null;
}

function parseScopedTask(value: unknown): Record<string, unknown> {
  if (!isRecord(value) || Object.keys(value).some((key) => !["task_id", "property_label", "address", "title", "due_at", "state", "version"].includes(key))
    || !isUuid(value.task_id) || typeof value.property_label !== "string" || !value.property_label
    || typeof value.title !== "string" || !value.title || typeof value.due_at !== "string"
    || !Number.isFinite(Date.parse(value.due_at))
    || !["open", "accepted", "reported_done", "completed", "cancelled"].includes(String(value.state))
    || !Number.isSafeInteger(value.version) || (value.version as number) < 1
    || (value.address !== null && value.address !== undefined && typeof value.address !== "string")) {
    throw new TaskLinkApiError("PROVIDER_UNAVAILABLE");
  }
  return value;
}

function mapped(error: unknown): Response {
  const code = error instanceof TaskLinkApiError ? error.code : "PROVIDER_UNAVAILABLE";
  const status = code === "UNAUTHENTICATED" ? 401 : code === "FORBIDDEN" ? 403
    : code === "NOT_FOUND" ? 404 : code === "LINK_EXPIRED" ? 410
      : code === "CONFLICT" ? 409 : code === "VALIDATION_ERROR" ? 422 : 503;
  return fail(status, code);
}
function json(status: number, data: unknown): Response {
  return new Response(JSON.stringify({ data, meta: { request_id: crypto.randomUUID() } }),
    { status, headers: headers() });
}
function fail(status: number, code: string): Response {
  return new Response(JSON.stringify({ error: { code, message: status === 410 ? "Keçidin vaxtı bitib və ya ləğv edilib."
    : status === 404 ? "Keçid tapılmadı və ya icazə yoxdur." : "Sorğu qəbul edilmədi.", request_id: crypto.randomUUID() } }),
    { status, headers: headers() });
}
function headers(): Headers { return new Headers({ "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "private, no-store", "Referrer-Policy": "no-referrer", "X-Robots-Tag": "noindex, nofollow" }); }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
function isUuid(value: unknown): value is string { return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function isToken(value: string): boolean { return value.length >= 43 && value.length <= 256 && /^[A-Za-z0-9_-]+$/.test(value); }
