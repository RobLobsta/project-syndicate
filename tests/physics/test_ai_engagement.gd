extends TestCase
## [AiDriver] in a real engagement — doc 05 §15.7 and doc 07 §10, end to end.
##
## Every other file that puts two Assemblies in front of each other drives them
## with [code]tests/combat_arena.gd[/code]'s test pilot. This one drives one side
## with [code]src/ai/[/code] and nothing else: a driver on
## [signal MatchClockService.tick_started], a scan at 2.9 Hz, a selector, and the
## same [EffectorSystem] a player's trigger reaches. The other side is parked and
## unarmed, which is exactly the state the match scene was in before this
## session and is therefore the control the finding is measured against.
##
## [b]It is deliberately a fight the AI should win.[/b] The question this file
## asks is not "who wins" — that is [code]test_family_duels.gd[/code]'s — but
## whether the chain from a registry scan to a round leaving a barrel closes at
## all: does it choose a target, turn toward it, close, converge a mount, open
## the gate, spend ammunition, and take integrity off something.
##
## The turn is the assertion worth the most. The attacker spawns facing
## [b]away[/b] from its target, because a driver whose steering sign is inverted
## drives away from what it is shooting at just as hard as a correct one drives
## toward it — and every assertion about rounds fired and damage landed passes
## against both, since the mount traverses 360°.

## The two builds, at each end of a separation wide enough that the attacker must
## drive to reach its stand-off. 40 m against a 6 m stand-off leaves 34 m of
## approach, which at the wheeled build's measured 4.45 m/s is about eight
## seconds — inside the window below with room for the fight itself.
const SEPARATION_M: float = 40.0

## Ticks for both builds to fall onto their contacts with the triggers cold.
const SETTLE_TICKS: int = 90
## Ticks of the approach measured on their own, before the rest of the fight.
## Long enough for a 180° turn at the wheeled build's steering rate and short
## enough that the range has not yet collapsed, so the two measurements below
## are of a turn and of a closure rather than of one thing twice.
const TURN_TICKS: int = 330
## Ticks the engagement then runs for. A parked unarmed target cannot end it, so
## this is the budget rather than the expected length.
const ENGAGE_TICKS: int = 600

## The store the attacker is given. Finite, so the ledger can be asserted as an
## equality against the shots fired (§9: a store that merely fell is satisfied by
## a module that double-charges every round).
const LOADED_ROUNDS: int = 400

## §10's difficulty, held at 1.0. This file is asking whether the chain closes,
## and a driver that misses by design would make every damage assertion below a
## measurement of the RNG. The error model itself is asserted in
## [code]tests/unit/test_ai_target_selector.gd[/code].
const DIFFICULTY: float = 1.0

## §10.2's arc penalty, by value, from doc 07 §10.
const ARC_COST_WEIGHT: float = 140.0
## Distance the two arc probes are placed at. Equal for both, so that the
## proximity term cancels out of the score difference and the arc term is the
## only thing left.
const ARC_PROBE_RANGE_M: float = 40.0

## Speed, in m/s, below which a driver counts as having arrived rather than as
## still going round.
##
## It is not tight because holding a stand-off is not holding still. §15.7.1's
## closing test is a hard range comparison, so a driver parked at its demand
## crosses it in both directions as the hull settles and the target drifts —
## throttle on, brake on, throttle on — and idles at a few metres a second rather
## than at zero. That is the law working, not an orbit, and the two are told
## apart by the round count below rather than by this.
##
## [b]It was 2.0, which was a description of the idle rather than a separation
## between the two states, and it broke on a change that cannot have touched
## it.[/b] Session 26 added an integration file that opens a match — four
## Assemblies spawned and freed before this file runs — and the measured arrival
## speed went from under 2 m/s to 3.86 with nothing in the AI or the motion layer
## changed. That is LEARNED_FACTS.md §1 fact 54 exactly: once several bodies
## share a space the solver's float ordering depends on the allocation history of
## the whole process, so a threshold sitting just above a measurement is a
## threshold that measures the suite.
##
## The bound is now half the 11 m/s this driver reaches on the approach, which is
## the state it has to be distinguished [i]from[/i]. Re-measuring and re-asserting
## 4.0 would have moved the fragility to whoever adds the next file.
const ARRIVED_SPEED_MPS: float = 5.5

## Rounds a driver that actually stopped at its stand-off must get away, against
## the one that an orbiting driver manages.
##
## An Assembly circling its target crosses its own stand-off once a lap, and
## §15.7.4 opens the trigger for exactly the moment it is inside — so "the AI
## fired" is satisfied by a driver that never stopped at all. Measured: one round
## without §15.7.1's arrival brake, eleven with it. Four sits three times below
## the one and four times above the other, which is as far from both as an
## engagement quantity this chaotic allows.
const ARRIVED_ROUNDS_FLOOR: int = 4

var _fought: bool = false
var _arena: CombatArena = null
var _engagement: Engagement = null


func after_all() -> void:
	if _arena != null:
		_arena.close()
		_arena = null


## ===== THE CHOICE ======================================================


func test_the_driver_selects_the_only_enemy_on_the_field() -> void:
	await _run()
	check_eq(
		_engagement.target_id_at_open,
		_engagement.target_assembly_id,
		"the first scan picked the one Assembly on the other team"
	)


## §10's first filter, through the real roster rather than a fabricated one. An
## AI that shot at its own side would be visible here as a target id that is its
## own.
func test_the_driver_never_selects_itself() -> void:
	await _run()
	check_ne(
		_engagement.target_id_at_open,
		_engagement.attacker_assembly_id,
		"and it is not the attacker itself"
	)


## ===== §15.7.1's TURN ==================================================


## The sign of the whole chain, from a bearing through a steering demand through
## a steered contact to a hull that yawed.
##
## The fixture assertion comes first and is not decoration: if the attacker did
## not in fact spawn facing away, every number after it is satisfied by a build
## that never turned at all.
func test_the_attacker_turns_toward_a_target_behind_it() -> void:
	await _run()
	check_true(
		_engagement.bearing_at_open_deg > 150.0,
		"the attacker spawned facing away: %.1f degrees of error"
		% _engagement.bearing_at_open_deg
	)
	check_true(
		_engagement.bearing_after_turn_deg < 30.0,
		(
			"and drove itself onto the bearing: %.1f degrees after %d ticks"
			% [_engagement.bearing_after_turn_deg, TURN_TICKS]
		)
	)


func test_the_attacker_closes_on_its_target() -> void:
	await _run()
	check_true(
		_engagement.range_at_open_m > SEPARATION_M * 0.75,
		"the fixture opened at range: %.1f m" % _engagement.range_at_open_m
	)
	check_true(
		_engagement.closest_range_m < AiDriver.GROUND_STAND_OFF_M * 2.0,
		(
			"and closed to inside twice its stand-off: %.1f m against %.1f m"
			% [_engagement.closest_range_m, AiDriver.GROUND_STAND_OFF_M]
		)
	)


## It stops rather than ramming, and it [b]stops[/b] rather than orbiting.
##
## The range assertions alone were not enough and are kept company for a reason.
## Under an earlier throttle law the driver arrived at its stand-off at 11 m/s,
## ran through to 3.1 m, was outside it again a second later and set off on
## another lap — and every range assertion in this file passes against that, as
## does "the AI fired", because an orbiting driver gets a round off each time it
## crosses its own boundary. The round count below is what tells the two apart.
func test_the_attacker_stops_rather_than_driving_through() -> void:
	await _run()
	check_true(
		_engagement.final_range_m > 1.0,
		"it did not end up inside the target: %.1f m" % _engagement.final_range_m
	)
	check_true(
		_engagement.final_range_m < AiDriver.GROUND_STAND_OFF_M * 2.0,
		"and it held its stand-off rather than wandering off it: %.1f m against %.1f"
		% [_engagement.final_range_m, AiDriver.GROUND_STAND_OFF_M]
	)
	check_true(
		_engagement.final_speed_mps < ARRIVED_SPEED_MPS,
		(
			"and it was stopped when the engagement closed, not on another lap: %.2f m/s"
			% _engagement.final_speed_mps
		)
	)
	# The speed above is a sample and an orbiting driver is slow twice a lap, so
	# it does not separate the two states on its own — measured, it passes for
	# both. What does is how much shooting the driver got done once it arrived,
	# and it is the assertion that closed session 23's `aim-point-read-from-scan`
	# survivor as well: a driver aiming at a 350 ms stale point cannot hold a
	# solution from a standstill either, and gets two rounds away instead of nine.
	check_true(
		_engagement.attacker_shots >= ARRIVED_ROUNDS_FLOOR,
		(
			"and it stayed there long enough to use the gun: %d rounds against a floor of %d"
			% [_engagement.attacker_shots, ARRIVED_ROUNDS_FLOOR]
		)
	)


## ===== FIRING ==========================================================


func test_the_attacker_opens_fire_and_the_parked_target_does_not() -> void:
	await _run()
	check_true(
		_engagement.attacker_shots > 0, "the AI fired: %d rounds" % _engagement.attacker_shots
	)
	check_eq(_engagement.target_shots, 0, "and the parked target, with no driver, fired none")


## §15.7.4's fire discipline: the trigger is cold for every metre of the
## approach, and this asserts it stayed cold.
##
## [b]It was expected to be temporary and it is not.[/b] The rule was written as
## a workaround for the shipped autocannon's bore sitting half a cell off the
## hull's centreline, on the reasoning that centring the bore would remove the
## yaw and with it the need. The bore is now centred — rule 27, and
## [code]tests/physics/test_recoil_geometry.gd[/code] measures the lateral lever
## at a millimetre — and holding the trigger through an approach still wrecks it:
## the same driver, same build, fired on the move, never came round at all and
## finished 59 m out having started at 43 m.
##
## The reason is in that same file's second measurement. The recoil is applied at
## the muzzle, and a driver turning toward a target is by definition firing off
## its own nose; a traversed mount swings its line of action out to the two and a
## quarter metres it sits forward of the centre of mass, and one round at 90° of
## traverse yaws the hull sixty-five times harder than the same round fired dead
## ahead. Centring the bore fixes the on-axis case and cannot touch that one.
##
## So this is not a style preference about when a bot shoots, and it is not
## waiting on a data change any more. It is waiting on a mount whose recoil does
## not pass two metres from the centre of mass, which is a build question rather
## than a part one.
func test_the_attacker_closes_with_its_guns_cold() -> void:
	await _run()
	check_true(
		_engagement.range_after_turn_m > AiDriver.GROUND_STAND_OFF_M * 2.0,
		(
			"the approach was still running when this was sampled: %.1f m out"
			% _engagement.range_after_turn_m
		)
	)
	check_eq(
		_engagement.shots_during_approach,
		0,
		"and not one round had been fired while it was still driving"
	)


## The ledger, as an equality. §9: a store that merely went down is satisfied by
## a module that charges two rounds for every one it emits.
func test_every_round_fired_came_out_of_the_store() -> void:
	await _run()
	check_eq(
		_engagement.rounds_remaining,
		LOADED_ROUNDS - _engagement.attacker_shots,
		(
			"%d of %d left after %d shots"
			% [_engagement.rounds_remaining, LOADED_ROUNDS, _engagement.attacker_shots]
		)
	)


## Rounds fired is not damage done. A driver that aims at the sky spends
## ammunition just as fast as one that hits, and the two are indistinguishable
## everywhere above this assertion.
func test_the_rounds_land_on_the_target() -> void:
	await _run()
	check_true(
		_engagement.damage_to_target > 0.0,
		"integrity came off the target: %.0f" % _engagement.damage_to_target
	)
	# KINETIC specifically, and the channel matters. Nothing on the field is
	# shooting at the attacker, so a round landing on it would mean it had hit
	# itself — but it ends the engagement stopped at its stand-off, six metres
	# from a target it has been dismantling, and the debris that comes off that
	# target is a physical body it can be nudged by. That is an IMPACT packet and
	# it is correct; asserting the total to zero made this a test of whether the
	# fixture happened to leave any wreckage in the road.
	check_approx(
		_engagement.kinetic_to_attacker,
		0.0,
		"and not one round came off the attacker, which nothing was shooting at"
	)


## ===== §10.2's ARC COST ================================================
## Measured on the settled fixture, before the fight, when the pose is known.


## The delegation, in both directions. A reachability test that answered true for
## everything would leave §10.2's penalty permanently unpaid and be invisible in
## any ranking.
func test_a_mount_reports_what_it_can_and_cannot_reach() -> void:
	await _run()
	check_true(_engagement.reaches_ahead, "the mount reaches a target level and ahead")
	check_false(
		_engagement.reaches_below,
		"and not one directly beneath it, which is past its 8 degrees of depression"
	)


## The penalty, by value. Two candidates at the same range, one reachable and one
## not: the proximity term cancels and the difference is doc 07 §10's 140.
func test_an_unreachable_candidate_pays_the_documented_penalty() -> void:
	await _run()
	check_approx(
		_engagement.score_ahead - _engagement.score_below,
		ARC_COST_WEIGHT,
		"the arc cost is 140 exactly",
		1e-3
	)


## ===== THE RUN =========================================================


## One engagement, run once, recorded, and asserted from by every method above.
## A fight is destructive and cannot be repeated (§9).
func _run() -> void:
	if _fought:
		return
	_fought = true

	_arena = CombatArena.new()
	_arena.open()

	var attack_xz := Vector2(0.0, SEPARATION_M * 0.5)
	var target_xz := Vector2(0.0, -SEPARATION_M * 0.5)
	# Facing away: the yaw that points at the target, turned half a circle.
	var attacker := _arena.spawn(
		CombatArena.Recipe.WHEELED_LIGHT,
		0,
		attack_xz,
		CombatArena.yaw_towards(attack_xz, target_xz) + PI,
		LOADED_ROUNDS
	)
	var target := _arena.spawn(
		CombatArena.Recipe.WHEELED_HEAVY,
		1,
		target_xz,
		CombatArena.yaw_towards(target_xz, attack_xz),
		0
	)
	# No driver and no pilot. The control is the match scene as it stood before
	# this session: a build that aims at nothing and never moves.
	target.arena_piloted = false

	await _arena.settle(SETTLE_TICKS)

	var rec := Engagement.new()
	rec.attacker_assembly_id = attacker.assembly_id()
	rec.target_assembly_id = target.assembly_id()
	_probe_arc(rec, attacker)

	# Attached after the settle, so the approach below starts from rest and the
	# turn is measured from the pose the fixture was built at.
	var driver := _arena.make_autonomous(attacker, DIFFICULTY)

	rec.range_at_open_m = _flat_range(attacker, target)
	rec.bearing_at_open_deg = _bearing_deg(attacker, target)

	await _arena.engage(TURN_TICKS)
	rec.bearing_after_turn_deg = _bearing_deg(attacker, target)
	rec.target_id_at_open = driver.target_id()
	rec.range_after_turn_m = _flat_range(attacker, target)
	rec.shots_during_approach = int(_arena.shots_by.get(rec.attacker_assembly_id, 0))
	rec.closest_range_m = rec.range_after_turn_m

	await _arena.engage(ENGAGE_TICKS)
	rec.closest_range_m = minf(rec.closest_range_m, _flat_range(attacker, target))
	rec.final_range_m = _flat_range(attacker, target)
	rec.final_speed_mps = attacker.runtime.body.linear_velocity.length()
	rec.attacker_shots = int(_arena.shots_by.get(rec.attacker_assembly_id, 0))
	rec.target_shots = int(_arena.shots_by.get(rec.target_assembly_id, 0))
	rec.damage_to_target = float(_arena.damage_by_target.get(rec.target_assembly_id, 0.0))
	rec.damage_to_attacker = float(_arena.damage_by_target.get(rec.attacker_assembly_id, 0.0))
	rec.kinetic_to_attacker = _arena.damage_through(
		rec.attacker_assembly_id, PartEnums.DamageChannel.KINETIC
	)
	rec.rounds_remaining = _arena.ammo.rounds_stored(
		rec.attacker_assembly_id, _arena.projectile_registry.id_of(CombatArena.ROUND_KEY)
	)
	_engagement = rec

	for line: String in _arena.timeline:
		print("      %s" % line)
	print(
		(
			"  ai engagement: bearing %.1f° -> %.1f°, range %.1f -> %.1f m, closest %.1f m, "
			% [
				rec.bearing_at_open_deg, rec.bearing_after_turn_deg, rec.range_at_open_m,
				rec.range_after_turn_m, rec.closest_range_m
			]
		)
		+ "%d rounds, %d of them on the approach" % [rec.attacker_shots, rec.shots_during_approach]
	)


## §10.2's two probes, taken on the settled attacker: one point the mount can
## reach and one it cannot, at equal range in the Assembly's own frame.
func _probe_arc(rec: Engagement, attacker: CombatArena.Combatant) -> void:
	var body := attacker.runtime.body
	var origin := attacker.runtime.part_world_position(attacker.gun_slot)
	var forward := -body.global_transform.basis.z
	var ahead := origin + forward.normalized() * ARC_PROBE_RANGE_M
	var below := origin + Vector3.DOWN * ARC_PROBE_RANGE_M

	rec.reaches_ahead = attacker.guns.reaches(attacker.gun_slot, ahead)
	rec.reaches_below = attacker.guns.reaches(attacker.gun_slot, below)

	var ctx := AiContext.new()
	ctx.assembly_id = attacker.assembly_id()
	ctx.team = 0
	ctx.position = body.global_position
	ctx.effectors = attacker.guns
	ctx.effector_slot = attacker.gun_slot
	rec.score_ahead = AiTargetSelector.score_for(
		ctx, _probe_handle(ahead), ARC_PROBE_RANGE_M
	)
	rec.score_below = AiTargetSelector.score_for(
		ctx, _probe_handle(below), ARC_PROBE_RANGE_M
	)


## A candidate at [param position], intact and on the other team, carrying an id
## no Assembly in this arena has — so the retaliation term cannot fire on it and
## the only difference between two probes is where they are.
static func _probe_handle(position: Vector3) -> AiContext.TargetHandle:
	var handle := AiContext.TargetHandle.new()
	handle.id = -1
	handle.team = 1
	handle.position = position
	handle.integrity_fraction = 1.0
	return handle


## Horizontal range between two combatants. Flat, because the two sit at
## different heights on the slab and the driver's own tactic is flat.
static func _flat_range(a: CombatArena.Combatant, b: CombatArena.Combatant) -> float:
	var d := b.runtime.body.global_position - a.runtime.body.global_position
	return Vector2(d.x, d.z).length()


## Absolute heading error from [param a]'s nose to [param b], in degrees.
static func _bearing_deg(a: CombatArena.Combatant, b: CombatArena.Combatant) -> float:
	var offset := b.runtime.body.global_position - a.runtime.body.global_position
	return absf(rad_to_deg(AiDriver.bearing_to(a.runtime.body.global_transform.basis, offset)))


## What one engagement left behind.
class Engagement:
	extends RefCounted

	var attacker_assembly_id: int = 0
	var target_assembly_id: int = 0
	var target_id_at_open: int = 0
	var range_at_open_m: float = 0.0
	var range_after_turn_m: float = 0.0
	var shots_during_approach: int = 0
	var closest_range_m: float = 0.0
	var final_range_m: float = 0.0
	var bearing_at_open_deg: float = 0.0
	var bearing_after_turn_deg: float = 0.0
	var attacker_shots: int = 0
	var target_shots: int = 0
	var rounds_remaining: int = 0
	var damage_to_target: float = 0.0
	var damage_to_attacker: float = 0.0
	var kinetic_to_attacker: float = 0.0
	var final_speed_mps: float = 0.0
	var reaches_ahead: bool = false
	var reaches_below: bool = false
	var score_ahead: float = 0.0
	var score_below: float = 0.0
