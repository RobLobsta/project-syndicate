#!/usr/bin/env python3
"""Fault sweep over doc 01 §10.5's second direct-fire row and what it is wired to.

Six planted faults over the change that made an Assembly able to drive and shoot
at the same time — the build a player is handed, the comparison fixture, and the
projectile wiring a second round type needed — plus three that belong to the
change and cannot be planted here, listed under AUTHORED at the bottom.

  starter-keeps-the-autocannon  the shipped starter re-armed with the heavy row
  starter-ceiling-never-checked the drivability precondition asserted vacuously
  repeater-recoils-like-a-30    the row authored at the autocannon's impulse
  repeater-cycles-like-a-30     the fast cycle taken away
  repeater-cannot-penetrate     the round's penetration below what a panel rates
  repeater-round-unregistered   §12's registry never told about the second round
  ammo-stocks-only-the-first    an Assembly stocked for a round it does not fire
  hud-counts-the-wrong-round    §14.1's counter reading the other store
  arena-repeater-is-an-autocannon the comparison fixture comparing one row twice

**Two of these are about a fixture rather than about the game, and they are the
interesting ones.** `arena-repeater-is-an-autocannon` makes
`tests/physics/test_drive_and_shoot.gd` compare the heavy row against itself; if
that survives, the file's whole claim is unfalsifiable. And
`starter-ceiling-never-checked` replaces the drivability bound with one no
published row could exceed, which is the shape of assertion
`LEARNED_FACTS.md` §2 calls "a test that reads the same constant the source
does".

**Three of the six survived their first run and the survivals were worth more
than the fixes.** `starter-ceiling-never-checked` said a threshold cannot assert
anything about itself — the repair is a second check that the catalogue's heavy
row is on the other side of it. `ammo-stocks-only-the-first` and
`hud-counts-the-wrong-round` said that nothing anywhere verified which store a
player's own module draws from: until this change every module in the catalogue
chambered the same round, so three separate lookups agreed by accident and a
build that could not fire a shot for the whole match was invisible.

    python3 tools/ci/sweeps/effector_choice_sweep.py            # all of them, 4 workers
    python3 tools/ci/sweeps/effector_choice_sweep.py --list
    python3 tools/ci/sweeps/effector_choice_sweep.py -j1 --full repeater-recoils-like-a-30

The loop, the parallelism, the timeout and the fail-fast rule all live in
`sweeplib.py`; read that before changing how this runs. Update BASELINE in the
same change as anything that moves the check count, or every fault after it
reads as caught.

Note that the three AUTHORED entries would have to be planted in
`tools/author_combat_parts.gd`, which is a generator: the sweep would patch the
generator and the suite would go on reading the `.tres` files it already wrote,
so they do **not** reproduce. A run that wants them has to re-author in the
workspace first, which `sweeplib` deliberately does not do.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweeplib

STARTER = "src/assembly/lattice/starter_blueprint.gd"
BLUEPRINT_TEST = "tests/unit/test_blueprint.gd"
MATCH = "src/ui/match/match_screen.gd"
ARENA = "tests/combat_arena.gd"

BASELINE = 7725

FAULTS = [
    # The one line that decides what a first-time player is handed. The build is
    # legal, the match runs, every unit test passes, and the first fight is the
    # one the capture found: a hull turned ninety-nine degrees by its own gun.
    ("starter-keeps-the-autocannon", STARTER,
     'const EFFECTOR_KEY: StringName = &"eff.ballistic.repeater_12.t2"',
     'const EFFECTOR_KEY: StringName = &"eff.ballistic.autocannon_30.t3"'),

    # The precondition asserted against a bound nothing could fail. This is the
    # fault that decides whether the rule above is defended or merely written
    # down, and it is invisible to every other file.
    ("starter-ceiling-never-checked", BLUEPRINT_TEST,
     "const STARTER_RECOIL_CEILING_NS: float = 120.0",
     "const STARTER_RECOIL_CEILING_NS: float = 100000.0"),

    # The comparison fixture comparing the heavy row against itself. Every
    # assertion in `test_drive_and_shoot.gd` is about a difference between two
    # rows, so a recipe that lays out the same row twice makes the whole file
    # unfalsifiable while leaving it green-looking.
    ("arena-repeater-is-an-autocannon", ARENA,
     "		Recipe.WHEELED_REPEATER:\n			_lay_out_wheeled(ctx, false, REPEATER_KEY)",
     "		Recipe.WHEELED_REPEATER:\n			_lay_out_wheeled(ctx, false, GUN_KEY)"),

    # Doc 07 §12's registry told about one round type. The second module then
    # resolves no projectile id and declines to fire — which is the correct
    # failure mode and is still a build that cannot shoot.
    ("repeater-round-unregistered", MATCH,
     '	&"proj.kinetic.ap_30",\n	&"proj.kinetic.ap_12",',
     '	&"proj.kinetic.ap_30",'),

    # An Assembly stocked for the first round type in the registry rather than
    # for the ones its own modules chamber. Presents as a gun that fires for
    # exactly as long as the ledger's default lasts and then stops.
    ("ammo-stocks-only-the-first", MATCH,
     "		for id: int in _round_ids_of(runtime):\n			ammo.add(assembly_id, id, rounds)",
     "		ammo.add(assembly_id, 0, rounds)"),

    # §14.1's counter and §14.3's ammunition state reading a store the player's
    # module never draws from. The HUD reports a full magazine over an empty
    # module, or an empty one over a full module, depending which way round the
    # build is.
    ("hud-counts-the-wrong-round", MATCH,
     "		_round_id = _round_id_at(runtime, gun_slot)",
     "		_round_id = 0"),
]

# Faults that belong to this change and that this harness cannot plant, because
# their subject is a generator whose output is committed. Recorded so that the
# next session does not conclude the row is untested — the assertions that cover
# them are `test_part_registry_data.gd`'s shipped-key list, the registry
# validator's rules 17-27, and `test_drive_and_shoot.gd`'s measurement.
AUTHORED = [
    "repeater-recoils-like-a-30",
    "repeater-cycles-like-a-30",
    "repeater-cannot-penetrate",
]


if __name__ == "__main__":
    raise SystemExit(sweeplib.run_sweep(FAULTS, BASELINE, __doc__))
