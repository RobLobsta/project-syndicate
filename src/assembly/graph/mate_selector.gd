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
	if a.bears_load != b.bears_load:
		return a.bears_load

	if not is_equal_approx(a.joint_strength_n, b.joint_strength_n):
		return a.joint_strength_n > b.joint_strength_n

	var da := int(graph.depth[a.other_slot])
	var db := int(graph.depth[b.other_slot])
	if da != db:
		return da < db

	return a.other_slot < b.other_slot
