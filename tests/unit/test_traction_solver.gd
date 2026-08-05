extends TestCase
## [TractionSolver], from [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §7.

const RADIUS: float = 0.50
const RATED_KG: float = 620.0
const TRACTION: float = 1.05

var _profile: MotiveAssemblyProfile = null


func before_all() -> void:
	_profile = MotiveAssemblyProfile.new()
	_profile.contact_radius_m = RADIUS
	_profile.rated_load_kg = RATED_KG
	_profile.traction_coefficient = TRACTION
	_profile.rolling_resistance = 0.014


## ===== SLIP ============================================================


func test_slip_ratio_is_relative_to_the_contact_speed() -> void:
	# omega 10 rad/s at 0.5 m is a 5 m/s contact speed against 4 m/s of travel.
	check_approx(
		TractionSolver.slip_ratio(10.0, RADIUS, 4.0),
		0.25,
		"one metre per second of overspeed against four is 0.25"
	)


func test_slip_ratio_uses_the_reference_speed_at_rest() -> void:
	check_approx(
		TractionSolver.slip_ratio(10.0, RADIUS, 0.0),
		5.0 / TractionSolver.V_REF_MPS,
		"at rest the denominator is V_REF, not zero"
	)


func test_slip_angle_is_the_lateral_over_longitudinal_tangent() -> void:
	check_approx(TractionSolver.slip_angle_tan(2.0, 4.0), 0.5, "2 over 4")
	check_approx(
		TractionSolver.slip_angle_tan(2.0, -4.0),
		0.5,
		"the denominator is a magnitude, so reversing does not flip the slip angle"
	)


## ===== FRICTION CURVE ==================================================


func test_the_curve_is_normalised_to_unity_at_the_peak() -> void:
	check_approx(TractionSolver.pacejka(1.0), 1.0, "f(1) is exactly 1 at the peak slip")
	check_approx(TractionSolver.pacejka(0.0), 0.0, "no slip, no force")


## Steep below the peak and gentle beyond it is what gives controllable
## breakaway rather than a cliff. A curve that simply rose would pass a test that
## only checked f(1).
func test_the_curve_rises_steeply_then_falls_off_gently() -> void:
	check_true(TractionSolver.pacejka(0.5) > 0.5, "the rise below the peak is steeper than linear")
	check_true(TractionSolver.pacejka(2.0) < 1.0, "past the peak the curve falls back")
	check_true(
		TractionSolver.pacejka(2.0) > 0.75,
		"but gently: at twice the peak slip there is still most of the grip"
	)


## ===== LOAD SENSITIVITY ================================================


func test_load_sensitivity_is_unity_at_the_rating() -> void:
	check_approx(
		TractionSolver.load_sensitivity(_profile, RATED_KG * SyndicateConstants.GRAVITY_MPS2),
		1.0,
		"a contact carrying exactly its rating is unmodified"
	)


func test_double_the_rated_load_costs_the_documented_grip() -> void:
	check_approx(
		TractionSolver.load_sensitivity(_profile, 2.0 * RATED_KG * SyndicateConstants.GRAVITY_MPS2),
		1.0 - TractionSolver.K_LOAD,
		"double the rating loses 18% of nominal grip; the overweight-build behaviour"
	)


func test_load_sensitivity_clamps_both_ways() -> void:
	check_approx(
		TractionSolver.load_sensitivity(_profile, 0.0),
		TractionSolver.LOAD_SENS_MAX,
		"an unloaded contact caps at 1.15 rather than growing without bound"
	)
	check_approx(
		TractionSolver.load_sensitivity(_profile, 100.0 * RATED_KG * SyndicateConstants.GRAVITY_MPS2),
		TractionSolver.LOAD_SENS_MIN,
		"a grossly overloaded contact floors at 0.55"
	)


func test_effective_mu_multiplies_the_four_terms() -> void:
	var rated_n := RATED_KG * SyndicateConstants.GRAVITY_MPS2
	check_approx(
		TractionSolver.effective_mu(_profile, rated_n, PartEnums.IntegrityBand.NOMINAL, 1.0),
		TRACTION,
		"at the rating, undamaged, on a nominal surface, mu is the authored value"
	)
	check_approx(
		TractionSolver.effective_mu(_profile, rated_n, PartEnums.IntegrityBand.IMPAIRED, 1.0),
		TRACTION * 0.60,
		"IMPAIRED costs 40% of it, the mandated behaviour"
	)
	check_approx(
		TractionSolver.effective_mu(_profile, rated_n, PartEnums.IntegrityBand.NOMINAL, 0.42),
		TRACTION * 0.42,
		"a slick surface multiplies on top"
	)


## ===== COMBINED SLIP ===================================================


func test_pure_longitudinal_slip_at_the_peak_spends_all_the_grip_forwards() -> void:
	var f := TractionSolver.combined_forces(TractionSolver.KAPPA_PEAK, 0.0, 1.0, 1000.0, 1.0)
	check_approx(f.x, 1000.0, "the full friction budget, driving the Assembly forwards")
	check_approx(f.y, 0.0, "and nothing lateral")


## The three signs, pinned together. §7.1 defines kappa as (omega*r - v), which
## is already the negative of the patch's slip velocity, so the longitudinal and
## lateral components carry opposite signs. Getting this backwards inverts the
## throttle, which is what the §7.2 amendment records.
func test_the_sign_convention_in_all_three_directions() -> void:
	check_true(
		TractionSolver.combined_forces(0.1, 0.0, 1.0, 1000.0, 1.0).x > 0.0,
		"a driven contact — turning faster than the ground — pushes the Assembly forwards"
	)
	check_true(
		TractionSolver.combined_forces(-0.1, 0.0, 1.0, 1000.0, 1.0).x < 0.0,
		"and one dragging behind the ground pushes it backwards, which is engine braking"
	)
	check_true(
		TractionSolver.combined_forces(0.0, 0.1, 1.0, 1000.0, 1.0).y < 0.0,
		"a contact sliding right is pushed left, opposing the slide"
	)


func test_the_friction_circle_bounds_the_total_not_each_axis() -> void:
	var f := TractionSolver.combined_forces(
		TractionSolver.KAPPA_PEAK, TractionSolver.ALPHA_PEAK_TAN, 1.0, 1000.0, 1.0
	)
	var s := sqrt(2.0)
	check_approx(
		f.length(),
		1000.0 * TractionSolver.pacejka(s),
		"peak slip on both axes at once still spends one budget, not two",
		1e-3
	)
	check_approx(
		absf(f.x), absf(f.y), "and splits it evenly between them at equal normalised slip", 1e-3
	)


func test_no_slip_produces_no_force() -> void:
	check_eq(
		TractionSolver.combined_forces(0.0, 0.0, 1.0, 1000.0, 1.0),
		Vector2.ZERO,
		"a contact that is not sliding generates nothing"
	)


## The anisotropy of a tracked patch is applied inside the combined solve, so it
## changes the [b]longitudinal[/b] force too. Applied to the result instead, the
## longitudinal component would be identical and this test would fail — which is
## exactly the confusion §14.4 exists to prevent.
func test_lateral_grip_ratio_enters_before_the_combination() -> void:
	var circle := TractionSolver.combined_forces(
		TractionSolver.KAPPA_PEAK, TractionSolver.ALPHA_PEAK_TAN, 1.0, 1000.0, 1.0
	)
	var ellipse := TractionSolver.combined_forces(
		TractionSolver.KAPPA_PEAK, TractionSolver.ALPHA_PEAK_TAN, 1.0, 1000.0, 2.0
	)
	check_true(
		absf(ellipse.y) < absf(circle.y),
		"twice the lateral grip means the same slip angle is half as far into the budget"
	)
	check_ne(
		ellipse.x,
		circle.x,
		"and the longitudinal force changes with it, because the ratio is inside the solve"
	)
	check_true(
		absf(ellipse.x) > absf(circle.x),
		"the grip freed from cornering is available for drive"
	)


## ===== CONTACT INTEGRATION =============================================
## §7.4, as repaired. Every call below goes through the slip-velocity step; the
## explicit rate step it replaced was 142 times outside its own stability limit
## and hid that by saturating rather than diverging.

const SHARE_KG: float = 900.0
const CONTACT_MASS_KG: float = 68.0


func _inertia() -> float:
	return TractionSolver.contact_inertia(CONTACT_MASS_KG, RADIUS)


## One tick with a free contact — no ground reaction and no hull under it — is
## still `tau / I_c * dt`, because at `F = 0` the implicit factor is exactly 1 and
## the slip step reduces to the rate step. That equality is what says the repair
## changed the [i]conditioning[/i] of §7.4's balance and not the balance itself.
func test_drive_torque_spins_the_contact_up() -> void:
	check_approx(_inertia(), 0.5 * CONTACT_MASS_KG * RADIUS * RADIUS, "a uniform disc")
	check_approx(
		TractionSolver.integrate_contact(
			0.0, 0.0, _inertia(), SHARE_KG, 100.0, 0.0, 0.0, RADIUS,
			SyndicateConstants.PHYSICS_DT
		),
		100.0 / _inertia() * SyndicateConstants.PHYSICS_DT,
		"one tick of 100 N.m against the contact's own inertia"
	)


## §7.4's ground reaction. A contact that is gripping is retarded by that grip,
## which is what stops a driven contact spinning up without limit. The sign here
## and the sign in [method TractionSolver.combined_forces] have to agree, so this
## uses the output of that function rather than a hand-picked number.
func test_ground_reaction_opposes_the_drive() -> void:
	var grip := TractionSolver.combined_forces(0.1, 0.0, 1.0, 4000.0, 1.0).x
	check_true(grip > 0.0, "the contact is gripping forwards")
	var free := TractionSolver.integrate_contact(
		5.0, 2.4, _inertia(), SHARE_KG, 100.0, 0.0, 0.0, RADIUS,
		SyndicateConstants.PHYSICS_DT
	)
	var loaded := TractionSolver.integrate_contact(
		5.0, 2.4, _inertia(), SHARE_KG, 100.0, 0.0, grip, RADIUS,
		SyndicateConstants.PHYSICS_DT
	)
	check_true(loaded < free, "and a gripping contact spins up more slowly than a free one")


## The zero-crossing guard is what stops a braked contact oscillating around zero
## and injecting energy. Without it the same inputs overshoot into reverse.
func test_braking_stops_at_zero_rather_than_reversing() -> void:
	check_approx(
		TractionSolver.integrate_contact(
			1.0, 0.5, _inertia(), SHARE_KG, 0.0, 1000.0, 0.0, RADIUS,
			SyndicateConstants.PHYSICS_DT
		),
		0.0,
		"a brake big enough to reverse the contact in one tick stops it instead"
	)
	# The same magnitude applied as negative drive is not a brake, and must be
	# allowed to reverse — or the guard is firing on the wrong condition.
	check_true(
		TractionSolver.integrate_contact(
			1.0, 0.5, _inertia(), SHARE_KG, -1000.0, 0.0, 0.0, RADIUS,
			SyndicateConstants.PHYSICS_DT
		)
		< 0.0,
		"negative drive torque may reverse the contact; only braking is guarded"
	)


func test_a_gentle_brake_does_not_snap_to_zero() -> void:
	var next := TractionSolver.integrate_contact(
		10.0, 4.9, _inertia(), SHARE_KG, 0.0, 50.0, 0.0, RADIUS,
		SyndicateConstants.PHYSICS_DT
	)
	check_true(next > 0.0 and next < 10.0, "it slows without crossing zero")


## [b]The defect this file could not see for thirty-six sessions.[/b] A contact
## under a hull standing still, knocked a little off the rolling condition, must
## settle rather than oscillate. The old explicit step answered a rate of the
## opposite sign and larger magnitude on the very first tick, every tick, which is
## the limit cycle `tests/physics/test_rest_stability.gd` measures end to end.
func test_a_disturbed_contact_at_rest_settles_instead_of_reversing() -> void:
	var omega := 0.05
	var reversals := 0
	var previous := omega
	for _i: int in 12:
		var kappa := TractionSolver.slip_ratio(omega, RADIUS, 0.0)
		var f := TractionSolver.combined_forces(kappa, 0.0, 1.05, 8900.0, 1.0).x
		f = TractionSolver.stick_limited_force_n(
			f,
			omega * RADIUS,
			TractionSolver.slip_mobility(_inertia(), RADIUS, SHARE_KG),
			SyndicateConstants.PHYSICS_DT
		)
		omega = TractionSolver.integrate_contact(
			omega, 0.0, _inertia(), SHARE_KG, 0.0, 0.0, f, RADIUS,
			SyndicateConstants.PHYSICS_DT
		)
		if signf(omega) != signf(previous) and not is_zero_approx(omega):
			reversals += 1
		previous = omega
	check_eq(reversals, 0, "a settling contact never changes direction")
	check_true(absf(omega) < 0.05, "and it is nearer the rolling condition than it started")


## §7.4 part 3. A friction force may arrest a slide and may never reverse one, and
## an explicit step is perfectly willing to. The cap answers the force that lands
## the slip exactly on zero.
func test_the_stick_cap_reduces_only_what_would_overshoot() -> void:
	var dt := SyndicateConstants.PHYSICS_DT
	check_approx(
		TractionSolver.stick_limited_force_n(100.0, 4.0, 1.0 / 900.0, dt),
		100.0,
		"a force that cannot cross the slip inside a tick is untouched"
	)
	check_approx(
		TractionSolver.stick_limited_force_n(-1.0e6, 0.10, 1.0 / 900.0, dt),
		-TractionSolver.STICK_RELAXATION * 0.10 * 900.0 / dt,
		"and one that would is answered with the force that takes the agreed share off it"
	)
	check_true(
		TractionSolver.stick_limited_force_n(50.0, 0.0, 1.0 / 900.0, dt) == 0.0,
		"a contact with no slip at all is pushed by nothing"
	)


## LEARNED_FACTS fact 73's second wrong turn, pinned as a property rather than as
## a recollection. The tangent at zero is 12.415 times steeper than §7.2's average
## slope, so an implicit factor built on it over-damps by orders of magnitude.
func test_the_chord_is_the_stiffness_and_it_is_below_the_tangent() -> void:
	var normal := 8900.0
	var mu := 1.05
	# The tangent at zero, from §7.4's derivation: mu*N*f'(0)/kappa_peak * r/V_REF.
	var tangent := (
		mu * normal * 12.415 / TractionSolver.KAPPA_PEAK
		* RADIUS / TractionSolver.V_REF_MPS
	) / RADIUS
	var slip := 0.05
	var kappa := TractionSolver.slip_ratio(slip / RADIUS, RADIUS, 0.0)
	var chord := TractionSolver.chord_stiffness(
		TractionSolver.combined_forces(kappa, 0.0, mu, normal, 1.0).x, slip
	)
	check_true(chord > 0.0, "a sliding contact has a stiffness")
	check_true(chord < tangent, "and it is below the tangent at zero, never above it")
	check_approx(
		TractionSolver.chord_stiffness(0.0, 0.0),
		0.0,
		"at exactly the rolling condition there is no force to take a chord of"
	)


## §7.4's static hold, and the reason `signf(0.0) == 0.0` used to make a brake
## vanish at the moment it succeeded. A resisting torque at rest absorbs the net
## torque up to its own capacity and no further.
func test_a_resisting_torque_holds_a_stationary_contact() -> void:
	var dt := SyndicateConstants.PHYSICS_DT
	# The ground dragging a locked contact forwards: F_long negative, no drive.
	var held := TractionSolver.integrate_contact(
		0.0, 3.0, _inertia(), SHARE_KG, 0.0, 8300.0, -500.0, RADIUS, dt
	)
	check_true(
		absf(held) < 1e-4, "a brake with capacity to spare holds the contact at zero"
	)
	var overwhelmed := TractionSolver.integrate_contact(
		0.0, 3.0, _inertia(), SHARE_KG, 0.0, 10.0, -500.0, RADIUS, dt
	)
	check_true(
		overwhelmed > 0.0,
		"and one without it is overwhelmed rather than winning by arithmetic"
	)


## §15.5's release. One key means both "slow down" and "back out", and a brake
## that holds a contact at rest also holds it against the reverse drive coming off
## the same key.
func test_the_service_brake_is_released_as_the_hull_stops_going_forwards() -> void:
	check_approx(
		TractionSolver.brake_release_scale(8.0), 1.0, "at speed it is the full service brake"
	)
	check_approx(
		TractionSolver.brake_release_scale(TractionSolver.BRAKE_RELEASE_SPEED_MPS),
		0.0,
		"at a crawl it is released entirely, so the same key is pure reverse drive"
	)
	check_approx(
		TractionSolver.brake_release_scale(-4.0),
		0.0,
		"and a hull already rolling backwards is never braked by the key reversing it"
	)
	var mid := TractionSolver.brake_release_scale(
		TractionSolver.BRAKE_RELEASE_SPEED_MPS + TractionSolver.BRAKE_RELEASE_BAND_MPS * 0.5
	)
	check_true(mid > 0.0 and mid < 1.0, "and the release is a band rather than a step")


func test_the_share_mass_is_the_normal_load_over_gravity() -> void:
	check_approx(
		TractionSolver.share_mass_kg(900.0 * SyndicateConstants.GRAVITY_MPS2),
		900.0,
		"a contact in vertical equilibrium answers for exactly what it carries"
	)
	check_approx(
		TractionSolver.share_mass_kg(0.0),
		TractionSolver.MIN_SHARE_MASS_KG,
		"and an unloaded one floors rather than dividing by nothing"
	)


## Both terms of §7.4's mobility are load-bearing: dropping either makes the slip
## resist changing by the wrong amount, and only one of the two is obvious.
func test_the_slip_mobility_is_the_two_masses_in_series() -> void:
	var mobility := TractionSolver.slip_mobility(_inertia(), RADIUS, SHARE_KG)
	check_approx(
		mobility,
		RADIUS * RADIUS / _inertia() + 1.0 / SHARE_KG,
		"the contact's own rotational term plus the hull's linear one"
	)
	check_true(
		TractionSolver.slip_mobility(_inertia(), RADIUS, SHARE_KG * 100.0) < mobility,
		"a contact under more hull finds its slip harder to change"
	)


## ===== TORQUE DISTRIBUTION =============================================


func test_torque_is_split_by_normal_load() -> void:
	var out := TractionSolver.distribute_torque(800.0, PackedFloat32Array([100.0, 300.0]))
	check_approx(out[0], 200.0, "a quarter of the load takes a quarter of the torque")
	check_approx(out[1], 600.0, "and three quarters takes three quarters")


## Load weighting is what suppresses wheelspin on an airborne contact without a
## traction-control hack.
func test_an_unloaded_contact_receives_almost_no_torque() -> void:
	var out := TractionSolver.distribute_torque(800.0, PackedFloat32Array([0.0, 800.0]))
	check_approx(out[0], 0.0, "a contact carrying nothing is driven by nothing")
	check_approx(out[1], 800.0, "and the loaded one takes all of it")


func test_no_load_anywhere_distributes_nothing() -> void:
	var out := TractionSolver.distribute_torque(800.0, PackedFloat32Array([0.0, 0.0]))
	check_approx(out[0], 0.0, "an airborne Assembly spins no contact up")
	check_approx(out[1], 0.0, "including the second one")


func test_rolling_resistance_rises_with_damage() -> void:
	check_approx(
		TractionSolver.rolling_resistance_n(_profile, 1000.0, PartEnums.IntegrityBand.NOMINAL),
		14.0,
		"0.014 of the normal load"
	)
	check_approx(
		TractionSolver.rolling_resistance_n(_profile, 1000.0, PartEnums.IntegrityBand.IMPAIRED),
		14.0 * 1.35,
		"IMPAIRED adds 35%, per doc 05 §7.3"
	)


## ===== §7.8 CLOSED-THROTTLE RETARDATION AND THE CAP =====================
## Doc 05 §7.8, written out by hand here rather than imported, because a test that
## reads the same constant the source does asserts nothing (LEARNED_FACTS.md §2).

## §7.8's published table.
const DRAG_FRACTION: float = 0.35
const DRAG_TAPER_MPS: float = 2.00
const DRAG_RELEASE_THROTTLE: float = 0.20
const CAP_BAND_MPS: float = 2.00

## A contact's share of the shipped Prime Mover across four driven contacts.
const CAPACITY_NM: float = 1600.0


func test_the_driveline_drag_is_a_fraction_of_the_drive_capacity() -> void:
	check_approx(
		TractionSolver.driveline_drag_nm(CAPACITY_NM, 0.0, 10.0),
		DRAG_FRACTION * CAPACITY_NM,
		"a shut throttle above the speed taper retards with 0.35 of the capacity",
		1e-3
	)
	check_approx(
		TractionSolver.driveline_drag_nm(CAPACITY_NM * 2.0, 0.0, 10.0),
		DRAG_FRACTION * CAPACITY_NM * 2.0,
		"and twice the mover is twice the engine braking, which is what makes it "
		+ "a property of the machine rather than a figure of its own",
		1e-3
	)
	check_approx(
		TractionSolver.driveline_drag_nm(0.0, 0.0, 10.0),
		0.0,
		"an undriven contact freewheels",
		1e-6
	)


## [b]The assertion that would have caught the first version of this term.[/b]
## Scaled by a bare `1 − |throttle|` the drag cancels the drive at a quarter
## throttle, so the Assembly decelerates under a demand to accelerate.
func test_the_drag_is_released_before_any_useful_throttle_and_never_exceeds_the_drive() -> void:
	check_approx(
		TractionSolver.driveline_drag_nm(CAPACITY_NM, DRAG_RELEASE_THROTTLE, 10.0),
		0.0,
		"a fifth of the throttle releases it entirely",
		1e-6
	)
	check_approx(
		TractionSolver.driveline_drag_nm(CAPACITY_NM, 1.0, 10.0),
		0.0,
		"and full throttle certainly does",
		1e-6
	)
	# [b]The property the throttle must have, and the first version of this test
	# demanded something weaker.[/b] It asked only that net torque be monotonic and
	# accepted a band below an eighth of the throttle where a demand to accelerate
	# still retarded the Assembly — true of a real driveline and indefensible as a
	# control. The drag is now capped at the drive it is opposing, so the first
	# sliver of throttle releases the engine braking rather than losing to it.
	var previous := -INF
	for step: int in 41:
		var throttle := float(step) / 40.0
		var net := (
			CAPACITY_NM * throttle
			- TractionSolver.driveline_drag_nm(CAPACITY_NM, throttle, 10.0)
		)
		check_true(
			net >= previous,
			(
				"a throttle of %.3f nets %+.0f N.m against %+.0f at the step below it; "
				+ "more throttle may never mean less"
			) % [throttle, net, previous]
		)
		check_true(
			net >= 0.0 or is_zero_approx(throttle),
			(
				"and a throttle of %.3f nets %+.0f N.m — a demand to accelerate may "
				+ "never retard"
			) % [throttle, net]
		)
		previous = net
	# The other half: a shut throttle is still fully retarded, or the cap above has
	# deleted the term rather than bounded it.
	check_approx(
		TractionSolver.driveline_drag_nm(CAPACITY_NM, 0.0, 10.0),
		DRAG_FRACTION * CAPACITY_NM,
		"while a shut throttle keeps the whole of it",
		1e-3
	)


func test_the_drag_tapers_away_at_a_crawl_so_it_does_not_stand_in_for_the_holding_brake() -> void:
	check_approx(
		TractionSolver.driveline_drag_nm(CAPACITY_NM, 0.0, 0.0),
		0.0,
		"a stationary contact is not retarded by a driveline",
		1e-6
	)
	check_approx(
		TractionSolver.driveline_drag_nm(CAPACITY_NM, 0.0, DRAG_TAPER_MPS * 0.5),
		DRAG_FRACTION * CAPACITY_NM * 0.5,
		"and it comes in linearly over the first two metres a second",
		1e-3
	)
	check_true(
		TractionSolver.driveline_drag_nm(CAPACITY_NM, 0.0, -10.0) > 0.0,
		"a contact turning backwards is retarded too, and by the same amount"
	)


func test_the_speed_cap_governs_rather_than_switching_off() -> void:
	check_approx(
		TractionSolver.speed_cap_scale(0.0, 24.0), 1.0, "well below the cap, nothing is taken"
	)
	check_approx(
		TractionSolver.speed_cap_scale(24.0 - CAP_BAND_MPS * 0.5, 24.0),
		0.5,
		"half a band below it, half the torque survives",
		1e-6
	)
	check_approx(
		TractionSolver.speed_cap_scale(24.0, 24.0), 0.0, "at the cap, none does"
	)
	check_approx(
		TractionSolver.speed_cap_scale(40.0, 24.0),
		0.0,
		"and past it the taper clamps rather than driving the Assembly backwards",
		1e-6
	)


## A Core Module that publishes no cap is saying this document has nothing to add,
## not that the Assembly may not move.
func test_a_cap_of_zero_governs_nothing() -> void:
	check_approx(TractionSolver.speed_cap_scale(10.0, 0.0), 1.0, "a zero cap is no cap")
	check_approx(TractionSolver.speed_cap_scale(10.0, -1.0), 1.0, "and neither is a negative one")
