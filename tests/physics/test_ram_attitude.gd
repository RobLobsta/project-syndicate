extends TestCase
## Three [AiDriver]s converging on a stationary Assembly, and the one question
## every other engagement file in this suite cannot answer: [b]does it end up on
## its side?[/b]
##
## Doc 05 §15.7.1 owns the approach and §15.7.5 owns the spacing between several
## drivers closing on one target. Between them they decide what the shipped
## match's first five seconds are, and until session 31 nothing measured the
## outcome that matters most to whoever is sitting in the target: the capture
## showed an 1107 kg hull on its flank at five seconds and destroyed at seven,
## while the suite was green on 6143 checks.
##
## [b]It is green code that was wrong, not broken code that was missed.[/b] Every
## fixture in [code]tests/physics/[/code] records rounds, ticks, kills and travel,
## and a build that has been driven over moves none of them. That is why this file
## opens with an instrument rather than with a law:
## [member CombatArena.Combatant.worst_roll_deg] is the number, and the assertions
## below are what it is for.
##
## [b]Nobody here is armed.[/b] Every combatant is spawned with a store of zero,
## so not one round leaves a barrel for the whole run and the only thing that can
## move the target is a hull. An engagement that also shoots cannot tell a build
## that was rammed over from one that was blown over, and the two want different
## repairs.

## The shipped match's own geometry, from [code]MatchScreen[/code]: a player at
## the origin and three opponents converging from the far side. Copied rather
## than imported, and deliberately — §9's rule is that a test which reads the
## same constant its subject does asserts nothing, and the case being defended
## here is the arrangement a player actually meets rather than whatever
## [code]MatchScreen[/code] is set to this week.
const TARGET_XZ := Vector2(0.0, 0.0)
const ATTACKER_XZ: Array[Vector2] = [
	Vector2(0.0, -34.0), Vector2(-22.0, -46.0), Vector2(21.0, -44.0)
]

## Ticks for four builds to fall onto their contacts with nothing driving them.
const SETTLE_TICKS: int = 90

## Ticks the approach then runs for. The nearest attacker is 34 m out and the
## wheeled build makes about 4.5 m/s, so eight seconds is the approach and the
## rest is however long the drivers spend at their stand-off — which is the
## window the ram happens in, and the reason this is not cut to the approach.
const APPROACH_TICKS: int = 900

## Degrees of roll past which a hull is not on its wheels any more.
##
## [b]It is not a description of the measurement and must not become one.[/b]
## Between an upright build and one on its flank there is 90°, and the fixture
## has to sit somewhere that a wheel lifting over a bump cannot reach and a hull
## going over cannot avoid. 30° is a third of the way onto a flank: past the
## point where a four-contact build has any weight left on the inside pair, so
## an Assembly that reaches it is falling rather than leaning.
##
## Measured before it was chosen, and there is nothing near it in either
## direction. Against the shipped six-metre stand-off the target reached
## [b]146.2°[/b] — past a flank and most of the way onto its roof — and stayed
## there; against §15.7.1's arrival law and a stand-off that clears the hulls it
## reads [b]0.3°[/b]. No run of this fixture has ever produced a number between
## one degree and a hundred and forty, which is what makes a bound in the middle
## of that gap a bound rather than a description of a reading.
const ROLLED_OVER_DEG: float = 30.0

## Metres of clear air a stand-off has to leave between the two hulls.
##
## [b]Bare non-contact is not enough, and a fault sweep is what showed it.[/b]
## The first version of the assertion below demanded only that the gap stay
## positive, and against the shipped six-metre stand-off — with the arrival brake
## already in — it passed with **eight centimetres**. A sampled-per-tick gap of
## eight centimetres on hulls closing at a couple of metres a second is a
## collision the sampling missed, and `stand-off-inside-the-hulls` accordingly
## survived every physics file in the suite and was caught only by the unit test
## asserting the published constant.
##
## So the fixture asks for what a stand-off actually is rather than for the
## absence of the worst outcome. One metre is well above the sampling error and
## well under the 3.16 m the shipped law leaves.
const CLEAR_AIR_M: float = 1.0

## Degrees of roll past which a [i]driver[/i] is not on its wheels any more.
##
## Looser than the bound above, and the difference is the whole reason there are
## two constants. The target is standing still, so anything that tips it is
## something that hit it; an attacker is braking hard out of thirteen metres a
## second with the lock over, and leaning twenty degrees through that is a
## wheeled build doing its job. Measured at 5.4° on the settled approach and
## 21.5° on a run whose fixture had drifted, so this is not a threshold sitting
## on top of a reading.
##
## 60° is two thirds of the way onto a flank: nothing a build recovers from.
const DRIVER_ROLLED_OVER_DEG: float = 60.0

## Metres, body origin to body origin, inside which a driver counts as having
## arrived.
##
## [b]The assertion that stops every other one in this file being vacuous.[/b]
## "The target was not rolled over" is satisfied in full by three drivers that
## never reached it, which is a documented failure of §15.7.1's throttle law —
## the section records opponents milling about at forty to seventy metres for a
## whole capture under a floor that was measurably better on a flat slab. So the
## fix for the ram is not allowed to buy its number by not arriving, and this is
## what says so.
##
## Twice the base stand-off, which is the same bound
## [code]test_ai_engagement.gd[/code] uses for the same reason.
const ARRIVED_M: float = AiDriver.GROUND_STAND_OFF_M * 2.0

## Metres the nearest attacker must start out at for the approach to be one.
##
## Written down rather than derived from the stand-off, and that is the point:
## the constant under test in this file [i]is[/i] the stand-off, so a fixture
## precondition scaled off it moves whenever the subject does and stops being a
## precondition. 30 m is comfortably short of the shipped match's nearest
## opponent spawn at 34 m and comfortably longer than any stand-off this section
## would plausibly hold.
const OPENED_AT_LEAST_M: float = 30.0

## §10's difficulty. Irrelevant to a fixture where nothing can fire, and set to
## the shipped match's value anyway so that the scan and the target choice run
## exactly as they do in a game.
const DIFFICULTY: float = 0.55

var _fought: bool = false
var _arena: CombatArena = null
var _run_record: Approach = null


func after_all() -> void:
	if _arena != null:
		_arena.close()
		_arena = null


## ===== THE FIXTURE =====================================================


## First, because every assertion after it is unfalsifiable if the drivers never
## turned up. §2's lesson, in the form it takes here: a bound is only tested by
## geometry that reaches it.
func test_the_drivers_actually_reach_the_target() -> void:
	await _run()
	check_true(
		_run_record.opened_at_m > OPENED_AT_LEAST_M,
		"the fixture opened out of contact: nearest attacker %.1f m out"
		% _run_record.opened_at_m
	)
	check_true(
		_run_record.closest_m < ARRIVED_M,
		(
			"and at least one of them closed to inside twice its stand-off: %.1f m against %.1f"
			% [_run_record.closest_m, ARRIVED_M]
		)
	)


## ===== WHAT THE INSTRUMENT IS FOR ======================================


## Doc 05 §15.7.1, from the target's point of view. The whole finding, in one
## number that did not exist before this file.
func test_the_stationary_target_is_still_on_its_wheels() -> void:
	await _run()
	check_true(
		_run_record.target_roll_deg < ROLLED_OVER_DEG,
		(
			"the target was not rolled over: %.1f degrees of roll against a bound of %.0f"
			% [_run_record.target_roll_deg, ROLLED_OVER_DEG]
		)
	)


## The rammer goes over too, and asserting only the victim would miss half of it.
## An Assembly that drives into a stationary 1107 kg hull at speed lifts its own
## nose and can end up on its flank beside the thing it hit.
func test_the_drivers_are_still_on_their_wheels() -> void:
	await _run()
	check_true(
		_run_record.worst_attacker_roll_deg < DRIVER_ROLLED_OVER_DEG,
		(
			"no driver rolled itself over on the approach: worst %.1f degrees"
			% _run_record.worst_attacker_roll_deg
		)
	)


## §15.7.1's stand-off is a range a driver stops at, and this is the assertion
## that it is one. Distinct from the roll and from the shove: a driver can arrive
## on top of its target, fail to tip it, fail to move it, and still be standing
## where no stand-off would put it.
##
## Measured against the hulls rather than against the stand-off, because it is
## the hulls that decide what a collision is — and with a metre of margin rather
## than at bare contact, for the reason [constant CLEAR_AIR_M] records.
func test_no_driver_ends_up_on_top_of_the_target() -> void:
	await _run()
	check_true(
		_run_record.hulls_touch_at_m > 0.0,
		"the hulls were measured: they meet at %.1f m" % _run_record.hulls_touch_at_m
	)
	check_true(
		_run_record.closest_m - _run_record.hulls_touch_at_m > CLEAR_AIR_M,
		(
			"the nearest approach left clear air rather than grazing: %.2f m of gap"
			% (_run_record.closest_m - _run_record.hulls_touch_at_m)
		)
	)


## ===== THE RUN =========================================================


## One approach, run once, recorded, and asserted from by every method above. A
## destructive fixture cannot be repeated (§9), and this one is destructive in
## the literal sense: if the ram happens, the target is on its side for the rest
## of the file.
func _run() -> void:
	if _fought:
		return
	_fought = true

	_arena = CombatArena.new()
	_arena.open()

	# A store of zero on every combatant. Nothing fires for the whole run, so the
	# only thing that can move the target is a hull — which is the isolation this
	# file exists for.
	var target := _arena.spawn(
		CombatArena.Recipe.WHEELED_REPEATER, 0, TARGET_XZ, 0.0, 0
	)
	# No driver and no pilot: the state a player is in while they look around,
	# and the state doc 11 §16's wreck is in for the rest of the match.
	target.arena_piloted = false

	var attackers: Array[CombatArena.Combatant] = []
	for xz: Vector2 in ATTACKER_XZ:
		attackers.append(
			_arena.spawn(
				CombatArena.Recipe.WHEELED_LIGHT,
				1,
				xz,
				CombatArena.yaw_towards(xz, TARGET_XZ),
				0
			)
		)

	await _arena.settle(SETTLE_TICKS)

	var rec := Approach.new()
	rec.hulls_touch_at_m = (
		target.hull_half_length_m() + attackers[0].hull_half_length_m()
	)
	rec.target_speed_at_open_mps = target.runtime.body.linear_velocity.length()
	# Recorded when the fixture is built, not when a test happens to ask: the
	# runner sorts methods and by the time an alphabetically later one runs the
	# target may be several metres from here (§9).
	var settled_at := target.runtime.body.global_position
	rec.opened_at_m = INF
	for a: CombatArena.Combatant in attackers:
		rec.opened_at_m = minf(
			rec.opened_at_m, settled_at.distance_to(a.runtime.body.global_position)
		)

	# Attached after the settle, so the approach starts from rest and from the
	# pose the fixture was built at. Every field is set before the node enters
	# the tree, which is what [method CombatArena.make_autonomous] is for.
	for a: CombatArena.Combatant in attackers:
		_arena.make_autonomous(a, DIFFICULTY)

	await _arena.engage(APPROACH_TICKS)

	rec.closest_m = target.closest_enemy_m
	rec.target_roll_deg = target.worst_roll_deg
	rec.target_nose_down_deg = target.worst_nose_down_deg
	rec.target_peak_speed_mps = target.peak_speed_mps
	rec.target_shoved_m = Vector2(
		target.runtime.body.global_position.x - settled_at.x,
		target.runtime.body.global_position.z - settled_at.z
	).length()
	for a: CombatArena.Combatant in attackers:
		rec.worst_attacker_roll_deg = maxf(rec.worst_attacker_roll_deg, a.worst_roll_deg)
		rec.attacker_peak_speed_mps = maxf(rec.attacker_peak_speed_mps, a.peak_speed_mps)
	rec.shots = _arena.shots_fired
	_run_record = rec

	for line: String in _arena.timeline:
		print("      %s" % line)
	# Closed the moment its record is taken, not in `after_all`. A leaked arena
	# leaves four Assemblies standing at the origin and the next file builds its
	# engagement inside them, which reports as a damage defect in a file that has
	# nothing wrong with it (LEARNED_FACTS.md §1 fact 48). `after_all` stays as
	# the guard for a run that failed part-way through.
	_arena.close()
	_arena = null
	print(
		(
			"  ram: opened %.1f m, closest %.1f m (hulls meet at %.1f m, gap %.2f m); "
			% [
				rec.opened_at_m, rec.closest_m, rec.hulls_touch_at_m,
				rec.closest_m - rec.hulls_touch_at_m
			]
		)
		+ (
			"target roll %.1f°, nose down %.1f°, "
			% [rec.target_roll_deg, rec.target_nose_down_deg]
		)
		+ (
			"shoved %.2f m, peak %.2f m/s (from %.2f m/s at open); "
			% [rec.target_shoved_m, rec.target_peak_speed_mps, rec.target_speed_at_open_mps]
		)
		+ (
			"attacker roll %.1f°, peak %.1f m/s; %d rounds"
			% [rec.worst_attacker_roll_deg, rec.attacker_peak_speed_mps, rec.shots]
		)
	)


## What one approach left behind.
class Approach:
	extends RefCounted

	var opened_at_m: float = 0.0
	var closest_m: float = 0.0
	## Origin-to-origin range at which the two builds' colliders meet nose to
	## nose. The number §15.7.1's stand-off has to clear, and the reason the
	## record prints a gap rather than only a range.
	var hulls_touch_at_m: float = 0.0
	var target_roll_deg: float = 0.0
	var target_nose_down_deg: float = 0.0
	var target_peak_speed_mps: float = 0.0
	## How far the stationary target ended up from where it settled.
	##
	## [b]Printed and deliberately not asserted, because it does not measure what
	## it looks like it measures.[/b] It was an assertion first — a parked 1107 kg
	## Assembly moves for exactly one reason — and the reason turned out not to be
	## the drivers. A wheeled build with no throttle and no brake never comes to
	## rest on a level slab: this fixture's target reads 0.38 m/s at the end of a
	## 90-tick settle and [b]still 0.38 m/s after 360[/b], and covers two to three
	## metres over the engagement while the nearest hull stays three metres clear
	## of it. Nothing in doc 05 §7 puts a rolling resistance under a free contact.
	##
	## So the shove is the drift, and the assertion it looked like it was making
	## is made properly by the hull gap above — which cannot be satisfied by a
	## target that wandered off on its own. The drift itself is a real finding and
	## is written up in `HANDOFF.md` rather than fixed here.
	var target_shoved_m: float = 0.0
	## The target's own speed at the moment the drivers were released, and the
	## number that identified the drift above. A fixture whose baseline is already
	## moving reports its own drift as a ram.
	var target_speed_at_open_mps: float = 0.0
	var worst_attacker_roll_deg: float = 0.0
	var attacker_peak_speed_mps: float = 0.0
	## Rounds fired by anybody. Asserted nowhere and printed on purpose: it is
	## zero by construction, and a run where it is not is a run whose isolation
	## has quietly gone.
	var shots: int = 0
