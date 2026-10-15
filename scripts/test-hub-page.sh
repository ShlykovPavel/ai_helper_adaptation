#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-hub-page.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc \
    tests/FlowHubTestStubs.swift \
    NotchBuddy/Sources/App/FlowHub.swift \
    tests/HubPageTunnelGuardTests.swift \
    -o "$TEST_DIR/hub-page-tests"

"$TEST_DIR/hub-page-tests"
