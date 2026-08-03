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

## Fraction of its speed at the conclusion the coasting wreck must be under by
## the end of the window. It is on a flat slab with no drive: it should be
## stopping, and anything that is not stopping is being pushed.
const COAST_DECAY_CEILING: float = 0.5

var _ran: bool = false
var _terminated: bool = false
var _speed_under_power_mps: float = 0.0
var _mass_before_kg: float = 0.0
var _mass_after_kg: float = 0.0
var _speed_at_conclusion_mps: float = 0.0
var _speed_coasting_mps: float = 0.0
var _speed_commanded_mps: float = 0.0

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


## The law. Invariant I-2 ends the Assembly; doc 05 §3.1 makes the motion layer
## stop with it, and a demand standing against a wreck is the fixture that can
## tell "stopped" from "happens to be slowing down".
func test_a_wreck_does_not_move_however_hard_it_is_commanded() -> void:
	await _run_all()
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


## Runs once. The fixture is destructive — an Assembly whose Core Module has gone
## cannot be put back — so every method above asserts one thing about one run
## (LEARNED_FACTS.md §1 fact 43).
func _run_all() -> void:
	if _ran:
		return
	_ran = true

	_arena = CombatArena.new()
	_arena.open()
	# [CombatArena] carries the four systems an engagement needs and deliberately
	# not these three, because every file that fights in it measures something
	# else and adding bodies to a shared space moves those measurements
	# (LEARNED_FACTS.md §1 fact 54). They are built here instead, in the order and
	# with the wiring [MatchScreen] uses, because the collapse this file is about
	# is the one the match produces: the destruction orphans every part, the
	# scheduler severs the islands, the pool takes them, and the body the motion
	# layer is still solving for is left holding the floor.
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

	# Destroyed while moving, because that is the state the capture was taken in
	# and because a stationary wreck cannot show a traction solver still working:
	# every ground family's force is a function of slip, and slip at rest is zero.
	c.motion.input.throttle = 1.0
	await physics_frames(DRIVE_TICKS)
	_speed_under_power_mps = c.runtime.body.linear_velocity.length()
	_mass_before_kg = c.runtime.body.mass
	# Doc 11 §16.2 takes the controls off the player's Assembly at the conclusion
	# and [method AiDriver.idle] centres an opponent's, so the record a wreck is
	# left holding is a neutral one.
	c.motion.input.throttle = 0.0

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
	# The detachment the destruction queued resolves on the next tick, which is
	# the tick the body loses its islands and its mass.
	await physics_frames(1)

	_terminated = not c.is_alive()
	_speed_at_conclusion_mps = c.runtime.body.linear_velocity.length()

	await physics_frames(COAST_TICKS)
	_speed_coasting_mps = c.runtime.body.linear_velocity.length()
	# Read here rather than at the conclusion. The severance is scheduled and the
	# re-solve runs on a worker (doc 05 §4.3), so which tick the new mass lands on
	# is the scheduler's business and not this file's claim; that it lands is.
	_mass_after_kg = c.runtime.body.mass

	# From rest, and against the loudest demand the input layer can produce. A
	# live Assembly answers this by driving off; a terminated one must not answer
	# it at all.
	c.runtime.body.linear_velocity = Vector3.ZERO
	c.runtime.body.angular_velocity = Vector3.ZERO
	c.motion.input.throttle = 1.0
	await physics_frames(COMMANDED_TICKS)
	_speed_commanded_mps = c.runtime.body.linear_velocity.length()
	c.motion.input.throttle = 0.0

	print(
		(
			"      wreck: %.2f m/s under power at %.1f kg; conclusion %.2f m/s at %.3f kg; "
			+ "coasting %.2f m/s after %d ticks; %.2f m/s under full throttle from rest"
		) % [
			_speed_under_power_mps, _mass_before_kg, _speed_at_conclusion_mps,
			_mass_after_kg, _speed_coasting_mps, COAST_TICKS, _speed_commanded_mps
		]
	)
	_teardown()


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
