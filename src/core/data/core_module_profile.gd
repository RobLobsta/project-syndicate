class_name CoreModuleProfile
extends Resource
## Core Module payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.1.
##
## The Core Module is the Chassis Graph root and the sole [RigidBody3D] owner.
## Architectural Invariant I-2: there is exactly one per Assembly, always at
## slot 0, and losing it terminates the Assembly.

## Which locomotion families this chassis is built to carry, as one bit per
## [enum PartEnums.LocomotionMode]. Doc 01 §7.1, and the composite masks are
## [constant PartEnums.CHASSIS_GROUND] and its two siblings.
##
## [PlacementValidator] refuses a Motive Assembly whose family this mask does not
## admit, which is what makes a chassis a chassis rather than a box every
## locomotion family is bolted to in turn. Defaulted to the ground families so
## that an unauthored profile behaves as every Core Module did before the field
## existed.
@export var locomotion_mask: int = PartEnums.CHASSIS_GROUND

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
