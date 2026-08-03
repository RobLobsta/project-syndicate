extends TestCase
## [AiDriver]'s tactic — doc 05 §15.7.1 and §15.7.2.
##
## The statics only. What the driver does with a clock, a registry and a body is
## [code]tests/physics/test_ai_engagement.gd[/code]'s subject; what it computes
## from a bearing is here, because the arithmetic is the whole tactic and a
## bearing is three floats.
##
## [b]Every assertion here is a direction or a value, never a magnitude alone.[/b]
## §9's oldest lesson in this repository is that a sign defect survives any test
## that asserts a demand was produced: an Assembly steered away from its target
## turns just as hard as one steered toward it, and only the sign tells them
## apart.

## Doc 05 §15.7.1, by value. Written out by hand rather than imported.
const STEER_SATURATION_RAD: float = 0.35
const AMBULATORY_TURN_SATURATION_RAD: float = 0.60
const AMBULATORY_YAW_DAMPING: float = 0.55
const AMBULATORY_STEER_AUTHORITY: float = 0.5
const GROUND_STAND_OFF_M: float = 6.0
const AMBULATORY_STAND_OFF_M: float = 20.0
const ROTARY_STAND_OFF_M: float = 22.0

## An Assembly at the origin facing doc 07 §7.2's forward, which is [code]-Z[/code].
const FACING_FORWARD := Basis.IDENTITY


## ===== §15.7.1's BEARING ===============================================


## Straight ahead is zero error, and this is the assertion every other one here
## rests on: if the reference direction were wrong, every demand below would be
## wrong by the same constant and the pair of them would still look symmetrical.
func test_a_target_dead_ahead_is_a_zero_bearing() -> void:
	check_approx(
		AiDriver.bearing_to(FACING_FORWARD, Vector3(0.0, 0.0, -50.0)),
		0.0,
		"forward is -Z"
	)


## A quarter turn each way, by value. Positive is a left-hand bearing under
## [method Vector3.signed_angle_to] about the world up, which is what makes the
## negation in [method AiDriver.steer_demand] a rule rather than a taste.
func test_a_target_to_each_side_is_a_quarter_turn_of_bearing() -> void:
	check_approx(
		AiDriver.bearing_to(FACING_FORWARD, Vector3(-30.0, 0.0, 0.0)),
		PI * 0.5,
		"a target to the left"
	)
	check_approx(
		AiDriver.bearing_to(FACING_FORWARD, Vector3(30.0, 0.0, 0.0)),
		-PI * 0.5,
		"and one to the right"
	)


## A target up a hill is not a target to the left. Without the flattening, the
## vertical component leaks into the bearing and an Assembly on a slope steers
## at a hill rather than at an enemy — which the arena's slab could never have
## shown and doc 09's basin can.
func test_the_bearing_ignores_height() -> void:
	var level := AiDriver.bearing_to(FACING_FORWARD, Vector3(20.0, 0.0, -20.0))
	var uphill := AiDriver.bearing_to(FACING_FORWARD, Vector3(20.0, 40.0, -20.0))
	check_approx(uphill, level, "forty metres of climb changes no bearing")


## A degenerate offset produces no demand rather than a NaN. The state is real:
## it is the tick an Assembly is exactly on top of what it is chasing.
func test_a_zero_offset_is_a_zero_bearing() -> void:
	check_approx(AiDriver.bearing_to(FACING_FORWARD, Vector3.ZERO), 0.0, "nothing to steer at")


## ===== §15.7.1's STEERING ==============================================


## The rule, in both directions. Positive steer is right and a right turn is a
## negative rotation about the world up, so a target to the right — a negative
## bearing — must produce a positive demand.
func test_the_steering_demand_opposes_the_bearing_error() -> void:
	var to_the_right := AiDriver.bearing_to(FACING_FORWARD, Vector3(10.0, 0.0, -30.0))
	check_true(to_the_right < 0.0, "a target on the right is a negative bearing")
	check_true(
		AiDriver.steer_demand(to_the_right) > 0.0,
		"and steers right, which is positive"
	)

	var to_the_left := AiDriver.bearing_to(FACING_FORWARD, Vector3(-10.0, 0.0, -30.0))
	check_true(to_the_left > 0.0, "a target on the left is a positive bearing")
	check_true(
		AiDriver.steer_demand(to_the_left) < 0.0,
		"and steers left, which is negative"
	)


## The gain, by value, at half saturation — where the clamp is not yet doing any
## of the work and the division is visible.
func test_the_steering_demand_is_the_documented_gain() -> void:
	var half := STEER_SATURATION_RAD * 0.5
	check_approx(
		AiDriver.steer_demand(half), -0.5, "half the saturation error is half the demand"
	)
	check_approx(AiDriver.steer_demand(-half), 0.5, "and the same the other way")


## Saturation, asserted just inside and well outside. A demand that grew past one
## would be silently clamped by the motion layer, so a missing clamp here is
## invisible downstream — which is exactly why it is asserted here.
func test_the_steering_demand_saturates_at_the_documented_error() -> void:
	check_approx(
		AiDriver.steer_demand(-STEER_SATURATION_RAD), 1.0, "at saturation, full demand"
	)
	check_approx(AiDriver.steer_demand(-PI), 1.0, "and half a turn is no more than full")
	check_approx(AiDriver.steer_demand(PI), -1.0, "in both directions")


## ===== §15.7.2's AMBULATORY RATE COMMAND ===============================


## The family's demand carries the same sign rule, and it must: the two go
## through the same [member ControlInput.steer] field.
func test_the_ambulatory_demand_opposes_the_bearing_too() -> void:
	check_true(
		AiDriver.ambulatory_steer_demand(-0.3, 0.0) > 0.0, "a target on the right"
	)
	check_true(
		AiDriver.ambulatory_steer_demand(0.3, 0.0) < 0.0, "and one on the left"
	)


## The authority ceiling, by value. §15.7.2: below one because §13.5 spends the
## same number on the lateral half of the desired velocity, and a saturated
## demand walks the Assembly 45° off its own nose.
func test_the_ambulatory_demand_is_capped_below_full_authority() -> void:
	check_approx(
		AiDriver.ambulatory_steer_demand(-PI, 0.0),
		AMBULATORY_STEER_AUTHORITY,
		"half a turn of error still asks for only half authority"
	)
	check_approx(
		AiDriver.ambulatory_steer_demand(PI, 0.0),
		-AMBULATORY_STEER_AUTHORITY,
		"and the same the other way"
	)


## The gain before the ceiling, at half the family's saturation.
func test_the_ambulatory_gain_is_the_documented_one() -> void:
	var half := AMBULATORY_TURN_SATURATION_RAD * 0.5
	check_approx(
		AiDriver.ambulatory_steer_demand(half, 0.0),
		-0.5 * AMBULATORY_STEER_AUTHORITY,
		"half the saturation error, half the demand, half the authority"
	)


## The damping term, which is what §15.7.2 exists for: a hull already turning
## right must be asked to turn right [i]less[/i], or it exceeds the ~30°/s its
## own mount can track and spends the fight one step behind its target.
##
## Asserted as a difference against the undamped demand rather than as a value,
## because the sign of the damper is the thing that can be wrong and a value
## assertion passes against a damper that reinforces the turn by the same amount.
func test_the_ambulatory_damper_opposes_the_hull_yaw() -> void:
	var bearing := -0.2
	var undamped := AiDriver.ambulatory_steer_demand(bearing, 0.0)
	var turning_right := AiDriver.ambulatory_steer_demand(bearing, -1.0)
	var turning_left := AiDriver.ambulatory_steer_demand(bearing, 1.0)
	check_true(
		turning_right < undamped,
		"already yawing right, ask for less right: %.3f against %.3f"
		% [turning_right, undamped]
	)
	check_true(
		turning_left > undamped,
		"already yawing left, ask for more right: %.3f against %.3f"
		% [turning_left, undamped]
	)
	check_approx(
		turning_left - undamped,
		AMBULATORY_YAW_DAMPING * AMBULATORY_STEER_AUTHORITY,
		"and the step is the documented gain, through the authority ceiling"
	)


## A hull yawing hard enough saturates on the damper alone, with no heading error
## at all. That is the state the term is for and it must reach full opposition.
func test_a_fast_yaw_saturates_the_damper_by_itself() -> void:
	check_approx(
		AiDriver.ambulatory_steer_demand(0.0, 10.0),
		AMBULATORY_STEER_AUTHORITY,
		"a hull spinning left asks for all the right it has"
	)


## ===== THE STAND-OFFS ==================================================


## Per family, by value, and the ambulatory one is longer for §15.7.2's reason:
## the family is the steadiest mount in the game standing still and the worst
## walking, so it plants and shoots rather than closing.
func test_each_family_fights_at_its_documented_stand_off() -> void:
	check_approx(
		AiDriver.default_stand_off_m(PartEnums.LocomotionMode.GROUND),
		GROUND_STAND_OFF_M,
		"wheeled closes to six metres"
	)
	check_approx(
		AiDriver.default_stand_off_m(PartEnums.LocomotionMode.TRACKED),
		GROUND_STAND_OFF_M,
		"and tracked fights at the same range"
	)
	check_approx(
		AiDriver.default_stand_off_m(PartEnums.LocomotionMode.AMBULATORY),
		AMBULATORY_STAND_OFF_M,
		"an ambulatory build plants further out"
	)
	check_approx(
		AiDriver.default_stand_off_m(PartEnums.LocomotionMode.ROTARY),
		ROTARY_STAND_OFF_M,
		"and a rotary one holds station further out still"
	)
