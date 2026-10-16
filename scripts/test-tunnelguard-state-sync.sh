#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-tunnelguard-state-sync.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
CACHE_ARGS=()
if [ -d "NotchBuddy/build/ModuleCache.noindex" ]; then
    CACHE_ARGS=(-module-cache-path "NotchBuddy/build/ModuleCache.noindex")
fi

swiftc -swift-version 6 -strict-concurrency=complete "${CACHE_ARGS[@]+"${CACHE_ARGS[@]}"}" \
    NotchBuddy/Sources/App/TunnelGuardPowerGuard.swift \
    NotchBuddy/Sources/App/TunnelGuardNetworkWorker.swift \
    NotchBuddy/Sources/App/TunnelGuardAppHunter.swift \
    NotchBuddy/Sources/App/TunnelGuardWatchdog.swift \
    tests/TunnelGuardStateSyncTests.swift -o "$TEST_DIR/tunnelguard-state-sync-tests"
"$TEST_DIR/tunnelguard-state-sync-tests"
