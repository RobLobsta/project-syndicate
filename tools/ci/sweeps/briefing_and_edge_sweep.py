#!/usr/bin/env python3
"""Fault sweep over the briefing hold and the edge in a fight.

Two unrelated pieces of one session, swept together because each is a handful of
lines and each is exactly the kind of line a later change deletes without
anything noticing.

  briefing-hold-ignored       doc 05 §15.7.4's third gate: an opponent that shoots
                              a first-time player while they read the control card
  briefing-taken-by-toggle    doc 11 §14.6's distinction: a card the player raised
                              counting as a briefing, so `hud_toggle_stats` becomes
                              a key that stops the opposition firing on demand
  briefing-never-held         the match layer never writing the hold onto its
                              drivers -- expected to SURVIVE; see below
  melee-stand-off-defaulted   the melee recipe holding at the ground family's
                              twenty metres, so an edge with 2.4 m of reach parks
                              seventeen and a half metres short of anything
  shoulder-orientation-lost   the orientation group asked to carry an Appendage's
                              shoulder onto a hull face and answering "identity"
  sustained-delivers-impulse  §15.4's per-swing impulse applied on every tick of
                              contact -- a former survivor of
                              `burn_and_hold_sweep.py`, CAUGHT here

`sustained-delivers-impulse` is the interesting one and is the reason this sweep
re-plants a fault another sweep already owns. `test_held_weapon` freezes its
target for the sustained phase, so an impulse added per tick moves nothing it can
observe and the fault survived the sweep that found it. `test_melee_duel` drives
one live Assembly into another, and the assertion that separates them is not the
one that was tempting: under the fault the target is thrown to 7.7 m/s against
2.76 correct, which is inside the noise of a two-Assembly fight, while the
**range re-opens 5.15 m against 0.03**. Contact once made is either kept or it is
not, and that is the shape the law has.

`briefing-never-held` is expected to survive and is planted anyway.
`tests/integration/test_first_run_card.gd` asserts the gate on the driver and the
briefing on the HUD; the four lines of `MatchScreen` that join them are reached
only by `tests/integration/test_screen_flow.gd`, which builds two real matches and
does not control `SyndicateSettings.control_card_seen`. Closing it means either
that file taking over the settings save/restore the card file already does, or a
match cheap enough to build twice. Recorded rather than left as a sentence.

    python3 tools/ci/sweeps/briefing_and_edge_sweep.py
    python3 tools/ci/sweeps/briefing_and_edge_sweep.py -j1 --full briefing-hold-ignored

The loop, the parallelism, the timeout and the fail-fast rule all live in
`sweeplib.py`. Update BASELINE in the same change as anything that moves the
check count, or every fault after it reads as caught.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweeplib

DRIVER = "src/ai/ai_driver.gd"
CARD = "src/ui/hud/control_card.gd"
SCREEN = "src/ui/match/match_screen.gd"
ARENA = "tests/combat_arena.gd"
ORIENTATION = "src/core/math/orientation_table.gd"
EFFECTORS = "src/combat/effectors/effector_system.gd"

# The check count at the commit this last ran clean. sweeplib measures the real
# one and warns if this disagrees, so a stale value here is a printed warning
# rather than a sweep that reports CAUGHT for everything.
BASELINE = 7712

FAULTS = [
    # §15.7.4's third gate deleted: the opponent opens fire over the briefing.
    ("briefing-hold-ignored", DRIVER,
     "		guns.set_trigger(0, not hold_fire and not _closing and has_stopped())",
     "		guns.set_trigger(0, not _closing and has_stopped())"),

    # §14.6's distinction between a briefing and a legend. A player leaning on
    # the toggle would buy eleven seconds of an opponent that will not shoot.
    ("briefing-taken-by-toggle", CARD,
     "func raise() -> void:\n	_briefing = false",
     "func raise() -> void:\n	_briefing = true"),

    # The match layer never telling its drivers. Expected to survive; see the
    # module docstring.
    ("briefing-never-held", SCREEN,
     "	var held := hud != null and hud.briefing_is_up()",
     "	var held := false"),

    # The melee recipe holding at the ground family's stand-off. It parks
    # seventeen and a half metres from a weapon that reaches 2.4.
    ("melee-stand-off-defaulted", ARENA,
     "	elif recipe == Recipe.MELEE:\n		c.stand_off_m = MELEE_STAND_OFF_M",
     "	elif false:\n		c.stand_off_m = MELEE_STAND_OFF_M"),

    # The orientation group answering identity for a shoulder. The arm is then
    # placed hanging downward through the hull and the validator refuses it.
    ("shoulder-orientation-lost", ORIENTATION,
     "	for i: int in COUNT:\n"
     "		if (basis_for(i) * local_axis).is_equal_approx(onto):\n"
     "			return i\n"
     "	return IDENTITY_INDEX",
     "	for i: int in COUNT:\n"
     "		if false:\n"
     "			return i\n"
     "	return IDENTITY_INDEX"),

    # §15.4's impulse on every tick of contact rather than once per swing. A
    # recorded survivor of `burn_and_hold_sweep.py`; see the module docstring.
    ("sustained-delivers-impulse", EFFECTORS,
     "	if state.energised:\n"
     "		# §15.5 delivers no impulse.",
     "	if false:\n"
     "		# §15.5 delivers no impulse."),
]


if __name__ == "__main__":
    raise SystemExit(sweeplib.run_sweep(FAULTS, BASELINE, __doc__))
