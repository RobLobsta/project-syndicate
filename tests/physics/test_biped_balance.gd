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
## [*] [b]§13.10, the ankle.[/b] `mot.limb.broad_foot.t4` authors a 1.10 × 0.62 m
##     support polygon, the centre of pressure may move inside it, and the
##     resulting torque is bounded by `N × half-extent`. That bound is the
##     model: a foot in the air can do nothing, and there is no configuration in
##     which the term produces energy. It is a different row from the quadruped's
##     because that bound is the whole of a biped's balance and only a fraction
##     of a quadruped's — doc 01 §10.3.
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

## Ticks the turn is held for. Ten seconds, and the length is the assertion: the
## machine used to survive four of them.
const TURN_TICKS: int = 600

## Degrees of tilt within which the machine counts as standing.
##
## Ten, and the figure is derived rather than chosen. A rigid body on a support
## polygon is statically stable while its centre of mass projects inside that
## polygon, so the tilt this build can hold is `asin(foot_length / 2h)` — and on
## `mot.limb.broad_foot.t4`'s 1.10 m foot under a centre of mass 2.55 m up that is
## **12.5°**. Ten leaves room for the settle's own transient and stays inside it.
##
## [b]It was 6.8°, on the 0.60 m foot this recipe used to share with the
## quadruped, and that number is why [method test_a_sustained_turn_does_not_put_it_on_its_face]
## exists.[/b] Doc 01 §10.3 has the derivation and the two measurements.
const UPRIGHT_LIMIT_DEG: float = 10.0

## Degrees of tilt a machine under a sustained turn may reach and still be
## driving rather than falling.
##
## Measured at **13.8° worst and 9.3° at the end** over ten seconds of throttle
## 0.8 at full right lock — a banked turn, held. The bound is a little under twice
## that, which is the margin LEARNED_FACTS.md §1 fact 47 asks of a physics
## fixture, and it is nowhere near the 90° this build reached on the shared foot.
const TURN_TILT_LIMIT_DEG: float = 25.0

## Degrees a full right demand must carry the heading round inside
## [constant TURN_TICKS].
##
## Ten seconds at `mot.limb.broad_foot.t4`'s authored 45°/s is 450°; the machine
## measures about 600, because doc 05 §13.12's rate controller and §13.5's plant
## rotation both act. Asserted at 180 — well under either figure — because the
## claim this makes is "it turned, the way it was asked to, and was still turning
## at the end", and a tighter bound on an over-turn would be asserting the
## over-turn.
const TURN_MIN_DEG: float = 180.0

## Throttle held through the turn. Short of full, because a turn taken at a speed
## the gait cannot deliver is a speed error rather than a turn, and doc 05 §13.11's
## capture point answers a speed error by leaning the machine forward.
const TURN_THROTTLE: float = 0.8

## Metres the machine may drift from where it was put down while standing still.
## It is balancing rather than bolted down, so this is not zero — but a metre of
## wander in five seconds is a machine walking away from its own spawn.
##
## [b]This was the one assertion in the file that failed, from the day the file
## was written until the session that closed it.[/b] It measured 2.82 m on the
## unarmed biped and 4.22 m once `CombatArena.Recipe.BIPED` carried two
## Appendages, two edges and a backpack; over a five-second window with nothing
## commanding it the machine slid **9.74 m at 2.74 m/s**. It is now **0.49 m**.
##
## The diagnosis recorded here was right about the symptom and wrong about the
## cure. "§13.10's ankle holds attitude and §13.11's capture point acts only at
## touchdown" is exactly correct — the machine slid at 0.6° of tilt, perfectly
## upright — and the conclusion drawn from it was that closing it needed a third
## balance layer. It did not. §13.4 already re-plants a standing limb when its hip
## leaves the foot, which is the stepping reflex; what was missing is that
## §13.5's placement law answered the hip's ground projection outright at zero
## cadence, so every one of those re-plants put the foot **directly under a hip
## that was already travelling** and arrested nothing. The capture point was not
## absent from the standing state, it was being discarded on arrival.
##
## The bound stays at a metre rather than being tightened onto the measurement.
## The machine is balancing rather than bolted down and this is the assertion that
## would notice it walking away from its own spawn again.
const STANDING_DRIFT_LIMIT_M: float = 1.0

## Metres a commanded run must cover, and metres a commanded reverse must cover
## in the opposite direction.
##
## [b]The reverse figure is the one that matters.[/b] Doc 05 §13.9 measures the
## shipped ambulatory family at 0.01 m of reverse over three seconds and asserts
## it as a defect in `tests/physics/test_braking_and_reverse.gd`. Anything above
## noise here is §13.11 doing the thing the old placement law could not.
##
## Re-measured on `mot.limb.broad_foot.t4`: **9.47 m forward and 8.44 m back**,
## against 4.32 and 5.22 when the recipe stood on the four-limbed family's limb
## and 0.01 m of reverse when the placement law had only an authored gain.
const TRAVEL_MIN_M: float = 1.5
const REVERSE_MIN_M: float = 0.75

var _arena: CombatArena = null

var _settled_tilt_deg: float = -1.0
var _settled_drift_m: float = -1.0
var _forward_m: float = 0.0
var _reverse_m: float = 0.0
var _turn_worst_tilt_deg: float = 0.0
var _turn_final_tilt_deg: float = 0.0
var _turn_deg: float = 0.0
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


## [b]The assertion this file did not have, and the whole of what
## `mot.limb.broad_foot.t4` is for.[/b]
##
## Every other method here measures the machine in a straight line, and in a
## straight line it was fine: 0.6° of settled tilt and nine metres on a demand.
## Ask it to turn and it went over — measured on the shared `mot.limb.strider.t4`
## foot at throttle 0.8 and full right lock, **97.7° of tilt, face down from
## t=390, and it stays there for the rest of the window**. Nothing in the suite
## looked, because nothing in the suite held a steering demand on a biped.
##
## The mechanism is doc 05 §13.10's clamp and it is arithmetic, not mystery. An
## ankle can apply `N × half-extent`, a limb in single support carries the whole
## Assembly so `N ≈ m·g`, and the tilt that bound can hold against the pendulum it
## is holding is `sin θ_max = foot_length / 2h`. A biped is in single support for
## `2 × duty − 1 = 76%` of its gait cycle; a quadruped never is. So the foot that
## is generous on four limbs was 6.8° on two, and a commanded turn produces eight.
##
## Asserted as a tilt and a heading together, because each alone passes for the
## wrong reason: a machine lying on its face has stopped turning, and a machine
## spinning on its side has turned a very long way.
func test_a_sustained_turn_does_not_put_it_on_its_face() -> void:
	await _run()
	check_true(
		_turn_worst_tilt_deg < TURN_TILT_LIMIT_DEG,
		(
			"ten seconds of full right lock and the worst tilt is %.1f°, ending at "
			+ "%.1f°, against 97.7° on the four-limbed family's foot"
		) % [_turn_worst_tilt_deg, _turn_final_tilt_deg]
	)
	check_true(
		_turn_deg < -TURN_MIN_DEG,
		(
			"and it came round %+.0f° to its right while doing it, where positive is "
			+ "left and a right demand is a negative rotation about world up"
		) % _turn_deg
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

	await _turn()
	print(
		"      biped: %d ticks of full right lock — %+.0f° of heading, worst tilt %.1f°, ending %.1f°"
		% [TURN_TICKS, _turn_deg, _turn_worst_tilt_deg, _turn_final_tilt_deg]
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


## Holds throttle and full right lock for [constant TURN_TICKS] and records the
## worst tilt reached, the tilt at the end, and the heading accumulated.
##
## The heading is accumulated per tick rather than compared end to end, for the
## reason `tests/physics/test_ambulatory_drift.gd` records at length:
## `signed_angle_to` answers in (−180°, 180°], and this machine comes round more
## than a full circle inside the window, so an end-to-end comparison reports a
## small angle in the wrong direction.
func _turn() -> void:
	_arena = CombatArena.new()
	_arena.open()
	var c := _arena.spawn(CombatArena.Recipe.BIPED, 0, Vector2.ZERO, 0.0, 0)
	await _arena.settle(SETTLE_TICKS)
	var body := c.runtime.body
	var previous := -body.global_basis.z
	_turn_deg = 0.0
	_turn_worst_tilt_deg = 0.0
	for i: int in TURN_TICKS:
		c.motion.input.throttle = TURN_THROTTLE
		c.motion.input.steer = 1.0
		await _arena.step_once()
		var now := -body.global_basis.z
		_turn_deg += rad_to_deg(previous.signed_angle_to(now, Vector3.UP))
		previous = now
		_turn_worst_tilt_deg = maxf(_turn_worst_tilt_deg, _tilt_deg(c))
	c.motion.input.throttle = 0.0
	c.motion.input.steer = 0.0
	_turn_final_tilt_deg = _tilt_deg(c)
	_close()


func _tilt_deg(c: CombatArena.Combatant) -> float:
	var up := c.runtime.body.global_basis.y
	return rad_to_deg(up.angle_to(Vector3.UP))


func _close() -> void:
	if _arena != null:
		_arena.close()
		_arena = null
