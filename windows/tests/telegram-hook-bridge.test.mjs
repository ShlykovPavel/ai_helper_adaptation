// Integration and unit tests for Telegram hook bridge and island approval flow.
// Verifies hook events, pending card lifecycle, remote resolution, and Bridge contracts.

import { afterEach, beforeEach, mock, test } from "node:test";
import assert from "node:assert/strict";
import { calls, emit, sent } from "./tauri.mjs";
import { registerHookHandlers, dropPendingCard } from "../src/island/hooks.ts";
import { DEFAULT_SETTINGS, State } from "../src/core/state.ts";
import { Bridge } from "../src/core/bridge.ts";

const CLAUDE = "integration_claude";

let asked = [];
const island = {
  alert: (view) => {
    State.view = view;
    asked.push(`alert:${view}`);
  },
  setView: (view) => {
    State.view = view;
    asked.push(`setView:${view}`);
  },
  reveal: () => asked.push("reveal"),
  dropPin: () => asked.push("dropPin"),
};
registerHookHandlers(island);

const hook = (payload) => emit("hook", payload);

beforeEach(() => {
  mock.timers.enable({ apis: ["setTimeout"] });
  asked = [];
  calls.length = 0;
  State.tasks = [];
  State.focusId = null;
  State.mode = "hidden";
  State.view = "overview";
  State.paused = false;
  State.isPinned = false;
  State.pendingApproval = null;
  State.settings = { ...DEFAULT_SETTINGS };
  State.loadIntegrationTasks();
});

afterEach(() => {
  mock.timers.runAll();
  mock.timers.reset();
});

// ── Hook Events & Notifications ─────────────────────────────────────────────

test("Stop hook event updates task state, finalLine and is alerted", () => {
  hook({
    hook_event_name: "Stop",
    session_id: "s1",
    last_assistant_message: "Turn completed successfully. All tests pass.",
  });
  const t = State.tasks.find((x) => x.id === CLAUDE);
  assert.equal(t.state, "finished");
  assert.equal(t.finalLine, "Turn completed successfully. All tests pass.");
  assert.deepEqual(t.steps, ["Turn completed successfully. All tests pass."]);
  assert.deepEqual(asked, ["alert:finished"]);
});

test("PermissionRequest registers request id, sets state and sends approvalAck", () => {
  hook({
    hook_event_name: "PermissionRequest",
    request_id: "pr-100",
    session_id: "s1",
    tool_name: "Bash",
    tool_input: { command: "cargo test" },
  });
  assert.deepEqual(State.pendingApproval, {
    requestId: "pr-100",
    sessionId: "s1",
    pillId: CLAUDE,
    tool: "Bash",
    command: "Bash · cargo test",
  });
  assert.deepEqual(sent("approval_ack"), [{ requestId: "pr-100" }]);
  assert.deepEqual(sent("approval_decline"), []);
  assert.deepEqual(asked, ["alert:approval"]);
});

// ── Single Card & Duplicate Request Protection ──────────────────────────────

test("When approval card is on screen, duplicate requests are declined", () => {
  hook({
    hook_event_name: "PermissionRequest",
    request_id: "pr-1",
    session_id: "s1",
    tool_name: "Bash",
    tool_input: { command: "npm test" },
  });
  assert.equal(State.pendingApproval?.requestId, "pr-1");
  calls.length = 0;

  hook({
    hook_event_name: "PermissionRequest",
    request_id: "pr-2",
    session_id: "s2",
    tool_name: "Bash",
    tool_input: { command: "ls -la" },
  });
  assert.equal(State.pendingApproval?.requestId, "pr-1");
  assert.deepEqual(sent("approval_decline"), [{ requestId: "pr-2" }]);
  assert.deepEqual(sent("approval_ack"), []);
});

test("When question card is on screen, duplicate requests are declined", () => {
  hook({
    hook_event_name: "PermissionRequest",
    request_id: "q-1",
    session_id: "s1",
    tool_name: "AskUserQuestion",
    tool_input: {
      questions: [
        {
          question: "Continue?",
          header: "Confirmation",
          options: [{ label: "Yes" }, { label: "No" }],
        },
      ],
    },
  });
  assert.equal(State.pendingApproval?.requestId, "q-1");
  assert.ok(State.pendingApproval?.questions);
  calls.length = 0;

  hook({
    hook_event_name: "PermissionRequest",
    request_id: "pr-dup",
    session_id: "s2",
    tool_name: "Bash",
    tool_input: { command: "pwd" },
  });
  assert.equal(State.pendingApproval?.requestId, "q-1");
  assert.deepEqual(sent("approval_decline"), [{ requestId: "pr-dup" }]);
});

// ── Question Options and Headers Preservation ───────────────────────────────

test("Questions preserve all options, descriptions, headers and multiSelect", () => {
  hook({
    hook_event_name: "PermissionRequest",
    request_id: "q-full",
    session_id: "s1",
    tool_name: "AskUserQuestion",
    tool_input: {
      questions: [
        {
          question: "Select target platform",
          header: "Target OS",
          options: [
            { label: "Linux", description: "Ubuntu 24.04" },
            { label: "Windows", description: "Windows 11" },
            { label: "macOS", description: "macOS Sonoma" },
          ],
          multiSelect: true,
        },
      ],
    },
  });
  const q = State.pendingApproval?.questions?.[0];
  assert.ok(q);
  assert.equal(q.question, "Select target platform");
  assert.equal(q.header, "Target OS");
  assert.equal(q.multiSelect, true);
  assert.deepEqual(q.options, [
    { label: "Linux", description: "Ubuntu 24.04" },
    { label: "Windows", description: "Windows 11" },
    { label: "macOS", description: "macOS Sonoma" },
  ]);
});

// ── Bridge Decisions & Remote Cleanups ──────────────────────────────────────

test("Answering via bridge invokes approvalDecision and dropPendingCard clears card", async () => {
  hook({
    hook_event_name: "PermissionRequest",
    request_id: "pr-ans",
    session_id: "s1",
    tool_name: "Bash",
    tool_input: { command: "git push" },
  });
  assert.equal(State.pendingApproval?.requestId, "pr-ans");
  await Bridge.approvalDecision("pr-ans", "allow");
  assert.deepEqual(sent("approval_decision"), [{ requestId: "pr-ans", decision: "allow" }]);
  dropPendingCard(island);
  assert.equal(State.pendingApproval, null);
  assert.deepEqual(asked.slice(-1), ["setView:overview"]);
});

test("Answering question via bridge invokes approvalAnswer and dropPendingCard clears card", async () => {
  hook({
    hook_event_name: "PermissionRequest",
    request_id: "q-ans",
    session_id: "s1",
    tool_name: "AskUserQuestion",
    tool_input: {
      questions: [
        {
          question: "Color?",
          options: [{ label: "Blue" }, { label: "Red" }],
        },
      ],
    },
  });
  await Bridge.approvalAnswer("q-ans", { "Color?": "Blue" });
  assert.deepEqual(sent("approval_answer"), [{ requestId: "q-ans", answers: { "Color?": "Blue" } }]);
  dropPendingCard(island);
  assert.equal(State.pendingApproval, null);
});

test("Remote decision completed tool via PostToolUse cleanly clears pending approval card", () => {
  hook({
    hook_event_name: "PermissionRequest",
    request_id: "pr-remote",
    session_id: "sess-remote",
    tool_name: "Bash",
    tool_input: { command: "make test" },
  });
  assert.equal(State.pendingApproval?.requestId, "pr-remote");
  // Terminal or Telegram answers remotely -> tool runs -> PostToolUse arrives
  hook({
    hook_event_name: "PostToolUse",
    session_id: "sess-remote",
    tool_name: "Bash",
    tool_input: { command: "make test" },
  });
  assert.equal(State.pendingApproval, null);
});

test("Remote decision completed turn via Stop cleanly clears pending approval card", () => {
  hook({
    hook_event_name: "PermissionRequest",
    request_id: "pr-remote-stop",
    session_id: "sess-remote-stop",
    tool_name: "Bash",
    tool_input: { command: "make test" },
  });
  assert.equal(State.pendingApproval?.requestId, "pr-remote-stop");
  hook({
    hook_event_name: "Stop",
    session_id: "sess-remote-stop",
    last_assistant_message: "Done with task",
  });
  assert.equal(State.pendingApproval, null);
});

test("Paused island declines permission request immediately without opening card", () => {
  State.paused = true;
  hook({
    hook_event_name: "PermissionRequest",
    request_id: "pr-paused",
    session_id: "s1",
    tool_name: "Bash",
  });
  assert.deepEqual(sent("approval_decline"), [{ requestId: "pr-paused" }]);
  assert.equal(State.pendingApproval, null);
});
