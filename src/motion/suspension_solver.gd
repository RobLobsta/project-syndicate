class_name SuspensionSolver
extends RefCounted
## Spring-damper suspension, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §6.
##
## Pure statics with no state of its own. Everything that persists between ticks
## lives on the [MotiveContact] passed in, which is what lets [TrackSolver] call
## these same functions once per road station without any of them knowing that
## more than one contact exists.
##
## Architectural Invariant I-3: none of this is a physics constraint. Suspension
## travel is modelled per Motive Assembly by a shape cast against the chassis
## body, and the chassis itself is rigid.

## Bottom-out limit as a multiple of the force at full travel. Beyond it the
## suspension is on its stops and the chassis takes the load directly.
const BOTTOM_OUT_MULT: float = 3.2

## Rebound is damped less than compression, as on a real damper. A symmetric
## damper packs down over successive bumps and never recovers its travel.
const REBOUND_DAMP_RATIO: float = 0.65

## Damping ratio used to derive the effective damper from the effective spring.
## Deriving it rather than scaling the authored value keeps the ride frequency
## consistent across build weights — the difference between a heavy build
## feeling planted and one feeling like it is floating.
const DAMPING_RATIO: float = 0.42

## Bounds on the spring scaling so that neither a featherweight nor an
## overloaded build ends up on a spring that cannot hold it or cannot move.
const SPRING_SCALE_MIN: float = 0.55
const SPRING_SCALE_MAX: float = 2.40

## Anti-roll stiffness as a fraction of the effective spring rate. Exposed as a
## garage slider over [0.0, 0.6]; this is the default.
const ANTI_ROLL_RATIO: float = 0.22

## Chassis speed below which the damper term is scaled back, killing the
## residual oscillation that otherwise keeps a settled Assembly awake.
const SETTLE_SPEED_MPS: float = 0.05
const SETTLE_DAMP_SCALE: float = 0.4

## Longitudinal separation within which two probes are treated as an axle pair,
## and the sign test their lateral coordinates must fail to be one.
const AXLE_PAIR_TOLERANCE_M: float = 0.35


## Travel consumed by the probe, in metres, clamped into [0, travel_limit].
##
## Zero when the probe found nothing or hangs beyond its rest length; a
## suspension at full extension carries no load, which is what makes an airborne
## Motive Assembly contribute nothing rather than pulling the chassis down.
static func compression(profile: MotiveAssemblyProfile, contact: MotiveContact) -> float:
	if not contact.grounded:
		return 0.0
	return clampf(
		profile.suspension_rest_length_m - contact.distance_m,
		0.0,
		profile.suspension_travel_limit_m
	)


## Metres the contact's part is drawn below the cell it was placed in, for the
## presentation layer of §16 and for nothing else.
##
## The travel the spring has [b]not[/b] consumed. §6.1's authoring convention
## puts the rest length one full travel above the part's own collider, so a
## contact at full droop hangs exactly [member
## MotiveAssemblyProfile.suspension_travel_limit_m] below its placement and a
## bottomed-out one sits in it — but the definition does not depend on that
## convention holding, because a strut's visible extension is the travel it has
## left whatever the numbers around it are.
##
## An ungrounded contact reads zero compression and therefore hangs at full
## droop, which is what a wheel does when the ground falls away under it.
##
## Presentation follows the simulation here and never the reverse: the mesh
## moves and the collider does not, because Architectural Invariant I-1 fixes a
## part's physical footprint from placement to destruction.
static func droop_m(profile: MotiveAssemblyProfile, contact: MotiveContact) -> float:
	return profile.suspension_travel_limit_m - compression(profile, contact)


## Rate of change of compression, in m/s, from the value stored on the contact.
static func compression_rate(contact: MotiveContact, current_x: float, dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	return (current_x - contact.prev_compression_m) / dt


## Spring-damper force along the contact normal, in newtons.
##
## [param stiffness_n_m] and [param damping_ns_m] are the [b]effective[/b]
## values from [method retune], not the authored ones: the authored stiffness is
## nominal for the part's rated load and would put a heavy build on its bump
## stops.
##
## Clamped non-negative because a suspension pushes and never pulls (§11
## invariant 6), and clamped above at the bottom-out limit.
static func force(
	stiffness_n_m: float,
	damping_ns_m: float,
	travel_limit_m: float,
	compression_m: float,
	compression_rate_mps: float,
	damp_multiplier: float,
	chassis_speed_mps: float
) -> float:
	var damp := damping_ns_m * damp_multiplier
	if compression_rate_mps < 0.0:
		damp *= REBOUND_DAMP_RATIO
	if chassis_speed_mps < SETTLE_SPEED_MPS:
		damp *= SETTLE_DAMP_SCALE
	var f := stiffness_n_m * compression_m + damp * compression_rate_mps
	var f_max := stiffness_n_m * travel_limit_m * BOTTOM_OUT_MULT
	return clampf(f, 0.0, f_max)


## Effective spring and damper for a contact carrying [param static_normal_n],
## returned as [code](k_eff, c_eff)[/code].
##
## Fires on mass recompute only, never per tick. The damper is derived from the
## critical-damping formula against the corner mass the spring actually carries,
## which is what holds the ride frequency constant as a build gains weight.
static func retune(profile: MotiveAssemblyProfile, static_normal_n: float) -> Vector2:
	var rated_n := profile.rated_load_kg * SyndicateConstants.GRAVITY_MPS2
	var scale := clampf(static_normal_n / maxf(rated_n, 1.0), SPRING_SCALE_MIN, SPRING_SCALE_MAX)
	var k_eff := profile.suspension_stiffness_n_m * scale
	var corner_mass := static_normal_n / SyndicateConstants.GRAVITY_MPS2
	var c_eff := 2.0 * DAMPING_RATIO * sqrt(maxf(k_eff * corner_mass, 0.001))
	return Vector2(k_eff, c_eff)


## Equal-and-opposite anti-roll force for a probe pair, in newtons.
##
## [b]Positive means push [i]up[/i] on the left and down on the right[/b], the
## left being the negative-x end of the pair. A positive result therefore says
## the left is the more compressed side — the chassis is low on the left — and
## the couple lifts it, which is the roll an anti-roll bar exists to resist.
##
## Applied the other way round this term is a roll [i]amplifier[/i], and it was
## for the life of the project: it pushes the loaded side further down, and once
## the inside contact leaves the ground there is no spring on that side left to
## oppose it. Doc 05 §6.5 carries the divergence it produced and the measurement
## either side of the repair.
##
## Returned as one scalar because the pair is equal and opposite by construction,
## and returning two would let a caller apply them asymmetrically.
static func anti_roll_force(
	stiffness_n_m: float, compression_left_m: float, compression_right_m: float, ratio: float
) -> float:
	return stiffness_n_m * ratio * (compression_left_m - compression_right_m)


## True when two probes at these assembly-local positions form an axle pair.
##
## Derived at spawn rather than authored: pairing is a property of where the
## builder put the Motive Assemblies, and a build with three on one side has no
## authored answer.
static func is_axle_pair(a_local: Vector3, b_local: Vector3) -> bool:
	if absf(a_local.z - b_local.z) > AXLE_PAIR_TOLERANCE_M:
		return false
	# Opposite sides, and neither on the centreline: a pair straddling zero has
	# no roll couple to resist, so anti-roll between them would be a pure
	# vertical force on the spine.
	return a_local.x * b_local.x < 0.0
