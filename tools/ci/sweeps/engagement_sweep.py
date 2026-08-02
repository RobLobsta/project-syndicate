#!/usr/bin/env python3
"""Fault sweep over the paths the multi-Assembly engagements of session 15 rest on.

Six faults, chosen rather than enumerated, because a sweep now costs about four
and a half minutes a fault: the suite grew three engagement files and its
physics tests wait on real ticks at 60 Hz (handoff §2). Six is twenty-seven
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
import subprocess, sys, os, re

ROOT = "/home/user/project-syndicate"
PS = os.path.join(ROOT, "src/combat/projectiles/projectile_system.gd")
ES = os.path.join(ROOT, "src/combat/effectors/effector_system.gd")
AS = os.path.join(ROOT, "src/combat/effectors/aim_solver.gd")
ARENA = os.path.join(ROOT, "tests/combat_arena.gd")

BASELINE = 4325  # tools/ci/run_all_checks.sh at the commit this landed

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
    ("no-overpenetration", PS,
     "	var continued := _report_hit(index, def, hit)\n	if continued:",
     "	var continued := _report_hit(index, def, hit)\n	if false and continued:"),

    # Doc 07 §8's impulse never reaches the body. The pitch measurement still
    # passes -- zero is a small number -- and the rearward push is the half that
    # has to notice.
    ("recoil-not-applied", ES,
     "	runtime.body.apply_impulse(\n		-direction * profile.recoil_impulse_ns,",
     "	runtime.body.apply_impulse(\n		Vector3.ZERO * profile.recoil_impulse_ns,"),

    # A mount may elevate and depress without limit. Nothing ever sits on a
    # stop, and the finding recorded in the ambulatory mirror match evaporates.
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
