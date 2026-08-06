extends TestCase
## The energy edge in a fight. Doc 07 §15, end to end, against something that
## drives, turns, shoots back, and is not where the fixture put it.
##
## [code]tests/physics/test_held_weapon.gd[/code] owns what the laws compute: a
## frozen attacker, a target planted a measured distance down the blade, and every
## number in §15.3, §15.4 and §15.5 asserted against the authored profile. It says
## nothing at all about whether an Assembly can ever land one — neither build in it
## moves, and the target is put back by hand when the strike pushes it away.
##
## This is the other half, and it is the half the game has. `CombatArena` had five
## recipes and not one carried an Appendage, so the melee module authored in
## session 18 and the sustained contact added in session 42 had never been in an
## engagement at all.
##
## [b]The build is a walker with an arm on each flank, and that is a rule.[/b] Doc
## 01 §7.1 refuses an Appendage on any chassis that does not carry the ambulatory
## family, so the only Assembly that can hold a blade is one with a torso and legs
## — see [method PlacementValidator._check_appendage_chassis] for why, and
## [constant CombatArena.MELEE_ARMS] for why the arms run forward from the
## shoulders rather than hanging at the sides.
##
## [b]Two phases, because the two questions have different answers and a single
## fight would only reach the first of them.[/b]
##
## [enum]
## [*] [b]The contact.[/b] Against an unarmed opponent at twelve metres: can a
##     walker close inside its own reach, and once there, can it [i]hold[/i]
##     contact? §15.5 pays per tick, so a build that arrives, strikes, and drifts
##     back off the blade collects one strike — which is LEARNED_FACTS.md §1 fact
##     100 seen from the other side. The same phase settles §15.4's impulse, which
##     is 2800 N·s applied to a 1.1 t hull on contacts rather than to the free body
##     the other file measures it against: if it were enough to knock a target out
##     of reach, the contact would end on the swing that started it.
## [*] [b]The duel.[/b] The same build against an armed one at thirty metres. It
##     loses, and the interesting part is how.
## [/enum]
##
## [b]The edge was expected to lose and that is a measurement, not a failure.[/b]
## What the two phases together say is that the weapon is not what fails: given
## something to walk at, this build arrives and cuts. Against something that
## shoots, it **loses ground** — 30.0 m out to 31.9 — which is doc 05 §13's open
## steering defect and not doc 07 §15's. Asserted as it behaves, per §9's rule
## about writing down a measurement you cannot yet fix.
##
## There is no fire in either phase. `CombatArena` builds no [DotScheduler], so doc
## 08 §7.3's ignition — which the contact phase certainly deposits the heat for —
## cannot light here. That is the arena's gap rather than this file's, and closing
## it would move every engagement measurement in the suite at once.

## Metres between the two spawns, per phase.
##
## Twelve for the contact phase: far enough that the build has to drive there
## under its own power and close enough that a four-tonne Assembly accelerating at
## about a metre per second per second gets there inside the window.
##
## Thirty for the duel, which is the shipped match's own spawn distance rounded to
## the arena's slab. Everything past the gunner's twenty-metre stand-off is the
## edge being shot at for free, and that is the point of the number.
const CONTACT_SEPARATION_M: float = 12.0
const DUEL_SEPARATION_M: float = 30.0

## Ticks for both builds to fall onto their contacts with the triggers cold.
const SETTLE_TICKS: int = 90
## Ticks each phase then runs for. Budgets rather than expectations: the contact
## phase ends when the window does and the duel ends when a Core Module goes.
const CONTACT_TICKS: int = 420
const DUEL_TICKS: int = 900

## The store both builds are given. Only a direct-fire module spends it; doc 07
## §15 resolves by swept volume and touches no ledger, which is one of the things
## the round counter below is asserted to show.
const LOADED_ROUNDS: int = 600

## Range, in metres between body origins, inside which the two hulls are as close
## as their colliders let them get.
##
## A walking Assembly holding two blades out in front of it stops at **8.8 m**,
## which is where the blades meet the other hull, and it cuts from there — so this
## is a floor on "arrived" rather than a measurement of one, with room over the
## measured figure for the fact that a walker never quite stands still.
##
## [b]It was 8.0 while the melee build was wheeled and the layout is what moved
## it.[/b] Two arms carried at the top of a 2.4 m torso reach further forward than
## one arm carried at hull height did, and the walker's own hull is deeper. The
## number is a property of the recipe and has to be re-derived whenever the recipe
## moves, which is the argument for the assertion that follows it: THERMAL
## arriving at all is unambiguous where a range is a geometry.
const CONTACT_RANGE_M: float = 10.0

## Metres the range may re-open by after the edge has first cut something.
##
## [b]This is the assertion §15.5's "an instalment carries no impulse" was waiting
## for, and it is a gap rather than a threshold.[/b] Held correctly the walker
## arrives at its blades' length and stays there: measured re-opening over the
## rest of the phase, **0.00 m**. With §15.4's per-swing impulse applied on every
## tick instead, sixty of them a second throw the target clear and the range opens
## by metres.
##
## [b]It is not sufficient on its own and the history is the lesson.[/b] While
## this recipe was wheeled it rammed at three metres a second, kept a firm grip,
## and the re-opening separated correct from faulted by 0.03 m against 5.15. A
## walker leans on its target far more gently and its contact flickers, so a fault
## that throws the target costs contact rather than distance and the re-opening
## stops discriminating. [constant TARGET_PEAK_SPEED_MPS] is what discriminates
## now — and the two constants are kept together because which of them is the
## sharp one is a property of the [i]recipe[/i], and the recipe has already
## changed once.
const CONTACT_REOPEN_M: float = 1.5

## Ceiling on how fast the target may ever be travelling during the contact phase,
## in m/s.
##
## The other half of §15.5's "an instalment carries no impulse", and on a walking
## attacker it is the half that bites. A four-tonne machine walking into a 1.1 t
## one moves it at **0.03 m/s** — the shove is two colliders touching and nothing
## else. With §15.4's 2800 N·s applied on every tick instead, sixty a second is
## about 46 m/s² on that hull and it leaves at speed.
##
## One is thirty times the measured figure and far below anything an impulse can
## produce, which is the margin fact 47 asks for. Note that this bound would have
## been [b]useless[/b] on the wheeled version of this recipe, where the ram itself
## moved the target at 2.76 m/s: the same law needs a different instrument
## depending on how the Assembly carrying it gets around.
const TARGET_PEAK_SPEED_MPS: float = 1.0

var _ran: bool = false
var _arena: CombatArena = null
var _contact: Phase = null
var _duel: Phase = null


func after_all() -> void:
	_close_arena()


## ===== THE CONTACT =====================================================


## The first question, and the one every other assertion about the contact phase
## is conditional on. An edge that never arrives is not an edge that lost.
func test_the_edge_closes_to_contact() -> void:
	await _run()
	check_true(
		_contact.closest_range_m < CONTACT_RANGE_M,
		(
			"the melee build closed from %.1f m to %.1f m, which is hull to hull"
			% [CONTACT_SEPARATION_M, _contact.closest_range_m]
		)
	)


## The chain closes: an Assembly that drove there put an edge through another
## Assembly's hull, and it arrived as heat because that is what doc 01 §10.5
## authors.
func test_the_edge_cuts_what_it_reached() -> void:
	await _run()
	if not check_true(
		_contact.thermal_to_target > 0.0,
		"the edge reached the other hull: %.1f THERMAL" % _contact.thermal_to_target
	):
		return
	check_true(
		_contact.thermal_to_target > _contact.kinetic_to_target,
		(
			"and the authored mix survives the fight: %.1f THERMAL against %.1f KINETIC"
			% [_contact.thermal_to_target, _contact.kinetic_to_target]
		)
	)


## §15.5's whole claim, asserted as the thing a fight can settle and a frozen
## fixture cannot: contact is [b]held[/b] rather than collected one swing at a
## time.
##
## The pigeonhole is the swing count. A discrete swing costs
## `wind_up_s + swing_duration_s + recovery_s` — 0.96 s, or 58 ticks — so a build
## that could only ever strike has an upper bound on the ticks it can resolve on,
## and it is far below the ticks it spends in contact. More contact ticks than
## swings started is the sustained law and nothing else.
func test_contact_is_held_rather_than_struck() -> void:
	await _run()
	if not check_true(
		_contact.contact_ticks > 0, "the edge resolved against the target at all"
	):
		return
	check_true(
		_contact.energised_ticks > 0,
		"§15.5 pinned the edge at the end of its arc for %d ticks"
			% _contact.energised_ticks
	)
	check_true(
		_contact.contact_ticks > _contact.swings_started,
		(
			"and it cut on %d ticks against %d swing(s) started, so the contact was held"
			% [_contact.contact_ticks, _contact.swings_started]
		)
	)


## §15.4's impulse against the reach that delivered it, which is the question
## `test_held_weapon` cannot ask because it freezes its target for the whole of
## the phase this one measures.
##
## §15.5 says an instalment carries no impulse, and that sentence had never been
## asserted anywhere: a frozen body absorbs sixty impulses a second and reports
## nothing, so the planted fault that deletes the rule survived the sweep that
## found it. Here the target is live, is standing on its own contacts, and is
## being leaned on by a four-tonne Assembly — and it moves at seven centimetres a
## second. See [constant TARGET_PEAK_SPEED_MPS] for what the fault does to that.
func test_a_held_edge_does_not_throw_what_it_is_cutting() -> void:
	await _run()
	if not check_true(_contact.contact_ticks > 0, "the edge made contact to hold"):
		return
	check_true(
		_contact.target_peak_speed_mps < TARGET_PEAK_SPEED_MPS,
		(
			"the target never exceeded %.2f m/s over the whole phase, so what reached "
			% _contact.target_peak_speed_mps
			+ "it was contact and not §15.4's per-swing impulse"
		)
	)
	check_true(
		_contact.reopened_m < CONTACT_REOPEN_M,
		(
			"the range never re-opened by more than %.2f m after the first cut"
			% _contact.reopened_m
		)
	)
	check_true(
		_contact.final_range_m < CONTACT_RANGE_M,
		(
			"and the two were still hull to hull at %.1f m when the window closed"
			% _contact.final_range_m
		)
	)


## Doc 07 §15 resolves by swept volume and spends nothing. Asserted through the
## store, which is the only thing that can tell a module that swung from one that
## shot.
func test_the_edge_spends_no_ammunition() -> void:
	await _run()
	check_eq(
		_contact.edge_rounds_remaining,
		LOADED_ROUNDS,
		"not one round left the melee build's store over the whole phase"
	)


## ===== THE DUEL ========================================================


## Asserted as it behaves, with the numbers that explain it. §9: a finding left in
## prose gets re-litigated and one left in a test does not.
func test_the_gunner_wins_the_duel() -> void:
	await _run()
	if not check_true(
		_duel.decided,
		"the duel reached a decision in %d ticks" % _duel.ticks
	):
		return
	check_false(
		_duel.edge_survived,
		(
			"the gunner wins: %d rounds for %.0f integrity, against %.0f the edge "
			% [_duel.target_shots, _duel.damage_to_edge, _duel.damage_to_target]
			+ "took off in return"
		)
	)


## [b]The finding, and it is doc 05 §13's rather than doc 07 §15's.[/b] Over thirty
## metres, under fire, the melee build does not merely fail to arrive — it
## **loses ground**, finishing 31.9 m from a target it started 30.0 m from.
##
## The edge is not what fails here. Given something to walk at, the same build
## closes and cuts (every assertion above). What it cannot do is close on a target
## while being shot at, and that is §3.1.3's open defect seen from a new angle: a
## walking Assembly's steering demand reaches only the correction term of §13.5's
## placement law, so a heading it is asked to hold is a heading it drifts off.
## Recorded here rather than in prose because a finding left in prose gets
## re-litigated (§9).
##
## The `effector_lost` half is recorded and deliberately not asserted. When this
## recipe was wheeled it lost its arm and blade at t=37 and the reading was "a held
## module is the first thing a round meets" — which is still true and is still the
## reason a melee build wants armour in front of its arms. It is simply no longer
## what kills this one: the walker dies at 30 m with its arms intact, because it
## never brings them anywhere.
func test_the_walker_cannot_close_on_something_that_is_shooting() -> void:
	await _run()
	check_true(
		_duel.closest_range_m > CONTACT_RANGE_M,
		(
			"it never got inside its own reach: %.1f m at the closest, against the "
			% _duel.closest_range_m + "%.1f m it needs" % CONTACT_RANGE_M
		)
	)
	check_true(
		_duel.final_range_m > DUEL_SEPARATION_M,
		(
			"and finished further out than it started: %.1f m against %.1f"
			% [_duel.final_range_m, DUEL_SEPARATION_M]
		)
	)


## The layout's own cost, asserted as it stands because a player building this
## would meet it in the first second.
##
## **Two arms and two blades are 1434 kg carried ahead of and above a walking
## torso, and the machine leans on it: 29.6° nose-down.** It stays up — every foot
## keeps finding the ground and it never goes onto a flank — but it walks at a
## pronounced stoop, and that is a third of the way to the 90° that would put its
## blades in the dirt.
##
## The wheeled version of this recipe answered the same problem with an Energy
## Cell in the tail as ballast. That is not available here: four limbs and two arms
## are 31 of the ambulatory chassis's 34 mounts, and doc 01 §7.1 will not let the
## arms move to a hull with more of them. The candidates are a lighter Appendage
## tier, a shorter blade, or a chassis with the mounts for a counterweight — all
## three are data, and none is measured.
func test_the_walker_stoops_under_its_own_arms() -> void:
	await _run()
	check_true(
		_contact.worst_nose_down_deg > 15.0,
		(
			"1434 kg of arms and blades pitches the walker %.1f degrees nose-down, "
			% _contact.worst_nose_down_deg
			+ "which is the layout's cost and is asserted as it stands"
		)
	)
	check_true(
		_contact.worst_nose_down_deg < 45.0,
		"and it is a stoop rather than a fall: still under 45 degrees"
	)
	check_true(
		_contact.worst_roll_deg < 90.0,
		"and it never went onto a flank: %.1f degrees of roll" % _contact.worst_roll_deg
	)


## ===== THE RUNS ========================================================


## Both phases, run once, recorded, and asserted from by every method above (§9).
## A fight is destructive and cannot be repeated.
##
## One arena at a time, and each is closed the moment its record is taken — fact
## 45 and fact 48. Two arenas open together would put the duel inside the contact
## phase's wreckage and every number either of them reports would be a mixture.
func _run() -> void:
	if _ran:
		return
	_ran = true
	_contact = await _fight(CONTACT_SEPARATION_M, 0, CONTACT_TICKS, "contact")
	_duel = await _fight(DUEL_SEPARATION_M, LOADED_ROUNDS, DUEL_TICKS, "duel")


## One engagement: a [constant CombatArena.Recipe.MELEE] build against a
## [constant CombatArena.Recipe.WHEELED_LIGHT] one [param separation_m] apart, the
## second of them carrying [param target_rounds].
##
## It runs its own loop over [method CombatArena.tick_once] rather than calling
## [method CombatArena.engage], because §15.5 is a per-tick law and the stage
## machine that says whether the edge is in contact is only readable between
## physics frames.
func _fight(
	separation_m: float, target_rounds: int, max_ticks: int, label: String
) -> Phase:
	_arena = CombatArena.new()
	_arena.open()

	var edge_xz := Vector2(0.0, separation_m * 0.5)
	var target_xz := Vector2(0.0, -separation_m * 0.5)
	var edge := _arena.spawn(
		CombatArena.Recipe.MELEE,
		0,
		edge_xz,
		CombatArena.yaw_towards(edge_xz, target_xz),
		LOADED_ROUNDS
	)
	var target := _arena.spawn(
		CombatArena.Recipe.WHEELED_LIGHT,
		1,
		target_xz,
		CombatArena.yaw_towards(target_xz, edge_xz),
		target_rounds
	)
	await _arena.settle(SETTLE_TICKS)

	var rec := Phase.new()
	rec.edge_assembly_id = edge.assembly_id()
	rec.target_assembly_id = target.assembly_id()
	rec.closest_range_m = _flat_range(edge, target)

	var state := edge.guns.strike_state(edge.gun_slot)
	var previous := MeleeStrikeState.Stage.READY
	var thermal_seen := 0.0
	for i: int in max_ticks:
		await _arena.tick_once()
		rec.ticks += 1
		rec.closest_range_m = minf(rec.closest_range_m, _flat_range(edge, target))
		# Sampled here rather than read off [member CombatArena.Combatant.peak_speed_mps]
		# because that one starts at the spawn, and every recipe here is dropped two
		# metres onto the slab — the settle's own fall would be the peak.
		rec.target_peak_speed_mps = maxf(
			rec.target_peak_speed_mps, target.runtime.body.linear_velocity.length()
		)
		if state != null:
			if state.stage == MeleeStrikeState.Stage.WIND_UP and previous != state.stage:
				rec.swings_started += 1
			if state.energised:
				rec.energised_ticks += 1
			previous = state.stage
		# A tick on which the edge took THERMAL integrity off the target. Read off
		# the arena's per-channel running total rather than off a signal this file
		# connects: the target is also being driven into, and an IMPACT packet is
		# not a cut.
		var thermal := _arena.damage_through(
			rec.target_assembly_id, PartEnums.DamageChannel.THERMAL
		)
		if thermal > thermal_seen:
			rec.contact_ticks += 1
			thermal_seen = thermal
			if rec.range_at_first_cut_m == INF:
				rec.range_at_first_cut_m = _flat_range(edge, target)
		# How far the range ever recovers after the edge has first cut something,
		# which is the whole of §15.5's "no impulse" claim seen from the outside.
		if rec.range_at_first_cut_m < INF:
			rec.reopened_m = maxf(
				rec.reopened_m, _flat_range(edge, target) - rec.closest_range_m
			)
		if _arena.teams_standing().size() <= 1:
			break
	_arena.stand_down()

	rec.decided = _arena.teams_standing().size() <= 1
	rec.edge_survived = edge.is_alive()
	rec.final_range_m = _flat_range(edge, target)
	rec.damage_to_target = float(_arena.damage_by_target.get(rec.target_assembly_id, 0.0))
	rec.damage_to_edge = float(_arena.damage_by_target.get(rec.edge_assembly_id, 0.0))
	rec.thermal_to_target = _arena.damage_through(
		rec.target_assembly_id, PartEnums.DamageChannel.THERMAL
	)
	rec.kinetic_to_target = _arena.damage_through(
		rec.target_assembly_id, PartEnums.DamageChannel.KINETIC
	)
	rec.target_shots = int(_arena.shots_by.get(rec.target_assembly_id, 0))
	rec.edge_rounds_remaining = _arena.ammo.rounds_stored(
		rec.edge_assembly_id, _arena.projectile_registry.id_of(CombatArena.ROUND_KEY)
	)
	rec.effector_lost = _arena.destroyed.has(Vector2i(rec.edge_assembly_id, edge.gun_slot))
	rec.worst_nose_down_deg = edge.worst_nose_down_deg
	rec.worst_roll_deg = edge.worst_roll_deg

	for line: String in _arena.timeline:
		print("      %s" % line)
	print(
		(
			"  melee %s: closed %.1f -> %.1f m in %d ticks; %d swing(s), %d energised "
			% [label, separation_m, rec.closest_range_m, rec.ticks, rec.swings_started,
				rec.energised_ticks]
		)
		+ (
			"ticks, %d ticks of contact for %.0f THERMAL / %.0f KINETIC; "
			% [rec.contact_ticks, rec.thermal_to_target, rec.kinetic_to_target]
		)
		+ (
			"target peaked at %.2f m/s and the range re-opened %.2f m; "
			% [rec.target_peak_speed_mps, rec.reopened_m]
		)
		+ (
			"the other build fired %d rounds for %.0f; edge %.1f deg nose-down, %.1f roll"
			% [rec.target_shots, rec.damage_to_edge, rec.worst_nose_down_deg,
				rec.worst_roll_deg]
		)
	)
	_close_arena()
	return rec


func _close_arena() -> void:
	if _arena == null:
		return
	_arena.close()
	_arena = null


## Horizontal range between two combatants, which is the range a driver's own
## tactic is written in.
static func _flat_range(a: CombatArena.Combatant, b: CombatArena.Combatant) -> float:
	var d := b.runtime.body.global_position - a.runtime.body.global_position
	return Vector2(d.x, d.z).length()


## What one phase left behind.
class Phase:
	extends RefCounted

	var edge_assembly_id: int = 0
	var target_assembly_id: int = 0
	var ticks: int = 0
	var decided: bool = false
	var edge_survived: bool = false
	var closest_range_m: float = INF
	var final_range_m: float = 0.0
	## Fastest the target was ever travelling once the engagement opened.
	var target_peak_speed_mps: float = 0.0
	## Range the first cut landed at, and the most the range ever recovered after
	## it — the pair §15.5's "an instalment carries no impulse" is read through.
	var range_at_first_cut_m: float = INF
	var reopened_m: float = 0.0
	## Swings the stage machine started, and ticks §15.5 held the edge energised.
	var swings_started: int = 0
	var energised_ticks: int = 0
	## Ticks on which the edge took THERMAL integrity off the target.
	var contact_ticks: int = 0
	var damage_to_target: float = 0.0
	var damage_to_edge: float = 0.0
	var thermal_to_target: float = 0.0
	var kinetic_to_target: float = 0.0
	var target_shots: int = 0
	var edge_rounds_remaining: int = 0
	## True when the melee build's own Effector Module was destroyed.
	var effector_lost: bool = false
	var worst_nose_down_deg: float = 0.0
	var worst_roll_deg: float = 0.0
