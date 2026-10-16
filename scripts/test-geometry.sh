#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/geometry-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -DSTANDALONE_CLI \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       tests/ShapeshifterGeometryTests.swift -o "$TEST_DIR/geometry-tests"
"$TEST_DIR/geometry-tests"
