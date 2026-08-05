extends TestCase
## An ambulatory Assembly commanded straight ahead, with the steering demand held
## at exactly zero, turning most of the way round in five seconds.
##
## [b]This file records a defect. It does not fix one.[/b] The behaviour is
## asserted as it is, so the day it changes something fails and says so.
##
## [b]What it is.[/b] Hold `throttle = 1`, hold `steer = 0`, and the hull yaws
## progressively in one direction — measured below at something over a hundred
## degrees across three hundred ticks. Nothing commands it. The build is
## symmetric about its own centreline: the limbs sit at ±0.875 m, the stations
## mirror at ±0.75 m, and the solved centre of mass is 15 mm off centre on a
## machine 1.75 m wide.
##
## [b]Why it matters more than it looks.[/b] It is not a wobble, it is an
## integrator: heading error accumulates for as long as the Assembly walks, and
## the steering demand cannot null it. Held hard over the yaw drift is
## [i]reduced[/i] and not reversed, which is the measurement that turns "the
## pilot is steering badly" into "the family has less yaw authority than it has
## yaw disturbance". Everything downstream inherits it — an Assembly that cannot
## hold a heading cannot hold a firing solution either, because doc 07 §4.3
## converges a mount at half a degree and slews it at 65°/s.
##
## [b]What it is not.[/b] Not a fall: §13.4's every foot planted is honoured and
## the hull stays level to within a degree, walking or standing. Not the
## placement law's saturated velocity
## demand, which was a real defect and is fixed —
## [method GaitSolver.top_speed_mps] now caps the demand at what the gait can
## deliver, and that alone cut the walking pitch from thirty degrees to under
## ten. Not the turn command's sign, which was inverted against every other
## family and is fixed. The drift is what is left after all three.
##
## [b]Where the fix belongs.[/b] Doc 05 §13, and probably §13.8 — which states
## outright that "the Raibert term is the only balance authority" and lists no
## heading authority at all. A yaw-rate term in the placement law is new
## architecture and CLAUDE.md §10 rule 13 puts it outside what a test file may
## decide. What this file does is stop it being rediscovered.
##
## [b]The rebuild widened it.[/b] The standing case used to hold a heading to a
## fraction of a degree and was this file's control; on the 5148 kg chassis it
## turns about fifty degrees over the same window. See
## [method test_standing_still_no_longer_holds_a_heading], which is asserted as it
## behaves for the same reason everything else here is.

const SETTLE_TICKS: int = 200
## Ticks the Assembly is walked for. Five seconds, which is about the length of
## an engagement and therefore the number that matters.
const WALK_TICKS: int = 300

## Degrees of heading change that is unambiguously a drift rather than a weave.
## A gait bobs; a gait does not turn a right angle by accident.
const DRIFT_THRESHOLD_DEG: float = 60.0
## Degrees the hull may lean and still count as walking rather than falling.
const UPRIGHT_DOT: float = 0.90
## Degrees an uncommanded standing Assembly is measured to turn over
## [constant WALK_TICKS]. See
## [method test_standing_still_no_longer_holds_a_heading].
const STANDING_DRIFT_FLOOR_DEG: float = 20.0

## Metres between the four stations, and how far off the arena's centreline the
## whole row sits. Well clear of where every other file builds its fixture, so a
## leaked Assembly is a visible bug rather than a silent one that eats the next
## file's rounds.
const STATION_SPACING_M: float = 120.0
const STATION_OFFSET_M: float = 300.0

var _measured: bool = false
var _arena: CombatArena = null
var _neutral_deg: float = 0.0
var _hard_over_deg: float = 0.0
var _counter_deg: float = 0.0
var _standing_deg: float = 0.0
var _standing_upright: float = 0.0
var _walking_upright: float = 0.0


func after_all() -> void:
	if _arena != null:
		_arena.close()
		_arena = null


func test_a_neutral_steering_demand_does_not_hold_a_heading() -> void:
	await _measure()
	check_true(
		absf(_neutral_deg) > DRIFT_THRESHOLD_DEG,
		(
			"walked straight ahead with steer held at zero and turned %.1f° in %d ticks"
			% [_neutral_deg, WALK_TICKS]
		)
	)
	check_true(
		_walking_upright > UPRIGHT_DOT,
		"while staying on its feet, so this is a drift and not a fall: up · UP = %.3f"
		% _walking_upright
	)


func test_the_steering_demand_cannot_null_the_drift() -> void:
	# The assertion that makes it a defect rather than a tuning note. If full
	# opposite lock held the heading, an autopilot could fly this family and the
	# finding would be "the pilot needs a gain". It does not: with the demand hard
	# over against the drift for five seconds the hull still ends up turned most of
	# a right angle, which is the measurement that turns "the pilot is steering
	# badly" into "the family has less yaw authority than it has yaw disturbance".
	await _measure()
	check_true(
		absf(_counter_deg) > DRIFT_THRESHOLD_DEG,
		(
			"full opposite steer still ends up turned past the threshold: %.1f° against %.1f°"
			% [_counter_deg, DRIFT_THRESHOLD_DEG]
		)
	)
	# And the demand is not simply ignored — the two opposite commands produce
	# different headings, which is what separates this from a dead control path.
	#
	# Both sides of this comparison are *commanded* runs, and that is deliberate.
	# It used to compare the counter-steered run against the neutral one, and
	# session 23 found that assertion resting on a number that is not
	# reproducible: adding one unrelated engagement file earlier in the suite
	# flipped the neutral case from +169.6° to −76.1° while leaving both commanded
	# runs byte-identical at +109.8° and +93.1°. The neutral walker is the
	# knife-edge — it is the one whose outcome is decided entirely by accumulated
	# asymmetry, with no demand to dominate it — so its *direction* is a property
	# of the suite's floating-point history and not of the family. Its magnitude
	# is stable and is asserted above; nothing here may depend on its sign.
	check_true(
		absf(_hard_over_deg - _counter_deg) > 1.0,
		(
			"and the demand does bite: %.1f° hard over against %.1f° countering"
			% [_hard_over_deg, _counter_deg]
		)
	)


## [b]The control used to be the half that worked, and the rebuild took it.[/b]
##
## §13.4's standing state held a heading to a fraction of a degree indefinitely —
## which is why the arena's tactics plant an ambulatory Assembly before it shoots
## instead of walking it into contact. On the rebuilt chassis a standing Assembly
## yaws about fifty degrees over the same three hundred ticks. The hull attitude
## is still level, so it is not falling over; it is turning on the spot with
## nothing asking it to.
##
## [b]Asserted as it behaves, as a magnitude and never as a sign.[/b] Nothing
## commands this walker, so LEARNED_FACTS.md §1 fact 54's second half applies in
## full: an uncommanded quantity's direction is a property of the suite's
## floating-point history. The magnitude is the measurement. When doc 05 §13 gains
## the heading term §13.8 currently forbids by omission, this check goes red and
## the fix is to re-measure it back down, not to loosen it.
func test_standing_still_no_longer_holds_a_heading() -> void:
	await _measure()
	check_true(
		absf(_standing_deg) > STANDING_DRIFT_FLOOR_DEG,
		(
			"a standing Assembly turns on the spot: %.2f° over %d ticks, where the "
			+ "1391 kg build it replaced held to under one"
		) % [_standing_deg, WALK_TICKS]
	)
	check_true(
		_standing_upright > 0.999,
		"and it is turning rather than toppling: up · UP = %.4f" % _standing_upright
	)


## ===== FIXTURES ========================================================


## Walks one Assembly per steering demand, each on its own patch of slab, and
## records the heading it ends up with.
##
## The recipe is [constant CombatArena.Recipe.AMBULATORY_BARE] — no Effector
## Module — deliberately. An armed build drifts further, and somebody would
## reasonably ask whether 196 kg on the nose is the cause. It is not: this is the
## symmetric machine with nothing bolted to it.
func _measure() -> void:
	if _measured:
		return
	_measured = true
	_arena = CombatArena.new()
	_arena.open()
	_neutral_deg = await _walk(0.0, 1.0, 0)
	_walking_upright = _last_upright
	_hard_over_deg = await _walk(1.0, 1.0, 1)
	_counter_deg = await _walk(-1.0, 1.0, 2)
	_standing_deg = await _walk(0.0, 0.0, 3)
	_standing_upright = _last_upright
	# Closed here rather than left to `after_all`, and it matters. Every arena
	# builds in the one world the autoloads live in (§3.45), and this file sorts
	# first in `tests/physics/` — four Assemblies left standing on the slab put
	# the next file's engagement inside them, where they soak every round fired.
	# `after_all` stays as the guard for a run that fails part-way through.
	_arena.close()
	_arena = null
	print(
		(
			"  ambulatory drift over %d ticks: neutral %+.1f°, hard over %+.1f°, "
			+ "counter %+.1f°, standing %+.2f°"
		)
		% [WALK_TICKS, _neutral_deg, _hard_over_deg, _counter_deg, _standing_deg]
	)


var _last_upright: float = 0.0


## Spawns an Assembly at its own station, settles it, holds [param steer] and
## [param throttle] for [constant WALK_TICKS], and returns the signed heading
## change in degrees. Positive is left.
func _walk(steer: float, throttle: float, station: int) -> float:
	var c := _arena.spawn(
		CombatArena.Recipe.AMBULATORY_BARE,
		station,
		Vector2(float(station) * STATION_SPACING_M, STATION_OFFSET_M),
		0.0,
		0
	)
	await _arena.settle(SETTLE_TICKS)
	var body := c.runtime.body
	var start := -body.global_transform.basis.z
	c.motion.input.throttle = throttle
	c.motion.input.steer = steer
	for i: int in WALK_TICKS:
		await physics_frames(1)
	c.motion.input.throttle = 0.0
	c.motion.input.steer = 0.0
	_last_upright = body.global_transform.basis.y.dot(Vector3.UP)
	return rad_to_deg(start.signed_angle_to(-body.global_transform.basis.z, Vector3.UP))
