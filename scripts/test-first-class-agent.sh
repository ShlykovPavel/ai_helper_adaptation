#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-first-class.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/PillCatalog.swift \
    NotchBuddy/Sources/CoucouKit/PillColors.swift \
    NotchBuddy/Sources/CoucouKit/IslandTypes.swift \
    tests/FirstClassAgentTests.swift -o "$TEST_DIR/first-class-tests"
"$TEST_DIR/first-class-tests"
