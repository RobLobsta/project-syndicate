extends TestCase
## [PlacementValidator] end to end — the check chain of doc 02 §7, and commit
## and removal (§9), against the real shipped parts.
##
## This is the gate every path into the lattice passes through: the garage, the
## auto-assembler, blueprint loading, and the server's re-validation of a
## blueprint a client sent (Architectural Invariant I-8). A check that silently
## stops rejecting does not fail here as an error — it fails as a placement the
## game quietly starts allowing, months later, in a build nobody is looking at.
## So every check below is asserted in both directions: a case it must reject
## and a neighbouring case it must not.
##
## Real parts where the geometry is the point, synthetic definitions where a
## rule needs a part class or a limit that is not authored yet. A synthetic
## candidate is never committed — only validated — because commit resolves
## definitions through [code]PartRegistry[/code], and a fixture in the registry
## would change what every other test in the suite sees.

const CORE_KEY := &"core.command.compact.t2"
const PANEL_KEY := &"str.panel.medium.t2"

## The Core Module seated at the lattice origin. Occupies x 22..25, y 4..6,
## z 22..26; its whole top face at y = 6 is DECK polarity.
const CORE_ORIGIN := Vector3i(24, 4, 24)
## Directly on the Core Module's deck. The panel occupies x 22..25, z 22..25.
const DECK_ORIGIN := Vector3i(24, 7, 24)
## One cell out from the Core Module's +X face, with clear air below it.
const BESIDE_ORIGIN := Vector3i(26, 5, 24)

## Published in doc 01 §10.2 and re-asserted here so a data change that breaks
## the arithmetic below names itself rather than failing as a wrong reject code.
const PANEL_MASS := 34.0
const PANEL_LOAD_CAPACITY := 520.0
const CORE_MOUNT_BUDGET := 28
const CORE_POWER_CAPACITY := 240.0

var _core: PartDefinition = null
var _panel: PartDefinition = null
## Contexts created by tests, disposed together. Physics server RIDs are not
## reference counted, so a context dropped without disposal leaks a space that
## keeps stepping for the life of the process.
var _contexts: Array[BuildContext] = []


func before_all() -> void:
	_core = PartRegistry.definition_by_key(CORE_KEY)
	_panel = PartRegistry.definition_by_key(PANEL_KEY)


func after_all() -> void:
	for ctx in _contexts:
		ctx.dispose()
	_contexts.clear()


## ===== FIXTURE SANITY ==================================================


func test_fixture_parts_are_what_the_arithmetic_below_assumes() -> void:
	check_not_null(_core, "the Core Module is registered")
	check_not_null(_panel, "the Structural Component is registered")
	check_approx(_panel.mass_kg, PANEL_MASS, "panel mass matches doc 01 §10.2")
	check_approx(
		_panel.load_capacity_kg, PANEL_LOAD_CAPACITY, "panel load capacity matches §10.2"
	)
	check_eq(_core.core_profile.mount_budget, CORE_MOUNT_BUDGET, "core mount budget matches §10.1")
	check_approx(
		_core.core_profile.power_capacity_pu, CORE_POWER_CAPACITY, "core power capacity matches"
	)


## ===== §7.1 BOUNDS =====================================================


func test_out_of_bounds_is_rejected() -> void:
	var ctx := _new_context()
	var cand := PlacementCandidate.create(_core, Vector3i(1, 1, 1), 0)
	check_eq(
		_validate(ctx, cand), PlacementValidator.Reject.OUT_OF_BOUNDS,
		"a part straddling the lattice edge is out of bounds"
	)


## ===== §7.2 OCCUPANCY ==================================================


func test_overlap_is_rejected_before_anything_expensive() -> void:
	# Occupancy is checked second, before mating and before the physics query.
	# A second Core Module on top of the first is both occupied and duplicate;
	# the cheaper answer is the one the chain must give.
	var ctx := _context_with_core()
	var cand := PlacementCandidate.create(_core, CORE_ORIGIN, 0)
	check_eq(
		_validate(ctx, cand), PlacementValidator.Reject.CELL_OCCUPIED,
		"overlapping cells reject on occupancy, not on the duplicate core"
	)


## ===== §7.3 MATING =====================================================


func test_an_assembly_must_start_with_a_core_module() -> void:
	var ctx := _new_context()
	var panel := PlacementCandidate.create(_panel, DECK_ORIGIN, 0)
	check_eq(
		_validate(ctx, panel), PlacementValidator.Reject.NO_MATING_NODE,
		"a Structural Component has nothing to attach to in an empty lattice"
	)
	var core := PlacementCandidate.create(_core, CORE_ORIGIN, 0)
	check_eq(
		_validate(ctx, core), PlacementValidator.Reject.NONE,
		"the Core Module is the graph root and needs no mate (I-2)"
	)


func test_panel_mates_on_the_core_deck() -> void:
	var ctx := _context_with_core()
	var cand := PlacementCandidate.create(_panel, DECK_ORIGIN, 0)
	check_eq(_validate(ctx, cand), PlacementValidator.Reject.NONE, "the panel seats on the deck")
	check_eq(cand.parent_slot, SyndicateConstants.CORE_SLOT, "its parent is the Core Module")
	check_eq(cand.mates.size(), 1, "one physical joint, not one per shared face")
	check_true(cand.mates[0].bears_load, "the joint bears load")


func test_a_part_floating_free_of_everything_is_rejected() -> void:
	var ctx := _context_with_core()
	var cand := PlacementCandidate.create(_panel, Vector3i(24, 20, 24), 0)
	check_eq(
		_validate(ctx, cand), PlacementValidator.Reject.NO_MATING_NODE,
		"a part in clear air above the Assembly has no mate"
	)


func test_polarity_mismatch_is_distinguished_from_no_mate() -> void:
	# The Core Module's deck accepts FACE_MALE and FACE_NEUTRAL and refuses
	# FACE_FEMALE (doc 02 §7.3). The player found the right face and the wrong
	# part, and the ghost has to say so — "nothing to attach to" would send them
	# looking somewhere else entirely.
	var ctx := _context_with_core()
	var def := _synthetic(PartEnums.PartClass.SUPPORT_MODULE, PartEnums.AttachmentPolarity.FACE_FEMALE)
	var cand := PlacementCandidate.create(def, DECK_ORIGIN, 0)
	check_eq(
		_validate(ctx, cand), PlacementValidator.Reject.POLARITY_MISMATCH,
		"a recessed face cannot mate with a deck"
	)


func test_class_restriction_is_distinguished_from_polarity() -> void:
	var ctx := _context_with_core()
	var def := _synthetic(PartEnums.PartClass.SUPPORT_MODULE, PartEnums.AttachmentPolarity.FACE_NEUTRAL)
	# Accepts only Motive Assemblies, so the Core Module below is refused.
	for node in def.attachment_nodes:
		node.accepts_classes = PackedInt32Array([int(PartEnums.PartClass.MOTIVE_ASSEMBLY)])
	var cand := PlacementCandidate.create(def, DECK_ORIGIN, 0)
	check_eq(
		_validate(ctx, cand), PlacementValidator.Reject.CLASS_NOT_ACCEPTED,
		"the polarity fits but the class restriction does not"
	)


## ===== §7.4 CLASS LIMITS AND BUDGETS ===================================


func test_second_core_module_is_rejected() -> void:
	var ctx := _context_with_core()
	var cand := PlacementCandidate.create(_core, Vector3i(24, 10, 24), 0)
	# Seated so its own cells clear the committed core but its lower face still
	# mates, isolating DUPLICATE_CORE from CELL_OCCUPIED.
	cand.origin_cell = Vector3i(24, 7, 24)
	cand.resolve()
	check_eq(
		_validate(ctx, cand), PlacementValidator.Reject.DUPLICATE_CORE,
		"exactly one Core Module per Assembly (I-2)"
	)


func test_mount_budget_boundary() -> void:
	var ctx := _context_with_core()
	var exact := _synthetic(PartEnums.PartClass.SUPPORT_MODULE, PartEnums.AttachmentPolarity.FACE_NEUTRAL)
	exact.mount_weight = CORE_MOUNT_BUDGET
	check_eq(
		_validate(ctx, PlacementCandidate.create(exact, DECK_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"consuming the budget exactly is legal"
	)

	var over := _synthetic(PartEnums.PartClass.SUPPORT_MODULE, PartEnums.AttachmentPolarity.FACE_NEUTRAL)
	over.mount_weight = CORE_MOUNT_BUDGET + 1
	check_eq(
		_validate(ctx, PlacementCandidate.create(over, DECK_ORIGIN, 0)),
		PlacementValidator.Reject.MOUNT_BUDGET_EXCEEDED,
		"one over the budget is not"
	)


func test_core_module_is_exempt_from_its_own_mount_budget() -> void:
	# The Core Module offers the mounts, so it cannot be charged against them:
	# before it is committed the budget is zero, and any non-zero mount weight
	# on the core itself would make an Assembly impossible to start.
	#
	# The shipped Core Module declares mount_weight 0, which would let this pass
	# whether the exemption existed or not. A synthetic core with a real mount
	# weight is what actually exercises it.
	var ctx := _new_context()
	check_eq(
		_validate(ctx, PlacementCandidate.create(_core, CORE_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"the shipped Core Module places into an empty lattice"
	)

	var heavy := _synthetic(
		PartEnums.PartClass.CORE_MODULE, PartEnums.AttachmentPolarity.FACE_NEUTRAL
	)
	heavy.core_profile = CoreModuleProfile.new()
	heavy.mount_weight = 5
	heavy.power_draw_pu = 50.0
	check_eq(
		_validate(_new_context(), PlacementCandidate.create(heavy, CORE_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"a Core Module carrying mount weight and draw is still exempt from both"
	)


func test_power_budget_boundary() -> void:
	var ctx := _context_with_core()
	var exact := _synthetic(PartEnums.PartClass.SUPPORT_MODULE, PartEnums.AttachmentPolarity.FACE_NEUTRAL)
	exact.power_draw_pu = CORE_POWER_CAPACITY
	check_eq(
		_validate(ctx, PlacementCandidate.create(exact, DECK_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"drawing the whole capacity is legal"
	)

	var over := _synthetic(PartEnums.PartClass.SUPPORT_MODULE, PartEnums.AttachmentPolarity.FACE_NEUTRAL)
	over.power_draw_pu = CORE_POWER_CAPACITY + 1.0
	check_eq(
		_validate(ctx, PlacementCandidate.create(over, DECK_ORIGIN, 0)),
		PlacementValidator.Reject.POWER_BUDGET_EXCEEDED,
		"one power unit over is not"
	)


func test_a_part_carrying_its_own_supply_pays_for_itself() -> void:
	var ctx := _context_with_core()
	var plant := _synthetic(PartEnums.PartClass.PRIME_MOVER, PartEnums.AttachmentPolarity.FACE_NEUTRAL)
	plant.power_draw_pu = CORE_POWER_CAPACITY * 2.0
	plant.power_supply_pu = CORE_POWER_CAPACITY * 2.0
	check_eq(
		_validate(ctx, PlacementCandidate.create(plant, DECK_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"its own supply counts toward the capacity its draw is checked against"
	)


func test_effector_class_limit() -> void:
	var ctx := _context_with_core()
	var eff := _synthetic(PartEnums.PartClass.EFFECTOR_MODULE, PartEnums.AttachmentPolarity.FACE_NEUTRAL)
	eff.effector_profile = EffectorModuleProfile.new()
	# Wide open arc, so the limit is what rejects rather than §7.6.
	eff.effector_profile.yaw_limit_deg = Vector2(-180.0, 180.0)
	eff.effector_profile.muzzle_offsets_m = PackedVector3Array([Vector3(0.0, 0.0, 0.125)])

	check_eq(
		_validate(ctx, PlacementCandidate.create(eff, DECK_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"the first Effector Module is fine"
	)
	# Charge the ledger directly: committing sixteen synthetic parts would need
	# them in the registry, and the check reads only these counters.
	for _i in SyndicateConstants.MAX_EFFECTORS_PER_ASSEMBLY:
		ctx.budgets.add(eff)
	check_eq(
		_validate(ctx, PlacementCandidate.create(eff, DECK_ORIGIN, 0)),
		PlacementValidator.Reject.CLASS_LIMIT_EXCEEDED,
		"the seventeenth is not"
	)


## ===== §7.5 MOTIVE GROUND CLEARANCE ====================================


func test_motive_clearance_rejects_a_blocked_travel_envelope() -> void:
	# A blocked suspension is invisible in the garage and produces violent
	# jitter in a match. Catching it here removes the whole failure class.
	var ctx := _context_with_core()
	var motive := _motive()
	check_eq(
		_validate(ctx, PlacementCandidate.create(motive, DECK_ORIGIN, 0)),
		PlacementValidator.Reject.MOTIVE_GROUND_BLOCKED,
		"mounted on the deck, its travel sweeps straight into the Core Module"
	)


func test_motive_clearance_accepts_clear_air_below() -> void:
	var ctx := _context_with_core()
	var motive := _motive()
	check_eq(
		_validate(ctx, PlacementCandidate.create(motive, BESIDE_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"mounted on the flank with clear air below, the same part is legal"
	)


func test_motive_clearance_follows_the_part_orientation() -> void:
	# The probe direction is the part's own down, rotated. Inverted, its travel
	# sweeps upward — which is clear here, where its upright travel is not.
	var ctx := _context_with_core()
	var motive := _motive()
	var inverted := PlacementCandidate.create(motive, DECK_ORIGIN, _inverted_orientation())
	check_eq(
		OrientationTable.rotate_face(inverted.orientation_index, Vector3i(0, -1, 0)),
		Vector3i(0, 1, 0),
		"fixture: this orientation turns the part's down into world up"
	)
	check_eq(
		_validate(ctx, inverted), PlacementValidator.Reject.NONE,
		"inverted, the travel envelope points into clear air"
	)


func test_non_motive_parts_skip_the_clearance_check() -> void:
	var ctx := _context_with_core()
	check_eq(
		_validate(ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"a Structural Component on the deck has no travel envelope to block"
	)


## ===== §7.6 EFFECTOR ARC ===============================================


func test_effector_arc_is_clear_above_the_assembly() -> void:
	var ctx := _context_with_core()
	check_eq(
		_validate(ctx, PlacementCandidate.create(_effector(), DECK_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"nothing obstructs a deck-mounted effector's traverse"
	)


func test_effector_arc_rejects_a_fully_enclosed_module() -> void:
	var ctx := _context_with_core()
	_wall_ring(ctx, DECK_ORIGIN, 3)
	check_eq(
		_validate(ctx, PlacementCandidate.create(_effector(), DECK_ORIGIN, 0)),
		PlacementValidator.Reject.EFFECTOR_ARC_BLOCKED,
		"walled in on every side, the traversable arc collapses"
	)


func test_effector_arc_tolerates_partial_obstruction() -> void:
	# A turret tucked behind a Structural Component has cover and a narrow arc.
	# That is a trade the player is allowed to make; §7.6 only rejects the
	# fully buried case.
	var ctx := _context_with_core()
	_wall_side(ctx, DECK_ORIGIN, 3)
	check_eq(
		_validate(ctx, PlacementCandidate.create(_effector(), DECK_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"one wall costs arc without making the module useless"
	)


func test_arc_trace_ignores_the_candidates_own_cells() -> void:
	# The blueprint re-validation case: the part is already in the occupancy
	# array. A trace that counted its own cells as obstruction would reject
	# every effector on reload.
	var ctx := _context_with_core()
	var cand := PlacementCandidate.create(_effector(), DECK_ORIGIN, 0)
	ctx.occupancy.write_slot(200, cand.cells)
	check_eq(
		PlacementValidator._check_effector_arc(ctx, cand), PlacementValidator.Reject.NONE,
		"a muzzle starting inside its own module is not blocked by it"
	)
	ctx.occupancy.erase_slot(200)


## ===== §7.7 COLLIDER INTERPENETRATION ==================================


func test_face_contact_is_not_penetration() -> void:
	# Every part in an Assembly touches its neighbours by construction, and the
	# shipped colliders fill their cells exactly. Without the negative margin
	# this check would reject every legal placement in the game.
	var ctx := _context_with_core()
	check_true(ctx.has_physics(), "fixture: the context has a physics space")
	check_eq(
		_validate(ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"a panel resting flush on the core deck does not interpenetrate it"
	)


func test_an_oversized_collider_is_caught() -> void:
	var ctx := _context_with_core()
	var bulging := _synthetic(
		PartEnums.PartClass.SUPPORT_MODULE, PartEnums.AttachmentPolarity.FACE_NEUTRAL
	)
	_set_box_collider(bulging, Vector3(0.5, 0.5, 0.5))
	check_eq(
		_validate(ctx, PlacementCandidate.create(bulging, BESIDE_ORIGIN, 0)),
		PlacementValidator.Reject.COLLIDER_INTERPENETRATION,
		"a primitive protruding well past its own cells overlaps the neighbour"
	)


func test_headless_context_skips_the_physics_query() -> void:
	# §12 invariant 1: the physics query may only reject, never accept. Skipping
	# it on the dedicated server therefore cannot admit anything the integer
	# checks refused — which is what makes server-side blueprint validation
	# affordable without a physics space per connecting player.
	var ctx := _headless_context_with_core()
	var bulging := _synthetic(
		PartEnums.PartClass.SUPPORT_MODULE, PartEnums.AttachmentPolarity.FACE_NEUTRAL
	)
	_set_box_collider(bulging, Vector3(0.5, 0.5, 0.5))
	check_false(ctx.has_physics(), "fixture: no physics space")
	check_eq(
		_validate(ctx, PlacementCandidate.create(bulging, BESIDE_ORIGIN, 0)),
		PlacementValidator.Reject.NONE,
		"the same candidate passes every integer check"
	)


## ===== §7.8 STRUCTURAL LOAD ============================================


func test_load_capacity_boundary_under_hard_limits() -> void:
	# Fourteen panels hang off the first one: 14 x 34 kg = 476 kg, and one more
	# panel brings the joint to 510 kg against the panel's 520 kg capacity.
	var ctx := _stacked_context(14)
	ctx.enforce_hard_limits = true
	check_approx(
		ctx.graph.subtree_mass[1], 14.0 * PANEL_MASS, "fixture: the stack masses what it should"
	)
	var under := PlacementCandidate.create(_panel, Vector3i(28, 7, 24), 0)
	check_eq(
		_validate(ctx, under), PlacementValidator.Reject.NONE,
		"510 kg on a 520 kg joint is within capacity"
	)


func test_load_capacity_exceeded_under_hard_limits() -> void:
	var ctx := _stacked_context(15)
	ctx.enforce_hard_limits = true
	check_approx(ctx.graph.subtree_mass[1], 15.0 * PANEL_MASS, "fixture: 510 kg already hanging")
	var over := PlacementCandidate.create(_panel, Vector3i(28, 7, 24), 0)
	check_eq(
		_validate(ctx, over), PlacementValidator.Reject.LOAD_CAPACITY_EXCEEDED,
		"544 kg on a 520 kg joint is refused in Ranked mode"
	)


func test_load_capacity_is_soft_in_sandbox() -> void:
	var ctx := _stacked_context(15)
	ctx.enforce_hard_limits = false
	var over := PlacementCandidate.create(_panel, Vector3i(28, 7, 24), 0)
	check_eq(
		_validate(ctx, over), PlacementValidator.Reject.NONE,
		"Sandbox admits the over-capacity placement"
	)
	check_eq(
		over.soft_reject, PlacementValidator.Reject.LOAD_CAPACITY_EXCEEDED,
		"but records why it is strained, for the amber ghost of §8"
	)

	var slot := PlacementValidator.commit(ctx, over)
	check_true(
		ctx.state(slot).has_flag(PartFlags.FLAG_STRAINED),
		"and commits it flagged, so the joint fails earlier under combat stress"
	)


func test_a_clean_placement_is_not_flagged_strained() -> void:
	var ctx := _context_with_core()
	var cand := PlacementCandidate.create(_panel, DECK_ORIGIN, 0)
	var slot := PlacementValidator.commit(ctx, cand)
	check_eq(cand.soft_reject, PlacementValidator.Reject.NONE, "nothing soft-rejected")
	check_false(ctx.state(slot).has_flag(PartFlags.FLAG_STRAINED), "and the part is unflagged")


## ===== §9.1 COMMIT =====================================================


func test_core_commits_to_slot_zero() -> void:
	var ctx := _new_context()
	var slot := PlacementValidator.commit(ctx, PlacementCandidate.create(_core, CORE_ORIGIN, 0))
	check_eq(slot, SyndicateConstants.CORE_SLOT, "the Core Module lands on slot 0 (I-2)")
	check_eq(
		int(ctx.graph.parent[slot]), SyndicateConstants.INVALID_SLOT,
		"and is the primary tree root"
	)
	check_eq(
		ctx.occupancy.occupied_count, _core.occupancy_cells.size(),
		"its whole footprint is claimed"
	)


func test_commit_updates_every_structure_at_once() -> void:
	var ctx := _context_with_core()
	var cand := PlacementCandidate.create(_panel, DECK_ORIGIN, 0)
	var before_cells := ctx.occupancy.occupied_count
	var slot := PlacementValidator.commit(ctx, cand)

	check_eq(slot, 1, "the panel takes the next free slot")
	check_eq(
		ctx.occupancy.occupied_count, before_cells + _panel.occupancy_cells.size(),
		"occupancy grew by exactly the panel's footprint"
	)
	check_eq(ctx.state(slot).part_def_id, _panel.runtime_id, "state records the definition")
	check_eq(ctx.state(slot).parent_slot, SyndicateConstants.CORE_SLOT, "and its parent")
	check_approx(ctx.state(slot).integrity, _panel.integrity_max, "committed at full integrity")
	check_true(ctx.graph.is_alive(slot), "the graph knows about it")
	check_approx(
		ctx.graph.subtree_mass[SyndicateConstants.CORE_SLOT], _core.mass_kg + PANEL_MASS,
		"and the core's subtree mass includes it"
	)
	check_eq(ctx.budgets.mount_used, _panel.mount_weight, "the ledger charged the mount")
	check_true(ctx.proxy_body(slot).is_valid(), "and a build proxy exists for §7.7")


func test_commit_emits_part_attached() -> void:
	# EventBus is what wakes the mass solver, the fusion rebuild, and the stat
	# panel. Nothing polls (Architectural Invariant I-4), so a commit that does
	# not emit leaves every one of them showing stale numbers.
	var ctx := _context_with_core()
	var seen := _SignalProbe.new()
	EventBus.part_attached.connect(seen.on_part)
	PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0))
	EventBus.part_attached.disconnect(seen.on_part)

	check_eq(seen.count, 1, "exactly one part_attached")
	check_eq(seen.last_assembly, ctx.assembly_id, "carrying this Assembly's id")
	check_eq(seen.last_slot, 1, "and the committed slot")


## ===== §9.2 REMOVAL ====================================================


func test_removal_restores_the_lattice_exactly() -> void:
	var ctx := _context_with_core()
	var before := ctx.occupancy.occupied_count
	var slot := PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0))
	var cascaded := PlacementValidator.remove(ctx, slot)

	check_eq(cascaded, PackedByteArray(), "a leaf takes nothing with it")
	check_eq(ctx.occupancy.occupied_count, before, "occupancy is back where it started")
	check_null(ctx.state(slot), "the slot is free")
	check_false(ctx.graph.is_alive(slot), "the graph dropped it")
	check_eq(ctx.budgets.mount_used, 0, "the ledger released the mount")
	check_false(ctx.proxy_body(slot).is_valid(), "and the build proxy is gone")
	check_approx(
		ctx.graph.subtree_mass[SyndicateConstants.CORE_SLOT], _core.mass_kg,
		"the core carries only itself again"
	)


func test_removal_reparents_an_orphan_that_has_another_support() -> void:
	# The whole point of §9.2: orphans that can find a new parent are kept, and
	# only the genuinely unsupported are removed.
	var ctx := _reparent_fixture()
	var cascaded := PlacementValidator.remove(ctx, 2)

	check_eq(cascaded, PackedByteArray(), "nothing was cascaded")
	check_true(ctx.graph.is_alive(3), "the orphan survived")
	check_eq(int(ctx.graph.parent[3]), 4, "re-parented onto the neighbour it still rests on")
	check_eq(ctx.state(3).parent_slot, 4, "and its state agrees with the graph")
	check_true(ctx.graph.is_connected_to_core(3), "it still reaches the Core Module")


func test_removal_cascades_what_cannot_be_reparented() -> void:
	var ctx := _reparent_fixture()
	var cascaded := PlacementValidator.remove(ctx, 1)

	check_eq(cascaded, PackedByteArray([2]), "the part with no other support went too")
	check_false(ctx.graph.is_alive(2), "and is gone from the graph")
	check_true(ctx.graph.is_alive(3), "while the one that could re-parent stayed")
	check_eq(int(ctx.graph.parent[3]), 4, "hanging off its surviving neighbour")


func test_removing_the_core_module_takes_everything() -> void:
	# Architectural Invariant I-2: losing the Core Module terminates the
	# Assembly. Nothing can re-parent, because nothing reaches a dead root.
	var ctx := _reparent_fixture()
	var cascaded := PlacementValidator.remove(ctx, SyndicateConstants.CORE_SLOT)

	check_eq(cascaded.size(), 4, "every other part cascaded")
	check_eq(ctx.occupancy.occupied_count, 0, "the lattice is empty")
	check_eq(ctx.graph.live_slots(), PackedByteArray(), "and so is the graph")
	check_eq(ctx.budgets.mount_used, 0, "the ledger is back to zero")


func test_removal_emits_part_removed() -> void:
	var ctx := _context_with_core()
	var slot := PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0))
	var seen := _SignalProbe.new()
	EventBus.part_removed.connect(seen.on_part)
	PlacementValidator.remove(ctx, slot)
	EventBus.part_removed.disconnect(seen.on_part)
	check_eq(seen.count, 1, "exactly one part_removed")


func test_commit_removal_cycles_do_not_drift() -> void:
	# Every structure the validator touches is maintained incrementally, and
	# none of them fails loudly. Twenty-five cycles make a one-part-per-cycle
	# leak in any of them obvious.
	var ctx := _context_with_core()
	var cells := ctx.occupancy.occupied_count
	for i in 25:
		var slot := PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0))
		PlacementValidator.remove(ctx, slot)
		check_eq(ctx.occupancy.occupied_count, cells, "occupancy after cycle %d" % i)
		check_eq(ctx.budgets.mount_used, 0, "mount budget after cycle %d" % i)
		check_approx(
			ctx.graph.subtree_mass[SyndicateConstants.CORE_SLOT], _core.mass_kg,
			"core subtree mass after cycle %d" % i
		)
	check_eq(ctx.graph.live_slots(), PackedByteArray([0]), "only the Core Module is left")


## ===== CONTRACT ========================================================


func test_every_reject_code_has_a_localisation_key() -> void:
	# CLAUDE.md §10 rule 7: never a literal user-facing string. A missing key
	# would surface as a blank inspector strip, which reads as "no reason given".
	var count := PlacementValidator.Reject.size()
	check_eq(PlacementValidator.REJECT_KEYS.size(), count, "one key per rejection code")
	var seen := {}
	for key: StringName in PlacementValidator.REJECT_KEYS:
		check_true(String(key).begins_with("build.reject."), "'%s' is namespaced" % key)
		seen[key] = true
	check_eq(seen.size(), count, "and every key is distinct")


func test_reject_key_lookup_is_total() -> void:
	for i in PlacementValidator.Reject.size():
		check_eq(
			PlacementValidator.reject_key(i), PlacementValidator.REJECT_KEYS[i],
			"code %d resolves to its own key" % i
		)


func test_arc_threshold_matches_the_document() -> void:
	check_approx(
		PlacementValidator.ARC_BLOCKED_REJECT_RATIO, 0.6, "§7.6 sets the threshold at 60%"
	)
	check_approx(
		PlacementValidator.INTERPENETRATION_MARGIN_M, -0.008, "§7.7 sets the margin at -8 mm"
	)


func test_validation_is_repeatable() -> void:
	# §8 throttles validation to candidate changes, so the same candidate is
	# re-validated whenever the player nudges back to a cell they tried before.
	# A chain that accumulated state across runs would answer differently.
	var ctx := _context_with_core()
	var cand := PlacementCandidate.create(_panel, DECK_ORIGIN, 0)
	var first := _validate(ctx, cand)
	var first_parent := cand.parent_slot
	for _i in 8:
		check_eq(_validate(ctx, cand), first, "the same candidate yields the same verdict")
		check_eq(cand.parent_slot, first_parent, "and the same parent")


func test_rejected_candidates_carry_no_parent() -> void:
	# A candidate that failed must not keep a parent from an earlier position:
	# committing on a stale parent would record a joint that does not exist.
	var ctx := _context_with_core()
	var cand := PlacementCandidate.create(_panel, DECK_ORIGIN, 0)
	check_eq(_validate(ctx, cand), PlacementValidator.Reject.NONE, "legal here")
	check_eq(cand.parent_slot, SyndicateConstants.CORE_SLOT, "with the core as parent")

	cand.origin_cell = Vector3i(24, 20, 24)
	cand.resolve()
	check_eq(_validate(ctx, cand), PlacementValidator.Reject.NO_MATING_NODE, "illegal there")
	check_eq(
		cand.parent_slot, SyndicateConstants.INVALID_SLOT, "and the stale parent was cleared"
	)


func test_a_candidate_is_cleared_when_the_lattice_moves_under_it() -> void:
	# The same candidate, unmoved, against a context that changed. Nothing calls
	# resolve() here, so the clearing has to happen inside validate() — this is
	# the case a candidate object reused across an edit actually hits, and a
	# parent left over from the previous verdict would commit a joint to a slot
	# that no longer exists.
	var ctx := _context_with_core()
	var panel := PlacementValidator.commit(
		ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0)
	)
	var cand := PlacementCandidate.create(_panel, Vector3i(24, 8, 24), 0)
	check_eq(_validate(ctx, cand), PlacementValidator.Reject.NONE, "legal on top of the panel")
	check_eq(cand.parent_slot, panel, "with the panel as parent")

	PlacementValidator.remove(ctx, panel)
	check_eq(
		_validate(ctx, cand), PlacementValidator.Reject.NO_MATING_NODE,
		"with the panel gone the same candidate is floating"
	)
	check_eq(
		cand.parent_slot, SyndicateConstants.INVALID_SLOT,
		"and validate cleared the parent without resolve() being called"
	)
	check_eq(cand.mates.size(), 0, "and the mate list with it")


## ===== FIXTURES ========================================================


func _new_context() -> BuildContext:
	var ctx := BuildContext.with_physics(0)
	_contexts.append(ctx)
	return ctx


func _context_with_core() -> BuildContext:
	var ctx := _new_context()
	PlacementValidator.commit(ctx, PlacementCandidate.create(_core, CORE_ORIGIN, 0))
	return ctx


func _headless_context_with_core() -> BuildContext:
	var ctx := BuildContext.headless(0)
	_contexts.append(ctx)
	PlacementValidator.commit(ctx, PlacementCandidate.create(_core, CORE_ORIGIN, 0))
	return ctx


## A Core Module with [param count] panels stacked vertically above it, so that
## slot 1 carries a subtree of known mass for the §7.8 boundary tests.
func _stacked_context(count: int) -> BuildContext:
	var ctx := _context_with_core()
	for i in count:
		var cand := PlacementCandidate.create(_panel, Vector3i(24, 7 + i, 24), 0)
		var r := PlacementValidator.validate(ctx, cand)
		if r != PlacementValidator.Reject.NONE:
			fail("fixture: stacking panel %d rejected with code %d" % [i, r])
			return ctx
		PlacementValidator.commit(ctx, cand)
	return ctx


## Core Module, a panel on its deck (1), a panel above that (2), a panel beside
## the upper one (3), and finally a panel that bridges back down to the core (4).
##
## Commit order is what makes this a re-parenting fixture rather than an
## ordinary stack: slot 3 is committed while slot 2 is its only neighbour, so
## slot 2 becomes its tree parent; slot 4 arrives afterwards and adds the
## support edge that lets slot 3 survive slot 2's removal.
func _reparent_fixture() -> BuildContext:
	var ctx := _context_with_core()
	var origins: Array[Vector3i] = [
		Vector3i(24, 7, 24),  # 1: on the deck
		Vector3i(24, 8, 24),  # 2: above it
		Vector3i(24, 8, 28),  # 3: beside 2, touching nothing else yet
		Vector3i(24, 7, 28),  # 4: below 3, bridging to the core and to 1
	]
	for origin: Vector3i in origins:
		var cand := PlacementCandidate.create(_panel, origin, 0)
		var r := PlacementValidator.validate(ctx, cand)
		if r != PlacementValidator.Reject.NONE:
			fail("fixture: panel at %v rejected with code %d" % [origin, r])
			return ctx
		PlacementValidator.commit(ctx, cand)

	# The fixture only means anything if the tree came out as described.
	if int(ctx.graph.parent[3]) != 2:
		fail("fixture: slot 3's parent is %d, expected 2" % int(ctx.graph.parent[3]))
	if int(ctx.graph.parent[4]) != SyndicateConstants.CORE_SLOT:
		fail("fixture: slot 4's parent is %d, expected 0" % int(ctx.graph.parent[4]))
	return ctx


## A one-cell part with a node on each of the six faces.
func _synthetic(
	part_class: PartEnums.PartClass, polarity: PartEnums.AttachmentPolarity
) -> PartDefinition:
	var def := PartDefinition.new()
	def.part_key = &"fixture.synthetic"
	def.part_class = part_class
	def.mass_kg = PANEL_MASS
	def.integrity_max = 300.0
	def.load_capacity_kg = 400.0
	def.mount_weight = 1
	def.occupancy_cells = PackedVector3Array([Vector3.ZERO])
	var nodes: Array[AttachmentNodeDef] = []
	for face: Vector3i in AttachmentNodeDef.AXIS_NORMALS:
		var node := AttachmentNodeDef.new()
		node.cell = Vector3i.ZERO
		node.face_normal = face
		node.polarity = polarity
		nodes.append(node)
	def.attachment_nodes = nodes
	_set_box_collider(def, Vector3(0.125, 0.125, 0.125))
	def._bake_derived_fields()
	return def


func _motive() -> PartDefinition:
	var def := _synthetic(
		PartEnums.PartClass.MOTIVE_ASSEMBLY, PartEnums.AttachmentPolarity.FACE_NEUTRAL
	)
	var mp := MotiveAssemblyProfile.new()
	# 0.56 m of travel over a 0.25 m cell is three cells of probe depth.
	mp.suspension_rest_length_m = 0.32
	mp.suspension_travel_limit_m = 0.24
	def.motive_profile = mp
	return def


func _effector() -> PartDefinition:
	var def := _synthetic(
		PartEnums.PartClass.EFFECTOR_MODULE, PartEnums.AttachmentPolarity.FACE_NEUTRAL
	)
	var ep := EffectorModuleProfile.new()
	ep.yaw_limit_deg = Vector2(-180.0, 180.0)
	# Half a cell forward, so the trace starts inside the module rather than on
	# a cell boundary where the first DDA step is ambiguous.
	ep.muzzle_offsets_m = PackedVector3Array([Vector3(0.0, 0.0, 0.125)])
	def.effector_profile = ep
	return def


func _set_box_collider(def: PartDefinition, half_extents: Vector3) -> void:
	var prim := ColliderPrimitiveDef.new()
	prim.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	prim.half_extents_m = half_extents
	var profile := ColliderProfile.new()
	profile.primitives = [prim]
	def.collider_profile = profile


## Orientation index whose basis carries the part's own down onto world up.
func _inverted_orientation() -> int:
	for i in SyndicateConstants.ORIENTATION_COUNT:
		if OrientationTable.rotate_face(i, Vector3i(0, -1, 0)) == Vector3i(0, 1, 0):
			return i
	fail("no inverted orientation found in the 24-element group")
	return 0


## Writes a solid one-cell-thick square annulus around [param centre] at
## Chebyshev radius [param radius], in the plane the yaw sweep traverses.
##
## Written straight into occupancy under a spare slot: the arc check reads only
## the occupancy array, and building the ring out of real parts would need
## thirty-two committed panels to test one threshold.
func _wall_ring(ctx: BuildContext, centre: Vector3i, radius: int) -> void:
	var cells := PackedVector3Array()
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dz)) != radius:
				continue
			cells.append(Vector3(centre + Vector3i(dx, 0, dz)))
	ctx.occupancy.write_slot(200, cells)


## One straight wall on the +Z side only, leaving the rest of the arc open.
func _wall_side(ctx: BuildContext, centre: Vector3i, distance: int) -> void:
	var cells := PackedVector3Array()
	for dx in range(-distance, distance + 1):
		cells.append(Vector3(centre + Vector3i(dx, 0, distance)))
	ctx.occupancy.write_slot(201, cells)


## Runs the chain and returns the code, so the assertions read as one line.
func _validate(ctx: BuildContext, cand: PlacementCandidate) -> int:
	return int(PlacementValidator.validate(ctx, cand))


## Counts EventBus emissions. A distinct receiver object per probe because two
## Callables bound over the same object and method compare equal, so binding an
## index cannot tell two handlers apart.
class _SignalProbe:
	extends RefCounted
	var count: int = 0
	var last_assembly: int = -1
	var last_slot: int = -1

	func on_part(assembly_id: int, slot: int) -> void:
		count += 1
		last_assembly = assembly_id
		last_slot = slot
