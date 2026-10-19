#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-codex.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
# The gauge model is compiled separately from its SwiftUI card for these tests.
sed '/\/\/ MARK: - Codex Plan Card View/,$d' NotchBuddy/Sources/App/CodexPlanGauge.swift > "$TEST_DIR/CodexPlanGauge.swift"
printf '\n#endif\n' >> "$TEST_DIR/CodexPlanGauge.swift"
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/ClaudePlanGauge.swift \
    "$TEST_DIR/CodexPlanGauge.swift" \
    NotchBuddy/Sources/App/AskQuestion.swift \
    tests/CodexIntegrationTests.swift -o "$TEST_DIR/codex-tests"
"$TEST_DIR/codex-tests"
