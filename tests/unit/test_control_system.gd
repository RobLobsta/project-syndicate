extends TestCase
## The action-to-intent mapping of [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §15,
## driven through the real input map.
##
## Actions are pressed with [method Input.action_press] rather than by
## constructing [InputEvent]s, which is the same path a device takes once the
## input map has resolved it — and it is what makes this a test of the mapping
## rather than a test of Godot's event routing.
##
## The signs are the whole of this file. Every field here is read by a solver
## that will happily integrate the wrong one: a reversed steer axis drives an
## Assembly into the wall it was steering away from, and §15.4's cyclic
## inversion is invisible to anything that does not compose the mapping with
## §12.3's rotation order. Which is why the two cyclic tests do exactly that.

## Deflection the cyclic composition is taken at, in degrees. Any non-zero angle
## inside a swashplate's cone does; twelve is the shipped disc's limit.
const CYCLIC_LIMIT_DEG: float = 12.0

## A partial pull, to check the analogue path carries a magnitude rather than a
## boolean. Deliberately not 0.5 — a mapping that returned a half for anything
## pressed would pass against that.
const PART_PULL: float = 0.4

var _input: ControlInput = null
var _system: ControlSystem = null


func before_all() -> void:
	_input = ControlInput.new()
	_system = ControlSystem.new()
	_system.input = _input
	# A TestCase is a RefCounted and has no tree of its own; the bus has one.
	EventBus.get_tree().root.add_child(_system)


func after_all() -> void:
	_release_all()
	if is_instance_valid(_system):
		_system.queue_free()


## ===== THE GROUND AXES =================================================


func test_throttle_comes_off_the_throttle_action() -> void:
	_release_all()
	_press(ControlSystem.ACTION_THROTTLE, 1.0)
	_system.sample()
	check_approx(_input.throttle, 1.0, "a held throttle is full drive demand")
	check_approx(_input.brake, 0.0, "and asks for no brake")


func test_the_analogue_path_carries_a_magnitude() -> void:
	_release_all()
	_press(ControlSystem.ACTION_THROTTLE, PART_PULL)
	_system.sample()
	check_approx(
		_input.throttle, PART_PULL, "a trigger at 0.4 is 0.4, not 'pressed'"
	)


func test_the_brake_action_is_both_the_brake_and_reverse() -> void:
	_release_all()
	# §15.5. Above a walking pace §7.2's brake term dominates and the Assembly
	# slows; at rest the negative drive torque backs it out, and the zero-crossing
	# guard is what stops the brake itself reversing anything. One subtraction,
	# no reverse *state*, and nothing here needs to know the Assembly's speed.
	_press(ControlSystem.ACTION_BRAKE, 1.0)
	_system.sample()
	check_approx(_input.brake, 1.0, "the brake is the brake")
	check_approx(_input.throttle, -1.0, "and it is also the reverse demand")


func test_throttle_and_brake_together_cancel_the_drive_and_keep_the_brake() -> void:
	_release_all()
	_press(ControlSystem.ACTION_THROTTLE, 1.0)
	_press(ControlSystem.ACTION_BRAKE, 1.0)
	_system.sample()
	check_approx(_input.throttle, 0.0, "opposed drive demands cancel")
	check_approx(_input.brake, 1.0, "and the brake is not one of the two being opposed")


func test_positive_steer_is_right() -> void:
	_release_all()
	# Doc 11 §7.2 fixes this for every input device, and §7.0 negates it again
	# when it rotates the contact frame. Getting it wrong at either end steers
	# the wrong way; getting it wrong at both is a bug that hides itself.
	_press(ControlSystem.ACTION_STEER_RIGHT, 1.0)
	_system.sample()
	check_approx(_input.steer, 1.0, "steer right is positive")

	_release_all()
	_press(ControlSystem.ACTION_STEER_LEFT, 1.0)
	_system.sample()
	check_approx(_input.steer, -1.0, "and steer left is negative")


func test_a_neutral_sample_is_neutral() -> void:
	_release_all()
	_press(ControlSystem.ACTION_THROTTLE, 1.0)
	_system.sample()
	_release_all()
	_system.sample()
	check_true(_input.is_neutral(), "releasing everything asks for no motion at all")
	check_approx(_input.brake, 0.0, "and no brake")


## ===== ONE AXIS, SEVERAL FAMILIES ======================================


func test_the_drive_axis_is_also_the_collective() -> void:
	_release_all()
	# §15.3. Holding throttle spools the disc and pitches it to climb; holding
	# the brake action pitches it the other way and descends under power. A
	# rotary Assembly needs no second control scheme to be flyable.
	_press(ControlSystem.ACTION_THROTTLE, 1.0)
	_system.sample()
	check_approx(_input.collective, _input.throttle, "climb is the drive axis")

	_release_all()
	_press(ControlSystem.ACTION_BRAKE, 1.0)
	_system.sample()
	check_approx(_input.collective, -1.0, "and the brake action is descend")


func test_the_steer_axis_is_also_the_pedals() -> void:
	_release_all()
	_press(ControlSystem.ACTION_STEER_RIGHT, 1.0)
	_system.sample()
	check_approx(_input.yaw, _input.steer, "§12.4's yaw authority is the steer axis")


## ===== CYCLIC (§15.4) ==================================================


func test_pitching_forward_tilts_the_thrust_vector_forward() -> void:
	_release_all()
	# The composition, not the sign in isolation. §12.3 rotates the disc axis
	# about +X by cyclic.x, and under that order a *positive* x carries the
	# thrust toward +Z, which is backwards — so the mapping inverts and the only
	# assertion that catches a mistake at either end is what the disc does.
	_press(ControlSystem.ACTION_PITCH_FORWARD, 1.0)
	_system.sample()
	var thrust := RotorSolver.thrust_direction(
		0, _input.cyclic * CYCLIC_LIMIT_DEG, CYCLIC_LIMIT_DEG
	)
	check_true(
		thrust.z < 0.0,
		"a forward pitch demand points the thrust vector at -Z, which is forward"
	)
	check_true(absf(thrust.x) < 0.01, "and does not roll it")

	_release_all()
	_press(ControlSystem.ACTION_PITCH_BACK, 1.0)
	_system.sample()
	check_true(
		RotorSolver.thrust_direction(0, _input.cyclic * CYCLIC_LIMIT_DEG, CYCLIC_LIMIT_DEG).z
		> 0.0,
		"and a back pitch demand points it the other way"
	)


func test_rolling_right_tilts_the_thrust_vector_right() -> void:
	_release_all()
	_press(ControlSystem.ACTION_ROLL_RIGHT, 1.0)
	_system.sample()
	var thrust := RotorSolver.thrust_direction(
		0, _input.cyclic * CYCLIC_LIMIT_DEG, CYCLIC_LIMIT_DEG
	)
	check_true(thrust.x > 0.0, "a right roll demand points the thrust vector at +X")
	check_true(absf(thrust.z) < 0.01, "and does not pitch it")

	_release_all()
	_press(ControlSystem.ACTION_ROLL_LEFT, 1.0)
	_system.sample()
	check_true(
		RotorSolver.thrust_direction(0, _input.cyclic * CYCLIC_LIMIT_DEG, CYCLIC_LIMIT_DEG).x
		< 0.0,
		"and a left roll demand points it the other way"
	)


func test_the_tilt_axes_are_independent_of_the_steer_axis() -> void:
	_release_all()
	# A rotary Assembly rolls and yaws with different controls, which is the
	# reason §7.1 gained four actions rather than reusing the steer pair.
	_press(ControlSystem.ACTION_ROLL_RIGHT, 1.0)
	_system.sample()
	check_approx(_input.yaw, 0.0, "rolling is not yawing")

	_release_all()
	_press(ControlSystem.ACTION_STEER_RIGHT, 1.0)
	_system.sample()
	check_true(_input.cyclic.is_zero_approx(), "and yawing is not rolling")


## ===== THE REST OF THE RECORD ==========================================


func test_the_held_buttons_are_carried() -> void:
	_release_all()
	_press(ControlSystem.ACTION_HANDBRAKE, 1.0)
	_press(ControlSystem.ACTION_BOOST, 1.0)
	_system.sample()
	check_true(_input.handbrake, "the handbrake is held")
	check_true(_input.boost, "and so is boost")

	_release_all()
	_system.sample()
	check_false(_input.handbrake, "and released when they are not")
	check_false(_input.boost, "both of them")


func test_the_aid_authority_reaches_the_record_and_is_bounded() -> void:
	_release_all()
	# §15.6: a setting rather than an intent, which is why it is not an action.
	# Bounded here because §7.6's limiter lerps by it and an authority above one
	# would extrapolate past the managed torque.
	_system.aid_authority = 0.5
	_system.sample()
	check_approx(_input.traction_control, 0.5, "a half is a real intermediate state")

	_system.aid_authority = 4.0
	_system.sample()
	check_approx(_input.traction_control, 1.0, "and an out-of-range setting is clamped")

	_system.aid_authority = 1.0


func test_the_clock_is_what_drives_a_sample() -> void:
	_release_all()
	# §15.1. The connection is the whole production wiring: nothing else calls
	# sample(), so a system that failed to connect would leave every family
	# reading the record's initial values forever — an Assembly that ignores its
	# controls rather than one that misreads them.
	_release_all()
	_system.sample()
	check_approx(_input.throttle, 0.0, "starting from a known state")

	_press(ControlSystem.ACTION_THROTTLE, 1.0)
	MatchClock.tick_started.emit(MatchClock.tick)
	check_approx(_input.throttle, 1.0, "a tick is what takes the sample")


## ===== FIXTURES ========================================================


func _press(action: StringName, strength: float) -> void:
	Input.action_press(action, strength)


## Releases every action this file touches. Called before each test rather than
## after, so that a test which fails part-way through cannot leave a key held
## for the next one — the runner sorts the methods and none of them may depend
## on what another did.
func _release_all() -> void:
	for action: StringName in _actions():
		Input.action_release(action)


func _actions() -> Array[StringName]:
	return [
		ControlSystem.ACTION_THROTTLE,
		ControlSystem.ACTION_BRAKE,
		ControlSystem.ACTION_STEER_LEFT,
		ControlSystem.ACTION_STEER_RIGHT,
		ControlSystem.ACTION_HANDBRAKE,
		ControlSystem.ACTION_BOOST,
		ControlSystem.ACTION_PITCH_FORWARD,
		ControlSystem.ACTION_PITCH_BACK,
		ControlSystem.ACTION_ROLL_LEFT,
		ControlSystem.ACTION_ROLL_RIGHT,
	]
