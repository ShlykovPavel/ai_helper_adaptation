#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/expanded-lod.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedRenderer.swift \
       tests/IslandTypeStubs.swift \
       tests/ShapeshifterExpandedLODTests.swift -o "$TEST_DIR/expanded-tests"
"$TEST_DIR/expanded-tests"
