extends TestCase
## [AssemblyRegistry] — the directory doc 08 §5.3, doc 12 §7.2 and doc 04 §6 all
## assume, and which two schedulers had each been keeping a private copy of.
##
## Small, and load-bearing in one specific way: [method AssemblyRegistry.ids] is
## the order a blast resolves its targets in (doc 08 §5.3), and a blast that
## destroys several parts determines the order of
## [signal EventBusService.part_destroyed], which determines debris body ordering
## on the network. An unordered directory would put a network desync three
## indirections away from a [method Dictionary.keys] call.

const ASSEMBLY_LOW := 2
const ASSEMBLY_MID := 7
const ASSEMBLY_HIGH := 40

var _runtimes: Array[AssemblyRuntime] = []


func after_all() -> void:
	for runtime in _runtimes:
		runtime.free()
	_runtimes.clear()


func test_a_registered_assembly_resolves_by_its_own_id() -> void:
	# The id comes off the runtime rather than being passed alongside it. Two
	# copies of it are two chances to disagree about who just took a hit.
	var registry := AssemblyRegistry.new()
	var runtime := _runtime(ASSEMBLY_MID)
	registry.register(runtime)

	check_eq(registry.get_runtime(ASSEMBLY_MID), runtime, "the runtime resolves by id")
	check_true(registry.has(ASSEMBLY_MID), "and the registry says so")
	check_eq(registry.count(), 1, "one Assembly is registered")
	check_eq(registry.graph_of(ASSEMBLY_MID), runtime.graph, "its graph resolves too")


func test_an_unknown_id_resolves_to_nothing_rather_than_erroring() -> void:
	# A packet for an Assembly that died this tick is ordinary, not exceptional;
	# doc 08 §5.1 rejects it and carries on.
	var registry := AssemblyRegistry.new()
	check_null(registry.get_runtime(ASSEMBLY_LOW), "no runtime for an unregistered id")
	check_null(registry.graph_of(ASSEMBLY_LOW), "and no graph")
	check_false(registry.has(ASSEMBLY_LOW), "and it is not present")
	check_eq(registry.count(), 0, "the registry is empty")
	check_eq(registry.ids(), PackedInt32Array(), "with no ids in it")


func test_ids_are_ascending_whatever_order_they_arrived_in() -> void:
	# Architectural Invariant I-9. Deliberately registered high-id-first.
	var registry := AssemblyRegistry.new()
	registry.register(_runtime(ASSEMBLY_HIGH))
	registry.register(_runtime(ASSEMBLY_LOW))
	registry.register(_runtime(ASSEMBLY_MID))

	check_eq(
		registry.ids(),
		PackedInt32Array([ASSEMBLY_LOW, ASSEMBLY_MID, ASSEMBLY_HIGH]),
		"ascending by id, not by arrival"
	)


func test_the_id_list_is_a_copy() -> void:
	# A caller that could edit it would be changing what the next blast sweep
	# iterates, from outside the registry entirely.
	var registry := AssemblyRegistry.new()
	registry.register(_runtime(ASSEMBLY_MID))
	var ids := registry.ids()
	ids.append(ASSEMBLY_HIGH)
	check_eq(registry.ids(), PackedInt32Array([ASSEMBLY_MID]), "the registry is unchanged")


func test_unregistering_removes_the_entry_and_its_id() -> void:
	var registry := AssemblyRegistry.new()
	registry.register(_runtime(ASSEMBLY_LOW))
	registry.register(_runtime(ASSEMBLY_MID))
	registry.unregister(ASSEMBLY_LOW)

	check_false(registry.has(ASSEMBLY_LOW), "the Assembly is gone")
	check_null(registry.get_runtime(ASSEMBLY_LOW), "and resolves to nothing")
	check_eq(registry.ids(), PackedInt32Array([ASSEMBLY_MID]), "and left the id list")
	check_eq(registry.count(), 1, "leaving the other one")


func test_unregistering_an_unknown_id_is_not_an_error() -> void:
	# Two systems tear an Assembly down and either may get there first.
	var registry := AssemblyRegistry.new()
	var probe := _Probe.new()
	registry.assembly_unregistered.connect(probe.on_unregistered)
	registry.unregister(ASSEMBLY_HIGH)
	check_eq(registry.count(), 0, "nothing happened")
	check_eq(probe.unregistered, PackedInt32Array(), "and nothing was announced")


func test_an_id_can_be_reused_after_its_assembly_leaves() -> void:
	# A respawn takes the same peer's Assembly id. Registering it again must be
	# an ordinary registration and not a duplicate.
	var registry := AssemblyRegistry.new()
	registry.register(_runtime(ASSEMBLY_MID))
	registry.unregister(ASSEMBLY_MID)
	var replacement := _runtime(ASSEMBLY_MID)
	registry.register(replacement)

	check_eq(registry.get_runtime(ASSEMBLY_MID), replacement, "the new runtime is the one held")
	check_eq(registry.ids(), PackedInt32Array([ASSEMBLY_MID]), "and the id appears exactly once")


## ===== THE SIGNALS THE SCHEDULERS RUN ON ===============================


func test_registration_and_removal_are_announced() -> void:
	var registry := AssemblyRegistry.new()
	var probe := _Probe.new()
	registry.assembly_registered.connect(probe.on_registered)
	registry.assembly_unregistered.connect(probe.on_unregistered)

	registry.register(_runtime(ASSEMBLY_MID))
	check_eq(probe.registered, PackedInt32Array([ASSEMBLY_MID]), "the arrival is announced")
	registry.unregister(ASSEMBLY_MID)
	check_eq(probe.unregistered, PackedInt32Array([ASSEMBLY_MID]), "and so is the departure")


func test_a_departure_is_announced_while_the_entry_can_still_be_resolved() -> void:
	# The order is the whole point of the signal. A handler cleaning up after an
	# Assembly — dropping its pending detachment, discarding its queued mass
	# solve — is told about it while it can still be looked at, not afterwards.
	var registry := AssemblyRegistry.new()
	var probe := _Probe.new()
	probe.registry = registry
	registry.assembly_unregistered.connect(probe.on_unregistered)
	registry.register(_runtime(ASSEMBLY_MID))

	registry.unregister(ASSEMBLY_MID)
	check_true(probe.resolved_during_removal, "the runtime was still resolvable in the handler")
	check_false(registry.has(ASSEMBLY_MID), "and gone once the call returned")


## ===== FIXTURES ========================================================


## A runtime carrying nothing but an id and a graph.
##
## The registry stores whole [AssemblyRuntime]s, but reads only those two, and
## adopting a [BuildContext] here would drag a physics space into every test in
## this file for no assertion's benefit.
func _runtime(assembly_id: int) -> AssemblyRuntime:
	var runtime := AssemblyRuntime.new()
	runtime.assembly_id = assembly_id
	_runtimes.append(runtime)
	return runtime


## Records what the registry announced. A distinct receiver object rather than a
## bound Callable, because two Callables bound over the same object and method
## compare equal and cannot be told apart.
class _Probe:
	extends RefCounted

	var registered: PackedInt32Array = PackedInt32Array()
	var unregistered: PackedInt32Array = PackedInt32Array()
	var registry: AssemblyRegistry = null
	var resolved_during_removal: bool = false

	func on_registered(assembly_id: int) -> void:
		registered.append(assembly_id)

	func on_unregistered(assembly_id: int) -> void:
		unregistered.append(assembly_id)
		if registry != null:
			resolved_during_removal = registry.get_runtime(assembly_id) != null
