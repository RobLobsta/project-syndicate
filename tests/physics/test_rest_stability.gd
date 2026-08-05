extends TestCase
## What an Assembly does when nobody is asking it for anything, from
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §7.4.
##
## [b]This file is asserted as it fails.[/b] Every check below records a defect
## that is diagnosed, understood, and deliberately not repaired in the session
## that measured it — so when §7.4's open defect is closed, this file goes red and
## the fix is to re-measure and re-assert, never to loosen. It is the third file
## in the repository of that shape and the convention is `HANDOFF.md` §4's.
##
## [b]The defect.[/b] Every engagement fixture here drives, shoots, or is shot at.
## None of them had ever asked the simplest question a player asks in the first
## ten seconds — [i]I let go of the keys; does it stop?[/i] — and the answer is no.
## A wheeled build with no throttle and no brake reads a few tenths of a metre a
## second at the end of a settle and is still reading them six seconds later, and
## wanders metres over an engagement.
##
## [b]The cause is not a missing friction term, and that matters, because the
## obvious repair does not work.[/b] §7.4's torque balance is right; the
## integration of it is 142 times outside its own stability limit. The friction
## reaction is a very stiff function of the contact's rate near the rolling
## condition — about 2.9e5 N per rad/s at the shipped all-road figures — so an
## explicit step is stable only below 117 microseconds against this project's
## 16.7 ms tick. It does not diverge, because §7.2's curve saturates. It settles
## into a limit cycle. Rolling resistance added to that would be a small correct
## term inside a large wrong one, and §7.4's amendment records the repair, what it
## was measured to cost, and why it is a `balance-review` pass rather than a bug
## fix.
##
## [b]So the instrument this file adds is the one nothing had: the sign history of
## the contact's angular rate.[/b] A hull that is stationary on average moves no
## speed assertion and no travel assertion, and both of those were green through
## this for the life of the project — six thousand checks and a defect a player
## meets in the first ten seconds. What a chattering contact cannot hide from is
## being asked how often it changes direction.
##
## One Assembly on a slab, which reproduces exactly (LEARNED_FACTS.md §1 fact 44),
## so this file may assert values where an engagement file may only assert
## directions. It still asserts them as bands rather than as points: the *sign*
## history is the measurement, and the magnitudes around it are recorded so that
## the next session can see what moved.

## Ticks the build is given to fall onto its contacts and settle. The same figure
## the other single-Assembly files use.
const SETTLE_TICKS: int = 180

## Ticks the contact's rate is sampled over, one sample per tick. The limit cycle
## reverses on every tick, so a dozen is ten more than it takes to see.
const SAMPLE_TICKS: int = 12

## Ticks the build is left alone for. Six seconds: the original measurement was
## that the drift does not decay over three hundred ticks, so the window has to be
## long enough that "it is still moving" cannot be answered with "it has not
## finished stopping".
const COAST_TICKS: int = 360

## Sign reversals of the contact rate expected across [constant SAMPLE_TICKS].
##
## [b]This is the defect, and the number is a floor rather than a ceiling.[/b] A
## settled contact turns one way or sits at zero; this one reverses on more than
## half the eleven transitions of the twelve samples. Asserted at six so that the
## check is about a contact oscillating rather than about the exact count, which
## LEARNED_FACTS.md §1 fact 54 would have move under an unrelated file.
##
## [b]It was eight, against a measured eleven, and the rebuild took the measured
## figure to seven.[/b] That is not §7.4 being repaired — the peak below went the
## other way, from 4.7 rad/s to 5.9 against a free-rolling 1.2, and the drift from
## 2.3 m to 2.95 — it is a heavier hull pinning the contact against the friction
## saturation for a tick here and there instead of reversing on every one. The
## floor was re-measured rather than the defect re-described.
const CHATTERING_REVERSALS: int = 6

## Peak contact rate, in rad/s, the chatter reaches while the hull is standing
## still. Measured at 5.9 against a free-rolling 1.2 — the chatter is what is
## reversing, not the contact tracking the hull.
const CHATTER_PEAK_FLOOR_RAD_S: float = 2.0

## Speed, in m/s, the build is still doing at the end of the window. A build that
## had come to rest would be under a hundredth of this, and the check is what goes
## red when §7.4 is closed.
const STILL_MOVING_MPS: float = 0.02

## Metres it wanders over the same window while standing on flat ground under no
## demand. Anything it covers is something pushing it.
const DRIFTED_M: float = 0.10

var _ran: bool = false
var _arena: CombatArena = null

var _reversals: int = 0
var _worst_omega: float = 0.0
var _free_rolling_omega: float = 0.0
var _speed_at_settle_mps: float = 0.0
var _speed_coasting_mps: float = 0.0
var _drift_m: float = 0.0


func after_all() -> void:
	_teardown()


## The instrument, and the whole reason the file exists. A contact that reverses
## every tick is not solving anything; it is oscillating about the rolling
## condition because the step cannot resolve it.
##
## The second check is what stops the first being satisfied by a contact that is
## merely turning slowly: the chatter runs at rates the hull's own speed cannot
## account for, so a reversal here is a reversal of something large.
func test_a_resting_contact_reverses_every_tick() -> void:
	await _run()
	check_true(
		_reversals >= CHATTERING_REVERSALS,
		(
			"a contact under a build standing still reversed %d times in %d ticks. "
			+ "If this has dropped, §7.4's step has been repaired and this file is now "
			+ "the wrong way round — re-measure it, do not loosen it"
		) % [_reversals, SAMPLE_TICKS]
	)
	check_true(
		_worst_omega > CHATTER_PEAK_FLOOR_RAD_S,
		(
			"and peaked at %.2f rad/s against a free-rolling %.3f, so what is reversing "
			+ "is the limit cycle and not the contact tracking the hull"
		) % [_worst_omega, _free_rolling_omega]
	)


## What a player meets in the first ten seconds. The build is on level ground with
## no throttle and no brake and it does not stop.
func test_a_build_left_alone_does_not_come_to_rest() -> void:
	await _run()
	check_true(
		_speed_coasting_mps > STILL_MOVING_MPS,
		(
			"%d ticks after the settle the build is still doing %.4f m/s, against %.4f m/s "
			+ "at the settle. When §7.4 is closed this is the check that goes red"
		) % [COAST_TICKS, _speed_coasting_mps, _speed_at_settle_mps]
	)
	check_true(
		_drift_m > DRIFTED_M,
		"and wandered %.3f m from where it was left" % _drift_m
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

	# Sampled per tick rather than over a window, because the defect is a per-tick
	# alternation and any average of it is zero. That is exactly why no existing
	# fixture could see it.
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

	print(
		(
			"      at rest: %d reversals in %d ticks, peak %.3f rad/s against a "
			+ "free-rolling %.3f; %.4f m/s and %.3f m after %d ticks"
		) % [
			_reversals, SAMPLE_TICKS, _worst_omega, _free_rolling_omega,
			_speed_coasting_mps, _drift_m, COAST_TICKS
		]
	)
	_teardown()


func _teardown() -> void:
	if _arena != null:
		_arena.close()
		_arena = null
