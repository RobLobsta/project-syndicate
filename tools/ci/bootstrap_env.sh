#!/usr/bin/env bash
# Provisions the local Godot toolchain into .tooling/ (gitignored).
#
# Idempotent: re-running with the engine already present is a no-op. The engine
# binary, the editor's user:// data, and all test output live under .tooling/ so
# that nothing the toolchain writes can ever land in a commit.
#
# Usage:  tools/ci/bootstrap_env.sh
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.1-stable}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLING_DIR="$REPO_ROOT/.tooling"
GODOT_DIR="$TOOLING_DIR/godot"
GODOT_BIN="$GODOT_DIR/Godot_v${GODOT_VERSION}_linux.x86_64"
ARCHIVE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"

mkdir -p "$GODOT_DIR" "$TOOLING_DIR/godot_user" "$TOOLING_DIR/godot_config" \
         "$TOOLING_DIR/godot_cache" "$TOOLING_DIR/out"

if [[ ! -x "$GODOT_BIN" ]]; then
	echo "bootstrap_env: fetching Godot ${GODOT_VERSION}"
	tmp_zip="$(mktemp "$TOOLING_DIR/godot.XXXXXX.zip")"
	trap 'rm -f "$tmp_zip"' EXIT
	curl -fsSL --retry 4 --retry-delay 2 --max-time 600 -o "$tmp_zip" "$ARCHIVE_URL"
	unzip -oq "$tmp_zip" -d "$GODOT_DIR"
	rm -f "$tmp_zip"
	trap - EXIT
	chmod +x "$GODOT_BIN"
fi

"$GODOT_BIN" --headless --version
echo "bootstrap_env: engine ready at $GODOT_BIN"
