#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-gestapo-phase1-safe.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

CACHE_ARGS=()
if [ -d "NotchBuddy/build/ModuleCache.noindex" ]; then
    CACHE_ARGS=(-module-cache-path "NotchBuddy/build/ModuleCache.noindex")
fi

swiftc -swift-version 6 -strict-concurrency=complete "${CACHE_ARGS[@]}" \
    NotchBuddy/Sources/App/GestapoPowerGuard.swift \
    NotchBuddy/Sources/App/GestapoNetworkWorker.swift \
    NotchBuddy/Sources/App/GestapoAppHunter.swift \
    NotchBuddy/Sources/App/GestapoWatchdog.swift \
    tests/GestapoPhase1SafeTests.swift -o "$TEST_DIR/gestapo-phase1-safe-tests"

"$TEST_DIR/gestapo-phase1-safe-tests"
