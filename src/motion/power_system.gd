class_name PowerSystem
extends RefCounted
## Prime Mover and Energy Cell aggregation, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §7.5 and
## [code]docs/PART_DATA_SCHEMA.md[/code] §9.
##
## Recomputed on structural and band-change events only, never per tick
## (Architectural Invariant I-4). The per-tick path reads the three cached
## scalars this class produces and does no arithmetic over the part set.
##
## Both totals index [DegradationTable], so a damaged Power Plant reduces the
## Assembly's drive torque and its power supply by different amounts — torque
## falls faster, which is what makes a battered Assembly sluggish before it
## browns out.

## Total drive torque available, in N·m, after band degradation.
var drive_torque_nm: float = 0.0
## Total power supplied, in PU, after band degradation.
var supply_pu: float = 0.0
## Total power drawn, in PU. Includes a rotary Motive Assembly's full-collective
## shaft draw, which is why a rotary build's budget is conservative.
var draw_pu: float = 0.0


## Fraction of demanded power the Assembly can actually deliver, in [0, 1].
##
## Consumed by [method RotorSolver.commanded_omega], which scales the commanded
## angular rate rather than the thrust. Returns 1.0 when nothing is drawing, so
## an Assembly with no modules is not treated as starved.
func available_fraction() -> float:
	if draw_pu <= 0.0:
		return 1.0
	return clampf(supply_pu / draw_pu, 0.0, 1.0)


## True when demand exceeds supply and the starvation flag should be set.
func is_starved() -> bool:
	return draw_pu > supply_pu


## Recomputes every total from a live part set.
##
## [param states] is the Assembly's slot-indexed state array and [param alive]
## the Chassis Graph's liveness array, so a detached or destroyed part
## contributes nothing without this function needing to know why.
func recompute(states: Array, alive: PackedByteArray) -> void:
	drive_torque_nm = 0.0
	supply_pu = 0.0
	draw_pu = 0.0
	for slot: int in mini(states.size(), alive.size()):
		if alive[slot] == 0:
			continue
		var st: PartInstanceState = states[slot]
		if st == null or (st.flags & PartFlags.FLAG_DETACHED) != 0:
			continue
		var def := PartRegistry.definition(st.part_def_id)
		if def == null:
			continue
		var band := int(st.integrity_band)
		draw_pu += def.power_draw_pu
		supply_pu += (
			def.power_supply_pu
			* DegradationTable.multiplier(DegradationTable.POWER_SUPPLY, band)
		)
		if def.part_class == PartEnums.PartClass.PRIME_MOVER and def.prime_mover_profile != null:
			drive_torque_nm += (
				def.prime_mover_profile.drive_torque_nm
				* DegradationTable.multiplier(DegradationTable.POWER_TORQUE, band)
			)


## Drive torque reaching the ground after the throttle curve, in N·m.
##
## Clamped at zero rather than allowed negative: reverse is a negative contact
## rate, not a negative engine, and letting the torque go negative would spin
## every contact backwards on a brake application.
func throttle_torque_nm(throttle: float) -> float:
	return drive_torque_nm * clampf(throttle, -1.0, 1.0)
