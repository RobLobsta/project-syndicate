class_name MotiveAssemblyProfile
extends Resource
## Motive Assembly payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.2.
##
## Suspension is modelled per Motive Assembly by shape casts against the chassis
## body; Architectural Invariant I-3 forbids a joint here, so nothing in this
## profile may be interpreted as a physics constraint.

@export var kind: PartEnums.MotiveKind = PartEnums.MotiveKind.WHEELED_STEERED
@export var contact_radius_m: float = 0.42
@export var contact_width_m: float = 0.26
@export var suspension_rest_length_m: float = 0.32
@export var suspension_stiffness_n_m: float = 42000.0
@export var suspension_damping_ns_m: float = 3400.0
@export var suspension_travel_limit_m: float = 0.24
@export var max_steer_angle_deg: float = 32.0
@export var steer_rate_deg_s: float = 140.0
@export var rated_load_kg: float = 620.0
## Nominal value only. Degradation multipliers from DegradationTable and surface
## multipliers from SurfaceTable are applied on top of it by the traction solver.
@export var traction_coefficient: float = 1.05
@export var rolling_resistance: float = 0.014
@export var brake_torque_nm: float = 2600.0
@export var driven: bool = true
