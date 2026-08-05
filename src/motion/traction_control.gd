class_name TractionControl
extends RefCounted
## Wheel-slip limiting and yaw stabilisation, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §7.6.
##
## Pure statics, like every other solver in this layer: it holds no state, and
## everything that persists between ticks lives on the [MotiveContact] the caller
## passes in. It contributes no force of its own — it scales a drive torque down
## and adds a brake torque, both of which reach the ground through §7.2's
## friction solve. That is deliberate and it is the whole design:
##
## [b]An electronic aid may not apply a force the tyres could not.[/b] A yaw
## controller that called [method RigidBody3D.apply_torque] would turn an
## Assembly just as briskly on ice, on a slope, or with two wheels off the
## ground, and would keep working after the contacts it is supposed to be
## managing had stopped touching anything. Modulating the brakes produces the
## same yaw moment through the same contact patches the driver is using, so it
## fades out exactly when grip does, and it costs nothing when the Assembly is
## already going where it was pointed.
##
## Applies to the GROUND family only. A tracked Assembly steers [i]by[/i] making
## its flanks disagree (§14.2), so a yaw controller that removed the disagreement
## would remove its steering; and a rotary or ambulatory one has no slip ratio to
## limit. §7.6 records that boundary rather than leaving it to be rediscovered.

## Slip ratio the limiter holds the contact patch at. Just past the peak of the
## §7.2 friction curve, so an Assembly under management is still near maximum
## longitudinal grip rather than backed off to a safe fraction of it.
const TARGET_SLIP_RATIO: float = 0.14

## Road speed the allowance is taken against when the Assembly is slower than it,
## in m/s. A slip *ratio* is meaningless at a standstill — §7.1 divides by
## `max(|v|, 0.8)`, so any rotation at all reads as enormous slip — and a limiter
## that believed it would cut the torque of a stationary Assembly to nothing and
## never let it move. Measuring the allowance against a floor turns the law into
## a slip *velocity* at low speed and a slip ratio once rolling, which is what
## launch control is, and it is one `maxf` rather than a second mode.
const LAUNCH_REFERENCE_MPS: float = 5.0

## How hard drive torque is cut per m/s of patch overspeed past the allowance.
## Shaped as a reciprocal rather than a subtraction so the cut is smooth, is
## never total, and cannot change the sign of the torque it is managing.
const SLIP_GAIN: float = 1.2

## Corrective brake torque per rad/s of yaw error, before the per-part ceiling.
const YAW_GAIN_NM_PER_RAD_S: float = 2600.0

## Yaw error tolerated without any correction, in rad/s. Below this the Assembly
## is going where it was pointed to within the noise of a settling suspension,
## and correcting would mean the brakes were never off.
const YAW_DEADBAND_RAD_S: float = 0.10

## Ceiling on the corrective brake, as a fraction of the part's own brake torque.
## Well below 1.0: this may bias an Assembly's yaw and may not stop it.
##
## [b]It was 0.55, and 0.55 was tuned against a contact that could not brake.[/b]
## Doc 05 §7.4's step was 142 times outside its own stability limit, so the brake
## torque's sign reversed on most ticks and the aid's demand arrived as a fraction
## of itself. With the step repaired, 0.55 of the shipped Motive Assembly's brake
## is 4565 N·m against the 4672 N·m that locks its patch — so the aid was locking
## the flank it was supposed to be modulating, and a locked patch spends its whole
## friction budget longitudinally and has none left to resist the spin. Measured
## on an imposed 1 rad/s: the aid left [b]more[/b] yaw than no aid at all.
##
## An aid that locks the patch it is biasing has stopped being a bias and become
## a handbrake. A quarter of the authored brake keeps the flank rolling, which is
## the condition under which a brake bias produces yaw rather than removing grip.
const MAX_BRAKE_FRACTION: float = 0.25

## Below this speed the yaw controller does nothing. The kinematic target divides
## by nothing at a standstill and a stationary Assembly has no heading error
## worth the name — it also lets a driver pivot a light build on the handbrake
## without the aid fighting them.
const MIN_YAW_CONTROL_SPEED_MPS: float = 1.5

## Lateral acceleration the grip limit is taken at, as a multiple of the surface
## friction. Keeps the yaw target inside what the contacts could actually
## deliver, so the controller never chases a heading the Assembly cannot hold.
const GRIP_YAW_MARGIN: float = 0.95


## Multiplier on drive torque that holds the contact patch's overspeed inside the
## allowance, in [code](0, 1][/code].
##
## [param patch_speed_mps] is `omega * radius` and [param road_speed_mps] is the
## contact's own longitudinal velocity, so their difference is the slip velocity
## §7.1 normalises into a ratio. The allowance is that ratio applied to the road
## speed, floored at [constant LAUNCH_REFERENCE_MPS] — see the constant.
##
## [param authority] scales the whole intervention, so an aid at 0.0 returns 1.0
## and the driver gets the torque they asked for, wheelspin included.
static func drive_scale(
	patch_speed_mps: float, road_speed_mps: float, authority: float
) -> float:
	var allowed := TARGET_SLIP_RATIO * maxf(absf(road_speed_mps), LAUNCH_REFERENCE_MPS)
	var excess := maxf(absf(patch_speed_mps - road_speed_mps) - allowed, 0.0)
	if is_zero_approx(excess):
		return 1.0
	var cut := 1.0 / (1.0 + excess * SLIP_GAIN)
	return lerpf(1.0, cut, clampf(authority, 0.0, 1.0))


## The yaw rate a steer angle asks for, in rad/s, from the bicycle model.
##
## Negative for a right-hand lock: forward is `-Z` and right is `+X`, so turning
## right is a negative rotation about `+Y`. [param wheelbase_m] is the
## longitudinal spread of the Assembly's ground contacts, derived at registration
## from where the builder put them rather than authored.
static func target_yaw_rate_rad_s(
	speed_mps: float, steer_rad: float, wheelbase_m: float
) -> float:
	if wheelbase_m < SyndicateConstants.EPSILON_LINEAR:
		return 0.0
	return -speed_mps * tan(steer_rad) / wheelbase_m


## The yaw rate the contacts could actually hold at this speed, in rad/s.
##
## A steer angle can always be commanded; the grip to follow it cannot. Clamping
## the target to `mu * g / v` is what stops the controller braking an Assembly
## into a corner it was never going to make.
static func grip_limited_yaw_rate_rad_s(speed_mps: float, mu: float) -> float:
	if speed_mps < MIN_YAW_CONTROL_SPEED_MPS:
		return INF
	return GRIP_YAW_MARGIN * mu * SyndicateConstants.GRAVITY_MPS2 / speed_mps


## Yaw error, in rad/s, after the deadband and the grip limit. Zero means leave
## the brakes alone.
static func yaw_error_rad_s(
	actual_rad_s: float, target_rad_s: float, grip_limit_rad_s: float
) -> float:
	var wanted := clampf(target_rad_s, -grip_limit_rad_s, grip_limit_rad_s)
	var error := actual_rad_s - wanted
	if absf(error) <= YAW_DEADBAND_RAD_S:
		return 0.0
	return error - signf(error) * YAW_DEADBAND_RAD_S


## Which flank to brake to correct [param yaw_error]: -1 for the negative-x side,
## +1 for the positive-x side.
##
## A rearward force on the left flank yaws the Assembly left, so an Assembly
## yawing right harder than it was asked to is corrected by braking the left.
## That is the same sign as the error, which is why this is one call rather than
## a branch.
static func brake_side(yaw_error: float) -> int:
	return -1 if yaw_error < 0.0 else 1


## Corrective brake torque for one contact, in N·m, bounded by the part's own
## brake and by [constant MAX_BRAKE_FRACTION].
static func yaw_brake_nm(
	yaw_error: float, part_brake_nm: float, authority: float
) -> float:
	if is_zero_approx(yaw_error):
		return 0.0
	var demand := absf(yaw_error) * YAW_GAIN_NM_PER_RAD_S * clampf(authority, 0.0, 1.0)
	return minf(demand, part_brake_nm * MAX_BRAKE_FRACTION)
