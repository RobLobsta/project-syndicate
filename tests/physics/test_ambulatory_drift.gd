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
## `m·g·h` it went to 0.54° — back under the one degree §13.4's standing state used
## to hold before the rebuild.
##
## **Re-measured at 5.68°, and the rise is the price of §13.5's standing capture
## point.** A standing Assembly now takes a real step whenever its hip leaves the
## foot it is standing on, where before it re-planted directly underneath itself
## and never had to move; a step is a stance force applied off the centreline, so
## a machine that steps holds a heading slightly less well than one that is
## sliding across the ground with both feet welded under its hips. Ten degrees is
## under twice the measurement, and it is bought with the assertion below —
## 6.85 m of translation became 0.18 m.
const STANDING_DRIFT_CEILING_DEG: float = 10.0

## Metres an uncommanded standing Assembly may travel over
## [constant WALK_TICKS].
##
## [b]This file is named for drift and measured only the rotational half of it,
## which is how the family came to slide for the whole life of the project.[/b]
## The heading assertion above has been green since §13.10's ankle landed and was
## read, reasonably, as "standing is solved"; meanwhile the same machine was
## travelling **6.85 m in five seconds at 2.28 m/s** with nothing commanding it,
## and the shipped biped 9.74 m at 2.74. Nothing measured it, because a machine
## sliding in a dead straight line at a constant heading is a machine this file
## reported as holding perfectly still.
##
## The cause was doc 05 §13.5's placement law answering the hip's ground
## projection outright at zero cadence, so §13.4's re-plant put the foot under a
## hip that was already moving and arrested nothing. Measured after: **0.18 m**.
## Half a metre is a bound rather than the measurement — the machine is balancing
## rather than bolted down — and it is an order below what it replaced.
const STANDING_TRAVEL_CEILING_M: float = 0.5
## How level a standing Assembly stays. It was asserted at 0.999 — two and a half
## degrees — and the strider chassis holds 0.9892, which is eight and a half.
## Lower inertia over the same gait disturbance is the whole of the difference,
## and it is a lean rather than a topple: [constant UPRIGHT_DOT]'s walking bound
## is far looser again.
const STANDING_UPRIGHT_DOT: float = 0.98
## Fraction of [member LimbProfile.turn_rate_deg_s] a commanded run must actually
## achieve, and the slack above it.
##
## [b]This constant used to be a ceiling on how far apart two opposite demands
## could land, and it is now a floor under how fast the machine comes round.[/b]
## The history is worth the three lines because it is the same measurement read
## three ways. It was written when full opposite lock could not null the drift; it
## became "both commanded runs land in the same place" — 4.7° apart out of 112° of
## effect, which was the sharpest statement this file could make of doc 05 §13.8's
## missing heading term; and it briefly read as an *inversion*, because with the
## ankle scaled to the machine the demand acquired 55° of authority pointing the
## wrong way.
##
## None of that survives §13.12. `steer` no longer feeds a lateral velocity into
## §13.5's correction — it turns the machine, through a rate controller on the
## body's own yaw inertia — and the two halves of turning stopped fighting.
## Measured over 300 ticks: full right **−218.7°** and full left **+219.4°**,
## which is 43.7 and 43.9 degrees a second against an authored 45.0.
## `mot.limb.strider.t4`'s authored turn rate, written out by value.
##
## Read from the document rather than from the profile, because a test that
## imports the same figure its subject reads asserts nothing (§9): the expectation
## would move with the part and a limb that had lost its turn rate entirely would
## still pass.
const LIMB_TURN_RATE_DEG_S: float = 45.0

const TURN_RATE_FLOOR: float = 0.70
const TURN_RATE_CEILING: float = 1.15

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
var _standing_travel_m: float = 0.0
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


## [b]The demand turns the machine, at the rate the part authors, in the direction
## it is asked to.[/b] This is doc 05 §13.12 and it is the assertion this file was
## written to be unable to make.
##
## Two things landed together and neither works without the other. `steer` stopped
## commanding a lateral velocity — a walking Assembly is driven like a walker, so
## `throttle` walks it along its own facing and `steer` turns it — and the family
## gained a heading authority: a rate controller on the body's own yaw inertia,
## divided among the limbs that are actually planted, targeting
## [member LimbProfile.turn_rate_deg_s].
##
## Until the first of those, one number did two jobs. A right command asked for a
## rightward *velocity* at the same moment it rotated the stride, §13.5's
## correction planted the foot hard left to produce the velocity, and the velocity
## error won — which is why three sessions of measurement read the placement law's
## sign as inverted when it was correct all along.
##
## [b]Asserted as a rate and a sign, never as a heading.[/b] The window is long
## enough for the machine to come round more than half a circle, and a heading is
## only defined modulo one — `_walk` accumulates per tick for exactly that reason,
## and the docstring there records what the wrap cost. Both sides of the
## comparison are commanded runs, which is the other rule this file learned the
## hard way: session 23 found the *neutral* case flipping sign when an unrelated
## file was added earlier in the suite, because a quantity with no demand driving
## it is the suite's floating-point history and not the family's behaviour.
func test_the_steering_demand_turns_the_machine_at_the_authored_rate() -> void:
	await _measure()
	var authored := WALK_TICKS * SyndicateConstants.PHYSICS_DT * LIMB_TURN_RATE_DEG_S
	# Positive is left and positive steer is right, so the right-hand run is the
	# negative one. Asserting the two separately rather than as a separation is
	# what makes a symmetric sign flip fail rather than pass.
	check_true(
		_hard_over_deg < -authored * TURN_RATE_FLOOR
		and _hard_over_deg > -authored * TURN_RATE_CEILING,
		(
			"a full right demand comes round %.1f° in %d ticks, against the %.1f° "
			+ "its authored %.0f°/s asks for"
		) % [_hard_over_deg, WALK_TICKS, -authored, LIMB_TURN_RATE_DEG_S]
	)
	check_true(
		_counter_deg > authored * TURN_RATE_FLOOR
		and _counter_deg < authored * TURN_RATE_CEILING,
		"and a full left demand comes round %+.1f° the other way" % _counter_deg
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


## [b]The half of "drift" this file is named for and did not measure.[/b] Six
## sessions of green heading assertions sat on top of a machine that was sliding
## across the arena at 2.28 m/s with nothing commanding it, because a slide in a
## straight line changes no heading at all. Doc 05 §13.5's standing capture point
## is what closed it; this check is what would notice it coming back.
func test_standing_still_holds_its_station_and_not_only_its_heading() -> void:
	await _measure()
	check_true(
		_standing_travel_m < STANDING_TRAVEL_CEILING_M,
		(
			"a standing Assembly stays where it was put: %.2f m over %d ticks, against "
			+ "6.85 m at 2.28 m/s before §13.5 kept the capture point at zero cadence"
		) % [_standing_travel_m, WALK_TICKS]
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
	_standing_travel_m = _last_travel_m
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
			+ "counter %+.1f°, standing %+.2f° and %.2f m"
		)
		% [
			WALK_TICKS, _neutral_deg, _hard_over_deg, _counter_deg, _standing_deg,
			_standing_travel_m
		]
	)


var _last_upright: float = 0.0
var _last_travel_m: float = 0.0


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
	c.motion.input.throttle = throttle
	c.motion.input.steer = steer
	# [b]Accumulated tick by tick, and it has to be.[/b] `signed_angle_to` answers
	# in (-180°, 180°], so a machine that turns further than half a circle reports
	# a smaller angle in the *opposite* direction — and doc 05 §13.12's heading
	# authority turns the shipped limb at 45°/s, which is 225° over this window.
	# Measured before this was fixed: a full right demand reported +154°, a left
	# turn, when the machine had in fact come round 206° to the right.
	var previous := -body.global_transform.basis.z
	var from := body.global_position
	var turned := 0.0
	for i: int in WALK_TICKS:
		await physics_frames(1)
		var now := -body.global_transform.basis.z
		turned += previous.signed_angle_to(now, Vector3.UP)
		previous = now
	c.motion.input.throttle = 0.0
	c.motion.input.steer = 0.0
	_last_upright = body.global_transform.basis.y.dot(Vector3.UP)
	# The other half of "drift", and the half this file was missing. Flat, because
	# a machine settling onto its feet changes height and that is not drift.
	_last_travel_m = Vector2(
		body.global_position.x - from.x, body.global_position.z - from.z
	).length()
	return rad_to_deg(turned)
