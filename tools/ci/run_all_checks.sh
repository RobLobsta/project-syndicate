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
# Tee'd rather than run directly, because the runner's exit code is not the
# whole story: it counts recorded assertion failures, and a GDScript *runtime*
# error — a null dereference, a failed assert(), a call on a freed object —
# prints to stderr and lets the calling method return, so the test that
# triggered it reports zero failures and the suite passes.
#
# That hole is not theoretical. Session 9's fault injection found a guard whose
# removal caused a null dereference in production code and changed nothing the
# suite could see, because the crash was the only symptom. Any fault whose
# symptom is an engine error rather than a failed check is invisible without
# this scan.
SUITE_LOG="$(mktemp)"
trap 'rm -f "$SUITE_LOG"' EXIT
set +e
"$GODOT" --headless --path "$REPO_ROOT" --script res://tools/ci/run_all_checks.gd 2>&1 \
	| tee "$SUITE_LOG"
SUITE_STATUS="${PIPESTATUS[0]}"
set -e

if grep -qE '^(SCRIPT ERROR|USER SCRIPT ERROR|ERROR):' "$SUITE_LOG"; then
	echo ""
	echo "run_all_checks: engine errors were printed during the suite:"
	grep -nE '^(SCRIPT ERROR|USER SCRIPT ERROR|ERROR):' "$SUITE_LOG" | head -20
	echo "run_all_checks: failing on the above, even though the checks passed."
	exit 1
fi

exit "$SUITE_STATUS"
