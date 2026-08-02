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


func test_five_a_side_combined_arms_grinds_without_resolving() -> void:
	# Ten Assemblies, five recipes a side, twenty seconds — and it does not
	# finish. Three of the ten die, both teams are still standing at the timeout,
	# and the survivors are still shooting at each other when the clock runs out.
	#
	# Asserted as it behaves, because the reason is already recorded next door and
	# is the same one:
	# [method test_family_duels.test_two_walking_assemblies_cannot_settle_it_and_here_is_why].
	# Once the opening exchange is over, what is left on each side includes
	# something that cannot hold a firing solution, and a mixed force fights at
	# the rate of its worst gun platform rather than its best. The ten-a-side
	# brawl below settles in ninety-one ticks with a roster of the one recipe that
	# can shoot straight, which is the same finding seen from the other end.
	await _run_all()
	var e := _combined

	check_eq(e.spawned, COMBINED_ARMS.size() * 2, "ten Assemblies took the field")
	check_eq(e.distinct_ids, e.spawned, "each with its own assembly id")
	check_eq(e.shooters, e.spawned, "every one of them opened fire")
	check_true(e.hits_landed > 0, "rounds landed: %d packets resolved" % e.hits_landed)
	check_true(
		e.terminated > 0, "%d Assemblies lost their Core Modules" % e.terminated
	)
	check_true(
		e.terminated < e.spawned, "and %d of them were still alive" % e.survivors_total
	)
	check_eq(e.ticks, ENGAGE_TICKS, "the engagement ran to the timeout")
	check_eq(e.teams_standing, 2, "with both teams still in it")


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


func test_ten_wheeled_builds_a_side_fight_to_a_decision() -> void:
	await _run_all()
	var e := _brawl

	check_eq(e.spawned, BRAWL_PER_SIDE * 2, "twenty Assemblies took the field")
	check_eq(e.distinct_ids, e.spawned, "each with its own assembly id")
	check_true(e.shooters > BRAWL_PER_SIDE, "%d of them opened fire" % e.shooters)
	check_true(
		e.terminated > 0, "%d Assemblies lost their Core Modules" % e.terminated
	)
	check_true(
		e.parts_destroyed > e.terminated,
		"and %d parts came off in total, so it was not all Core Module hits"
		% e.parts_destroyed
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


func test_the_brawl_is_the_bigger_engagement_by_every_measure_but_its_length() -> void:
	# The scaling claim, and the reason this file exists rather than a fourth
	# duel. Twenty Assemblies is twenty [MotiveSystem]s, twenty [EffectorSystem]s
	# and something over two hundred collision shapes in one space, and none of
	# the per-Assembly work became per-pair work.
	#
	# Note which way round the round counts go. The brawl fires [i]fewer[/i] total
	# rounds than the five-a-side, because it is over in ninety-one ticks against
	# twelve hundred — twenty guns opening at once on twenty targets settles it
	# before anybody reloads. Rounds fired is a measure of duration here, not of
	# intensity; hits, parts and kills are the measures of intensity, and the
	# brawl leads on all three.
	await _run_all()
	check_eq(_brawl.shooters, BRAWL_PER_SIDE * 2, "twenty Assemblies fired")
	check_eq(_combined.shooters, COMBINED_ARMS.size() * 2, "against the five-a-side's ten")
	check_true(
		_brawl.hits_landed > _combined.hits_landed,
		(
			"the brawl resolved more packets: %d against %d"
			% [_brawl.hits_landed, _combined.hits_landed]
		)
	)
	check_true(
		_brawl.terminated > _combined.terminated,
		(
			"and killed more Assemblies: %d against %d"
			% [_brawl.terminated, _combined.terminated]
		)
	)
	check_true(
		_brawl.ticks < _combined.ticks,
		"in less time: %d ticks against %d" % [_brawl.ticks, _combined.ticks]
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

	# Sampled inside the loop rather than read at the end: the pool drains as
	# rounds land and expire, so the count after the last tick says nothing about
	# how full it ever got.
	for i: int in ENGAGE_TICKS:
		for c: CombatArena.Combatant in arena.combatants:
			arena.command(c)
		await _tick()
		e.ticks += 1
		e.peak_in_flight = maxi(e.peak_in_flight, arena.projectiles.active_count())
		if arena.teams_standing().size() <= 1:
			break

	e.rounds_fired = arena.shots_fired
	e.hits_landed = arena.hits_landed
	e.shooters = arena.shots_by.size()
	e.parts_destroyed = arena.destroyed.size()
	e.terminated = arena.terminated.size()
	e.teams_standing = arena.teams_standing().size()
	e.survivors_total = arena.survivors(TEAM_A).size() + arena.survivors(TEAM_B).size()
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
	arena.close()
	_open = null
	return e


func _tick() -> void:
	await (Engine.get_main_loop() as SceneTree).physics_frame


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
