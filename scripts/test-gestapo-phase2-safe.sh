#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-gestapo-phase2-safe.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc -swift-version 6 -strict-concurrency=complete \
    NotchBuddy/Sources/App/GestapoAppHunter.swift \
    tests/GestapoAppHunterSafeTests.swift \
    -o "$TEST_DIR/gestapo-app-hunter-safe-tests"

"$TEST_DIR/gestapo-app-hunter-safe-tests"
