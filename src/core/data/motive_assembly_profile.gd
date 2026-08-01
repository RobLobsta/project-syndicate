class_name MotiveAssemblyProfile
extends Resource
## Motive Assembly payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.2.
##
## Suspension is modelled per Motive Assembly by shape casts against the chassis
## body; Architectural Invariant I-3 forbids a joint here, so nothing in this
## profile may be interpreted as a physics constraint.
##
## The fields below the family payload are the ones all four locomotion families
## genuinely share. Kind-specific parameters live in a sub-resource selected by
## [member kind], mirroring the way [PartDefinition] selects a class payload —
## the same rule, the same validator shape, and the same failure mode when it is
## violated. Widening this profile until every kind ignored two thirds of it was
## the alternative, and doc 01 §7.2 records why it was rejected.

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

## ===== FAMILY PAYLOAD ==================================================
## Exactly one is non-null for the kinds that need one, matching [member kind].
## Every GROUND kind carries none. Enforced by the registry validator.

@export var rotor_profile: RotorProfile = null  # ROTOR_DISC only
@export var limb_profile: LimbProfile = null  # AMBULATORY_LIMB only
@export var track_profile: TrackProfile = null  # TRACKED_SEGMENT only


## The locomotion family that moves an Assembly carrying this Motive Assembly.
## One array index; see [constant PartEnums.LOCOMOTION_OF_MOTIVE_KIND].
func locomotion_mode() -> int:
	return PartEnums.locomotion_of(kind)


## The family payload matching [member kind], or null when the kind needs none.
## The validator treats a mismatch between this and [member kind] as a hard
## failure, exactly as it does for a class payload.
func family_payload() -> Resource:
	match kind:
		PartEnums.MotiveKind.ROTOR_DISC:
			return rotor_profile
		PartEnums.MotiveKind.AMBULATORY_LIMB:
			return limb_profile
		PartEnums.MotiveKind.TRACKED_SEGMENT:
			return track_profile
	return null
