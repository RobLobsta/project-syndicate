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
import subprocess, sys, os, re

ROOT = "/home/user/project-syndicate"
DR = os.path.join(ROOT, "src/combat/damage/damage_resolver.gd")
AS = os.path.join(ROOT, "src/combat/effectors/aim_solver.gd")
ES = os.path.join(ROOT, "src/combat/effectors/effector_system.gd")
PS = os.path.join(ROOT, "src/combat/projectiles/projectile_system.gd")
AL = os.path.join(ROOT, "src/combat/effectors/ammo_ledger.gd")
MS = os.path.join(ROOT, "src/motion/motive_system.gd")

BASELINE = 4256  # tools/ci/run_all_checks.sh at the commit this landed

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
    ("sweep-becomes-point-test", PS,
     "	var params := PhysicsRayQueryParameters3D.create(_prev_position[index], _position[index])",
     "	var params := PhysicsRayQueryParameters3D.create(_position[index], _position[index] + _velocity[index].normalized() * 0.01)"),
    ("rounds-never-expire", PS,
     "		if _life_s[i] <= 0.0:\n			_release(i)\n			continue",
     "		if false:\n			_release(i)\n			continue"),
    ("self-immunity-always-on", PS,
     "	if age >= SELF_IMMUNITY_S or not _owner_rid[index].is_valid():\n		return []",
     "	if not _owner_rid[index].is_valid():\n		return []"),
    ("hit-never-releases-the-round", PS,
     "	var continued := _report_hit(index, def, hit)\n	if continued:",
     "	var continued := true\n	if continued:"),
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
            if "FAIL" in line:
                print("    " + line.strip(), flush=True)
