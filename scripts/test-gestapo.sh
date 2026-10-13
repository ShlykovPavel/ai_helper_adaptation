#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "========================================================"
echo "      🛡️  GESTAPO AUTOMATED TEST SUITE (L1 & L2)        "
echo "========================================================"

echo ""
echo "▶ Running Swift GestapoWatchdog Tests (L2 Daemon)..."
./scripts/test-gestapo-watchdog.sh

echo ""
echo "▶ Running Python Gestapo Hook Gate Tests (L1 Gate)..."
./scripts/test-gestapo-gate.sh

echo ""
echo "========================================================"
echo "  ✅ ALL GESTAPO VALIDATION TESTS PASSED SUCCESSFULLY   "
echo "========================================================"
