extends TestCase
## Every static of [TractionControl], asserted against the constant table
## published in [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §7.6.
##
## The published values are written out here by hand rather than imported from
## the class under test. A test that reads the same constant its subject reads
## asserts nothing: change the constant and the expectation moves with it. §7.6
## is the owner, this file is where the code is checked against §7.6, and
## [code]tests/physics/test_ground_assembly.gd[/code] is where the two loops are
## checked against an Assembly that is actually moving.

## §7.6's table, quoted.
const DOC_TARGET_SLIP_RATIO: float = 0.14
const DOC_LAUNCH_REFERENCE_MPS: float = 5.0
const DOC_SLIP_GAIN: float = 1.2
const DOC_YAW_GAIN_NM_PER_RAD_S: float = 2600.0
const DOC_YAW_DEADBAND_RAD_S: float = 0.10
const DOC_MAX_BRAKE_FRACTION: float = 0.25
const DOC_MIN_YAW_CONTROL_SPEED_MPS: float = 1.5
const DOC_YAW_CONTROL_SPEED_FRACTION: float = 0.317
const DOC_GRIP_YAW_MARGIN: float = 0.95

## The reference Core Module's authored cap, and the figure §7.6's ladder was
## measured against. Quoted rather than loaded: this file checks the code against
## the document, and a test that reads the `.tres` would move with the data.
const REFERENCE_SPEED_CAP_MPS: float = 24.0


func test_the_published_constants_are_what_the_document_says() -> void:
	check_approx(
		TractionControl.TARGET_SLIP_RATIO, DOC_TARGET_SLIP_RATIO, "TARGET_SLIP_RATIO"
	)
	check_approx(
		TractionControl.LAUNCH_REFERENCE_MPS, DOC_LAUNCH_REFERENCE_MPS, "LAUNCH_REFERENCE_MPS"
	)
	check_approx(TractionControl.SLIP_GAIN, DOC_SLIP_GAIN, "SLIP_GAIN")
	check_approx(
		TractionControl.YAW_GAIN_NM_PER_RAD_S,
		DOC_YAW_GAIN_NM_PER_RAD_S,
		"YAW_GAIN_NM_PER_RAD_S"
	)
	check_approx(
		TractionControl.YAW_DEADBAND_RAD_S, DOC_YAW_DEADBAND_RAD_S, "YAW_DEADBAND_RAD_S"
	)
	check_approx(
		TractionControl.MAX_BRAKE_FRACTION, DOC_MAX_BRAKE_FRACTION, "MAX_BRAKE_FRACTION"
	)
	check_approx(
		TractionControl.MIN_YAW_CONTROL_SPEED_MPS,
		DOC_MIN_YAW_CONTROL_SPEED_MPS,
		"MIN_YAW_CONTROL_SPEED_MPS"
	)
	check_approx(
		TractionControl.YAW_CONTROL_SPEED_FRACTION,
		DOC_YAW_CONTROL_SPEED_FRACTION,
		"YAW_CONTROL_SPEED_FRACTION"
	)
	check_approx(TractionControl.GRIP_YAW_MARGIN, DOC_GRIP_YAW_MARGIN, "GRIP_YAW_MARGIN")


## ===== SLIP LIMITING ===================================================


func test_slip_inside_the_allowance_is_not_touched() -> void:
	# At 20 m/s the allowance is 0.14 x 20 = 2.8 m/s of patch overspeed, which is
	# the ratio doing its job. Anything inside it is the tyre working, not
	# spinning.
	check_approx(
		TractionControl.drive_scale(22.7, 20.0, 1.0), 1.0, "2.7 m/s of slip at 20 m/s is fine"
	)
	check_approx(
		TractionControl.drive_scale(20.0, 20.0, 1.0), 1.0, "and no slip at all certainly is"
	)


func test_slip_past_the_allowance_is_cut_by_the_documented_reciprocal() -> void:
	# 20 m/s road, 25 m/s patch: 5.0 of slip against a 2.8 allowance leaves 2.2
	# of excess, and 1 / (1 + 2.2 x 1.2) is 0.27472527.
	var excess := 5.0 - DOC_TARGET_SLIP_RATIO * 20.0
	check_approx(
		TractionControl.drive_scale(25.0, 20.0, 1.0),
		1.0 / (1.0 + excess * DOC_SLIP_GAIN),
		"the cut is the reciprocal of §7.6, not a subtraction"
	)


func test_the_cut_is_never_total_and_never_changes_sign() -> void:
	# Shaped as a reciprocal precisely so that it cannot. A limiter that could
	# reach zero would leave an Assembly with no way out of a slide, and one that
	# could go negative would drive it backwards out of a wheelspin.
	var absurd := TractionControl.drive_scale(400.0, 0.0, 1.0)
	check_true(absurd > 0.0, "a wheel at 400 m/s of patch speed still gets some torque")
	check_true(absurd < 0.01, "though not much of it")


func test_the_allowance_is_a_slip_velocity_below_the_launch_floor() -> void:
	# The finding that cost session 12 a test. §7.1 divides by max(|v|, 0.8), so
	# a stationary Assembly reads any rotation at all as enormous slip; a limiter
	# that believed the ratio would cut its torque to nothing and it would never
	# move. The floor turns the law into a slip velocity below 5 m/s.
	check_approx(
		TractionControl.drive_scale(DOC_TARGET_SLIP_RATIO * DOC_LAUNCH_REFERENCE_MPS, 0.0, 1.0),
		1.0,
		"0.7 m/s of patch speed at a standstill is the launch allowance, and is free"
	)
	check_true(
		TractionControl.drive_scale(0.5, 1.0, 1.0) > 0.99,
		"a metre per second of road speed still gets the floor's allowance, not 0.14 of its own"
	)
	check_true(
		TractionControl.drive_scale(4.0, 0.0, 1.0) < 0.25,
		"and a wheel genuinely running away at a standstill is still caught"
	)


func test_authority_lerps_between_the_drivers_torque_and_the_managed_one() -> void:
	var managed := TractionControl.drive_scale(25.0, 20.0, 1.0)
	check_approx(
		TractionControl.drive_scale(25.0, 20.0, 0.0),
		1.0,
		"at zero authority the driver gets every newton-metre, wheelspin included"
	)
	check_approx(
		TractionControl.drive_scale(25.0, 20.0, 0.5),
		lerpf(1.0, managed, 0.5),
		"and a half is a real intermediate state rather than one of the two ends"
	)


func test_the_limiter_does_not_care_which_way_the_slip_points() -> void:
	# A locked wheel under braking slips as hard as a spinning one under power,
	# and §7.6's `excess` is taken on the magnitude.
	check_approx(
		TractionControl.drive_scale(15.0, 20.0, 1.0),
		TractionControl.drive_scale(25.0, 20.0, 1.0),
		"5 m/s of slip is 5 m/s of slip in either direction"
	)


## ===== YAW TARGET ======================================================


func test_the_yaw_target_is_the_bicycle_model() -> void:
	# Forward is -Z and right is +X, so a right-hand lock is a negative rotation
	# about +Y. Getting this backwards makes the controller brake the flank that
	# adds to the turn.
	var target := TractionControl.target_yaw_rate_rad_s(10.0, deg_to_rad(20.0), 2.5)
	check_approx(
		target, -10.0 * tan(deg_to_rad(20.0)) / 2.5, "v tan(delta) / L, negative to the right"
	)
	check_true(
		TractionControl.target_yaw_rate_rad_s(10.0, deg_to_rad(-20.0), 2.5) > 0.0,
		"and a left-hand lock asks for a positive yaw"
	)


func test_a_build_with_no_wheelbase_asks_for_no_yaw() -> void:
	# A single-axle build, or one whose Motive Assemblies have not registered
	# yet. Dividing by it would produce an infinite target and a permanent
	# full-authority brake on one flank.
	check_approx(
		TractionControl.target_yaw_rate_rad_s(10.0, deg_to_rad(20.0), 0.0),
		0.0,
		"a zero wheelbase is no bicycle model at all"
	)


func test_the_grip_limit_falls_away_with_speed() -> void:
	# 0.95 x mu x g / v. At 10 m/s on a mu of 1.0 that is 0.93195 rad/s, and it
	# halves every time the speed doubles.
	check_approx(
		TractionControl.grip_limited_yaw_rate_rad_s(10.0, 1.0),
		DOC_GRIP_YAW_MARGIN * SyndicateConstants.GRAVITY_MPS2 / 10.0,
		"the limit is the lateral acceleration the contacts could deliver"
	)
	check_true(
		TractionControl.grip_limited_yaw_rate_rad_s(20.0, 1.0)
		< TractionControl.grip_limited_yaw_rate_rad_s(10.0, 1.0),
		"and it tightens as the Assembly speeds up"
	)


func test_the_loop_engages_at_a_fraction_of_the_builds_own_cap() -> void:
	# The user-visible half of §7.6: the aid is for a machine that is travelling,
	# and 1.5 m/s is a walking pace. The engagement speed is a fraction of the
	# Assembly's authored cap so that "fast" means fast *for this build* — a 14 m/s
	# tracked hauler and a 24 m/s road build do not share a definition of it, and
	# an absolute figure would be silently tuned against whichever one the session
	# happened to have open (LEARNED_FACTS.md §1 fact 110).
	check_approx(
		TractionControl.yaw_engagement_speed_mps(REFERENCE_SPEED_CAP_MPS),
		REFERENCE_SPEED_CAP_MPS * DOC_YAW_CONTROL_SPEED_FRACTION,
		"the reference build engages the loop at about 7.6 m/s"
	)
	check_true(
		TractionControl.yaw_engagement_speed_mps(REFERENCE_SPEED_CAP_MPS)
		> DOC_MIN_YAW_CONTROL_SPEED_MPS * 4.0,
		"which is several times the 1.5 m/s floor it used to engage at"
	)
	check_true(
		TractionControl.yaw_engagement_speed_mps(14.0)
		< TractionControl.yaw_engagement_speed_mps(REFERENCE_SPEED_CAP_MPS),
		"and a slower build engages it sooner, in absolute terms, than a faster one"
	)


func test_the_engagement_speed_never_falls_under_the_models_own_floor() -> void:
	# The floor is the bicycle model's singularity guard rather than a design
	# choice, so a build with an absurdly low cap still keeps out of it. Without
	# this a 2 m/s cap would engage the loop at 0.63 m/s, where the grip limit is
	# dividing by almost nothing.
	check_approx(
		TractionControl.yaw_engagement_speed_mps(1.0),
		DOC_MIN_YAW_CONTROL_SPEED_MPS,
		"a 1 m/s cap still does not engage the loop under the floor"
	)
	check_approx(
		TractionControl.yaw_engagement_speed_mps(0.0),
		DOC_MIN_YAW_CONTROL_SPEED_MPS,
		"and neither does a build that reports no cap at all"
	)


func test_the_controller_stands_down_below_the_minimum_speed() -> void:
	# An unbounded limit is what "leave the brakes alone" looks like to
	# yaw_error_rad_s: the clamp becomes a no-op and a stationary Assembly can be
	# pivoted on the handbrake without the aid fighting it.
	check_true(
		is_inf(TractionControl.grip_limited_yaw_rate_rad_s(DOC_MIN_YAW_CONTROL_SPEED_MPS * 0.5, 1.0)),
		"below 1.5 m/s the yaw controller has no opinion"
	)
	check_false(
		is_inf(TractionControl.grip_limited_yaw_rate_rad_s(DOC_MIN_YAW_CONTROL_SPEED_MPS * 2.0, 1.0)),
		"and above it, it does"
	)


## ===== YAW ERROR AND THE BRAKE =========================================


func test_an_error_inside_the_deadband_is_no_error() -> void:
	check_approx(
		TractionControl.yaw_error_rad_s(DOC_YAW_DEADBAND_RAD_S * 0.5, 0.0, INF),
		0.0,
		"0.05 rad/s of drift on a straight is the suspension settling, not a fault"
	)


func test_the_deadband_is_subtracted_rather_than_stepped_over() -> void:
	# The difference matters at the boundary. Returning the raw error the moment
	# it clears the deadband steps the brake torque from nothing to 260 N.m in
	# one tick, which is a controller that hunts.
	check_approx(
		TractionControl.yaw_error_rad_s(0.5, 0.0, INF),
		0.5 - DOC_YAW_DEADBAND_RAD_S,
		"the correction starts from zero at the edge of the band"
	)
	check_approx(
		TractionControl.yaw_error_rad_s(-0.5, 0.0, INF),
		-(0.5 - DOC_YAW_DEADBAND_RAD_S),
		"and it is symmetric"
	)


func test_a_target_past_the_grip_limit_is_clamped_before_the_error_is_taken() -> void:
	# Otherwise the controller chases a corner the Assembly was never going to
	# make, and brakes the inside flank all the way into the wall.
	check_approx(
		TractionControl.yaw_error_rad_s(0.0, -9.0, 1.0),
		1.0 - DOC_YAW_DEADBAND_RAD_S,
		"a 9 rad/s target on a 1 rad/s grip limit is a 1 rad/s target"
	)


func test_the_corrective_brake_goes_on_the_flank_that_opposes_the_error() -> void:
	# A rearward force on the left flank yaws the Assembly left, so an Assembly
	# yawing right harder than asked is corrected on the left. A controller that
	# braked the other side would add to the spin it is trimming, and no test of
	# "does it drive straight" distinguishes that from a controller that is off.
	check_eq(TractionControl.brake_side(-1.0), -1, "yawing right too fast brakes the left flank")
	check_eq(TractionControl.brake_side(1.0), 1, "and yawing left too fast brakes the right")


func test_the_brake_demand_is_proportional_to_the_error() -> void:
	check_approx(
		TractionControl.yaw_brake_nm(0.1, 100000.0, 1.0),
		0.1 * DOC_YAW_GAIN_NM_PER_RAD_S,
		"2600 N.m per rad/s, against a part brake large enough not to bind"
	)
	check_approx(
		TractionControl.yaw_brake_nm(0.1, 100000.0, 0.25),
		0.1 * DOC_YAW_GAIN_NM_PER_RAD_S * 0.25,
		"and authority scales the demand, not just the limiter"
	)
	check_approx(
		TractionControl.yaw_brake_nm(0.0, 100000.0, 1.0), 0.0, "no error, no brake"
	)


func test_the_brake_is_capped_at_a_fraction_of_the_parts_own() -> void:
	# The cap is what makes this an aid rather than an override: at a quarter it may
	# bias an Assembly's yaw and may not stop it, so a driver who wants to stop
	# still has to use the brake. Uncapped, a large error locks the patch
	# outright — and a locked patch spends its whole friction circle
	# longitudinally and has none left to resist the spin the aid is correcting,
	# which is why the fraction came down from 0.55 to 0.25 this session.
	var part_brake := 1800.0
	check_approx(
		TractionControl.yaw_brake_nm(50.0, part_brake, 1.0),
		part_brake * DOC_MAX_BRAKE_FRACTION,
		"an absurd error still only ever gets a quarter of the part's brake"
	)
	check_true(
		TractionControl.yaw_brake_nm(50.0, part_brake, 1.0) < part_brake,
		"which is strictly less than locking it"
	)


func test_the_brake_demand_does_not_care_which_way_the_error_points() -> void:
	# The side is chosen by brake_side; the magnitude is a magnitude. A signed
	# torque here would cancel the flank choice and drive one wheel forwards.
	check_approx(
		TractionControl.yaw_brake_nm(-0.3, 100000.0, 1.0),
		TractionControl.yaw_brake_nm(0.3, 100000.0, 1.0),
		"the same error either way asks for the same brake"
	)
