#!/usr/bin/env bash
# Run every SceneTree *_test_runner.gd under scripts/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
cd "$ROOT"
mkdir -p .artifacts/validation

"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true

mapfile -t runners < <(find scripts -name '*_test_runner.gd' | sort)
if [[ "${#runners[@]}" -eq 0 ]]; then
	echo "verify runners: no *_test_runner.gd found"
	exit 1
fi

failed=0
for script in "${runners[@]}"; do
	res="res://${script}"
	echo "==> $res"
	log=".artifacts/validation/$(basename "$script" .gd).log"
	set +e
	"$GODOT_BIN" --headless --path . --script "$res" >"$log" 2>&1
	status=$?
	set -e
	cat "$log"
	if [[ "$status" -ne 0 ]] || grep -E 'SCRIPT ERROR|Parse Error' "$log" >/dev/null; then
		echo "FAIL $res"
		failed=1
	else
		echo "OK   $res"
	fi
done

if [[ "$failed" -ne 0 ]]; then
	echo "verify runners: FAILED"
	exit 1
fi
echo "verify runners: OK"
