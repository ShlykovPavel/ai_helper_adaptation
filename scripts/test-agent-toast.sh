#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-toast.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/AgentToast.swift \
    tests/AgentToastTests.swift -o "$TEST_DIR/toast-tests"
"$TEST_DIR/toast-tests"
