import { createHash, createHmac } from "node:crypto";

export function deriveTaskLinkToken(secretHex: string, actorId: string, taskId: string, key: string): string {
  if (!/^[0-9a-f]{64}$/.test(secretHex)) throw new TypeError("invalid_task_link_secret");
  return createHmac("sha256", Buffer.from(secretHex, "hex"))
    .update(`eve-task-link-v1\0${actorId}\0${taskId}\0${key}`)
    .digest("base64url");
}

export function sha256(value: string): string { return createHash("sha256").update(value).digest("hex"); }
