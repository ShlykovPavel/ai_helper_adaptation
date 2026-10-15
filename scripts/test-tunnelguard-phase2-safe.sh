#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-tunnelguard-phase2-safe.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

CACHE_ARGS=()
if [ -d "NotchBuddy/build/ModuleCache.noindex" ]; then
    CACHE_ARGS=(-module-cache-path "NotchBuddy/build/ModuleCache.noindex")
fi

swiftc -swift-version 6 -strict-concurrency=complete "${CACHE_ARGS[@]+"${CACHE_ARGS[@]}"}" \
    NotchBuddy/Sources/App/TunnelGuardAppHunter.swift \
    tests/TunnelGuardAppHunterSafeTests.swift \
    -o "$TEST_DIR/tunnelguard-app-hunter-safe-tests"

"$TEST_DIR/tunnelguard-app-hunter-safe-tests"
