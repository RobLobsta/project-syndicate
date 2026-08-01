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
## [b]Scope.[/b] This is §2, §3, and §4 — topology, mass aggregation, and the
## strain model that runs over it. The detachment solver of §5 is a separate
## class that reads these arrays; the connectivity traversal it is built on lives
## here because the garage's re-parenting search needs the same query.

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
## Parallel to [member neighbours]: 1 when [b]both[/b] nodes forming the edge at
## the same index declare [member AttachmentNodeDef.can_bear_load].
##
## [b]Addition to §2.1 as originally written.[/b] §3.2's first ordering key is
## whether a joint bears load on both sides, and until this array existed that
## fact lived only on the [MateRecord] the placement produced and was discarded
## once the edge was built. Re-parenting after a destruction (§5.3) has no mate
## records to consult, so without it the match path would have had to rank
## survivors on three of §3.2's four keys while the garage ranked them on four —
## the exact drift [method MateSelector.outranks] exists to prevent. §2.1 records
## the field.
var edge_bears_load: Array[PackedByteArray] = []

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

## ===== STRAIN (§4) =====================================================

## Bounds and smoothing of the dynamic amplification factor, per §4.1.
const KAPPA_MIN: float = 1.0
const KAPPA_MAX: float = 3.6
const KAPPA_SMOOTHING: float = 0.25

## Seconds an edge must stay above [constant STRAIN_LIMIT] before it fails, §4.2.
const STRAIN_FAILURE_DWELL_S: float = 0.45
## Strain fraction at which a joint is transmitting exactly its rated strength.
const STRAIN_LIMIT: float = 1.0
## Strain at or above which an edge joins the dwell-tracked candidate set.
## Edges below it are never revisited (§4.2).
const STRAIN_CANDIDATE_THRESHOLD: float = 0.85
## Change in an edge's strain worth telling the presentation layer about. Below
## this, the stress decal and the groan cue would not perceptibly differ.
const STRAIN_REPORT_EPSILON: float = 0.01

## Time constant of the exponential decay applied to both deposit terms of §4.1.
## Owned by [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code] §6.2 for impact.
const IMPACT_DECAY_TAU_S: float = 0.9
## Recoil is a sustained load only while an Effector Module keeps cycling, so it
## decays over roughly the cycle time of a slow effector.
const RECOIL_DECAY_TAU_S: float = 0.6
## Deposit below which a slot is dropped from the decay set entirely. A newton is
## far under the resolution of any joint strength in the part tables.
const DEPOSIT_FLOOR_N: float = 1.0

## Dynamic amplification of the static hanging load, §4.1. Starts at rest.
var _kappa: float = KAPPA_MIN
## Slot -> peak sustained recoil force deposited by Effector Modules at it.
var _recoil_deposit: PackedFloat32Array = PackedFloat32Array()
## Slot -> peak recent collision force deposited at it, decaying.
var _impact_deposit: PackedFloat32Array = PackedFloat32Array()
## Slots carrying a non-zero deposit of either kind, so decay costs nothing when
## nothing is loaded (§6.2 of doc 08 makes the same point).
var _deposit_active: PackedByteArray = PackedByteArray()

## Slots owning at least one edge at or above [constant
## STRAIN_CANDIDATE_THRESHOLD]. Rebuilt by [method recompute_strain], which is
## the only writer of [member edge_strain].
var _strained_candidates: PackedByteArray = PackedByteArray()
## Canonical edge key -> seconds the edge has spent at or above the limit.
var _dwell: Dictionary = {}

## Scratch for the post-order deposit accumulation in [method recompute_strain].
var _subtree_recoil: PackedFloat32Array = PackedFloat32Array()
var _subtree_impact: PackedFloat32Array = PackedFloat32Array()
## Scratch for the counting sort in [method _order_by_descending_depth].
var _depth_counts: PackedInt32Array = PackedInt32Array()
var _depth_order: PackedByteArray = PackedByteArray()

## Set by [method _propagate_mass_delta], per §3.3. Read and cleared by the mass
## solver, which is what turns it into [signal EventBusService.assembly_mass_dirty].
var _mass_dirty: bool = false

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
	_recoil_deposit.resize(MAX)
	_recoil_deposit.fill(0.0)
	_impact_deposit.resize(MAX)
	_impact_deposit.fill(0.0)
	_subtree_recoil.resize(MAX)
	_subtree_impact.resize(MAX)
	_depth_counts.resize(MAX)
	_depth_order.resize(MAX)
	children.resize(MAX)
	neighbours.resize(MAX)
	edge_strength.resize(MAX)
	edge_strain.resize(MAX)
	edge_bears_load.resize(MAX)
	for i in MAX:
		children[i] = PackedByteArray()
		neighbours[i] = PackedByteArray()
		edge_strength[i] = PackedFloat32Array()
		edge_strain[i] = PackedFloat32Array()
		edge_bears_load[i] = PackedByteArray()


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
		_add_edge(slot, m.other_slot, m.joint_strength_n, m.bears_load)

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
		_dwell.erase(_dwell_key(slot, int(other)))

	neighbours[slot] = PackedByteArray()
	edge_strength[slot] = PackedFloat32Array()
	edge_strain[slot] = PackedFloat32Array()
	edge_bears_load[slot] = PackedByteArray()
	parent[slot] = INVALID
	depth[slot] = 0
	alive[slot] = 0
	mass_kg[slot] = 0.0
	subtree_mass[slot] = 0.0
	_recoil_deposit[slot] = 0.0
	_impact_deposit[slot] = 0.0
	_forget_deposits(slot)
	var at_cand := _strained_candidates.find(slot)
	if at_cand != -1:
		_strained_candidates.remove_at(at_cand)


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


## Removes [param slot] whatever it was holding up, and returns the children it
## orphaned. This is the match-mode counterpart of the garage's cascading
## removal, and the [code]remove_node[/code] §5.3 calls before it seeds its
## search.
##
## [b]Addition to §5.3 as originally written.[/b] §5.3 calls
## [code]graph.remove_node(removed_slot)[/code] without defining it, and
## [method detach] cannot serve: it requires a childless slot, which a destroyed
## part in the middle of a hull never is. Splitting the orphaning out and
## returning the orphans is what lets the caller re-parent the survivors — the
## ones that turn out to still reach the Core Module through a support edge —
## rather than pretending a part with no tree parent is a valid resting state.
## §5.3 records the method.
func remove_node(slot: int) -> PackedByteArray:
	assert(alive[slot] == 1, "slot %d is not live" % slot)
	var orphans := detach_orphaning_children(slot)
	detach(slot)
	return orphans


## Removes the support edge between [param a] and [param b], leaving both parts
## alive. This is what a strain failure does (§4.2): the joint yields, the parts
## do not.
##
## When the edge was also a tree link, the child is left parentless and is
## returned as [constant CORE] would never be — the caller must re-parent or
## sever it, exactly as after [method detach_orphaning_children]. Returns the
## slot left parentless, or [constant INVALID] when the edge carried no tree
## link.
func sever_edge(a: int, b: int) -> int:
	if edge_index(a, b) == -1:
		return INVALID
	_remove_edge_one_way(a, b)
	_remove_edge_one_way(b, a)
	_dwell.erase(_dwell_key(a, b))

	var child := INVALID
	if int(parent[a]) == b:
		child = a
	elif int(parent[b]) == a:
		child = b
	if child == INVALID:
		return INVALID

	var p := int(parent[child])
	_propagate_mass_delta(p, -subtree_mass[child])
	var kids: PackedByteArray = children[p]
	var at := kids.find(child)
	if at != -1:
		kids.remove_at(at)
		children[p] = kids
	parent[child] = INVALID
	_refresh_depths(child)
	return child


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


## ===== TRAVERSAL PRIMITIVES ============================================
## [DetachmentSolver] runs §5.3's search over this graph rather than inside it,
## because the search is an algorithm over the topology and not a property of it.
## These three expose exactly the stamp machinery of §2.2 that it needs, so it
## never reaches into [member _visit_stamp] directly.


## Starts a traversal and returns its stamp, per §2.2.
##
## Stamps only ever increase, so a stamp taken earlier is strictly less than one
## taken later and two live stamps can never be mistaken for one another. §5.3
## depends on exactly that when it compares a node against both a proven stamp
## and a local one.
func begin_traversal() -> int:
	return _begin_traversal()


func mark_visited(slot: int, stamp: int) -> void:
	_visit_stamp[slot] = stamp


func visit_stamp_of(slot: int) -> int:
	return _visit_stamp[slot]


## True when a mass delta has been propagated since the mass solver last looked.
## §3.3 sets it on every write to [member subtree_mass].
func is_mass_dirty() -> bool:
	return _mass_dirty


func clear_mass_dirty() -> void:
	_mass_dirty = false


## ===== STRAIN (§4) =====================================================


## Current dynamic amplification factor. Garage strain prediction reads it as
## [constant KAPPA_MIN]: §9 shows strain statically and never fails a joint.
func dynamic_factor() -> float:
	return _kappa


## Smooths [member _kappa] towards the amplification implied by
## [param chassis_accel_mps2], per §4.1.
##
## Called at 10 Hz from the motion system (doc 05 §9). This is a scalar filter,
## not a poll of connectivity: it costs one lerp per Assembly and touches no
## slot, no edge, and no traversal. Architectural Invariant I-4 is about
## structural evaluation, and nothing structural happens here.
func update_dynamic_factor(chassis_accel_mps2: float) -> void:
	var target := clampf(
		KAPPA_MIN + chassis_accel_mps2 / SyndicateConstants.GRAVITY_MPS2, KAPPA_MIN, KAPPA_MAX
	)
	_kappa = lerpf(_kappa, target, KAPPA_SMOOTHING)


## Records the sustained recoil force an Effector Module at [param slot] is
## putting through its mounting joint, per doc 07 §8.
##
## The peak is kept rather than the sum: two effectors on one slot is impossible,
## and a second discharge inside the decay window is the same load continuing,
## not a second load added to it.
func deposit_recoil_force(slot: int, newtons: float) -> void:
	if slot < 0 or slot >= MAX or alive[slot] == 0:
		return
	_recoil_deposit[slot] = maxf(_recoil_deposit[slot], newtons)
	_mark_deposit_active(slot)


## Records the force a recent collision deposited at [param slot], per doc 08 §6.2.
func deposit_impact_force(slot: int, newtons: float) -> void:
	if slot < 0 or slot >= MAX or alive[slot] == 0:
		return
	_impact_deposit[slot] = maxf(_impact_deposit[slot], newtons)
	_mark_deposit_active(slot)


## Decays both deposit terms of §4.1 towards zero over [param dt] seconds.
##
## [b]Addition to §4.1 as originally written.[/b] Doc 08 §6.2 decays the impact
## deposit and doc 07 §8 deposits recoil without ever clearing it, which would
## make a single discharge a load the joint carries for the rest of the match.
## Both are recent-load deposits and both decay here, differing only in time
## constant. §4.1 records it.
##
## Returns true while anything remains loaded, so the caller can stop calling.
func decay_deposits(dt: float) -> bool:
	if _deposit_active.is_empty():
		return false  # the overwhelmingly common path
	var recoil_factor := exp(-dt / RECOIL_DECAY_TAU_S)
	var impact_factor := exp(-dt / IMPACT_DECAY_TAU_S)
	var still_active := PackedByteArray()
	for s in _deposit_active:
		var slot := int(s)
		_recoil_deposit[slot] *= recoil_factor
		_impact_deposit[slot] *= impact_factor
		if _recoil_deposit[slot] < DEPOSIT_FLOOR_N:
			_recoil_deposit[slot] = 0.0
		if _impact_deposit[slot] < DEPOSIT_FLOOR_N:
			_impact_deposit[slot] = 0.0
		if _recoil_deposit[slot] > 0.0 or _impact_deposit[slot] > 0.0:
			still_active.append(slot)
	_deposit_active = still_active
	return not _deposit_active.is_empty()


## Recomputes every tree edge's strain from the quasi-static model of §4.1 and
## emits [signal EventBusService.joint_strain_changed] for the ones that moved.
##
## Called at recomputation events only — a mass recompute, a recoil discharge, an
## impact deposit — never on a timer. One pass is O(V): the deposit terms are
## subtree sums, so they are accumulated child-to-parent in one descending-depth
## sweep rather than by a walk per slot.
##
## Strain is carried on the edge to the [b]primary tree parent[/b], which is the
## joint §4.1's formula describes. Support edges to other neighbours exist and
## carry connectivity, but no load is attributed to them: §4.1 defines exactly
## one force per part and the tree is where §3.2 decided that force flows.
func recompute_strain(assembly_id: int) -> void:
	var live := _order_by_descending_depth()
	for i in live:
		var slot := int(_depth_order[i])
		_subtree_recoil[slot] = _recoil_deposit[slot]
		_subtree_impact[slot] = _impact_deposit[slot]
	for i in live:
		var slot := int(_depth_order[i])
		var p := int(parent[slot])
		if p == INVALID:
			continue
		_subtree_recoil[p] += _subtree_recoil[slot]
		_subtree_impact[p] += _subtree_impact[slot]

	var candidates := PackedByteArray()
	for i in live:
		var slot := int(_depth_order[i])
		var p := int(parent[slot])
		if p == INVALID:
			continue
		var e := edge_index(slot, p)
		if e == -1:
			# The tree link is always a mated pair, so this means the two
			# structures have diverged — loudly, because every load path through
			# this part is now unaccounted for.
			push_error(
				"ChassisGraph: slot %d has tree parent %d with no support edge" % [slot, p]
			)
			continue
		var rated := edge_strength[slot][e]
		if rated <= 0.0:
			continue
		var force := (
			subtree_mass[slot] * SyndicateConstants.GRAVITY_MPS2 * _kappa
			+ _subtree_recoil[slot]
			+ _subtree_impact[slot]
		)
		var strain := force / rated
		# The stored value is always current; only the announcement is gated.
		# Gating the write instead would let a joint sit at a stale strain
		# indefinitely, because each individual step stayed under the epsilon.
		var moved := absf(strain - edge_strain[slot][e]) >= STRAIN_REPORT_EPSILON
		set_edge_strain(slot, p, strain)
		if moved:
			EventBus.joint_strain_changed.emit(assembly_id, slot, p, strain)
		if strain >= STRAIN_CANDIDATE_THRESHOLD:
			candidates.append(slot)
		else:
			_dwell.erase(_dwell_key(slot, p))
	# Ascending, so that a cascade of failures is emitted in the same order on
	# the server and on every client replaying the same events.
	candidates.sort()
	_strained_candidates = candidates


## Accrues dwell on every candidate edge at or above the limit and emits
## [signal EventBusService.joint_failed] for the ones that have held there for
## [constant STRAIN_FAILURE_DWELL_S], per §4.2.
##
## Iterates the small dirty set [method recompute_strain] leaves behind, not all
## slots. An Assembly under no load has an empty set and this returns
## immediately.
##
## [b]Amendment to §4.2 as originally written.[/b] §4.2 keys dwell on the
## ordered pair [code]slot * MAX + other[/code], which gives one physical joint
## two independent timers — one per endpoint — so a joint whose two ends entered
## the candidate set on different passes fails later than its dwell says, and one
## whose ends both entered fails twice. The key here is canonical over the
## unordered pair. §4.2 records it.
func evaluate_strain(assembly_id: int, dt: float) -> void:
	if _strained_candidates.is_empty():
		return
	for s in _strained_candidates:
		var slot := int(s)
		if alive[slot] == 0:
			continue
		var p := int(parent[slot])
		if p == INVALID:
			continue
		var i := edge_index(slot, p)
		if i == -1:
			continue
		var key := _dwell_key(slot, p)
		if edge_strain[slot][i] < STRAIN_LIMIT:
			_dwell.erase(key)
			continue
		var held: float = float(_dwell.get(key, 0.0)) + dt
		_dwell[key] = held
		# The tolerance is not slack in the rule. Dwell is a sum of sixtieths of
		# a second, which cannot represent 0.45 exactly, so a bare >= gives the
		# joint one extra tick — and the exact tick a joint fails on is
		# replicated, so the server and a client accumulating in a different
		# order would disagree about it.
		if held >= STRAIN_FAILURE_DWELL_S - SyndicateConstants.EPSILON_LINEAR:
			_dwell.erase(key)
			EventBus.joint_failed.emit(assembly_id, slot, p)


## Seconds [param a]—[param b] has spent at or above the strain limit. Zero for
## an edge that is not being tracked.
func dwell_seconds(a: int, b: int) -> float:
	return float(_dwell.get(_dwell_key(a, b), 0.0))


## Slots owning a tree edge in the dwell-tracked candidate set, ascending. A copy:
## the caller must not be able to change what the next evaluation sweeps.
func strained_candidates() -> PackedByteArray:
	return _strained_candidates.duplicate()


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


func _add_edge(a: int, b: int, strength: float, bears_load: bool) -> void:
	assert(a != b, "a slot cannot mate with itself: %d" % a)
	assert(alive[b] == 1, "slot %d mated to dead slot %d" % [a, b])
	if neighbours[a].has(b):
		# Two nodes of the same part pair may mate against the same neighbour —
		# a wide part meeting a wide part shares several faces. That is one
		# physical joint, and duplicating the edge would double-count it in
		# every strain and connectivity sum.
		return

	var load_byte := 1 if bears_load else 0

	var na: PackedByteArray = neighbours[a]
	var sa: PackedFloat32Array = edge_strength[a]
	var ta: PackedFloat32Array = edge_strain[a]
	var la: PackedByteArray = edge_bears_load[a]
	na.push_back(b)
	sa.push_back(strength)
	ta.push_back(0.0)
	la.push_back(load_byte)
	neighbours[a] = na
	edge_strength[a] = sa
	edge_strain[a] = ta
	edge_bears_load[a] = la

	var nb: PackedByteArray = neighbours[b]
	var sb: PackedFloat32Array = edge_strength[b]
	var tb: PackedFloat32Array = edge_strain[b]
	var lb: PackedByteArray = edge_bears_load[b]
	nb.push_back(a)
	sb.push_back(strength)
	tb.push_back(0.0)
	lb.push_back(load_byte)
	neighbours[b] = nb
	edge_strength[b] = sb
	edge_strain[b] = tb
	edge_bears_load[b] = lb


func _remove_edge_one_way(owner_slot: int, other: int) -> void:
	var n: PackedByteArray = neighbours[owner_slot]
	var at := n.find(other)
	if at == -1:
		return
	var s: PackedFloat32Array = edge_strength[owner_slot]
	var t: PackedFloat32Array = edge_strain[owner_slot]
	var l: PackedByteArray = edge_bears_load[owner_slot]
	n.remove_at(at)
	s.remove_at(at)
	t.remove_at(at)
	l.remove_at(at)
	neighbours[owner_slot] = n
	edge_strength[owner_slot] = s
	edge_strain[owner_slot] = t
	edge_bears_load[owner_slot] = l


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
	_mass_dirty = true


## True when the edge at [param index] of [param slot] bears load at both ends.
func edge_bears_load_at(slot: int, index: int) -> bool:
	if slot < 0 or slot >= MAX:
		return false
	var l: PackedByteArray = edge_bears_load[slot]
	if index < 0 or index >= l.size():
		return false
	return l[index] == 1


## Fills [member _depth_order] with the live slots ordered deepest first and
## returns how many there are, so that a single sweep accumulates every child
## into its parent before the parent is itself read.
##
## A counting sort over depth, into preallocated scratch: the strain pass runs on
## every structural event and every mass recompute, and a comparison sort there
## would allocate on each one. Slots are placed in ascending order within a
## depth, so the result is a total order (Architectural Invariant I-9).
func _order_by_descending_depth() -> int:
	var deepest := 0
	var live := 0
	for s in MAX:
		if alive[s] == 0:
			continue
		live += 1
		deepest = maxi(deepest, int(depth[s]))
	if live == 0:
		return 0

	for d in deepest + 1:
		_depth_counts[d] = 0
	for s in MAX:
		if alive[s] == 1:
			_depth_counts[int(depth[s])] += 1

	# Turn the counts into the starting offset of each depth in the output,
	# walking from the deepest so that the deepest lands first.
	var running := 0
	for d: int in range(deepest, -1, -1):
		var n := _depth_counts[d]
		_depth_counts[d] = running
		running += n

	for s in MAX:
		if alive[s] == 0:
			continue
		var d := int(depth[s])
		_depth_order[_depth_counts[d]] = s
		_depth_counts[d] += 1
	return live


## Canonical key for the unordered pair, so one physical joint has one dwell
## timer regardless of which endpoint the candidate sweep reached it from.
static func _dwell_key(a: int, b: int) -> int:
	return mini(a, b) * MAX + maxi(a, b)


func _mark_deposit_active(slot: int) -> void:
	if not _deposit_active.has(slot):
		_deposit_active.append(slot)


func _forget_deposits(slot: int) -> void:
	var at := _deposit_active.find(slot)
	if at != -1:
		_deposit_active.remove_at(at)


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
