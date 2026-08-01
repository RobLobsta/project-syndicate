class_name DetachmentSolver
extends RefCounted
## Decides which parts stopped being attached to the Core Module, per
## [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §5.
##
## The obvious algorithm on losing a part is a flood fill from the Core Module
## across everything that remains, detaching whatever it fails to reach. That is
## [code]O(V + E)[/code] — about 180 nodes and 400 edges, roughly 15 µs — and it
## costs the same whether one panel came off or half the hull did. During a
## cascade, with a spar taking twelve parts across four ticks and thirty-two
## Assemblies under fire at once, paying it per event is not affordable.
##
## §5.3 instead runs [b]local reverse-reachability with early-out[/b]. Only parts
## that were reaching the Core Module [i]through[/i] the removed part can have
## been orphaned, so the search starts at its surviving neighbours and stops the
## instant it touches the Core Module or a node already proven connected in the
## same pass. Cost then scales with the size of the damage rather than the size
## of the Assembly.
##
## Architectural Invariant I-4: no [code]_process[/code], no
## [code]_physics_process[/code]. Every entry point here is called from a
## discrete structural event. [code]tests/arch/test_no_polling.gd[/code] enforces
## it over this whole directory.

const INVALID: int = SyndicateConstants.INVALID_SLOT

## §7.2 caps how many bodies the loss of a Core Module may produce. The remainder
## merges into the largest component rather than being dropped, so no part
## silently ceases to exist.
const MAX_TERMINAL_COMPONENTS: int = 8


## Removes every slot in [param removed_slots] and returns the severed islands,
## one [PackedByteArray] of slots per island.
##
## Surviving parts that lost their tree parent but not their connection are
## re-parented onto the best-ranked surviving neighbour before returning, so the
## primary tree is left valid. That is not the garage's re-parenting of §9.1 —
## there is no confirmation and nothing is kept that the support edges do not
## already hold up — but the tree still has to describe the Assembly that
## remains, because [member ChassisGraph.subtree_mass] and every strain figure
## computed from it are read off it.
##
## Islands are returned in ascending order of their lowest slot, and the slots
## within each island ascend. Both orderings are what lets a client replaying the
## same event set produce the same island decomposition and the same debris body
## ordering as the server (Architectural Invariant I-9, and §5.5).
static func solve(graph: ChassisGraph, removed_slots: PackedByteArray) -> Array[PackedByteArray]:
	var islands: Array[PackedByteArray] = []

	# Seeds are collected before any removal: once a slot is gone so are its
	# edges, and the neighbours that were hanging off it are exactly the parts
	# whose route to the Core Module may have just been cut.
	var seeds := PackedByteArray()
	var orphans := PackedByteArray()
	for s in removed_slots:
		var slot := int(s)
		if not graph.is_alive(slot):
			continue
		for n in graph.neighbours[slot]:
			var neighbour := int(n)
			if not removed_slots.has(neighbour) and not seeds.has(neighbour):
				seeds.append(neighbour)
		for o in graph.remove_node(slot):
			var orphan := int(o)
			if not orphans.has(orphan):
				orphans.append(orphan)

	seeds.sort()

	var proven := graph.begin_traversal()
	# The Core Module is proven by definition, so any search that reaches it
	# terminates on the same comparison that terminates on an earlier success.
	if graph.is_alive(ChassisGraph.CORE):
		graph.mark_visited(ChassisGraph.CORE, proven)

	for s in seeds:
		var seed := int(s)
		if not graph.is_alive(seed):
			continue
		if graph.visit_stamp_of(seed) == proven:
			continue
		var reached := _search_from(graph, seed, proven)
		if reached.connected:
			for v in reached.visited:
				graph.mark_visited(int(v), proven)
		else:
			var island: PackedByteArray = reached.visited.duplicate()
			island.sort()
			islands.append(island)

	# Sever first, re-parent second. Severing an island orphans any survivor
	# whose tree parent was in it, so the orphan set is not complete until the
	# islands are gone — and once they are, a leaving part can no longer be
	# picked as a new parent, because it is no longer alive.
	for o in _sever(graph, islands):
		var orphan := int(o)
		if not orphans.has(orphan):
			orphans.append(orphan)
	_reparent_survivors(graph, orphans)

	islands.sort_custom(compare_islands)
	return islands


## Convenience for the single-part case of §5.3.
static func solve_one(graph: ChassisGraph, removed_slot: int) -> Array[PackedByteArray]:
	var one := PackedByteArray()
	one.append(removed_slot)
	return solve(graph, one)


## Severs the whole component containing [param seed] and returns its slots.
##
## The counterpart of [method solve] for a part that was left [i]unsupported[/i]
## rather than destroyed — a strain failure cuts a joint, and the part that was
## hanging from it is still intact. [method solve] cannot serve: it treats its
## argument as a part that has ceased to exist and searches outwards from the
## neighbours it leaves behind, so an unsupported leaf would be quietly deleted
## and no island reported for it. Here the part is itself the island, along with
## everything still attached to it.
##
## The caller must have established that [param seed] cannot reach the Core
## Module. Called on a connected part this would sever the Assembly from itself.
static func sever_unsupported(graph: ChassisGraph, seed: int) -> PackedByteArray:
	assert(graph.is_alive(seed), "slot %d is not live" % seed)
	assert(not graph.is_connected_to_core(seed), "slot %d still reaches the core" % seed)

	var component := _flood(graph, seed, graph.begin_traversal())
	component.sort()
	var islands: Array[PackedByteArray] = [component]
	_reparent_survivors(graph, _sever(graph, islands))
	return component


## Partitions every live part into connected components, for the Core Module loss
## of §7.2.
##
## This is the one place a full flood fill is correct: with the root gone every
## part is orphaned by definition, so there is nothing for reverse-reachability
## to early-out against and every node genuinely has to be classified.
##
## Components beyond [constant MAX_TERMINAL_COMPONENTS] merge into the largest,
## per §7.2. Ties on size break on the lowest slot, so which component absorbs
## the remainder never depends on traversal order.
static func partition_live_components(graph: ChassisGraph) -> Array[PackedByteArray]:
	var components: Array[PackedByteArray] = []
	var stamp := graph.begin_traversal()
	for s in graph.live_slots():
		var slot := int(s)
		if graph.visit_stamp_of(slot) == stamp:
			continue
		var component := _flood(graph, slot, stamp)
		component.sort()
		components.append(component)
	components.sort_custom(compare_islands)

	if components.size() > MAX_TERMINAL_COMPONENTS:
		components = _merge_smallest_into_largest(components)
	return components


## ===== PRIVATE =========================================================


## Breadth-first over support edges from [param seed], stopping the moment the
## Core Module or an already-proven node is reached.
##
## [param proven_stamp] comes from an earlier [method ChassisGraph.begin_traversal]
## and the local stamp from a later one. Since the counter only increments, the
## proven stamp is strictly less than every local stamp and the two comparisons
## below cannot alias — which is the subtlety §5.3 calls out, and the reason the
## counter has a wrap branch at all.
static func _search_from(graph: ChassisGraph, seed: int, proven_stamp: int) -> SearchResult:
	var visited := PackedByteArray()
	var local_stamp := graph.begin_traversal()
	var queue := PackedByteArray()
	queue.append(seed)
	graph.mark_visited(seed, local_stamp)

	var head := 0
	while head < queue.size():
		var cur := int(queue[head])
		head += 1
		visited.append(cur)
		if cur == ChassisGraph.CORE:
			return SearchResult.new(true, visited)
		for n in graph.neighbours[cur]:
			var neighbour := int(n)
			if graph.alive[neighbour] == 0:
				continue
			if graph.visit_stamp_of(neighbour) == proven_stamp:
				visited.append(neighbour)
				return SearchResult.new(true, visited)
			if graph.visit_stamp_of(neighbour) == local_stamp:
				continue
			graph.mark_visited(neighbour, local_stamp)
			queue.append(neighbour)
	return SearchResult.new(false, visited)


## Every live slot reachable from [param seed] over support edges, marking as it
## goes. Used only by the full partition of §7.2.
static func _flood(graph: ChassisGraph, seed: int, stamp: int) -> PackedByteArray:
	var out := PackedByteArray()
	var queue := PackedByteArray()
	queue.append(seed)
	graph.mark_visited(seed, stamp)

	var head := 0
	while head < queue.size():
		var cur := int(queue[head])
		head += 1
		out.append(cur)
		for n in graph.neighbours[cur]:
			var neighbour := int(n)
			if graph.alive[neighbour] == 0:
				continue
			if graph.visit_stamp_of(neighbour) == stamp:
				continue
			graph.mark_visited(neighbour, stamp)
			queue.append(neighbour)
	return out


## Gives every survivor that lost its tree parent a new one.
##
## Ascending, so that two orphans competing for the same parent always resolve
## the same way. A survivor left parentless would keep its mass out of every
## ancestor's [member ChassisGraph.subtree_mass] and out of every strain figure
## computed from it, which is silent and permanent — hence the error rather than
## a quiet skip.
static func _reparent_survivors(graph: ChassisGraph, orphans: PackedByteArray) -> void:
	orphans.sort()
	for o in orphans:
		var orphan := int(o)
		if not graph.is_alive(orphan) or orphan == ChassisGraph.CORE:
			continue
		if int(graph.parent[orphan]) != INVALID:
			continue
		var alt := MateSelector.choose_support_parent(graph, orphan)
		if alt != INVALID:
			graph.reparent(orphan, alt)
		else:
			push_error(
				"DetachmentSolver: slot %d survived with no re-parenting candidate" % orphan
			)


## Takes the island slots out of the graph and returns the survivors they
## orphaned on the way out.
##
## Removal order within an island does not matter, and deliberately so:
## [method ChassisGraph.remove_node] lifts a slot's children off it before
## detaching it, so a part is never asked to leave while something still hangs
## from it. Ascending slot order is used because the island is already in it.
##
## The children that come back are the ones from [i]outside[/i] the island —
## parts whose tree parent was severed but whose own route to the Core Module
## runs through some other support edge.
static func _sever(graph: ChassisGraph, islands: Array[PackedByteArray]) -> PackedByteArray:
	var orphaned := PackedByteArray()
	for island in islands:
		for s in island:
			var slot := int(s)
			if not graph.is_alive(slot):
				continue
			for o in graph.remove_node(slot):
				var orphan := int(o)
				if not island.has(orphan) and not orphaned.has(orphan):
					orphaned.append(orphan)
	return orphaned


## Merges everything past the cap into the largest component, per §7.2.
static func _merge_smallest_into_largest(
	components: Array[PackedByteArray]
) -> Array[PackedByteArray]:
	var by_size := components.duplicate()
	by_size.sort_custom(_compare_by_descending_size)

	var kept: Array[PackedByteArray] = []
	for i in MAX_TERMINAL_COMPONENTS:
		kept.append(by_size[i])
	var largest: PackedByteArray = kept[0]
	for i: int in range(MAX_TERMINAL_COMPONENTS, by_size.size()):
		largest.append_array(by_size[i])
	largest.sort()
	kept[0] = largest

	kept.sort_custom(compare_islands)
	return kept


## Ascending by lowest slot. Every island is itself sorted, so element 0 is its
## lowest slot and no island can tie with another.
##
## Public because [DetachmentScheduler] merges islands from two sources — the
## parts destroyed this tick and the parts a failed joint left unsupported — and
## the merged list has to carry the same order a single pass would have produced.
static func compare_islands(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.is_empty() or b.is_empty():
		return b.is_empty() and not a.is_empty()
	return a[0] < b[0]


static func _compare_by_descending_size(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return a.size() > b.size()
	return compare_islands(a, b)


## The outcome of one reverse-reachability search.
##
## [member visited] is every node the search popped. On success those are all
## proven connected and get stamped, which is what makes the next seed's search
## early-out instead of re-walking the same region.
class SearchResult:
	extends RefCounted

	var connected: bool = false
	var visited: PackedByteArray = PackedByteArray()

	func _init(is_connected: bool, seen: PackedByteArray) -> void:
		connected = is_connected
		visited = seen
