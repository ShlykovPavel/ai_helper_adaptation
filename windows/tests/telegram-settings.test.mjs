// Unit tests for Windows/Linux Telegram settings UI.
// Verifies rendering, secret storage, test token, pairing, disconnect, toggles, and privacy.

import { afterEach, beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import { installFakeDom } from "./fakedom.mjs";
import { calls, internals, sent } from "./tauri.mjs";

installFakeDom();

const { telegramSection } = await import("../src/settings/telegram.ts");
const { DEFAULT_SETTINGS } = await import("../src/core/state.ts");

const settle = async (ticks = 5) => {
  for (let i = 0; i < ticks; i++) {
    await new Promise((resolve) => setImmediate(resolve));
  }
};

let statusMock = {
  enabled: false,
  tokenPresent: false,
  status: "stopped",
  pairedChatId: null,
  pairedBotUsername: null,
};

const originalInvoke = internals.invoke;

beforeEach(() => {
  calls.length = 0;
  statusMock = {
    enabled: false,
    tokenPresent: false,
    status: "stopped",
    pairedChatId: null,
    pairedBotUsername: null,
  };

  internals.invoke = async (cmd, args) => {
    calls.push([cmd, args]);
    if (cmd === "telegram_status") return statusMock;
    if (cmd === "telegram_test_token") {
      if (args.token === "invalid") throw new Error("401 Unauthorized");
      return "MyCoucouBot";
    }
    if (cmd === "telegram_new_pairing") {
      return "https://t.me/MyCoucouBot?start=testnonce123";
    }
    if (cmd === "telegram_disconnect") {
      statusMock.tokenPresent = false;
      statusMock.pairedChatId = null;
      statusMock.pairedBotUsername = null;
      statusMock.enabled = false;
      return null;
    }
    if (cmd === "secret_set") return null;
    if (cmd === "open_url") return null;
    if (cmd === "save_settings") return null;
    return null;
  };
});

afterEach(() => {
  internals.invoke = originalInvoke;
});

// ── Rendering & Initial State ────────────────────────────────────────────────

test("renders Telegram settings block with headers, guide, inputs, and not configured status", async () => {
  const present = {};
  const settings = { ...DEFAULT_SETTINGS };
  let saved = 0;
  const save = () => { saved++; };

  const section = telegramSection(present, settings, save);
  assert.ok(section, "telegramSection returned an element");

  // Header & description
  assert.match(section.textContent, /Telegram/);
  assert.match(section.textContent, /Connect your own Telegram bot/);

  // Guide
  assert.match(section.textContent, /How to create a bot/);
  assert.match(section.textContent, /1\. Open @BotFather in Telegram/);
  assert.match(section.textContent, /2\. Send \/newbot and choose a name and @username/);
  assert.match(section.textContent, /3\. Copy the HTTP API token and paste it below/);

  // Token input & placeholder
  const input = section.querySelector(".telegram-token-input");
  assert.ok(input, "token input found");
  assert.equal(input.getAttribute("type"), "password");
  assert.equal(input.placeholder, "Enter bot token from @BotFather");

  // Buttons
  const buttons = section.find("BUTTON");
  const buttonTexts = buttons.map((b) => b.textContent);
  assert.ok(buttonTexts.includes("Save"), "Save button present");
  assert.ok(buttonTexts.includes("Test token"), "Test token button present");

  await settle();

  // Initial status: Not configured
  assert.match(section.textContent, /Not configured/);

  // Notification checkboxes are present
  const finishedCb = section.querySelector(".cb-finished");
  const questionsCb = section.querySelector(".cb-questions");
  const approvalsCb = section.querySelector(".cb-approvals");
  assert.ok(finishedCb, "finished checkbox present");
  assert.ok(questionsCb, "questions checkbox present");
  assert.ok(approvalsCb, "approvals checkbox present");
});

test("shows (stored) placeholder when token is already present", async () => {
  const present = { "telegram-bot-token": true };
  const settings = { ...DEFAULT_SETTINGS };
  statusMock.tokenPresent = true;

  const section = telegramSection(present, settings, () => {});
  const input = section.querySelector(".telegram-token-input");
  assert.equal(input.placeholder, "(stored)");

  await settle();
  // With token present but not paired, shows awaiting pairing
  assert.match(section.textContent, /Awaiting pairing \(\/start\)/);
  assert.match(section.textContent, /Send \/start to the bot or open the link to pair\./);
});

// ── Token Storage & Testing ──────────────────────────────────────────────────

test("saving a token invokes secret_set, updates presence, clears input, and sets (stored)", async () => {
  const present = {};
  const settings = { ...DEFAULT_SETTINGS, telegramEnabled: false };
  let savedCount = 0;
  const save = () => { savedCount++; };
  const section = telegramSection(present, settings, save);

  const input = section.querySelector(".telegram-token-input");
  const saveBtn = section.querySelector(".telegram-save-btn");
  assert.ok(saveBtn, "save button found");

  input.value = "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11";
  input.fire("input");

  saveBtn.fire("click");
  await settle();

  // Verified secret_set called
  const secretCalls = sent("secret_set");
  assert.equal(secretCalls.length, 1);
  assert.equal(secretCalls[0].key, "telegram-bot-token");
  assert.equal(secretCalls[0].value, "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11");

  // Verified telegram_set_enabled called and settings.telegramEnabled activated
  assert.equal(settings.telegramEnabled, true);
  const setEnabledCalls = sent("telegram_set_enabled");
  assert.equal(setEnabledCalls.length, 1);
  assert.equal(setEnabledCalls[0].enabled, true);
  assert.ok(savedCount >= 1, "save() was called on token save");

  // Cleared input and updated placeholder
  assert.equal(input.value, "");
  assert.equal(input.placeholder, "(stored)");
  assert.equal(present["telegram-bot-token"], true);
  assert.match(section.textContent, /Saved\. Token stored securely\./);
});

test("testing a token invokes telegram_test_token and shows success", async () => {
  const present = { "telegram-bot-token": true };
  const settings = { ...DEFAULT_SETTINGS };
  const section = telegramSection(present, settings, () => {});

  const testBtn = section.querySelector(".telegram-test-btn");
  assert.ok(testBtn, "test button found");

  testBtn.fire("click");
  await settle();

  const testCalls = sent("telegram_test_token");
  assert.equal(testCalls.length, 1);
  assert.match(section.textContent, /✓ @MyCoucouBot/);
});

test("testing an invalid token shows sanitized error", async () => {
  const present = {};
  const settings = { ...DEFAULT_SETTINGS };
  const section = telegramSection(present, settings, () => {});

  const input = section.querySelector(".telegram-token-input");
  input.value = "invalid";
  input.fire("input");

  const testBtn = section.querySelector(".telegram-test-btn");
  testBtn.fire("click");
  await settle();

  assert.match(section.textContent, /401 Unauthorized/);
});

// ── Pairing & Deep Link ─────────────────────────────────────────────────────

test("clicking Pair invokes telegram_new_pairing and opens URL", async () => {
  const present = { "telegram-bot-token": true };
  statusMock.tokenPresent = true;
  statusMock.status = "polling";

  const section = telegramSection(present, { ...DEFAULT_SETTINGS }, () => {});
  await settle();

  const pairBtn = section.querySelector(".pair-btn");
  assert.ok(pairBtn, "pair button rendered when awaiting pairing");

  pairBtn.fire("click");
  await settle();

  assert.equal(sent("telegram_set_enabled").length, 1);
  assert.equal(sent("telegram_set_enabled")[0].enabled, true);

  const pairingCalls = sent("telegram_new_pairing");
  assert.equal(pairingCalls.length, 1);

  const openCalls = sent("open_url");
  assert.equal(openCalls.length, 1);
  assert.equal(openCalls[0].url, "https://t.me/MyCoucouBot?start=testnonce123");

  const linkInput = section.querySelector(".pairing-link-input");
  assert.ok(linkInput, "pairing link input displayed");
  assert.equal(linkInput.value, "https://t.me/MyCoucouBot?start=testnonce123");

  const copyBtn = section.querySelector(".copy-link-btn");
  assert.ok(copyBtn, "copy link button displayed");
});

// ── Connected / Paired State & Disconnect ────────────────────────────────────

test("displays connected status with bot username and masked chat id when paired", async () => {
  const present = { "telegram-bot-token": true };
  statusMock.tokenPresent = true;
  statusMock.pairedChatId = 123456789;
  statusMock.pairedBotUsername = "MyCoucouBot";

  const section = telegramSection(present, { ...DEFAULT_SETTINGS }, () => {});
  await settle();

  assert.match(section.textContent, /Connected/);
  assert.match(section.textContent, /Bot: @MyCoucouBot/);
  assert.match(section.textContent, /Chat: •••••6789/);

  const repairBtn = section.querySelector(".repair-btn");
  const disconnectBtn = section.querySelector(".disconnect-btn");
  assert.ok(repairBtn, "Re-pair button shown");
  assert.ok(disconnectBtn, "Disconnect button shown");
});

test("re-pair invokes telegram_new_pairing and open_url", async () => {
  const present = { "telegram-bot-token": true };
  statusMock.tokenPresent = true;
  statusMock.pairedChatId = 123456789;
  statusMock.pairedBotUsername = "MyCoucouBot";

  const section = telegramSection(present, { ...DEFAULT_SETTINGS }, () => {});
  await settle();

  const repairBtn = section.querySelector(".repair-btn");
  repairBtn.fire("click");
  await settle();

  assert.equal(sent("telegram_set_enabled").length, 1);
  assert.equal(sent("telegram_set_enabled")[0].enabled, true);
  assert.equal(sent("telegram_new_pairing").length, 1);
  assert.equal(sent("open_url").length, 1);
});

test("disconnect invokes telegram_disconnect, clears presence, resets settings, and updates status", async () => {
  const present = { "telegram-bot-token": true };
  const settings = {
    ...DEFAULT_SETTINGS,
    telegramEnabled: true,
    telegramPairedChatId: 123456789,
    telegramPairedBotUsername: "MyCoucouBot",
  };
  statusMock.tokenPresent = true;
  statusMock.pairedChatId = 123456789;
  statusMock.pairedBotUsername = "MyCoucouBot";

  let savedCount = 0;
  const save = () => { savedCount++; };

  const section = telegramSection(present, settings, save);
  await settle();

  const disconnectBtn = section.querySelector(".disconnect-btn");
  disconnectBtn.fire("click");
  await settle();

  assert.equal(sent("telegram_disconnect").length, 1);
  assert.equal(present["telegram-bot-token"], false);
  assert.equal(settings.telegramEnabled, false);
  assert.equal(settings.telegramPairedChatId, null);
  assert.equal(settings.telegramPairedBotUsername, null);
  assert.ok(savedCount >= 1, "save() was called on disconnect");

  // Status becomes Not configured
  assert.match(section.textContent, /Not configured/);
});

// ── Notification Toggles & activeIntegrations Independence ───────────────────

test("notification checkboxes toggle independently and invoke save()", async () => {
  const present = {};
  const settings = {
    ...DEFAULT_SETTINGS,
    telegramNotifyFinished: true,
    telegramNotifyQuestions: true,
    telegramNotifyApprovals: true,
    activeIntegrations: ["integration_github", "integration_stripe"],
  };

  let saved = 0;
  const save = () => { saved++; };

  const section = telegramSection(present, settings, save);

  const finishedCb = section.querySelector(".cb-finished");
  const questionsCb = section.querySelector(".cb-questions");
  const approvalsCb = section.querySelector(".cb-approvals");

  assert.equal(finishedCb.checked, true);
  assert.equal(questionsCb.checked, true);
  assert.equal(approvalsCb.checked, true);

  // Toggle finished
  finishedCb.checked = false;
  finishedCb.fire("change");
  assert.equal(settings.telegramNotifyFinished, false);
  assert.equal(saved, 1);

  // Toggle questions
  questionsCb.checked = false;
  questionsCb.fire("change");
  assert.equal(settings.telegramNotifyQuestions, false);
  assert.equal(saved, 2);

  // Toggle approvals
  approvalsCb.checked = false;
  approvalsCb.fire("change");
  assert.equal(settings.telegramNotifyApprovals, false);
  assert.equal(saved, 3);

  // Crucial: activeIntegrations is completely untouched!
  assert.deepEqual(settings.activeIntegrations, ["integration_github", "integration_stripe"]);
});

// ── Privacy & Security ───────────────────────────────────────────────────────

test("bot token is write-only password field and is never leaked to DOM text", async () => {
  const present = {};
  const settings = { ...DEFAULT_SETTINGS };
  const section = telegramSection(present, settings, () => {});

  const secretToken = "999888:SecretBotTokenNeverInLogs";
  const input = section.querySelector(".telegram-token-input");
  input.value = secretToken;
  input.fire("input");

  const saveBtn = section.querySelector(".telegram-save-btn");
  saveBtn.fire("click");
  await settle();

  // Check the text content of the whole section
  assert.ok(!section.textContent.includes(secretToken), "raw token never appears in section textContent");
  // Check input value was cleared
  assert.equal(input.value, "", "input value was cleared after save");
});

test("shows error badge on unauthorized or conflict status", async () => {
  const present = { "telegram-bot-token": true };

  // 1. Unauthorized
  statusMock.tokenPresent = true;
  statusMock.status = "unauthorized";
  let section = telegramSection(present, { ...DEFAULT_SETTINGS }, () => {});
  await settle();
  assert.match(section.textContent, /Invalid bot token\. Check token in BotFather\./);

  // 2. Conflict
  statusMock.status = "conflict";
  section = telegramSection(present, { ...DEFAULT_SETTINGS }, () => {});
  await settle();
  assert.match(section.textContent, /Another Coucou or bot instance is using this token\./);
});
