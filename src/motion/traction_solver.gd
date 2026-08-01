class_name TractionSolver
extends RefCounted
## Combined-slip friction, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §7.
##
## Pure statics, for the same reason [SuspensionSolver] is: [TrackSolver] calls
## every function here once per road station, and a solver holding state could
## not be reused that way.
##
## Architectural Invariant I-5: every function taking a band takes it as an
## already-cached integer. Nothing here reads integrity or computes a band.

## Speed floor in the slip denominators. Without it the division explodes at
## rest, which is the standard source of the "Assembly vibrates violently when
## stationary" bug.
const V_REF_MPS: float = 0.8

## Slip at which friction peaks. Normalising by these is what makes the
## combined-slip magnitude dimensionless and the friction circle circular.
const KAPPA_PEAK: float = 0.14
const ALPHA_PEAK_TAN: float = 0.16734  # tan(9.5 degrees)

## Simplified Pacejka shape. Rises steeply below the peak and falls off gently
## beyond it, which gives controllable breakaway rather than a cliff.
const PACEJKA_B: float = 8.5
const PACEJKA_C: float = 1.35

## Load sensitivity: real contacts lose relative grip as normal load rises.
## This is what makes an overweight build handle badly without a handling
## penalty applied on top of the physics.
const K_LOAD: float = 0.18
const LOAD_SENS_MIN: float = 0.55
const LOAD_SENS_MAX: float = 1.15

## Below this combined slip the contact is not sliding and produces no force.
const SLIP_EPSILON: float = 1e-5


## Longitudinal slip ratio.
static func slip_ratio(contact_omega: float, radius_m: float, v_long: float) -> float:
	var denom := maxf(absf(v_long), V_REF_MPS)
	return (contact_omega * radius_m - v_long) / denom


## Tangent of the slip angle. The tangent rather than the angle because the
## combined-slip magnitude needs it and [code]atan[/code] would be undone
## immediately.
static func slip_angle_tan(v_lat: float, v_long: float) -> float:
	return v_lat / maxf(absf(v_long), V_REF_MPS)


## Normalised friction utilisation at combined slip [param s].
##
## Normalised so that [code]f(1) == 1[/code] at the peak. The denominator is
## recomputed rather than cached in a static var because a static var on a
## [RefCounted] would be shared process-wide and this is two transcendentals
## against a solve that already costs dozens.
static func pacejka(s: float) -> float:
	return sin(PACEJKA_C * atan(PACEJKA_B * s)) / sin(PACEJKA_C * atan(PACEJKA_B))


## Load sensitivity multiplier at [param normal_n] against the part's rating.
static func load_sensitivity(profile: MotiveAssemblyProfile, normal_n: float) -> float:
	var rated_n := profile.rated_load_kg * SyndicateConstants.GRAVITY_MPS2
	return clampf(
		1.0 - K_LOAD * (normal_n / maxf(rated_n, 1.0) - 1.0), LOAD_SENS_MIN, LOAD_SENS_MAX
	)


## Effective friction coefficient: nominal, times load sensitivity, times the
## cached band multiplier, times the surface multiplier.
##
## [param surface_multiplier] is passed in rather than looked up so that this
## file does not depend on the Ground Array layer, which does not exist yet and
## which document 09 owns.
static func effective_mu(
	profile: MotiveAssemblyProfile, normal_n: float, band: int, surface_multiplier: float
) -> float:
	return (
		profile.traction_coefficient
		* load_sensitivity(profile, normal_n)
		* DegradationTable.multiplier(DegradationTable.MOTIVE_TRACTION, band)
		* surface_multiplier
	)


## Longitudinal and lateral friction force, in newtons, as
## [code](F_long, F_lat)[/code].
##
## A friction circle: a contact spending its grip on cornering has none left for
## acceleration. [param lateral_grip_ratio] scales the lateral axis and turns the
## circle into an ellipse, which is how a tracked patch's anisotropy enters
## (§14.4). It is applied [b]inside[/b] the combined solve rather than to the
## result, because applying it afterwards would let a station spend lateral grip
## it never had on longitudinal force.
static func combined_forces(
	kappa: float, tan_alpha: float, mu: float, normal_n: float, lateral_grip_ratio: float
) -> Vector2:
	var sx := kappa / KAPPA_PEAK
	var sy := tan_alpha / (ALPHA_PEAK_TAN * maxf(lateral_grip_ratio, SLIP_EPSILON))
	var s := sqrt(sx * sx + sy * sy)
	if s < SLIP_EPSILON:
		return Vector2.ZERO
	var f_max := mu * normal_n * pacejka(s)
	# The longitudinal sign is POSITIVE and the lateral NEGATIVE, and the
	# asymmetry is real rather than a slip. Both components oppose the contact
	# patch's sliding, but the two slip quantities are defined with opposite
	# senses: `kappa` is `(omega*r - v)`, which is already the negative of the
	# patch's slip velocity, while `tan_alpha` follows the lateral velocity
	# directly. A driven contact therefore has positive kappa and must push the
	# Assembly forwards, and a contact sliding right must be pushed left.
	#
	# Doc 05 §7.2 wrote both as negative; the amendment there records why that
	# made throttle decelerate an Assembly, and §7.4's own `- F_long * r`
	# retarding term only balances against the sign used here.
	return Vector2(f_max * sx / s, -f_max * sy / s)


## Contact angular rate after one tick of drive, brake, and ground reaction.
##
## Returns the new rate. The zero-crossing guard is what prevents the contact
## oscillating around zero under braking and injecting energy — another classic
## stutter source, and one that only shows up as a vehicle that will not quite
## come to rest.
static func integrate_contact(
	contact_omega: float,
	inertia_kgm2: float,
	drive_nm: float,
	brake_nm: float,
	f_long_n: float,
	radius_m: float,
	dt: float
) -> float:
	var brake_sign := -signf(contact_omega)
	var tau := drive_nm + brake_sign * brake_nm - f_long_n * radius_m
	var delta := (tau / maxf(inertia_kgm2, 0.001)) * dt
	var next := contact_omega + delta
	if brake_nm > 0.0 and signf(next) != signf(contact_omega) and not is_zero_approx(contact_omega):
		return 0.0
	return next


## Rotational inertia of a contact, in kg·m², as a uniform disc.
static func contact_inertia(mass_kg: float, radius_m: float) -> float:
	return 0.5 * mass_kg * radius_m * radius_m


## Drive torque for each contact, weighted by normal load.
##
## Load weighting is what suppresses wheelspin on an airborne contact without a
## traction-control hack: an unloaded contact receives almost no torque. A
## destroyed Power Plant simply reduces the total; a destroyed contact simply
## leaves the denominator.
##
## [param normals_n] and the returned array are parallel and index-aligned.
static func distribute_torque(
	total_nm: float, normals_n: PackedFloat32Array
) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(normals_n.size())
	var sum := 0.0
	for n: float in normals_n:
		sum += maxf(n, 0.0)
	if sum <= 0.0:
		out.fill(0.0)
		return out
	for i: int in normals_n.size():
		out[i] = total_nm * maxf(normals_n[i], 0.0) / sum
	return out


## Rolling resistance force opposing motion, in newtons.
static func rolling_resistance_n(
	profile: MotiveAssemblyProfile, normal_n: float, band: int
) -> float:
	return (
		profile.rolling_resistance
		* normal_n
		* DegradationTable.multiplier(DegradationTable.MOTIVE_ROLLING, band)
	)
