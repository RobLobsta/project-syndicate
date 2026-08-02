extends TestCase
## A round travelling at 940 metres per second, moving four centimetres in a
## tick, resolving its full damage against the same Core Module on every one of
## them until that Core Module is gone.
##
## [b]This file records a defect. It does not fix one.[/b] Everything below is
## asserted as it behaves, so that the day it changes something fails and says
## so — the alternative is a finding in prose, and a finding in prose gets
## re-litigated.
##
## [b]What doc 07 §12.2 specifies.[/b] A round that defeats what it hit does not
## expire. Its position is moved to the impact point plus two centimetres and the
## function returns, so the round carries on into whatever is behind — and the
## document gates that on a penetration budget:
##
## [codeblock]
## if def.penetrates_after_hit and _penetration_budget(i, def, hit) > 0.0:
##     _position[i] = hit.position + _velocity[i].normalized() * 0.02
##     return                                     # continue through the target
## [/codeblock]
##
## [b]What the code does.[/b] [ProjectileSystem] is faithful to every line of
## that except the budget, which the document calls for by name and defines
## nowhere. In its place it asks whether the packet was applied — and a
## penetrator that beat the armour once beats it again, so the answer is yes for
## as long as there is anything left to damage.
##
## [b]What that costs.[/b] The sweep runs once per tick, and the reposition ends
## the tick: the round advances two centimetres instead of the 15.7 m its
## velocity carries, and the remainder of the segment is thrown away. A round
## that stalls inside a hull therefore does not pass through it — it grinds, at
## roughly a metre a second, resolving a full-damage packet against whatever it
## is inside on every tick of the way. One round rated 120 damage takes a Core
## Module rated 1450 down to zero in ten ticks.
##
## [b]Why this is Invariant I-12 and not a balance question.[/b] I-12 requires
## every reaction that can be triggered repeatedly to carry an explicit bound,
## and tabulates eight of them. Overpenetration is a repeatable reaction with no
## bound at all: nothing counts the penetrations, nothing stops a round resolving
## against a slot it has already resolved against, and the only thing that ends
## it is the projectile's own life timer. The document knew — it wrote a budget
## into the gate — and the budget never got a definition to implement.
##
## Closing it is an amendment to doc 07 §12.2 and then a change to
## [ProjectileSystem], in that order, and CLAUDE.md §10 rule 13 puts both outside
## what a test file may decide. What this file does is make the cost visible.
##
## [b]The pairing is the one that reproduces it.[/b] An ambulatory Assembly
## firing up at a hovering rotary one, which is the first engagement in
## [code]tests/physics/test_family_duels.gd[/code]. Two frozen wheeled builds
## trading level shots at the same range do [i]not[/i] reproduce it: there, a
## round penetrates the Effector Module, resolves once more against the Core
## Module behind it on the following tick, and leaves. Whatever decides between
## the two is geometric, and finding out which geometry stalls a round is part of
## the work this file is handing over.

const SETTLE_TICKS: int = 180
## Ticks the engagement is watched for. The grind takes about ten once it starts;
## this is long enough to include the approach that sets it up.
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
## Consecutive stalled ticks that make it a grind rather than a rounding error.
const GRIND_TICKS: int = 3

## Packets one round may reasonably resolve against one part. One is the hit;
## the allowance is for the entry and exit faces of a single collider.
const SANE_PACKETS_PER_SLOT: int = 2

var _arena: CombatArena = null
var _shooter: CombatArena.Combatant = null
var _target: CombatArena.Combatant = null
var _measured: bool = false

## Longest run of consecutive ticks a single round spent stalled, and how fast it
## claimed to be going while it did.
var _longest_stall_ticks: int = 0
var _stalled_speed_mps: float = 0.0
var _stalled_step_m: float = 0.0
## Damage packets resolved against the target's Core Module, and the ticks they
## arrived on.
var _core_packets: int = 0
var _core_packet_ticks: Dictionary = {}
var _target_core_destroyed: bool = false


func after_all() -> void:
	if EventBus.part_damaged.is_connected(_on_part_damaged):
		EventBus.part_damaged.disconnect(_on_part_damaged)
	if _arena != null:
		_arena.close()
		_arena = null


func test_a_round_in_flight_advances_centimetres_in_a_tick() -> void:
	# The assertion that cannot be argued with, and the one that does not depend
	# on any damage number: the round reports a speed, and the distance it
	# actually covered in a tick is nowhere near that speed times the tick.
	await _measure()
	check_true(
		_longest_stall_ticks >= GRIND_TICKS,
		(
			"a round stalled for %d consecutive ticks while reporting %.0f m/s"
			% [_longest_stall_ticks, _stalled_speed_mps]
		)
	)
	check_true(
		_stalled_speed_mps > IN_FLIGHT_MPS,
		"it was still in flight, not expiring: %.0f m/s" % _stalled_speed_mps
	)
	check_true(
		_stalled_step_m < STALL_STEP_M,
		(
			"and it advanced %.3f m in the tick, against the %.1f m its velocity carries"
			% [_stalled_step_m, _stalled_speed_mps * SyndicateConstants.PHYSICS_DT]
		)
	)


func test_the_stalled_round_resolves_a_packet_every_tick_it_is_stalled() -> void:
	# The consequence. Doc 08 has no notion of a round hitting the same part
	# twice, and every multiplier in §4 is written for a single impact, so this
	# is a part taking its full penetration damage at 60 Hz.
	await _measure()
	check_true(
		_core_packets > SANE_PACKETS_PER_SLOT,
		(
			"the target's Core Module took %d separate packets across %d ticks"
			% [_core_packets, _core_packet_ticks.size()]
		)
	)
	check_true(
		_core_packet_ticks.size() >= GRIND_TICKS,
		"spread over the ticks of the grind rather than arriving together"
	)


func test_it_is_enough_to_destroy_a_core_module_outright() -> void:
	# Stated in the terms a balance reviewer would use: the round is authored at
	# 120 damage and the Core Module at 1450, which is a dozen clean hits, and
	# this is one round.
	await _measure()
	check_true(
		_target_core_destroyed,
		"the Core Module was destroyed during the grind"
	)


## ===== FIXTURES ========================================================


## Runs the engagement once and records what the projectile pool did, tick by
## tick.
##
## Nothing is frozen and nothing is aimed by hand. The pairing reproduces the
## stall on its own, and holding either Assembly still is exactly the change that
## stops reproducing it — which is itself the reason the geometry question in the
## class docstring is still open.
func _measure() -> void:
	if _measured:
		return
	_measured = true

	_arena = CombatArena.new()
	_arena.open()
	var at := Vector2(0.0, SEPARATION_M * 0.5)
	var bt := Vector2(0.0, -SEPARATION_M * 0.5)
	_shooter = _arena.spawn(
		CombatArena.Recipe.AMBULATORY, 0, at, CombatArena.yaw_towards(at, bt),
		AmmoLedger.UNLIMITED
	)
	# Both armed. Disarming the target looks like it ought to simplify the trace
	# and instead stops reproducing the stall: the two Assemblies push each other
	# around, and the geometry that catches a round only occurs while they are
	# both manoeuvring under fire. That sensitivity is the finding's shape, not a
	# flaw in the fixture, and it is why the pairing is named rather than reduced.
	_target = _arena.spawn(
		CombatArena.Recipe.ROTARY, 1, bt, CombatArena.yaw_towards(bt, at),
		AmmoLedger.UNLIMITED
	)
	await _arena.settle(SETTLE_TICKS)

	EventBus.part_damaged.connect(_on_part_damaged)
	var previous := {}
	var stalled := {}
	for i: int in WATCH_TICKS:
		_arena.command(_shooter)
		_arena.command(_target)
		await physics_frames(1)
		_sample_pool(previous, stalled)
		if not _target.is_alive():
			break
	EventBus.part_damaged.disconnect(_on_part_damaged)
	_target_core_destroyed = _target.runtime.states[SyndicateConstants.CORE_SLOT].has_flag(
		PartFlags.FLAG_DESTROYED
	)
	print(
		(
			"  overpenetration: longest stall %d ticks at %.0f m/s moving %.3f m/tick, "
			+ "%d packets on the Core Module"
		)
		% [_longest_stall_ticks, _stalled_speed_mps, _stalled_step_m, _core_packets]
	)
	_arena.close()
	_arena = null


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
				_stalled_step_m = step
		else:
			stalled[index] = 0


func _on_part_damaged(assembly_id: int, slot: int, _amount: float, _channel: int) -> void:
	if assembly_id != _target.assembly_id() or slot != SyndicateConstants.CORE_SLOT:
		return
	_core_packets += 1
	_core_packet_ticks[MatchClock.tick] = true
