extends TestCase
## [DetachmentSolver] — the local reverse-reachability of doc 04 §5.3 and the
## full partition of §7.2.
##
## Every test builds a graph whose answer is obvious by inspection and then
## asserts the whole surviving structure, not just the island list. The two
## halves fail independently: a search that severs too much and a search that
## severs too little both produce an island list, and only the survivors say
## which happened. A solver that returned the right islands while leaving a
## survivor parentless would corrupt every mass figure above it and pass a test
## that only read the return value.
##
## Fixtures are drawn as comments because the topology is the whole test. Read
## them as: an edge below a slot is a support edge, and the parenthesised slot is
## the tree parent.

const CORE := SyndicateConstants.CORE_SLOT
const INVALID := SyndicateConstants.INVALID_SLOT

const CORE_MASS := 380.0
const PART_MASS := 34.0
const STRONG := 60000.0
const WEAK := 500.0


## ===== THE COMMON CASES ================================================


func test_removing_a_leaf_severs_nothing() -> void:
	#  CORE — 1 — 2
	var g := _chain(2)
	var islands := DetachmentSolver.solve_one(g, 2)

	check_eq(islands.size(), 0, "a leaf takes nothing with it")
	check_eq(g.live_slots(), PackedByteArray([CORE, 1]), "the rest of the chain survives")
	check_approx(g.subtree_mass[CORE], CORE_MASS + PART_MASS, "and the core sheds its mass")


func test_removing_a_link_severs_everything_above_it() -> void:
	#  CORE — 1 — 2 — 3        remove 1
	var g := _chain(3)
	var islands := DetachmentSolver.solve_one(g, 1)

	check_eq(islands.size(), 1, "one island")
	check_eq(islands[0], PackedByteArray([2, 3]), "holding the two parts above the cut")
	check_eq(g.live_slots(), PackedByteArray([CORE]), "only the core remains")
	check_approx(g.subtree_mass[CORE], CORE_MASS, "carrying only itself")


func test_a_part_bridged_to_the_core_is_not_severed() -> void:
	# The reason connectivity runs over support edges and not the tree (§11
	# invariant 3). Slot 2's tree parent is 1, but it also touches the core.
	#
	#  CORE — 1 — 2
	#    └────────┘             remove 1
	var g := _graph_with_core()
	_attach(g, 1, CORE, [CORE])
	_attach(g, 2, 1, [1, CORE])

	var islands := DetachmentSolver.solve_one(g, 1)
	check_eq(islands.size(), 0, "the bridged part holds on")
	check_eq(g.live_slots(), PackedByteArray([CORE, 2]), "and stays on the Assembly")


func test_a_survivor_that_loses_its_tree_parent_is_reparented() -> void:
	# The same fixture as above, read from the tree's side. Slot 2 survives, so
	# it must end up with a real parent — a live part with no parent keeps its
	# mass out of every ancestor's subtree_mass, permanently and silently.
	var g := _graph_with_core()
	_attach(g, 1, CORE, [CORE])
	_attach(g, 2, 1, [1, CORE])
	DetachmentSolver.solve_one(g, 1)

	check_eq(int(g.parent[2]), CORE, "slot 2 is re-parented onto the core")
	check_eq(int(g.depth[2]), 1, "with its depth refreshed")
	check_eq(g.children[CORE], PackedByteArray([2]), "and the core lists it as a child")
	check_approx(g.subtree_mass[CORE], CORE_MASS + PART_MASS, "so its mass is accounted for")


func test_reparenting_picks_the_strongest_load_bearing_joint() -> void:
	# §3.2's ordering, applied to survivors. Slot 3's tree parent is destroyed
	# and it must choose between the two joints it has left. Slots 2 and 4 are
	# at the same depth and neither is the lower index of the pair the strength
	# key picks, so keys 3 and 4 cannot produce this answer by accident.
	var g := _fork(STRONG, true, WEAK, true)
	DetachmentSolver.solve_one(g, 1)

	check_true(g.is_alive(3), "the survivor holds on through its other joints")
	check_eq(int(g.parent[3]), 2, "and re-parents onto the stronger joint")
	check_approx(g.subtree_mass[2], PART_MASS * 2.0, "carrying its mass onto that branch")


func test_reparenting_prefers_a_load_bearing_joint_over_a_stronger_one() -> void:
	# Key 1 outranks key 2. A non-load-bearing node is not a support even when
	# it is rated higher, and ordering the keys the other way round would hang
	# an Assembly off a joint that declines to carry it. Same fixture, with the
	# strong joint refusing load, so the answer must flip.
	var g := _fork(STRONG, false, WEAK, true)
	DetachmentSolver.solve_one(g, 1)
	check_eq(int(g.parent[3]), 4, "the load-bearing joint wins despite being weaker")


## ===== BATCHING AND CASCADES ===========================================


func test_two_removals_in_one_pass_produce_one_island() -> void:
	# §5.5's reason for existing. Resolving the two deaths separately would give
	# two island sets, one a subset of the other, and two debris spawns where
	# one is correct.
	#
	#  CORE — 1 — 2 — 3 — 4     remove 1 and 2
	var g := _chain(4)
	var islands := DetachmentSolver.solve(g, PackedByteArray([1, 2]))

	check_eq(islands.size(), 1, "one island, not two")
	check_eq(islands[0], PackedByteArray([3, 4]), "holding everything above the higher cut")


func test_two_branches_severed_at_once_are_two_islands() -> void:
	#        1 — 2                 4 — 5
	#  CORE ─┘                └──── ┘
	#  CORE — 1 — 2   and   CORE — 4 — 5      remove 1 and 4
	var g := _graph_with_core()
	_attach(g, 1, CORE, [CORE])
	_attach(g, 2, 1, [1])
	_attach(g, 3, CORE, [CORE])
	_attach(g, 4, 3, [3])

	var islands := DetachmentSolver.solve(g, PackedByteArray([1, 3]))
	check_eq(islands.size(), 2, "two independent islands")
	check_eq(islands[0], PackedByteArray([2]), "the lower-numbered island first")
	check_eq(islands[1], PackedByteArray([4]), "then the other")


func test_islands_and_their_slots_are_ordered_deterministically() -> void:
	# Not cosmetic. The network layer replays the same event set on every client
	# and relies on getting the same decomposition in the same order (§5.5).
	var a := _wide_graph()
	var b := _wide_graph()
	var from_a := DetachmentSolver.solve(a, PackedByteArray([1, 2]))
	var from_b := DetachmentSolver.solve(b, PackedByteArray([2, 1]))

	check_eq(from_a.size(), from_b.size(), "the same island count either way round")
	for i in from_a.size():
		check_eq(from_a[i], from_b[i], "island %d is identical" % i)


func test_removing_an_already_dead_slot_is_a_no_op() -> void:
	# The scheduler dedupes, but a joint failure and a destruction can name the
	# same part in one tick through different routes.
	var g := _chain(2)
	var islands := DetachmentSolver.solve(g, PackedByteArray([2, 2]))
	check_eq(islands.size(), 0, "no island from the duplicate")
	check_eq(g.live_slots(), PackedByteArray([CORE, 1]), "and nothing extra removed")


## ===== CORE MODULE LOSS (§7.2) =========================================


func test_partition_finds_every_component() -> void:
	#  CORE — 1 — 2      3 — 4      (3 and 4 already floating)
	var g := _graph_with_core()
	_attach(g, 1, CORE, [CORE])
	_attach(g, 2, 1, [1])
	# A second, disconnected pair. Attached through the tree to keep the graph
	# well-formed, then cut loose at the support edge.
	_attach(g, 3, CORE, [CORE])
	_attach(g, 4, 3, [3])
	g.sever_edge(3, CORE)

	var parts := DetachmentSolver.partition_live_components(g)
	check_eq(parts.size(), 2, "two components")
	check_eq(parts[0], PackedByteArray([CORE, 1, 2]), "the core's component, ascending")
	check_eq(parts[1], PackedByteArray([3, 4]), "and the floating pair")


func test_partition_merges_the_remainder_into_the_largest() -> void:
	# §7.2 caps the bodies at 8. Ten independent parts must come back as eight
	# components with the surplus absorbed, and no slot may go missing.
	var g := _graph_with_core()
	for i in range(1, 11):
		_attach(g, i, CORE, [CORE])
		g.sever_edge(i, CORE)

	var parts := DetachmentSolver.partition_live_components(g)
	check_eq(parts.size(), DetachmentSolver.MAX_TERMINAL_COMPONENTS, "capped at eight bodies")

	var seen := PackedByteArray()
	for component in parts:
		seen.append_array(component)
	seen.sort()
	check_eq(seen.size(), 11, "every one of the eleven live slots is in exactly one component")


func test_partition_ignores_dead_slots() -> void:
	var g := _chain(3)
	g.remove_node(3)
	var parts := DetachmentSolver.partition_live_components(g)
	check_eq(parts.size(), 1, "one component")
	check_eq(parts[0], PackedByteArray([CORE, 1, 2]), "holding only the live slots")


## ===== CONSERVATION ====================================================


func test_repeated_solves_do_not_drift() -> void:
	# Every structure the solver touches is maintained incrementally and none of
	# them fails loudly. Cycling back to the same graph and asserting the totals
	# return to baseline is what makes a one-slot-per-cycle leak visible.
	var baseline := ""
	for cycle in 12:
		var g := _chain(4)
		DetachmentSolver.solve(g, PackedByteArray([2]))
		if cycle == 0:
			baseline = g.debug_report()
		else:
			check_eq(g.debug_report(), baseline, "cycle %d matches the first" % cycle)
	check_ne(baseline, "", "the baseline was captured")


func test_severed_mass_leaves_the_surviving_tree() -> void:
	var g := _chain(4)
	DetachmentSolver.solve_one(g, 2)
	check_approx(
		g.subtree_mass[CORE], CORE_MASS + PART_MASS, "only the core and slot 1 remain accounted"
	)
	check_approx(g.subtree_mass[1], PART_MASS, "and slot 1 carries only itself")


func test_every_survivor_has_a_parent() -> void:
	var g := _wide_graph()
	DetachmentSolver.solve(g, PackedByteArray([1]))
	for s in g.live_slots():
		var slot := int(s)
		if slot == CORE:
			check_eq(int(g.parent[slot]), INVALID, "the core stays rootless (I-2)")
		else:
			check_ne(int(g.parent[slot]), INVALID, "slot %d has a tree parent" % slot)
			check_true(g.is_alive(int(g.parent[slot])), "slot %d's parent is live" % slot)


## ===== HELPERS =========================================================


func _graph_with_core() -> ChassisGraph:
	var g := ChassisGraph.new()
	g.attach(CORE, INVALID, [] as Array[MateRecord], CORE_MASS)
	return g


## A straight chain of [param length] parts hanging off the Core Module.
func _chain(length: int) -> ChassisGraph:
	var g := _graph_with_core()
	for i in range(1, length + 1):
		_attach(g, i, i - 1, [i - 1])
	return g


## CORE with slots 1 and 2 side by side, both carrying 3, which also touches 4.
##
##   CORE — 1 — 3 — 4
##     └─── 2 ──┘
func _wide_graph() -> ChassisGraph:
	var g := _graph_with_core()
	_attach(g, 1, CORE, [CORE])
	_attach(g, 2, CORE, [CORE])
	_attach(g, 3, 1, [1, 2])
	_attach(g, 4, 3, [3])
	return g


## Slot 3 hangs off slot 1 and also touches slots 2 and 4, so that destroying 1
## forces the §3.2 ordering to choose between the two survivors.
##
##   CORE — 1 — 3
##     ├─── 2 ──┤
##     └─── 4 ──┘
func _fork(
	strength_two: float, bears_two: bool, strength_four: float, bears_four: bool
) -> ChassisGraph:
	var g := _graph_with_core()
	_attach(g, 1, CORE, [CORE])
	_attach(g, 2, CORE, [CORE])
	_attach_weighted(
		g,
		3,
		1,
		[[1, STRONG, true], [2, strength_two, bears_two]],
	)
	# Attached last so that slot 4 exists to be mated against slot 3 from its
	# own side; the edge is the same object either way round.
	_attach_weighted(g, 4, CORE, [[CORE, STRONG, true], [3, strength_four, bears_four]])
	return g


func _attach(g: ChassisGraph, slot: int, tree_parent: int, mated: Array) -> void:
	var weighted: Array = []
	for other: int in mated:
		weighted.append([other, STRONG, true])
	_attach_weighted(g, slot, tree_parent, weighted)


## [param mated] is an array of [code][other_slot, strength, bears_load][/code].
func _attach_weighted(g: ChassisGraph, slot: int, tree_parent: int, mated: Array) -> void:
	var mates: Array[MateRecord] = []
	for entry: Array in mated:
		var m := MateRecord.new()
		m.other_slot = entry[0]
		m.joint_strength_n = entry[1]
		m.bears_load = entry[2]
		mates.append(m)
	g.attach(slot, tree_parent, mates, PART_MASS)
