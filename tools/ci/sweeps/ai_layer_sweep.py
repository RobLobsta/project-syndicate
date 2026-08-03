#!/usr/bin/env python3
"""Fault sweep over `src/ai/` and the two rules it made the match layer depend on.

Ten faults, planted against laws rather than against loops (handoff §9). Doc 05
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

`breakaway-never-releases` is expected to SURVIVE and is kept for that reason.
It is the change that was actually shipped for an afternoon: green on every
fixture in the suite, and it stopped the opponents ever reaching the player in
the real match, because `tests/combat_arena.gd` builds a flat slab and the arena
has fifteen metres of relief. Nothing in the suite can see it. The only thing
that catches it is a capture (handoff §3.55), and it stays here as the standing
reminder that this section's fixtures are not the game.

    python3 tools/ci/sweeps/ai_layer_sweep.py                  # all ten
    python3 tools/ci/sweeps/ai_layer_sweep.py steer-sign-flipped

Each fault is planted, the full suite runs, and the file is restored in a
`finally`. Two rules, both learned the hard way and both still true:

  * Do not `git add -A` while this is running. It will commit a planted fault.
  * Do not kill it between the write and the restore. Check `git status` after.

Caught is a non-zero exit, a recorded failure, *or* a check count that differs
from the baseline -- the last of those is what catches a fault that truncates the
suite into a green partial pass. Update BASELINE in the same change as anything
that moves the check count, or every fault after it reads as caught.
"""
import subprocess, sys, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
DRIVER = os.path.join(ROOT, "src/ai/ai_driver.gd")
SELECTOR = os.path.join(ROOT, "src/ai/ai_target_selector.gd")
ES = os.path.join(ROOT, "src/combat/effectors/effector_system.gd")
SCHED = os.path.join(ROOT, "src/assembly/graph/detachment_scheduler.gd")
GUN_TRES = os.path.join(ROOT, "data/parts/eff/eff.ballistic.autocannon_30.t3.tres")

BASELINE = 5130  # tools/ci/run_all_checks.sh at the commit this landed

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
]


def run():
    p = subprocess.run(["tools/ci/run_all_checks.sh"], cwd=ROOT,
                       capture_output=True, text=True)
    tail = p.stdout + p.stderr
    m = re.search(r"run_all_checks: (\d+) checks, (\d+) failures across (\d+)/(\d+) files", tail)
    return p.returncode, m.groups() if m else None, tail


only = sys.argv[1:] if len(sys.argv) > 1 else None
for name, path, old, new in FAULTS:
    if only and name not in only:
        continue
    src = open(path).read()
    if old not in src:
        print(f"{name}: PATCH-MISS", flush=True)
        continue
    open(path, "w").write(src.replace(old, new, 1))
    try:
        rc, g, tail = run()
    finally:
        open(path, "w").write(src)
    if g is None:
        print(f"{name}: rc={rc} NO-SUMMARY (crash/parse)", flush=True)
        continue
    checks, failures, badfiles, files = g
    caught = rc != 0 or int(failures) > 0 or int(checks) != BASELINE
    print(f"{name}: {'CAUGHT' if caught else 'SURVIVED'} "
          f"rc={rc} checks={checks} failures={failures}", flush=True)
    if caught and int(failures) > 0:
        for line in tail.splitlines():
            if "FAIL" in line or line.strip().startswith("test_"):
                print("    " + line.strip(), flush=True)
