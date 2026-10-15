#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "========================================================"
echo "      🛡️  GESTAPO AUTOMATED TEST SUITE (L1 & L2)        "
echo "========================================================"

echo ""
echo "▶ 1/5 Running Swift Gestapo Phase 1 Tests (Core & PowerGuard)..."
./scripts/test-gestapo-phase1-safe.sh

echo ""
echo "▶ 2/5 Running Swift Gestapo Phase 2 Tests (AppHunter & Kill-Switch)..."
./scripts/test-gestapo-phase2-safe.sh

echo ""
echo "▶ 3/5 Running Swift Gestapo Phase 3 Tests (UI & Route Validation)..."
./scripts/test-gestapo-phase3-safe.sh

echo ""
echo "▶ 4/5 Running Swift Gestapo Watchdog Tests (L2 Daemon Transitions)..."
./scripts/test-gestapo-watchdog.sh

echo ""
echo "▶ 5/5 Running Python Gestapo Hook Gate Tests (L1 Gate)..."
./scripts/test-gestapo-gate.sh

echo ""
echo "========================================================"
echo "  ✅ ALL GESTAPO VALIDATION TESTS PASSED SUCCESSFULLY   "
echo "========================================================"
