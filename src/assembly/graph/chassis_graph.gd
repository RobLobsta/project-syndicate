class_name ChassisGraph
extends RefCounted
## The structural topology of one Assembly, owned by
## [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §2 and §3.
##
## Two overlaid structures over the same slots. The [b]primary tree[/b]
## ([member parent], [member children], [member depth]) carries hierarchy: load
## paths, subtree mass, and the re-parenting the garage does when a part is
## removed. The [b]support edge graph[/b] ([member neighbours]) carries physical
## adjacency and is the [i]only[/i] structure connectivity is evaluated over
## (§11 invariant 3) — a part hanging off a severed branch may still be attached
## to the Assembly through a support edge its tree parent knows nothing about.
##
## Architectural Invariant I-4: this class declares no [code]_process[/code] and
## no [code]_physics_process[/code]. Every array below changes only in response
## to a discrete attach, detach, or re-parent. A match with no destruction costs
## zero graph CPU time. [code]tests/arch/test_no_polling.gd[/code] enforces it.
##
## Architectural Invariant I-3: nothing here is a physics constraint. An
## Assembly is one [RigidBody3D]; these edges describe which parts hold which
## others up, and structural failure is a topological event, never a joint.
##
## [b]Scope.[/b] This is §2, §3, and the connectivity traversal §5.3 is built
## on. Strain accumulation (§4) and the detachment solver (§5) are separate
## systems that read these arrays; [member edge_strain] is allocated and kept in
## sync by the edge writers here so that adding the solver does not have to
## rewrite them.

const MAX: int = SyndicateConstants.MAX_PARTS_PER_ASSEMBLY
const INVALID: int = SyndicateConstants.INVALID_SLOT
const CORE: int = SyndicateConstants.CORE_SLOT

## ===== PRIMARY TREE ====================================================

## Slot -> its primary parent, or [constant INVALID] for the root and for
## unattached slots.
var parent: PackedByteArray = PackedByteArray()
## Slot -> its primary children, ascending. Ascending by construction because
## slots are allocated lowest-first and appended in allocation order.
var children: Array[PackedByteArray] = []
## Slot -> depth in the primary tree. The Core Module is depth 0.
var depth: PackedByteArray = PackedByteArray()

## ===== SUPPORT EDGE GRAPH ==============================================

## Slot -> mated slots. Edges are stored at both endpoints so that neighbour
## iteration is one contiguous read with no indirection.
var neighbours: Array[PackedByteArray] = []
## Parallel to [member neighbours]: rated strength (N) of the edge at the same
## index.
var edge_strength: Array[PackedFloat32Array] = []
## Parallel to [member neighbours]: accumulated strain fraction [0,1] of the
## edge at the same index. Written by the strain model of §4.
var edge_strain: Array[PackedFloat32Array] = []

## ===== CACHED AGGREGATES ===============================================

## Slot -> the part's own mass in kilograms.
##
## [b]Addition to §2.1 as originally written.[/b] §3.1 calls
## [code]m_mass_of(slot)[/code] but §2.1 declared no field to hold it, leaving
## the graph unable to compute the mass delta its own attach path propagates.
## Storing it alongside [member subtree_mass] follows the precedent of the other
## cached aggregates and keeps the graph free of a [code]PartRegistry[/code]
## dependency. §2.1 records the field.
var mass_kg: PackedFloat32Array = PackedFloat32Array()
## Slot -> mass of the slot plus every descendant in the [b]primary tree[/b].
## Maintained by walking to the root on each change (§3.3), never recomputed.
var subtree_mass: PackedFloat32Array = PackedFloat32Array()
## Slot -> 1 when the slot participates in structure.
var alive: PackedByteArray = PackedByteArray()

## ===== TRAVERSAL SCRATCH ===============================================
## Preallocated. §11 invariant 9: no heap allocation occurs in the traversal
## path during a match.

var _visit_stamp: PackedInt32Array = PackedInt32Array()
var _stamp_counter: int = 0
var _queue: PackedByteArray = PackedByteArray()

## The stamp counter wraps here rather than at int32 max, so the wrap branch is
## reachable by a test instead of only after two billion traversals.
const _STAMP_WRAP: int = 0x7FFFFFFF


func _init() -> void:
	parent.resize(MAX)
	parent.fill(INVALID)
	depth.resize(MAX)
	depth.fill(0)
	alive.resize(MAX)
	alive.fill(0)
	mass_kg.resize(MAX)
	mass_kg.fill(0.0)
	subtree_mass.resize(MAX)
	subtree_mass.fill(0.0)
	_visit_stamp.resize(MAX)
	_visit_stamp.fill(0)
	_queue.resize(MAX)
	children.resize(MAX)
	neighbours.resize(MAX)
	edge_strength.resize(MAX)
	edge_strain.resize(MAX)
	for i in MAX:
		children[i] = PackedByteArray()
		neighbours[i] = PackedByteArray()
		edge_strength[i] = PackedFloat32Array()
		edge_strain[i] = PackedFloat32Array()


## Registers [param slot] with [param primary_parent] as its tree parent and one
## support edge per record in [param mates], per §3.1.
##
## [param primary_parent] must be [constant INVALID] only for the Core Module at
## slot 0 (Architectural Invariant I-2). The caller chooses it through
## [method MateSelector.choose_primary]; passing an arbitrary mate here would
## make the tree — and therefore every load path — depend on placement order.
func attach(
	slot: int, primary_parent: int, mates: Array[MateRecord], part_mass_kg: float
) -> void:
	assert(slot >= 0 and slot < MAX, "slot out of range: %d" % slot)
	assert(alive[slot] == 0, "slot %d is already live" % slot)
	assert(
		primary_parent == INVALID or alive[primary_parent] == 1,
		"slot %d attached to dead parent %d" % [slot, primary_parent]
	)
	assert(
		primary_parent != INVALID or slot == CORE,
		"only the Core Module may be rootless; slot %d is not slot 0" % slot
	)

	alive[slot] = 1
	parent[slot] = primary_parent
	depth[slot] = 0 if primary_parent == INVALID else depth[primary_parent] + 1
	mass_kg[slot] = part_mass_kg

	if primary_parent != INVALID:
		var kids: PackedByteArray = children[primary_parent]
		kids.push_back(slot)
		children[primary_parent] = kids

	for m in mates:
		_add_edge(slot, m.other_slot, m.joint_strength_n)

	_propagate_mass_delta(slot, part_mass_kg)


## Removes [param slot] from the tree and from every support edge.
##
## The slot must have no primary children: the caller decides what happens to an
## orphaned subtree — the garage re-parents where it can (§9.2 of doc 02), a
## match severs it into a debris island — and that decision cannot be made here
## without knowing which of the two is running.
func detach(slot: int) -> void:
	assert(slot >= 0 and slot < MAX, "slot out of range: %d" % slot)
	assert(alive[slot] == 1, "slot %d is not live" % slot)
	assert(
		children[slot].is_empty(),
		"slot %d still has %d primary children; re-parent or remove them first"
		% [slot, children[slot].size()]
	)

	_propagate_mass_delta(slot, -mass_kg[slot])

	var p := int(parent[slot])
	if p != INVALID:
		var kids: PackedByteArray = children[p]
		var at := kids.find(slot)
		if at != -1:
			kids.remove_at(at)
			children[p] = kids

	for other in neighbours[slot]:
		_remove_edge_one_way(int(other), slot)

	neighbours[slot] = PackedByteArray()
	edge_strength[slot] = PackedFloat32Array()
	edge_strain[slot] = PackedFloat32Array()
	parent[slot] = INVALID
	depth[slot] = 0
	alive[slot] = 0
	mass_kg[slot] = 0.0
	subtree_mass[slot] = 0.0


## Lifts [param slot]'s direct children off it and returns them, so that
## [method detach] can then remove a childless slot.
##
## The returned slots stay alive with [member parent] set to [constant INVALID].
## That is a deliberate intermediate state, not a valid resting one: the caller
## must re-parent or remove every slot returned here before the edit completes.
## The garage's removal path (§9.2 of doc 02) does exactly that, and it is the
## only reason a live non-root slot may be parentless.
func detach_orphaning_children(slot: int) -> PackedByteArray:
	assert(alive[slot] == 1, "slot %d is not live" % slot)
	var kids: PackedByteArray = children[slot]
	for kid in kids:
		# Remove the child's whole subtree from this slot and every ancestor
		# before cutting the link, while subtree_mass[kid] still describes it.
		_propagate_mass_delta(slot, -subtree_mass[kid])
		parent[kid] = INVALID
		_refresh_depths(kid)
	children[slot] = PackedByteArray()
	return kids


## Moves [param slot] and its whole subtree under [param new_parent].
##
## Support edges are untouched: re-parenting changes which part is considered to
## hold this one up, not which parts it physically touches.
func reparent(slot: int, new_parent: int) -> void:
	assert(alive[slot] == 1, "slot %d is not live" % slot)
	assert(alive[new_parent] == 1, "new parent %d is not live" % new_parent)
	assert(slot != CORE, "the Core Module is the root and cannot be re-parented")
	assert(
		not _is_descendant_of(new_parent, slot),
		"re-parenting slot %d under its own descendant %d would cycle" % [slot, new_parent]
	)
	if int(parent[slot]) == new_parent:
		return

	var moved := subtree_mass[slot]
	var old_parent := int(parent[slot])
	if old_parent != INVALID:
		var kids: PackedByteArray = children[old_parent]
		var at := kids.find(slot)
		if at != -1:
			kids.remove_at(at)
			children[old_parent] = kids
		_propagate_mass_delta(old_parent, -moved)

	parent[slot] = new_parent
	var new_kids: PackedByteArray = children[new_parent]
	new_kids.push_back(slot)
	children[new_parent] = new_kids
	_propagate_mass_delta(new_parent, moved)
	_refresh_depths(slot)


## [param slot] and every descendant in the primary tree, in breadth-first order
## from [param slot]. Deterministic: [member children] is ascending, so the same
## tree always yields the same list (Architectural Invariant I-9).
func subtree_slots(slot: int) -> PackedByteArray:
	var out := PackedByteArray()
	if slot < 0 or slot >= MAX or alive[slot] == 0:
		return out
	var head := 0
	var tail := 0
	_queue[tail] = slot
	tail += 1
	while head < tail:
		var s := int(_queue[head])
		head += 1
		out.append(s)
		for kid in children[s]:
			_queue[tail] = kid
			tail += 1
	return out


## True when [param slot] reaches the Core Module through support edges.
##
## Over support edges, never over the primary tree (§11 invariant 3). This is
## the query the garage's re-parenting uses to reject a candidate parent that is
## itself already severed, and the same reachability the detachment solver of §5
## runs in reverse.
func is_connected_to_core(slot: int) -> bool:
	if slot < 0 or slot >= MAX or alive[slot] == 0:
		return false
	if slot == CORE:
		return true
	if alive[CORE] == 0:
		return false

	var stamp := _begin_traversal()
	var head := 0
	var tail := 0
	_queue[tail] = slot
	tail += 1
	_visit_stamp[slot] = stamp
	while head < tail:
		var s := int(_queue[head])
		head += 1
		for n in neighbours[s]:
			var ns := int(n)
			if ns == CORE:
				return true
			if _visit_stamp[ns] == stamp or alive[ns] == 0:
				continue
			_visit_stamp[ns] = stamp
			_queue[tail] = ns
			tail += 1
	return false


## Index of the edge to [param b] within [param a]'s parallel arrays, or -1.
func edge_index(a: int, b: int) -> int:
	if a < 0 or a >= MAX:
		return -1
	return neighbours[a].find(b)


## Rated strength of the support edge between [param a] and [param b], or 0.0
## when no such edge exists.
func edge_strength_between(a: int, b: int) -> float:
	var i := edge_index(a, b)
	return 0.0 if i == -1 else edge_strength[a][i]


## Writes [param strain] to both stored copies of the edge.
##
## Both endpoints hold the edge, so a writer that updates one copy leaves the
## other stale and the strain a part reports then depends on which end asked.
func set_edge_strain(a: int, b: int, strain: float) -> void:
	var ia := edge_index(a, b)
	var ib := edge_index(b, a)
	if ia == -1 or ib == -1:
		push_error("ChassisGraph: no support edge between slots %d and %d" % [a, b])
		return
	var sa := edge_strain[a]
	sa[ia] = strain
	edge_strain[a] = sa
	var sb := edge_strain[b]
	sb[ib] = strain
	edge_strain[b] = sb


func edge_strain_between(a: int, b: int) -> float:
	var i := edge_index(a, b)
	return 0.0 if i == -1 else edge_strain[a][i]


func is_alive(slot: int) -> bool:
	if slot < 0 or slot >= MAX:
		return false
	return alive[slot] == 1


func mass_of(slot: int) -> float:
	if slot < 0 or slot >= MAX:
		return 0.0
	return mass_kg[slot]


## Live slots in ascending order. Ascending by construction so that every
## traversal built on it is reproducible (Architectural Invariant I-9).
func live_slots() -> PackedByteArray:
	var out := PackedByteArray()
	for s in MAX:
		if alive[s] == 1:
			out.append(s)
	return out


## Deterministic textual dump, per §10. Used by tests and by the in-match
## developer overlay. Carries no timestamp and no float formatting beyond one
## decimal, so two runs over the same graph are byte-identical.
func debug_report() -> String:
	var sb := PackedStringArray()
	sb.append("slot parent depth alive mass_kg subtree_kg neighbours")
	for s in MAX:
		if alive[s] == 0 and int(parent[s]) == INVALID:
			continue
		sb.append(
			(
				"%4d %6d %5d %5d %7.1f %10.1f  %s"
				% [
					s,
					int(parent[s]),
					int(depth[s]),
					int(alive[s]),
					mass_kg[s],
					subtree_mass[s],
					String(",").join(_slot_list(neighbours[s])),
				]
			)
		)
	return String("\n").join(sb)


## ===== PRIVATE =========================================================


func _add_edge(a: int, b: int, strength: float) -> void:
	assert(a != b, "a slot cannot mate with itself: %d" % a)
	assert(alive[b] == 1, "slot %d mated to dead slot %d" % [a, b])
	if neighbours[a].has(b):
		# Two nodes of the same part pair may mate against the same neighbour —
		# a wide part meeting a wide part shares several faces. That is one
		# physical joint, and duplicating the edge would double-count it in
		# every strain and connectivity sum.
		return

	var na: PackedByteArray = neighbours[a]
	var sa: PackedFloat32Array = edge_strength[a]
	var ta: PackedFloat32Array = edge_strain[a]
	na.push_back(b)
	sa.push_back(strength)
	ta.push_back(0.0)
	neighbours[a] = na
	edge_strength[a] = sa
	edge_strain[a] = ta

	var nb: PackedByteArray = neighbours[b]
	var sb: PackedFloat32Array = edge_strength[b]
	var tb: PackedFloat32Array = edge_strain[b]
	nb.push_back(a)
	sb.push_back(strength)
	tb.push_back(0.0)
	neighbours[b] = nb
	edge_strength[b] = sb
	edge_strain[b] = tb


func _remove_edge_one_way(owner_slot: int, other: int) -> void:
	var n: PackedByteArray = neighbours[owner_slot]
	var at := n.find(other)
	if at == -1:
		return
	var s: PackedFloat32Array = edge_strength[owner_slot]
	var t: PackedFloat32Array = edge_strain[owner_slot]
	n.remove_at(at)
	s.remove_at(at)
	t.remove_at(at)
	neighbours[owner_slot] = n
	edge_strength[owner_slot] = s
	edge_strain[owner_slot] = t


## Adds [param delta] to [param from_slot] and to every ancestor, per §3.3.
##
## The guard is not defensive padding. The primary tree being acyclic is an
## invariant other code can violate through a bug, and a silent infinite loop
## inside a physics tick is far worse than an assertion.
func _propagate_mass_delta(from_slot: int, delta: float) -> void:
	var s := from_slot
	var guard := 0
	while s != INVALID:
		subtree_mass[s] += delta
		s = int(parent[s])
		guard += 1
		assert(guard <= MAX, "cycle detected in primary tree at slot %d" % from_slot)


## Rewrites [member depth] for [param root] and its subtree after a re-parent.
func _refresh_depths(root: int) -> void:
	var head := 0
	var tail := 0
	_queue[tail] = root
	tail += 1
	while head < tail:
		var s := int(_queue[head])
		head += 1
		var p := int(parent[s])
		depth[s] = 0 if p == INVALID else depth[p] + 1
		for kid in children[s]:
			_queue[tail] = kid
			tail += 1


func _is_descendant_of(candidate: int, ancestor: int) -> bool:
	var s := candidate
	var guard := 0
	while s != INVALID:
		if s == ancestor:
			return true
		s = int(parent[s])
		guard += 1
		assert(guard <= MAX, "cycle detected in primary tree at slot %d" % candidate)
	return false


## Increments the traversal stamp, per §2.2.
##
## A slot counts as visited this traversal iff its stamp equals the counter, so
## no clearing is ever required and a traversal costs exactly what it touches
## rather than [constant MAX].
func _begin_traversal() -> int:
	_stamp_counter += 1
	if _stamp_counter >= _STAMP_WRAP:
		_visit_stamp.fill(0)
		_stamp_counter = 1
	return _stamp_counter


static func _slot_list(slots: PackedByteArray) -> PackedStringArray:
	var out := PackedStringArray()
	for s in slots:
		out.append(str(s))
	return out
