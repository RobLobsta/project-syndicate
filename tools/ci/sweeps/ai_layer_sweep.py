#!/usr/bin/env python3
"""Fault sweep over `src/ai/` and the two rules it made the match layer depend on.

Ten faults, planted against laws rather than against loops (LEARNED_FACTS.md §3). Doc 05
§15.7 and doc 07 §10 are the subjects, plus the duplicate `assembly_terminated`
producer session 23 removed — which had been held in place by a fixture asserting
the wrong half of doc 04 §8.2, so it gets a fault of its own to stop it coming
back.

  steer-sign-flipped          §15.7.1's negation: a driver that turns away
  throttle-taper-removed      §15.7.1's cosine, without which a wheeled build spirals
  fire-discipline-removed     §15.7.4: firing on the move yaws the hull off its heading
  aim-point-read-from-scan    §10 vs §10.3: aiming at where the target was 350 ms ago
  team-filter-dropped         §10's first line: an AI that shoots its own side
  range-gate-removed          §10's 320 m
  arc-cost-always-reachable   §10.2's penalty, permanently unpaid
  difficulty-error-flat       §10.3's error no longer growing with range
  scan-stagger-constant       §10.4: every driver scanning on the same tick
  terminated-emitted-twice    doc 04 §8.2's "nothing else may emit it", restored
  breakaway-removed           §15.7.1's standing start: the build never comes round
  breakaway-never-releases    the same, applied at every speed -- a STANDING SURVIVOR
  bore-off-centreline         doc 01 §14 rule 27, on the shipped data
  arrival-brake-removed       §15.7.1's arrival law: the driver rams what it aimed at
  closure-is-speed-not-projection  the same law, asked for the wrong quantity
  stand-off-inside-the-hulls       the stand-off back inside the two hulls

`breakaway-never-releases` is the change that actually shipped for an afternoon:
the standing-start demand applied at every speed, so it becomes a sustained heavy
throttle. It stopped the opponents ever reaching the player on the arena's real
terrain while every fixture in the suite stayed green, because
`tests/combat_arena.gd` builds a flat slab and the arena has fifteen metres of
relief.

**Read its history before trusting any verdict in this file.** It was a survivor
in session 24, CAUGHT in session 30, and is a survivor again in session 31 —
three verdicts without one line of the code it defends being touched. Session 30
caught it because with no arrival brake a sustained throttle made the driver
orbit its own stand-off, which `test_ai_engagement`'s rounds floor is sensitive
to. Session 31's arrival brake stops a driver orbiting whatever its throttle is
doing, so the symptom that fixture was reading is gone. A sweep verdict is a
statement about the fixtures and not about the rule. What closes this one is
terrain in a fixture, or a capture (`LEARNED_FACTS.md` §1 fact 55).

`aim-point-read-from-scan` is the other standing survivor and is marginal rather
than firmly one thing: CAUGHT on one run and SURVIVED on the next, either side of
an unrelated change. Read it as untested rather than as tested.

**Run `--full` before believing a CAUGHT here.** Fail-fast stops at the first
failing file, and the three faults session 31 added against §15.7.1's arrival law
all reported CAUGHT at 871 checks from the same unit test. Under `--full`,
`stand-off-inside-the-hulls` turned out to be caught by nothing else at all — the
physics fixture's gap assertion was passing by eight centimetres — and the
assertion was tightened rather than the result accepted.

    python3 tools/ci/sweeps/ai_layer_sweep.py            # all of them, 4 workers
    python3 tools/ci/sweeps/ai_layer_sweep.py -j1 --full steer-sign-flipped

The loop, the parallelism, the timeout and the fail-fast rule all live in
`sweeplib.py`; read that before changing how this runs. Update BASELINE in the
same change as anything that moves the check count, or every fault after it
reads as caught.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweeplib

DRIVER = "src/ai/ai_driver.gd"
SELECTOR = "src/ai/ai_target_selector.gd"
ES = "src/combat/effectors/effector_system.gd"
SCHED = "src/assembly/graph/detachment_scheduler.gd"
GUN_TRES = "data/parts/eff/eff.ballistic.autocannon_30.t3.tres"

# The check count at the commit this last ran clean. sweeplib measures the real
# one and warns if this disagrees, so a stale value here is a printed warning
# rather than a sweep that reports CAUGHT for everything.
BASELINE = 6165

FAULTS = [
    # §15.7.1's whole sign rule. Positive steer is right and a right turn is a
    # negative rotation about the world up, so dropping the negation drives the
    # Assembly away from what it is aiming at -- and the mount traverses 360°, so
    # it keeps shooting the whole time and every firing assertion still passes.
    ("steer-sign-flipped", DRIVER,
     "	return clampf(-bearing_rad / STEER_SATURATION_RAD, -1.0, 1.0)",
     "	return clampf(bearing_rad / STEER_SATURATION_RAD, -1.0, 1.0)"),

    # §15.7.1's cosine, back to the boolean it replaced. Measured: a wheeled
    # build spawned facing away spirals outward at constant bearing and never
    # closes.
    ("throttle-taper-removed", DRIVER,
     "	var demand := clampf(cos(bearing_rad), APPROACH_MIN_THROTTLE, 1.0)",
     "	var demand := 1.0"),

    # §15.7.4. The trigger held through the approach. The recoil is applied at a
    # muzzle 2.25 m forward of the centre of mass, so a traversed mount yaws the
    # hull sixty-five times harder than one firing dead ahead, and the driver
    # never comes round.
    ("fire-discipline-removed", DRIVER,
     "		guns.set_trigger(0, not _closing)",
     "		guns.set_trigger(0, true)"),

    # §10 runs selection at 2.9 Hz and aim solving every tick. Reading the aim
    # point off the scan's handle collapses the two, and the mount converges on
    # where the target was up to 350 ms ago.
    ("aim-point-read-from-scan", DRIVER,
     "	_target_point = target.part_world_position(SyndicateConstants.CORE_SLOT)",
     "	if _context.handle_for_id(_target_id) != null:\n"
     "		_target_point = _context.handle_for_id(_target_id).position"),

    # §10's first line. An AI that shoots its own side.
    ("team-filter-dropped", SELECTOR,
     "		if candidate.team == ctx.team:\n			continue",
     "		if false:\n			continue"),

    # §10's engagement range, so a driver acquires a target on the far side of
    # the map and drives at it.
    ("range-gate-removed", SELECTOR,
     "		if d > MAX_ENGAGEMENT_RANGE_M:\n			continue",
     "		if false:\n			continue"),

    # §10.2's arc cost, permanently unpaid: every candidate reads as reachable,
    # including one under a mount that can depress 8 degrees.
    #
    # Anchored on `reaches`'s return expression rather than on its null guard.
    # The guard's three lines appear twice in this file -- `can_fire` opens the
    # same way -- and `.replace(old, new, 1)` took the first, so the first version
    # of this fault made every module able to fire and reported CAUGHT with 19
    # failures across five files that have nothing to do with target selection.
    # Handoff §2.0: ask what reads the line before planting a fault on it, and
    # read a CAUGHT with an implausible blast radius as suspiciously as a
    # SURVIVED.
    ("arc-cost-always-reachable", ES,
     "	return (\n"
     "		is_equal_approx(AimSolver.clamp_yaw(angles.x, profile.yaw_limit_deg), angles.x)\n"
     "		and is_equal_approx(AimSolver.clamp_pitch(angles.y, profile.pitch_limit_deg), angles.y)\n"
     "	)",
     "	return true"),

    # §10.3's error no longer scaling with range, so a driver is as accurate at
    # 300 m as at 30 -- which is the shape of an AI that feels like it cheats.
    ("difficulty-error-flat", SELECTOR,
     "		* (distance / SIGMA_REFERENCE_RANGE_M)",
     "		* 1.0"),

    # §10.4's stagger. Every driver in the match scans on the same tick forever.
    ("scan-stagger-constant", SELECTOR,
     "	return fposmod(float(assembly_id) * SCAN_STAGGER_STEP_S, SCAN_INTERVAL_S)",
     "	return 0.0"),

    # Doc 04 §8.2's "nothing else may emit it", violated again. This is the
    # defect session 23 removed, and it was live for seven sessions because the
    # fixture that should have caught it asserted the duplicate instead.
    ("terminated-emitted-twice", SCHED,
     "		_announce(assembly_id, component)\n	# And nothing is emitted here.",
     "		_announce(assembly_id, component)\n"
     "	EventBus.assembly_terminated.emit(assembly_id, 0)\n"
     "	# And nothing is emitted here."),

    # §15.7.1's breakaway, removed so the taper's floor is all there is. That is
    # the state the law was in before the standing start was measured: the build
    # settles at about 0.2 m/s with the lock over and never comes round.
    ("breakaway-removed", DRIVER,
     "	if speed_mps < APPROACH_BREAKAWAY_SPEED_MPS:",
     "	if false:"),

    # And the opposite error, which is the one that shipped for an afternoon:
    # the breakaway applied at every speed, so it becomes a sustained heavy
    # throttle rather than a standing start. Green on a flat slab; it is what
    # stopped the opponents ever reaching the player on real terrain.
    ("breakaway-never-releases", DRIVER,
     "	if speed_mps < APPROACH_BREAKAWAY_SPEED_MPS:",
     "	if speed_mps < 1000.0:"),

    # Doc 01 §14 rule 27, planted on the shipped data rather than on the tool
    # that writes it: the bore back onto the pivot cell, which for an even-width
    # footprint is half a cell off its own centreline. This is the exact defect
    # the module carried until rule 27 existed, expressed as one number.
    #
    # The generator is deliberately not the target. Patching
    # `tools/author_combat_parts.gd` changes nothing until somebody re-runs it,
    # so a fault planted there would report SURVIVED for a reason that has
    # nothing to do with what is being defended -- §2.0's lesson about reading a
    # result whose blast radius does not match its subject, in advance.
    ("bore-off-centreline", GUN_TRES,
     "muzzle_offsets_m = PackedVector3Array(-0.125, 0, -2.125)",
     "muzzle_offsets_m = PackedVector3Array(0, 0, -2.125)"),

    # §15.7.1's arrival brake, deleted outright. This is the state the section
    # was in for every session up to 31: a driver spawned facing its target
    # holds full throttle for the whole run-in and a bare throttle cut is all
    # that is between it and whatever is standing on the mark. Measured at
    # 18.2 m/s of arrival speed and 146.2° of roll on the thing it hit.
    ("arrival-brake-removed", DRIVER,
     "	if closure_mps <= ARRIVAL_CLOSURE_DEADBAND_MPS:\n		return 0.0",
     "	if true:\n		return 0.0"),

    # The same law asked for the wrong quantity: the Assembly's speed rather than
    # the component of it along the bearing. A driver crossing in front of its
    # target then brakes for a range it is not closing, which is what would stop
    # §15.7.5's outer rungs ever taking station.
    #
    # Planted where the law is stated rather than where it is used, because the
    # brake itself is a closed loop and a loop absorbs an error in the quantity
    # it is closing over (LEARNED_FACTS.md §2.1).
    ("closure-is-speed-not-projection", DRIVER,
     "	return Vector3(velocity.x, 0.0, velocity.z).dot(flat.normalized())",
     "	return Vector3(velocity.x, 0.0, velocity.z).length()"),

    # And the largest of the three, as one number: the stand-off back inside the
    # hulls. Two reference builds touch at 4.8 m of origin separation, so 6.0 is
    # nose-to-nose parking with 1.2 m of air against an arrival overshoot of
    # about the same. No approach law rescues it.
    ("stand-off-inside-the-hulls", DRIVER,
     "const GROUND_STAND_OFF_M: float = 10.0",
     "const GROUND_STAND_OFF_M: float = 6.0"),
]


if __name__ == "__main__":
    raise SystemExit(sweeplib.run_sweep(FAULTS, BASELINE, __doc__))
