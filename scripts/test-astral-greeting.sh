#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
RESOURCE_DIR="NotchBuddy/Resources/Mascots/AstralGreeting"
if [[ ! -f "$RESOURCE_DIR/rig.json" ]]; then
    echo "FAIL: accepted Astral greeting is missing from native resources"
    exit 1
fi
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/astral-greeting.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/AstralGreetingAnimation.swift \
    tests/AstralGreetingTests.swift -o "$TEST_DIR/greeting-tests"
"$TEST_DIR/greeting-tests" "$RESOURCE_DIR" tests/fixtures/astral-greeting/browser-poses.json "${ASTRAL_GREETING_RENDER:-$TEST_DIR/native-preview.png}"
