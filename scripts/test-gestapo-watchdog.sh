#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-gestapo-watchdog.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/GestapoWatchdog.swift \
    tests/GestapoWatchdogTests.swift -o "$TEST_DIR/gestapo-watchdog-tests"
"$TEST_DIR/gestapo-watchdog-tests"
