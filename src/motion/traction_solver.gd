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

## Slip velocity, in m/s, below which the chord stiffness of §7.4's implicit step
## is taken as zero.
##
## Not a tolerance on the physics — it is the one place the chord `|F| / |u|` is
## genuinely 0/0, and the force there is zero too, so the implicit factor has
## nothing to damp. The stick cap of [method stick_limited_force_n] is what holds
## the contact in that neighbourhood, and it is exact rather than asymptotic.
const CHORD_EPSILON_MPS: float = 1e-4

## Floor on the mass a contact is credited with resisting its own slip through the
## chassis, in kilogrammes. Only reached by a contact carrying no load at all,
## which produces no friction either.
const MIN_SHARE_MASS_KG: float = 1.0

## Fraction of a slip the stick cap of §7.4 part 3 may remove in one tick.
##
## [b]Under one, and the reason is the second limit cycle this project found.[/b]
## A deadbeat cap — the force that lands the slip exactly on zero — is exact only
## if the mass resisting that slip is exact, and for a contact a metre below the
## centre of mass it is not: part of what the force moves is the hull's
## [i]rotation[/i], and the share mass of §7.4 accounts only for its translation.
## The overestimate reversed what it was correcting, and the reversal reversed
## back on the next tick.
##
## Measured on the reference build standing still: at 1.0 the roll rate alternated
## between −0.22 and +0.21 rad/s on every single tick — the identical signature
## §7.4's own defect had, one axis out and one layer up — and the hull crept at
## 0.05 m/s for as long as it was left alone. Halving the correction is what turns
## a deadbeat step into a geometric one, and it tolerates an effective mass
## overestimated by up to a factor of two, which is comfortably more than the
## rotational term can account for.
const STICK_RELAXATION: float = 0.5

## Floor on a contact's rotational inertia, in kg·m². A zero would divide.
const MIN_CONTACT_INERTIA: float = 0.001

## ===== §7.7 THE HOLDING BRAKE ==========================================

## Fraction of a Motive Assembly's authored brake torque the holding brake
## applies. The whole of it: the holding brake only ever engages at a crawl, so
## what it has to do is hold rather than decelerate, and a fraction of the service
## brake would only be a slower way to arrive at the same place.
const HOLDING_BRAKE_FRACTION: float = 1.0

## Speed, in m/s, below which the holding brake engages on its own. Above it a
## driver who has let go of everything is coasting, which is a thing they asked
## for; below it they have stopped, which is a thing the Assembly should stay in.
const HOLDING_BRAKE_SPEED_MPS: float = 1.5

## Fraction of the pitch-over deceleration the service brake is allowed to
## demand. §7.7's proportioning.
##
## An Assembly standing on a contact base of length `L` with its centre of mass
## `h` above that base tips forward when it decelerates harder than
## `g · (L/2) / h`. That is not a modelling artefact — it is what a short, tall
## vehicle does — and it stayed invisible while §7.4's step could not produce a
## real retarding force in the first place. With the step repaired, a tracked
## build braking from 4.8 m/s pitched to ninety degrees and finished balanced on
## its nose.
##
## The margin is what turns "will not tip" into "will not get near tipping", and
## it costs the reference wheeled build nothing: three metres of base under a
## centre of mass a metre up allows 11.8 m/s², which is above the 10.3 its
## contacts can make anyway. It bites only on the builds that need it.
const PITCH_LIMIT_MARGIN: float = 0.80

## Floor on the centre-of-mass height used in that ratio, in metres. A build whose
## centre of mass is at ground level cannot pitch over and must not divide by
## nothing on the way to finding that out.
const MIN_PITCH_HEIGHT_M: float = 0.20

## ===== §15.5's BRAKE RELEASE ===========================================

## Forward speed, in m/s, at or below which the service brake demand is released
## entirely, so that the same key is pure reverse drive.
const BRAKE_RELEASE_SPEED_MPS: float = 0.40

## Width of the band above that, in m/s, over which the release is taken. A step
## would put a discontinuity in the retarding force exactly where a player is
## trying to come to a stop.
const BRAKE_RELEASE_BAND_MPS: float = 0.60


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


## Reciprocal reduced mass of a contact's longitudinal slip, in 1/kg.
##
## §7.4's `A = r²/I_c + 1/m_share`. The slip is a difference between two things
## that move — the patch's own surface speed and the hull's — so the mass that
## resists changing it is the two in series, and both terms belong.
##
## [param share_mass_kg] is the hull mass this contact carries, taken from its
## own normal load rather than from a count of contacts: an Assembly with three
## wheels off the ground has one contact answering for all of it, and the
## normal force already knows that.
static func slip_mobility(
	inertia_kgm2: float, radius_m: float, share_mass_kg: float
) -> float:
	var r := maxf(radius_m, SyndicateConstants.EPSILON_LINEAR)
	return (
		r * r / maxf(inertia_kgm2, MIN_CONTACT_INERTIA)
		+ 1.0 / maxf(share_mass_kg, MIN_SHARE_MASS_KG)
	)


## The chord `|F| / |u|` of §7.2's curve over the slip the contact is actually
## at, in newtons per m/s.
##
## [b]The chord, and never the tangent at zero.[/b] The tangent bounds every
## slope the curve has, which makes it the natural choice for an implicit factor
## and makes it wrong: measured on the shipped build it over-damps by a factor of
## 317, so a contact knocked to a slip of −0.05 m/s takes forty ticks to recover
## and drags kilonewtons the whole time. An implicit factor is a statement about
## how fast the state may move, so an overestimate is not conservative — it is a
## brake nobody meant to fit. The chord is the average slope actually traversed,
## is never above the tangent, and collapses to the right small number past the
## peak.
static func chord_stiffness(f_long_n: float, slip_mps: float) -> float:
	if absf(slip_mps) < CHORD_EPSILON_MPS:
		return 0.0
	return absf(f_long_n) / absf(slip_mps)


## [param force_n] reduced, if it must be, to the largest force that removes no
## more than [constant STICK_RELAXATION] of [param slip] within one tick.
##
## §7.4 part 3, and it is what makes a stationary Assembly stay where it is. A
## friction force is a reaction: it opposes a slide and it may arrest one, but it
## may never reverse the slide it is opposing, and an explicit step is perfectly
## willing to. [param mobility] is 1/kg for a linear axis and
## [method slip_mobility] for the longitudinal one.
##
## It only ever reduces a magnitude, so it cannot inject energy (§11 invariant
## 10). See [constant STICK_RELAXATION] for why the bound is a fraction of the
## slip rather than the whole of it.
static func stick_limited_force_n(
	force_n: float, slip: float, mobility: float, dt: float
) -> float:
	if dt <= 0.0 or mobility <= 0.0:
		return force_n
	var limit := STICK_RELAXATION * absf(slip) / (dt * mobility)
	return clampf(force_n, -limit, limit)


## True when [param resist_nm] can absorb the whole of the torque acting on a
## stationary contact, so the contact is held and its slip can only change through
## the hull.
##
## The distinction is worth a function because [b]a held contact has a different
## mobility[/b]: §7.4's `A` puts the patch's own rotational inertia in series with
## the hull's mass, and a contact the brake is pinning cannot spend the rotational
## half. Sizing the stick cap against the series figure instead throttles a locked
## contact to a few hundred newtons — measured, and it is the difference between a
## service brake that stops an Assembly in three metres and one that takes ten.
static func is_contact_held(
	contact_omega: float, drive_nm: float, resist_nm: float, f_long_n: float, radius_m: float
) -> bool:
	if not is_zero_approx(contact_omega):
		return false
	return absf(drive_nm - f_long_n * radius_m) <= resist_nm


## Contact angular rate after one tick of drive, resistance, and ground reaction,
## stepped through the [b]slip velocity[/b] rather than through the rate itself.
##
## §7.4. `I_c ω̇ = τ − F_long·r` is the balance and it is right; what was wrong
## for the life of the project was integrating it explicitly. `F_long` is a very
## stiff function of `ω` near the rolling condition — about 2.9e5 N per rad/s at
## the shipped figures — so explicit Euler is stable only below 117 µs against a
## 16.7 ms tick, a factor of 142. It saturates rather than diverging, so it
## presented as a limit cycle: a contact under a parked build reversing eight
## times in twelve ticks and peaking at 5.9 rad/s against a free-rolling 1.2.
##
## The repair has three parts and each one is load-bearing.
##
## [b]One: step `u = ω·r − v_long`, not `ω`.[/b] The slip is the quantity the
## friction actually depends on, and `ω = (v_long + u) / r` is read back off it
## afterwards — so a contact follows an accelerating hull for free instead of
## having to be integrated into following it. Damping `ω` implicitly instead is
## unconditionally stable, kills the limit cycle exactly as intended, and was
## measured at [b]0.20 m/s under full throttle[/b], because the fictitious
## inertia that damps the residual also resists a contact genuinely spinning up.
##
## [b]Two: the implicit factor uses the chord[/b] — see [method chord_stiffness].
##
## [b]Three: the ground reaction is stick-limited[/b] — see
## [method stick_limited_force_n]. The caller applies the identical limited force
## to the body, so the hull and the patch never disagree about what passed
## between them.
##
## [param resist_nm] is the brake and the rolling resistance summed [i]before[/i]
## the sign is taken, so neither is ever applied in the direction the other
## resists. At rest it becomes a static hold: the resisting torque absorbs as much
## of the net torque as its capacity allows and no more, which is the difference
## between a parked Assembly and one whose brake vanishes the instant it succeeds.
## [code]signf(0.0)[/code] is [code]0.0[/code], and reading the sign off a
## stationary contact is what used to make the brake disappear at exactly the
## moment it had done its job.
static func integrate_contact(
	contact_omega: float,
	v_long_mps: float,
	inertia_kgm2: float,
	share_mass_kg: float,
	drive_nm: float,
	resist_nm: float,
	f_long_n: float,
	radius_m: float,
	dt: float
) -> float:
	var r := maxf(radius_m, SyndicateConstants.EPSILON_LINEAR)
	var i_c := maxf(inertia_kgm2, MIN_CONTACT_INERTIA)
	var u := contact_omega * r - v_long_mps
	var mobility := slip_mobility(i_c, r, share_mass_kg)

	# A contact the resistance is holding does not rotate, and saying so outright is
	# both exact and cheaper than deriving it. The alternative — stepping the slip
	# and reading the rate back off it — needs the hull's end-of-tick speed, and
	# predicting that from this contact's own force alone is a feed-forward that
	# [b]injects energy when it is wrong[/b]: measured, a parked build wound its
	# contacts up to thirteen rad/s and drove itself backwards at four metres a
	# second with the throttle at zero, because each tick's reconstruction credited
	# the hull with an acceleration it had not had.
	if is_contact_held(contact_omega, drive_nm, resist_nm, f_long_n, r):
		return 0.0

	# The torque the contact would feel with no brake and no rolling resistance.
	# Used only to decide how much of itself the resistance may spend; the balance
	# below carries the ground reaction through `mobility`, not through `tau`.
	var free_nm := drive_nm - f_long_n * r
	var resist_signed := (
		clampf(free_nm, -resist_nm, resist_nm)
		if is_zero_approx(contact_omega)
		else signf(contact_omega) * resist_nm
	)
	var tau := drive_nm - resist_signed

	var k := chord_stiffness(f_long_n, u)
	var next_u := u + dt * (r * tau / i_c - f_long_n * mobility) / (1.0 + dt * mobility * k)
	var next := (v_long_mps + next_u) / r
	# A brake may arrest a contact and may not reverse it. Guarded on the rate
	# rather than on the slip, because the slip of a locked contact is `-v_long`
	# and is supposed to be large — that is what a locked contact is.
	if resist_nm > 0.0 and signf(next) != signf(contact_omega) and not is_zero_approx(contact_omega):
		return 0.0
	return next


## Rotational inertia of a contact, in kg·m², as a uniform disc.
static func contact_inertia(mass_kg: float, radius_m: float) -> float:
	return 0.5 * mass_kg * radius_m * radius_m


## The hull mass a contact carrying [param normal_n] is answering for, in kg.
##
## The normal force divided by gravity, which is exactly the share in vertical
## equilibrium and degrades the right way out of it: a contact unweighted in a
## corner or over a crest is credited with less of the hull, which is what makes
## §7.4's slip step stop resisting it.
static func share_mass_kg(normal_n: float) -> float:
	return maxf(normal_n / SyndicateConstants.GRAVITY_MPS2, MIN_SHARE_MASS_KG)


## §15.5's brake release: the fraction of the service brake demand that survives
## at [param forward_speed_mps], the hull's velocity along its own nose.
##
## [b]Signed, and the sign is the whole point.[/b] `veh_brake` is one key meaning
## both "slow down" and "back out", and §15.5 keeps that arrangement because a
## reverse [i]state[/i] needs the input layer to know the Assembly's speed and
## produces the familiar failure where a build rolling backwards down a slope
## refuses to brake. What §15.5 could not do while §7.4 was unstable was let the
## brake actually work: a brake that holds a contact at rest also holds it against
## the reverse drive torque coming off the same key, and the Assembly never backs
## out at all.
##
## So the demand is released as the hull comes to a stop [i]going forwards[/i],
## and a hull already travelling backwards is below the band and never braked by
## the key that is reversing it. Above the band it is the full service brake.
static func brake_release_scale(forward_speed_mps: float) -> float:
	return clampf(
		(forward_speed_mps - BRAKE_RELEASE_SPEED_MPS) / BRAKE_RELEASE_BAND_MPS, 0.0, 1.0
	)


## §7.7's proportioning: the deceleration, in m/s², the service brake may demand
## of an Assembly whose leading contact is [param lever_m] ahead of its centre of
## mass with that centre [param com_height_m] above the contacts.
##
## [b]An aid may not apply a force the contacts could not, and it may not ask them
## for one that puts the Assembly on its roof either.[/b] §7.6 already modulates
## one flank's brakes to bias yaw; this is the same intervention in the other
## plane, and it is the reason a service brake that finally works is an
## improvement rather than a new way to lose a build.
##
## A lever of zero — the centre of mass already out over the leading contact —
## answers zero, which stops the brake outright rather than dividing by nothing.
## That is the correct answer: an Assembly that far over has no pitch authority
## left to spend.
static func pitch_limited_decel_mps2(lever_m: float, com_height_m: float) -> float:
	if lever_m <= 0.0:
		return 0.0
	return (
		PITCH_LIMIT_MARGIN
		* SyndicateConstants.GRAVITY_MPS2
		* lever_m
		/ maxf(com_height_m, MIN_PITCH_HEIGHT_M)
	)


## Drive torque for each contact, weighted by normal load.
##
## Load weighting is what suppresses wheelspin on an airborne contact without a
## traction-control hack: an unloaded contact receives almost no torque. A
## destroyed Prime Mover simply reduces the total; a destroyed contact simply
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
