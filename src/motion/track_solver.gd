class_name TrackSolver
extends RefCounted
## Tracked locomotion, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §14.
##
## A track is a ground contact smeared along the hull. It reuses
## [SuspensionSolver] and [TractionSolver] verbatim, once per road station, and
## adds the two things a point contact has no term for: a drive model that
## steers by rate difference rather than by angle, and a resistance to slewing
## the patch across the ground.
##
## That reuse is only available because both of those are pure statics taking a
## contact and a profile. Nothing here reimplements a spring or a friction
## curve, and the next change to either is picked up by tracks for free.

## Yaw rate at which slew resistance reaches its full value, in rad/s.
##
## The cap is what keeps it a resistance rather than a brake. Below the
## reference it scales in; above it is constant, and it never exceeds what the
## friction of the patch could actually supply. Without the cap a fast spin
## would generate unbounded counter-torque and the Assembly would snap to a
## stop, which reads as hitting a wall.
const SLEW_REFERENCE_RAD_S: float = 1.2


## Assembly-local positions of a tracked part's road stations, fore to aft.
##
## [param part_local] is the part's own centre and [param rolling_axis] its
## rolling direction in assembly space, so the stations lie along the patch
## wherever the builder oriented it.
static func station_positions(
	profile: TrackProfile, part_local: Vector3, rolling_axis: Vector3
) -> PackedVector3Array:
	var axis := rolling_axis.normalized()
	var offsets := profile.station_offsets_m()
	var out := PackedVector3Array()
	out.resize(offsets.size())
	for i: int in offsets.size():
		out[i] = part_local + axis * offsets[i]
	return out


## Steering bias in [-1, 1] at [param steer_command] and [param speed_mps].
##
## At rest, authority is full and a bias of ±1 drives one side forward and the
## other backward, so the Assembly counter-rotates on the spot. At the profile's
## taper speed authority is zero, both sides receive the same torque, and
## steering is whatever the patch's lateral grip concedes — which, at a lateral
## grip ratio above 1.0, is very little.
##
## Nothing switches. A pivot and a long committed arc are the same linear
## expression evaluated at two speeds.
static func drive_bias(profile: TrackProfile, steer_command: float, speed_mps: float) -> float:
	return clampf(steer_command, -1.0, 1.0) * profile.authority_at_speed(speed_mps)


## Drive torque for the left and right sides, as [code](left, right)[/code].
##
## [param internal_loss] is charged before the torque reaches the ground, not
## afterwards, because that is where it physically goes — into the track's own
## pins, links, and idlers. The visible result is that a tracked Assembly is
## slower than a wheeled one of identical power, which is the cost its grip and
## ground pressure are bought with.
static func side_torques(profile: TrackProfile, total_nm: float, bias: float) -> Vector2:
	var usable := total_nm * (1.0 - clampf(profile.internal_loss, 0.0, 1.0))
	var half := usable * 0.5
	return Vector2(half * (1.0 + bias), half * (1.0 - bias))


## Yaw torque resisting a slew of the patch, in N·m.
##
## Proportional to patch length, to normal load, and to the rate of the slew up
## to the reference. The length-times-load product is the design statement: a
## heavy tracked Assembly is committed, doubling its armour doubles the torque
## needed to change its heading, and no steering input overcomes it. That is the
## failure mode a bastion build is meant to have, and it emerges from two
## authored numbers rather than from a handling penalty applied on top.
##
## Always opposes the existing yaw rate and never reverses it (§11 invariant 18).
## There is no early-out for a stationary hull or an airborne track, and there
## was one until fault injection showed it could be removed without a single
## test noticing. It could: `signf(0.0)` is `0.0`, and a zero normal load makes
## the magnitude zero, so both cases already fall out of the arithmetic. Fifteen
## untested lines with an excuse is worse than four tested ones.
static func slew_torque_nm(
	profile: TrackProfile, normal_total_n: float, yaw_rate_rad_s: float
) -> float:
	var scale := minf(1.0, absf(yaw_rate_rad_s) / SLEW_REFERENCE_RAD_S)
	# No floor on the load: suspension force is clamped non-negative at source
	# (§6.2), so a negative total cannot reach here, and guarding against it was
	# another untested line fault injection could remove for free.
	var magnitude := (
		profile.slew_resistance_nm_per_n_m * profile.patch_length_m * normal_total_n * scale
	)
	return -signf(yaw_rate_rad_s) * magnitude


## Which side of the Assembly a tracked part at [param part_local] drives.
##
## Returns -1 for left, +1 for right. A part on the centreline counts as left,
## so a single-track Assembly is deterministic rather than depending on a float
## comparison against zero.
static func side_of(part_local: Vector3) -> int:
	return 1 if part_local.x > 0.0 else -1


## Longitudinal patch speed, in m/s, at [param sprocket_omega].
static func patch_speed_mps(profile: MotiveAssemblyProfile, sprocket_omega: float) -> float:
	return sprocket_omega * profile.contact_radius_m


## Share of the part's rated load one station is expected to carry, in newtons.
##
## Authored below [code]1 / road_stations[/code] on both shipping rows. That
## deliberate softness at the ends of the patch is what lets a track conform to
## a rise rather than bridge across it rigidly, and it is the knob to reach for
## when a tracked build feels like it is on stilts.
static func station_static_load_n(
	profile: MotiveAssemblyProfile, track: TrackProfile
) -> float:
	return profile.rated_load_kg * SyndicateConstants.GRAVITY_MPS2 * track.station_load_share
