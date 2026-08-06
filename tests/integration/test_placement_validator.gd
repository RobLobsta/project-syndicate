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
## Doc 01 §7.1's two family-locked chassis, and one Motive Assembly per family.
const STRIDER_KEY := &"core.ambulatory.strider.t3"
const LIFTER_KEY := &"core.rotary.lifter.t3"
const WHEEL_KEY := &"mot.wheeled.allroad.t2"
const LIMB_KEY := &"mot.limb.strider.t4"
const ROTOR_KEY := &"mot.rotor.coaxial_mid.t3"
const ARM_KEY := &"apx.arm.manipulator.t3"

## Each probe hung off its chassis's `-X` flank, at `z` 24 and at a height every
## chassis occupies.
##
## [b]The `x` is now per chassis, and that is the session-44 rebuild arriving
## here.[/b] The three chassis used to share a 6x4 section, so one probe cell was
## legal geometry on all of them and the chassis was provably the only thing
## differing between cases. Doc 01 §10.1 records why that stopped: seated at
## [constant CORE_ORIGIN] the command core spans `x` 20..27, the strider 21..26
## and the lifter 22..25, so there is no cell outboard of all three flanks.
##
## [b]A shared cell would now be worse than useless rather than merely stale.[/b]
## Two of the three cases would reject on `CELL_OCCUPIED` — the candidate inside a
## wider hull — and a `CELL_OCCUPIED` refusal reads from the outside exactly like
## the family rule working. So the probe is placed against each chassis's own
## flank, and the flank offsets below are the only thing that varies: the part,
## the orientation, the height and the `z` are identical across the three.
const FLANK_X_BY_CHASSIS: Array[int] = [18, 19, 20]
## Probe heights, one per motive part, chosen so each overlaps the `y` band of
## every chassis. They differ only because the three parts have different pivots:
## a disc grows upward from its pivot, a limb hangs downward from it, and a wheel
## straddles it.
const FLANK_WHEEL_Y: int = 6
const FLANK_LIMB_Y: int = 7
const FLANK_ROTOR_Y: int = 4
const FLANK_Z: int = 24
## The same probe for an Appendage: its shoulder carried onto `+X` so the arm
## mates through the chassis's `-X` flank and reaches outboard from there.
##
## [b]A flank mount rather than the forward-running one
## [constant CombatArena.MELEE_ARMS] uses, and the reason is the fixture rather
## than the pose.[/b] An arm running forward has to sit one cell ahead of its
## hull's `-Z` face, and the three chassis put that face at `z` 17, 19 and 10 —
## so no single candidate is legal geometry on all three, and a case that
## rejected on `CELL_OCCUPIED` would look exactly like the family rule working.
## Under [constant ARM_ORIENTATION] the shoulder is the arm's `+X` end, so its
## origin sits one cell outboard of the flank on every chassis.
const FLANK_ARM_Y: int = 6
const ARM_ORIENTATION: int = 8

## The Core Module seated at the lattice origin. Occupies x 20..27, y 4..7,
## z 17..30; its whole top face at y = 7 is DECK polarity.
const CORE_ORIGIN := Vector3i(24, 4, 24)
## Directly on the Core Module's deck. The panel occupies x 22..25, z 22..25.
const DECK_ORIGIN := Vector3i(24, 8, 24)
## One cell out from the Core Module's +X face, with clear air below it. The
## flank is at x = 27 since the hull went to eight cells wide.
const BESIDE_ORIGIN := Vector3i(28, 5, 24)
## Beside the stack of [method _stacked_context] and clear of the Core Module
## entirely. The hull spans x 20..27 and reaches y = 7, so a panel one cell out
## from the stack at deck height would rest on the roof and take the Core Module
## as its parent — which is a different joint from the one §7.8 is being asked
## about here. One cell higher, it can only mate with the stack.
##
## The `x` follows the **stack**, which is on the lattice centreline and did not
## move when the hull went to eight cells wide. It was taken out to 29 with the
## flank during the session-44 rebuild and stopped reaching the stack at all.
const LATERAL_ORIGIN := Vector3i(28, 9, 24)

## Published in doc 01 §10.2 and re-asserted here so a data change that breaks
## the arithmetic below names itself rather than failing as a wrong reject code.
const PANEL_MASS := 100.0
const PANEL_LOAD_CAPACITY := 1560.0
const CORE_MOUNT_BUDGET := 28
const CORE_POWER_CAPACITY := 520.0

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
	var cand := PlacementCandidate.create(_core, Vector3i(24, 14, 24), 0)
	# Seated so its own cells clear the committed core but its lower face still
	# mates, isolating DUPLICATE_CORE from CELL_OCCUPIED.
	cand.origin_cell = Vector3i(24, 8, 24)
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
	# The lateral panel mates with slot 2, so the joint under test carries the
	# fourteen panels above slot 2 plus the candidate: 14 x 100 kg = 1400 kg, and
	# the candidate brings it to 1500 against the panel's 1560 kg capacity.
	var ctx := _stacked_context(15)
	ctx.enforce_hard_limits = true
	check_approx(
		ctx.graph.subtree_mass[2], 14.0 * PANEL_MASS, "fixture: the stack masses what it should"
	)
	var under := PlacementCandidate.create(_panel, LATERAL_ORIGIN, 0)
	check_eq(
		_validate(ctx, under), PlacementValidator.Reject.NONE,
		"1500 kg on a 1560 kg joint is within capacity"
	)


func test_load_capacity_exceeded_under_hard_limits() -> void:
	var ctx := _stacked_context(16)
	ctx.enforce_hard_limits = true
	check_approx(ctx.graph.subtree_mass[2], 15.0 * PANEL_MASS, "fixture: 1500 kg already hanging")
	var over := PlacementCandidate.create(_panel, LATERAL_ORIGIN, 0)
	check_eq(
		_validate(ctx, over), PlacementValidator.Reject.LOAD_CAPACITY_EXCEEDED,
		"1600 kg on a 1560 kg joint is refused in Ranked mode"
	)


func test_load_capacity_is_soft_in_sandbox() -> void:
	var ctx := _stacked_context(16)
	ctx.enforce_hard_limits = false
	var over := PlacementCandidate.create(_panel, LATERAL_ORIGIN, 0)
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


## One emission per part that left, not one per call.
##
## Every listener but the mass solver is keyed on the slot — the garage preview
## holds a mesh per slot and drops it here — so a cascade announced once leaves
## the rest of its meshes standing in the air over the hole they came out of.
## That is what a player saw: take a station off the shipped starter and the
## contact it was carrying stays hanging where it was.
func test_a_cascade_announces_every_part_it_took() -> void:
	var ctx := _reparent_fixture()
	var seen := _SignalProbe.new()
	EventBus.part_removed.connect(seen.on_part)
	var cascaded := PlacementValidator.remove(ctx, 1)
	EventBus.part_removed.disconnect(seen.on_part)

	check_eq(cascaded, PackedByteArray([2]), "the fixture cascades one part")
	check_eq(seen.count, 2, "both the part named and the one that went with it")
	check_eq(seen.slots, PackedByteArray([1, 2]), "the named part first, then the cascade")
	for s in seen.slots:
		check_null(ctx.state(int(s)), "slot %d is gone by the time it is announced" % int(s))


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


## ===== §7.4 CHASSIS FAMILY =============================================


## Doc 02 §7.4 and doc 01 §7.1: a Motive Assembly's locomotion family must be one
## the committed Core Module declares.
##
## Asserted as the whole three-by-three matrix rather than as one refusal,
## because the two halves fail differently and both are shipping defects. A mask
## that refuses too much leaves a chassis nothing can move; a mask that refuses
## too little is the state this check was written to end, and it passes every
## test that only looks for a rejection.
##
## All three probes hang off the Core Module's `-X` flank at a height every
## chassis shares, so the only thing that differs between the nine cases is the
## part at slot 0 — which is what makes a rejection attributable to the chassis
## rather than to the geometry.
func test_a_chassis_takes_its_own_locomotion_family_and_no_other() -> void:
	var chassis: Array[StringName] = [CORE_KEY, STRIDER_KEY, LIFTER_KEY]
	var motive: Array[StringName] = [WHEEL_KEY, LIMB_KEY, ROTOR_KEY]
	var probe_y: Array[int] = [FLANK_WHEEL_Y, FLANK_LIMB_Y, FLANK_ROTOR_Y]

	for c: int in chassis.size():
		var core := PartRegistry.definition_by_key(chassis[c])
		if not check_not_null(core, "%s is registered" % chassis[c]):
			continue
		for m: int in motive.size():
			var part := PartRegistry.definition_by_key(motive[m])
			if not check_not_null(part, "%s is registered" % motive[m]):
				continue
			var ctx := _new_context()
			PlacementValidator.commit(ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))
			var origin := Vector3i(FLANK_X_BY_CHASSIS[c], probe_y[m], FLANK_Z)
			var r := PlacementValidator.validate(
				ctx, PlacementCandidate.create(part, origin, 0)
			)
			var expected := (
				PlacementValidator.Reject.NONE
				if c == m
				else PlacementValidator.Reject.MOTIVE_FAMILY_MISMATCH
			)
			check_eq(r, expected, "%s on %s" % [motive[m], chassis[c]])


## The refusal must arrive before the budgets, not instead of them.
##
## An unreachable check reads exactly like a working one from the outside: if
## [method _check_budgets] rejected first, every case above would still pass on a
## chassis whose mounts happened to be full, and the family rule would be dead
## code nobody could see. The strider offers thirty-four mounts and a rotor disc
## costs four, so the only reason this candidate can be refused is its family.
func test_the_family_refusal_is_not_a_budget_refusal_in_disguise() -> void:
	var core := PartRegistry.definition_by_key(STRIDER_KEY)
	var rotor := PartRegistry.definition_by_key(ROTOR_KEY)
	if core == null or rotor == null:
		fail("fixture: the strider chassis and the rotor disc must both be registered")
		return
	var ctx := _new_context()
	PlacementValidator.commit(ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))
	check_true(
		ctx.budgets.mount_used + rotor.mount_weight <= ctx.budgets.mount_budget(),
		"the mount budget has room for the disc"
	)
	check_eq(
		PlacementValidator.validate(
			ctx,
			PlacementCandidate.create(
				rotor, Vector3i(FLANK_X_BY_CHASSIS[1], FLANK_ROTOR_Y, FLANK_Z), 0
			)
		),
		PlacementValidator.Reject.MOTIVE_FAMILY_MISMATCH,
		"and it is refused on its family anyway"
	)


## A lattice with no Core Module refuses nothing on family grounds.
##
## Not reachable through the garage, the auto-assembler or blueprint loading —
## §7.3 admits only a Core Module into an empty lattice — but reachable from a
## fixture, and an absent chassis declaring nothing is the same answer
## `mount_budget()` already gives. The rejection here is the mating one, which is
## the check that owns the case.
func test_a_lattice_with_no_chassis_refuses_on_mating_rather_than_on_family() -> void:
	var rotor := PartRegistry.definition_by_key(ROTOR_KEY)
	if not check_not_null(rotor, "the rotor disc is registered"):
		return
	check_eq(
		PlacementValidator.validate(
			_new_context(),
			PlacementCandidate.create(
				rotor, Vector3i(FLANK_X_BY_CHASSIS[2], FLANK_ROTOR_Y, FLANK_Z), 0
			)
		),
		PlacementValidator.Reject.NO_MATING_NODE,
		"an empty lattice takes a Core Module first and says so"
	)


## Doc 01 §7.1's appendage half: an arm belongs to a walking Assembly and to no
## other, and the rule is asserted across every shipped chassis in both
## directions.
##
## Both directions, because a rule with one is not a rule. A check that refused
## everything would pass an assertion that only tried the wheeled hull, and a check
## that refused nothing would pass one that only tried the strider.
func test_an_appendage_takes_an_ambulatory_chassis_and_no_other() -> void:
	var arm := PartRegistry.definition_by_key(ARM_KEY)
	if not check_not_null(arm, "the Appendage is registered"):
		return
	var chassis: Array[StringName] = [CORE_KEY, STRIDER_KEY, LIFTER_KEY]
	for c: int in chassis.size():
		var key := chassis[c]
		var core := PartRegistry.definition_by_key(key)
		if not check_not_null(core, "%s is registered" % key):
			continue
		var ctx := _new_context()
		PlacementValidator.commit(ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))
		var expected := (
			PlacementValidator.Reject.NONE
			if key == STRIDER_KEY
			else PlacementValidator.Reject.APPENDAGE_CHASSIS_MISMATCH
		)
		var origin := Vector3i(FLANK_X_BY_CHASSIS[c] + 1, FLANK_ARM_Y, FLANK_Z)
		check_eq(
			PlacementValidator.validate(
				ctx, PlacementCandidate.create(arm, origin, ARM_ORIENTATION)
			),
			expected,
			"an Appendage on %s" % key
		)


## The refusal must arrive on the chassis and not on the mounts.
##
## Same shape as the motive version above and for the same reason: an unreachable
## check reads exactly like a working one from the outside. The command core
## offers twenty-eight mounts and an arm costs far fewer, so the only thing that
## can refuse this candidate is the family.
func test_the_appendage_refusal_is_not_a_budget_refusal_in_disguise() -> void:
	var core := PartRegistry.definition_by_key(CORE_KEY)
	var arm := PartRegistry.definition_by_key(ARM_KEY)
	if core == null or arm == null:
		fail("fixture: the command chassis and the Appendage must both be registered")
		return
	var ctx := _new_context()
	PlacementValidator.commit(ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))
	check_true(
		ctx.budgets.mount_used + arm.mount_weight <= ctx.budgets.mount_budget(),
		"the mount budget has room for the arm"
	)
	check_eq(
		PlacementValidator.validate(
			ctx,
			PlacementCandidate.create(
				arm,
				Vector3i(FLANK_X_BY_CHASSIS[0] + 1, FLANK_ARM_Y, FLANK_Z),
				ARM_ORIENTATION
			)
		),
		PlacementValidator.Reject.APPENDAGE_CHASSIS_MISMATCH,
		"and it is refused on its chassis anyway"
	)


## §7.3's Prime Mover mask, and the rule that makes four sets of physics tuning
## independent of each other.
##
## Asserted from both sides on one chassis, because a rule that only ever refuses
## is indistinguishable from a rule that always refuses. The road hull takes the
## wheeled family's flat slab and refuses the tank's turbine, the mech's block and
## the rotorcraft's turboshaft — none of which is a budget refusal: all four rows
## carry the identical section, mass and mount weight, so the family mask is the
## only thing that can separate them.
func test_a_prime_mover_is_refused_by_a_chassis_it_does_not_drive() -> void:
	var core := PartRegistry.definition_by_key(CORE_KEY)
	var wheeled := PartRegistry.definition_by_key(&"pmv.combustion.flat.t2")
	if core == null or wheeled == null:
		fail("fixture: the command chassis and the wheeled mover must both be registered")
		return
	var ctx := _new_context()
	PlacementValidator.commit(ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))

	var seat := Vector3i(CORE_ORIGIN.x, CORE_ORIGIN.y, CORE_ORIGIN.z + 10)
	check_eq(
		PlacementValidator.validate(ctx, PlacementCandidate.create(wheeled, seat, 0)),
		PlacementValidator.Reject.NONE,
		"a wheeled chassis takes the wheeled family's mover"
	)
	for key: StringName in [
		&"pmv.turbine.tracked.t3", &"pmv.combustion.strider.t3", &"pmv.turboshaft.rotary.t3"
	]:
		var foreign := PartRegistry.definition_by_key(key)
		if foreign == null:
			fail("fixture: %s must be registered" % key)
			continue
		check_eq(
			foreign.mount_weight,
			wheeled.mount_weight,
			"%s costs the same mounts as the wheeled mover, so this is not a budget refusal" % key
		)
		check_eq(
			PlacementValidator.validate(ctx, PlacementCandidate.create(foreign, seat, 0)),
			PlacementValidator.Reject.PRIME_MOVER_CHASSIS_MISMATCH,
			"and refuses %s, which drives another family" % key
		)


## A mover that declares nothing drives everything, which is what keeps the field
## from narrowing a `.tres` nobody has authored for it. The default is
## [constant PartEnums.CHASSIS_ANY] rather than a single family precisely so that
## adding the mask to [PrimeMoverProfile] could not silently refuse a part.
func test_a_prime_mover_that_declares_no_family_is_admitted_anywhere() -> void:
	var profile := PrimeMoverProfile.new()
	for mode: int in PartEnums.LOCOMOTION_MODE_COUNT:
		check_true(
			profile.drives(mode),
			"an unauthored Prime Mover drives locomotion family %d" % mode
		)


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
	var cand := PlacementCandidate.create(_panel, Vector3i(24, 9, 24), 0)
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
		var cand := PlacementCandidate.create(_panel, Vector3i(24, 8 + i, 24), 0)
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
		Vector3i(24, 8, 24),  # 1: on the deck
		Vector3i(24, 9, 24),  # 2: above it
		Vector3i(24, 9, 28),  # 3: beside 2, touching nothing else yet
		Vector3i(24, 8, 28),  # 4: below 3, bridging to the core and to 1
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
	## Every slot the signal named, in the order it named them. A closure
	## capturing a local would capture a copy (LEARNED_FACTS.md §1 fact 68).
	var slots: PackedByteArray = PackedByteArray()

	func on_part(assembly_id: int, slot: int) -> void:
		count += 1
		last_assembly = assembly_id
		last_slot = slot
		slots.append(slot)
