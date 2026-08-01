extends TestCase
## [MateSelector] — primary parent choice, doc 04 §3.2.
##
## The point of this class is that the answer must not depend on the order the
## mates were discovered in. Lattice scan order is an implementation detail of
## whichever code found the pairs; if it leaked into the tree, the client and
## the server would agree about every part and disagree about which one holds
## which up, and the first thing anyone would notice is two machines producing
## different debris from the same shot.
##
## Every ordering test below therefore runs its input in several permutations
## and asserts one answer.

const CORE := SyndicateConstants.CORE_SLOT
const INVALID := SyndicateConstants.INVALID_SLOT

const STRONG := 90000.0
const WEAK := 20000.0


func test_no_mates_yields_no_parent() -> void:
	var g := _chain_graph()
	var none: Array[MateRecord] = []
	check_eq(MateSelector.choose_primary(none, g), -1, "no mates, no index")
	check_eq(
		MateSelector.choose_primary_slot(none, g), INVALID,
		"and no slot — legal only for the Core Module"
	)


func test_single_mate_is_chosen() -> void:
	var g := _chain_graph()
	var mates: Array[MateRecord] = [_mate(2, WEAK, false)]
	check_eq(MateSelector.choose_primary_slot(mates, g), 2, "the only mate wins by default")


func test_key_1_load_bearing_beats_everything_else() -> void:
	# A non-bearing mate must lose even when it is stronger and shallower.
	# can_bear_load is a declaration that a node may serve as a structural
	# parent; strength is irrelevant if the answer is no.
	var g := _chain_graph()
	var bearing := _mate(3, WEAK, true)
	var not_bearing := _mate(1, STRONG, false)
	check_true(
		MateSelector.outranks(bearing, not_bearing, g),
		"a weak deep load-bearing mate beats a strong shallow one that is not"
	)
	_check_order_invariant([bearing, not_bearing], g, 3, "load-bearing wins")


func test_key_2_higher_joint_strength_wins() -> void:
	var g := _chain_graph()
	var strong := _mate(3, STRONG, true)
	var weak := _mate(1, WEAK, true)
	_check_order_invariant([strong, weak], g, 3, "the stronger joint wins")


func test_key_3_lower_depth_breaks_a_strength_tie() -> void:
	# Shallower keeps the tree short, which keeps the mass propagation of §3.3
	# short — it walks to the root on every edit.
	#
	# The shallow mate deliberately has the *higher* slot index. With both on
	# the same side, key 4 alone would produce the same answer and the test
	# would pass with key 3 deleted.
	var g := _branch_graph()
	var shallow := _mate(4, STRONG, true)  # depth 1, higher slot
	var deep := _mate(3, STRONG, true)  # depth 3, lower slot
	check_eq(int(g.depth[4]), 1, "fixture: slot 4 is shallow")
	check_eq(int(g.depth[3]), 3, "fixture: slot 3 is deep")
	check_true(
		MateSelector.outranks(shallow, deep, g),
		"depth decides before the slot index does"
	)
	_check_order_invariant([deep, shallow], g, 4, "the shallower mate wins")


func test_key_4_lowest_slot_breaks_a_full_tie() -> void:
	var g := _sibling_graph()
	check_eq(int(g.depth[1]), 1, "fixture: siblings share a depth")
	check_eq(int(g.depth[2]), 1, "fixture: siblings share a depth")
	var a := _mate(1, STRONG, true)
	var b := _mate(2, STRONG, true)
	_check_order_invariant([b, a], g, 1, "the lowest slot index wins")


func test_shuffled_input_is_order_independent() -> void:
	# The property the whole class exists for, over a set where every key is
	# exercised at once.
	var g := _chain_graph()
	var mates: Array[MateRecord] = [
		_mate(1, WEAK, false),  # shallow and strongest-placed, but not bearing
		_mate(2, STRONG, true),  # the correct answer
		_mate(3, STRONG, true),  # same strength, deeper
		_mate(4, WEAK, true),  # bearing but weak
	]
	check_eq(int(g.depth[2]), 2, "fixture: slot 2 is shallower than slot 3")

	var seen := {}
	for perm: Array[MateRecord] in _permutations(mates):
		seen[MateSelector.choose_primary_slot(perm, g)] = true
	check_eq(seen.size(), 1, "every permutation of the same mates agrees")
	check_true(seen.has(2), "and they agree on slot 2")


func test_ordering_is_a_strict_total_order() -> void:
	# Two mates may never each outrank the other: a non-strict comparator makes
	# the winner depend on scan order again, which is exactly the bug this
	# class prevents. Checked over every pair in a set with deliberate ties.
	var g := _chain_graph()
	var mates: Array[MateRecord] = [
		_mate(1, STRONG, true),
		_mate(2, STRONG, true),
		_mate(3, WEAK, true),
		_mate(4, STRONG, false),
	]
	for a: MateRecord in mates:
		check_false(MateSelector.outranks(a, a, g), "slot %d does not outrank itself" % a.other_slot)
		for b: MateRecord in mates:
			if a.other_slot == b.other_slot:
				continue
			var ab := MateSelector.outranks(a, b, g)
			var ba := MateSelector.outranks(b, a, g)
			check_true(
				ab != ba,
				(
					"exactly one of (%d, %d) outranks the other"
					% [a.other_slot, b.other_slot]
				)
			)


## ===== MATERECORD ======================================================
## The record the selector ranks. Its two derived fields are the ones a
## placement is rated by, and both take the pessimistic reading — which is only
## visible in a test, because every node on both shipped parts currently
## declares the same strength and all of them bear load.


func test_joint_is_rated_by_the_weaker_node() -> void:
	# A joint is a pair of mating faces and fails at whichever face yields
	# first. Rating it by the stronger node would let a part advertise a
	# strength its partner cannot honour, and the joint would then be picked as
	# primary parent — and survive strain — on the back of a number that
	# describes only one end of it.
	var rec := MateRecord.create(7, _node(STRONG, true), _node(WEAK, true))
	check_approx(rec.joint_strength_n, WEAK, "the weaker face sets the joint strength")
	check_eq(rec.other_slot, 7, "and the mated slot is recorded")

	var reversed := MateRecord.create(7, _node(WEAK, true), _node(STRONG, true))
	check_approx(
		reversed.joint_strength_n, WEAK, "which end declared it makes no difference"
	)


func test_a_joint_bears_load_only_when_both_ends_do() -> void:
	check_true(
		MateRecord.create(1, _node(STRONG, true), _node(STRONG, true)).bears_load,
		"both ends bearing"
	)
	check_false(
		MateRecord.create(1, _node(STRONG, true), _node(STRONG, false)).bears_load,
		"the far end refuses"
	)
	check_false(
		MateRecord.create(1, _node(STRONG, false), _node(STRONG, true)).bears_load,
		"the near end refuses"
	)


## ===== HELPERS =========================================================


## Core -> 1 -> 2 -> 3 -> 4, so every slot has a distinct depth.
func _chain_graph() -> ChassisGraph:
	var g := ChassisGraph.new()
	g.attach(CORE, INVALID, [] as Array[MateRecord], 100.0)
	var prev := CORE
	for s: int in range(1, 5):
		var mates: Array[MateRecord] = [_mate(prev, STRONG, true)]
		g.attach(s, prev, mates, 10.0)
		prev = s
	return g


## Core -> 1 -> 2 -> 3, plus a shallow slot 4 hanging directly off the core, so
## that depth and slot index disagree.
func _branch_graph() -> ChassisGraph:
	var g := _chain_graph()
	g.detach(4)
	var mates: Array[MateRecord] = [_mate(CORE, STRONG, true)]
	g.attach(4, CORE, mates, 10.0)
	return g


## Core with two children at equal depth, for the final tie-break.
func _sibling_graph() -> ChassisGraph:
	var g := ChassisGraph.new()
	g.attach(CORE, INVALID, [] as Array[MateRecord], 100.0)
	var slots: Array[int] = [1, 2]
	for s: int in slots:
		var mates: Array[MateRecord] = [_mate(CORE, STRONG, true)]
		g.attach(s, CORE, mates, 10.0)
	return g


## A resolved node carrying only the two fields [method MateRecord.create]
## derives from. Positioned so that the pair is geometrically legal, since
## create() trusts the validator to have checked that already.
func _node(strength: float, bears: bool) -> ResolvedNode:
	var rn := ResolvedNode.new()
	var src := AttachmentNodeDef.new()
	src.joint_strength_n = strength
	src.can_bear_load = bears
	rn.source = src
	return rn


func _mate(other: int, strength: float, bears: bool) -> MateRecord:
	var m := MateRecord.new()
	m.other_slot = other
	m.joint_strength_n = strength
	m.bears_load = bears
	return m


## Asserts the expected winner over every permutation of [param mates].
func _check_order_invariant(
	mates: Array[MateRecord], g: ChassisGraph, expected: int, message: String
) -> void:
	var typed: Array[MateRecord] = []
	for m: MateRecord in mates:
		typed.append(m)
	for perm: Array[MateRecord] in _permutations(typed):
		check_eq(MateSelector.choose_primary_slot(perm, g), expected, message)


## Every ordering of [param items]. Deliberately exhaustive rather than
## randomised: a seeded shuffle would test one order per run and could pass for
## months before hitting the one that fails.
func _permutations(items: Array[MateRecord]) -> Array:
	var out: Array = []
	if items.size() <= 1:
		out.append(items)
		return out
	for i: int in items.size():
		var rest: Array[MateRecord] = []
		for j: int in items.size():
			if j != i:
				rest.append(items[j])
		for tail: Array[MateRecord] in _permutations(rest):
			var perm: Array[MateRecord] = [items[i]]
			for t: MateRecord in tail:
				perm.append(t)
			out.append(perm)
	return out
