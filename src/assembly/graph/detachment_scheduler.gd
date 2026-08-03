class_name DetachmentScheduler
extends Node
## Batches structural loss to one resolution per Assembly per tick, per
## [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §5.5.
##
## Parts rarely die alone. A blast damages six panels at once, and resolving
## detachment six times produces six island sets — several of them subsets of one
## another — and six debris spawns where one is correct. Destruction is therefore
## accumulated into a per-Assembly pending set and resolved once, in the
## [constant EventBusService.PRIORITY_DETACHMENT] phase of
## [signal EventBusService.tick_resolved].
##
## Architectural Invariant I-4: no [code]_process[/code] and no
## [code]_physics_process[/code]. The three signals below are the only things
## that wake this node, and with nothing pending the resolve phase returns on its
## first line. A twenty-minute match with no destruction costs zero graph CPU
## time.
##
## [b]Scope.[/b] This resolves topology: which parts stopped being attached, and
## what the Assembly looks like afterwards. Turning a severed island into a
## [RigidBody3D] is §6, and is reached through [member island_sink] — see the
## note there.

## Emitted for each island this scheduler severed, in the order §5.5 fixes.
##
## Distinct from [signal EventBusService.island_detached], which §6 emits once a
## debris body exists and carries that body's id. This one says only that the
## parts left the Assembly, which is the authoritative structural fact and is
## true whether or not anything is spawned to represent them.
signal island_severed(assembly_id: int, slots: PackedByteArray)

## Called once per severed island, with the assembly id and the island's slots.
##
## [b]The seam to §6.[/b] [code]IslandDetacher.detach[/code] needs the Assembly's
## [RigidBody3D], its per-part states, and its colliders in order to build a
## debris body, none of which the graph layer has or should have. Assigning that
## function here is how the match scene wires the two together; until it is
## assigned the islands are still computed, still severed, and still announced —
## there is simply no debris body, which is presentation rather than structure.
var island_sink: Callable = Callable()

## The Assemblies this scheduler resolves for. Assigned by the match scene before
## the node enters the tree.
##
## [b]Was a private [code]assembly_id -> ChassisGraph[/code] map.[/b] Two
## schedulers each kept one, and doc 08 §5.3 and doc 12 §7.2 both assumed a third
## that did not exist; [AssemblyRegistry] is that lookup, and this reads the graph
## out of it rather than being told about one separately.
var registry: AssemblyRegistry = null

## Assembly id -> [PackedByteArray] of slots destroyed since the last resolve.
var _pending: Dictionary = {}
## Assembly id -> slots left parentless by a strain failure since the last
## resolve. Kept apart from [member _pending] because an unsupported part is not
## a destroyed one: resolving it as destroyed would delete a part that may still
## be holding on through another edge.
var _pending_orphans: Dictionary = {}
## §5.6. Detaching an island can destroy further parts — a severed Prime Mover
## detonates — and those deaths must land in the next tick's pending set rather
## than re-entering the pass that caused them.
var _reentrancy_guard: bool = false


func _ready() -> void:
	assert(registry != null, "DetachmentScheduler entered the tree with no AssemblyRegistry")
	EventBus.part_destroyed.connect(_on_part_destroyed)
	EventBus.joint_failed.connect(_on_joint_failed)
	EventBus.connect_tick_resolved(_resolve_all, EventBusService.PRIORITY_DETACHMENT)
	registry.assembly_unregistered.connect(_on_assembly_unregistered)


func _exit_tree() -> void:
	EventBus.part_destroyed.disconnect(_on_part_destroyed)
	EventBus.joint_failed.disconnect(_on_joint_failed)
	EventBus.disconnect_tick_resolved(_resolve_all)
	registry.assembly_unregistered.disconnect(_on_assembly_unregistered)


## An Assembly that has left the match has nothing to resolve. Dropping the
## pending set matters: a destruction queued in the tick it was removed would
## otherwise resolve against a graph nobody owns any more.
func _on_assembly_unregistered(assembly_id: int) -> void:
	_pending.erase(assembly_id)
	_pending_orphans.erase(assembly_id)


## Slots awaiting resolution for [param assembly_id]. Used by
## [code]tests/integration/test_detachment_scheduler.gd[/code] to assert that a
## death arriving during a resolve lands in the following tick.
func pending_for(assembly_id: int) -> PackedByteArray:
	var set: PackedByteArray = _pending.get(assembly_id, PackedByteArray())
	return set.duplicate()


func _on_part_destroyed(assembly_id: int, slot: int, _cause: int) -> void:
	_queue(assembly_id, slot)


## A failed joint severs the edge immediately; whether that orphans anything is
## decided in the resolve phase along with everything else that died this tick.
##
## The child left parentless by the severed edge is what gets queued, not the
## joint: §5.3 searches from the neighbours of a removed part, and the part whose
## support was just cut is the one whose route to the Core Module is in doubt.
func _on_joint_failed(assembly_id: int, slot_a: int, slot_b: int) -> void:
	var graph := registry.graph_of(assembly_id)
	if graph == null:
		push_error("DetachmentScheduler: joint_failed for unregistered assembly %d" % assembly_id)
		return
	var orphan := graph.sever_edge(slot_a, slot_b)
	if orphan == SyndicateConstants.INVALID_SLOT:
		return
	_queue_orphan(assembly_id, orphan)


func _queue(assembly_id: int, slot: int) -> void:
	var set: PackedByteArray = _pending.get(assembly_id, PackedByteArray())
	if not set.has(slot):
		set.append(slot)
	_pending[assembly_id] = set


## An orphan is not itself destroyed, so it must not go into the destroyed set —
## resolving would remove a part that is merely unsupported. It goes into a
## parallel set that the resolve phase seeds its search from.
func _queue_orphan(assembly_id: int, slot: int) -> void:
	var set: PackedByteArray = _pending_orphans.get(assembly_id, PackedByteArray())
	if not set.has(slot):
		set.append(slot)
	_pending_orphans[assembly_id] = set


func _resolve_all() -> void:
	if _pending.is_empty() and _pending_orphans.is_empty():
		return  # the overwhelmingly common path
	assert(not _reentrancy_guard, "detachment re-entered")
	_reentrancy_guard = true

	# Ascending assembly id, then ascending slot within each. Not cosmetic: it
	# is what guarantees the server and every client replaying the same event set
	# produce identical island decompositions and identical debris ordering
	# (doc 12 §7.3).
	var ids: Array = _pending.keys()
	for id: int in _pending_orphans.keys():
		if not ids.has(id):
			ids.append(id)
	ids.sort()

	var destroyed_by_id := _pending
	var orphans_by_id := _pending_orphans
	_pending = {}
	_pending_orphans = {}

	for assembly_id: int in ids:
		var destroyed: PackedByteArray = destroyed_by_id.get(assembly_id, PackedByteArray())
		var orphans: PackedByteArray = orphans_by_id.get(assembly_id, PackedByteArray())
		destroyed.sort()
		orphans.sort()
		_resolve_assembly(assembly_id, destroyed, orphans)

	_reentrancy_guard = false


func _resolve_assembly(
	assembly_id: int, destroyed: PackedByteArray, orphans: PackedByteArray
) -> void:
	var graph := registry.graph_of(assembly_id)
	if graph == null:
		push_error("DetachmentScheduler: resolve for unregistered assembly %d" % assembly_id)
		return

	# §7.2. With the root gone every part is orphaned by definition, so there is
	# nothing for reverse-reachability to early-out against and the short-circuit
	# is both cheaper and the only correct classification.
	if destroyed.has(ChassisGraph.CORE):
		_terminate(assembly_id, graph, destroyed)
		return

	var islands := DetachmentSolver.solve(graph, destroyed)
	islands.append_array(_resolve_orphans(graph, orphans, islands))
	islands.sort_custom(DetachmentSolver.compare_islands)

	for island in islands:
		_announce(assembly_id, island)

	if not destroyed.is_empty() or not islands.is_empty():
		EventBus.assembly_structure_changed.emit(assembly_id)
	if graph.is_mass_dirty():
		graph.clear_mass_dirty()
		EventBus.assembly_mass_dirty.emit(assembly_id)


## Severs the parts a strain failure left unsupported.
##
## An orphan whose edge failed may still reach the Core Module through another
## neighbour, in which case it stays and [DetachmentSolver] has already given it
## a new parent. Only the ones that cannot are severed, and only those not
## already accounted for by an island from the destroyed set.
func _resolve_orphans(
	graph: ChassisGraph, orphans: PackedByteArray, existing: Array[PackedByteArray]
) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for o in orphans:
		var orphan := int(o)
		if not graph.is_alive(orphan):
			continue
		if _in_any(existing, orphan) or _in_any(out, orphan):
			continue
		if graph.is_connected_to_core(orphan):
			if int(graph.parent[orphan]) == SyndicateConstants.INVALID_SLOT:
				var alt := MateSelector.choose_support_parent(graph, orphan)
				if alt != SyndicateConstants.INVALID_SLOT:
					graph.reparent(orphan, alt)
			continue
		# The part is intact and merely unsupported, so it is the island rather
		# than the hole in one.
		out.append(DetachmentSolver.sever_unsupported(graph, orphan))
	return out


## §7.2. Every remaining part becomes debris; the components are found with the
## one full flood fill in the project that is correct, because every node
## genuinely has to be classified.
func _terminate(assembly_id: int, graph: ChassisGraph, destroyed: PackedByteArray) -> void:
	# The parts that died this tick are gone, not debris. Partitioning before
	# removing them would put the destroyed Core Module in a component and spawn
	# a body for a part that no longer exists.
	for s in destroyed:
		var slot := int(s)
		if graph.is_alive(slot):
			graph.remove_node(slot)

	var components := DetachmentSolver.partition_live_components(graph)
	for component in components:
		for s in component:
			var slot := int(s)
			if graph.is_alive(slot):
				graph.remove_node(slot)
		_announce(assembly_id, component)
	# And nothing is emitted here. Doc 04 §8.2: "the producer is therefore
	# `DamageResolver`, and it is the only one … nothing else may emit it."
	#
	# This used to emit `assembly_terminated(assembly_id, 0)`, with a comment
	# saying attribution belonged to the damage layer "until it does". It does:
	# `DamageResolver` has emitted the attributed event since session 16, on the
	# same tick, from the destruction of slot 0 that is the only thing that can
	# bring `_terminate` here in the first place — CLAUDE.md §10 rule 10 lets
	# nothing else write integrity. So this line was not a fallback, it was a
	# second announcement of every death, and it was visible in the match HUD as
	# a player's own destruction reported twice: once by whoever killed them and
	# once by nobody.
	#
	# Two producers of one invariant is worse than either alone, and this is the
	# tenth time that has been true in this repository.


func _announce(assembly_id: int, island: PackedByteArray) -> void:
	island_severed.emit(assembly_id, island)
	if island_sink.is_valid():
		island_sink.call(assembly_id, island)


static func _in_any(islands: Array[PackedByteArray], slot: int) -> bool:
	for island in islands:
		if island.has(slot):
			return true
	return false
