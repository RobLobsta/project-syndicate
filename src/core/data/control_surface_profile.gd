class_name ControlSurfaceProfile
extends Resource
## Control Surface payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.6.
## Consumed by the aerodynamics solver in [code]docs/DYNAMIC_MASS_PHYSICS.md[/code].

@export var reference_area_m2: float = 0.34
## Negative values are downforce, which is the usual case for a ground Assembly.
@export var lift_coefficient: float = -0.62
@export var drag_coefficient: float = 0.11
@export var stall_angle_deg: float = 14.0
@export var pressure_centre_offset_m: Vector3 = Vector3.ZERO
