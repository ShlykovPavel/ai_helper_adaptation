#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-tunnelguard-watchdog.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
CACHE_ARGS=()
if [ -d "NotchBuddy/build/ModuleCache.noindex" ]; then
    CACHE_ARGS=(-module-cache-path "NotchBuddy/build/ModuleCache.noindex")
fi

swiftc -swift-version 6 -strict-concurrency=complete "${CACHE_ARGS[@]}" \
    NotchBuddy/Sources/App/TunnelGuardPowerGuard.swift \
    NotchBuddy/Sources/App/TunnelGuardNetworkWorker.swift \
    NotchBuddy/Sources/App/TunnelGuardAppHunter.swift \
    NotchBuddy/Sources/App/TunnelGuardWatchdog.swift \
    tests/TunnelGuardWatchdogTests.swift -o "$TEST_DIR/tunnelguard-watchdog-tests"
"$TEST_DIR/tunnelguard-watchdog-tests"
