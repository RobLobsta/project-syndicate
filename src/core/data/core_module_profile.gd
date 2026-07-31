class_name CoreModuleProfile
extends Resource
## Core Module payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.1.
##
## The Core Module is the Chassis Graph root and the sole [RigidBody3D] owner.
## Architectural Invariant I-2: there is exactly one per Assembly, always at
## slot 0, and losing it terminates the Assembly.

@export var power_capacity_pu: float = 240.0
@export var mount_budget: int = 28
@export var speed_cap_mps: float = 22.0
## Steering responsiveness multiplier.
@export var control_authority: float = 1.0
## Above this total Assembly mass, handling penalties accrue.
@export var mass_tolerance_kg: float = 4200.0
@export var operator_seat_offset_m: Vector3 = Vector3(0.0, 0.35, 0.0)
@export var respawn_integrity_fraction: float = 1.0
