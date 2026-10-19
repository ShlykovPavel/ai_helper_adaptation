#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-telegram-controller.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc \
    NotchBuddy/Sources/App/AskQuestion.swift \
    NotchBuddy/Sources/App/Telegram/TelegramModels.swift \
    NotchBuddy/Sources/App/Telegram/TelegramActionRegistry.swift \
    NotchBuddy/Sources/App/Telegram/TelegramPairing.swift \
    NotchBuddy/Sources/App/Telegram/TelegramBotAPI.swift \
    NotchBuddy/Sources/App/Telegram/TelegramPolling.swift \
    NotchBuddy/Sources/App/Telegram/TelegramBotController.swift \
    tests/TelegramControllerTestStubs.swift \
    tests/TelegramControllerTests.swift -o "$TEST_DIR/telegram-controller-tests"
"$TEST_DIR/telegram-controller-tests"
