#!/usr/bin/env python3
"""Fault sweep over doc 05 §16: where a Motive Assembly's mesh is drawn.

Eleven faults over the code this session added — the droop a contact hangs by,
the frame the droop is applied in, the pivot a limb turns about, and the swing
arc a foot is drawn along.

  visual-pass-never-runs        §16.4: the pass dropped from the tick
  droop-is-the-compression      §16.1: the travel used instead of the travel left
  droop-lifts-the-part          §16.1: the mesh raised rather than lowered
  droop-is-always-full          §16.1: full extension whatever the probe found
  an-ungrounded-wheel-tucks-up  §16.1: a wheel over a crest drawn in its cell
  droop-runs-down-the-part      §16.1: the offset composed in the part's frame
  limb-drawn-at-its-placement   §16.3: the leg never turns
  limb-turns-about-its-mesh     §16.3: the pivot is the mesh origin, not the hip
  a-planted-foot-keeps-the-arc  §16.3: stance drawn at the last swing sample
  swing-arc-does-not-lift       §13.7: the foot slides rather than steps
  swing-progress-from-the-top   §16.3: progress measured from the cycle, not swing

**Two of these are worth reading whatever the verdict.** `droop-runs-down-the-
part` is the composition error the whole of `PartMeshFactory.contact_pose`
exists to prevent, and it is invisible to every fixture in `tests/physics/`
because a Motive Assembly is only ever mounted upright there — the assertion
that sees it is the synthetic sideways orientation in
`tests/unit/test_part_mesh_pose.gd`. And `limb-turns-about-its-mesh` leaves the
limb pointing correctly at its foot, so every direction assertion passes: only
the fact that the mesh moved at all catches it.

**One fault is expected to survive and is here to prove it does.** A tracked
patch is drawn at the mean of its road stations, and on a flat slab every
station reports the same distance — so the mean and the first station are the
same number and no fixture in the suite can tell them apart. It needs a bogie
straddling a slope. Read a `SURVIVED` on `tracked-mean-is-its-first-station` as
the measurement it is, not as a defect to patch around.

    python3 tools/ci/sweeps/contact_visual_sweep.py            # all of them, 4 workers
    python3 tools/ci/sweeps/contact_visual_sweep.py --list
    python3 tools/ci/sweeps/contact_visual_sweep.py -j1 --full droop-lifts-the-part

The loop, the parallelism, the timeout and the fail-fast rule all live in
`sweeplib.py`; read that before changing how this runs. Update BASELINE in the
same change as anything that moves the check count, or every fault after it
reads as caught.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweeplib

SUSPENSION = "src/motion/suspension_solver.gd"
GAIT = "src/motion/gait_solver.gd"
MOTIVE = "src/motion/motive_system.gd"
FACTORY = "src/core/util/part_mesh_factory.gd"

BASELINE = 6111

FAULTS = [
    # §16.4's one call site. Every mesh stays at its placement pose for the whole
    # match, which is exactly the state this section was written to end.
    ("visual-pass-never-runs", MOTIVE,
     "	_deposit_ruts()\n	_drive_visuals()",
     "	_deposit_ruts()"),

    # The travel consumed instead of the travel left. The mesh moves, by a
    # plausible amount, in the wrong direction against the ground: a wheel rises
    # as its spring compresses.
    ("droop-is-the-compression", SUSPENSION,
     "	return profile.suspension_travel_limit_m - compression(profile, contact)",
     "	return compression(profile, contact)"),

    # The same quantity applied the other way up, in the factory rather than in
    # the solver, so the arithmetic is right and the frame is not.
    ("droop-lifts-the-part", FACTORY,
     "	t.origin += Vector3.DOWN * droop_m",
     "	t.origin += Vector3.UP * droop_m"),

    # Full extension whatever the probe found. A settled build's wheels hang a
    # travel below the hull and the springs are visibly doing nothing — and every
    # airborne assertion still passes, because full droop is what those expect.
    ("droop-is-always-full", SUSPENSION,
     "	return profile.suspension_travel_limit_m - compression(profile, contact)",
     "	return profile.suspension_travel_limit_m"),

    # The half §16.1 says needs no second code path, given one that gets it
    # wrong: a contact with nothing under it draws its part in its placed cell.
    # This is the shipped behaviour of before this session, confined to the case
    # where it was most visible.
    ("an-ungrounded-wheel-tucks-up", SUSPENSION,
     "	return profile.suspension_travel_limit_m - compression(profile, contact)",
     "	if not contact.grounded:\n		return 0.0\n"
     "	return profile.suspension_travel_limit_m - compression(profile, contact)"),

    # The offset composed in the part's own frame instead of the chassis's.
    # Identical for anything mounted upright, which is every Motive Assembly in
    # `tests/physics/`, and carries a sideways-mounted one out along the hull.
    ("droop-runs-down-the-part", FACTORY,
     "	var t := pose(vp, origin_cell, orientation_index)\n	t.origin += Vector3.DOWN * droop_m\n	return t",
     "	return (pose(vp, origin_cell, orientation_index)\n"
     "		* Transform3D(Basis(), Vector3.DOWN * droop_m))"),

    # §16.3 not applied at all. The legs of a walking Assembly never move, which
    # is the state the section was written to end and the one a green suite
    # tolerated for eight sessions.
    ("limb-drawn-at-its-placement", FACTORY,
     "	if to_foot.length() < SyndicateConstants.EPSILON_LINEAR:\n		return rest",
     "	if true:\n		return rest"),

    # The turn taken about the mesh's own origin rather than about the hip. The
    # limb still points exactly at its foot, so every direction assertion in the
    # suite is satisfied; what is wrong is that the hip leaves the chassis.
    ("limb-turns-about-its-mesh", FACTORY,
     "	return Transform3D(turn * rest.basis, hip_local + turn * (rest.origin - hip_local))",
     "	return Transform3D(turn * rest.basis, rest.origin)"),

    # Stance drawn at whatever the swing arc last sampled. The planted foot is a
    # fixed world anchor and the drawn one drifts off it — which reads as a limb
    # sliding while it is carrying the machine's weight.
    ("a-planted-foot-keeps-the-arc", MOTIVE,
     "	limb.foot_visual_world = limb.foot_world\n\n	if not now_stance:",
     "	if not now_stance:"),

    # §13.7's parabola dropped, leaving the foot sliding along the ground from
    # the point it left to the point it is reaching for. A gait with no step in
    # it, and every horizontal quantity still correct.
    ("swing-arc-does-not-lift", GAIT,
     "	return from_world.lerp(to_world, u) + Vector3.UP * swing_height_m(profile, u)",
     "	return from_world.lerp(to_world, u)"),

    # Progress measured from the top of the cycle rather than from lift-off, so
    # the foot starts each swing most of the way to its target and lifts by less
    # than the authored step height. Monotonic, in range, and wrong.
    ("swing-progress-from-the-top", GAIT,
     "	return clampf((phase - duty_factor) / span, 0.0, 1.0)",
     "	return clampf(phase, 0.0, 1.0)"),

    # Expected to survive. A tracked patch's stations all report the same
    # distance on a flat slab, so the mean and the first are one number and
    # nothing in the suite stands a bogie on a slope. See the docstring.
    ("tracked-mean-is-its-first-station", MOTIVE,
     "	var total := 0.0\n	for c: MotiveContact in contacts:\n"
     "		total += SuspensionSolver.droop_m(profile, c)\n	return total / float(contacts.size())",
     "	return SuspensionSolver.droop_m(profile, contacts[0])"),
]


if __name__ == "__main__":
    raise SystemExit(sweeplib.run_sweep(FAULTS, BASELINE, __doc__))
