#!/usr/bin/env python3
"""Fault sweep over the paths the multi-Assembly engagements of session 15 rest on.

Six faults, chosen rather than enumerated, because a sweep now costs about four
and a half minutes a fault: the suite grew three engagement files and its
physics tests wait on real ticks at 60 Hz (LEARNED_FACTS.md §1). Six is twenty-seven
minutes, which is affordable in one session; thirty would not have been, and an
unfinished sweep is worse than a small finished one.

Each one targets a claim the new files make that nothing else in the suite
covers:

  self-immunity-zero        the duels' "a round never strikes its own Assembly"
  no-overpenetration        the grind file's whole subject
  recoil-not-applied        the nose-mount recoil measurement
  pitch-clamp-removed       the ambulatory mirror's "pinned against the stop"
  cyclic-pitch-inverted     the arena's rotary autopilot, and every airborne check
  cyclic-not-cone-clamped   §35's cone clamp, which holds the hover inside 14 degrees

    python3 tools/ci/sweeps/engagement_sweep.py               # all six
    python3 tools/ci/sweeps/engagement_sweep.py recoil-not-applied

Each fault is planted, the full suite runs, and the file is restored in a
`finally`. Two rules, both learned the hard way and both still true:

  * Do not `git add -A` while this is running. It will commit a planted fault.
  * Do not kill it between the write and the restore. Check `git status` after.

Caught is a non-zero exit, a recorded failure, *or* a check count that differs
from the baseline -- the last of those is what catches a fault that truncates the
suite into a green partial pass.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweeplib

PS = "src/combat/projectiles/projectile_system.gd"
ES = "src/combat/effectors/effector_system.gd"
AS = "src/combat/effectors/aim_solver.gd"
ARENA = "tests/combat_arena.gd"

# The check count at the commit this last ran clean. sweeplib measures the real
# one and warns if this disagrees, so a stale value here is a printed warning
# rather than a sweep that reports CAUGHT for everything.
BASELINE = 6165

FAULTS = [
    # A round may hit the Assembly that fired it the instant it leaves the
    # muzzle. The nose mount emits from 2.75 m ahead of the lattice origin, so
    # the line passes where the hull would be if the offset composition were
    # wrong by one step -- which is what the duels' self-hit check exists for.
    ("self-immunity-zero", PS,
     "const SELF_IMMUNITY_S: float = 0.06",
     "const SELF_IMMUNITY_S: float = 0.0"),

    # No round ever continues past what it hit. The grind cannot happen, and
    # tests/physics/test_overpenetration_grind.gd should say so loudly.
    # The whole point of doc 07 §12.2.2's budget, removed: a round may resolve
    # against one part and then keep resolving against it forever.
    ("penetration-budget-removed", PS,
     "		if resolved >= budget:\n			_release(index)\n			return",
     "		if false:\n			_release(index)\n			return"),

    # The budget counted from zero at the top of every tick instead of over the
    # round's life -- which is what the code did until session 16, and what let
    # the fault above survive its first sweep. A round crossing two hulls on two
    # consecutive ticks resolves eight packets against a bound of four.
    ("strikes-reset-each-tick", PS,
     "	var resolved := _strikes[index]",
     "	var resolved := 0"),

    # §12.2.1's strike record neutered: a round may hit the same part twice.
    ("same-part-twice-allowed", PS,
     "		if _already_struck(index, hit):\n			continue",
     "		if false:\n			continue"),

    # The within-tick continuation removed, which is the half of the fix that
    # stops a round crawling through a hull at a metre a second.
    ("sweep-does-not-continue", PS,
     "		from = Vector3(hit[\"position\"]) + direction * PENETRATION_STEP_M",
     "		from = to"),

    # Doc 07 §8's impulse never reaches the body. The pitch measurement still
    # passes -- zero is a small number -- and the rearward push is the half that
    # has to notice.
    ("recoil-not-applied", ES,
     "	runtime.body.apply_impulse(\n		-direction * profile.recoil_impulse_ns,",
     "	runtime.body.apply_impulse(\n		Vector3.ZERO * profile.recoil_impulse_ns,"),

    # A mount may elevate and depress without limit. Nothing ever sits on a
    # stop, and the finding recorded in the ambulatory mirror match evaporates.
    # §13.4's standing state: every foot planted. Without the re-plant an
    # Assembly commanded to stand from spawn never establishes a foot at all.
    ("standing-never-replants", "src/motion/motive_system.gd",
     "	if now_stance and (not was_planted or (standing and slack)):",
     "	if now_stance and not was_planted:"),

    # §13.5's turn command back to the sign that walked an Assembly left on a
    # demand to go right.
    ("gait-turn-sign-flipped", "src/motion/gait_solver.gd",
     "		var yaw := deg_to_rad(-profile.turn_rate_deg_s * turn_command * stance_s)",
     "		var yaw := deg_to_rad(profile.turn_rate_deg_s * turn_command * stance_s)"),

    # The placement law handed the chassis speed cap again, ten times what any
    # gait can deliver, which saturates the correction term permanently.
    ("gait-chases-chassis-speed", "src/motion/motive_system.gd",
     "	return minf(_speed_cap_mps(), GaitSolver.top_speed_mps(profile))",
     "	return _speed_cap_mps()"),

    # Doc 04 §8.2's producer removed. Nothing announces a terminated Assembly.
    ("no-assembly-terminated", "src/combat/damage/damage_resolver.gd",
     "	if st.slot == SyndicateConstants.CORE_SLOT:\n		EventBus.assembly_terminated.emit(",
     "	if false:\n		EventBus.assembly_terminated.emit("),

    # §4.3.1's gate: a mount pinned on its stop reads on-target again.
    ("arc-gate-removed", ES,
     "		hp.on_target = hp.solution_in_arc and AimSolver.is_converged(",
     "		hp.on_target = true and AimSolver.is_converged("),

    ("pitch-clamp-removed", AS,
     "	return clampf(desired_pitch, deg_to_rad(limit_deg.x), deg_to_rad(limit_deg.y))",
     "	return desired_pitch"),

    # The arena's autopilot solves the swash angles that point a disc along a
    # wanted world direction. Inverting the pitch half tips every rotary
    # Assembly the wrong way the moment it is asked to move.
    ("cyclic-pitch-inverted", ARENA,
     "	var pitch := asin(clampf(rest.z, -1.0, 1.0))",
     "	var pitch := -asin(clampf(rest.z, -1.0, 1.0))"),

    # §35: two 14 degree deflections clamped per component compose to 19.8 of
    # resultant tilt. Replacing the cone clamp with a per-axis one lets the
    # autopilot ask for more than the swashplate has.
    ("cyclic-not-cone-clamped", ARENA,
     "	return Vector2(rad_to_deg(pitch), rad_to_deg(roll)).limit_length(limit) / limit",
     "	return Vector2(\n		clampf(rad_to_deg(pitch), -limit, limit),\n"
     "		clampf(rad_to_deg(roll), -limit, limit)\n	) / limit"),
]


if __name__ == "__main__":
    raise SystemExit(sweeplib.run_sweep(FAULTS, BASELINE, __doc__))
