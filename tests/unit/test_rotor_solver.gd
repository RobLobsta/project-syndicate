extends TestCase
## [RotorSolver], from [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §12.
##
## The numbers here are the shipping `mot.rotor.coaxial_mid.t3` parameters of
## document 01 §10.3, and the thrust assertion is the relationship those
## coefficients were solved from rather than an observation of what the code
## happens to produce.

const DISC_R: float = 2.60
const OMEGA: float = 85.0
const C_T: float = 0.020
const C_Q: float = 0.0024
const RATED_KG: float = 2600.0
const COLLECTIVE_MAX: float = 14.0
const COLLECTIVE_MIN: float = -4.0
const CYCLIC_LIMIT: float = 14.0

var _rotor: RotorProfile = null


func before_all() -> void:
	_rotor = RotorProfile.new()
	_rotor.disc_radius_m = DISC_R
	_rotor.blade_count = 4
	_rotor.spin_sign = 1
	_rotor.nominal_rad_s = OMEGA
	_rotor.spool_up_tau_s = 2.40
	_rotor.spool_down_tau_s = 4.80
	_rotor.thrust_coefficient = C_T
	_rotor.torque_coefficient = C_Q
	_rotor.collective_limit_deg = Vector2(COLLECTIVE_MIN, COLLECTIVE_MAX)
	_rotor.collective_rate_deg_s = 22.0
	_rotor.cyclic_limit_deg = CYCLIC_LIMIT
	_rotor.cyclic_rate_deg_s = 48.0
	_rotor.yaw_authority_nm = 9600.0
	_rotor.torque_reaction_ratio = 0.0
	_rotor.ground_effect_radii = 1.0
	_rotor.ground_effect_gain = 0.24
	_rotor.translational_lift_mps = 14.0
	_rotor.translational_lift_gain = 0.18
	_rotor.vortex_ring_descent_mps = 6.0
	_rotor.vortex_ring_loss = 0.32


## ===== GEOMETRY ========================================================


func test_disc_area_and_tip_speed() -> void:
	check_approx(_rotor.disc_area_m2(), PI * DISC_R * DISC_R, "pi r squared", 1e-4)
	check_approx(_rotor.tip_speed_mps(OMEGA), 221.0, "85 rad/s at 2.6 m is 221 m/s", 1e-4)


## The relationship the coefficients were solved from, and what §14 rule 19
## checks on every shipped disc.
func test_max_thrust_lifts_the_rated_load() -> void:
	var required := RATED_KG * SyndicateConstants.GRAVITY_MPS2
	check_approx(
		_rotor.max_thrust_n() / required,
		1.0,
		"thrust at full collective is the rated load within 1%",
		0.01
	)


## ===== THRUST ==========================================================


func test_thrust_scales_with_collective_against_the_maximum() -> void:
	check_approx(
		RotorSolver.base_thrust_n(_rotor, OMEGA, COLLECTIVE_MAX),
		_rotor.max_thrust_n(),
		"full collective is the quoted maximum",
		1e-3
	)
	check_approx(
		RotorSolver.base_thrust_n(_rotor, OMEGA, COLLECTIVE_MAX * 0.5),
		_rotor.max_thrust_n() * 0.5,
		"half collective is half the thrust",
		1e-3
	)


## Signed, not clamped at zero: a disc at negative pitch pushes along its own
## -axis, which is how an Assembly holds itself down. A clamped implementation
## returns zero here and this is the test that says so.
func test_negative_collective_produces_negative_thrust() -> void:
	var t := RotorSolver.base_thrust_n(_rotor, OMEGA, COLLECTIVE_MIN)
	check_true(t < 0.0, "minimum collective pushes the Assembly down, not nothing")
	check_approx(
		t,
		_rotor.max_thrust_n() * (COLLECTIVE_MIN / COLLECTIVE_MAX),
		"and scales by the same normalisation",
		1e-3
	)


func test_thrust_goes_as_the_square_of_the_angular_rate() -> void:
	check_approx(
		RotorSolver.base_thrust_n(_rotor, OMEGA * 0.5, COLLECTIVE_MAX),
		RotorSolver.base_thrust_n(_rotor, OMEGA, COLLECTIVE_MAX) * 0.25,
		"halving the rate quarters the lift; why a power shortfall bites hard",
		1e-3
	)


## ===== REGIMES =========================================================


func test_ground_effect_is_strongest_on_the_deck_and_gone_by_one_radius() -> void:
	check_approx(RotorSolver.ground_effect(_rotor, 0.0), 1.24, "full gain at zero height")
	check_approx(RotorSolver.ground_effect(_rotor, DISC_R * 0.5), 1.12, "half gain at half span")
	check_approx(RotorSolver.ground_effect(_rotor, DISC_R), 1.0, "nothing at one radius up")
	check_approx(RotorSolver.ground_effect(_rotor, 500.0), 1.0, "and nothing far above it")


func test_translational_lift_saturates_at_its_authored_speed() -> void:
	check_approx(RotorSolver.translational_lift(_rotor, 0.0), 1.0, "a hover gets nothing")
	check_approx(RotorSolver.translational_lift(_rotor, 7.0), 1.09, "half speed, half gain")
	check_approx(RotorSolver.translational_lift(_rotor, 14.0), 1.18, "full gain")
	check_approx(RotorSolver.translational_lift(_rotor, 60.0), 1.18, "and no more beyond it")


func test_vortex_ring_needs_a_vertical_descent() -> void:
	check_approx(
		RotorSolver.vortex_ring(_rotor, 0.0, 0.0), 1.0, "a hover is not in its own downwash"
	)
	check_approx(
		RotorSolver.vortex_ring(_rotor, RotorSolver.VORTEX_RING_ONSET_MPS, 0.0),
		1.0,
		"a gentle settle onto a landing site is never punished"
	)
	check_approx(
		RotorSolver.vortex_ring(_rotor, 6.0, 0.0), 0.68, "a full vertical descent costs 32%"
	)
	check_approx(RotorSolver.vortex_ring(_rotor, 3.0, 0.0), 0.84, "half as deep, half the loss")


## Flying forward releases it immediately. This is the recovery technique, and a
## test that only checked the descent term would pass against an implementation
## with no escape at all.
func test_forward_flight_escapes_the_vortex_ring() -> void:
	check_approx(
		RotorSolver.vortex_ring(_rotor, 6.0, 14.0),
		1.0,
		"at translational lift speed the loss is fully released"
	)
	check_approx(
		RotorSolver.vortex_ring(_rotor, 6.0, 7.0), 0.84, "and half released at half that speed"
	)


func test_effective_thrust_stacks_every_regime_and_the_band() -> void:
	var base := RotorSolver.base_thrust_n(_rotor, OMEGA, COLLECTIVE_MAX)
	check_approx(
		RotorSolver.effective_thrust_n(
			_rotor, OMEGA, COLLECTIVE_MAX, 0.0, 14.0, 0.0, PartEnums.IntegrityBand.IMPAIRED
		),
		base * 1.24 * 1.18 * 1.0 * 0.60,
		"ground effect, translational lift, no vortex ring, and IMPAIRED",
		1.0
	)


## A disc at IMPAIRED loses exactly what a wheel at IMPAIRED loses. One table,
## per Invariant I-5.
func test_a_damaged_disc_uses_the_shared_motive_row() -> void:
	var nominal := RotorSolver.effective_thrust_n(
		_rotor, OMEGA, COLLECTIVE_MAX, 100.0, 0.0, 0.0, PartEnums.IntegrityBand.NOMINAL
	)
	var impaired := RotorSolver.effective_thrust_n(
		_rotor, OMEGA, COLLECTIVE_MAX, 100.0, 0.0, 0.0, PartEnums.IntegrityBand.IMPAIRED
	)
	check_approx(
		impaired / nominal,
		DegradationTable.MOTIVE_TRACTION[PartEnums.IntegrityBand.IMPAIRED],
		"the ratio is the shared MOTIVE_TRACTION entry"
	)


## ===== SPOOL ===========================================================


## The exact discrete solution is independent of the step size. An Euler lag is
## not, and a client replaying several ticks inside one rollback frame would
## converge to a different angular rate than it did live.
func test_spool_is_independent_of_the_step_size() -> void:
	var one := RotorSolver.spool(0.0, OMEGA, 2.4, 0.1)
	var half := RotorSolver.spool(RotorSolver.spool(0.0, OMEGA, 2.4, 0.05), OMEGA, 2.4, 0.05)
	check_approx(one, half, "one step of 0.1 s equals two of 0.05 s", 1e-9)


func test_spool_is_not_the_euler_step_it_would_be_mistaken_for() -> void:
	check_ne(
		RotorSolver.spool(0.0, OMEGA, 2.4, 0.1),
		OMEGA * (0.1 / 2.4),
		"the exact solution differs from a first-order Euler lag"
	)


func test_spool_approaches_but_never_overshoots() -> void:
	var w := 0.0
	var overshoots := 0
	for _i: int in 600:
		w = RotorSolver.spool(w, OMEGA, 2.4, SyndicateConstants.PHYSICS_DT)
		if w > OMEGA:
			overshoots += 1
	check_eq(overshoots, 0, "the rate never exceeds its command over ten seconds")
	# Ten seconds is 4.17 time constants, so 1.5% of the gap remains. Asserting
	# a fraction rather than equality keeps the test about the approach rather
	# than about how long the loop happens to run.
	check_true(w > OMEGA * 0.98, "and is within 2% of its command by then")


## Spool-down is longer than spool-up, which is what makes an unpowered descent
## survivable rather than a stone drop.
func test_spool_down_is_slower_than_spool_up() -> void:
	check_approx(RotorSolver.spool_tau_s(_rotor, 0.0, OMEGA), 2.40, "rising uses spool_up")
	check_approx(RotorSolver.spool_tau_s(_rotor, OMEGA, 0.0), 4.80, "falling uses spool_down")


func test_power_shortfall_scales_the_commanded_rate() -> void:
	check_approx(RotorSolver.commanded_omega(_rotor, 1.0, 1.0), OMEGA, "full power, full rate")
	check_approx(
		RotorSolver.commanded_omega(_rotor, 1.0, 0.9),
		OMEGA * 0.9,
		"a 10% shortfall costs 10% of the rate, which is 19% of the lift"
	)
	check_approx(
		RotorSolver.commanded_omega(_rotor, 1.0, 2.0),
		OMEGA,
		"surplus power does not overspeed the disc"
	)


## ===== TILT ============================================================


func test_no_cyclic_points_along_the_disc_axis() -> void:
	var d := RotorSolver.thrust_direction(0, Vector2.ZERO, CYCLIC_LIMIT)
	check_approx(d.angle_to(Vector3.UP), 0.0, "at orientation 0 the axis is straight up")


func test_single_axis_cyclic_tilts_by_its_full_deflection() -> void:
	var d := RotorSolver.thrust_direction(0, Vector2(CYCLIC_LIMIT, 0.0), CYCLIC_LIMIT)
	check_approx(
		rad_to_deg(d.angle_to(Vector3.UP)), CYCLIC_LIMIT, "14 degrees of pitch is 14 of tilt", 1e-3
	)


## The swashplate's authority is a cone. Clamping per axis instead would let a
## stick held to a corner produce sqrt(2) times the limit — the classic
## diagonal-is-faster bug, and immediately exploitable where tilt is how you
## accelerate.
func test_diagonal_cyclic_is_bounded_by_the_cone_not_a_box() -> void:
	var single := RotorSolver.thrust_direction(0, Vector2(CYCLIC_LIMIT, 0.0), CYCLIC_LIMIT)
	var diagonal := RotorSolver.thrust_direction(
		0, Vector2(CYCLIC_LIMIT, CYCLIC_LIMIT), CYCLIC_LIMIT
	)
	check_true(
		diagonal.angle_to(Vector3.UP) <= single.angle_to(Vector3.UP) + 1e-4,
		"a corner input tilts no further than a cardinal one"
	)
	check_true(
		rad_to_deg(diagonal.angle_to(Vector3.UP)) < CYCLIC_LIMIT * 1.41,
		"and nowhere near the sqrt(2) a box clamp would give"
	)


func test_the_thrust_direction_follows_the_lattice_orientation() -> void:
	var upright := RotorSolver.thrust_direction(0, Vector2.ZERO, CYCLIC_LIMIT)
	var rotated := RotorSolver.thrust_direction(5, Vector2.ZERO, CYCLIC_LIMIT)
	check_approx(rotated.length(), 1.0, "always a unit vector")
	check_approx(
		rotated.distance_to(OrientationTable.basis_for(5) * Vector3.UP),
		0.0,
		"the axis is the part's own +Y under its orientation basis",
		1e-5
	)
	check_ne(upright, rotated, "and a rotated part does not thrust straight up")


## ===== TORQUE AND POWER ================================================


func test_shaft_torque_and_power_follow_the_torque_coefficient() -> void:
	var tip := _rotor.tip_speed_mps(OMEGA)
	check_approx(
		RotorSolver.shaft_torque_nm(_rotor, OMEGA),
		C_Q * SyndicateConstants.AIR_DENSITY_KG_M3 * _rotor.disc_area_m2() * tip * tip * DISC_R,
		"the published expression, evaluated",
		1e-3
	)
	check_approx(
		RotorSolver.shaft_power_w(_rotor, OMEGA),
		RotorSolver.shaft_torque_nm(_rotor, OMEGA) * OMEGA,
		"power is torque times rate",
		1e-3
	)


## ROTOR_W_PER_PU is 4500 precisely so that this disc draws one standard Power
## Plant's supply. If that stops being true the constant has lost its meaning.
func test_a_mid_disc_at_full_collective_draws_one_standard_power_plant() -> void:
	check_approx(
		RotorSolver.draw_pu(_rotor, OMEGA),
		150.0,
		"§12.5: one pmv.combustion.standard.t2 per mid disc",
		1.0
	)


## ===== SWASHPLATE STEPS ================================================


func test_collective_is_rate_limited_and_clamped_to_its_range() -> void:
	check_approx(
		RotorSolver.step_collective(_rotor, 0.0, 100.0, 1.0),
		COLLECTIVE_MAX,
		"one second of travel cannot exceed the authored maximum"
	)
	check_approx(
		RotorSolver.step_collective(_rotor, 0.0, COLLECTIVE_MAX, 0.1),
		2.2,
		"and within the range it moves at the authored rate"
	)
	check_approx(
		RotorSolver.step_collective(_rotor, 0.0, -100.0, 1.0),
		COLLECTIVE_MIN,
		"the negative limit clamps too"
	)


func test_cyclic_steps_toward_a_cone_limited_target() -> void:
	var stepped := RotorSolver.step_cyclic(_rotor, Vector2.ZERO, Vector2(100.0, 0.0), 0.1)
	check_approx(stepped.x, 4.8, "48 deg/s for 0.1 s")
	check_approx(stepped.y, 0.0, "and nothing on the other axis")
	var settled := RotorSolver.step_cyclic(_rotor, Vector2.ZERO, Vector2(100.0, 100.0), 10.0)
	check_approx(
		settled.length(), CYCLIC_LIMIT, "a long step lands on the cone, not past it", 1e-4
	)


## ===== §12.7 ATTITUDE HOLD =============================================


## [b]The sign, and CLAUDE.md §10 rule 14 is why this is the first assertion.[/b]
## A negated levelling term is a controller that pushes the machine over, and it
## still produces a non-zero torque of a plausible magnitude — so a test that
## asserted "a torque was applied" would pass on the version that flips the
## Assembly onto its back.
func test_the_levelling_torque_rotates_the_hull_back_toward_upright() -> void:
	# Banked with the hull's up axis tilted toward +X. The restoring axis is
	# `body_up x world_up`, which for that bank is +Z — and a positive rotation
	# about +Z carries (+x, +y) toward (-y, +x), taking the up axis back off +X.
	# [b]Verified by rotating the fixture rather than by reasoning about it[/b]: the
	# check below applies the torque's own axis to the banked basis and asserts the
	# tilt actually falls, which is the only form of this test a sign flip cannot
	# pass.
	var banked := Basis(Vector3.BACK, deg_to_rad(-20.0))
	var torque := RotorSolver.levelling_torque_nm(
		banked, Vector3.ZERO, 1000.0, 1.0e9, 1.0
	)
	check_true(banked.y.x > 0.0, "the fixture is banked with its up axis toward +X")
	check_true(
		torque.z > 0.0,
		"and the levelling torque is about +Z: %s" % torque
	)
	check_true(
		Basis(torque.normalized(), deg_to_rad(5.0)).y.angle_to(Vector3.UP)
		< banked.y.angle_to(Vector3.UP),
		"and turning the hull about that axis reduces its tilt rather than adding to it"
	)
	check_approx(torque.y, 0.0, "with nothing about world up")

	# The mirror, because a term that only ever answers one sign is a constant.
	var other := RotorSolver.levelling_torque_nm(
		Basis(Vector3.BACK, deg_to_rad(20.0)), Vector3.ZERO, 1000.0, 1.0e9, 1.0
	)
	check_true(other.z < 0.0, "and a bank the other way is corrected the other way")


func test_a_level_hull_is_left_alone() -> void:
	check_true(
		RotorSolver.levelling_torque_nm(
			Basis(), Vector3.ZERO, 1000.0, 1.0e9, 1.0
		).is_zero_approx(),
		"an upright hull with no rate needs no correction"
	)


## The damping half, asserted on a hull that is already level and rolling. Without
## it the loop is a spring and the Assembly porpoises rather than settling.
func test_the_levelling_torque_opposes_a_roll_rate() -> void:
	var torque := RotorSolver.levelling_torque_nm(
		Basis(), Vector3(0.0, 0.0, 4.0), 1000.0, 1.0e9, 1.0
	)
	check_true(torque.z < 0.0, "a level hull rolling about +Z is retarded about -Z")


## §12.7's bound is the model rather than a safety rail: what levels a rotorcraft
## is the swashplate working against its own thrust, so a disc making none levels
## nothing and a powerless Assembly falls over.
func test_the_levelling_torque_cannot_exceed_the_discs_own_authority() -> void:
	var wild := Basis(Vector3.BACK, deg_to_rad(-60.0))
	var bounded := RotorSolver.levelling_torque_nm(wild, Vector3.ZERO, 50000.0, 900.0, 1.0)
	check_approx(
		bounded.length(), 900.0, "an absurd tilt still only gets the authority it has", 1e-3
	)
	check_true(
		RotorSolver.levelling_torque_nm(wild, Vector3.ZERO, 50000.0, 0.0, 1.0).is_zero_approx(),
		"and a disc producing no thrust levels nothing at all"
	)


## Yaw belongs to [member RotorProfile.yaw_authority_nm] and to nothing else. Two
## controllers on one axis is the defect doc 05 §13.5 spent three sessions on.
func test_the_levelling_torque_never_touches_yaw() -> void:
	var torque := RotorSolver.levelling_torque_nm(
		Basis(Vector3.BACK, deg_to_rad(-15.0)), Vector3(0.0, 6.0, 0.0), 1000.0, 1.0e9, 1.0
	)
	check_approx(torque.y, 0.0, "a hull spinning about world up is not levelled by this term")


## One over the disc count, so an Assembly levels with the discs it still has.
func test_the_levelling_share_scales_the_result() -> void:
	var whole := RotorSolver.levelling_torque_nm(
		Basis(Vector3.BACK, deg_to_rad(-10.0)), Vector3.ZERO, 1000.0, 1.0e9, 1.0
	)
	var half := RotorSolver.levelling_torque_nm(
		Basis(Vector3.BACK, deg_to_rad(-10.0)), Vector3.ZERO, 1000.0, 1.0e9, 0.5
	)
	check_approx(half.length(), whole.length() * 0.5, "half the discs, half the authority", 1e-3)


## The authority is the moment the thrust makes at the edge of the cone, so it is
## linear in both thrust and lever and zero when either is.
func test_the_levelling_authority_is_thrust_times_cone_times_lever() -> void:
	var authority := RotorSolver.levelling_authority_nm(_rotor, 10000.0, 2.0)
	check_approx(
		authority,
		10000.0 * sin(deg_to_rad(CYCLIC_LIMIT)) * 2.0,
		"T sin(cone) x lever"
	)
	check_approx(
		RotorSolver.levelling_authority_nm(_rotor, 10000.0, 0.0),
		0.0,
		"a disc on the centre of mass has no lever and levels nothing"
	)
