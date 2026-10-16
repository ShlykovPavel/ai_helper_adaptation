#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/facade-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -DSTANDALONE_CLI \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotSettings.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift \
       tests/ShapeshifterFacadeTests.swift -o "$TEST_DIR/facade-tests"
"$TEST_DIR/facade-tests"
