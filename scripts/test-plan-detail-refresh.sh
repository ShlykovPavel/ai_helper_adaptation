#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-plan-detail-refresh.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/CoucouKit/ColorHex.swift \
    NotchBuddy/Sources/App/ClaudePlanGauge.swift \
    NotchBuddy/Sources/App/AntigravityPlanGauge.swift \
    NotchBuddy/Sources/App/CodexPlanGauge.swift \
    NotchBuddy/Sources/App/ClaudePlanCardView.swift \
    NotchBuddy/Sources/App/AntigravityPlanCardView.swift \
    tests/PlanDetailRefreshTests.swift -o "$TEST_DIR/plan-detail-refresh-tests"
"$TEST_DIR/plan-detail-refresh-tests"
