import assert from "node:assert/strict";
import test from "node:test";
import {
  parseTaskTransitionAck,
  validateTaskIdempotencyKey,
  validateTaskTransition,
  type TaskTransitionInput,
} from "../../../src/modules/operations/task-transition-contract.ts";

const mediaId = "f3000000-0000-0000-0000-000000000011";
const manager: TaskTransitionInput = { expected_version: 2, action: "request_rework", note: "Foto bulanıqdır" };

test("task transition state and capability rules match the documented machine", () => {
  assert.deepEqual(validateTaskTransition({ expected_version: 1, action: "accept" }, "open", "scoped_link", "Usta"), {});
  assert.deepEqual(validateTaskTransition({ expected_version: 1, action: "report_done", note: "Hazırdır", media_ids: [mediaId] }, "accepted", "scoped_link", "Usta"), {});
  assert.deepEqual(validateTaskTransition(manager, "reported_done", "task.manage"), {});
  assert.ok(validateTaskTransition({ expected_version: 1, action: "confirm" }, "accepted", "task.manage").transition);
  assert.ok(validateTaskTransition({ expected_version: 1, action: "cancel" }, "completed", "task.manage").transition);
  assert.ok(validateTaskTransition({ expected_version: 1, action: "request_rework" }, "reported_done", "task.manage").note);
  assert.ok(validateTaskTransition({ expected_version: 1, action: "confirm" }, "reported_done", "scoped_link").action);
});

test("media list, claimed identity, and idempotency key are bounded", () => {
  assert.ok(validateTaskTransition({ expected_version: 1, action: "accept" }, "open", "scoped_link").claimed_name);
  assert.ok(validateTaskTransition({ expected_version: 1, action: "report_done", media_ids: [mediaId, mediaId] }, "accepted", "task.manage").media_ids);
  assert.ok(validateTaskTransition({ expected_version: 1, action: "report_done", media_ids: Array.from({ length: 21 }, (_, index) => `f3000000-0000-0000-0000-${String(index + 1).padStart(12, "0")}`) }, "accepted", "task.manage").media_ids);
  assert.equal(validateTaskIdempotencyKey("task-transition-key-01"), true);
  assert.equal(validateTaskIdempotencyKey("short"), false);
});

test("transition acknowledgements are strict and contain no raw task details", () => {
  const ack = {
    event_id: "f4000000-0000-0000-0000-000000000011",
    task_id: "f5000000-0000-0000-0000-000000000011",
    state: "reported_done",
    version: 3,
    replayed: false,
  };
  assert.equal(parseTaskTransitionAck(ack).state, "reported_done");
  assert.throws(() => parseTaskTransitionAck({ ...ack, title: "private title" }), /invalid_task_transition_ack/);
  assert.throws(() => parseTaskTransitionAck({ ...ack, version: 1 }), /invalid_task_transition_ack/);
});
