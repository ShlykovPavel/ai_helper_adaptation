#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-concurrency.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AskQuestion.swift \
    NotchBuddy/Sources/App/QuestionQueue.swift \
    NotchBuddy/Sources/App/ApprovalQueue.swift \
    NotchBuddy/Sources/CoucouKit/PillCatalog.swift \
    NotchBuddy/Sources/CoucouKit/PillColors.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    tests/MultiAgentConcurrencyE2ETests.swift -o "$TEST_DIR/concurrency-tests"
"$TEST_DIR/concurrency-tests"
