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
const GROUND_STAND_OFF_M: float = 20.0
const AMBULATORY_STAND_OFF_M: float = 20.0
const ROTARY_STAND_OFF_M: float = 22.0
const ARRIVAL_DECEL_MPS2: float = 6.0
const ARRIVAL_CLOSURE_DEADBAND_MPS: float = 0.5

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
		"wheeled closes to twenty metres"
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


## ===== §15.7.1's ARRIVAL BRAKE =========================================
## The law that stopped the shipped match opening with the player being driven
## over. Every assertion here is a value or a direction against the constants
## written out at the top of this file — never a call to the code under test
## with different arguments, which asserts only that it is self-consistent.


## The far half of the profile. A driver crossing open ground toward something
## thirty metres away is not arriving at it, and a law that braked there would
## be a law that never got anywhere.
func test_a_driver_with_room_to_stop_does_not_brake() -> void:
	check_approx(
		AiDriver.arrival_brake(40.0, GROUND_STAND_OFF_M, 12.0),
		0.0,
		"thirty metres of slack absorbs twelve metres a second"
	)


## The near half, and the one case that is a ram rather than an arrival: inside
## the stand-off and still coming on. Nothing about the closure's magnitude can
## make that a demand for less than everything.
func test_a_driver_inside_its_stand_off_and_still_closing_brakes_fully() -> void:
	check_approx(
		AiDriver.arrival_brake(GROUND_STAND_OFF_M - 1.0, GROUND_STAND_OFF_M, 1.0),
		1.0,
		"past the stand-off, full brake"
	)
	check_approx(
		AiDriver.arrival_brake(GROUND_STAND_OFF_M, GROUND_STAND_OFF_M, 8.0),
		1.0,
		"and exactly on it, where the slack is zero rather than negative"
	)


## The band between them, by value. `v² / 2s` is the deceleration the slack
## requires; the demand is zero where that equals the planned figure and full
## where it is twice it.
##
## Both ends are asserted, because a law that saturated immediately and one that
## never saturated would each pass a single reading taken in the middle.
func test_the_demand_spans_one_planned_deceleration_to_two() -> void:
	# 6 m/s into 3 m of slack needs 36 / 6 = 6.0 m/s², exactly the plan.
	check_approx(
		AiDriver.arrival_brake(GROUND_STAND_OFF_M + 3.0, GROUND_STAND_OFF_M, 6.0),
		0.0,
		"at the planned deceleration the driver is still coasting"
	)
	# 6 m/s into 1.5 m needs 36 / 3 = 12.0 m/s², twice the plan.
	check_approx(
		AiDriver.arrival_brake(GROUND_STAND_OFF_M + 1.5, GROUND_STAND_OFF_M, 6.0),
		1.0,
		"at twice it, everything the build has"
	)
	# 36 / 4.5 = 8.0 m/s², a third of the way from one plan to two.
	check_approx(
		AiDriver.arrival_brake(GROUND_STAND_OFF_M + 2.25, GROUND_STAND_OFF_M, 6.0),
		1.0 / 3.0,
		"and a third of the way across the band is a third of the demand",
		1e-4
	)


## A closure at or under the deadband is not an arrival. Without this a driver
## parked on its mark stands on the brakes for the whole match, because its own
## hull settling reads as closing.
func test_a_closure_under_the_deadband_is_not_an_arrival() -> void:
	check_approx(
		AiDriver.arrival_brake(
			GROUND_STAND_OFF_M - 2.0, GROUND_STAND_OFF_M, ARRIVAL_CLOSURE_DEADBAND_MPS
		),
		0.0,
		"at the deadband exactly, nothing — even from inside the stand-off"
	)
	check_true(
		AiDriver.arrival_brake(
			GROUND_STAND_OFF_M - 2.0,
			GROUND_STAND_OFF_M,
			ARRIVAL_CLOSURE_DEADBAND_MPS + 0.01
		) > 0.0,
		"and a hair over it, everything"
	)


## Opening the range is never an arrival, in either sense. A driver reversing out
## of a stand-off it overshot must not be braking against its own escape.
func test_a_driver_opening_the_range_never_brakes() -> void:
	check_approx(
		AiDriver.arrival_brake(GROUND_STAND_OFF_M + 1.0, GROUND_STAND_OFF_M, -8.0),
		0.0,
		"backing off fast, no brake"
	)
	check_approx(
		AiDriver.arrival_brake(GROUND_STAND_OFF_M - 3.0, GROUND_STAND_OFF_M, -2.0),
		0.0,
		"and backing out of the stand-off it is already inside"
	)


## §15.7.1's closure is a projection onto the bearing, not a speed, and the sign
## is the rule. A driver crossing in front of its target is closing at nothing,
## and one driving away is closing at a negative rate — both of which the brake
## above depends on to stay out of the way.
func test_the_closure_is_the_component_along_the_bearing() -> void:
	var to_the_north := Vector3(0.0, 0.0, -10.0)
	check_approx(
		AiDriver.closure_mps(Vector3(0.0, 0.0, -6.0), to_the_north),
		6.0,
		"straight at it is the whole speed"
	)
	check_approx(
		AiDriver.closure_mps(Vector3(0.0, 0.0, 6.0), to_the_north),
		-6.0,
		"and straight away from it is the negation"
	)
	check_approx(
		AiDriver.closure_mps(Vector3(6.0, 0.0, 0.0), to_the_north),
		0.0,
		"across it is no closure at all"
	)


## Height is not closure. §15.7.1 flattens every bearing it takes, and a target
## at the bottom of a hill would otherwise read as one being closed on at the
## Assembly's whole rate of descent.
func test_the_closure_ignores_height() -> void:
	check_approx(
		AiDriver.closure_mps(Vector3(0.0, -9.0, 0.0), Vector3(0.0, -20.0, -10.0)),
		0.0,
		"falling toward a target below is not closing on it"
	)


## ===== §15.7.5's STAND-OFF LADDER ======================================
## Doc 05 §15.7.5, by value. Written out by hand.

const ALLY_STAND_OFF_STEP_M: float = 4.5
const ALLY_STAND_OFF_MAX_STEPS: int = 3


## The rung a driver with the field to itself stands on. If this moved, every
## engagement in the project would move with it and nothing else here would say
## so.
func test_a_driver_with_no_friends_keeps_its_family_stand_off() -> void:
	check_approx(
		AiDriver.laddered_stand_off_m(GROUND_STAND_OFF_M, 0),
		GROUND_STAND_OFF_M,
		"nobody closer means the base range"
	)


## One step per friend, by value rather than by "it went up". A ladder with the
## wrong step still increases.
func test_each_closer_friend_adds_one_documented_step() -> void:
	check_approx(
		AiDriver.laddered_stand_off_m(GROUND_STAND_OFF_M, 1),
		GROUND_STAND_OFF_M + ALLY_STAND_OFF_STEP_M,
		"one friend closer is one step out"
	)
	check_approx(
		AiDriver.laddered_stand_off_m(GROUND_STAND_OFF_M, 2),
		GROUND_STAND_OFF_M + 2.0 * ALLY_STAND_OFF_STEP_M,
		"two friends closer is two steps out"
	)


## The cap, asserted at the rung above it as well as at it. A clamp written as
## `if steps == MAX` passes at the boundary and fails one past it.
func test_the_ladder_stops_at_the_documented_cap() -> void:
	var capped := GROUND_STAND_OFF_M + float(ALLY_STAND_OFF_MAX_STEPS) * ALLY_STAND_OFF_STEP_M
	check_approx(
		AiDriver.laddered_stand_off_m(GROUND_STAND_OFF_M, ALLY_STAND_OFF_MAX_STEPS),
		capped,
		"the last rung is the documented one"
	)
	check_approx(
		AiDriver.laddered_stand_off_m(GROUND_STAND_OFF_M, ALLY_STAND_OFF_MAX_STEPS + 4),
		capped,
		"and a fourth friend does not push it further out"
	)


## The ladder is a spacing rule, not a family rule: it takes whatever base it is
## given, so an ambulatory driver's twenty metres ladders the same way.
func test_the_ladder_applies_to_any_family_stand_off() -> void:
	check_approx(
		AiDriver.laddered_stand_off_m(AMBULATORY_STAND_OFF_M, 1),
		AMBULATORY_STAND_OFF_M + ALLY_STAND_OFF_STEP_M,
		"the base is the argument, not a constant inside the rule"
	)


## The predicate the whole arrangement rests on: friends *nearer the target than
## I am*, and nothing else. Three drivers strung out along the approach must
## produce three different counts, or they all stop at the same range and the
## ladder has done nothing.
func test_only_friends_nearer_the_target_are_counted() -> void:
	var target := _handle(1, 1, Vector3(0.0, 0.0, 0.0))
	# Own side, at 10, 20 and 30 m from the target on one line.
	var near := _handle(2, 0, Vector3(0.0, 0.0, 10.0))
	var mid := _handle(3, 0, Vector3(0.0, 0.0, 20.0))
	var far := _handle(4, 0, Vector3(0.0, 0.0, 30.0))

	check_eq(
		AiDriver.closer_allies(_context_at(0, near.position, [target, mid, far]), target),
		0,
		"the nearest of three has nobody in front of it"
	)
	check_eq(
		AiDriver.closer_allies(_context_at(0, mid.position, [target, near, far]), target),
		1,
		"the middle one has one"
	)
	check_eq(
		AiDriver.closer_allies(_context_at(0, far.position, [target, near, mid]), target),
		2,
		"and the furthest has two"
	)


## The target is on the other side, so counting "everyone nearer" rather than
## "everyone nearer on my side" would push every driver out one extra rung and
## would do it invisibly, because the ladder would still be a ladder.
func test_the_target_s_own_side_is_not_counted_as_friends() -> void:
	var target := _handle(1, 1, Vector3.ZERO)
	var enemy_escort := _handle(5, 1, Vector3(0.0, 0.0, 4.0))
	var me := Vector3(0.0, 0.0, 20.0)
	check_eq(
		AiDriver.closer_allies(_context_at(0, me, [target, enemy_escort]), target),
		0,
		"an opponent standing between me and my target is not a friend"
	)


## Two Assemblies abreast share a rung. Doc 05 §15.7.5 says ties are not broken,
## and the alternative — a strict inequality that answered differently depending
## on which of two identical ranges was compared first — would make the ladder
## depend on registry order.
func test_two_friends_at_equal_range_share_a_rung() -> void:
	var target := _handle(1, 1, Vector3.ZERO)
	var abreast := _handle(2, 0, Vector3(6.0, 0.0, 8.0))
	var me := Vector3(-6.0, 0.0, 8.0)
	check_eq(
		AiDriver.closer_allies(_context_at(0, me, [target, abreast]), target),
		0,
		"neither of two Assemblies abreast is in front of the other"
	)


## A driver with no scan behind it must not ladder off a null record.
func test_a_missing_context_or_target_counts_nothing() -> void:
	var target := _handle(1, 1, Vector3.ZERO)
	check_eq(AiDriver.closer_allies(null, target), 0, "no context, no friends")
	check_eq(
		AiDriver.closer_allies(_context_at(0, Vector3.ZERO, []), null),
		0,
		"no target, nothing to be nearer than"
	)


func _handle(id: int, team: int, position: Vector3) -> AiContext.TargetHandle:
	var handle := AiContext.TargetHandle.new()
	handle.id = id
	handle.team = team
	handle.position = position
	return handle


func _context_at(
	team: int, position: Vector3, candidates: Array[AiContext.TargetHandle]
) -> AiContext:
	var context := AiContext.new()
	context.team = team
	context.position = position
	context.visible_assemblies = candidates
	return context
