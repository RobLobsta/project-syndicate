extends TestCase
## [ChassisGraph] — the primary tree, the support edge graph, and the subtree
## mass that §7.8 of doc 02 rejects placements against.
##
## The aggregates here are all maintained incrementally, which means none of
## them fails loudly. A dropped mass delta leaves a load capacity permanently
## consumed by a part that is no longer there; a half-removed edge leaves a
## severed fragment reporting itself as connected to the Core Module. Both
## surface much later as behaviour nobody can trace back to a graph edit, so
## every test below re-asserts the whole invariant after the operation rather
## than just the value the operation touched.

const CORE := SyndicateConstants.CORE_SLOT
const INVALID := SyndicateConstants.INVALID_SLOT

## Distinct so that a mass assertion names which part went missing.
const CORE_MASS := 380.0
const M_A := 34.0
const M_B := 50.0
const M_C := 12.0


func test_starts_empty() -> void:
	var g := ChassisGraph.new()
	check_eq(g.live_slots(), PackedByteArray(), "no slots live")
	check_false(g.is_alive(CORE), "the core slot is not live before attach")
	check_approx(g.subtree_mass[CORE], 0.0, "core subtree mass starts at zero")
	check_false(g.is_connected_to_core(3), "an unattached slot reaches nothing")


func test_root_attach() -> void:
	var g := _graph_with_core()
	check_true(g.is_alive(CORE), "the core is live")
	check_eq(int(g.parent[CORE]), INVALID, "the core is rootless (I-2)")
	check_eq(int(g.depth[CORE]), 0, "the core is depth 0")
	check_approx(g.subtree_mass[CORE], CORE_MASS, "core subtree mass is its own mass")
	check_true(g.is_connected_to_core(CORE), "the core reaches itself")


func test_child_attach_builds_tree_and_edge() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)

	check_eq(int(g.parent[1]), CORE, "slot 1's parent is the core")
	check_eq(int(g.depth[1]), 1, "slot 1 is depth 1")
	check_eq(g.children[CORE], PackedByteArray([1]), "the core lists slot 1")
	check_approx(g.subtree_mass[1], M_A, "the leaf carries only itself")
	check_approx(g.subtree_mass[CORE], CORE_MASS + M_A, "the core carries both")
	check_eq(g.live_slots(), PackedByteArray([0, 1]), "both slots live, ascending")


func test_support_edges_are_stored_at_both_endpoints() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)

	check_true(g.neighbours[CORE].has(1), "the core knows slot 1")
	check_true(g.neighbours[1].has(CORE), "slot 1 knows the core")
	check_approx(
		g.edge_strength_between(CORE, 1), g.edge_strength_between(1, CORE),
		"both copies of the edge rate it identically"
	)


func test_edge_strain_writes_reach_both_copies() -> void:
	# One-sided strain writes are the failure this guards: the strain a part
	# reports would then depend on which end of the joint was asked.
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)

	g.set_edge_strain(CORE, 1, 0.42)
	check_approx(g.edge_strain_between(CORE, 1), 0.42, "strain readable from the core")
	check_approx(g.edge_strain_between(1, CORE), 0.42, "strain readable from slot 1")


func test_mass_propagates_the_whole_way_to_the_root() -> void:
	# A three-deep chain: the deepest attach must reach the core, not stop at
	# the immediate parent.
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	_attach(g, 2, 1, M_B)
	_attach(g, 3, 2, M_C)

	check_approx(g.subtree_mass[3], M_C, "the leaf carries itself")
	check_approx(g.subtree_mass[2], M_B + M_C, "slot 2 carries slot 3")
	check_approx(g.subtree_mass[1], M_A + M_B + M_C, "slot 1 carries the branch")
	check_approx(
		g.subtree_mass[CORE], CORE_MASS + M_A + M_B + M_C, "the core carries everything"
	)
	check_eq(int(g.depth[3]), 3, "depth accumulates down the chain")


func test_detach_restores_every_aggregate() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	_attach(g, 2, 1, M_B)
	g.detach(2)

	check_false(g.is_alive(2), "slot 2 is no longer live")
	check_approx(g.subtree_mass[2], 0.0, "the detached slot carries nothing")
	check_approx(g.subtree_mass[1], M_A, "slot 1 is back to its own mass")
	check_approx(g.subtree_mass[CORE], CORE_MASS + M_A, "the core lost slot 2's mass")
	check_eq(g.children[1], PackedByteArray(), "slot 1 has no children")
	check_false(g.neighbours[1].has(2), "slot 1's edge to slot 2 is gone")
	check_eq(g.neighbours[2], PackedByteArray(), "slot 2 keeps no edges")


func test_attach_detach_cycles_do_not_drift() -> void:
	# The incremental totals are what rot over an editing session, and they rot
	# silently. Twenty-five cycles would make a one-part-per-cycle leak obvious.
	var g := _graph_with_core()
	for i in 25:
		_attach(g, 1, CORE, M_A)
		check_approx(g.subtree_mass[CORE], CORE_MASS + M_A, "core mass after attach %d" % i)
		g.detach(1)
		check_approx(g.subtree_mass[CORE], CORE_MASS, "core mass after detach %d" % i)
	check_eq(g.live_slots(), PackedByteArray([0]), "only the core survives the cycles")


func test_detach_orphaning_children_moves_the_whole_subtree_off() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	_attach(g, 2, 1, M_B)
	_attach(g, 3, 2, M_C)

	var orphans := g.detach_orphaning_children(1)
	check_eq(orphans, PackedByteArray([2]), "slot 1's only direct child is returned")
	check_eq(int(g.parent[2]), INVALID, "the orphan is parentless")
	check_true(g.is_alive(2), "the orphan is still live")
	check_true(g.is_alive(3), "the orphan's own subtree is untouched")
	check_approx(g.subtree_mass[2], M_B + M_C, "the orphan keeps its subtree mass")
	check_approx(g.subtree_mass[1], M_A, "slot 1 shed the whole branch, not just slot 2")
	check_approx(g.subtree_mass[CORE], CORE_MASS + M_A, "the core shed it too")


func test_reparent_moves_mass_between_branches() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	_attach(g, 2, CORE, M_B)
	_attach(g, 3, 1, M_C)

	g.reparent(3, 2)

	check_eq(int(g.parent[3]), 2, "slot 3 now hangs off slot 2")
	check_eq(int(g.depth[3]), 2, "its depth is recomputed")
	check_approx(g.subtree_mass[1], M_A, "the old branch gave the mass up")
	check_approx(g.subtree_mass[2], M_B + M_C, "the new branch took it on")
	check_approx(
		g.subtree_mass[CORE], CORE_MASS + M_A + M_B + M_C,
		"the total is unchanged — mass moved, it did not appear or vanish"
	)
	check_eq(g.children[1], PackedByteArray(), "slot 1 dropped the child")
	check_eq(g.children[2], PackedByteArray([3]), "slot 2 gained it")


func test_reparent_refreshes_depth_of_a_whole_subtree() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	_attach(g, 2, 1, M_A)
	_attach(g, 3, 2, M_A)
	_attach(g, 4, CORE, M_A)
	check_eq(int(g.depth[3]), 3, "slot 3 starts three deep")

	g.reparent(2, 4)

	check_eq(int(g.depth[2]), 2, "the moved slot's depth is right")
	check_eq(int(g.depth[3]), 3, "and its child's depth followed it")


func test_connectivity_runs_over_support_edges_not_the_tree() -> void:
	# §11 invariant 3, and the reason it exists: slot 2's tree parent is slot 1,
	# but it also touches the core directly. Losing slot 1 must not make it
	# unreachable, because physically it is still resting on the core.
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	var mates: Array[MateRecord] = [_mate(1, 60000.0, true), _mate(CORE, 60000.0, true)]
	g.attach(2, 1, mates, M_B)

	check_true(g.is_connected_to_core(2), "slot 2 reaches the core")
	g.detach_orphaning_children(1)
	g.detach(1)
	check_true(
		g.is_connected_to_core(2),
		"slot 2 still reaches the core through its own support edge"
	)


func test_severed_slot_reports_disconnected() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	_attach(g, 2, 1, M_B)
	check_true(g.is_connected_to_core(2), "slot 2 reaches the core through slot 1")

	g.detach_orphaning_children(1)
	g.detach(1)
	check_false(g.is_connected_to_core(2), "with slot 1 gone there is no path left")


func test_nothing_reaches_a_dead_core() -> void:
	# Architectural Invariant I-2: losing the Core Module terminates the
	# Assembly. Everything must report severed, not merely the parts that
	# touched it.
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	_attach(g, 2, 1, M_B)
	g.detach_orphaning_children(CORE)
	g.detach(CORE)

	check_false(g.is_connected_to_core(1), "slot 1 is severed")
	check_false(g.is_connected_to_core(2), "so is everything behind it")


func test_duplicate_edges_are_not_double_counted() -> void:
	# A wide part meeting a wide part shares several faces. That is one physical
	# joint; two edges would double it in every strain and connectivity sum.
	var g := _graph_with_core()
	var mates: Array[MateRecord] = [
		_mate(CORE, 60000.0, true),
		_mate(CORE, 45000.0, true),
		_mate(CORE, 51000.0, true),
	]
	g.attach(1, CORE, mates, M_A)

	check_eq(g.neighbours[1], PackedByteArray([0]), "one edge to the core, not three")
	check_eq(g.neighbours[CORE], PackedByteArray([1]), "and one back")


func test_visit_stamp_survives_many_traversals() -> void:
	# The stamp is never cleared between traversals, so a stale stamp would make
	# a later traversal skip slots it should visit. Exercised by running far
	# more traversals than any single edit performs.
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	_attach(g, 2, 1, M_B)
	var connected := 0
	for _i in 200:
		if g.is_connected_to_core(2):
			connected += 1
	check_eq(connected, 200, "every one of 200 traversals finds the same answer")


func test_subtree_slots_is_breadth_first_and_ascending() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	_attach(g, 2, CORE, M_A)
	_attach(g, 3, 1, M_A)
	_attach(g, 4, 1, M_A)

	check_eq(
		g.subtree_slots(CORE), PackedByteArray([0, 1, 2, 3, 4]),
		"breadth-first from the core, ascending within each level"
	)
	check_eq(g.subtree_slots(1), PackedByteArray([1, 3, 4]), "and from an interior slot")
	check_eq(g.subtree_slots(2), PackedByteArray([2]), "a leaf is its own subtree")


func test_debug_report_is_reproducible() -> void:
	# §10's dump is consumed by tests and by the developer overlay. Two runs
	# over the same graph must diff clean, so it carries no timestamp and no
	# hash-ordered iteration.
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A)
	_attach(g, 2, 1, M_B)
	check_eq(g.debug_report(), g.debug_report(), "two dumps of one graph are identical")
	check_true(g.debug_report().begins_with("slot parent depth"), "the header is present")


## ===== HELPERS =========================================================


func _graph_with_core() -> ChassisGraph:
	var g := ChassisGraph.new()
	g.attach(CORE, INVALID, [] as Array[MateRecord], CORE_MASS)
	return g


func _attach(g: ChassisGraph, slot: int, to: int, mass: float) -> void:
	var mates: Array[MateRecord] = [_mate(to, 60000.0, true)]
	g.attach(slot, to, mates, mass)


func _mate(other: int, strength: float, bears: bool) -> MateRecord:
	var m := MateRecord.new()
	m.other_slot = other
	m.joint_strength_n = strength
	m.bears_load = bears
	return m
