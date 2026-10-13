#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Running Gestapo L1 Hook Gate & Kill-Switch Tests ==="
python3 tests/test_gestapo_hook_gate.py
