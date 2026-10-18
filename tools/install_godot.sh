#!/usr/bin/env bash
# Install Godot 4.6.3 editor on PATH. Idempotent. Does not vendor the binary.
set -euo pipefail

VERSION="4.6.3"
ZIP="Godot_v${VERSION}-stable_linux.x86_64.zip"
URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable/${ZIP}"
SUMS_URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable/SHA512-SUMS.txt"
DEST="/opt/godot"
BIN_NAME="Godot_v${VERSION}-stable_linux.x86_64"
LINK="/usr/local/bin/godot"

if [[ -x "$LINK" ]] && "$LINK" --headless --version 2>/dev/null | grep -q "${VERSION}"; then
	echo "godot ${VERSION} already installed"
	exit 0
fi

if command -v sudo >/dev/null 2>&1 && [[ "$(id -u)" -ne 0 ]]; then
	SUDO="sudo"
else
	SUDO=""
fi

$SUDO mkdir -p "$DEST"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

curl -fsSL "$SUMS_URL" -o "$tmpdir/SHA512-SUMS.txt"
curl -fsSL "$URL" -o "$tmpdir/$ZIP"
(
	cd "$tmpdir"
	grep -F "$ZIP" SHA512-SUMS.txt > "$ZIP.sha512"
	sha512sum -c "$ZIP.sha512"
)
$SUDO unzip -o "$tmpdir/$ZIP" -d "$DEST"
$SUDO chmod +x "$DEST/$BIN_NAME"
$SUDO ln -sfn "$DEST/$BIN_NAME" "$LINK"

missing="$(ldd "$DEST/$BIN_NAME" | awk '/not found/ {print $1}' || true)"
if [[ -n "$missing" ]]; then
	echo "godot is missing shared libraries:" >&2
	echo "$missing" >&2
	exit 1
fi

"$LINK" --headless --version
