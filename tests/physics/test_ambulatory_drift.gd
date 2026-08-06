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
## [b]The rebuild widened it and the chassis split narrowed it again.[/b] The
## standing case used to hold a heading to a fraction of a degree and was this
## file's control; on the 5148 kg ground chassis it turned about fifty degrees
## over the same window. On `core.ambulatory.strider.t3` — 1350 kg against 1800,
## nine cells long against thirteen — it turns eighteen. Every number in this file
## moved with that chassis and every one of them was re-measured against it:

## | | ground chassis | strider chassis |
## |---|---|---|
## | neutral | −140.4° | **−92.2°** |
## | hard over | −8.3° | +24.6° |
## | counter | −156.1° | **+19.9°** |
## | standing | +51.2° | **−18.1°** |
##
## [b]Three of those improved and one exposed something worse.[/b] Both commanded
## runs now land within five degrees of each other, at +24.6° and +19.9°, from a
## neutral case at −92.2°. So a steering demand moves the outcome by a hundred and
## twelve degrees [i]whichever way it is pointed[/i]. That is not a heading
## authority with too little gain; it is a perturbation of the gait that happens
## to have a direction attached, and it is the sharpest statement this file has
## ever been able to make of §13.8's missing term.
## [method test_the_steering_demand_is_a_disturbance_rather_than_a_heading_authority]
## is the assertion, and it replaces one that said the demand could not null the
## drift — which stopped being true on this chassis.

const SETTLE_TICKS: int = 200
## Ticks the Assembly is walked for. Five seconds, which is about the length of
## an engagement and therefore the number that matters.
const WALK_TICKS: int = 300

## Degrees of heading change that is unambiguously a drift rather than a weave.
## A gait bobs; a gait does not turn fifteen degrees by accident.
##
## It was 60, which was the measurement when the family walked on the ground
## chassis and turned a right angle in five seconds. The strider chassis took that
## to 20.2° and doc 05 §13.10's proportional ankle to **31.8°** — the drift is
## still there and is no longer enormous, so the floor comes down to a little
## under half the measurement, which is the margin fact 47 asks for.
const DRIFT_THRESHOLD_DEG: float = 15.0
## Degrees the hull may lean and still count as walking rather than falling.
const UPRIGHT_DOT: float = 0.90
## Degrees an uncommanded standing Assembly may turn over
## [constant WALK_TICKS], now that it turns almost none.
##
## [b]This constant was a floor and is now a ceiling, and that is the whole of
## what doc 05 §13.10's revision did for standing.[/b] The figure was 51.2° on the
## ground chassis and 18.1° on the strider, and the file asserted it as a defect
## as it stood. With the ankle's restoring torque scaled to the machine's own
## `m·g·h` it is **0.54°** — back under the one degree §13.4's standing state used
## to hold before the rebuild. Four degrees is seven times the measurement and
## still far below anything the defect ever produced.
const STANDING_DRIFT_CEILING_DEG: float = 4.0
## How level a standing Assembly stays. It was asserted at 0.999 — two and a half
## degrees — and the strider chassis holds 0.9892, which is eight and a half.
## Lower inertia over the same gait disturbance is the whole of the difference,
## and it is a lean rather than a topple: [constant UPRIGHT_DOT]'s walking bound
## is far looser again.
const STANDING_UPRIGHT_DOT: float = 0.98
## Degrees between the two commanded runs, above which the steering demand is a
## signed heading authority rather than a disturbance with a sign attached.
##
## It was measured at 4.7° and asserted as a ceiling: full left and full right
## landed in the same place, which is the sharpest statement this file could make
## of doc 05 §13.8's missing heading term. Under §13.10's proportional ankle the
## two runs separate by **55.1°** and land on opposite sides of neutral, so the
## demand now decides the heading. Twenty-five is under half the measurement.
##
## What it does [b]not[/b] decide is which way. See
## [method test_the_steering_demand_has_authority_and_it_is_inverted].
const STEERING_SEPARATION_DEG: float = 25.0

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


## [b]The demand decides the heading now, and it decides it backwards.[/b]
##
## This assertion has been re-measured twice and inverted once. It was written
## against a ground chassis on which full opposite lock could not null the drift;
## it became "both commanded runs land in the same place" — +24.6° against +19.9°,
## under five degrees apart out of a hundred and twelve degrees of effect — which
## was the sharpest statement this file could make of doc 05 §13.8's missing
## heading term. Under §13.10's proportional ankle the same two runs land at
## **+44.0° and −11.1°**: opposite sides of neutral, 55.1° apart. A walking
## Assembly that spends less of its stride staying upright has a placement law
## that can actually steer it.
##
## [b]And the sign is wrong.[/b] `_walk` returns positive for left and
## [member ControlInput.steer] is positive for right, so a right demand should
## come back negative. Full right returns +44.0° and full left −11.1°: the family
## steers the opposite way to every other one in the game. Doc 05 §13.5's
## placement law already negates the yaw once for exactly this reason and that
## negation is correct in isolation, so this is not that line — it is a second
## inversion somewhere between the demand and the plant that could not be seen
## while the demand had no authority to invert. Asserted as it stands, as §9
## requires: when the inversion is found this check goes red and the fix is to
## flip the comparison, never to widen it.
##
## Both sides of the comparison are [i]commanded[/i] runs, and that is deliberate.
## It used to compare the counter-steered run against the neutral one, and session
## 23 found that assertion resting on a number that is not reproducible: adding
## one unrelated engagement file earlier in the suite flipped the neutral case
## from +169.6° to −76.1° while leaving both commanded runs byte-identical. The
## neutral walker is the knife-edge — the one whose outcome is decided entirely by
## accumulated asymmetry, with no demand to dominate it — so its direction is a
## property of the suite's floating-point history and not of the family. Its
## magnitude is stable and is asserted above; nothing here may depend on its sign.
func test_the_steering_demand_has_authority_and_it_is_inverted() -> void:
	await _measure()
	check_true(
		_hard_over_deg - _counter_deg > STEERING_SEPARATION_DEG,
		(
			"a right demand ends %+.1f° and a left one %+.1f°, %.1f° apart — so the "
			+ "demand decides the heading, and it decides it the wrong way round: "
			+ "positive is left and positive steer is right"
		)
		% [_hard_over_deg, _counter_deg, _hard_over_deg - _counter_deg]
	)


## [b]It came back.[/b]
##
## §13.4's standing state held a heading to a fraction of a degree indefinitely,
## which is why the arena's tactics plant an ambulatory Assembly before it shoots
## instead of walking it into contact. The chassis rebuild took that away: a
## standing Assembly yawed about fifty degrees over three hundred ticks on the
## ground hull and eighteen on `core.ambulatory.strider.t3`, turning on the spot
## with nothing asking it to, and this file asserted the defect as it stood.
##
## Doc 05 §13.10's ankle is now a multiple of the Assembly's own `m·g·h` rather
## than an absolute 60 000 N·m/rad, and the drift is **0.54°** — under the one
## degree the standing state used to hold. Nothing here was aimed at yaw: the
## ankle sets its yaw component to zero by construction (§13.10) and always has.
## What changed is that the machine is no longer working its stance to stay
## upright, so the horizontal components of four stance forces cancel the way the
## geometry says they should.
##
## Asserted as a magnitude and never as a sign, exactly as it was when it was a
## complaint. Nothing commands this walker, so LEARNED_FACTS.md §1 fact 54's
## second half applies in full: an uncommanded quantity's direction is a property
## of the suite's floating-point history.
func test_standing_still_holds_a_heading_again() -> void:
	await _measure()
	check_true(
		absf(_standing_deg) < STANDING_DRIFT_CEILING_DEG,
		(
			"a standing Assembly holds its heading: %.2f° over %d ticks, against "
			+ "18.1° on this chassis before §13.10's proportional ankle and 51.2° "
			+ "on the ground one"
		) % [_standing_deg, WALK_TICKS]
	)
	check_true(
		_standing_upright > STANDING_UPRIGHT_DOT,
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
