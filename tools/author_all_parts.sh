#!/usr/bin/env bash
# Re-authors every shipped part, in the one order that produces correct data.
#
# THE ORDER IS THE POINT OF THIS FILE. `author_appendage_parts.gd` re-authors a
# key `author_locomotion_parts.gd` also writes: it loads `eff.melee.beam_edge.t4`
# and replaces its attachment nodes with a single GRIP hilt, so the edge can be
# held in a hand and cannot be welded to a roof. Run locomotion after appendage
# and the edge quietly goes back to being a deck mount — no error, no warning,
# and the registry validates either way. The symptom is a melee build whose
# blades are refused with `polarity_mismatch` at the far end of the suite.
#
# LEARNED_FACTS.md §1 fact 76 recorded that ordering as a fact to remember. It
# was then forgotten twice, which is what a fact-to-remember does. This script is
# the version that cannot be forgotten.
#
#   tools/author_all_parts.sh
#
# Idempotent: re-running rewrites the same bytes, and the manifest append is
# append-only because `part_def_id` is serialised into save data and packets.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# The registry has to reimport before a script can resolve the class_name
# globals it touches (LEARNED_FACTS.md §1 fact 1).
tools/ci/godot.sh --headless --path . --import >/dev/null

for stage in first combat locomotion appendage chassis; do
	echo "author_all_parts: ${stage}"
	tools/ci/godot.sh --headless --path . --script "tools/author_${stage}_parts.gd"
done

tools/ci/godot.sh --headless --path . --import >/dev/null
tools/ci/godot.sh --headless --path . --script tools/validate_part_registry.gd
