class_name CoreModuleProfile
extends Resource
## Core Module payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.1.
##
## The Core Module is the Chassis Graph root and the sole [RigidBody3D] owner.
## Architectural Invariant I-2: there is exactly one per Assembly, always at
## slot 0, and losing it terminates the Assembly.

## Which locomotion families this chassis is built to carry, as one bit per
## [enum PartEnums.LocomotionMode]. Doc 01 §7.1, and the composite masks are
## [constant PartEnums.CHASSIS_WHEELED] and its three siblings.
##
## [PlacementValidator] refuses a Motive Assembly whose family this mask does not
## admit — and, since §7.3 gained its own mask, a Prime Mover that does not drive
## every family the hull declares.
##
## [b]The default was `CHASSIS_GROUND_TRANSITIONAL`, which is retired.[/b] That
## mask carried `GROUND` and `TRACKED` together so `core.command.compact.t2` — the
## road car — also accepted a bogie, on a reading the tracked family disproved and
## on the grounds that the shipped tracked recipe had nowhere else to live.
## Session 44 moved that recipe onto `core.tracked.hauler.t3` and the mask has
## been vestigial ever since. What forced the issue is §7.3's rule: a hull
## declaring two families needs a mover driving both, so the road car declaring a
## family it does not use would have refused every wheeled Prime Mover in the
## registry.
@export var locomotion_mask: int = PartEnums.CHASSIS_WHEELED

@export var power_capacity_pu: float = 240.0
@export var mount_budget: int = 28
@export var speed_cap_mps: float = 22.0
## Steering responsiveness multiplier.
@export var control_authority: float = 1.0
## Above this total Assembly mass, handling penalties accrue.
@export var mass_tolerance_kg: float = 4200.0
@export var operator_seat_offset_m: Vector3 = Vector3(0.0, 0.35, 0.0)
@export var respawn_integrity_fraction: float = 1.0


## True when this chassis carries locomotion family [param mode].
func carries(mode: int) -> bool:
	return PartEnums.chassis_carries(locomotion_mask, mode)
