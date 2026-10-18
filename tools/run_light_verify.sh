#!/usr/bin/env bash
# Light acceptance: project load smoke only (no full runner suite, no GUI).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
cd "$ROOT"
mkdir -p .artifacts/validation

echo "==> import (best-effort)"
"$GODOT_BIN" --headless --path . --import >.artifacts/validation/import.log 2>&1 || true

echo "==> project load smoke"
set +e
"$GODOT_BIN" --headless --path . --script res://scripts/core/project_load_smoke_test_runner.gd \
	>.artifacts/validation/project_load_smoke.log 2>&1
status=$?
set -e
cat .artifacts/validation/project_load_smoke.log
if [[ "$status" -ne 0 ]]; then
	echo "light verify: FAILED (exit $status)"
	exit "$status"
fi
if grep -E 'SCRIPT ERROR|Parse Error' .artifacts/validation/project_load_smoke.log; then
	echo "light verify: FAILED (script error)"
	exit 1
fi
echo "light verify: OK"
