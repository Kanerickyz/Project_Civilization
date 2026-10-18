#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
OUT="${1:-${ROOT}/.artifacts/move_attack_ranges}"
mkdir -p "$OUT"
export DISPLAY="${DISPLAY:-:1}"
"$GODOT" --path "$ROOT" --display-driver x11 \
  --script res://scripts/dev/gui_capture_move_attack_ranges.gd -- "$OUT"
