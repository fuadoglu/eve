export type TaskState = "open" | "accepted" | "reported_done" | "completed" | "cancelled";
export type TaskTransitionAction = "accept" | "report_done" | "confirm" | "request_rework" | "cancel";

export type TaskTransitionInput = {
  expected_version: number;
  action: TaskTransitionAction;
  note?: string;
  media_ids?: string[];
};

export type ScopedAcceptInput = { expected_version: number; claimed_name: string };
export type ScopedTaskDoneInput = {
  expected_version: number;
  claimed_name: string;
  note?: string;
  media_ids?: string[];
};

export type TaskTransitionAck = {
  event_id: string;
  task_id: string;
  state: TaskState;
  version: number;
  replayed: boolean;
};

export type TaskTransitionActor = "task.manage" | "scoped_link";
export type TaskTransitionErrors = Partial<Record<"expected_version" | "action" | "note" | "claimed_name" | "media_ids" | "transition", string>>;

const transitions: Record<TaskTransitionAction, readonly TaskState[]> = {
  accept: ["open"],
  report_done: ["open", "accepted"],
  confirm: ["reported_done"],
  request_rework: ["reported_done"],
  cancel: ["open", "accepted", "reported_done"],
};

export function validateTaskTransition(
  input: TaskTransitionInput,
  state: TaskState,
  actor: TaskTransitionActor,
  scopedClaimedName?: string,
): TaskTransitionErrors {
  const errors: TaskTransitionErrors = {};
  if (!Number.isSafeInteger(input.expected_version) || input.expected_version < 1) {
    errors.expected_version = "Gözlənilən versiya müsbət tam ədəd olmalıdır.";
  }
  if (!transitions[input.action]) {
    errors.action = "Tapşırıq əməliyyatı tanınmır.";
    return errors;
  }
  if (!transitions[input.action].includes(state)) {
    errors.transition = "Tapşırıq bu vəziyyətdən həmin əməliyyata keçə bilməz.";
  }
  if (actor === "scoped_link" && !["accept", "report_done"].includes(input.action)) {
    errors.action = "Keçid bu tapşırıq keçidi üçün icazəli deyil.";
  }
  if (actor === "task.manage" && scopedClaimedName !== undefined) {
    errors.claimed_name = "Bildirən ad yalnız scoped keçiddə qəbul edilir.";
  }
  if (actor === "scoped_link" && ["accept", "report_done"].includes(input.action)
      && (!scopedClaimedName || scopedClaimedName.trim().length < 1 || scopedClaimedName.trim().length > 100)) {
    errors.claimed_name = "Bildirən adı 1–100 simvol arasında yazın.";
  }
  if (input.action === "request_rework" && (!input.note || input.note.trim().length < 1 || input.note.length > 2000)) {
    errors.note = "Yenidən baxış səbəbini 1–2000 simvol arasında yazın.";
  } else if (input.note !== undefined && input.note.length > 2000) {
    errors.note = "Qeyd ən çox 2000 simvol ola bilər.";
  }
  if (input.media_ids !== undefined && (!Array.isArray(input.media_ids) || input.media_ids.length > 20
      || new Set(input.media_ids).size !== input.media_ids.length || input.media_ids.some((id) => !isUuid(id)))) {
    errors.media_ids = "Ən çox 20 fərqli media identifikatoru seçin.";
  }
  return errors;
}

export function validateTaskIdempotencyKey(value: string): boolean {
  return /^[A-Za-z0-9_-]{16,128}$/.test(value);
}

export function parseTaskTransitionAck(value: unknown): TaskTransitionAck {
  if (!isRecord(value) || !hasOnlyKeys(value, ["event_id", "task_id", "state", "version", "replayed"])
      || !isUuid(value.event_id) || !isUuid(value.task_id) || !isTaskState(value.state)
      || !Number.isSafeInteger(value.version) || (value.version as number) < 2
      || typeof value.replayed !== "boolean") {
    throw new TypeError("invalid_task_transition_ack");
  }
  return value as TaskTransitionAck;
}

function isTaskState(value: unknown): value is TaskState {
  return value === "open" || value === "accepted" || value === "reported_done"
    || value === "completed" || value === "cancelled";
}
function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
function hasOnlyKeys(value: Record<string, unknown>, allowed: readonly string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}
