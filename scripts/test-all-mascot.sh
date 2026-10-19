#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=========================================================="
echo "      Astral Morph Mascot Full Verification Suite        "
echo "=========================================================="

echo "[0/7] Running Native Astral Idle Tests..."
bash scripts/test-astral-idle.sh

echo "[0/7] Running Native Astral Greeting Tests..."
bash scripts/test-astral-greeting.sh

echo "[1/7] Running Geometry & Notch Anchoring Tests..."
bash scripts/test-geometry.sh

echo "[2/7] Running Compact LOD & Mini Pill Tests..."
bash scripts/test-compact-lod.sh

echo "[3/7] Running Expanded LOD & Expressive Face Tests..."
bash scripts/test-expanded-lod.sh

echo "[4/7] Running Sprite Sheet Animator & Fallback Tests..."
bash scripts/test-sprite-sheet-animator.sh

echo "[5/7] Running Facade & Secondary Surfaces Tests..."
bash scripts/test-facade.sh

echo "[6/7] Running Astral Morph E2E Tests..."
bash scripts/test-astral-morph-e2e.sh

echo "[7/7] Running Cross-Platform TypeScript / Node.js Tests..."
node windows/tests/compact-lod.test.mjs
node windows/tests/expanded-lod.test.mjs

echo "=========================================================="
echo "  ✅ All Mascot Tests Passed Successfully! (0 Failures)  "
echo "=========================================================="
