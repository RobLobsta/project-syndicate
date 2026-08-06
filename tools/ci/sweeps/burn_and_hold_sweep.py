#!/usr/bin/env python3
"""Fault sweep over sustained contact and fire: doc 07 §15.5 and doc 08 §7.1/§7.3.

Eleven faults against the laws this session landed. The first nine are planted
together because the two only make a weapon when they are both there: a held edge
that deals damage but deposits no heat is a slower autocannon, and a fire nothing
can start is a flag. The last two are the session's two interface rules, which
are each one line and are exactly the kind of line a later change deletes without
anything noticing.

  sustained-hold-ignored        §15.5's stage: a held edge recovers like a strike
  sustained-set-not-cleared     the one line -- contact resolves once and never again
  sustained-uses-strike-damage  a held edge dealing 640 a tick instead of 340 a second
  sustained-no-interval         the instalment not saying what it covers, so §7.1's
                                heat is deposited sixty times a second
  sustained-delivers-impulse    §15.4's impulse applied on every tick of contact
  fire-never-ignites            the resolver never telling §7.3 a part caught
  fire-ignites-every-packet     one entry per packet instead of one per burning part
                                — a survivor on its first run, because the
                                resolver was testing the same thing a second
                                time and made the scheduler's own rule dead
  fire-never-cools              §7.1's hysteresis band unreachable: it burns forever
  dot-cadence-ignored           §7.3's 10 Hz gate: an instalment every tick, six
                                times the authored rate
  carries-row-dropped           doc 11 §4.3: a chassis that will not say what it takes
  control-card-always-raised    §14.6's first-run flag consulted by nobody

`sustained-set-not-cleared` is the one to watch. §15.3 deduplicates a target for
the whole swing, so an implementation that holds the stage and forgets the
clearing delivers exactly one packet and then nothing for as long as the trigger
is down -- which no assertion about damage *arriving* can separate from a correct
one, and which is why `test_held_weapon` counts the ticks that resolved rather
than the damage that landed.

`sustained-delivers-impulse` **survived here and is now caught elsewhere.** This
fixture freezes its target so that contact is maintained across two hundred ticks,
and a frozen body absorbs the impulse the fault adds, so nothing this sweep runs
could see it. Session 43's `tests/physics/test_melee_duel.gd` drives one live
Assembly into another and asserts that the target is never thrown: 0.03 m/s
correct against 4.00 under the fault. The fault is kept in this list because it
belongs to §15.5 and because a sweep that stopped planting it would stop noticing
if the fixture that catches it were ever deleted -- see
`tools/ci/sweeps/briefing_and_edge_sweep.py`, which plants the same one against
the file that closes it.

    python3 tools/ci/sweeps/burn_and_hold_sweep.py
    python3 tools/ci/sweeps/burn_and_hold_sweep.py -j1 --full fire-never-cools

The loop, the parallelism, the timeout and the fail-fast rule all live in
`sweeplib.py`. Update BASELINE in the same change as anything that moves the
check count, or every fault after it reads as caught.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweeplib

SOLVER = "src/combat/effectors/melee_solver.gd"
EFFECTORS = "src/combat/effectors/effector_system.gd"
RESOLVER = "src/combat/damage/damage_resolver.gd"
SCHEDULER = "src/combat/damage/dot_scheduler.gd"
INSPECTOR = "src/ui/garage/part_inspector.gd"
HUD = "src/ui/hud/match_hud.gd"

# The check count at the commit this last ran clean. sweeplib measures the real
# one and warns if this disagrees, so a stale value here is a printed warning
# rather than a sweep that reports CAUGHT for everything.
BASELINE = 7760

FAULTS = [
    # §15.5's stage rule: the edge recovers at the end of its arc whatever the
    # trigger is doing, which is what the melee path did before this session.
    ("sustained-hold-ignored", SOLVER,
     "				if hold and profile.sustained:",
     "				if false:"),

    # The one line the two paths differ by. The stage holds, the sweep runs, and
    # the target is immune from the moment the arc first cut it.
    ("sustained-set-not-cleared", EFFECTORS,
     "	elif state.energised:\n"
     "		# §15.5, and it is the one line the two paths differ by: an edge held",
     "	elif false:\n"
     "		# §15.5, and it is the one line the two paths differ by: an edge held"),

    # A held edge charging strike damage per tick: 640 a tick against an authored
    # 340 a second, which is a hundred and thirteen times the rate.
    ("sustained-uses-strike-damage", EFFECTORS,
     "		if state.energised:\n"
     "			amount = MeleeSolver.sustained_channel_damage(melee, channel, dt)",
     "		if false:\n"
     "			amount = MeleeSolver.sustained_channel_damage(melee, channel, dt)"),

    # The instalment not declaring its interval. **A survivor, and the sweep is
    # what established why**: §7.1's heat is `raw · 0.55` per packet with a
    # `maxf(interval_s, 1.0)` that is 1.0 for every interval this game produces,
    # so the field reaches §7.2's corrosive decay and nothing else — and no
    # shipped melee mix authors a corrosive share. The same shape as the
    # ammunition sentinel: the line is right, and every fixture takes the other
    # branch.
    ("sustained-no-interval", EFFECTORS,
     "		if state.energised:\n			packet.interval_s = dt",
     "		if false:\n			packet.interval_s = dt"),

    # §15.4's impulse on every tick of contact rather than once per swing.
    # Expected to survive; see the module docstring.
    ("sustained-delivers-impulse", EFFECTORS,
     "	if state.energised:\n"
     "		# §15.5 delivers no impulse.",
     "	if false:\n"
     "		# §15.5 delivers no impulse."),

    # The resolver setting the flag and telling nobody, which is what a part on
    # fire did for the whole life of the project before doc 08 §7.3 was written.
    ("fire-never-ignites", RESOLVER,
     "	if dot != null and st.has_flag(PartFlags.FLAG_OVERHEATED):",
     "	if false:"),

    # One entry per packet instead of one per burning part: a build held in a
    # beam burns at some multiple of §7.1's authored rate.
    ("fire-ignites-every-packet", SCHEDULER,
     "	for entry: DotEntry in _entries:\n"
     "		if entry.assembly_id == assembly_id and entry.slot == slot:\n"
     "			entry.source_assembly_id = source_assembly_id\n"
     "			return",
     "	for entry: DotEntry in _entries:\n"
     "		if false:\n"
     "			entry.source_assembly_id = source_assembly_id\n"
     "			return"),

    # §7.1's hysteresis band made unreachable. The fire never goes out, and a
    # part that catches once is a part that burns to nothing.
    ("fire-never-cools", RESOLVER,
     "const THERMAL_COOLING_HU_S: float = 18.0",
     "const THERMAL_COOLING_HU_S: float = 0.0"),

    # §7.3's cadence gate. Ten instalments a second becomes sixty, and the
    # documented burn rate is six times what it says.
    ("dot-cadence-ignored", SCHEDULER,
     "	if _accum_s < TICK_INTERVAL_S:\n		return",
     "	if false:\n		return"),

    # Doc 11 §4.3's first row on a chassis: the one figure that decides what a
    # player may bolt on, back to not being shown at all.
    ("carries-row-dropped", INSPECTOR,
     "	rows.append(Row.new(KEY_CARRIES, chassis_families(p.locomotion_mask)))",
     "	pass"),

    # §14.6's first-run flag consulted by nobody, which is the state the card
    # shipped in: raised over every match a player ever plays.
    ("control-card-always-raised", HUD,
     "	if not SyndicateSettings.control_card_seen:",
     "	if true:"),
]


if __name__ == "__main__":
    raise SystemExit(sweeplib.run_sweep(FAULTS, BASELINE, __doc__))
