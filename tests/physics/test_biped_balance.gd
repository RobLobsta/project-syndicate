extends TestCase
## A two-limbed Assembly stands up, and doc 05 §13.10 and §13.11 are why.
##
## [b]This is the file that says the biped is real.[/b] Before §13.10 a limb was
## a spring-damper force along the hip-to-foot line acting through a
## dimensionless foot, so the only pitch stability a walking Assembly had was the
## fore-and-aft separation of its feet — and two feet side by side have a
## separation of zero. `CombatArena.Recipe.BIPED` on the old model is a machine
## that pitches over on its first tick, every time, with nothing to stop it.
##
## Two terms changed that and this file asserts them from opposite ends:
##
## [enum]
## [*] [b]§13.10, the ankle.[/b] `mot.limb.strider.t4` authors a 0.60 × 0.34 m
##     support polygon, the centre of pressure may move inside it, and the
##     resulting torque is bounded by `N × half-extent`. That bound is the
##     model: a foot in the air can do nothing, and there is no configuration in
##     which the term produces energy.
## [*] [b]§13.11, the capture point.[/b] The plant target's correction term is
##     `(v − v_desired) · sqrt(h/g)` rather than an authored gain, so it carries
##     the [i]sign[/i] of the demand. §13.9 records the ambulatory family as
##     unable to reverse at all — 0.01 m over three seconds — because the old
##     correction could scale a disturbance and never create one.
## [/enum]
##
## Every assertion here is a direction or a band and never a tick count, because
## two Assemblies never share this arena and one on a slab reproduces exactly
## (LEARNED_FACTS.md §1 fact 44). The fixture is destructive in the sense fact 43
## describes — a settled stance is a state, not a pure function — so each phase
## opens its own arena and closes it the moment it has its measurement (fact 48).

## Ticks the biped is given to fall onto its feet and settle.
const SETTLE_TICKS: int = 300

## Ticks a demand is held for.
const DRIVE_TICKS: int = 240

## Degrees of tilt within which the machine counts as standing.
##
## Ten, and the figure is derived rather than chosen. A rigid body on a support
## polygon is statically stable while its centre of mass projects inside that
## polygon, so the tilt this build can hold is `asin(foot_length / 2h)` — 0.60 m
## of foot under a centre of mass about 2.8 m up is about 6°. Ten leaves room for
## the settle's own transient and is still far below the angle at which the ankle
## saturates and the machine is committed to falling.
const UPRIGHT_LIMIT_DEG: float = 10.0

## Metres the machine may drift from where it was put down while standing still.
## It is balancing rather than bolted down, so this is not zero — but a metre of
## wander in five seconds is a machine walking away from its own spawn.
const STANDING_DRIFT_LIMIT_M: float = 1.0

## Metres a commanded run must cover, and metres a commanded reverse must cover
## in the opposite direction.
##
## [b]The reverse figure is the one that matters.[/b] Doc 05 §13.9 measures the
## shipped ambulatory family at 0.01 m of reverse over three seconds and asserts
## it as a defect in `tests/physics/test_braking_and_reverse.gd`. Anything above
## noise here is §13.11 doing the thing the old placement law could not.
const TRAVEL_MIN_M: float = 1.5
const REVERSE_MIN_M: float = 0.75

var _arena: CombatArena = null

var _settled_tilt_deg: float = -1.0
var _settled_drift_m: float = -1.0
var _forward_m: float = 0.0
var _reverse_m: float = 0.0
var _ran: bool = false


func after_all() -> void:
	_close()


## The whole of §13.10's claim: two feet, no fore-aft base, and it stands anyway.
func test_a_two_limbed_assembly_settles_upright() -> void:
	await _run()
	check_true(
		_settled_tilt_deg >= 0.0 and _settled_tilt_deg < UPRIGHT_LIMIT_DEG,
		(
			"a biped settles at %.1f° of tilt, inside the %.0f° its own support "
			+ "polygon can hold"
		) % [_settled_tilt_deg, UPRIGHT_LIMIT_DEG]
	)


## Standing is standing, not a slow topple that happens to still be upright when
## the window closes. A machine falling at 0.2 m/s is upright for a long time.
func test_it_stands_where_it_was_put_rather_than_walking_off() -> void:
	await _run()
	check_true(
		_settled_drift_m >= 0.0 and _settled_drift_m < STANDING_DRIFT_LIMIT_M,
		"and it is still within %.2f m of where it was put down" % _settled_drift_m
	)


func test_a_travel_demand_walks_it_forward() -> void:
	await _run()
	check_true(
		_forward_m > TRAVEL_MIN_M,
		"a full throttle carries the biped %.2f m forward" % _forward_m
	)


## §13.11's sign, and the reason the term replaced an authored gain rather than
## joining it. Asserted as a *direction* against the forward run rather than as a
## distance alone, because a machine that fell over backwards also moves backwards.
func test_a_negative_demand_walks_it_backward() -> void:
	await _run()
	check_true(
		_reverse_m > REVERSE_MIN_M,
		(
			"and a negative throttle carries it %.2f m the other way, where doc 05 "
			+ "§13.9 measures the four-limbed family at 0.01 m"
		) % _reverse_m
	)
	check_true(
		_forward_m > 0.0 and _reverse_m > 0.0,
		"both demands moved it, and they moved it opposite ways"
	)


## Runs once and prints the report, which is most of what this file is for.
func _run() -> void:
	if _ran:
		return
	_ran = true

	# Phase one: put it down and leave it alone.
	_arena = CombatArena.new()
	_arena.open()
	var c := _arena.spawn(CombatArena.Recipe.BIPED, 0, Vector2.ZERO, 0.0, 0)
	var start := c.runtime.body.global_position
	await _arena.settle(SETTLE_TICKS)
	_settled_tilt_deg = _tilt_deg(c)
	var here := c.runtime.body.global_position
	_settled_drift_m = Vector2(here.x - start.x, here.z - start.z).length()
	print(
		"      biped: %.0f kg, settled %.1f° tilt, %.2f m of drift, body y %.2f"
		% [c.runtime.body.mass, _settled_tilt_deg, _settled_drift_m, here.y]
	)
	_close()

	_forward_m = await _travelled(1.0)
	_reverse_m = await _travelled(-1.0)
	print(
		"      biped: %.2f m forward on a full demand, %.2f m back on a negative one"
		% [_forward_m, _reverse_m]
	)


## Distance covered along the Assembly's own forward axis under [param throttle].
##
## Measured along the hull's heading rather than along world `-Z`, so a machine
## that has yawed during the run still reports the distance it actually travelled
## rather than the projection of it.
func _travelled(throttle: float) -> float:
	_arena = CombatArena.new()
	_arena.open()
	var c := _arena.spawn(CombatArena.Recipe.BIPED, 0, Vector2.ZERO, 0.0, 0)
	await _arena.settle(SETTLE_TICKS)

	var from := c.runtime.body.global_position
	var heading := -c.runtime.body.global_basis.z

	# [b]Stepped through [method CombatArena.step_once], and neither of the other
	# two helpers would do.[/b] `settle` zeroes throttle and steer before it steps
	# and `tick_once` overwrites them with the pilot's decisions, so a demand
	# written before either is gone by the first tick. The symptom is two runs
	# reporting byte-identical displacement for opposite throttles, which reads
	# exactly like a locomotion family ignoring its own input and is a fixture
	# holding the input wrong.
	for i: int in DRIVE_TICKS:
		c.motion.input.throttle = throttle
		await _arena.step_once()
	c.motion.input.throttle = 0.0

	var delta := c.runtime.body.global_position - from
	var flat := Vector3(delta.x, 0.0, delta.z)
	var along := flat.dot(Vector3(heading.x, 0.0, heading.z).normalized())
	_close()
	return along * signf(throttle)


func _tilt_deg(c: CombatArena.Combatant) -> float:
	var up := c.runtime.body.global_basis.y
	return rad_to_deg(up.angle_to(Vector3.UP))


func _close() -> void:
	if _arena != null:
		_arena.close()
		_arena = null
