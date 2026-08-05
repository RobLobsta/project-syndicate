extends TestCase
## Stopping and backing out, from [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §7.7,
## §12.8, §13.9 and §15.5.
##
## [b]Three questions a person asks in the first thirty seconds, and until this
## session the repository could answer none of them.[/b] Can I stop? Does it stay
## stopped? Can I back up? The mechanism for the first was complete and correct
## for the wheeled and tracked families and was being cancelled underneath by
## §7.4's limit cycle — `brake_sign := -signf(contact_omega)`, and that sign
## reversed on eight ticks in twelve. The other two did not exist: `handbrake` had
## a producer and no consumer, and §15.5's reverse could not work while a brake
## that finally held also held against the reverse drive coming off the same key.
##
## One Assembly at a time on a slab, so this file may assert values rather than
## only directions (LEARNED_FACTS.md §1 fact 44). Each recipe gets its own arena,
## opened and closed around its measurement (fact 45 and fact 48).

## Ticks each build is given to fall onto its contacts and settle.
const SETTLE_TICKS: int = 180
## Ticks of full throttle before the brake is applied.
const RUN_UP_TICKS: int = 240
## Ticks the brake is held for. Four seconds is well beyond any stopping distance
## measured here, so a build that has not stopped by the end has not stopped.
const BRAKE_TICKS: int = 300
## Ticks of reverse demand.
const REVERSE_TICKS: int = 180
## Ticks the parked build is left alone for.
const PARK_TICKS: int = 360

## Speed, in m/s, at or below which a build counts as stopped. A tenth of what
## `test_rest_stability.gd` used to measure a build doing with nobody touching it.
const STOPPED_MPS: float = 0.30

## Speed, in m/s, a run-up must reach for the brake measurement to mean anything.
## The fixture assertion: everything about stopping is satisfied by a build that
## never moved.
const RUN_UP_FLOOR_MPS: float = 3.0

## Metres a parked build may move over [constant PARK_TICKS] on flat ground.
const PARKED_DRIFT_M: float = 0.05

## Metres a build must travel backwards along its own nose under a reverse demand.
const REVERSE_FLOOR_M: float = 3.0

## Fraction of its walking speed an ambulatory build must be under after the same
## brake window.
##
## [b]A fraction rather than a figure, and it is deliberately not a stop.[/b] A
## walking Assembly brakes by freezing §13.4's gait with every foot planted and
## letting the hull tilt each hip-to-foot line until §13.6's axial spring opposes
## the travel. That is a real deceleration through a real friction cone and it is
## about half of a wheeled build's: measured, 1.45 m/s down to 0.65 over five
## seconds. A stance [i]shear[/i] term would close the rest and is new architecture
## in doc 05 §13; `HANDOFF.md` §3.3 carries it.
const AMBULATORY_BRAKE_FRACTION: float = 0.60

var _wheeled: Run = null
var _tracked: Run = null
var _ambulatory: Run = null
var _rotary: Run = null


## ===== THE GROUND FAMILIES =============================================


func test_a_wheeled_build_brakes_to_a_stop() -> void:
	await _measure()
	check_true(
		_wheeled.run_up_mps > RUN_UP_FLOOR_MPS,
		"the run-up reached %.2f m/s, so there is something to stop" % _wheeled.run_up_mps
	)
	check_true(
		_wheeled.stopped_mps < STOPPED_MPS,
		(
			"and the service brake took it to %.3f m/s in %.2f m"
			% [_wheeled.stopped_mps, _wheeled.stopping_distance_m]
		)
	)
	check_true(
		_wheeled.stop_ticks > 0,
		"inside the window, at tick %d of %d" % [_wheeled.stop_ticks, BRAKE_TICKS]
	)


func test_a_tracked_build_brakes_to_a_stop_and_stays_on_its_tracks() -> void:
	await _measure()
	check_true(
		_tracked.run_up_mps > RUN_UP_FLOOR_MPS,
		"the run-up reached %.2f m/s" % _tracked.run_up_mps
	)
	check_true(
		_tracked.stopped_mps < STOPPED_MPS,
		(
			"and it stopped in %.2f m at %.3f m/s"
			% [_tracked.stopping_distance_m, _tracked.stopped_mps]
		)
	)
	# §7.7's proportioning, end to end. The tracked recipe stands on a 1.42 m
	# contact base under a centre of mass a metre up, so an unproportioned brake at
	# the friction limit pitches it past ninety degrees — measured, before §7.7
	# existed, and it finished balanced on its nose. The brake is bounded by the
	# deceleration the base can take, and the base is measured against the
	# direction of travel so it shrinks as the hull pitches.
	check_true(
		_tracked.worst_upright > 0.90,
		(
			"and it never came off its tracks doing it: %.3f of upright at worst, "
			+ "against 0.00 with no proportioning"
		) % _tracked.worst_upright
	)


## §7.7. A driver demanding neither drive nor brake below a crawl has parked, and
## the Assembly stays where it was left.
func test_a_build_with_no_input_parks_itself() -> void:
	await _measure()
	check_true(_wheeled.parked, "the holding brake engaged on an empty record")
	check_true(
		_wheeled.park_drift_m < PARKED_DRIFT_M,
		"and the build moved %.3f m over %d ticks" % [_wheeled.park_drift_m, PARK_TICKS]
	)


## §15.5, and the half of it that could not work before. The brake demand is
## released as the hull comes to a stop going forwards, so the same key that shed
## the speed backs the build out.
func test_the_ground_families_reverse() -> void:
	await _measure()
	check_true(
		_wheeled.reverse_m < -REVERSE_FLOOR_M,
		"a wheeled build backs out %.2f m along its own nose" % _wheeled.reverse_m
	)
	check_true(
		_tracked.reverse_m < -REVERSE_FLOOR_M,
		"and a tracked one %.2f m" % _tracked.reverse_m
	)


## ===== THE FAMILIES THAT HAVE NO CONTACTS TO BRAKE =====================


## §13.9. `input.brake` used to reach `_apply_traction` and nothing else, so the
## two families that do not roll had no deceleration control of any kind — not
## conflated, not weak: absent.
func test_a_walking_build_can_be_asked_to_stop() -> void:
	await _measure()
	check_true(
		_ambulatory.run_up_mps > 1.0,
		"the gait carried it to %.2f m/s" % _ambulatory.run_up_mps
	)
	check_true(
		_ambulatory.stopped_mps < _ambulatory.run_up_mps * AMBULATORY_BRAKE_FRACTION,
		(
			"and a brake demand put it into §13.4's standing state and took it from "
			+ "%.3f m/s to %.3f"
		) % [_ambulatory.run_up_mps, _ambulatory.stopped_mps]
	)


## [b]Asserted as it stands, and it is the one family that cannot.[/b] A negative
## throttle reaches §13.5's placement law as a negative desired velocity, the law
## plants the foot ahead of neutral exactly as it should, and the Assembly then
## goes [b]nowhere[/b]: 0.01 m over three seconds against a wheeled build's 7.67.
##
## It is the same defect doc 05 §13.8 records for the steering demand, seen along
## the other axis. `turn_command` rotates the plant offset and nothing else, and
## the travel demand only reaches the correction term of the placement law — so
## what the gait can actually produce is bounded by how far the correction can
## move one plant, and reversing needs the whole stride to run the other way. Doc
## 05 §13 owes the family a term that carries the sign of the demand into the
## cadence and the swing, which is new architecture rather than a solver fix.
##
## Recorded here rather than left in prose because it is the check that goes red
## when somebody closes it, and the fix then is to re-measure and re-assert.
## `HANDOFF.md` §3.1.2 carries it.
func test_a_walking_build_does_not_reverse() -> void:
	await _measure()
	check_true(
		absf(_ambulatory.reverse_m) < 0.5,
		(
			"a negative throttle moves a walking Assembly %.2f m, against a wheeled "
			+ "build's %.2f — doc 05 §13.5's placement law has no reverse in it"
		) % [_ambulatory.reverse_m, _wheeled.reverse_m]
	)


## §12.8. A disc touches nothing, so its brake is a cyclic tilt against the hull's
## own horizontal velocity — the same control a player has, bounded to the same
## swashplate cone, and it stops the moment the demand does.
func test_a_rotary_build_arrests_its_horizontal_flight() -> void:
	await _measure()
	check_true(
		_rotary.run_up_mps > 1.0,
		"the disc carried it to %.2f m/s of horizontal flight" % _rotary.run_up_mps
	)
	check_true(
		_rotary.stopped_mps < _rotary.run_up_mps * 0.6,
		(
			"and a brake demand tilted the disc against it: %.2f m/s from %.2f"
			% [_rotary.stopped_mps, _rotary.run_up_mps]
		)
	)


## The convention, without an Assembly. §15.4's two inversions are the reason this
## is a solver function rather than four lines at the call site, and a sign flip
## in either of them is a brake that accelerates.
func test_the_arrest_demand_opposes_the_hull_velocity() -> void:
	var reference := RotorSolver.ARREST_REFERENCE_MPS
	# Travelling forward, which is -Z. §12.3 carries the thrust toward +Z on a
	# positive cyclic.x, and +Z is backwards, so arresting forward flight is a
	# positive x demand.
	var forward := RotorSolver.arrest_cyclic(Vector3(0.0, 0.0, -reference), 1.0, reference)
	check_true(forward.x > 0.0, "arresting forward flight tilts the thrust backwards")
	check_true(is_zero_approx(forward.y), "and asks for no roll")
	# Travelling right, which is +X. A positive cyclic.y carries the thrust toward
	# -X, which is left, so arresting rightward drift is a positive y demand.
	var rightward := RotorSolver.arrest_cyclic(Vector3(reference, 0.0, 0.0), 1.0, reference)
	check_true(rightward.y > 0.0, "arresting rightward drift tilts the thrust left")
	check_true(is_zero_approx(rightward.x), "and asks for no pitch")
	check_eq(
		RotorSolver.arrest_cyclic(Vector3(0.0, 0.0, -reference), 0.0, reference),
		Vector2.ZERO,
		"and no demand asks for nothing, so this is a brake and not an autopilot"
	)
	check_true(
		RotorSolver.arrest_cyclic(
			Vector3(0.0, 0.0, -reference * 10.0), 1.0, reference
		).length()
		<= 1.0 + SyndicateConstants.EPSILON_LINEAR,
		"and it saturates rather than demanding a swashplate angle that does not exist"
	)


## ===== THE FIXTURE =====================================================


func after_all() -> void:
	# Nothing to drain: every arena is closed the moment its record is taken
	# (LEARNED_FACTS.md §1 fact 48). This exists so that a run which failed
	# part-way through says so rather than leaking one.
	pass


func _measure() -> void:
	if _wheeled != null:
		return
	_wheeled = await _run(CombatArena.Recipe.WHEELED_LIGHT, true, "wheeled")
	_tracked = await _run(CombatArena.Recipe.TRACKED, true, "tracked")
	_ambulatory = await _run(CombatArena.Recipe.AMBULATORY, false, "ambulatory")
	_rotary = await _run(CombatArena.Recipe.ROTARY, false, "rotary")


## One build: settle, park, run up, brake, reverse. In that order, because the
## park has to be measured before anything has driven and the reverse after the
## brake has proved it can stop.
##
## [param park] is false for the two families that do not stand on braked contacts
## — §7.7 is a rule about a contact, and a disc has none.
func _run(recipe: int, park: bool, label: String) -> Run:
	var out := Run.new()
	var arena := CombatArena.new()
	arena.open()
	var c := arena.spawn(recipe, 0, Vector2.ZERO, 0.0, 0)
	# No pilot. The arena's command loop would drive this build and both demands
	# would be in the measurement.
	c.arena_piloted = false
	await arena.settle(SETTLE_TICKS)
	var body := c.runtime.body

	if park:
		var park_start := body.global_position
		await physics_frames(PARK_TICKS)
		out.parked = c.motion.holding_brake_engaged()
		out.park_drift_m = body.global_position.distance_to(park_start)

	c.motion.input.throttle = 1.0
	# A rotary build has to be flown while it runs up: it holds no hover of its
	# own (HANDOFF.md §3.7), and the arena's autopilot is the only thing in the
	# repository that does. The cyclic below is the same field §12.8's arrest adds
	# into, which is what makes the brake measurement a measurement of the brake.
	for i: int in RUN_UP_TICKS:
		if recipe == CombatArena.Recipe.ROTARY:
			arena.fly_toward(c, body.global_position - body.global_transform.basis.z * 120.0)
		await physics_frames(1)
	out.run_up_mps = _flat_speed(body)
	out.worst_upright = body.global_transform.basis.y.dot(Vector3.UP)

	c.motion.input.throttle = 0.0
	c.motion.input.cyclic = Vector2.ZERO
	c.motion.input.yaw = 0.0
	c.motion.input.brake = 1.0
	var brake_start := body.global_position
	for i: int in BRAKE_TICKS:
		if recipe == CombatArena.Recipe.ROTARY:
			arena.hold_altitude(c)
		await physics_frames(1)
		out.worst_upright = minf(
			out.worst_upright, body.global_transform.basis.y.dot(Vector3.UP)
		)
		if out.stop_ticks == 0 and _flat_speed(body) < STOPPED_MPS:
			out.stop_ticks = i + 1
	out.stopped_mps = _flat_speed(body)
	out.stopping_distance_m = body.global_position.distance_to(brake_start)

	# §15.5. On the ground families the brake demand is held as well as the
	# reverse, because that is what one key produces and it is the case that could
	# not work before: a brake that holds a contact at rest also holds it against
	# the reverse drive coming off the same key. The other two families do not
	# share that key — §12.8 and §13.9 are their own mechanisms — so they reverse
	# on the throttle alone.
	c.motion.input.throttle = -1.0
	c.motion.input.brake = 1.0 if park else 0.0
	c.motion.input.yaw = 0.0
	# The rotary family is deliberately not asked to reverse here. §15.3 maps the
	# throttle axis onto the collective, so its reverse is a cyclic pitch-back —
	# `veh_pitch_back`, which is bound and which a player has — and measuring what
	# a sustained cyclic does to the hull needs doc 05 §15.7.3's stability
	# augmentation to exist first. Without it the Assembly has no attitude control
	# at all and the measurement is of a tumble. `HANDOFF.md` §3.7.
	var reverse_start := body.global_position
	var nose := -body.global_transform.basis.z
	for i: int in REVERSE_TICKS:
		if recipe == CombatArena.Recipe.ROTARY:
			arena.hold_altitude(c)
		await physics_frames(1)
	out.reverse_m = (body.global_position - reverse_start).dot(nose)

	print(
		(
			"      %s: run-up %.2f m/s, stopped at %.3f m/s in %.2f m (tick %d), "
			+ "reverse %+.2f m, worst upright %.3f, parked %s at %.3f m"
		) % [
			label, out.run_up_mps, out.stopped_mps,
			out.stopping_distance_m, out.stop_ticks, out.reverse_m, out.worst_upright,
			str(out.parked), out.park_drift_m
		]
	)
	arena.close()
	return out


## Horizontal speed. The vertical component is a rotary build's whole flight and a
## wheeled build's suspension, and neither is what a brake is being asked about.
static func _flat_speed(body: RigidBody3D) -> float:
	var v := body.linear_velocity
	return Vector2(v.x, v.z).length()


## One build's record, taken while the fixture runs rather than in a test method:
## the runner sorts methods, and by the time a later one asks the arena is closed
## (LEARNED_FACTS.md §1 fact 42).
class Run:
	extends RefCounted
	var run_up_mps: float = 0.0
	var stopped_mps: float = 0.0
	var stopping_distance_m: float = 0.0
	var stop_ticks: int = 0
	var reverse_m: float = 0.0
	var worst_upright: float = 1.0
	var parked: bool = false
	var park_drift_m: float = 0.0
