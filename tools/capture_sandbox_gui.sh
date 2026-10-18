#!/usr/bin/env bash
# 保存沙盘 GUI 截图（需 DISPLAY）。用法: capture_sandbox_gui.sh <out.png> [width] [height] [zoom]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
OUT="${1:?output png path required}"
W="${2:-1280}"
H="${3:-720}"
ZOOM="${4:-1.0}"
mkdir -p "$(dirname "$OUT")"
"$GODOT" --path "$ROOT" --display-driver x11 --rendering-driver opengl3 \
  --resolution "${W}x${H}" --script res://scripts/dev/gui_capture_sandbox.gd -- "$OUT" "$W" "$H" "$ZOOM"
