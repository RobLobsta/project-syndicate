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


## Angular rate after one tick of spooling toward [param command_rad_s].
##
## The exact discrete solution of the first-order lag, not an Euler step. This
## matters here in a way it does not elsewhere in the motion layer: a client
## re-simulating a rotor during rollback replays several ticks inside one frame,
## and an Euler lag would converge at a different rate under replay than it did
## live, so a rotor's altitude would drift every time the network corrected it.
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
## the spool lag. A rotary Assembly losing a Power Plant sinks; it does not
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
