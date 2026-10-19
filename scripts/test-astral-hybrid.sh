#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hybrid-idle-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc NotchBuddy/Sources/App/AstralHybridIdleAnimation.swift \
       tests/AstralHybridIdleTests.swift \
       -o "$TEST_DIR/hybrid-idle-tests"

"$TEST_DIR/hybrid-idle-tests"
