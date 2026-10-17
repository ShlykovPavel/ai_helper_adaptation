import { Bridge, type TelegramStatusResponse } from "../core/bridge";
import type { Settings } from "../core/state";
import { h } from "../views/dom";
import { t } from "../i18n/i18n";

export function telegramSection(
  present: Record<string, boolean>,
  settings: Settings,
  save: () => Promise<void> | void,
): HTMLElement {
  const section = h("section", { class: "telegram-section" });

  // 1. Header
  const header = h("h2", {},
    h("span", { class: "telegram-dot", style: "background:#0088cc" }),
    h("span", { text: t("Telegram") }),
  );

  // 2. Description
  const description = h("div", {
    class: "hint",
    text: t("Connect your own Telegram bot. Coucou connects directly from this computer to send completions and answer questions."),
  });

  // 3. Collapsible BotFather guide
  const guideSummary = h("summary", { text: t("How to create a bot") });
  const step1 = h("div", { class: "telegram-guide-step", style: "cursor:pointer" },
    h("span", { text: t("1. Open @BotFather in Telegram") }),
  );
  step1.addEventListener("click", () => {
    void Bridge.openUrl("https://t.me/BotFather");
  });

  const step2 = h("div", {
    class: "telegram-guide-step",
    text: t("2. Send /newbot and choose a name and @username"),
  });
  const step3 = h("div", {
    class: "telegram-guide-step",
    text: t("3. Copy the HTTP API token and paste it below"),
  });

  const guide = h("details", { class: "telegram-guide" },
    guideSummary,
    h("div", { class: "telegram-guide-steps" }, step1, step2, step3),
  );

  // 4. Token input row
  const tokenLabel = h("label", { text: t("Bot Token") });
  const tokenInput = h("input", {
    type: "password",
    class: "telegram-token-input",
    placeholder: present["telegram-bot-token"] ? t("(stored)") : t("Enter bot token from @BotFather"),
    autocomplete: "off",
    spellcheck: "false",
    style: "flex:1 1 auto;min-width:0",
  }) as HTMLInputElement;

  tokenInput.value = "";
  tokenInput.placeholder = present["telegram-bot-token"] ? t("(stored)") : t("Enter bot token from @BotFather");

  const saveBtn = h("button", { class: "telegram-save-btn", text: t("Save") });
  const testBtn = h("button", { class: "telegram-test-btn", text: t("Test token") });
  const feedback = h("div", { class: "hint telegram-feedback" });

  function updateTestBtnDisabled() {
    const hasInput = (tokenInput.value ?? "").trim().length > 0;
    const hasStored = present["telegram-bot-token"] ?? false;
    testBtn.disabled = !hasInput && !hasStored;
  }
  tokenInput.addEventListener("input", updateTestBtnDisabled);
  updateTestBtnDisabled();

  const tokenRow = h("div", { class: "row" }, tokenLabel, tokenInput, saveBtn, testBtn);

  // 5. Status & pairing block
  const statusBlock = h("div", { class: "telegram-status-block", style: "display:flex;flex-direction:column;gap:8px" });

  // 6. Notification toggles block
  const togglesBlock = h("div", { class: "telegram-toggles", style: "display:flex;flex-direction:column;gap:6px" });

  function makeCheckbox(
    checked: boolean,
    notifyKey: "finished" | "questions" | "approvals",
    labelText: string,
    onChange: (val: boolean) => void,
  ) {
    const input = h("input", {
      type: "checkbox",
      class: `telegram-checkbox cb-${notifyKey}`,
      "data-notify": notifyKey,
    }) as HTMLInputElement;
    input.checked = checked;
    if (checked) input.setAttribute("checked", "true");

    const onToggle = () => {
      if ("fire" in input) {
        input.checked = !input.checked;
      }
      if (input.checked) input.setAttribute("checked", "true");
      else input.removeAttribute("checked");
      onChange(input.checked);
    };

    input.addEventListener("change", () => {
      if (input.checked) input.setAttribute("checked", "true");
      else input.removeAttribute("checked");
      onChange(input.checked);
    });
    input.addEventListener("click", onToggle);

    const label = h("label", { class: "telegram-checkbox-row", style: "display:flex;align-items:center;gap:8px;cursor:pointer" },
      input,
      h("span", { text: labelText }),
    );
    return { label, input };
  }

  const finishedCb = makeCheckbox(
    settings.telegramNotifyFinished ?? true,
    "finished",
    t("Completions and stops"),
    (val) => {
      settings.telegramNotifyFinished = val;
      void save();
    },
  );

  const questionsCb = makeCheckbox(
    settings.telegramNotifyQuestions ?? true,
    "questions",
    t("Questions"),
    (val) => {
      settings.telegramNotifyQuestions = val;
      void save();
    },
  );

  const approvalsCb = makeCheckbox(
    settings.telegramNotifyApprovals ?? true,
    "approvals",
    t("Approvals"),
    (val) => {
      settings.telegramNotifyApprovals = val;
      void save();
    },
  );

  togglesBlock.append(finishedCb.label, questionsCb.label, approvalsCb.label);

  // 7. Actions block (Re-pair and Disconnect)
  const actionsBlock = h("div", { class: "row telegram-actions", style: "gap:8px" });
  const repairBtn = h("button", { class: "repair-btn", text: t("Re-pair") });
  const disconnectBtn = h("button", { class: "disconnect-btn", text: t("Disconnect") });
  actionsBlock.append(repairBtn, disconnectBtn);

  // Status drawing function
  async function refresh() {
    statusBlock.replaceChildren();

    let res: TelegramStatusResponse | null = null;
    try {
      res = await Bridge.telegramStatus();
    } catch {
      // Mock or call failed
    }

    const tokenPresent = (res?.tokenPresent ?? false) || (present["telegram-bot-token"] ?? false);
    const status = res?.status;
    const pairedChatId = res?.pairedChatId ?? settings.telegramPairedChatId ?? null;
    const pairedBotUsername = res?.pairedBotUsername ?? settings.telegramPairedBotUsername ?? null;

    updateTestBtnDisabled();

    if (!tokenPresent && !pairedChatId) {
      statusBlock.append(
        h("div", { class: "row status-row" },
          h("label", { text: t("Status") }),
          h("span", { class: "badge secondary", text: t("Not configured") }),
        ),
      );
      actionsBlock.style.display = "none";
      return;
    }

    if (status === "unauthorized") {
      statusBlock.append(
        h("div", { class: "row status-row" },
          h("label", { text: t("Status") }),
          h("span", { class: "badge error", text: t("Invalid bot token. Check token in BotFather.") }),
        ),
      );
      actionsBlock.style.display = "flex";
      repairBtn.style.display = "none";
      disconnectBtn.style.display = "";
      return;
    }

    if (status === "conflict") {
      statusBlock.append(
        h("div", { class: "row status-row" },
          h("label", { text: t("Status") }),
          h("span", { class: "badge error", text: t("Another Coucou or bot instance is using this token.") }),
        ),
      );
      actionsBlock.style.display = "flex";
      repairBtn.style.display = "none";
      disconnectBtn.style.display = "";
      return;
    }

    if (pairedChatId) {
      const maskedChat = String(pairedChatId).length > 4
        ? "•••••" + String(pairedChatId).slice(-4)
        : String(pairedChatId);

      statusBlock.append(
        h("div", { class: "row status-row" },
          h("label", { text: t("Status") }),
          h("span", { class: "badge success", text: t("Connected") }),
          ...(pairedBotUsername ? [h("span", { class: "hint bot-user", text: t("Bot: @{username}", { username: pairedBotUsername }) })] : []),
          h("span", { class: "hint chat-id", text: t("Chat: {chatId}", { chatId: maskedChat }) }),
        ),
      );
      actionsBlock.style.display = "flex";
      repairBtn.style.display = "";
      disconnectBtn.style.display = "";
    } else {
      // Awaiting pairing
      const pairBtn = h("button", { class: "pair-btn primary", text: t("Pair") });
      const pairingBox = h("div", { class: "pairing-link-box" });

      pairBtn.addEventListener("click", async () => {
        try {
          const url = await Bridge.telegramNewPairing();
          void Bridge.openUrl(url);

          const linkInput = h("input", {
            type: "text",
            readonly: "true",
            value: url,
            class: "pairing-link-input",
            style: "flex:1 1 auto;min-width:0",
          }) as HTMLInputElement;
          linkInput.value = url;

          const copyBtn = h("button", { class: "copy-link-btn", text: t("Copy link") });
          copyBtn.addEventListener("click", () => {
            void navigator.clipboard?.writeText(url).then(() => {
              copyBtn.textContent = t("Copied");
              setTimeout(() => {
                copyBtn.textContent = t("Copy link");
              }, 1500);
            });
          });

          pairingBox.replaceChildren(
            h("div", { class: "row", style: "gap:8px;margin-top:6px" }, linkInput, copyBtn),
          );
        } catch (err) {
          feedback.textContent = String(err);
          feedback.className = "hint error";
        }
      });

      statusBlock.append(
        h("div", { class: "row status-row" },
          h("label", { text: t("Status") }),
          h("span", { class: "badge warning", text: t("Awaiting pairing (/start)") }),
        ),
        h("div", { class: "hint", text: t("Send /start to the bot or open the link to pair.") }),
        h("div", { class: "row" }, pairBtn),
        pairingBox,
      );

      actionsBlock.style.display = "flex";
      repairBtn.style.display = "none";
      disconnectBtn.style.display = "";
    }
  }

  // Token save handler
  saveBtn.addEventListener("click", async () => {
    const val = (tokenInput.value ?? "").trim();
    if (!val) return;
    try {
      await Bridge.secretSet("telegram-bot-token", val);
      present["telegram-bot-token"] = true;
      tokenInput.value = "";
      tokenInput.placeholder = t("(stored)");
      feedback.textContent = t("Saved. Token stored securely.");
      feedback.className = "hint success";
      await refresh();
    } catch (err) {
      feedback.textContent = String(err);
      feedback.className = "hint error";
    }
  });

  // Token test handler
  testBtn.addEventListener("click", async () => {
    const val = (tokenInput.value ?? "").trim();
    testBtn.disabled = true;
    testBtn.textContent = t("Testing…");
    try {
      const name = await Bridge.telegramTestToken(val);
      feedback.textContent = `✓ @${name}`;
      feedback.className = "hint success";
      await refresh();
    } catch (err) {
      feedback.textContent = String(err);
      feedback.className = "hint error";
    } finally {
      testBtn.disabled = false;
      testBtn.textContent = t("Test token");
    }
  });

  // Re-pair handler
  repairBtn.addEventListener("click", async () => {
    try {
      const url = await Bridge.telegramNewPairing();
      void Bridge.openUrl(url);
      await refresh();
    } catch (err) {
      feedback.textContent = String(err);
      feedback.className = "hint error";
    }
  });

  // Disconnect handler
  disconnectBtn.addEventListener("click", async () => {
    try {
      await Bridge.telegramDisconnect();
      present["telegram-bot-token"] = false;
      tokenInput.value = "";
      tokenInput.placeholder = t("Enter bot token from @BotFather");
      settings.telegramEnabled = false;
      settings.telegramPairedChatId = null;
      settings.telegramPairedUserId = null;
      settings.telegramPairedBotUsername = null;
      settings.telegramPairingNonce = null;
      settings.telegramPairingExpiresAt = null;
      feedback.textContent = "";
      await save();
      await refresh();
    } catch (err) {
      feedback.textContent = String(err);
      feedback.className = "hint error";
    }
  });

  // Initial draw
  void refresh();

  section.append(
    header,
    description,
    guide,
    tokenRow,
    feedback,
    statusBlock,
    togglesBlock,
    actionsBlock,
  );

  return section;
}
