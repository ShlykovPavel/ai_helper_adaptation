#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mascot-e2e.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -DSTANDALONE_CLI \
       tests/FlowHubTestStubs.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotTypes.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/MascotSettings.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/SpriteSheetAnimator.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterCompactRenderer.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterExpandedRenderer.swift \
       NotchBuddy/Sources/CoucouKit/Mascots/Shapeshifter/ShapeshifterHostView.swift \
       tests/AstralMorphE2ETests.swift -o "$TEST_DIR/e2e-tests"
"$TEST_DIR/e2e-tests"
