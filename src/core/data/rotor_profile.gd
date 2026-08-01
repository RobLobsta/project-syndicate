class_name RotorProfile
extends Resource
## Rotary Motive Assembly payload, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §7.2.1.
##
## Carried by a [MotiveAssemblyProfile] whose [member MotiveAssemblyProfile.kind]
## is [constant PartEnums.MotiveKind.ROTOR_DISC], and by no other. The semantics
## and every formula that reads these fields are owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §12; this resource owns only their
## existence and their units.
##
## The shipping values are derived rather than chosen: thrust at full collective
## solves to the parent profile's [member MotiveAssemblyProfile.rated_load_kg]
## times gravity, which the registry validator checks (§14 rule 19).

## ===== DISC GEOMETRY ===================================================

## Radius of the swept disc, in metres. Not the collider's radius — that is
## [member MotiveAssemblyProfile.contact_radius_m], which describes the hub.
@export var disc_radius_m: float = 2.60
@export var blade_count: int = 4
## +1 or -1. Two discs with opposed signs cancel each other's reaction torque.
@export var spin_sign: int = 1

## ===== SPOOL ===========================================================

## Angular rate at full throttle, in rad/s.
@export var nominal_rad_s: float = 85.0
## Time constant of the first-order approach to the commanded angular rate.
@export var spool_up_tau_s: float = 2.40
## Longer than spool-up on every shipping disc: a rotor with no power keeps
## turning, which is what makes an unpowered descent survivable.
@export var spool_down_tau_s: float = 4.80

## ===== LIFT ============================================================

## Thrust coefficient, quoted at maximum collective:
## [code]T = C_T * rho * A * (omega * R)^2[/code].
@export var thrust_coefficient: float = 0.020
## Shaft torque coefficient: [code]Q = C_Q * rho * A * (omega * R)^2 * R[/code].
@export var torque_coefficient: float = 0.0024
## Blade pitch range in degrees. The minimum is authored negative so the disc
## can push along its own -axis and hold the Assembly down against a gust.
@export var collective_limit_deg: Vector2 = Vector2(-4.0, 14.0)
@export var collective_rate_deg_s: float = 22.0

## ===== TILT ============================================================

## Maximum deflection of the thrust vector from the disc axis. Bounds the
## resultant of the two cyclic components, never each one separately: a
## swashplate's authority is a cone, and a square limit would make a diagonal
## stick deflection sqrt(2) times faster than a cardinal one.
@export var cyclic_limit_deg: float = 14.0
@export var cyclic_rate_deg_s: float = 48.0
## Yaw torque available from differential collective across a coaxial pair, or
## from an anti-torque station on a single-disc build.
@export var yaw_authority_nm: float = 9600.0

## ===== REGIME ==========================================================

## Fraction of reaction torque transmitted to the chassis. 0.0 for a coaxial
## disc whose counter-rotating half cancels it inside the part; 1.0 for a lone
## main disc, which transmits all of it and needs an opposed disc to fly.
@export var torque_reaction_ratio: float = 0.0
## Height above ground, in disc radii, below which ground effect adds thrust.
@export var ground_effect_radii: float = 1.0
## Peak ground-effect thrust gain, reached at zero height.
@export var ground_effect_gain: float = 0.24
## Airspeed at which translational lift reaches its full value, in m/s. Also
## the speed at which forward flight fully suppresses vortex ring state.
@export var translational_lift_mps: float = 14.0
@export var translational_lift_gain: float = 0.18
## Descent rate at which the disc is fully inside its own downwash, in m/s.
@export var vortex_ring_descent_mps: float = 6.0
## Peak thrust lost to vortex ring state.
@export var vortex_ring_loss: float = 0.32


## Swept disc area in square metres.
func disc_area_m2() -> float:
	return PI * disc_radius_m * disc_radius_m


## Blade tip speed at [param omega_rad_s], in m/s. The shipping family shares
## 221 m/s, which is where a real rotor lives — below the transonic tip.
func tip_speed_mps(omega_rad_s: float) -> float:
	return omega_rad_s * disc_radius_m


## Thrust at full collective and nominal angular rate, in newtons.
##
## The quantity §14 rule 19 compares against rated load, and the reason the
## shipping coefficients are what they are.
func max_thrust_n() -> float:
	var tip := tip_speed_mps(nominal_rad_s)
	return thrust_coefficient * SyndicateConstants.AIR_DENSITY_KG_M3 * disc_area_m2() * tip * tip
