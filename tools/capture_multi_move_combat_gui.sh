#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GODOT="${GODOT_BIN:-godot}"
export DISPLAY="${DISPLAY:-:1}"
"$GODOT" --path . --display-driver x11 --audio-driver Dummy --script res://scripts/dev/multi_move_combat_gui_capture.gd
