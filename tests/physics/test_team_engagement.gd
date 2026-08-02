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
	# sides. Same fight, different float ordering (§3.44).
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
		e.terminated >= e.spawned / 2,
		"at least half the field was destroyed: %d of %d" % [e.terminated, e.spawned]
	)
	check_true(
		e.survivors_total < e.spawned / 2,
		"and fewer than half were left: %d" % e.survivors_total
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
	# Twenty Assemblies, and the one engagement of the five that now runs to its
	# timeout rather than being over in ninety-one ticks.
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
		e.ticks > ENGAGE_TICKS / 2,
		"and it took most of the window to do it: %d of %d ticks" % [e.ticks, ENGAGE_TICKS]
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
		["rounds", _brawl.rounds_fired, _combined.rounds_fired],
		["packets", _brawl.hits_landed, _combined.hits_landed],
		["parts", _brawl.parts_destroyed, _combined.parts_destroyed],
		["kills", _brawl.terminated, _combined.terminated],
	]:
		check_true(
			int(pair[1]) > int(pair[2]),
			"the brawl leads on %s: %d against %d" % [pair[0], int(pair[1]), int(pair[2])]
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
