#!/usr/bin/env python3
"""Fault sweep over the damage layer, the effector layer, and doc 08 §8.4.

Session 14 planted these 37 and ran 4 before running out of session; the other
33 are the handoff's §8 item 0 and are the first thing the next session should
do. Committed rather than left in a scratchpad precisely because it was not
finished -- a sweep script that only exists while its author is still in the room
is how eight faults went unrun between sessions 12 and 13.

    python3 tools/ci/sweeps/combat_layer_sweep.py            # all of them
    python3 tools/ci/sweeps/combat_layer_sweep.py aim-yaw-sign   # one by name

Each fault is planted, the full suite runs, and the file is restored in a
`finally`. Two rules, both learned the hard way:

  * Do not `git add -A` while this is running. It will commit a planted fault.
  * Do not kill it between the write and the restore. Check `git status` after.

Caught is determined by a non-zero exit, a recorded failure, *or* a check count
that differs from the baseline -- the last of those is what catches a fault that
truncates the suite into a green partial pass.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweeplib

DR = "src/combat/damage/damage_resolver.gd"
AS = "src/combat/effectors/aim_solver.gd"
ES = "src/combat/effectors/effector_system.gd"
PS = "src/combat/projectiles/projectile_system.gd"
AL = "src/combat/effectors/ammo_ledger.gd"
MS = "src/motion/motive_system.gd"
ID = "src/assembly/graph/island_detacher.gd"

MP = "src/core/data/melee_profile.gd"

# The check count at the commit this last ran clean. sweeplib measures the real
# one and warns if this disagrees, so a stale value here is a printed warning
# rather than a sweep that reports CAUGHT for everything.
BASELINE = 5258

FAULTS = [
    # --- DamageResolver, §4 -------------------------------------------
    ("ricochet-angle-gate-dropped", DR,
     "	if cos_theta >= RICOCHET_COS:\n		return false",
     "	if false:\n		return false"),
    ("blast-exponent-linear", DR,
     "	return pow(1.0 - clampf(distance_m / radius_m, 0.0, 1.0), BLAST_EXPONENT)",
     "	return 1.0 - clampf(distance_m / radius_m, 0.0, 1.0)"),
    ("impact-threshold-removed", DR,
     "	if v_eff <= IMPACT_THRESHOLD_MPS:\n		return 0.0",
     "	if v_eff <= 0.0:\n		return 0.0"),
    ("impact-cap-removed", DR,
     "	return minf(IMPACT_K * pow(v_eff - IMPACT_THRESHOLD_MPS, IMPACT_EXPONENT), IMPACT_MAX_PER_CONTACT)",
     "	return IMPACT_K * pow(v_eff - IMPACT_THRESHOLD_MPS, IMPACT_EXPONENT)"),
    ("band-boundary-inclusive", DR,
     "	if fraction < SyndicateConstants.BAND_STRESSED:\n		return PartEnums.IntegrityBand.STRESSED",
     "	if fraction <= SyndicateConstants.BAND_STRESSED:\n		return PartEnums.IntegrityBand.STRESSED"),
    ("armour-band-multiplier-dropped", DR,
     "	var armour := def.armour_rating * DegradationTable.ARMOUR_RATING[int(st.integrity_band)]\n\n	match packet.channel:",
     "	var armour := def.armour_rating\n\n	match packet.channel:"),
    ("resistance-dropped", DR,
     "	var resisted := packet.raw_amount * (\n		1.0 - st.effective_resistance(def, int(packet.channel))\n	)",
     "	var resisted := packet.raw_amount"),
    ("destruction-never-flagged", DR,
     "	st.flags |= PartFlags.FLAG_DESTROYED\n	st.integrity = 0.0",
     "	st.integrity = 0.0"),
    ("destroyed-event-never-emitted", DR,
     "	EventBus.part_destroyed.emit(runtime.assembly_id, st.slot, int(packet.channel))",
     "	pass"),
    ("band-transition-never-written", DR,
     "	if band_after != band_before:\n		st.integrity_band = band_after\n		destroyed = _on_band_transition(runtime, st, def, band_before, band_after, packet)",
     "	if band_after != band_before:\n		destroyed = _on_band_transition(runtime, st, def, band_before, band_after, packet)"),
    ("dead-parts-still-damageable", DR,
     "	if st == null or st.has_flag(PartFlags.FLAG_DESTROYED | PartFlags.FLAG_DETACHED):\n		return DamageOutcome.rejected(\"part not live\")",
     "	if st == null:\n		return DamageOutcome.rejected(\"part not live\")"),
    ("integrity-floor-removed", DR,
     "	st.integrity = maxf(0.0, st.integrity - effective)",
     "	st.integrity = st.integrity - effective"),
    # --- AimSolver, §3-4 ----------------------------------------------
    ("aim-yaw-sign", AS,
     "	return Vector2(atan2(-d.x, -d.z), atan2(d.y, horizontal))",
     "	return Vector2(atan2(d.x, d.z), atan2(d.y, horizontal))"),
    ("aim-pitch-sign", AS,
     "	return Vector2(atan2(-d.x, -d.z), atan2(d.y, horizontal))",
     "	return Vector2(atan2(-d.x, -d.z), -atan2(d.y, horizontal))"),
    ("direction-forward-flipped", AS,
     "	return Vector3(-sin(yaw_rad) * horizontal, sin(pitch_rad), -cos(yaw_rad) * horizontal)",
     "	return Vector3(sin(yaw_rad) * horizontal, sin(pitch_rad), cos(yaw_rad) * horizontal)"),
    ("slew-band-multiplier-ignored", AS,
     "	var step := deg_to_rad(rate_deg_s) * band_multiplier * dt",
     "	var step := deg_to_rad(rate_deg_s) * dt"),
    ("yaw-convergence-not-wrapped", AS,
     "	var yaw_error := absf(wrapf(yaw_target_rad - yaw_rad, -PI, PI))",
     "	var yaw_error := absf(yaw_target_rad - yaw_rad)"),
    ("pitch-convergence-wrapped", AS,
     "	var pitch_error := absf(pitch_target_rad - pitch_rad)",
     "	var pitch_error := absf(wrapf(pitch_target_rad - pitch_rad, -PI, PI))"),
    ("full-traverse-clamped", AS,
     "	if limit_deg.y - limit_deg.x >= 360.0:\n		return wrapf(desired_yaw, -PI, PI)",
     "	if false:\n		return wrapf(desired_yaw, -PI, PI)"),
    ("cone-uniform-in-angle", AS,
     "	var z := rng.randf_range(cos_max, 1.0)",
     "	var z := cos(rng.randf_range(0.0, half_angle_rad))"),
    ("cone-basis-degenerate", AS,
     "	var reference := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT",
     "	var reference := Vector3.UP"),
    # --- EffectorSystem, §7 -------------------------------------------
    ("fire-gate-ignores-aim", ES,
     "	if not hp.on_target:\n		return false",
     "	if false:\n		return false"),
    ("fire-gate-ignores-ammo", ES,
     "	if ammo != null and not ammo.has_rounds(runtime.assembly_id, _projectile_id[slot]):\n		return false",
     "	if false:\n		return false"),
    ("fire-gate-ignores-timers", ES,
     "	if not hp.timers_clear():\n		return false",
     "	if false:\n		return false"),
    ("melee-modules-emit", ES,
     "	if profile.is_melee():\n		return false",
     "	if false:\n		return false"),
    ("cycle-timer-never-set", ES,
     "	hp.cycle_timer_s = profile.cycle_time_s * _cycle_mult[slot]",
     "	hp.cycle_timer_s = 0.0"),
    ("muzzle-ignores-mount-rotation", ES,
     "	var mount := Transform3D(Basis.from_euler(Vector3(pitch_rad, yaw_rad, 0.0)), Vector3.ZERO)",
     "	var mount := Transform3D()"),
    ("ammo-never-consumed", ES,
     "	if ammo != null:\n		ammo.consume(runtime.assembly_id, _projectile_id[slot], 1)",
     "	pass"),
    # --- ProjectileSystem, §12 ----------------------------------------
    # Re-targeted in session 18. Session 14 planted this against a line session 16
    # rewrote when it closed §4.13, so it reported PATCH-MISS for three sessions
    # and the swept ray -- which §5 calls the one place in the combat layer where
    # the obvious implementation is silently wrong -- went undefended.
    ("sweep-becomes-point-test", PS,
     "	var from := _prev_position[index]\n	var to := _position[index]",
     "	var from := _position[index] - _velocity[index].normalized() * 0.01\n	var to := _position[index]"),
    ("rounds-never-expire", PS,
     "		if _life_s[i] <= 0.0:\n			_release(i)\n			continue",
     "		if false:\n			_release(i)\n			continue"),
    ("self-immunity-always-on", PS,
     "	if age >= SELF_IMMUNITY_S or not _owner_rid[index].is_valid():\n		return []",
     "	if not _owner_rid[index].is_valid():\n		return []"),
    # Also re-targeted in session 18, and against the same rewrite.
    ("hit-never-releases-the-round", PS,
     "		if not _report_hit(index, def, hit):\n			_release(index)\n			return",
     "		if not _report_hit(index, def, hit):\n			return"),
    # --- EffectorSystem melee, §15.3 and §15.4 ------------------------
    # The shape. A sphere at the blade's midpoint is what shipped for four
    # sessions and it is §15.1's mistake made thicker: an edge is a volume, and
    # a ball on a point of it queries 0.36 m of a 2.40 m blade.
    ("melee-sphere-not-capsule", ES,
     "	var capsule := CapsuleShape3D.new()\n	capsule.radius = melee.edge_radius_m\n"
     "	capsule.height = maxf(melee.reach_m, melee.edge_radius_m * 2.0)",
     "	var capsule := SphereShape3D.new()\n	capsule.radius = melee.edge_radius_m"),
    # The orientation. A capsule runs along its own +Y, so without the quarter
    # turn the blade stands vertically through the wielder's own hull.
    ("melee-capsule-not-rotated", ES,
     "		params.transform = edge * EDGE_TO_CAPSULE",
     "		params.transform = edge"),
    # §15.4's impulse direction, and §15.1's third reason a projectile is wrong.
    # The blade axis and the edge's travel are perpendicular unit vectors out of
    # one transform, so only a direction assertion separates them.
    #
    # Planted on the impulse rather than on the packet. The first version of this
    # patched `var direction := travel.normalized()` and SURVIVED, because that
    # local reaches only the packet's own direction fields -- and the packet's
    # normal is derived from its direction, so §4's ricochet test sees the two
    # exactly opposed whatever either of them is. See §5.
    ("melee-travel-is-blade-axis", ES,
     "		MeleeSolver.strike_impulse(melee, travel),",
     "		MeleeSolver.strike_impulse(melee, -edge.basis.z),"),
    # §15.4's impulse on the struck Assembly. Applied to a frozen body it is
    # unobservable, which is why the fixture leaves the target free.
    ("melee-no-target-impulse", ES,
     "	victim.body.apply_impulse(\n		MeleeSolver.strike_impulse(melee, travel),\n"
     "		edge.origin - victim.body.global_transform.origin\n	)",
     "	pass"),
    # §15.4's gate is inert on the shipped edge, which authors a zero minimum --
    # so the fault that tests it is one that makes it refuse everything, not one
    # that changes a threshold nothing reaches.
    ("melee-closing-speed-gate-always-refuses", ES,
     "	if not MeleeSolver.closing_speed_satisfied(melee, _closing_speed_on(victim)):\n		return",
     "	if true:\n		return"),
    # §15.3's per-swing dedup, which is what makes the sample count invisible to
    # balance. Without it a 16-sample swing deals sixteen times a 6-sample one.
    ("melee-strike-not-deduplicated", ES,
     "	state.struck_this_swing.append(victim.assembly_id)\n	state.last_strike_point_world",
     "	state.last_strike_point_world"),
    # The sample count itself. 6 across a 150° arc leaves a 1.26 m hole at the
    # blade tip; §15.3's gap arithmetic is what says so.
    ("melee-sample-count-back-to-six", MP,
     "@export var swing_samples: int = 16",
     "@export var swing_samples: int = 6"),
    # --- AmmoLedger, §9.2 ---------------------------------------------
    # --- band dispatch (doc 08 §8.4) ----------------------------------
    ("motive-never-subscribes", MS,
     "	EventBus.part_band_changed.connect(_on_part_band_changed)",
     "	pass"),
    ("effector-never-subscribes", ES,
     "	EventBus.part_band_changed.connect(_on_part_band_changed)",
     "	pass"),
    ("motive-id-filter-dropped", MS,
     "	if runtime == null or assembly_id != runtime.assembly_id:\n		return\n	if _motive_slots.has(slot):",
     "	if runtime == null:\n		return\n	if _motive_slots.has(slot):"),
    ("effector-slot-filter-dropped", ES,
     "	if _hardpoints.has(slot):\n		on_band_changed(slot, after)",
     "	on_band_changed(slot, after)"),
    ("consume-does-not-reduce", AL,
     "	store[projectile_id] = held - taken",
     "	store[projectile_id] = held"),
    # --- IslandDetacher, doc 04 §6 ------------------------------------
    # §3.19's ordering rule. Writing the transform while the body is still
    # shapeless leaves it with the broadphase entry it had when empty, and every
    # query against it afterwards returns nothing -- a debris body that renders
    # in the right place and cannot be hit. Invisible to every assertion that
    # reads the node rather than the space.
    ("debris-transform-before-shapes", ID,
     "	var body := pool.acquire()\n	body.source_assembly_id = runtime.assembly_id",
     "	var body := pool.acquire()\n	body.global_transform = runtime.body.global_transform\n"
     "	body.source_assembly_id = runtime.assembly_id"),
]


if __name__ == "__main__":
    raise SystemExit(sweeplib.run_sweep(FAULTS, BASELINE, __doc__))
