#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-tunnelguard-phase1-safe.XXXXXX")"
export TUNNELGUARD_TEST_MODE=1

STATE_FILE="$HOME/Library/Application Support/NotchBuddy/tunnelguard-state.json"
BEFORE_HASH=""
if [ -f "$STATE_FILE" ]; then
    BEFORE_HASH="$(shasum -a 256 "$STATE_FILE" | awk '{print $1}')"
fi

cleanup() {
    rm -rf "$TEST_DIR"
    AFTER_HASH=""
    if [ -f "$STATE_FILE" ]; then
        AFTER_HASH="$(shasum -a 256 "$STATE_FILE" | awk '{print $1}')"
    fi
    if [ "$BEFORE_HASH" != "$AFTER_HASH" ]; then
        echo "❌ FATAL: Real state file was modified during tests!" >&2
        echo "Before SHA256: $BEFORE_HASH" >&2
        echo "After SHA256:  $AFTER_HASH" >&2
        exit 1
    fi
}
trap cleanup EXIT

CACHE_ARGS=()
if [ -d "NotchBuddy/build/ModuleCache.noindex" ]; then
    CACHE_ARGS=(-module-cache-path "NotchBuddy/build/ModuleCache.noindex")
fi

swiftc -swift-version 6 -strict-concurrency=complete "${CACHE_ARGS[@]+"${CACHE_ARGS[@]}"}" \
    NotchBuddy/Sources/App/TunnelGuardPowerGuard.swift \
    NotchBuddy/Sources/App/TunnelGuardNetworkWorker.swift \
    NotchBuddy/Sources/App/TunnelGuardAppHunter.swift \
    NotchBuddy/Sources/App/TunnelGuardWatchdog.swift \
    tests/TunnelGuardTestHelper.swift \
    tests/TunnelGuardPhase1SafeTests.swift -o "$TEST_DIR/tunnelguard-phase1-safe-tests"

"$TEST_DIR/tunnelguard-phase1-safe-tests"
