class_name MateSelector
extends RefCounted
## Chooses which of a placement's accepted mates becomes its primary tree
## parent, per [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §3.2.
##
## A part placed against several existing parts has several legal parents, and
## the choice decides every load path through it. Making that choice depend on
## the order the mates happened to be discovered in would make the tree — and
## therefore [member ChassisGraph.subtree_mass], strain, and which island a
## detachment produces — depend on lattice scan order. Client and server would
## then disagree about structure while agreeing about every part.
##
## Architectural Invariant I-9: the ordering below is a total order, so a
## shuffled input yields an identical result. [code]tests/unit/test_mate_selector.gd[/code]
## asserts exactly that.


## Index into [param mates] of the record that should become the primary parent,
## or -1 when [param mates] is empty.
##
## The keys, in order:
## [br]1. A mate that bears load on [b]both[/b] sides.
## [br]2. Among those, the highest [member MateRecord.joint_strength_n].
## [br]3. Among ties, the lowest tree depth — closest to the Core Module, which
## keeps the tree shallow and the mass propagation of §3.3 short.
## [br]4. Among remaining ties, the lowest slot index.
##
## Key 4 alone would be deterministic, so keys 1–3 are not there for
## reproducibility; they are there because the shallowest strongest load-bearing
## joint is the one that physically carries the part.
static func choose_primary(mates: Array[MateRecord], graph: ChassisGraph) -> int:
	if mates.is_empty():
		return -1
	var best := 0
	for i in range(1, mates.size()):
		if outranks(mates[i], mates[best], graph):
			best = i
	return best


## Slot of the chosen primary parent, or [constant SyndicateConstants.INVALID_SLOT]
## when there are no mates — which is legal only for the Core Module.
static func choose_primary_slot(mates: Array[MateRecord], graph: ChassisGraph) -> int:
	var i := choose_primary(mates, graph)
	return SyndicateConstants.INVALID_SLOT if i == -1 else mates[i].other_slot


## True when [param a] should be preferred over [param b] under the §3.2
## ordering.
##
## Public because the garage's re-parenting search (§9.2 of doc 02) ranks
## surviving neighbours by the same four keys. §9.2 states that ordering
## independently; sharing this function is what keeps the two from drifting
## apart, which would let a part land under one parent when placed and a
## different one when its neighbour is removed.
##
## Strict at every key: equal values fall through to the next, and the final key
## can never tie because two mates cannot share a slot.
static func outranks(a: MateRecord, b: MateRecord, graph: ChassisGraph) -> bool:
	return _outranks_keys(
		a.bears_load,
		a.joint_strength_n,
		int(graph.depth[a.other_slot]),
		a.other_slot,
		b.bears_load,
		b.joint_strength_n,
		int(graph.depth[b.other_slot]),
		b.other_slot
	)


## Slot of the best support-edge neighbour of [param slot] that still reaches the
## Core Module, or [constant SyndicateConstants.INVALID_SLOT] when none does.
##
## This is the match-mode counterpart of the garage's alternate-parent search
## (§9.2 of doc 02). The garage re-derives its candidates from the lattice
## because it must also honour polarity and class acceptance for a part being
## moved; after a destruction the mating is already settled and the surviving
## edges are exactly the legal parents, so ranking reads straight off the graph.
##
## Both paths rank on the same four keys through [method _outranks_keys], which
## is the whole reason [member ChassisGraph.edge_bears_load] is stored: a part
## must not land under one parent when placed and a different one when the part
## holding it up is shot away.
static func choose_support_parent(graph: ChassisGraph, slot: int) -> int:
	var best := SyndicateConstants.INVALID_SLOT
	var best_strength := 0.0
	var best_bears := false
	var best_depth := 0

	# Hoisted: it is the same answer for every neighbour, and it shares the
	# graph's traversal scratch with the reachability query below.
	var own_subtree := graph.subtree_slots(slot)

	var ns: PackedByteArray = graph.neighbours[slot]
	for i in ns.size():
		var other := int(ns[i])
		if graph.alive[other] == 0:
			continue
		# A part cannot be held up by something it already holds up, and a
		# candidate that is itself severed would let the graph claim a
		# connection the Assembly does not have.
		if own_subtree.has(other):
			continue
		if not graph.is_connected_to_core(other):
			continue

		var bears := graph.edge_bears_load_at(slot, i)
		var strength := graph.edge_strength[slot][i]
		var d := int(graph.depth[other])
		if (
			best == SyndicateConstants.INVALID_SLOT
			or _outranks_keys(
				bears, strength, d, other, best_bears, best_strength, best_depth, best
			)
		):
			best = other
			best_bears = bears
			best_strength = strength
			best_depth = d
	return best


## The §3.2 ordering itself, over the four keys rather than over a carrier type.
##
## Strict at every key: equal values fall through to the next, and the final key
## can never tie because two candidates cannot share a slot. Both entry points
## above delegate here so there is exactly one expression of the ordering — two
## copies would agree until someone changed one of them.
static func _outranks_keys(
	a_bears: bool,
	a_strength: float,
	a_depth: int,
	a_slot: int,
	b_bears: bool,
	b_strength: float,
	b_depth: int,
	b_slot: int
) -> bool:
	if a_bears != b_bears:
		return a_bears
	if not is_equal_approx(a_strength, b_strength):
		return a_strength > b_strength
	if a_depth != b_depth:
		return a_depth < b_depth
	return a_slot < b_slot
