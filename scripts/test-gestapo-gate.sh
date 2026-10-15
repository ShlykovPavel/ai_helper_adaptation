#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Running Gestapo L1 Hook Gate Tests (Safe Suite) ==="
PYTHONPATH=tests python3 -m unittest -v \
    test_gestapo_hook_gate.TestGestapoHookVPNCheck \
    test_gestapo_hook_gate.TestAgentPIDDetection \
    test_gestapo_hook_gate.TestShellWrapperFailClosed \
    test_gestapo_hook_gate.TestGestapoGateE2E.test_e2e_deny_payload_schema
