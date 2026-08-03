extends TestCase
## Two engagements with more than two Assemblies in them: five-a-side combined
## arms, and twenty wheeled builds in one brawl.
##
## [code]test_family_duels.gd[/code] asks what a locomotion family does to a
## fight. This file asks what happens when the fight is bigger than the pairing,
## and it is the first thing in the project's history to put ten Assemblies on a
## side. Three things only become visible at that scale:
##
## [enum]
## [*] [b]Target selection is a system.[/b] Every Assembly picks the nearest live
##     enemy every tick, so the two lines converge into a knot and the pairings
##     re-form as Assemblies die. Nothing coordinates it and nothing needs to.
## [*] [b]The bounds are real bounds.[/b] Twenty Effector Modules on a 0.14 s
##     cycle can put a hundred and forty rounds a second into a pool sized at
##     2048, and Invariant I-12's ceiling stops being arithmetic on paper.
## [*] [b]Friendly fire is geometry, not a rule.[/b] Nothing in [DamageResolver]
##     knows what a team is. A line of Assemblies firing through each other at
##     the line opposite hits whatever the ray reaches first, which is sometimes
##     the Assembly in front.
## [/enum]
##
## [b]The five-a-side is one of each recipe.[/b] Both teams field the identical
## five, which makes the composition a constant and leaves position, facing and
## the roll of the spread cone as the only differences — the same reasoning that
## makes the mirror duels worth running.

## Metres between the two lines at the start, and between neighbours in a line.
const LINE_SEPARATION_M: float = 40.0
const FILE_SPACING_M: float = 7.0

const SETTLE_TICKS: int = 180
## Ticks a team engagement is given. Twenty seconds; a five-a-side that reaches
## this is a finding rather than a pass, and the brawl is allowed the same.
const ENGAGE_TICKS: int = 1200

const TEAM_A: int = 0
const TEAM_B: int = 1

const BRAWL_PER_SIDE: int = 10

## What this fight cost before §4.13 bounded overpenetration: one round stalling
## inside a hull took a Core Module to zero on its own, and twenty guns finished
## in ninety-one ticks. The reversal is what the brawl is here to record.
const BRAWL_PRE_BOUND_TICKS: int = 91

## Floor on the brawl's length, and deliberately far below what it measures.
##
## [b]This bound was `ENGAGE_TICKS / 2` and that was not a measurement of the
## fight.[/b] Session 20 added an integration file elsewhere in the suite that
## spawns eight two-part Assemblies and frees them before any physics test runs,
## and the brawl went from running out its 1200-tick window to finishing in 316 —
## reproducibly, three runs in a row, and reproducibly again from a control file
## that did nothing but spawn those bodies and free them. Nothing about the
## combat layer changed.
##
## That is JULES.md §6.6 and LEARNED_FACTS.md §1 fact 54 arriving where nobody had
## applied them:
## once twenty rigid bodies share one space, the solver's float ordering depends
## on the allocation history of the whole process, so a tick count is a
## measurement of the [i]suite[/i] and not of the engagement. Re-asserting the
## new number would only move the fragility to the next session that adds a file.
##
## So the bound is set at twice the pre-fix figure — clear of every composition
## measured (316, 338, and the full window) by a wide margin, and still an order
## of magnitude away from the ninety-one ticks it exists to rule out. It is a
## floor on the reversal, which is a real property, rather than a description of
## the fight, which is not a stable one.
const BRAWL_MIN_TICKS: int = BRAWL_PRE_BOUND_TICKS * 2

## Assemblies the five-a-side must destroy for the fight to count as decided.
##
## [b]This is a bound, not a measurement, and the distinction is the whole
## point.[/b] It was `spawned / 2` — five of ten — and that number sat inside the
## fixture's natural spread rather than below it. Observed terminations across
## runs: 7 (three survivors at the timeout), 5 (one team standing at 654 ticks),
## and 4 (after `tests/physics/test_ground_terrain.gd` was added). Nothing about
## the fight changed between the last two; LEARNED_FACTS.md §1 fact 54 is the mechanism,
## and it is that once twenty rigid bodies have shared a space the solver's float
## ordering depends on the allocation history of the whole process, so any
## earlier file that creates and destroys bodies moves the outcome here.
##
## That fact predicted this exact failure — "re-asserting the new number would have
## moved the fragility to whoever added the next file" — so the fix is not to
## re-centre on 4. Three of ten is comfortably under every run anybody has
## observed and still fails hard if combat regresses to a stalemate, which is the
## only thing this assertion was ever defending. The qualitative claims above it
## — every Assembly opened fire, rounds landed, Core Modules were lost, more
## parts died than Assemblies — carry the rest.
const COMBINED_MIN_TERMINATED: int = 3

## The combined-arms roster, in the order it is fielded from the left flank.
## Both teams get the same five, so the composition is a constant.
const COMBINED_ARMS: Array[int] = [
	CombatArena.Recipe.WHEELED_LIGHT,
	CombatArena.Recipe.WHEELED_HEAVY,
	CombatArena.Recipe.TRACKED,
	CombatArena.Recipe.AMBULATORY,
	CombatArena.Recipe.ROTARY,
]

var _fought: bool = false
var _combined: Engagement = null
var _brawl: Engagement = null
var _open: CombatArena = null


func after_all() -> void:
	if _open != null:
		_open.close()
		_open = null


## ===== COMBINED ARMS ===================================================


func test_five_a_side_combined_arms_fights_itself_to_pieces() -> void:
	# Ten Assemblies, five recipes a side, and it now produces a result: most of
	# the field dies. One run ended at 654 ticks with a single team holding the
	# ground; the next ran the clock out with three survivors between the two
	# sides. Same fight, different float ordering (LEARNED_FACTS.md §3).
	#
	# It did not, last session. What changed is not the roster and not the
	# tactics — it is that overpenetration is bounded (doc 07 §12.2.2), so a
	# round no longer grinds a Core Module to zero on its own and a fight is
	# decided by volume of fire instead of by which round happened to stall; that
	# the fire gate refuses a clamped solution (§4.3.1), so nobody spends the
	# engagement shooting over the enemy; and that an ambulatory Assembly plants
	# and shoots instead of walking in circles.
	await _run_all()
	var e := _combined

	check_eq(e.spawned, COMBINED_ARMS.size() * 2, "ten Assemblies took the field")
	check_eq(e.distinct_ids, e.spawned, "each with its own assembly id")
	check_eq(e.shooters, e.spawned, "every one of them opened fire")
	check_true(e.hits_landed > 0, "rounds landed: %d packets resolved" % e.hits_landed)
	check_true(
		e.terminated > 0, "%d Assemblies lost their Core Modules" % e.terminated
	)
	# Ranged, not exact, and §3.44 is why: once ten rigid bodies share one space
	# the run is no longer bit-reproducible, and two consecutive runs of this
	# fixture have ended at 654 ticks with one team standing and at the 1200-tick
	# timeout with three survivors between them. Both are the same result — a
	# combined-arms line that fights itself to pieces — and an exact assertion on
	# either would be asserting float ordering inside the physics server.
	check_true(
		e.terminated >= COMBINED_MIN_TERMINATED,
		"a decisive share of the field was destroyed: %d of %d" % [e.terminated, e.spawned]
	)
	check_true(
		e.survivors_total <= e.spawned - COMBINED_MIN_TERMINATED,
		"and that many fewer were left standing: %d" % e.survivors_total
	)


func test_every_recipe_reached_the_five_a_side_in_working_order() -> void:
	# The fixture assertion, recorded when the fixture was built rather than when
	# an alphabetically later method happens to ask. A combined-arms engagement in
	# which the rotary Assemblies had quietly fallen out of the sky during the
	# settle, or the ambulatory ones had come down on their hulls, would satisfy
	# every assertion above it and would be a four-a-side.
	await _run_all()
	check_eq(_combined.upright_at_start, _combined.spawned, "all ten were upright")
	check_eq(
		_combined.airborne_at_start,
		2,
		"and both rotary Assemblies were flying when the shooting started"
	)


## ===== THE BRAWL =======================================================


func test_ten_wheeled_builds_a_side_grind_each_other_down() -> void:
	# Twenty Assemblies, and the one engagement of the five that takes seconds
	# rather than being over in ninety-one ticks.
	#
	# That reversal is the clearest single measurement of what bounding
	# overpenetration did. Last session this was the fastest fight in the suite —
	# twenty guns opening at once, and a round that stalled inside a hull took a
	# Core Module to zero on its own. Now the same twenty guns need twenty seconds
	# to kill sixteen of each other and cannot finish, which is what a firefight
	# between symmetrical forces should look like.
	await _run_all()
	var e := _brawl

	check_eq(e.spawned, BRAWL_PER_SIDE * 2, "twenty Assemblies took the field")
	check_eq(e.distinct_ids, e.spawned, "each with its own assembly id")
	check_eq(e.shooters, e.spawned, "every one of them opened fire")
	check_true(
		e.terminated > BRAWL_PER_SIDE,
		"%d of the twenty lost their Core Modules" % e.terminated
	)
	check_true(
		e.parts_destroyed > e.terminated,
		"and %d parts came off in total, so it was not all Core Module hits"
		% e.parts_destroyed
	)
	check_true(
		e.ticks > BRAWL_MIN_TICKS,
		(
			"and it took far longer than the %d ticks it took before the bound: %d of %d"
			% [BRAWL_PRE_BOUND_TICKS, e.ticks, ENGAGE_TICKS]
		)
	)


func test_the_projectile_pool_survived_twenty_effector_modules() -> void:
	# Invariant I-12's 2048, met by the only thing in the project that can
	# actually reach it. Twenty modules on a 0.14 s cycle emit about a hundred and
	# forty rounds a second between them, so a pool that leaked at all would fill
	# inside a fifteen-second engagement — and §12.4's recycling would then start
	# taking live rounds, which presents as shots vanishing in mid-air and is
	# close to undiagnosable after the fact.
	await _run_all()
	check_true(
		_brawl.peak_in_flight < ProjectileSystem.POOL_SIZE,
		(
			"the pool peaked at %d of %d rounds in flight"
			% [_brawl.peak_in_flight, ProjectileSystem.POOL_SIZE]
		)
	)
	check_true(
		_brawl.rounds_fired > _brawl.peak_in_flight,
		(
			"and %d rounds were fired against that peak, so rounds were being retired"
			% _brawl.rounds_fired
		)
	)


func test_the_brawl_is_the_bigger_engagement() -> void:
	# The scaling claim, and the reason this file exists rather than a fourth
	# duel. Twenty Assemblies is twenty [MotiveSystem]s, twenty [EffectorSystem]s
	# and something over two hundred collision shapes in one space, and none of
	# the per-Assembly work became per-pair work.
	await _run_all()
	check_eq(_brawl.shooters, BRAWL_PER_SIDE * 2, "twenty Assemblies fired")
	check_eq(_combined.shooters, COMBINED_ARMS.size() * 2, "against the five-a-side's ten")
	for pair: Array in [
		["packets", _brawl.hits_landed, _combined.hits_landed],
		["parts", _brawl.parts_destroyed, _combined.parts_destroyed],
		["kills", _brawl.terminated, _combined.terminated],
	]:
		check_true(
			int(pair[1]) > int(pair[2]),
			"the brawl leads on %s: %d against %d" % [pair[0], int(pair[1]), int(pair[2])]
		)
	# Rounds is a [b]rate[/b] here and the three rows above are not, which is a
	# distinction this assertion learned the hard way. Parts and kills are bounded
	# by the roster — twenty Assemblies have more to lose than ten — so comparing
	# the totals is comparing the engagements. Rounds fired is bounded by nothing
	# but the clock, and the moment the brawl started reaching a decision inside a
	# fifth of its budget while the five-a-side still ran to the timeout, the
	# bigger engagement "lost" on rounds by having finished. §3.54's warning about
	# tick counts in a multi-Assembly file, arriving through a quantity that is
	# not obviously a tick count.
	var brawl_rate := float(_brawl.rounds_fired) / maxf(float(_brawl.ticks), 1.0)
	var combined_rate := float(_combined.rounds_fired) / maxf(float(_combined.ticks), 1.0)
	check_true(
		brawl_rate > combined_rate,
		(
			"and it leads on rounds per tick: %.3f over %d ticks against %.3f over %d"
			% [brawl_rate, _brawl.ticks, combined_rate, _combined.ticks]
		)
	)


## ===== FIXTURES ========================================================


func _run_all() -> void:
	if _fought:
		return
	_fought = true
	_combined = await _engage("combined arms", COMBINED_ARMS)
	var brawl_roster: Array[int] = []
	for i: int in BRAWL_PER_SIDE:
		brawl_roster.append(CombatArena.Recipe.WHEELED_HEAVY)
	_brawl = await _engage("wheeled brawl", brawl_roster)


## Fields [param roster] on both teams, facing each other across
## [constant LINE_SEPARATION_M], and runs it to a decision.
##
## Every arena builds its slab and its Assemblies at the same coordinates in the
## one world the autoloads live in, so exactly one is open at a time: two at once
## put the second engagement inside the first one's wreckage and mix both sets of
## counters on the bus.
func _engage(name: String, roster: Array[int]) -> Engagement:
	var arena := CombatArena.new()
	_open = arena
	arena.open()

	var half := float(roster.size() - 1) * FILE_SPACING_M * 0.5
	for i: int in roster.size():
		var x := float(i) * FILE_SPACING_M - half
		var a := Vector2(x, LINE_SEPARATION_M * 0.5)
		var b := Vector2(-x, -LINE_SEPARATION_M * 0.5)
		arena.spawn(
			roster[i], TEAM_A, a, CombatArena.yaw_towards(a, Vector2(a.x, -a.y)),
			AmmoLedger.UNLIMITED
		)
		arena.spawn(
			roster[i], TEAM_B, b, CombatArena.yaw_towards(b, Vector2(b.x, -b.y)),
			AmmoLedger.UNLIMITED
		)

	await arena.settle(SETTLE_TICKS)

	var e := Engagement.new()
	e.name = name
	e.spawned = arena.combatants.size()
	var ids := {}
	for c: CombatArena.Combatant in arena.combatants:
		ids[c.assembly_id()] = true
		if c.runtime.body.global_transform.basis.y.dot(Vector3.UP) > UPRIGHT_DOT:
			e.upright_at_start += 1
		if c.recipe == CombatArena.Recipe.ROTARY and c.runtime.body.global_position.y > 3.0:
			e.airborne_at_start += 1
	e.distinct_ids = ids.size()

	# Through [method CombatArena.engage] rather than a loop of this file's own.
	# A local loop was two lines shorter and left every entry in the timeline
	# stamped `t=0`, because the arena's tick counter advances inside its own
	# loop — a whole engagement's chronology lost to a duplicated four lines.
	await arena.engage(ENGAGE_TICKS)
	e.ticks = arena.ticks_engaged
	e.peak_in_flight = arena.peak_in_flight

	e.rounds_fired = arena.shots_fired
	e.hits_landed = arena.hits_landed
	e.shooters = arena.shots_by.size()
	e.parts_destroyed = arena.destroyed.size()
	e.terminated = arena.terminated.size()
	e.teams_standing = arena.teams_standing().size()
	e.survivors_total = arena.survivors(TEAM_A).size() + arena.survivors(TEAM_B).size()
	e.timeline = arena.timeline.duplicate()
	print(
		(
			"  %s: %d ticks, %d rounds from %d shooters, %d hits, %d parts, "
			+ "%d killed, %d left standing, pool peak %d"
		)
		% [
			name, e.ticks, e.rounds_fired, e.shooters, e.hits_landed,
			e.parts_destroyed, e.terminated, e.survivors_total, e.peak_in_flight
		]
	)
	for line: String in e.timeline:
		print("      " + line)
	arena.close()
	_open = null
	return e



## Dot product of an Assembly's own up with the world up that still counts as
## upright. Eight degrees of lean.
const UPRIGHT_DOT: float = 0.99


## ===== RECORDS =========================================================


## What one team engagement did, captured while it was still standing.
class Engagement:
	extends RefCounted

	var name: String = ""
	var ticks: int = 0
	var spawned: int = 0
	var distinct_ids: int = 0
	var upright_at_start: int = 0
	var airborne_at_start: int = 0
	var rounds_fired: int = 0
	var shooters: int = 0
	var hits_landed: int = 0
	var parts_destroyed: int = 0
	var terminated: int = 0
	var teams_standing: int = 0
	var survivors_total: int = 0
	var peak_in_flight: int = 0
	var timeline: PackedStringArray = PackedStringArray()
