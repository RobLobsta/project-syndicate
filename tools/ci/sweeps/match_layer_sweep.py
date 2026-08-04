#!/usr/bin/env python3
"""Fault sweep over doc 11 §16's match outcome and §14.3/§14.6's presentation.

Eleven faults over the code session 25 added: the rule that decides a match, the
bookkeeping that feeds it, the aim ray's hull test, the binding lookup behind the
control card, and doc 05 §15.7.5's stand-off ladder.

  outcome-always-victory      §16.1: the last team standing is always the player's
  outcome-draw-is-victory     §16.1's empty row: nobody standing reads as a win
  outcome-two-teams-decided   §16.1's bound at two, moved to one
  conclusion-fires-twice      §16.1: a match concludes once
  unregistered-ends-match     §16.1: an Assembly nobody rostered decides it
  counted-out-twice           §16.1: one Assembly takes its team out twice
  standing-list-unsorted      Invariant I-9 on the rule's only argument
  bracket-always-on           §14.3: the target bracket over open ground
  bracket-never-on            the same, in the other direction
  prompt-ignores-input-method §14.6: a controller player shown keyboard keys
  ladder-flat                 §15.7.5: every driver stops at the same range
  ladder-counts-all-sides     §15.7.5: the target's own escort counted as friends

**Most of these are shallow, and that is worth saying rather than hiding.** Seven
of the twelve are planted on `static func`s that a unit test calls directly, so
catching them proves the assertion exists and nothing more (LEARNED_FACTS.md §2:
a unit test over statics does not cover the code that calls them). The four worth
the run are `conclusion-fires-twice`, `unregistered-ends-match`,
`counted-out-twice` and `standing-list-unsorted`, which live in the instance path
and are reachable only through the bus.

`counted-out-twice` is not hypothetical: the guard it removes did not exist when
`test_match_conclusion.gd` was first written, and the file caught the defect on
its first run. Doc 11 §16.1 records it.

    python3 tools/ci/sweeps/match_layer_sweep.py            # all of them, 4 workers
    python3 tools/ci/sweeps/match_layer_sweep.py -j1 --full conclusion-fires-twice

The loop, the parallelism, the timeout and the fail-fast rule all live in
`sweeplib.py`; read that before changing how this runs. Update BASELINE in the
same change as anything that moves the check count, or every fault after it
reads as caught.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweeplib

STATE = "src/world/match/match_state.gd"
CAMERA = "src/ui/match/chase_camera.gd"
PROMPT = "src/ui/common/input_prompt.gd"
DRIVER = "src/ai/ai_driver.gd"

BASELINE = 6165

FAULTS = [
    # §16.1's local-team comparison, dropped. Every survivor is the player, so a
    # match the player loses reads as a win — which is the one presentation error
    # in this section that cannot be recovered from by looking at the screen.
    ("outcome-always-victory", STATE,
     "	return Outcome.VICTORY if standing[0] == local_team else Outcome.DEFEAT",
     "	return Outcome.VICTORY"),

    # The empty row folded into the single-team one. Nothing in an arena can
    # currently reach it, which is exactly why the rule is a static.
    ("outcome-draw-is-victory", STATE,
     "	if standing.is_empty():\n		return Outcome.DRAW",
     "	if standing.is_empty():\n		return Outcome.VICTORY"),

    # The bound at two moved to one, so a match with both sides standing is
    # declared over on the first termination.
    ("outcome-two-teams-decided", STATE,
     "	if standing.size() >= 2:",
     "	if standing.size() >= 3:"),

    # §16.1's conclude-once guard. Two Assemblies destroyed on the same tick raise
    # two signals and the second would put a card over the first.
    ("conclusion-fires-twice", STATE,
     "	if _outcome != Outcome.UNDECIDED:\n		# A match concludes once.",
     "	if false:\n		# A match concludes once."),

    # The roster guard: an Assembly nobody registered decides the match. In an
    # arena that is a debris body or a build from a fight that has finished.
    ("unregistered-ends-match", STATE,
     "	if not _team_of.has(assembly_id) or _counted_out.has(assembly_id):",
     "	if _counted_out.has(assembly_id) and not _team_of.has(assembly_id):"),

    # The per-Assembly guard, which is the defect the integration test caught on
    # its first run: one Assembly terminated twice takes its team out twice.
    ("counted-out-twice", STATE,
     "	_counted_out[assembly_id] = true",
     "	pass"),

    # Invariant I-9 on the standing list, which is the outcome rule's only
    # argument. Unsorted, the answer depends on which side spawned first.
    ("standing-list-unsorted", STATE,
     "	out.sort()\n	return out",
     "	return out"),

    # §14.3's hull test, permanently true: the bracket lights over open hillside,
    # which is the exact confusion it was added to remove.
    ("bracket-always-on", CAMERA,
     "	return (body.collision_layer & CollisionLayers.LAYER_ASSEMBLY_HULL) != 0",
     "	return true"),

    # And permanently false, which is the failure that looks like the feature was
    # never wired up rather than like a defect.
    ("bracket-never-on", CAMERA,
     "	return (body.collision_layer & CollisionLayers.LAYER_ASSEMBLY_HULL) != 0",
     "	return false"),

    # §14.6's device match. Every action in §7.1 carries a key and a gamepad
    # control, so "the first event" shows keys to a player holding a controller.
    ("prompt-ignores-input-method", PROMPT,
     "		if _is_gamepad_event(event) == want_gamepad:\n			return event",
     "		if true:\n			return event"),

    # §15.7.5's ladder flattened: three drivers converge on one point again.
    ("ladder-flat", DRIVER,
     "	return base_m + float(steps) * ALLY_STAND_OFF_STEP_M",
     "	return base_m"),

    # The team filter dropped from the count, so the target's own side is counted
    # as friends and every driver is pushed out a rung it did not earn.
    ("ladder-counts-all-sides", DRIVER,
     "		if handle.team != context.team or handle.id == target.id:",
     "		if handle.id == target.id:"),
]


if __name__ == "__main__":
    raise SystemExit(sweeplib.run_sweep(FAULTS, BASELINE, __doc__))
