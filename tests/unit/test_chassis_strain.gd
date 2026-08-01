extends TestCase
## [ChassisGraph]'s strain model — §4 of doc 04.
##
## Strain is the one quantity in the graph that is derived rather than recorded,
## so every test here fixes a load and asserts the number that comes out, rather
## than asserting that some number changed. A model that is merely monotonic in
## mass would pass a "heavier means more strain" test while being wrong by a
## factor of κ, and κ is the whole difference between a joint that survives a
## jump and one that does not.
##
## The dwell tests all assert both directions: the tick that must not fail the
## joint as well as the tick that must. A dwell that fires early and a dwell that
## fires on time are indistinguishable from the failing side alone.

const CORE := SyndicateConstants.CORE_SLOT
const INVALID := SyndicateConstants.INVALID_SLOT
const G := SyndicateConstants.GRAVITY_MPS2

const CORE_MASS := 380.0
const M_A := 34.0
const M_B := 50.0

## Weak enough that a 34 kg part hanging off it is at a strain worth reading, so
## the expected values below are not all within rounding of zero.
const WEAK_JOINT_N := 500.0
const STRONG_JOINT_N := 60000.0

## Assembly id used for the emitted signal payloads. Non-zero so that a test
## asserting on it cannot pass against a default-initialised field.
const ASSEMBLY := 7

var _strain_events: Array = []
var _failed_joints: Array = []


func before_all() -> void:
	EventBus.joint_strain_changed.connect(_on_strain_changed)
	EventBus.joint_failed.connect(_on_joint_failed)


func after_all() -> void:
	EventBus.joint_strain_changed.disconnect(_on_strain_changed)
	EventBus.joint_failed.disconnect(_on_joint_failed)


## ===== THE STATIC MODEL ================================================


func test_static_strain_is_hanging_load_over_rated_strength() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	g.recompute_strain(ASSEMBLY)

	# κ is 1.0 at rest, so the whole force is the static hanging load.
	var expected := M_A * G / WEAK_JOINT_N
	check_approx(g.edge_strain_between(1, CORE), expected, "strain is m·g / rated", 1e-4)


func test_strain_uses_subtree_mass_not_the_part_alone() -> void:
	# The single most plausible wrong implementation: charging a joint only for
	# the part directly above it. A spar carrying half a hull would then read as
	# lightly loaded right up until it sheared.
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	_attach(g, 2, 1, M_B, STRONG_JOINT_N)
	g.recompute_strain(ASSEMBLY)

	var expected := (M_A + M_B) * G / WEAK_JOINT_N
	check_approx(
		g.edge_strain_between(1, CORE), expected, "the lower joint carries both parts", 1e-4
	)
	check_approx(
		g.edge_strain_between(2, 1), M_B * G / STRONG_JOINT_N, "the upper joint carries one", 1e-4
	)


func test_strain_scales_with_the_dynamic_factor() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	g.recompute_strain(ASSEMBLY)
	var at_rest := g.edge_strain_between(1, CORE)

	# One update lerps a quarter of the way towards the target, so this asserts
	# the smoothing as well as the amplification.
	g.update_dynamic_factor(G)
	var kappa := lerpf(
		ChassisGraph.KAPPA_MIN, ChassisGraph.KAPPA_MIN + 1.0, ChassisGraph.KAPPA_SMOOTHING
	)
	check_approx(g.dynamic_factor(), kappa, "κ smooths a quarter of the way", 1e-5)

	g.recompute_strain(ASSEMBLY)
	check_approx(
		g.edge_strain_between(1, CORE), at_rest * kappa, "strain scales by κ exactly", 1e-4
	)


func test_dynamic_factor_is_clamped_at_both_ends() -> void:
	var g := _graph_with_core()
	for i in 40:
		g.update_dynamic_factor(1000.0)
	check_approx(g.dynamic_factor(), ChassisGraph.KAPPA_MAX, "κ saturates at the ceiling", 1e-3)
	for i in 40:
		g.update_dynamic_factor(-1000.0)
	check_approx(g.dynamic_factor(), ChassisGraph.KAPPA_MIN, "κ bottoms out at 1.0", 1e-3)


func test_the_core_module_has_no_strained_joint() -> void:
	# Slot 0 has no parent, so there is no edge for its own mass to load. An
	# implementation that walked every live slot without checking would index
	# the parent array at INVALID.
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	g.recompute_strain(ASSEMBLY)
	check_eq(int(g.parent[CORE]), INVALID, "the core stays rootless through a recompute")


## ===== DEPOSITS ========================================================


func test_recoil_deposit_adds_to_the_joint_below_it() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	g.recompute_strain(ASSEMBLY)
	var static_strain := g.edge_strain_between(1, CORE)

	g.deposit_recoil_force(1, 200.0)
	g.recompute_strain(ASSEMBLY)
	check_approx(
		g.edge_strain_between(1, CORE),
		static_strain + 200.0 / WEAK_JOINT_N,
		"recoil adds its force over the rated strength",
		1e-4
	)


func test_deposits_are_summed_over_the_subtree() -> void:
	# §4.1's F_recoil(s) is the recoil of every Effector Module in the subtree,
	# not just at s. An effector three parts up still loads the joint at the
	# bottom of the stack.
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	_attach(g, 2, 1, M_B, STRONG_JOINT_N)
	g.deposit_recoil_force(2, 300.0)
	g.recompute_strain(ASSEMBLY)

	var expected := ((M_A + M_B) * G + 300.0) / WEAK_JOINT_N
	check_approx(
		g.edge_strain_between(1, CORE), expected, "the deposit reaches the lower joint", 1e-4
	)


func test_deposits_take_the_peak_not_the_sum() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	g.deposit_impact_force(1, 400.0)
	g.deposit_impact_force(1, 150.0)
	g.recompute_strain(ASSEMBLY)

	var expected := (M_A * G + 400.0) / WEAK_JOINT_N
	check_approx(g.edge_strain_between(1, CORE), expected, "the smaller deposit is absorbed", 1e-4)


func test_deposits_decay_to_nothing() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	g.deposit_impact_force(1, 400.0)
	g.recompute_strain(ASSEMBLY)
	var loaded := g.edge_strain_between(1, CORE)

	var still_active := true
	var guard := 0
	while still_active and guard < 2000:
		still_active = g.decay_deposits(SyndicateConstants.PHYSICS_DT)
		guard += 1
	check_false(still_active, "the decay set empties")

	g.recompute_strain(ASSEMBLY)
	check_approx(
		g.edge_strain_between(1, CORE), M_A * G / WEAK_JOINT_N, "only the static load remains", 1e-4
	)
	check_true(loaded > g.edge_strain_between(1, CORE), "and it was higher while loaded")


func test_decay_costs_nothing_when_nothing_is_loaded() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	check_false(g.decay_deposits(SyndicateConstants.PHYSICS_DT), "an unloaded graph reports idle")


## ===== CANDIDATES AND DWELL ============================================


func test_only_edges_above_the_threshold_become_candidates() -> void:
	var g := _graph_with_core()
	# Rated so the static load lands well under the 0.85 candidate threshold.
	_attach(g, 1, CORE, M_A, STRONG_JOINT_N)
	g.recompute_strain(ASSEMBLY)
	check_eq(g.strained_candidates(), PackedByteArray(), "a lightly loaded joint is not tracked")

	g.deposit_impact_force(1, STRONG_JOINT_N)
	g.recompute_strain(ASSEMBLY)
	check_eq(g.strained_candidates(), PackedByteArray([1]), "an overloaded joint is tracked")


func test_a_candidate_that_unloads_leaves_the_set() -> void:
	# The set is rebuilt on every recompute rather than only added to. Left
	# growing, a joint that was briefly overloaded during a jump would be swept
	# for dwell for the rest of the match.
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, STRONG_JOINT_N)
	g.deposit_impact_force(1, STRONG_JOINT_N)
	g.recompute_strain(ASSEMBLY)
	check_eq(g.strained_candidates(), PackedByteArray([1]), "tracked while overloaded")

	g.decay_deposits(60.0)
	g.recompute_strain(ASSEMBLY)
	check_eq(g.strained_candidates(), PackedByteArray(), "untracked once the load is gone")


func test_a_joint_fails_only_after_the_full_dwell() -> void:
	var g := _overloaded_graph()
	_failed_joints.clear()

	var dt := SyndicateConstants.PHYSICS_DT
	var ticks := int(ceil(ChassisGraph.STRAIN_FAILURE_DWELL_S / dt))
	for i in ticks - 1:
		g.evaluate_strain(ASSEMBLY, dt)
	check_eq(_failed_joints.size(), 0, "the joint holds for the whole dwell")

	g.evaluate_strain(ASSEMBLY, dt)
	check_eq(_failed_joints.size(), 1, "and fails on the tick that completes it")
	check_eq(_failed_joints[0], [ASSEMBLY, 1, CORE], "naming the assembly and both ends")


func test_dwell_resets_when_the_load_comes_off() -> void:
	var g := _overloaded_graph()
	_failed_joints.clear()

	var dt := SyndicateConstants.PHYSICS_DT
	for i in 20:
		g.evaluate_strain(ASSEMBLY, dt)
	check_true(g.dwell_seconds(1, CORE) > 0.0, "dwell accrued while overloaded")

	g.decay_deposits(60.0)
	g.recompute_strain(ASSEMBLY)
	check_approx(g.dwell_seconds(1, CORE), 0.0, "and is cleared when the strain drops")
	check_eq(_failed_joints.size(), 0, "with no failure emitted")


func test_dwell_is_one_timer_per_joint_not_one_per_endpoint() -> void:
	# §4.2 as written keys dwell on the ordered pair, giving one physical joint
	# two independent counters. Reading it from both ends must give one number.
	var g := _overloaded_graph()
	g.evaluate_strain(ASSEMBLY, 0.1)
	check_approx(g.dwell_seconds(1, CORE), 0.1, "dwell readable from the child")
	check_approx(g.dwell_seconds(CORE, 1), 0.1, "and identical from the parent")


func test_evaluation_is_free_with_no_candidates() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, STRONG_JOINT_N)
	g.recompute_strain(ASSEMBLY)
	_failed_joints.clear()
	for i in 200:
		g.evaluate_strain(ASSEMBLY, 1.0)
	check_eq(_failed_joints.size(), 0, "an unloaded Assembly never fails a joint")


## ===== SIGNALS AND BOOKKEEPING =========================================


func test_strain_changes_are_announced_once_per_change() -> void:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	_strain_events.clear()

	g.recompute_strain(ASSEMBLY)
	check_eq(_strain_events.size(), 1, "the first recompute announces the joint")

	g.recompute_strain(ASSEMBLY)
	check_eq(_strain_events.size(), 1, "an identical recompute announces nothing")

	g.deposit_impact_force(1, 300.0)
	g.recompute_strain(ASSEMBLY)
	check_eq(_strain_events.size(), 2, "a real change announces again")


func test_detach_forgets_the_dwell_it_was_accruing() -> void:
	# A slot's dwell keys are reachable again the moment the slot is reused, and
	# a stale timer would fail a fresh joint partway through its first second.
	var g := _overloaded_graph()
	g.evaluate_strain(ASSEMBLY, 0.2)
	check_true(g.dwell_seconds(1, CORE) > 0.0, "dwell accrued")

	g.detach(1)
	check_approx(g.dwell_seconds(1, CORE), 0.0, "detaching clears it")
	check_eq(g.strained_candidates(), PackedByteArray(), "and drops the candidate")


func test_mass_dirty_is_set_by_a_propagation_and_cleared_on_demand() -> void:
	var g := ChassisGraph.new()
	check_false(g.is_mass_dirty(), "a fresh graph is clean")
	g.attach(CORE, INVALID, [] as Array[MateRecord], CORE_MASS)
	check_true(g.is_mass_dirty(), "an attach dirties the mass")
	g.clear_mass_dirty()
	check_false(g.is_mass_dirty(), "and the solver can clear it")
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	check_true(g.is_mass_dirty(), "a second attach dirties it again")


## ===== HELPERS =========================================================


func _on_strain_changed(assembly_id: int, a: int, b: int, strain: float) -> void:
	_strain_events.append([assembly_id, a, b, strain])


func _on_joint_failed(assembly_id: int, a: int, b: int) -> void:
	_failed_joints.append([assembly_id, a, b])


func _graph_with_core() -> ChassisGraph:
	var g := ChassisGraph.new()
	g.attach(CORE, INVALID, [] as Array[MateRecord], CORE_MASS)
	return g


## A two-part graph whose one joint is loaded past its rated strength and has
## already been swept into the candidate set.
func _overloaded_graph() -> ChassisGraph:
	var g := _graph_with_core()
	_attach(g, 1, CORE, M_A, WEAK_JOINT_N)
	g.deposit_impact_force(1, WEAK_JOINT_N * 2.0)
	g.recompute_strain(ASSEMBLY)
	return g


func _attach(g: ChassisGraph, slot: int, to: int, mass: float, strength: float) -> void:
	var m := MateRecord.new()
	m.other_slot = to
	m.joint_strength_n = strength
	m.bears_load = true
	g.attach(slot, to, [m] as Array[MateRecord], mass)
