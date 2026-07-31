class_name PowerPlantProfile
extends Resource
## Power Plant payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.3.

@export var drive_torque_nm: float = 3200.0
## Normalised angular rate on X, torque scalar on Y.
@export var torque_curve: Curve = null
@export var peak_angular_rpm: float = 5200.0
@export var throttle_response_s: float = 0.18
@export var thermal_throttle_start_hu: float = 620.0
@export var thermal_shutdown_hu: float = 900.0
@export var detonation_blast_radius_m: float = 4.2
@export var detonation_blast_damage: float = 380.0
