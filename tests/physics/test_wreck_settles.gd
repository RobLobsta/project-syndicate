extends TestCase
## What an Assembly's remains do after the Core Module has gone.
##
## Doc 11 §16.2 decides that nothing despawns: the wreck, the debris and the
## craters are the visible record of the fight, and the orbit camera the player
## is handed at the conclusion would otherwise be circling an empty basin. That
## decision is right and it is not the whole rule, because it says nothing about
## what the remains [i]do[/i], and until this file was written nothing did.
##
## The capture that first showed the end card also showed the answer: 17.3 m/s at
## the moment of the conclusion, 18.1 m/s ten frames later, and [b]92.0 m/s[/b]
## fifty frames after that — the hulk crossing the basin and climbing, as the
## last thing a player sees, every time.
##
## [b]The mechanism, measured here rather than guessed.[/b] Invariant I-2 ends
## the Assembly when slot 0 is destroyed, which orphans every part on it; the
## detachment scheduler severs the islands and the debris pool takes them, and
## the chassis body drops from [b]1107 kg to 1.0 kg[/b] —
## [constant MassSolver.MIN_BODY_MASS_KG], the floor the engine needs because it
## refuses a zero mass outright (LEARNED_FACTS.md §1 fact 24). Nothing tells the
## motion layer any of this. [method MotiveSystem.step] keeps gathering the same
## four contacts and solving the same springs, and an ordinary suspension force
## on a gram of body is an enormous acceleration.
##
## [b]So the assertion that matters is a law and not a speed.[/b] On flat ground
## with a neutral record the remains do slow down, which is why five sessions of
## a green suite never saw this: what the basin adds is a slope for those
## residual forces to point along. The law under both is
## [method test_a_wreck_does_not_move_however_hard_it_is_commanded] — a
## terminated Assembly's motion layer applies nothing at all — and that is
## assertable on a slab, in one second, without staging a fifteen-metre hill.
##
## [b]One Assembly, and no engagement.[/b] LEARNED_FACTS.md §1 fact 44: a fight
## between several Assemblies is not reproducible tick for tick, and this file
## needs numbers it can compare against each other. The Core Module is destroyed
## by submitting one packet through [DamageResolver] — the same door every other
## damage source in the project goes through (CLAUDE.md §10 rule 10) — so the
## termination happens on a tick this file chooses rather than on whichever tick
## a duel happened to land it.

## Ticks the build is given to fall onto its contacts before anything is done to
## it. Long enough that the suspension has settled and the body is not still
## carrying the drop.
const SETTLE_TICKS: int = 180

## Ticks the build is driven under full throttle before it is destroyed. Six
## seconds on the slab is a little under eighteen metres a second, which is the
## state the capture caught: a wreck at 17.3 m/s that fifty frames later was
## doing 92.
const DRIVE_TICKS: int = 360

## Ticks the remains are watched for with a neutral record, and with a full
## throttle demand standing. Two seconds each: the capture reached 92 m/s in
## fifty frames, so either window is several times over what it takes to show.
const COAST_TICKS: int = 300
const COMMANDED_TICKS: int = 120

## Damage submitted to the Core Module, and the penetration it carries. Both are
## far past anything the shipped autocannon produces: this test is about what
## happens [i]after[/i] the destruction and has no interest in staging a
## plausible one.
const LETHAL_DAMAGE: float = 100000.0
const LETHAL_PENETRATION: float = 100000.0

## Mass, in kilogrammes, under which the body counts as having collapsed onto the
## engine's floor. The measured figure is exactly [constant
## MassSolver.MIN_BODY_MASS_KG]; the margin is for the float32 round trip through
## the physics server.
const COLLAPSED_MASS_CEILING_KG: float = 1.5

## Speed, in m/s, a terminated Assembly may reach while a full throttle demand
## stands against it. It starts from rest, so this is a threshold on "moved at
## all" with room for the settle of a body that has just lost most of its mass.
const COMMANDED_WRECK_SPEED_CEILING_MPS: float = 0.5

## Speed, in m/s, a [i]live[/i] Assembly must exceed under the same demand over
## the same window. The control case: it separates a motion layer that declined
## to drive from a fixture that could not have driven anyway.
##
## Four times the ceiling the terminated case has to stay under, and the measured
## pair is 3.87 against 0.00 — so neither bound is a description of either
## measurement.
const ALIVE_COMMANDED_FLOOR_MPS: float = 2.0

## Fraction of its speed at the conclusion the coasting wreck must be under by
## the end of the window. It is on a flat slab with no drive: it should be
## stopping, and anything that is not stopping is being pushed.
const COAST_DECAY_CEILING: float = 0.5

## Metres the hulk may cover over the tail of the coast window, once the mass
## solve that follows the last island has landed. Doc 05 §3.7 freezes the body,
## so the measured figure is exactly zero; the ceiling is a threshold on "moved at
## all" rather than a description of anything.
const WRECK_TRAVEL_CEILING_M: float = 0.25

var _ran: bool = false
var _terminated: bool = false
var _speed_under_power_mps: float = 0.0
var _mass_before_kg: float = 0.0
var _mass_after_kg: float = 0.0
var _speed_at_conclusion_mps: float = 0.0
var _speed_coasting_mps: float = 0.0
var _wreck_travel_m: float = 0.0
var _wreck_frozen: bool = false
var _speed_commanded_mps: float = 0.0
var _speed_alive_commanded_mps: float = 0.0
var _contacts_after_termination: int = 0

var _arena: CombatArena = null
var _detachment: DetachmentScheduler = null
var _mass: MassRecomputeScheduler = null
var _debris: DebrisPool = null


func after_all() -> void:
	# The guard for a run that failed part-way through; the normal path tears the
	# fixture down the moment its record is taken (LEARNED_FACTS.md §1 fact 48).
	_teardown()


func test_the_core_module_was_destroyed() -> void:
	await _run_all()
	check_true(_terminated, "the packet destroyed the Core Module")


## The amplifier, recorded because the law below is uninteresting without it: a
## residual force on a tonne is a nudge and the same force on a kilogramme is an
## escape.
func test_the_body_collapses_onto_the_engines_mass_floor() -> void:
	await _run_all()
	check_true(
		_mass_before_kg > COLLAPSED_MASS_CEILING_KG,
		"the intact build masses %.1f kg" % _mass_before_kg
	)
	check_true(
		_mass_after_kg <= COLLAPSED_MASS_CEILING_KG,
		(
			"the wreck should be left on the %.3f kg floor once its islands have "
			+ "detached, and is at %.3f kg"
		) % [MassSolver.MIN_BODY_MASS_KG, _mass_after_kg]
	)


## The law. Invariant I-2 ends the Assembly; doc 05 §3.6 makes the motion layer
## stop with it, and a demand standing against a build whose contacts are still
## there is the fixture that can tell "declined to drive" from "had nothing left
## to drive with".
##
## The first two checks are what make the third mean anything. A fixture in which
## the contacts had gone would pass this with the guard deleted, and the first
## version of this file did exactly that — the guard was removed and nothing
## failed.
func test_a_wreck_does_not_move_however_hard_it_is_commanded() -> void:
	await _run_all()
	check_true(
		_speed_alive_commanded_mps > ALIVE_COMMANDED_FLOOR_MPS,
		"a live Assembly answers this demand by driving off: %.2f m/s"
			% _speed_alive_commanded_mps
	)
	check_true(
		_contacts_after_termination > 0,
		"and the wreck still has contacts under it to drive with: %d"
			% _contacts_after_termination
	)
	check_true(
		_speed_commanded_mps < COMMANDED_WRECK_SPEED_CEILING_MPS,
		(
			"a terminated Assembly held at full throttle for %d ticks reached %.2f m/s; "
			+ "the motion layer is still solving a build that no longer exists"
		) % [COMMANDED_TICKS, _speed_commanded_mps]
	)


## What a player watches. The wreck arrives at the conclusion carrying whatever
## it was doing and must be losing that, not adding to it.
func test_the_remains_slow_down_rather_than_accelerate() -> void:
	await _run_all()
	check_true(
		_speed_coasting_mps < _speed_at_conclusion_mps * COAST_DECAY_CEILING,
		(
			"%d ticks after the conclusion the wreck is doing %.2f m/s against %.2f m/s "
			+ "at the conclusion"
		) % [COAST_TICKS, _speed_coasting_mps, _speed_at_conclusion_mps]
	)


## Doc 05 §3.7, and doc 11 §16.2's decision made good. Slowing down is not the
## rule; staying put is. §3.5's floors leave a body that no longer holds anything
## describing itself as a one-kilogramme object with a hull-sized collider, and
## anything that brushes one of those launches it — which is what the capture
## caught climbing past 27 m/s under the end card.
##
## The first check is what makes the second mean anything: a wreck that had been
## deleted, or one whose colliders had all gone with its islands, would sit at
## zero travel for the wrong reason.
func test_the_wreck_stays_where_it_fell() -> void:
	await _run_all()
	check_true(_wreck_frozen, "a body with no live parts left is out of the simulation")
	check_true(
		_wreck_travel_m < WRECK_TRAVEL_CEILING_M,
		(
			"the hulk moved %.2f m over the last %d ticks of the window; doc 11 §16.2 "
			+ "has it staying where it fell"
		) % [_wreck_travel_m, COAST_TICKS - COAST_TICKS / 3]
	)


## Runs once. The fixture is destructive — an Assembly whose Core Module has gone
## cannot be put back — so every method above asserts one thing about one run
## (LEARNED_FACTS.md §1 fact 43).
##
## [b]Two arenas, opened one after the other, and the pair is the point.[/b] The
## defect has two halves and no single fixture holds both:
##
## [enum]
## [*] [b]The amplifier[/b] needs the detachment scheduler and the debris pool,
##     because the collapse to the engine's mass floor is what they do. With them
##     the islands come off — and so do the contacts, so there is nothing left for
##     the motion layer to push against and the wreck settles whatever the guard
##     does.
## [*] [b]The law[/b] needs the opposite: an Assembly that has been terminated
##     while its parts are still attached, so that [method MotiveSystem.step] has
##     four live contacts and a full throttle demand and must decline to use them.
##     That is the state a fault can be planted against, and the one the first
##     version of this file could not reach — the guard was removed and nothing
##     failed.
## [/enum]
##
## One at a time, closed before the next (LEARNED_FACTS.md §1 fact 45).
func _run_all() -> void:
	if _ran:
		return
	_ran = true
	await _measure_the_collapse()
	await _measure_the_law()


## Phase one: what a match does to a wreck's mass, and what its remains do when
## nobody is commanding them.
func _measure_the_collapse() -> void:
	_arena = CombatArena.new()
	_arena.open()
	# [CombatArena] carries the four systems an engagement needs and deliberately
	# not these three, because every file that fights in it measures something
	# else and adding bodies to a shared space moves those measurements
	# (LEARNED_FACTS.md §1 fact 54). They are built here instead, in the order and
	# with the wiring [MatchScreen] uses.
	_detachment = DetachmentScheduler.new()
	_detachment.registry = _arena.registry
	EventBus.get_tree().root.add_child(_detachment)
	_mass = MassRecomputeScheduler.new()
	_mass.registry = _arena.registry
	EventBus.get_tree().root.add_child(_mass)
	_debris = DebrisPool.new()
	_debris.registry = _arena.registry
	_detachment.island_sink = _debris.on_island_severed
	EventBus.get_tree().root.add_child(_debris)

	var c := _arena.spawn(CombatArena.Recipe.WHEELED_LIGHT, 0, Vector2.ZERO, 0.0, 0)
	await _arena.settle(SETTLE_TICKS)

	# Destroyed while moving, because that is the state the capture was taken in.
	c.motion.input.throttle = 1.0
	await physics_frames(DRIVE_TICKS)
	_speed_under_power_mps = c.runtime.body.linear_velocity.length()
	_mass_before_kg = c.runtime.body.mass
	# Doc 11 §16.2 takes the controls off the player's Assembly at the conclusion
	# and [method AiDriver.idle] centres an opponent's, so the record a wreck is
	# left holding is a neutral one.
	c.motion.input.throttle = 0.0

	_destroy_core(c)
	await physics_frames(1)
	_terminated = not c.is_alive()
	_speed_at_conclusion_mps = c.runtime.body.linear_velocity.length()

	# Sampled a third of the way through the window rather than at the conclusion.
	# The islands detach on the resolve phase of the tick the Core Module died on
	# and the solve that notices lands two ticks later (doc 05 §4.3), so a
	# displacement measured from the conclusion would be measuring those two ticks
	# of ballistic travel and calling them drift.
	await physics_frames(COAST_TICKS / 3)
	var settled_at := c.runtime.body.global_position
	await physics_frames(COAST_TICKS - COAST_TICKS / 3)
	_speed_coasting_mps = c.runtime.body.linear_velocity.length()
	_wreck_travel_m = c.runtime.body.global_position.distance_to(settled_at)
	_wreck_frozen = c.runtime.body.freeze
	# Read here rather than at the conclusion. The severance is scheduled and the
	# re-solve runs on a worker (doc 05 §4.3), so which tick the new mass lands on
	# is the scheduler's business and not this file's claim; that it lands is.
	_mass_after_kg = c.runtime.body.mass

	print(
		(
			"      wreck: %.2f m/s under power at %.1f kg; conclusion %.2f m/s; "
			+ "%.3f kg and %.2f m/s after %d ticks"
		) % [
			_speed_under_power_mps, _mass_before_kg, _speed_at_conclusion_mps,
			_mass_after_kg, _speed_coasting_mps, COAST_TICKS
		]
	)
	_teardown()


## Phase two: doc 05 §3.6's law, in the state that can falsify it.
##
## No detachment scheduler, so the destruction of slot 0 ends the Assembly and
## leaves every part — and every contact — where it was. The motion layer
## therefore [i]can[/i] drive this body, has a full throttle demand telling it to,
## and must not.
func _measure_the_law() -> void:
	_arena = CombatArena.new()
	_arena.open()
	var c := _arena.spawn(CombatArena.Recipe.WHEELED_LIGHT, 0, Vector2.ZERO, 0.0, 0)
	await _arena.settle(SETTLE_TICKS)

	# The control case, and it is not decoration: it is what proves the fixture
	# can tell the two states apart. A live Assembly given this demand drives off.
	c.motion.input.throttle = 1.0
	await physics_frames(COMMANDED_TICKS)
	_speed_alive_commanded_mps = c.runtime.body.linear_velocity.length()

	c.motion.input.throttle = 0.0
	c.runtime.body.linear_velocity = Vector3.ZERO
	c.runtime.body.angular_velocity = Vector3.ZERO
	_destroy_core(c)
	await physics_frames(1)
	_contacts_after_termination = c.motion.contact_count(_first_motive_slot(c))

	# From rest, and against the loudest demand the input layer can produce.
	c.runtime.body.linear_velocity = Vector3.ZERO
	c.runtime.body.angular_velocity = Vector3.ZERO
	c.motion.input.throttle = 1.0
	await physics_frames(COMMANDED_TICKS)
	_speed_commanded_mps = c.runtime.body.linear_velocity.length()
	c.motion.input.throttle = 0.0

	print(
		(
			"      wreck: %.2f m/s alive under full throttle; %.2f m/s terminated under "
			+ "the same demand, with %d contacts still under it"
		) % [_speed_alive_commanded_mps, _speed_commanded_mps, _contacts_after_termination]
	)
	_teardown()


## One packet through the ordinary door. CLAUDE.md §10 rule 10: nothing else in
## the project writes integrity, and a test that reached past [DamageResolver]
## would be staging a destruction the game cannot produce.
func _destroy_core(c: CombatArena.Combatant) -> void:
	var packet := DamagePacket.new()
	packet.target_assembly_id = c.assembly_id()
	packet.target_slot = SyndicateConstants.CORE_SLOT
	packet.channel = PartEnums.DamageChannel.KINETIC
	packet.raw_amount = LETHAL_DAMAGE
	packet.penetration = LETHAL_PENETRATION
	packet.impact_point_world = c.runtime.body.global_position
	packet.impact_normal_world = Vector3.UP
	packet.incoming_direction = Vector3.DOWN
	_arena.resolver.apply(packet)


static func _first_motive_slot(c: CombatArena.Combatant) -> int:
	var slots := c.motion.motive_slots()
	return slots[0] if not slots.is_empty() else SyndicateConstants.INVALID_SLOT


## Removes then frees, in that order: [MassRecomputeScheduler] joins its worker
## task in [code]_exit_tree[/code], and [method Object.free] on a node with a
## task in flight is refused before it ever reaches there (LEARNED_FACTS.md §1
## fact 53).
func _teardown() -> void:
	if _arena != null:
		_arena.close()
		_arena = null
	for node: Node in [_debris, _mass, _detachment] as Array[Node]:
		if node != null and is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.free()
	_debris = null
	_mass = null
	_detachment = null
