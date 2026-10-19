#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
RESOURCE_DIR="${ASTRAL_IDLE_RESOURCE_DIR:-NotchBuddy/Resources/Mascots/AstralIdle}"
if [[ ! -f "$RESOURCE_DIR/atlas.json" ]]; then
    echo "FAIL: saved idle animation is missing from native resources"
    exit 1
fi
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/astral-idle.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/AstralIdleAnimation.swift \
    tests/AstralIdleTests.swift -o "$TEST_DIR/idle-tests"
"$TEST_DIR/idle-tests" "$RESOURCE_DIR" design/mascot/astral-v2/animations/are-you-still-here-v2 "${ASTRAL_IDLE_RENDER:-$TEST_DIR/native-idle.png}"
