#!/usr/bin/env bash
# Full validation suite. Run before any commit touching src/ or data/.
#
# Godot's headless script runner reports GDScript parse errors on stderr but
# still exits 0, so this wrapper reimports the project first (surfacing parse
# failures) and then defers the pass/fail decision to the runner's exit code.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="$REPO_ROOT/tools/ci/godot.sh"

echo "== importing resources =="
"$GODOT" --headless --path "$REPO_ROOT" --import 2>&1 | (grep -Ev '^$' || true)

echo "== test suite =="
"$GODOT" --headless --path "$REPO_ROOT" --script res://tools/ci/run_all_checks.gd
