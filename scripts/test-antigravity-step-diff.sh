#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-step-diff.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/CoucouKit/DiffEngine.swift \
    NotchBuddy/Sources/App/AntigravityStepFormatter.swift \
    tests/AntigravityStepAndDiffTests.swift -o "$TEST_DIR/step-diff-tests"
"$TEST_DIR/step-diff-tests"
