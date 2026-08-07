class_name PrimeMoverProfile
extends Resource
## Prime Mover payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.3.
##
## A Prime Mover converts stored energy into shaft torque. It is the only class
## that produces [member drive_torque_nm], and an Assembly with none of them
## supplies power to its modules and drives nowhere.
##
## The class was called `POWER_PLANT` and carried both roles until §7.3 was split
## (§10.4). The name is the standard engineering term for a machine that turns
## energy into motion, and it is deliberately not *engine*: CLAUDE.md §8
## prohibits that word in identifiers, and the class covers a turbine and a
## reaction mass driver as readily as a piston.

## ===== FAMILY =========================================================

## Which locomotion families this Prime Mover is built to drive, as one bit per
## [enum PartEnums.LocomotionMode] — the same encoding
## [member CoreModuleProfile.locomotion_mask] uses, and read through the same
## [method PartEnums.chassis_carries].
##
## [b]It exists so that a family can be tuned without tuning the other three.[/b]
## Two Prime Movers used to carry four families between them: one slab drove
## every wheeled build and one upright block drove the tank, the quadruped, the
## biped and the rotorcraft. Every torque figure in the game was therefore a
## compromise across machines that share nothing — a 3.5 t road car and a 10.5 t
## tracked hauler ran the same 6400 N·m — and the visible consequence was that
## `HANDOFF.md` §3.1.1 sat blocked for four sessions with a measured, correct
## raise nobody could apply, because applying it moved every locomotion family in
## the suite at once.
##
## A mask rather than a single family because the wheeled pair is real: the road
## car mounts a flat slab as an engine bay behind the cabin and the utility truck
## mounts an upright block as a bonnet, and those are two sections of one
## family's mover rather than two families. Nothing here forbids a genuinely
## multi-family mover; what it forbids is one arriving by accident.
##
## Defaulted to every family, so an unauthored profile behaves exactly as every
## Prime Mover did before this field existed and no `.tres` is silently narrowed.
@export var locomotion_mask: int = PartEnums.CHASSIS_ANY

## ===== SHAFT ==========================================================

@export var drive_torque_nm: float = 3200.0
## Normalised angular rate on X, torque scalar on Y.
@export var torque_curve: Curve = null
@export var peak_angular_rpm: float = 5200.0
@export var throttle_response_s: float = 0.18

## ===== THERMAL AND FAILURE ============================================

@export var thermal_throttle_start_hu: float = 620.0
@export var thermal_shutdown_hu: float = 900.0
@export var detonation_blast_radius_m: float = 4.2
@export var detonation_blast_damage: float = 380.0


## True when this Prime Mover drives locomotion family [param mode].
func drives(mode: int) -> bool:
	return PartEnums.chassis_carries(locomotion_mask, mode)
