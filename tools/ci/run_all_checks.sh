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
# --fixed-fps 60 is what makes this suite affordable, and it is the *only*
# accelerant that is safe here.
#
# Headless Godot still paces its main loop against the wall clock: measured on
# 4.7.1 in this repo, 600 bare physics frames take 9.88 s — 60.8 fps — with no
# work in them at all. `tests/physics/` waits on real ticks, so its wall time was
# tick count divided by sixty and nothing else. --fixed-fps disables that
# real-time synchronisation and lets the loop advance as fast as the CPU allows;
# the same 600 frames then take 4 ms.
#
# It is safe because it changes *pacing* and not `delta`. The physics step stays
# 1/60 exactly, so every measurement, every integration and Invariant I-9's
# determinism are untouched — verified by diffing a full real-time run against a
# full --fixed-fps run: 4342 checks both ways and byte-identical engagement
# outcomes, down to the tick each Assembly died on.
#
# Do NOT reach for `Engine.time_scale` instead. It is the obvious-looking answer
# and it is wrong twice over: measured here it gives *no* speedup whatsoever
# (600 frames in 10.00 s at time_scale 20, still 60 fps, because it scales delta
# rather than the frame count), and the delta it hands `_physics_process` becomes
# 0.333 s — at which point a 940 m/s round advances 313 m per step and every
# spring in doc 05 explodes.
"$GODOT" --headless --path "$REPO_ROOT" --fixed-fps 60 \
	--script res://tools/ci/run_all_checks.gd 2>&1 \
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
