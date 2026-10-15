#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "========================================================"
echo "      🛡️  TUNNELGUARD AUTOMATED TEST SUITE (L1 & L2)        "
echo "========================================================"

echo ""
echo "▶ 1/5 Running Swift TunnelGuard Phase 1 Tests (Core & PowerGuard)..."
./scripts/test-tunnelguard-phase1-safe.sh

echo ""
echo "▶ 2/5 Running Swift TunnelGuard Phase 2 Tests (AppHunter & Kill-Switch)..."
./scripts/test-tunnelguard-phase2-safe.sh

echo ""
echo "▶ 3/5 Running Swift TunnelGuard Phase 3 Tests (UI & Route Validation)..."
./scripts/test-tunnelguard-phase3-safe.sh

echo ""
echo "▶ 4/5 Running Swift TunnelGuard Watchdog Tests (L2 Daemon Transitions)..."
./scripts/test-tunnelguard-watchdog.sh

echo ""
echo "▶ 5/5 Running Python TunnelGuard Hook Gate Tests (L1 Gate)..."
./scripts/test-tunnelguard-gate.sh

echo ""
echo "========================================================"
echo "  ✅ ALL TUNNELGUARD VALIDATION TESTS PASSED SUCCESSFULLY   "
echo "========================================================"
