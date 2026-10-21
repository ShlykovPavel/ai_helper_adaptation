#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-qqueue.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AskQuestion.swift \
    NotchBuddy/Sources/App/ApprovalQueue.swift \
    NotchBuddy/Sources/App/QuestionQueue.swift \
    tests/QuestionQueueTests.swift -o "$TEST_DIR/qqueue-tests"
"$TEST_DIR/qqueue-tests"
