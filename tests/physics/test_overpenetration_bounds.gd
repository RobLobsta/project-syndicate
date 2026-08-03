extends TestCase
## An armour-piercing round crossing an Assembly in the tick it arrives in,
## damaging each part it defeats exactly once, and leaving.
##
## [b]This file used to record a defect and now guards the fix.[/b] Session 15
## measured a round reporting 938 m/s advancing 0.040 m per tick for nine
## consecutive ticks, resolving a full 147.9-damage packet against the same Core
## Module on every one of them: one round rated 120 damage took a Core Module
## rated 1450 to zero. It decided five of that session's six engagements. The
## assertions below are the inverse of the ones that recorded it, written so the
## grind cannot come back without something here failing.
##
## [b]What was wrong.[/b] Doc 07 §12.2 said a round that defeats what it hit is
## repositioned to the impact point plus two centimetres and the function
## [i]returns[/i], gated on a `_penetration_budget` the document named and never
## defined. [ProjectileSystem] implemented every line except the budget and
## substituted "was the packet applied" — a question a penetrator answers yes to
## for as long as there is anything left to damage. And the reposition ended the
## tick: a stalled round advanced two centimetres instead of the 15.7 m its
## velocity carried, and the rest of the segment was discarded. Once per tick.
##
## [b]What replaced it[/b] (doc 07 §12.2, §12.2.1, §12.2.2):
##
## [enum]
## [*] The sweep runs over [b]the whole tick's travel[/b], not the first hit in
##     it. A round that penetrates continues inside the same tick, so a 3 m hull
##     costs it a fifth of a tick rather than a hundred and fifty of them.
## [*] [b]One part, one packet.[/b] A round never resolves twice against the same
##     `(assembly_id, slot)`. Every multiplier in doc 08 §4 is written for a
##     single impact, and there is no reading of any of them under which one
##     projectile strikes one Structural Component twice.
## [*] [b]Two Invariant I-12 bounds[/b], now in its table:
##     [constant ProjectileSystem.MAX_PENETRATIONS] parts of damage and
##     [constant ProjectileSystem.MAX_SWEEP_SEGMENTS] queries of work per tick.
## [/enum]
##
## [b]The pairing is the one that used to reproduce the grind[/b] — an ambulatory
## Assembly firing up at a hovering rotary one, both live, both manoeuvring —
## kept exactly as it was, so this file is a before-and-after of one fixture
## rather than of two.

const SETTLE_TICKS: int = 180
## Ticks the engagement is watched for.
const WATCH_TICKS: int = 240

## Metres the two start apart.
const SEPARATION_M: float = 24.0

## Speed, in m/s, above which a round is unambiguously in flight rather than
## expiring. Half the authored muzzle velocity.
const IN_FLIGHT_MPS: float = 470.0
## Metres a round may advance in one tick and still count as stalled. A round at
## [constant IN_FLIGHT_MPS] covers 7.8 m in a tick, so this is two orders of
## magnitude short of what its own velocity says it should have done.
const STALL_STEP_M: float = 0.20
## Consecutive stalled ticks that would make it a grind rather than a rounding
## error. The measurement this file replaces reached nine.
const GRIND_TICKS: int = 3

## ===== THE PENETRATION-BOUND FILE ======================================
## A second fixture, and a static one. See [method _measure_budget].

## Hulls in the file. Three heavy builds put six parts on the centreline against
## a bound of four, which is the smallest arrangement that can reach it.
const FILE_DEPTH: int = 3
## Metres between them. Wide enough that no two hulls touch and the round is in
## clear air between each pair; narrow enough that the whole file is inside two
## ticks of travel.
const FILE_SPACING_M: float = 13.0
## Metres behind the leading hull the round starts, and metres past the last one
## the line of fire is aimed at.
const MUZZLE_STAND_OFF_M: float = 6.0
const OVERSHOOT_M: float = 10.0
## Muzzle velocity, in m/s, matching §10.5's autocannon. 15.7 m per tick.
const MUZZLE_MPS: float = 940.0
## Ticks the one round is watched for. Four ticks of travel covers 63 m against
## a 42 m file, so a round still alive at the end never met the bound.
const FLIGHT_TICKS: int = 4
## Segments [method _count_parts_on_line] will probe before giving up. Well past
## [constant ProjectileSystem.MAX_SWEEP_SEGMENTS], because this walk is counting
## what is there rather than modelling what a round may do about it.
const LINE_PROBE_SEGMENTS: int = 24
## Stride for packing `(assembly_id, slot)` into one key, as
## [ProjectileSystem] does.
const PARTS_PER_ASSEMBLY: int = 256

var _measured: bool = false
var _arena: CombatArena = null
var _shooter: CombatArena.Combatant = null
var _target: CombatArena.Combatant = null

## Longest run of consecutive ticks any single round spent stalled.
var _longest_stall_ticks: int = 0
var _stalled_speed_mps: float = 0.0
## Damage packets resolved against the target, by slot.
var _packets_by_slot: Dictionary = {}
var _packets_total: int = 0
## Most distinct parts of the target struck within one tick.
var _widest_tick: int = 0
var _target_core_destroyed: bool = false
var _core_integrity_left: float = 0.0
var _core_integrity_max: float = 0.0

## Slots struck this tick, cleared at the top of every one. Its size is how many
## distinct parts the tick's rounds got through, which is the observable that
## says overpenetration still happens at all.
var _this_tick: Dictionary = {}

var _budget_measured: bool = false
## Packets the one hand-fired round of [method _measure_budget] resolved, the
## distinct `(assembly, slot)` pairs they landed on, how many separate ticks
## carried at least one of them, and how many parts its line of fire crossed.
var _budget_packets: int = 0
## Distinct `(assembly, slot)` keys in the round's strike record. Equal to
## [member _budget_packets] exactly when §12.2.1 held.
var _budget_slots: Dictionary = {}
var _budget_ticks_damaging: int = 0
var _budget_parts_on_line: int = 0
## Whether the round was retired rather than left flying with parts still ahead
## of it, which is the other half of "the bound stopped it".
var _budget_spent: bool = false


func after_all() -> void:
	if EventBus.part_damaged.is_connected(_on_part_damaged):
		EventBus.part_damaged.disconnect(_on_part_damaged)
	if _arena != null:
		_arena.close()
		_arena = null


func test_no_round_stalls_inside_a_hull() -> void:
	# The assertion that depends on no damage number at all, and the direct
	# inverse of the one this file used to make. A round reports a speed; the
	# distance it covers in a tick has to be consistent with that speed.
	await _measure()
	check_true(
		_longest_stall_ticks < GRIND_TICKS,
		(
			"the longest any round spent going nowhere was %d ticks, at %.0f m/s"
			% [_longest_stall_ticks, _stalled_speed_mps]
		)
	)


func test_damage_is_spread_across_the_hull_rather_than_piled_on_one_part() -> void:
	# §12.2.1's observable consequence. Asserted per slot rather than in
	# aggregate: a total is satisfied by one round getting through four parts and
	# by four rounds hitting one part four times, and only the second is the
	# defect. The grind's signature was one slot soaking nearly every packet in
	# the engagement while its neighbours took none.
	await _measure()
	check_true(_packets_total > 0, "rounds landed: %d packets" % _packets_total)
	check_true(
		_packets_by_slot.size() > 1,
		"across %d distinct parts of the target" % _packets_by_slot.size()
	)


func test_a_round_still_overpenetrates() -> void:
	# The rejection half, and the one that matters most. Bounding a reaction by
	# switching it off is not a fix: doc 07 §12.2 wants an armour-piercing round
	# to carry on into what is behind, and the `no-overpenetration` sweep fault
	# showed that turning it off makes nothing in the shipped set lethal at all.
	#
	# Two parts struck inside one tick is the signature that has to survive: the
	# round defeats the Effector Module on the nose and resolves again against
	# what is behind it, in the same tick, which is what "continues through the
	# target" is supposed to mean. Before the fix that second packet arrived on
	# the *following* tick, because the reposition ended the first one.
	await _measure()
	check_true(
		_widest_tick >= 2,
		"a round resolved against %d parts inside a single tick" % _widest_tick
	)


func test_one_round_no_longer_destroys_a_core_module() -> void:
	# Stated in the terms a balance reviewer would use. The round is authored at
	# 120 damage and a Core Module at 1450, which is a dozen clean hits. Before
	# the bound it took one; this engagement fires dozens, and the assertion is
	# that the Core Module's fate is decided by volume of fire.
	await _measure()
	var core_packets := int(_packets_by_slot.get(SyndicateConstants.CORE_SLOT, 0))
	if _target_core_destroyed:
		check_true(
			core_packets > 2,
			"the Core Module died to %d separate packets, not to one" % core_packets
		)
	else:
		check_true(
			_core_integrity_left < _core_integrity_max,
			(
				"the Core Module was hit and survived: %.0f of %.0f left"
				% [_core_integrity_left, _core_integrity_max]
			)
		)


func test_one_round_stops_at_the_authored_penetration_bound() -> void:
	# The ceiling, and the reason this method exists rather than another
	# assertion on the engagement above.
	#
	# A fault sweep removed [constant ProjectileSystem.MAX_PENETRATIONS] outright
	# — `if resolved >= budget` replaced with `if false` — and the whole suite
	# stayed green. Not because the bound is wrong but because nothing in it ever
	# reached the bound: a round crossing one hull gets through two or three parts
	# and stops for want of anything else to hit, so a limit of four and no limit
	# at all are the same limit. A bound is only tested by geometry that exceeds
	# it.
	#
	# So this fires one round down a file of three hulls, with six parts on the
	# line, and the round is spawned directly rather than by an Effector Module:
	# no bloom cone, no aim solver, no jam roll, one trajectory, one answer.
	await _measure_budget()
	# First, that the fixture can fail. Everything below is unfalsifiable if the
	# line of fire crosses four parts or fewer.
	check_true(
		_budget_parts_on_line > ProjectileSystem.MAX_PENETRATIONS,
		(
			"the file puts %d parts on the line, more than the bound of %d"
			% [_budget_parts_on_line, ProjectileSystem.MAX_PENETRATIONS]
		)
	)
	check_eq(
		_budget_packets,
		ProjectileSystem.MAX_PENETRATIONS,
		(
			"one round crossing %d parts on the line resolved against %d of them"
			% [_budget_parts_on_line, _budget_packets]
		)
	)
	# And it has to bind across the tick boundary, not inside one. At 940 m/s the
	# round covers 15.7 m per tick and the file is 26 m deep, so it crosses the
	# first hull on one tick and the other two on the next. A budget counted from
	# zero at the top of every tick would let this round resolve four packets and
	# then four more; §12.2.2 spends it over the round's life, and the only way to
	# see the difference is a target array deeper than one tick of travel.
	check_true(
		_budget_ticks_damaging > 1,
		"and it did so over %d ticks, not inside one" % _budget_ticks_damaging
	)
	# And it was retired for spending its budget, not left flying. A round that
	# reached four and carried on would satisfy the count above on the tick it was
	# sampled and go on doing damage afterwards.
	check_true(_budget_spent, "and the round was retired rather than left in flight")
	# §12.2.1, on the same shot: four strikes against four different parts.
	#
	# [b]This one cannot currently fail, and that is worth stating rather than
	# hiding.[/b] All twelve shipped `ColliderProfile`s carry exactly one convex
	# primitive, and the sweep queries with `hit_from_inside = false` from two
	# centimetres past each impact — so a straight ray physically cannot report
	# the same part twice, and `_already_struck` is a guard against geometry that
	# does not exist yet. Invariant I-1 permits three primitives per part; the day
	# one part ships with two along an axis, this assertion starts biting. It is
	# kept as the regression guard for that day, and the handoff records it as an
	# untested rule rather than a covered one.
	check_eq(
		_budget_slots.size(),
		_budget_packets,
		"against %d distinct parts, none of them struck twice" % _budget_slots.size()
	)


## ===== FIXTURES ========================================================


## Runs the engagement once and records what the projectile pool did, tick by
## tick.
func _measure() -> void:
	if _measured:
		return
	_measured = true

	_arena = CombatArena.new()
	_arena.open()
	var at := Vector2(0.0, SEPARATION_M * 0.5)
	var bt := Vector2(0.0, -SEPARATION_M * 0.5)
	# Two ground builds, and the pairing is deliberate after being wrong once.
	#
	# This was an AMBULATORY shooter against a ROTARY target, inherited from the
	# engagement §4.13's grind was first seen in. It should never have stayed: the
	# assertions below are about the projectile layer and say nothing about a
	# locomotion family, while the ambulatory build is the one the project already
	# records as a poor gun platform — it leans past its own 8° of depression and
	# was landing a single round in the whole window. Every measurement here rode
	# on that one round, and a small unrelated change to the shipped module's
	# footprint was enough to take it away and leave four assertions reading zero.
	#
	# A fixture whose subject is the round should not be gated on the hardest
	# platform in the game getting a shot off. WHEELED_LIGHT fires reliably from a
	# nose mount at the target's own height, and WHEELED_HEAVY carries the deeper
	# hull the penetration assertions want behind the first plate.
	_shooter = _arena.spawn(
		CombatArena.Recipe.WHEELED_LIGHT, 0, at, CombatArena.yaw_towards(at, bt),
		AmmoLedger.UNLIMITED
	)
	_target = _arena.spawn(
		CombatArena.Recipe.WHEELED_HEAVY, 1, bt, CombatArena.yaw_towards(bt, at),
		AmmoLedger.UNLIMITED
	)
	await _arena.settle(SETTLE_TICKS)

	EventBus.part_damaged.connect(_on_part_damaged)
	var previous := {}
	var stalled := {}
	for i: int in WATCH_TICKS:
		_this_tick.clear()
		_arena.command(_shooter)
		_arena.command(_target)
		await physics_frames(1)
		_sample_pool(previous, stalled)
		_widest_tick = maxi(_widest_tick, _this_tick.size())
		if not _target.is_alive():
			break
	EventBus.part_damaged.disconnect(_on_part_damaged)

	var core: PartInstanceState = _target.runtime.states[SyndicateConstants.CORE_SLOT]
	_target_core_destroyed = core.has_flag(PartFlags.FLAG_DESTROYED)
	_core_integrity_left = core.integrity
	_core_integrity_max = _target.runtime.definition_at(
		SyndicateConstants.CORE_SLOT
	).integrity_max
	print(
		(
			"  overpenetration bounds: longest stall %d ticks, %d packets over %d slots, "
			+ "widest single tick %d parts"
		)
		% [_longest_stall_ticks, _packets_total, _packets_by_slot.size(), _widest_tick]
	)
	_arena.close()
	_arena = null


## Fires exactly one round down a file of three stationary hulls and records
## what it got through.
##
## Deliberately not an engagement. Everything the two fixtures above are for —
## manoeuvre, aim convergence, spread, jam — is noise here, and a bound is a
## statement about one round's trajectory. So the round is handed straight to
## [method ProjectileSystem.spawn] on a line the targets' own Core Modules
## define, and the only thing that varies is what the sweep does with it.
func _measure_budget() -> void:
	if _budget_measured:
		return
	_budget_measured = true

	_arena = CombatArena.new()
	var arena := _arena
	arena.open()
	var targets: Array[CombatArena.Combatant] = []
	for i: int in FILE_DEPTH:
		targets.append(
			arena.spawn(
				# The heavy recipe, because its Energy Cell is the second part on
				# the centreline and three hulls of one part apiece would not reach
				# the bound either.
				CombatArena.Recipe.WHEELED_HEAVY, 1,
				Vector2(0.0, -FILE_SPACING_M * float(i)), 0.0, 0
			)
		)
	await arena.settle(SETTLE_TICKS)

	# The line of fire is the leading Core Module's own height, so it crosses
	# every hull through the part the recipe puts on the centreline rather than
	# through whatever happens to be at the body origin.
	var core: PartInstanceState = targets[0].runtime.states[SyndicateConstants.CORE_SLOT]
	var line_y := (
		targets[0].runtime.body.global_transform
		* LatticeMath.cell_to_local(core.origin_cell)
	).y
	var origin := Vector3(0.0, line_y, MUZZLE_STAND_OFF_M)
	var target_at := Vector3(0.0, line_y, -FILE_SPACING_M * float(FILE_DEPTH - 1) - OVERSHOOT_M)
	var direction := (target_at - origin).normalized()

	_budget_parts_on_line = _count_parts_on_line(arena, origin, target_at)

	var round_id := arena.projectile_registry.id_of(CombatArena.ROUND_KEY)
	var pooled := arena.projectiles.spawn(
		origin, direction * MUZZLE_MPS, round_id,
		# No owner: nothing here fired it, so §12.3's self-exclusion has nothing
		# to exclude and cannot quietly absorb a hit the bound should have.
		0, SyndicateConstants.INVALID_SLOT, RID()
	)
	# Read off the round's own strike record rather than off `part_damaged`.
	# Doc 08 §4.4 spalls behind every part a round defeats, and spall is
	# indistinguishable from a direct hit in the signal — the first version of
	# this fixture counted 18 packets across 13 slots from a single round and was
	# measuring the spall cone, not the bound.
	for i: int in FLIGHT_TICKS:
		var before := arena.projectiles.strikes_of(pooled)
		await physics_frames(1)
		if arena.projectiles.strikes_of(pooled) > before:
			_budget_ticks_damaging += 1
	_budget_packets = arena.projectiles.strikes_of(pooled)
	_budget_spent = not arena.projectiles.is_active(pooled)
	for key: int in arena.projectiles.struck_keys_of(pooled):
		_budget_slots[key] = true

	print(
		(
			"  penetration budget: %d parts on the line, %d resolved over %d ticks, "
			+ "round spent: %s"
		)
		% [_budget_parts_on_line, _budget_packets, _budget_ticks_damaging, _budget_spent]
	)
	arena.close()
	_arena = null


## Parts a straight ray from [param from] to [param to] would cross with no
## budget at all, counted the way the sweep counts them.
##
## This is what makes the ceiling assertion mean something: if the line crosses
## four parts or fewer then a bound of four is unreachable and the test would
## pass against no bound whatsoever, which is the exact failure it was written
## to close. Asserted rather than assumed.
func _count_parts_on_line(arena: CombatArena, from: Vector3, to: Vector3) -> int:
	var space := arena.projectiles.space
	var direction := (to - from).normalized()
	var seen := {}
	var cursor := from
	for i: int in LINE_PROBE_SEGMENTS:
		var params := PhysicsRayQueryParameters3D.create(cursor, to)
		params.collision_mask = CollisionLayers.MASK_PROJECTILE_TARGET
		params.hit_from_inside = false
		var hit := space.intersect_ray(params)
		if hit.is_empty():
			break
		cursor = Vector3(hit["position"]) + direction * ProjectileSystem.PENETRATION_STEP_M
		var body: Object = hit.get("collider")
		if not (body is ChassisBodyRef):
			continue
		var chassis := body as ChassisBodyRef
		var slot := chassis.slot_for_shape_index(int(hit.get("shape", -1)))
		if slot != SyndicateConstants.INVALID_SLOT:
			seen[chassis.assembly_id * PARTS_PER_ASSEMBLY + slot] = true
	return seen.size()


## One tick of the projectile pool, against the tick before it.
##
## [param previous] holds the last position seen for each live index and
## [param stalled] the run length of consecutive stalled ticks. An index that
## goes inactive drops out of both, so a recycled slot starts its own run rather
## than inheriting the previous round's.
func _sample_pool(previous: Dictionary, stalled: Dictionary) -> void:
	var pool := _arena.projectiles
	for index: int in ProjectileSystem.POOL_SIZE:
		if not pool.is_active(index):
			previous.erase(index)
			stalled.erase(index)
			continue
		var position := pool.position_of(index)
		var speed := pool.velocity_of(index).length()
		if not previous.has(index):
			previous[index] = position
			stalled[index] = 0
			continue
		var step: float = (position - Vector3(previous[index])).length()
		previous[index] = position
		if speed > IN_FLIGHT_MPS and step < STALL_STEP_M:
			stalled[index] = int(stalled[index]) + 1
			if int(stalled[index]) > _longest_stall_ticks:
				_longest_stall_ticks = int(stalled[index])
				_stalled_speed_mps = speed
		else:
			stalled[index] = 0


func _on_part_damaged(assembly_id: int, slot: int, _amount: float, _channel: int) -> void:
	if assembly_id != _target.assembly_id():
		return
	_packets_total += 1
	_packets_by_slot[slot] = int(_packets_by_slot.get(slot, 0)) + 1
	_this_tick[slot] = true
