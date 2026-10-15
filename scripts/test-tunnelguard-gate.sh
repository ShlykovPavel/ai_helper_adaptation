#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Running TunnelGuard L1 Hook Gate Tests (Safe Suite) ==="
PYTHONPATH=tests python3 -m unittest -v \
    test_tunnelguard_hook_gate.TestTunnelGuardHookVPNCheck \
    test_tunnelguard_hook_gate.TestAgentPIDDetection \
    test_tunnelguard_hook_gate.TestShellWrapperFailClosed \
    test_tunnelguard_hook_gate.TestTunnelGuardGateE2E.test_e2e_deny_payload_schema
