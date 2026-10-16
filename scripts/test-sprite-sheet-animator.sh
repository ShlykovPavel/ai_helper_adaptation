#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sprite-animator.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/SpriteSheetAnimator.swift \
       tests/IslandTypeStubs.swift \
       tests/SpriteSheetAnimatorTests.swift -o "$TEST_DIR/animator-tests"
"$TEST_DIR/animator-tests"
