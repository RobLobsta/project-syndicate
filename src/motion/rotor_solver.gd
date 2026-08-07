class_name RotorSolver
extends RefCounted
## Rotor lift and tilt, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §12.
##
## Pure statics over a [RotorProfile] and a [RotorDiscState]. A rotary Motive
## Assembly runs no probe and has no contact, so this family is the cheapest of
## the four per tick — it costs one [code]exp[/code], two rotations, and three
## calls into the physics server.

## Exchange rate between the shaft power a disc genuinely needs and the abstract
## Power Unit the schema budgets in.
##
## 4500 is not arbitrary: it is the value at which
## [code]mot.rotor.coaxial_mid.t3[/code] at full collective draws exactly 150 PU,
## the supply of one [code]pmv.combustion.standard.t2[/code]. The intended
## reading of a rotary Assembly's power line is therefore "one standard Power
## Plant per mid disc", legible in the garage without arithmetic.
const ROTOR_W_PER_PU: float = 4500.0

## Descent rates below this contribute no vortex ring loss at all, so a gentle
## settle onto a landing site is never punished.
const VORTEX_RING_ONSET_MPS: float = 1.0

## Horizontal speed, in m/s, at which §12.8's arrest demand saturates. Above it
## a full brake demand is the whole swashplate cone; below it the demand tapers
## with the speed, so the disc stops tilting as the hull stops moving rather than
## standing the Assembly on its nose over the last metre a second.
const ARREST_REFERENCE_MPS: float = 6.0


## Angular rate after one tick of spooling toward [param command_rad_s].
##
## The exact discrete solution of the first-order lag, not an Euler step. This
## matters here in a way it does not elsewhere in the motion layer: a client
## re-simulating a rotor during rollback replays several ticks inside one frame,
## and an Euler lag would converge at a different rate under replay than it did
## live, so a rotor's altitude would drift every time the network corrected it.
## ===== §12.7 ATTITUDE HOLD =============================================

## Time constant of the levelling loop, in seconds. The natural frequency is its
## reciprocal, so a smaller number is a stiffer machine.
##
## [b]A time rather than a torque, for the reason `LEARNED_FACTS.md` §1 fact 110
## records and §13.10's ankle constant paid for.[/b] An authored newton-metres
## would level a light Assembly briskly and a heavy one not at all, and would cap
## what a rotary build may carry at a mass nothing in the data or the interface
## states. The gain here is `I · ω_n²`, so it is a statement about how fast the
## attitude may be corrected and carries no assumption about the machine.
const ATTITUDE_RESPONSE_S: float = 0.45

## Damping ratio of the same loop. Just under critical: a rotorcraft that
## overshoots its level is one that porpoises, and one that is overdamped cannot
## be manoeuvred out of a bank.
const ATTITUDE_DAMPING_RATIO: float = 0.9


## §12.7's levelling torque about the horizontal axes, in world newton-metres.
##
## [b]Without this a rotary Assembly cannot fly, and the reason is that its thrust
## is fixed to its own hull.[/b] A disc pushes along the axis the chassis points
## it at, so a hull that has tilted one degree is a hull whose lift now has a
## horizontal component — which tilts it further. It is an inverted pendulum with
## the thrust above the centre of mass and nothing restoring it. Measured on the
## shipped recipe with a bare collective demand and no other input: the machine
## lifts off cleanly, passes 12° of tilt at two seconds, 57° at four, and comes
## down inverted at 177° — with a thrust-to-weight of 1.47, which is to say it was
## never short of lift.
##
## [b]It is bounded by [param authority_nm] and that bound is the model.[/b] The
## same rule §7.6 states for traction control: an aid may not apply a force the
## machine could not. What levels a helicopter is the swashplate tilting the disc
## against its own thrust, so the ceiling is `T · sin(cyclic_limit) · lever` —
## a disc making no thrust levels nothing, a disc at full thrust levels exactly as
## hard as its authored cone allows, and there is no configuration in which the
## term is free rotation. A rotary Assembly that has lost power falls over, which
## is correct.
##
## [b]Yaw is excluded rather than damped.[/b] [member RotorProfile.yaw_authority_nm]
## already owns that axis through [member ControlInput.yaw]; a leveller that also
## turned the machine would give the family two heading authorities, which is the
## defect §13.5 spent three sessions proving is worth avoiding.
##
## [param share] is one over the disc count, so an Assembly levels with the discs
## it still has and one with none does not level at all.
static func levelling_torque_nm(
	body_basis: Basis,
	angular_velocity: Vector3,
	horizontal_inertia_kg_m2: float,
	authority_nm: float,
	share: float
) -> Vector3:
	# `body_up x world_up` has |theta| = sin(tilt) and points along the rotation
	# that carries the hull back upright. Negating it is a controller that pushes
	# the machine over, and it would still look like a controller doing something
	# (CLAUDE.md §10 rule 14).
	var theta := body_basis.y.cross(Vector3.UP)
	var omega := angular_velocity - Vector3.UP * angular_velocity.dot(Vector3.UP)
	var w := 1.0 / maxf(ATTITUDE_RESPONSE_S, SyndicateConstants.EPSILON_LINEAR)
	var desired := (
		theta * (w * w) - omega * (2.0 * ATTITUDE_DAMPING_RATIO * w)
	) * maxf(horizontal_inertia_kg_m2, 0.0)
	return desired.limit_length(maxf(authority_nm, 0.0)) * clampf(share, 0.0, 1.0)


## The levelling authority one disc has, in newton-metres: the moment its own
## thrust makes when the swashplate tilts it to the edge of its cone.
static func levelling_authority_nm(
	profile: RotorProfile, thrust_n: float, lever_m: float
) -> float:
	return maxf(thrust_n, 0.0) * sin(deg_to_rad(profile.cyclic_limit_deg)) * maxf(lever_m, 0.0)


static func spool(omega_rad_s: float, command_rad_s: float, tau_s: float, dt: float) -> float:
	if tau_s <= 0.0 or dt <= 0.0:
		return command_rad_s
	return omega_rad_s + (command_rad_s - omega_rad_s) * (1.0 - exp(-dt / tau_s))


## The spool time constant to use for a step from [param omega_rad_s] toward
## [param command_rad_s].
##
## Spool-down is longer than spool-up on every shipping disc, which is what
## makes an unpowered descent survivable rather than a stone drop.
static func spool_tau_s(profile: RotorProfile, omega_rad_s: float, command_rad_s: float) -> float:
	return profile.spool_up_tau_s if command_rad_s >= omega_rad_s else profile.spool_down_tau_s


## Commanded angular rate, in rad/s, at [param throttle] and the power the
## Assembly can actually deliver.
##
## Power shortfall scales the [b]commanded rate[/b], never the thrust. Thrust
## goes as the square of the rate, so a 10% shortfall costs 19% of lift, the
## disc audibly slows, and the loss arrives over seconds because it is behind
## the spool lag. A rotary Assembly losing a Prime Mover sinks; it does not
## switch off.
static func commanded_omega(
	profile: RotorProfile, throttle: float, power_available_fraction: float
) -> float:
	return (
		profile.nominal_rad_s
		* clampf(throttle, 0.0, 1.0)
		* clampf(power_available_fraction, 0.0, 1.0)
	)


## Base thrust in newtons, before regime multipliers and degradation.
##
## The collective term is signed and normalised against the profile's
## [b]maximum[/b] collective, which is the pitch [member
## RotorProfile.thrust_coefficient] is quoted at. Negative collective therefore
## produces negative thrust — the disc pushes along its own -axis, which is how
## an Assembly holds itself down against a gust and why the minimum is authored
## negative rather than clamped at zero.
static func base_thrust_n(profile: RotorProfile, omega_rad_s: float, collective_deg: float) -> float:
	var tip := profile.tip_speed_mps(omega_rad_s)
	var reference := maxf(absf(profile.collective_limit_deg.y), SyndicateConstants.EPSILON_LINEAR)
	return (
		profile.thrust_coefficient
		* SyndicateConstants.AIR_DENSITY_KG_M3
		* profile.disc_area_m2()
		* tip
		* tip
		* (collective_deg / reference)
	)


## Ground effect multiplier at [param height_m] above the surface.
##
## Why a heavy rotary Assembly can lift off but cannot climb out. Without it,
## hovering a metre up feels identical to hovering at two hundred and the player
## never learns the disc is working.
static func ground_effect(profile: RotorProfile, height_m: float) -> float:
	var span := profile.ground_effect_radii * profile.disc_radius_m
	if span <= 0.0:
		return 1.0
	return 1.0 + profile.ground_effect_gain * maxf(0.0, 1.0 - maxf(height_m, 0.0) / span)


## Translational lift multiplier at horizontal airspeed [param airspeed_mps].
##
## Why forward flight is more efficient than a hover, and what makes a running
## takeoff a real technique rather than a cosmetic one.
static func translational_lift(profile: RotorProfile, airspeed_mps: float) -> float:
	if profile.translational_lift_mps <= 0.0:
		return 1.0
	var t := clampf(absf(airspeed_mps) / profile.translational_lift_mps, 0.0, 1.0)
	return 1.0 + profile.translational_lift_gain * t


## Vortex ring multiplier while descending at [param descent_mps] with
## [param airspeed_mps] of horizontal motion.
##
## The punishment for descending vertically into the disc's own downwash. The
## horizontal term is the escape: fly forward and it releases immediately, which
## is the actual recovery technique and is discoverable without a tutorial.
static func vortex_ring(profile: RotorProfile, descent_mps: float, airspeed_mps: float) -> float:
	if descent_mps <= VORTEX_RING_ONSET_MPS or profile.vortex_ring_descent_mps <= 0.0:
		return 1.0
	var depth := clampf(descent_mps / profile.vortex_ring_descent_mps, 0.0, 1.0)
	var escape := 1.0
	if profile.translational_lift_mps > 0.0:
		escape = 1.0 - clampf(absf(airspeed_mps) / profile.translational_lift_mps, 0.0, 1.0)
	return 1.0 - profile.vortex_ring_loss * depth * escape


## Thrust in newtons after every regime multiplier and the band multiplier.
##
## The band multiplier is [constant DegradationTable.MOTIVE_TRACTION], shared
## with the ground family rather than given a rotary column: a disc at IMPAIRED
## loses 40% of its thrust exactly as a wheel loses 40% of its grip, and
## Invariant I-5 wants one table.
static func effective_thrust_n(
	profile: RotorProfile,
	omega_rad_s: float,
	collective_deg: float,
	height_m: float,
	airspeed_mps: float,
	descent_mps: float,
	band: int
) -> float:
	return (
		base_thrust_n(profile, omega_rad_s, collective_deg)
		* ground_effect(profile, height_m)
		* translational_lift(profile, airspeed_mps)
		* vortex_ring(profile, descent_mps, airspeed_mps)
		* DegradationTable.multiplier(DegradationTable.MOTIVE_TRACTION, band)
	)


## Unit thrust direction in assembly space.
##
## The disc axis is the part's local +Y under its lattice orientation; cyclic
## deflects the thrust vector away from it. The two components are bounded on
## their [b]resultant[/b], because a swashplate's authority is a cone. Clamping
## per axis would let a stick held to a corner produce sqrt(2) times the limit,
## which is the classic diagonal-is-faster bug and is immediately exploitable in
## a game where tilt is how you accelerate.
static func thrust_direction(
	orientation_index: int, cyclic_deg: Vector2, limit_deg: float
) -> Vector3:
	var d := cyclic_deg.limit_length(maxf(limit_deg, 0.0))
	var dir := Vector3.UP
	dir = dir.rotated(Vector3.RIGHT, deg_to_rad(d.x))
	dir = dir.rotated(Vector3.BACK, deg_to_rad(d.y))
	return (OrientationTable.basis_for(orientation_index) * dir).normalized()


## Shaft torque in N·m at [param omega_rad_s].
static func shaft_torque_nm(profile: RotorProfile, omega_rad_s: float) -> float:
	var tip := profile.tip_speed_mps(omega_rad_s)
	return (
		profile.torque_coefficient
		* SyndicateConstants.AIR_DENSITY_KG_M3
		* profile.disc_area_m2()
		* tip
		* tip
		* profile.disc_radius_m
	)


## Shaft power in watts at [param omega_rad_s].
static func shaft_power_w(profile: RotorProfile, omega_rad_s: float) -> float:
	return shaft_torque_nm(profile, omega_rad_s) * omega_rad_s


## Power draw in Power Units at [param omega_rad_s].
static func draw_pu(profile: RotorProfile, omega_rad_s: float) -> float:
	return shaft_power_w(profile, omega_rad_s) / ROTOR_W_PER_PU


## Blade pitch after one tick of rate-limited travel toward [param command_deg].
##
## Rate-limited rather than lagged, unlike the angular rate: a swashplate is
## mechanically driven and genuinely does move at a constant rate.
static func step_collective(
	profile: RotorProfile, current_deg: float, command_deg: float, dt: float
) -> float:
	var target := clampf(
		command_deg, profile.collective_limit_deg.x, profile.collective_limit_deg.y
	)
	return move_toward(current_deg, target, profile.collective_rate_deg_s * dt)


## Cyclic demand, in the §15.4 convention, that arrests [param velocity_local] —
## the hull's horizontal velocity in its own frame — at [param demand] strength.
##
## §12.8, and the [b]whole[/b] of what a brake means to a family that touches
## nothing. `input.brake` reaches doc 05 §7's contact solve and no further, so a
## rotary Assembly had no deceleration control of any kind: the only way to stop
## one was to guess the opposite cyclic by hand and take it off again at the right
## moment.
##
## The two inversions are §15.4's and they are the reason this lives here rather
## than being written out at the call site. §12.3 rotates the disc axis about `+X`
## by `cyclic.x` and about `+Z` by `cyclic.y`, so a positive `cyclic.x` carries
## the thrust vector toward `+Z` — backwards — and a positive `cyclic.y` carries
## it toward `-X`, which is left. So arresting forward flight, which runs toward
## `-Z`, is a [b]positive[/b] x demand, and arresting rightward drift, which runs
## toward `+X`, is a positive y demand: `(-v.z, +v.x)`, normalised.
##
## [b]It is a brake and deliberately not an autopilot.[/b] It answers a demand
## the driver made, it stops the moment the demand does, and it is bounded to the
## same swashplate cone [method step_cyclic] bounds every other demand to. Holding
## a hover is three closed loops nobody asked for and is `HANDOFF.md` §3.7's.
static func arrest_cyclic(
	velocity_local: Vector3, demand: float, reference_mps: float
) -> Vector2:
	if reference_mps <= 0.0:
		return Vector2.ZERO
	var flat := Vector2(velocity_local.x, velocity_local.z) / reference_mps
	return Vector2(-flat.y, flat.x).limit_length(1.0) * clampf(demand, 0.0, 1.0)


## Cyclic deflection after one tick of rate-limited travel toward
## [param command_deg], with the command already bounded to the cone.
static func step_cyclic(
	profile: RotorProfile, current_deg: Vector2, command_deg: Vector2, dt: float
) -> Vector2:
	var target := command_deg.limit_length(profile.cyclic_limit_deg)
	var step := profile.cyclic_rate_deg_s * dt
	var delta := target - current_deg
	if delta.length() <= step:
		return target
	return current_deg + delta.normalized() * step
