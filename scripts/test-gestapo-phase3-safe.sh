#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-gestapo-phase3-safe.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/GestapoPowerGuard.swift \
    NotchBuddy/Sources/App/GestapoNetworkWorker.swift \
    NotchBuddy/Sources/App/GestapoAppHunter.swift \
    NotchBuddy/Sources/App/GestapoWatchdog.swift \
    tests/GestapoPhase3SafeTests.swift -o "$TEST_DIR/gestapo-phase3-safe-tests"

"$TEST_DIR/gestapo-phase3-safe-tests"
