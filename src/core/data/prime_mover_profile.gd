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
