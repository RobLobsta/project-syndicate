extends TestCase
## [DetachmentScheduler] — the cascade batching of doc 04 §5.5, the re-entrancy
## rule of §5.6, and the Core Module short-circuit of §7.2.
##
## This is the whole event contract exercised end to end: a destruction is
## announced on the [code]EventBus[/code], nothing happens, and the structure
## changes only when the tick resolves. Tests that called
## [code]_resolve_assembly[/code] directly would pass with the batching removed
## entirely, which is the one property this class exists to provide, so every
## test here goes through the signals.
##
## The scheduler is a [Node] and must be in the tree for its
## [code]_ready[/code] to have registered anything, so each test builds one and
## frees it. A leaked scheduler stays connected to the bus and resolves the next
## test's Assembly underneath it.

const CORE := SyndicateConstants.CORE_SLOT
const INVALID := SyndicateConstants.INVALID_SLOT

const CORE_MASS := 380.0
const PART_MASS := 34.0
const STRONG := 60000.0

const ASSEMBLY := 3
const OTHER_ASSEMBLY := 1

var _severed: Array = []
var _terminated: Array = []
var _structure_changed: Array = []
var _mass_dirty: Array = []
var _schedulers: Array[DetachmentScheduler] = []
var _runtimes: Array[AssemblyRuntime] = []


func before_all() -> void:
	EventBus.assembly_terminated.connect(_on_terminated)
	EventBus.assembly_structure_changed.connect(_on_structure_changed)
	EventBus.assembly_mass_dirty.connect(_on_mass_dirty)


func after_all() -> void:
	EventBus.assembly_terminated.disconnect(_on_terminated)
	EventBus.assembly_structure_changed.disconnect(_on_structure_changed)
	EventBus.assembly_mass_dirty.disconnect(_on_mass_dirty)
	_free_schedulers()
	_free_runtimes()


## ===== BATCHING ========================================================


func test_nothing_resolves_before_the_tick() -> void:
	# The batching in one assertion: the graph must be untouched between the
	# destruction and the resolve phase, because six parts dying in one tick
	# have to be resolved together or not at all.
	var g := _chain(3)
	var s := _scheduler(g)

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	check_true(g.is_alive(1), "the destroyed part is still in the graph")
	check_eq(s.pending_for(ASSEMBLY), PackedByteArray([1]), "and is pending instead")

	EventBus.tick_resolved.emit()
	check_false(g.is_alive(1), "the resolve phase removes it")
	check_eq(s.pending_for(ASSEMBLY), PackedByteArray(), "and drains the pending set")


func test_two_deaths_in_one_tick_produce_one_island() -> void:
	#  CORE — 1 — 2 — 3 — 4      destroy 1 and 2 in the same tick
	var g := _chain(4)
	_scheduler(g)

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.part_destroyed.emit(ASSEMBLY, 2, 0)
	EventBus.tick_resolved.emit()

	check_eq(_severed.size(), 1, "one island, not one per death")
	check_eq(_severed[0][1], PackedByteArray([3, 4]), "holding everything above the higher cut")
	check_eq(g.live_slots(), PackedByteArray([CORE]), "only the core remains")


func test_the_same_slot_twice_is_queued_once() -> void:
	# A joint failure and a destruction can name the same part in one tick.
	var g := _chain(2)
	var s := _scheduler(g)

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	check_eq(s.pending_for(ASSEMBLY), PackedByteArray([1]), "queued once")


func test_assemblies_resolve_in_ascending_id_order() -> void:
	# Deterministic ordering across Assemblies is what the network layer replays
	# against (§5.5). Emitted deliberately high-id-first.
	var high := _chain(2)
	var low := _chain(2)
	var s := _scheduler(high)
	_register(s, OTHER_ASSEMBLY, low)

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.part_destroyed.emit(OTHER_ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()

	check_eq(
		_structure_changed,
		[OTHER_ASSEMBLY, ASSEMBLY],
		"the lower assembly id resolves first regardless of emission order"
	)


func test_an_assembly_leaving_the_match_drops_its_pending_work() -> void:
	# The graph belongs to the Assembly, and once it is unregistered nobody owns
	# it. Resolving a destruction queued against it would walk a structure that
	# has left the match — and the resolve path's own null guard covers a
	# different case, an id that was never registered at all.
	var g := _chain(3)
	var s := _scheduler(g)

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	check_eq(s.pending_for(ASSEMBLY), PackedByteArray([1]), "the death is queued")

	s.registry.unregister(ASSEMBLY)
	check_eq(s.pending_for(ASSEMBLY), PackedByteArray(), "and leaves with the Assembly")

	EventBus.tick_resolved.emit()
	check_true(g.is_alive(1), "so the resolve phase never touches the orphaned graph")
	check_eq(_structure_changed.size(), 0, "and announces nothing for it")


func test_an_idle_tick_announces_nothing() -> void:
	# §5.5's overwhelmingly common path, and the reason a match with no
	# destruction costs zero graph CPU time.
	var g := _chain(2)
	_scheduler(g)
	EventBus.tick_resolved.emit()
	check_eq(_severed.size(), 0, "no island")
	check_eq(_structure_changed.size(), 0, "no structure change")
	check_eq(g.live_slots(), PackedByteArray([CORE, 1, 2]), "and the graph is untouched")


## ===== RE-ENTRANCY (§5.6) ==============================================


func test_a_death_during_a_resolve_lands_in_the_next_tick() -> void:
	# A severed Power Plant detonates and kills more parts. Those deaths must
	# not re-enter the pass that caused them; they resolve on the tick after.
	var g := _chain(4)
	var s := _scheduler(g)
	var relay := SecondaryKill.new(ASSEMBLY, 3)
	s.island_severed.connect(relay.on_island_severed)

	EventBus.part_destroyed.emit(ASSEMBLY, 2, 0)
	EventBus.tick_resolved.emit()

	check_true(relay.fired, "the secondary death was emitted during the resolve")
	check_eq(
		s.pending_for(ASSEMBLY), PackedByteArray([3]), "and is pending for the following tick"
	)
	s.island_severed.disconnect(relay.on_island_severed)


## ===== STRAIN FAILURES =================================================


func test_a_failed_joint_severs_the_part_it_was_holding() -> void:
	#  CORE — 1 — 2      the 1—2 joint yields
	var g := _chain(2)
	_scheduler(g)

	EventBus.joint_failed.emit(ASSEMBLY, 2, 1)
	check_eq(g.edge_index(1, 2), -1, "the edge is cut the moment the joint fails")
	EventBus.tick_resolved.emit()

	check_eq(_severed.size(), 1, "one island")
	check_eq(_severed[0][1], PackedByteArray([2]), "holding the part that lost its support")
	check_false(g.is_alive(2), "which is no longer on the Assembly")
	check_true(g.is_alive(1), "while the part below it stays")


func test_a_failed_joint_on_a_bridged_part_severs_nothing() -> void:
	# The joint yields but the part is also touching the core, so it holds on
	# and simply re-parents. A solver that severed on the failed edge alone
	# would drop a part that is still bolted to the hull.
	var g := _graph_with_core()
	_attach(g, 1, CORE, [CORE])
	_attach(g, 2, 1, [1, CORE])
	_scheduler(g)

	EventBus.joint_failed.emit(ASSEMBLY, 2, 1)
	EventBus.tick_resolved.emit()

	check_eq(_severed.size(), 0, "nothing severed")
	check_true(g.is_alive(2), "the bridged part stays")
	check_eq(int(g.parent[2]), CORE, "re-parented onto the joint it has left")


## ===== CORE MODULE LOSS (§7.2) =========================================


func test_losing_the_core_terminates_the_assembly() -> void:
	var g := _chain(3)
	_scheduler(g)

	EventBus.part_destroyed.emit(ASSEMBLY, CORE, 0)
	EventBus.tick_resolved.emit()

	check_eq(_terminated.size(), 1, "the Assembly is terminated")
	check_eq(_terminated[0][0], ASSEMBLY, "naming the Assembly")
	check_eq(g.live_slots(), PackedByteArray(), "and nothing is left in the graph")


func test_core_loss_turns_every_remaining_part_into_debris() -> void:
	# Two branches off the core become two components once the root is gone,
	# and every part must be in exactly one of them.
	var g := _graph_with_core()
	_attach(g, 1, CORE, [CORE])
	_attach(g, 2, 1, [1])
	_attach(g, 3, CORE, [CORE])
	_scheduler(g)

	EventBus.part_destroyed.emit(ASSEMBLY, CORE, 0)
	EventBus.tick_resolved.emit()

	var seen := PackedByteArray()
	for entry: Array in _severed:
		seen.append_array(entry[1])
	seen.sort()
	check_eq(seen, PackedByteArray([1, 2, 3]), "every surviving part is in exactly one island")


func test_core_loss_short_circuits_rather_than_searching() -> void:
	# §7.2. With the core in the destroyed set the reachability search has
	# nothing to early-out against, so the short-circuit runs instead — and it
	# must run even when other parts died in the same tick.
	var g := _chain(3)
	_scheduler(g)

	EventBus.part_destroyed.emit(ASSEMBLY, 2, 0)
	EventBus.part_destroyed.emit(ASSEMBLY, CORE, 0)
	EventBus.tick_resolved.emit()

	check_eq(_terminated.size(), 1, "terminated rather than resolved part by part")
	check_eq(g.live_slots(), PackedByteArray(), "with nothing left alive")


## ===== THE SINK AND THE DOWNSTREAM SIGNALS =============================


func test_the_island_sink_receives_every_island() -> void:
	var g := _chain(3)
	var s := _scheduler(g)
	var sink := SinkRecorder.new()
	s.island_sink = sink.take

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()

	check_eq(sink.taken.size(), 1, "the sink was called once")
	check_eq(sink.taken[0][1], PackedByteArray([2, 3]), "with the island's slots")


func test_a_resolve_marks_the_mass_dirty() -> void:
	# The mass solver runs at PRIORITY_MASS, after detachment, and needs to know
	# the structure moved underneath it.
	var g := _chain(2)
	_scheduler(g)
	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()
	check_eq(_mass_dirty, [ASSEMBLY], "the Assembly's mass is announced dirty exactly once")


func test_repeated_resolves_do_not_drift() -> void:
	# Nothing the scheduler maintains fails loudly. Twelve identical cycles
	# asserting the same surviving structure is what makes a per-cycle leak in
	# the pending sets or the graph aggregates visible.
	var baseline := ""
	for cycle in 12:
		_reset_recordings()
		var g := _chain(4)
		_scheduler(g)
		EventBus.part_destroyed.emit(ASSEMBLY, 2, 0)
		EventBus.tick_resolved.emit()
		_free_schedulers()
		if cycle == 0:
			baseline = g.debug_report()
		else:
			check_eq(g.debug_report(), baseline, "cycle %d matches the first" % cycle)
	check_ne(baseline, "", "the baseline was captured")


## ===== HELPERS =========================================================


## Re-emits a destruction from inside the resolve pass, standing in for the
## severed Power Plant of §5.6.
##
## A distinct object rather than a bound [Callable] because
## [method Callable.bind] does not make two Callables compare unequal.
class SecondaryKill:
	extends RefCounted

	var assembly_id: int = 0
	var slot: int = 0
	var fired: bool = false

	func _init(id: int, victim: int) -> void:
		assembly_id = id
		slot = victim

	func on_island_severed(_id: int, _slots: PackedByteArray) -> void:
		if fired:
			return
		fired = true
		EventBus.part_destroyed.emit(assembly_id, slot, 0)


class SinkRecorder:
	extends RefCounted

	var taken: Array = []

	func take(assembly_id: int, slots: PackedByteArray) -> void:
		taken.append([assembly_id, slots])


func _on_terminated(assembly_id: int, killer_id: int) -> void:
	_terminated.append([assembly_id, killer_id])


func _on_structure_changed(assembly_id: int) -> void:
	_structure_changed.append(assembly_id)


func _on_mass_dirty(assembly_id: int) -> void:
	_mass_dirty.append(assembly_id)


func _on_island_severed(assembly_id: int, slots: PackedByteArray) -> void:
	_severed.append([assembly_id, slots])


## A scheduler in the tree with [param graph] registered as [constant ASSEMBLY],
## with every previous one torn down first.
func _scheduler(graph: ChassisGraph) -> DetachmentScheduler:
	_free_schedulers()
	_reset_recordings()
	var s := DetachmentScheduler.new()
	s.registry = AssemblyRegistry.new()
	# A TestCase is a RefCounted and has no tree of its own. The scheduler has to
	# actually enter one, because everything it does is set up in _ready.
	EventBus.get_tree().root.add_child(s)
	_register(s, ASSEMBLY, graph)
	s.island_severed.connect(_on_island_severed)
	_schedulers.append(s)
	return s


## Puts [param graph] into [param s]'s registry under [param assembly_id].
##
## The registry holds [AssemblyRuntime]s, and these tests are about topology
## alone, so the runtime is a bare one carrying nothing but the id and the graph.
## Building a real one would drag a [BuildContext] and a physics space into every
## test in this file for no assertion's benefit.
func _register(s: DetachmentScheduler, assembly_id: int, graph: ChassisGraph) -> void:
	var runtime := AssemblyRuntime.new()
	runtime.assembly_id = assembly_id
	runtime.graph = graph
	_runtimes.append(runtime)
	s.registry.register(runtime)


func _free_schedulers() -> void:
	for s in _schedulers:
		if is_instance_valid(s):
			s.get_parent().remove_child(s)
			s.free()
	_schedulers.clear()


func _free_runtimes() -> void:
	for runtime in _runtimes:
		runtime.free()
	_runtimes.clear()


func _reset_recordings() -> void:
	_severed.clear()
	_terminated.clear()
	_structure_changed.clear()
	_mass_dirty.clear()


func _graph_with_core() -> ChassisGraph:
	var g := ChassisGraph.new()
	g.attach(CORE, INVALID, [] as Array[MateRecord], CORE_MASS)
	return g


func _chain(length: int) -> ChassisGraph:
	var g := _graph_with_core()
	for i in range(1, length + 1):
		_attach(g, i, i - 1, [i - 1])
	return g


func _attach(g: ChassisGraph, slot: int, tree_parent: int, mated: Array) -> void:
	var mates: Array[MateRecord] = []
	for other: int in mated:
		var m := MateRecord.new()
		m.other_slot = other
		m.joint_strength_n = STRONG
		m.bears_load = true
		mates.append(m)
	g.attach(slot, tree_parent, mates, PART_MASS)
