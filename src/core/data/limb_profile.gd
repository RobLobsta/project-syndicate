class_name LimbProfile
extends Resource
## Ambulatory Motive Assembly payload, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §7.2.2.
##
## Carried by a [MotiveAssemblyProfile] whose [member MotiveAssemblyProfile.kind]
## is [constant PartEnums.MotiveKind.AMBULATORY_LIMB], and by no other. The gait
## and stance semantics are owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §13.
##
## Architectural Invariant I-3 forbids a joint here as everywhere else. A limb is
## a [b]virtual leg[/b] — one spring-damper force along the hip-to-foot line —
## and its visible articulation is inverse kinematics under [code]VisualRoot[/code].
## §13.1 of document 05 records why a jointed leg is not merely forbidden but
## unnecessary.

## ===== GEOMETRY ========================================================

## Hip-to-foot distance at full extension, in metres. The stance controller
## never plants a foot beyond this from the hip.
@export var leg_length_m: float = 1.90
## Hip position relative to the part's pivot cell centre, in metres. The point
## the stance force is applied at, and the origin of the foot placement law.
@export var hip_offset_m: Vector3 = Vector3(0.0, 0.75, 0.0)
@export var foot_radius_m: float = 0.16
## ===== SUPPORT POLYGON (doc 05 §13.10) ================================
## Fore-aft and lateral extent of the foot's contact patch, in metres. Together
## they are the support polygon the centre of pressure may move inside, and the
## bound on the ankle torque is `N x half-extent` on each axis.
##
## [b]Both default to zero, and a profile that authors neither behaves exactly as
## it did before §13.10 existed.[/b] A foot with no extent can only push along
## the hip-to-foot line, which is the model every walking Assembly in this
## project was built on and is why every one of them was a quadruped: with no
## ankle, pitch stability is entirely the fore-aft stance base, and stance base
## and torso depth are the same cells. Authoring these is what makes a biped
## expressible.
@export var foot_length_m: float = 0.0
@export var foot_width_m: float = 0.0
## Height the stance controller holds the hip at, as a fraction of leg length.
## The virtual leg's rest length; the Assembly settles below it by whatever
## compression its share of the weight demands of the spring.
@export var stance_height_ratio: float = 0.86

## ===== STANCE ==========================================================

## Virtual-leg spring gains. These are a controller's, not a suspension's,
## which is why they are here rather than on the parent profile's suspension
## fields — a limb's compliance is commanded, and the validator requires those
## fields to be zero on an ambulatory Motive Assembly.
@export var stance_stiffness_n_m: float = 96000.0
@export var stance_damping_ns_m: float = 12000.0
## Ceiling on the axial force one limb produces. What makes an overloaded
## Assembly sag and sit down rather than launch.
@export var max_foot_force_n: float = 42000.0

## ===== GAIT ============================================================

## Fraction of the gait cycle spent in stance. Above 0.5 support is continuous
## and the Assembly never leaves the ground; below it there is a flight phase,
## which is expressible and outside the shipping set.
@export var duty_factor: float = 0.62
@export var nominal_cadence_hz: float = 1.05
@export var max_cadence_hz: float = 2.20
## Distance the body advances over one stance. Cadence is derived from this and
## commanded speed so the planted foot never skates.
@export var max_step_length_m: float = 1.10
## Peak foot clearance over the swing arc. Presentation only: nothing in the
## simulation reads a swinging foot's position.
@export var step_height_m: float = 0.34
## Raibert velocity-error gain on the foot placement law, in seconds. Sets how
## hard the limb brakes or accelerates by planting off the neutral point.
@export var placement_gain_s: float = 0.19
## Yaw authority, expressed as the rate at which the foot target rotates about
## the Assembly's vertical. There is no yaw torque term in this family.
@export var turn_rate_deg_s: float = 45.0


## Rest length of the virtual leg, in metres.
func stance_rest_length_m() -> float:
	return stance_height_ratio * leg_length_m


## Duration of one stance at [param cadence_hz], in seconds. The interval the
## foot placement law's neutral point is computed over.
func stance_duration_s(cadence_hz: float) -> float:
	return duty_factor / maxf(cadence_hz, SyndicateConstants.EPSILON_LINEAR)
