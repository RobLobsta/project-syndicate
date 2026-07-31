#!/usr/bin/env bash
# Invokes the bootstrapped engine with every writable path redirected into
# .tooling/. Godot otherwise scatters editor settings, shader caches, and
# user:// data across $HOME, which makes CI runs non-reproducible.
#
# Usage:  tools/ci/godot.sh --headless --path . --version
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLING_DIR="$REPO_ROOT/.tooling"

GODOT_BIN="$(find "$TOOLING_DIR/godot" -maxdepth 1 -name 'Godot_v*_linux.x86_64' -type f 2>/dev/null | sort | tail -1)"
if [[ -z "$GODOT_BIN" ]]; then
	echo "godot.sh: engine not provisioned; run tools/ci/bootstrap_env.sh" >&2
	exit 1
fi

export XDG_DATA_HOME="$TOOLING_DIR/godot_user"
export XDG_CONFIG_HOME="$TOOLING_DIR/godot_config"
export XDG_CACHE_HOME="$TOOLING_DIR/godot_cache"

exec "$GODOT_BIN" "$@"
