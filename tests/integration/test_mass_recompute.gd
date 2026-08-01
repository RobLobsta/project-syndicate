extends TestCase
## [MassRecomputeScheduler] — §4 of doc 05, driven through the signals rather
## than through its own methods.
##
## The scheduler's whole reason to exist is that it does the solve [i]once[/i],
## off the tick's critical path, for a batch of events that arrived together. A
## test that called the solver directly would pass just as happily with the
## batching removed, the worker thread removed, and the apply moved into the
## middle of a tick — which is to say with everything the class is for removed.
## So every test below emits [EventBusService] signals and advances
## [code]MatchClock.tick_started[/code], and asserts what landed on the body.

const CORE_KEY := &"core.command.compact.t2"
const PANEL_KEY := &"str.panel.medium.t2"

const CORE_ORIGIN := Vector3i(24, 4, 24)
const DECK_ORIGIN := Vector3i(24, 7, 24)

const ASSEMBLY_A := 11
const ASSEMBLY_B := 4

## Twelve is enough that a leak of one entry per cycle is unmistakable and few
## enough that the suite stays fast.
const CYCLE_COUNT := 12

var _core: PartDefinition = null
var _panel: PartDefinition = null
var _contexts: Array[BuildContext] = []
var _runtimes: Array[AssemblyRuntime] = []
var _schedulers: Array[MassRecomputeScheduler] = []


func before_all() -> void:
	_core = PartRegistry.definition_by_key(CORE_KEY)
	_panel = PartRegistry.definition_by_key(PANEL_KEY)


func after_all() -> void:
	# A scheduler left in the tree stays connected to the bus and resolves the
	# next test's fixture underneath it.
	for s in _schedulers:
		s.free()
	_schedulers.clear()
	for runtime in _runtimes:
		runtime.free()
	_runtimes.clear()
	for ctx in _contexts:
		ctx.dispose()
	_contexts.clear()


## ===== §4.3 THE TICK BOUNDARY ==========================================


func test_a_registration_is_solved_and_applied_one_tick_later() -> void:
	var s := _new_scheduler()
	var runtime := _adopted_runtime(ASSEMBLY_A)
	var probe := _MassProbe.new()
	s.mass_applied.connect(probe.on_applied)

	s.registry.register(runtime)
	check_eq(s.pending(), PackedInt32Array([ASSEMBLY_A]), "registration marks the Assembly dirty")

	MatchClock.tick_started.emit(100)
	check_eq(s.pending(), PackedInt32Array(), "the batch was captured")
	check_eq(probe.count, 0, "and nothing is applied on the tick that launched it")

	MatchClock.tick_started.emit(101)
	check_eq(probe.count, 1, "the result lands on the next tick")
	check_eq(probe.last_assembly, ASSEMBLY_A, "for the Assembly that was dirty")
	check_eq(probe.last_source_tick, 100, "carrying the tick its input was captured on")
	check_approx(
		runtime.body.mass, _core.mass_kg + _panel.mass_kg, "and the body carries both parts"
	)


func test_the_applied_properties_are_the_ones_the_solver_computes() -> void:
	var s := _new_scheduler()
	var runtime := _adopted_runtime(ASSEMBLY_A)
	s.registry.register(runtime)
	_advance(s, 200)

	var expected := MassSolver.compute(runtime.states, runtime.graph)
	check_approx(runtime.body.mass, expected.total_mass, "mass matches a synchronous solve")
	check_true(
		runtime.body.center_of_mass.is_equal_approx(expected.com_local),
		"and so does the centre of mass"
	)
	check_true(
		runtime.body.inertia.is_equal_approx(expected.inertia_diag),
		"and the diagonal of the tensor"
	)
	check_eq(runtime.mass_properties.assembly_id, ASSEMBLY_A, "the result names its Assembly")


func test_a_quiet_tick_costs_nothing() -> void:
	# Architectural Invariant I-4 as an assertion: a match in which nothing
	# breaks must never reach the worker thread.
	var s := _new_scheduler()
	var runtime := _adopted_runtime(ASSEMBLY_A)
	s.registry.register(runtime)
	_advance(s, 300)

	for tick in 5:
		MatchClock.tick_started.emit(400 + tick)
		check_false(s.is_solving(), "no solve was launched on a tick with nothing dirty")
	check_eq(s.pending(), PackedInt32Array(), "and nothing accumulated")


## ===== §4.1 THE FIVE TRIGGERS ==========================================


func test_every_documented_trigger_marks_the_assembly_dirty() -> void:
	var s := _new_scheduler()
	var runtime := _adopted_runtime(ASSEMBLY_A)
	s.registry.register(runtime)
	_advance(s, 500)

	EventBus.part_attached.emit(ASSEMBLY_A, 2)
	check_eq(s.pending(), PackedInt32Array([ASSEMBLY_A]), "part_attached")
	_advance(s, 510)

	EventBus.part_removed.emit(ASSEMBLY_A, 2)
	check_eq(s.pending(), PackedInt32Array([ASSEMBLY_A]), "part_removed")
	_advance(s, 520)

	EventBus.assembly_mass_dirty.emit(ASSEMBLY_A)
	check_eq(s.pending(), PackedInt32Array([ASSEMBLY_A]), "assembly_mass_dirty, from a destruction")
	_advance(s, 530)

	EventBus.island_detached.emit(ASSEMBLY_A, PackedByteArray([1]), 0)
	check_eq(s.pending(), PackedInt32Array([ASSEMBLY_A]), "island_detached")
	_advance(s, 540)

	EventBus.consumable_mass_step.emit(ASSEMBLY_A)
	check_eq(s.pending(), PackedInt32Array([ASSEMBLY_A]), "consumable_mass_step")


func test_events_for_an_unknown_assembly_are_ignored() -> void:
	# The bus is global. A garage context and a match Assembly both emit
	# part_attached, and the scheduler must not queue work for a body it has
	# never been given.
	var s := _new_scheduler()
	var runtime := _adopted_runtime(ASSEMBLY_A)
	s.registry.register(runtime)
	_advance(s, 600)

	EventBus.part_attached.emit(ASSEMBLY_B, 1)
	EventBus.assembly_mass_dirty.emit(ASSEMBLY_B)
	check_eq(s.pending(), PackedInt32Array(), "an unregistered Assembly queues nothing")


## ===== §4.1 BATCHING ===================================================


func test_a_burst_of_events_produces_exactly_one_solve() -> void:
	# A blast damages six panels at once. Six recomputes for one structural
	# change is the cost this class was written to remove.
	var s := _new_scheduler()
	var runtime := _adopted_runtime(ASSEMBLY_A)
	var probe := _MassProbe.new()
	s.mass_applied.connect(probe.on_applied)
	s.registry.register(runtime)
	_advance(s, 700)
	probe.count = 0

	for slot in 6:
		EventBus.assembly_mass_dirty.emit(ASSEMBLY_A)
	check_eq(s.pending(), PackedInt32Array([ASSEMBLY_A]), "six events, one entry")

	_advance(s, 710)
	check_eq(probe.count, 1, "and one applied result")


func test_two_assemblies_are_captured_in_ascending_id_order() -> void:
	# Ordering is not cosmetic: the server and every client replaying the same
	# event set must produce the same sequence of body writes (I-9).
	var s := _new_scheduler()
	var a := _adopted_runtime(ASSEMBLY_A)
	var b := _adopted_runtime(ASSEMBLY_B)
	var probe := _MassProbe.new()
	s.mass_applied.connect(probe.on_applied)

	s.registry.register(a)
	s.registry.register(b)
	check_eq(
		s.pending(), PackedInt32Array([ASSEMBLY_B, ASSEMBLY_A]),
		"the queue is ascending by id, not by arrival"
	)

	MatchClock.tick_started.emit(800)
	MatchClock.tick_started.emit(801)
	check_eq(probe.count, 2, "both Assemblies were solved")
	check_eq(
		probe.order, PackedInt32Array([ASSEMBLY_B, ASSEMBLY_A]), "and applied in the same order"
	)
	check_approx(a.body.mass, _core.mass_kg + _panel.mass_kg, "the first body took its mass")
	check_approx(b.body.mass, _core.mass_kg + _panel.mass_kg, "and so did the second")


func test_a_result_for_an_assembly_that_died_mid_solve_is_discarded() -> void:
	var s := _new_scheduler()
	var runtime := _adopted_runtime(ASSEMBLY_A)
	var probe := _MassProbe.new()
	s.mass_applied.connect(probe.on_applied)
	s.registry.register(runtime)

	MatchClock.tick_started.emit(900)
	s.registry.unregister(ASSEMBLY_A)
	MatchClock.tick_started.emit(901)

	check_eq(probe.count, 0, "there is nothing to recompute for a wreck")
	check_false(s.is_solving(), "and the task was still joined rather than left in flight")


func test_unregistering_drops_queued_work() -> void:
	var s := _new_scheduler()
	var runtime := _adopted_runtime(ASSEMBLY_A)
	s.registry.register(runtime)
	s.registry.unregister(ASSEMBLY_A)
	check_eq(s.pending(), PackedInt32Array(), "the queued entry left with the Assembly")

	MatchClock.tick_started.emit(1000)
	check_false(s.is_solving(), "and nothing was launched for it")


## ===== §5 THE SHIFT UNDER DAMAGE =======================================


func test_losing_a_part_moves_the_mass_and_the_centre_of_mass() -> void:
	# §5 is where the mass model becomes gameplay: the surviving structure has
	# to weigh less and balance differently, and both must follow from the same
	# recompute rather than from a special case.
	var s := _new_scheduler()
	var runtime := _adopted_runtime(ASSEMBLY_A)
	s.registry.register(runtime)
	_advance(s, 1100)
	var com_before := runtime.body.center_of_mass

	runtime.graph.detach(1)
	runtime.release_part(1)
	EventBus.assembly_mass_dirty.emit(ASSEMBLY_A)
	_advance(s, 1110)

	check_approx(runtime.body.mass, _core.mass_kg, "the panel's mass is gone")
	check_true(
		runtime.body.center_of_mass.y < com_before.y,
		"and the centre of mass dropped, because what left was on top"
	)
	check_eq(runtime.mass_properties.part_count, 1, "one part remains")


func test_repeated_loss_and_restoration_returns_to_the_baseline() -> void:
	# Everything the scheduler touches is incremental — a dirty list, a batch, a
	# staged result — and none of it fails loudly. A cycle that does not return
	# to its starting numbers is the only way a one-entry-per-cycle leak shows.
	var s := _new_scheduler()
	var runtime := _adopted_runtime(ASSEMBLY_A)
	s.registry.register(runtime)
	_advance(s, 1200)
	var baseline_mass := runtime.body.mass
	var baseline_com := runtime.body.center_of_mass

	var tick := 1210
	for cycle in CYCLE_COUNT:
		runtime.states[1].set_flag(PartFlags.FLAG_DETACHED, true)
		EventBus.assembly_mass_dirty.emit(ASSEMBLY_A)
		_advance(s, tick)
		tick += 10
		runtime.states[1].set_flag(PartFlags.FLAG_DETACHED, false)
		EventBus.part_attached.emit(ASSEMBLY_A, 1)
		_advance(s, tick)
		tick += 10

	check_approx(runtime.body.mass, baseline_mass, "mass returned to the baseline")
	check_true(
		runtime.body.center_of_mass.is_equal_approx(baseline_com),
		"and so did the centre of mass"
	)
	check_eq(s.pending(), PackedInt32Array(), "nothing accumulated in the dirty list")
	check_false(s.is_solving(), "and no task was left in flight")


## ===== FIXTURES ========================================================


func _new_scheduler() -> MassRecomputeScheduler:
	var s := MassRecomputeScheduler.new()
	# One registry per scheduler, so a test's Assemblies cannot be seen by the
	# scheduler the previous test left behind.
	s.registry = AssemblyRegistry.new()
	_schedulers.append(s)
	# _ready is where every connection is made, and a Node only gets one in a
	# tree. Going through an autoload's tree is how a TestCase, which is a
	# RefCounted and has no get_tree(), reaches the real one.
	EventBus.get_tree().root.add_child(s)
	return s


## Launches on [param tick] and applies on the tick after it, which is the full
## round trip of §4.3.
func _advance(_s: MassRecomputeScheduler, tick: int) -> void:
	MatchClock.tick_started.emit(tick)
	MatchClock.tick_started.emit(tick + 1)


func _adopted_runtime(assembly_id: int) -> AssemblyRuntime:
	var runtime := AssemblyRuntime.new()
	_runtimes.append(runtime)
	EventBus.get_tree().root.add_child(runtime)
	runtime.adopt(_context_with_core_and_panel(assembly_id))
	return runtime


func _context_with_core_and_panel(assembly_id: int) -> BuildContext:
	var ctx := BuildContext.with_physics(assembly_id)
	_contexts.append(ctx)
	PlacementValidator.commit(ctx, PlacementCandidate.create(_core, CORE_ORIGIN, 0))
	PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0))
	return ctx


## Records what the scheduler announced. A distinct receiver object rather than a
## bound Callable, because two Callables bound over the same object and method
## compare equal and cannot be told apart.
class _MassProbe:
	extends RefCounted

	var count: int = 0
	var last_assembly: int = -1
	var last_source_tick: int = -1
	var order: PackedInt32Array = PackedInt32Array()

	func on_applied(assembly_id: int, source_tick: int) -> void:
		count += 1
		last_assembly = assembly_id
		last_source_tick = source_tick
		order.append(assembly_id)
