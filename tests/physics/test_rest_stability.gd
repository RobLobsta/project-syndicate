extends TestCase
## What an Assembly does when nobody is asking it for anything, from
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §7.4 and §7.7.
##
## [b]This file was written asserted as it failed, and this session turned it
## round.[/b] Every check below used to record a defect that was diagnosed,
## understood, and deliberately not repaired; §7.4's open block said that closing
## it would turn this file red and that the fix was to re-measure and re-assert,
## never to loosen. That is what happened, and the numbers are worth keeping side
## by side because nothing else in the repository shows the size of it:
##
## | | before | after |
## |---|---|---|
## | Contact rate reversals in 12 ticks | 7 of 11 | [b]0[/b] |
## | Peak contact rate standing still | 5.9 rad/s | [b]under 0.01[/b] |
## | Speed six seconds after the settle | 0.196 m/s | [b]0.000 m/s[/b] |
## | Distance wandered in the same window | 1.307 m | [b]0.000 m[/b] |
##
## [b]The defect.[/b] Every engagement fixture here drives, shoots, or is shot at.
## None of them had ever asked the simplest question a player asks in the first
## ten seconds — [i]I let go of the keys; does it stop?[/i] — and for thirty-six
## sessions the answer was no.
##
## [b]The cause was not a missing friction term.[/b] §7.4's torque balance was
## right; the integration of it was 142 times outside its own stability limit,
## against a friction reaction of about 2.9e5 N per rad/s. It did not diverge,
## because §7.2's curve saturates — it limit-cycled, which is why no aggregate any
## fixture recorded ever moved.
##
## [b]So the instrument this file added is the one nothing had: the sign history
## of the contact's angular rate.[/b] A hull that is stationary on average moves
## no speed assertion and no travel assertion, and both of those were green
## through this for the life of the project. What a chattering contact cannot hide
## from is being asked how often it changes direction — and that is still the
## check that would notice the repair coming undone.
##
## One Assembly on a slab, which reproduces exactly (LEARNED_FACTS.md §1 fact 44),
## so this file may assert values where an engagement file may only assert
## directions.

## Ticks the build is given to fall onto its contacts and settle. The same figure
## the other single-Assembly files use.
const SETTLE_TICKS: int = 180

## Ticks the contact's rate is sampled over, one sample per tick. The old limit
## cycle reversed on every tick, so a dozen is ten more than it takes to see.
const SAMPLE_TICKS: int = 12

## Ticks the build is left alone for. Six seconds: the original measurement was
## that the drift does not decay over three hundred ticks, so the window has to be
## long enough that "it has come to rest" cannot be answered with "it has not
## finished stopping".
const COAST_TICKS: int = 360

## Sign reversals of the contact rate permitted across [constant SAMPLE_TICKS].
##
## [b]Zero, and it is measured at zero rather than allowed a margin.[/b] A settled
## contact turns one way or sits at zero. It used to reverse on seven of the
## eleven transitions of twelve samples, peaking at 5.9 rad/s against a
## free-rolling 1.2 — which is what §7.4's explicit step produced, and it is what
## this number is here to catch coming back.
const PERMITTED_REVERSALS: int = 0

## Peak contact rate, in rad/s, tolerated while the hull is standing still.
## Measured at under a thousandth; the bound is two orders above the measurement
## and three below the 5.9 rad/s it replaced.
const CHATTER_PEAK_CEILING_RAD_S: float = 0.01

## Speed, in m/s, the build may still be doing at the end of the window.
##
## §7.7's holding brake is what makes this a real zero rather than a small number:
## a driver demanding neither drive nor brake below a crawl has parked, and the
## resisting torque then holds the contacts while §7.4 part 3's stick cap lands
## the hull's remaining velocity on nothing. Measured at 0.0000 m/s.
const AT_REST_MPS: float = 0.01

## Metres it may wander over the same window on flat ground under no demand.
## Measured at 0.000 m against the 1.307 m it replaced.
const AT_REST_DRIFT_M: float = 0.05

var _ran: bool = false
var _arena: CombatArena = null

var _reversals: int = 0
var _worst_omega: float = 0.0
var _free_rolling_omega: float = 0.0
var _speed_at_settle_mps: float = 0.0
var _speed_coasting_mps: float = 0.0
var _drift_m: float = 0.0
var _holding: bool = false


func after_all() -> void:
	_teardown()


## The instrument, and the whole reason the file exists. A contact that reverses
## every tick is not solving anything; it is oscillating about the rolling
## condition because the step cannot resolve it.
##
## The second check is what stops the first being satisfied by a contact that is
## merely turning slowly: the old chatter ran at rates the hull's own speed could
## not account for.
func test_a_resting_contact_does_not_reverse() -> void:
	await _run()
	check_eq(
		_reversals,
		PERMITTED_REVERSALS,
		(
			"a contact under a build standing still reversed %d times in %d ticks. "
			+ "Seven was §7.4's limit cycle; if this is above zero the explicit step "
			+ "has come back"
		) % [_reversals, SAMPLE_TICKS]
	)
	check_true(
		_worst_omega < CHATTER_PEAK_CEILING_RAD_S,
		(
			"and peaked at %.4f rad/s against a free-rolling %.4f, so what is left is "
			+ "the contact tracking the hull and not a limit cycle"
		) % [_worst_omega, _free_rolling_omega]
	)


## What a player meets in the first ten seconds. The build is on level ground with
## no throttle and no brake and it comes to a complete stop.
func test_a_build_left_alone_comes_to_rest() -> void:
	await _run()
	check_true(
		_holding, "the holding brake engaged on a record demanding neither drive nor brake"
	)
	check_true(
		_speed_coasting_mps < AT_REST_MPS,
		(
			"%d ticks after the settle the build is doing %.4f m/s, against %.4f m/s "
			+ "at the settle and 0.196 m/s before §7.4 was closed"
		) % [COAST_TICKS, _speed_coasting_mps, _speed_at_settle_mps]
	)
	check_true(
		_drift_m < AT_REST_DRIFT_M,
		"and moved %.3f m from where it was left, against 1.307 m before" % _drift_m
	)


## Runs once; four assertions over one settle (LEARNED_FACTS.md §1 fact 43).
func _run() -> void:
	if _ran:
		return
	_ran = true
	_arena = CombatArena.new()
	_arena.open()
	var c := _arena.spawn(CombatArena.Recipe.WHEELED_LIGHT, 0, Vector2.ZERO, 0.0, 0)
	await _arena.settle(SETTLE_TICKS)

	_speed_at_settle_mps = c.runtime.body.linear_velocity.length()
	var slot := c.motion.motive_slots()[0]
	var radius := PartRegistry.definition(
		c.runtime.state(slot).part_def_id
	).motive_profile.contact_radius_m
	_free_rolling_omega = _speed_at_settle_mps / maxf(radius, SyndicateConstants.EPSILON_LINEAR)

	# Sampled per tick rather than over a window, because the defect this guards
	# against is a per-tick alternation and any average of it is zero. That is
	# exactly why no existing fixture could see it.
	var previous := 0.0
	for i: int in SAMPLE_TICKS:
		await physics_frames(1)
		var contact := c.motion.contact_at(slot, 0)
		var omega := 0.0 if contact == null else contact.contact_omega
		_worst_omega = maxf(_worst_omega, absf(omega))
		if i > 0 and signf(omega) != signf(previous) and not is_zero_approx(omega):
			_reversals += 1
		previous = omega

	var start := c.runtime.body.global_position
	await physics_frames(COAST_TICKS)
	_speed_coasting_mps = c.runtime.body.linear_velocity.length()
	_drift_m = c.runtime.body.global_position.distance_to(start)
	_holding = c.motion.holding_brake_engaged()

	print(
		(
			"      at rest: %d reversals in %d ticks, peak %.4f rad/s against a "
			+ "free-rolling %.4f; %.4f m/s and %.3f m after %d ticks, holding %s"
		) % [
			_reversals, SAMPLE_TICKS, _worst_omega, _free_rolling_omega,
			_speed_coasting_mps, _drift_m, COAST_TICKS, str(_holding)
		]
	)
	_teardown()


func _teardown() -> void:
	if _arena != null:
		_arena.close()
		_arena = null
