#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-agy-plan.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/ClaudePlanGauge.swift \
    NotchBuddy/Sources/App/AntigravityPlanGauge.swift \
    tests/AntigravityPlanGaugeTests.swift -o "$TEST_DIR/agy-plan-tests"
"$TEST_DIR/agy-plan-tests"
