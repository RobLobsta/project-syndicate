class_name AimSolver
extends RefCounted
## Pure aim geometry for a two-DOF hardpoint, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §3 and §4.
##
## Statics only. Everything here is a function of a direction, a set of limits
## and a rate, which is what lets a unit test assert an exact angle without
## building an Assembly — and what keeps [EffectorSystem] a loop over state
## rather than a page of trigonometry.

## Convergence tolerance, in radians. Half a degree: tight enough that a shot
## lands where the reticle is at any range worth firing at, loose enough that a
## mount does not chatter one step either side of its target forever.
const AIM_TOLERANCE_RAD: float = 0.0087

## Range a player's aim ray is cast to before it gives up and returns a point in
## open air. §4.1.
const AIM_RANGE_M: float = 900.0

## Slew rate multipliers by integrity band. §3.3.
##
## Owned by [DegradationTable] — these names index it rather than restating it,
## because CLAUDE.md §1.1 makes doc 08 the owner of every band multiplier and a
## second copy here is exactly the duplication that lets the two drift apart.


## Yaw and pitch, in radians, that point a mount in [param dir_rest] — the
## desired direction expressed in the module's own rest frame.
##
## The yaw node turns about [code]+Y[/code] and the pitch node about
## [code]+X[/code] inside it, matching §2's hierarchy. Extracting Euler angles
## from a look-at basis would give the same answer more expensively, and would
## carry a gimbal ambiguity at ±90° of pitch that this decomposition does not
## have.
##
## [b]The zero-yaw direction is [code]-Z[/code], not [code]+Z[/code].[/b] Doc 07
## §4.2 writes [code]atan2(x, z)[/code], which solves for a mount whose forward
## is [code]+Z[/code] — but §7.2 emits along [code]-muzzle_xform.basis.z[/code]
## and every Effector Module in the registry authors its barrel or its blade
## along its own [code]-Z[/code]. Two of those three agree and the decomposition
## was the odd one out: taken literally it points a turret exactly backwards,
## which the first duel between two real Assemblies is what found.
static func angles_for(dir_rest: Vector3) -> Vector2:
	if dir_rest.is_zero_approx():
		return Vector2.ZERO
	var d := dir_rest.normalized()
	var horizontal := sqrt(d.x * d.x + d.z * d.z)
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, horizontal))


## [param desired_yaw] clamped into [param limit_deg], in radians.
##
## A full-traverse mount — one whose authored limits span 360° or more — is not
## clamped at all, because clamping it would introduce a seam at the arbitrary
## point the limits happen to start, and a turret that can turn all the way round
## must be able to cross that point.
static func clamp_yaw(desired_yaw: float, limit_deg: Vector2) -> float:
	if limit_deg.y - limit_deg.x >= 360.0:
		return wrapf(desired_yaw, -PI, PI)
	return clampf(desired_yaw, deg_to_rad(limit_deg.x), deg_to_rad(limit_deg.y))


static func clamp_pitch(desired_pitch: float, limit_deg: Vector2) -> float:
	return clampf(desired_pitch, deg_to_rad(limit_deg.x), deg_to_rad(limit_deg.y))


## One tick of rate-limited rotation toward the target. §3.3.
##
## [param band_multiplier] is [constant DegradationTable.EFF_SLEW] at the
## module's cached band. A damaged turret traverses slowly; it does not traverse
## inaccurately.
static func slew(
	current_rad: float, target_rad: float, rate_deg_s: float, band_multiplier: float, dt: float
) -> float:
	var step := deg_to_rad(rate_deg_s) * band_multiplier * dt
	return move_toward(current_rad, target_rad, step)


## True when a mount has arrived within [constant AIM_TOLERANCE_RAD] on both
## axes.
##
## Yaw error is wrapped and pitch error is not, deliberately: yaw is a circle and
## the short way round -179° to +179° is two degrees, where pitch is an arc with
## ends and a 358° pitch error is not a thing a mount can have.
static func is_converged(
	yaw_rad: float, yaw_target_rad: float, pitch_rad: float, pitch_target_rad: float
) -> bool:
	var yaw_error := absf(wrapf(yaw_target_rad - yaw_rad, -PI, PI))
	var pitch_error := absf(pitch_target_rad - pitch_rad)
	return yaw_error <= AIM_TOLERANCE_RAD and pitch_error <= AIM_TOLERANCE_RAD


## The forward direction a mount at [param yaw_rad] / [param pitch_rad] points,
## in its own rest frame.
##
## The inverse of [method angles_for], and it is a genuine inverse: the round
## trip through both is the identity for any direction inside the pitch limits.
## That property is the assertion a test should make, because it cannot be
## satisfied by a sign error in either function alone.
static func direction_for(yaw_rad: float, pitch_rad: float) -> Vector3:
	var horizontal := cos(pitch_rad)
	return Vector3(-sin(yaw_rad) * horizontal, sin(pitch_rad), -cos(yaw_rad) * horizontal)


## Samples a direction uniformly over the solid angle of a cone. §7.4.
##
## Uniform in [code]cos(theta)[/code], not in theta. Sampling the angle uniformly
## clusters shots toward the centre and produces a grouping pattern that reads as
## distinctly non-physical — a dense core with a sparse halo, rather than an even
## scatter.
##
## [param rng] is the caller's seeded generator. There is no default and no
## global fallback: Invariant I-9 makes every stochastic system own its
## generator, and a spread roll is replayed by the network layer.
static func cone_sample(
	dir: Vector3, half_angle_rad: float, rng: RandomNumberGenerator
) -> Vector3:
	if half_angle_rad <= 0.0 or dir.is_zero_approx():
		return dir
	var cos_max := cos(half_angle_rad)
	var z := rng.randf_range(cos_max, 1.0)
	var phi := rng.randf() * TAU
	var s := sqrt(maxf(0.0, 1.0 - z * z))
	var local := Vector3(s * cos(phi), s * sin(phi), z)
	return (basis_from_forward(dir.normalized()) * local).normalized()


## An orthonormal basis whose [code]+Z[/code] is [param forward].
##
## The up reference flips to [code]+X[/code] when forward is near-vertical, which
## is not a nicety: a cross product with a parallel vector is zero, and the
## resulting basis would send every spread sample to the same place — a shotgun
## firing straight up would produce a perfect single hole.
static func basis_from_forward(forward: Vector3) -> Basis:
	var reference := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var right := reference.cross(forward).normalized()
	return Basis(right, forward.cross(right).normalized(), forward)
