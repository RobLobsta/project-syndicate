class_name GaitSolver
extends RefCounted
## Ambulatory locomotion, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §13.
##
## A limb is a [b]virtual leg[/b]: one spring-damper force along the hip-to-foot
## line, with a foot that is planted or swinging. This is the Spring-Loaded
## Inverted Pendulum, the standard model of legged locomotion in biomechanics
## and robotics, and it reproduces the force profile of real walking from two
## parameters. §13.1 of document 05 records why Architectural Invariant I-3
## does not merely forbid a jointed leg but makes one unnecessary.
##
## The visible articulation — thigh, shank, foot — is inverse kinematics under
## [code]VisualRoot[/code], driven from the hip and foot positions this solver
## already knows. It is presentation, exactly like the hardpoint hierarchy of
## document 07 §2, and Invariant I-1 keeps it out of the physics.

## Commanded speed below which the gait freezes with every foot planted.
##
## Not an optimisation — it is the behaviour. A walker asked to stand still
## stands, on every foot, rather than marching in place. It is also the only
## state in which every limb contributes stance force at once, which is why a
## stationary Assembly is rock-solid and a moving one visibly bobs.
const STANDING_SPEED_MPS: float = 0.15


## ===== §13.10 THE ANKLE STRATEGY ======================================

## Restoring torque per radian of tilt, and per radian per second of tilt rate.
##
## Each planted limb computes the same desired torque from the same body attitude
## and then clamps it by its [i]own[/i] normal load, which is what real ankles do
## and what makes the term degrade gracefully as feet leave the ground. So the
## aggregate stiffness of a standing Assembly is this figure times the number of
## limbs holding it up, and the damping is chosen against that aggregate rather
## than against one limb: under-damping an attitude loop on a machine this tall
## is a wobble that never settles, and the clamp keeps over-damping honest.
const ANKLE_STIFFNESS_NM_PER_RAD: float = 60000.0
const ANKLE_DAMPING_NMS_PER_RAD: float = 24000.0


## §13.10's clamp: the most torque this foot can apply at [param normal_force_n],
## as `(about the body's lateral axis, about its forward axis)`.
##
## The centre of pressure cannot leave the contact patch, so the moment it can
## produce about the foot's centre is the normal load times the distance the
## centre of pressure may travel — half the extent, on each axis. That is the
## whole physical content of §13.10 and it is why a foot carrying nothing can do
## nothing.
static func ankle_torque_limit_nm(profile: LimbProfile, normal_force_n: float) -> Vector2:
	var n := maxf(normal_force_n, 0.0)
	return Vector2(n * profile.foot_length_m * 0.5, n * profile.foot_width_m * 0.5)


## §13.10's ankle torque, in world newton-metres.
##
## [param body_basis] and [param angular_velocity] are the chassis's; the tilt is
## read from the basis rather than passed in, so a caller cannot supply one with
## the wrong sign. The returned torque is zero for a profile with no authored
## support polygon and for a foot carrying no load — both by construction rather
## than by an early return, because a bound of zero clamps everything to zero.
static func ankle_torque_nm(
	profile: LimbProfile,
	normal_force_n: float,
	body_basis: Basis,
	angular_velocity: Vector3
) -> Vector3:
	# `body_up x world_up` is an axis-angle whose magnitude is the sine of the
	# tilt and whose direction is the axis that rotates the body's up onto the
	# world's. Applying a torque along it therefore rights the machine, and that
	# sense is normative (§13.10) rather than a convention this file chose.
	var tilt := body_basis.y.cross(Vector3.UP)
	# The world-up component of the rate is yaw, and an ankle does not yaw: §13.5
	# makes turning a matter of placement and gives this family exactly one
	# heading authority.
	var rate := angular_velocity - Vector3.UP * angular_velocity.dot(Vector3.UP)
	var desired := tilt * ANKLE_STIFFNESS_NM_PER_RAD - rate * ANKLE_DAMPING_NMS_PER_RAD

	var limit := ankle_torque_limit_nm(profile, normal_force_n)
	var local := body_basis.inverse() * desired
	return body_basis * Vector3(
		clampf(local.x, -limit.x, limit.x),
		0.0,
		clampf(local.z, -limit.y, limit.y)
	)


## Phase offsets for a limb set, parallel to [param hips_local] and
## [param slots].
##
## Computed once per structural change and never per tick. Deterministic from
## the blueprint alone, which §11 invariant 16 requires: the server and every
## client must assign the same offsets or the same walker takes different steps
## on different machines.
##
## The rule, for n limbs: partition by the sign of the hip's lateral coordinate
## (zero to the left, so a single centred limb is deterministic), sort the left
## set fore-to-aft and the right set [b]aft-to-fore[/b], interleave left first,
## and assign [code]i / n[/code] over the result.
##
## The reversal is the whole design. Interleaving two same-direction orderings
## gives a four-limb Assembly the sequence front-left, front-right, rear-left,
## rear-right — and since the swing window is one contiguous arc of the cycle,
## the two limbs swinging together are the two front ones, leaving the Assembly
## standing on its rear pair and pitching forward every stride. Reversing one
## side makes the pair that swings together a [b]diagonal[/b], with the other
## diagonal still planted. That is what a real quadruped does, and it falls out
## of one reverse.
static func assign_phase_offsets(
	hips_local: PackedVector3Array, slots: PackedInt32Array
) -> PackedFloat32Array:
	var count := hips_local.size()
	var out := PackedFloat32Array()
	out.resize(count)
	if count == 0:
		return out

	var left: Array[int] = []
	var right: Array[int] = []
	for i: int in count:
		if hips_local[i].x <= 0.0:
			left.append(i)
		else:
			right.append(i)

	# Fore is -Z in assembly space, so ascending Z is fore-to-aft. Ties break on
	# slot index, which gives a total order; two limbs at one position would
	# otherwise be ordered by whatever the sort happened to do.
	var by_fore_aft := func(a: int, b: int) -> bool:
		if not is_equal_approx(hips_local[a].z, hips_local[b].z):
			return hips_local[a].z < hips_local[b].z
		return slots[a] < slots[b]
	left.sort_custom(by_fore_aft)
	right.sort_custom(by_fore_aft)
	right.reverse()

	var order: Array[int] = []
	var limit := maxi(left.size(), right.size())
	for i: int in limit:
		if i < left.size():
			order.append(left[i])
		if i < right.size():
			order.append(right[i])

	for i: int in order.size():
		out[order[i]] = float(i) / float(count)
	return out


## Gait cadence in Hz for [param speed_command_mps], or 0.0 when standing.
##
## Derived from step length rather than authored. The body advances one step
## length per stance, so a cadence that did not track commanded speed would
## slide the planted foot across the ground every stride — which reads as ice
## and is the single most common failure of procedural walk cycles.
## The fastest this gait can actually carry an Assembly, in m/s.
##
## §13.4 derives cadence from `speed / max_step_length_m` and clamps it at
## `max_cadence_hz`, so the gait covers at most one maximum step per half cycle
## at the maximum rate: `max_cadence_hz · max_step_length_m` and not a metre per
## second more. The shipped strider tops out at 2.42 m/s.
##
## It exists because §13.5's placement law needs it. The correction term chases
## `v_desired`, and handing it the Core Module's chassis speed cap — 24 m/s on
## the shipped Core Module, ten times what any gait can deliver — saturates that
## term permanently: every foot lands at the maximum step behind neutral, on
## every stride, whatever the throttle says. The Assembly then walks with its
## legs perpetually reaching backwards for a speed it cannot have, and pitches
## progressively nose-down doing it. Clamping the demand to what the family can
## produce is what makes the correction a correction again.
static func top_speed_mps(profile: LimbProfile) -> float:
	return profile.max_cadence_hz * profile.max_step_length_m


static func cadence_hz(profile: LimbProfile, speed_command_mps: float) -> float:
	var speed := absf(speed_command_mps)
	if speed < STANDING_SPEED_MPS:
		return 0.0
	var raw := speed / maxf(profile.max_step_length_m, SyndicateConstants.EPSILON_LINEAR)
	return clampf(raw, profile.nominal_cadence_hz, profile.max_cadence_hz)


## The shared gait clock after one tick at [param cadence_hz], wrapped to
## [0, 1).
##
## A cadence of zero holds the clock, which is what freezes the gait in the
## standing state without a second code path.
static func advance_clock(clock: float, cadence_hz_value: float, dt: float) -> float:
	return fposmod(clock + cadence_hz_value * dt, 1.0)


## A limb's phase from the shared clock and its own offset.
static func phase_of(clock: float, phase_offset: float) -> float:
	return fposmod(clock + phase_offset, 1.0)


## Where to plant the foot, in world space, on a swing-to-stance transition.
##
## The Raibert placement law. The first term is the [b]neutral point[/b]:
## planting there leaves the body's horizontal velocity unchanged across the
## stance, because its momentum carries it over the foot symmetrically. The
## second is the correction — planting ahead of neutral brakes, behind
## accelerates, and [member LimbProfile.placement_gain_s] sets how hard.
##
## This is not a heuristic dressed as physics; it is the balance law legged
## robots actually use, and it is why an Assembly here accelerates by leaning
## and reaching rather than by having a force added to it.
##
## Yaw is placement too: [param turn_command] rotates the target about the
## vertical, so the feet land off-axis and the resulting stance forces yaw the
## body. There is no yaw torque term anywhere in this family.
static func foot_target(
	profile: LimbProfile,
	hip_world: Vector3,
	ground_y: float,
	velocity_mps: Vector3,
	desired_velocity_mps: Vector3,
	cadence_hz_value: float,
	turn_command: float,
	com_height_m: float = 0.0
) -> Vector3:
	var hip_ground := Vector3(hip_world.x, ground_y, hip_world.z)
	if cadence_hz_value <= 0.0:
		return hip_ground

	var stance_s := profile.stance_duration_s(cadence_hz_value)
	var v_flat := Vector3(velocity_mps.x, 0.0, velocity_mps.z)
	var desired_flat := Vector3(desired_velocity_mps.x, 0.0, desired_velocity_mps.z)
	# §13.11. The first term is Raibert's neutral point, unchanged: planting there
	# leaves the body's horizontal momentum alone across the stance. The second is
	# the capture-point correction, and it is the term that used to be
	# `placement_gain_s` — an authored number with a magnitude and no authority.
	#
	# `sqrt(h/g)` is the linear inverted pendulum's time constant, so
	# `(v − v_desired) · sqrt(h/g)` is exactly the distance the foot has to be
	# planted from under the centre of mass for the momentum error to be spent by
	# the time the body arrives over it. It carries the sign of the demand, which
	# is the whole difference: a negative travel demand puts the target *behind*
	# the body and runs the stride the other way, where the old correction could
	# only ever scale a disturbance that was already there.
	var offset := v_flat * (stance_s * 0.5) + (v_flat - desired_flat) * capture_time_s(
		profile, com_height_m
	)

	if not is_zero_approx(turn_command):
		# Negated, and the sign is the whole line. [ControlInput.steer] is
		# documented as positive-is-right and every other family obeys it: doc 05
		# §7.1 rotates a wheeled contact frame right on a positive demand and
		# §14.2 drives the right track slower. A right turn is a [b]negative[/b]
		# rotation about the world up, so rotating the plant target by a positive
		# angle on a positive demand walks the Assembly left — which is what this
		# did, and it made an ambulatory Assembly the only thing in the game that
		# steered backwards.
		#
		# The old test could not see it. It asserted that a turn command moved the
		# foot and not which way it moved it, which is a fault a sign flip
		# satisfies exactly.
		var yaw := deg_to_rad(-profile.turn_rate_deg_s * turn_command * stance_s)
		offset = offset.rotated(Vector3.UP, yaw)

	# Clamped twice, in this order: the step first, then the reach. A leg cannot
	# reach past its own length, and clamping the reach after the step is what
	# keeps a limb from planting a foot it would have to over-extend to hold.
	offset = offset.limit_length(profile.max_step_length_m * 0.5)
	var target := hip_ground + offset
	var from_hip := target - hip_world
	if from_hip.length() > profile.leg_length_m:
		target = hip_world + from_hip.normalized() * profile.leg_length_m
	return target


## §13.11's capture time constant, `sqrt(h / g)`, in seconds.
##
## [param com_height_m] is the height of the centre of mass over the planted
## foot, not over the body origin — an Assembly's origin is its lattice origin
## and sits wherever the Core Module's pivot cell happens to be, so measuring
## from it makes the pendulum a property of how the build was authored.
##
## Floored by [member LimbProfile.placement_gain_s], which is what that field now
## means: the authored gain is the correction a limb applies when it has no
## pendulum to measure — at spawn, in the air, or on a build whose centre of mass
## has collapsed onto its feet. Above that floor the physics decides.
static func capture_time_s(profile: LimbProfile, com_height_m: float) -> float:
	var h := maxf(com_height_m, 0.0)
	return maxf(sqrt(h / SyndicateConstants.GRAVITY_MPS2), profile.placement_gain_s)


## §13.11's capture point in world metres: where a foot must be planted for the
## body to arrive over it with its horizontal momentum spent.
##
## Exposed separately from [method foot_target] because it is the quantity a test
## can assert directly, and because a driver or a HUD that wants to show where
## the machine is about to have to step needs it without a limb profile.
static func capture_point(
	com_world: Vector3, com_velocity_mps: Vector3, com_height_m: float
) -> Vector3:
	var tau := sqrt(maxf(com_height_m, 0.0) / SyndicateConstants.GRAVITY_MPS2)
	return Vector3(
		com_world.x + com_velocity_mps.x * tau,
		com_world.y - com_height_m,
		com_world.z + com_velocity_mps.z * tau
	)


## Axial stance force in newtons along the hip-to-foot line.
##
## Clamped non-negative because a leg pushes and never pulls, the same rule
## §6.2 states for suspension. Clamped above at [member
## LimbProfile.max_foot_force_n], which is what makes an overloaded Assembly sag
## rather than launch: a limb rated at 42 kN under a build that puts 60 kN on it
## simply cannot hold the body up, and the Assembly settles until enough limbs
## share the load or it sits down.
static func stance_axial_force_n(
	profile: LimbProfile, length_m: float, prev_length_m: float, dt: float
) -> float:
	var compression := profile.stance_rest_length_m() - length_m
	var rate := 0.0
	if dt > 0.0:
		rate = (length_m - prev_length_m) / dt
	var f := profile.stance_stiffness_n_m * compression - profile.stance_damping_ns_m * rate
	return clampf(f, 0.0, profile.max_foot_force_n)


## Effective foot friction coefficient.
##
## Runs through the same [constant DegradationTable.MOTIVE_TRACTION] band
## multiplier the wheels use, so a damaged limb loses grip before it loses the
## ability to hold weight — the more interesting of the two failure orders.
static func foot_mu(
	profile: MotiveAssemblyProfile, band: int, surface_multiplier: float
) -> float:
	return (
		profile.traction_coefficient
		* DegradationTable.multiplier(DegradationTable.MOTIVE_TRACTION, band)
		* surface_multiplier
	)


## [param force] with its tangential component limited by what the normal load
## can hold against [param mu].
##
## A foot demanding more shear than friction allows slips: the force is scaled
## back and the caller slides the plant point by the residual, so an Assembly on
## a slick surface cannot accelerate, loses its footing progressively rather
## than in one frame, and recovers when it reaches grip.
static func limit_by_friction(force: Vector3, normal: Vector3, mu: float) -> Vector3:
	var n := normal.normalized()
	var along := force.dot(n)
	if along <= 0.0:
		return Vector3.ZERO
	var tangent := force - n * along
	var cap := mu * along
	if tangent.length() <= cap:
		return force
	return n * along + tangent.normalized() * cap


## True when [method limit_by_friction] would have scaled the tangent back.
static func would_slip(force: Vector3, normal: Vector3, mu: float) -> bool:
	var n := normal.normalized()
	var along := force.dot(n)
	if along <= 0.0:
		return false
	return (force - n * along).length() > mu * along


## Foot height above the line from [param from_world] to [param to_world] at
## swing progress [param t], in metres.
##
## Presentation only: nothing in the simulation reads a swinging foot. A
## parabola peaking at [member LimbProfile.step_height_m] at mid-swing.
static func swing_height_m(profile: LimbProfile, t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return profile.step_height_m * 4.0 * u * (1.0 - u)


## Progress through the swing half of the cycle, in [0, 1].
##
## Zero at lift-off and one at touchdown. A duty factor of 1.0 leaves no swing
## at all and answers zero rather than dividing by it — that is a limb that is
## always in stance, which is a legal profile and not an error.
static func swing_progress(phase: float, duty_factor: float) -> float:
	var span := 1.0 - duty_factor
	if span <= SyndicateConstants.EPSILON_LINEAR:
		return 0.0
	return clampf((phase - duty_factor) / span, 0.0, 1.0)


## Where the foot is [i]drawn[/i] at swing progress [param t]: a straight line
## from the point it left, [param from_world], to the point it is reaching for,
## [param to_world], lifted by [method swing_height_m].
##
## §13.7, and the whole of what a swinging limb contributes to what a player
## sees. The simulation applies no force during swing, so nothing that reads this
## can feed back into the physics — which is what lets the caller re-derive the
## target every tick from the placement law instead of freezing one at lift-off.
static func swing_foot_world(
	profile: LimbProfile, from_world: Vector3, to_world: Vector3, t: float
) -> Vector3:
	var u := clampf(t, 0.0, 1.0)
	return from_world.lerp(to_world, u) + Vector3.UP * swing_height_m(profile, u)
