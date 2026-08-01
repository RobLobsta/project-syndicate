class_name PlacementValidator
extends RefCounted
## The ordered placement safety chain of
## [code]docs/GRID_SNAPPING_LOGIC.md[/code] §7, plus commit and removal (§9).
##
## [b]Every[/b] path into the lattice comes through here: the garage, the
## auto-assembler, blueprint loading, and the server's re-validation of a
## blueprint a client sent (CLAUDE.md §10 rule 8, Architectural Invariant I-8).
## A second implementation — even a "quick check" for the ghost preview — is how
## a client-only legal placement becomes a server desync.
##
## The chain is short-circuiting and ordered cheapest-first, so the common
## rejection costs a handful of integer comparisons. Architectural Invariant
## I-6: every check but the last is integer arithmetic over the lattice. The
## single physics query runs last, after every integer check has passed, and may
## only [i]reject[/i] — it can never accept a placement the integers refused.

enum Reject {
	NONE = 0,
	OUT_OF_BOUNDS,
	CELL_OCCUPIED,
	NO_MATING_NODE,
	POLARITY_MISMATCH,
	CLASS_NOT_ACCEPTED,
	MOUNT_BUDGET_EXCEEDED,
	POWER_BUDGET_EXCEEDED,
	CLASS_LIMIT_EXCEEDED,
	MOTIVE_GROUND_BLOCKED,
	EFFECTOR_ARC_BLOCKED,
	COLLIDER_INTERPENETRATION,
	LOAD_CAPACITY_EXCEEDED,
	DUPLICATE_CORE,
}

## Effector arc sampling, per §7.6.
const ARC_SAMPLE_STEP_DEG: float = 15.0
const ARC_TRACE_LENGTH_CELLS: int = 24
## Above this blocked fraction the arc is unusable. A partially obstructed
## effector is a legitimate trade-off — a turret tucked behind a Structural
## Component has cover and a narrow arc — whereas a fully buried one is always a
## mistake. The garage surfaces the free-arc percentage so the trade is explicit.
const ARC_BLOCKED_REJECT_RATIO: float = 0.6

## Negative so that intended face contact is not reported as penetration, per
## §7.7. Every part in an Assembly touches its neighbours by construction.
const INTERPENETRATION_MARGIN_M: float = -0.008

## Localisation keys for each rejection, indexed by [enum Reject]. CLAUDE.md §10
## rule 7: never a literal user-facing string.
const REJECT_KEYS: Array[StringName] = [
	&"build.reject.none",
	&"build.reject.out_of_bounds",
	&"build.reject.cell_occupied",
	&"build.reject.no_mating_node",
	&"build.reject.polarity_mismatch",
	&"build.reject.class_not_accepted",
	&"build.reject.mount_budget_exceeded",
	&"build.reject.power_budget_exceeded",
	&"build.reject.class_limit_exceeded",
	&"build.reject.motive_ground_blocked",
	&"build.reject.effector_arc_blocked",
	&"build.reject.collider_interpenetration",
	&"build.reject.load_capacity_exceeded",
	&"build.reject.duplicate_core",
]

## Downward face in the part's own frame, rotated per candidate by §7.5.
const _LOCAL_DOWN: Vector3i = Vector3i(0, -1, 0)
## Muzzle-forward axis in the effector's own frame. +Z, matching the muzzle
## offsets authored in [member EffectorModuleProfile.muzzle_offsets_m].
const _LOCAL_FORWARD: Vector3 = Vector3(0.0, 0.0, 1.0)


## §7.3 states the mating matrix is symmetric and that the validator asserts it
## at startup. It is asserted here rather than only in the polarity unit test so
## that a build running the validator has checked its own premise.
static func _static_init() -> void:
	var count := PartEnums.ATTACHMENT_POLARITY_COUNT
	for a in count:
		for b in count:
			assert(
				(
					AttachmentNodeDef.polarity_compatible(a, b)
					== AttachmentNodeDef.polarity_compatible(b, a)
				),
				"polarity matrix is asymmetric at (%d, %d)" % [a, b]
			)


## Runs the full chain against [param cand], returning the first rejection.
##
## [b]Mutates the candidate.[/b] A clean run leaves [member
## PlacementCandidate.mates], [member PlacementCandidate.parent_slot], and
## [member PlacementCandidate.soft_reject] filled — deciding them needs the
## lattice, and re-deriving them at commit would be a second implementation of
## the mating rule. A rejection leaves them cleared.
static func validate(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
	cand.mates = []
	cand.parent_slot = SyndicateConstants.INVALID_SLOT
	cand.soft_reject = Reject.NONE

	var r := _check_bounds(ctx, cand)
	if r != Reject.NONE:
		return r
	r = _check_occupancy(ctx, cand)
	if r != Reject.NONE:
		return r
	r = _check_mating(ctx, cand)
	if r != Reject.NONE:
		return r
	r = _check_class_limits(ctx, cand)
	if r != Reject.NONE:
		return r
	r = _check_budgets(ctx, cand)
	if r != Reject.NONE:
		return r
	r = _check_motive_clearance(ctx, cand)
	if r != Reject.NONE:
		return r
	r = _check_effector_arc(ctx, cand)
	if r != Reject.NONE:
		return r
	r = _check_collider_interpenetration(ctx, cand)
	if r != Reject.NONE:
		return r
	r = _check_structural_load(ctx, cand)
	if r != Reject.NONE:
		return r
	return Reject.NONE


## Localisation key naming [param reject], for the ghost inspector strip of §8.
static func reject_key(reject: Reject) -> StringName:
	var i := int(reject)
	if i < 0 or i >= REJECT_KEYS.size():
		return &"build.reject.none"
	return REJECT_KEYS[i]


## Commits a validated placement and returns its slot, per §9.1.
##
## [signal EventBusService.part_attached] is what wakes the mass solver, the
## fusion rebuild, and the UI stat panel. Nothing polls (Architectural Invariant
## I-4), so this function spawns no meshes: the presentation layer reacts to the
## signal.
static func commit(ctx: BuildContext, cand: PlacementCandidate) -> int:
	assert(validate(ctx, cand) == Reject.NONE, "commit of a placement that does not validate")

	var slot := ctx.allocate_slot()
	if slot == SyndicateConstants.INVALID_SLOT:
		push_error(
			(
				"PlacementValidator: assembly %d is full at %d parts; '%s' not committed"
				% [ctx.assembly_id, BuildContext.MAX, cand.definition.part_key]
			)
		)
		return SyndicateConstants.INVALID_SLOT

	var is_core := cand.definition.part_class == PartEnums.PartClass.CORE_MODULE
	assert(
		is_core == (slot == SyndicateConstants.CORE_SLOT),
		"Architectural Invariant I-2: slot 0 is the Core Module and nothing else"
	)

	var st := PartInstanceState.new()
	st.slot = slot
	st.part_def_id = cand.definition.runtime_id
	st.origin_cell = cand.origin_cell
	st.orientation_index = cand.orientation_index
	st.parent_slot = cand.parent_slot
	st.integrity = cand.definition.integrity_max
	st.integrity_band = PartEnums.IntegrityBand.NOMINAL
	# Sandbox mode admits an over-capacity joint and marks it. The Chassis Graph
	# reads the flag and fails that joint earlier under combat stress, so the
	# trade the player made in the garage is the one they get in the match.
	st.set_flag(PartFlags.FLAG_STRAINED, cand.soft_reject == Reject.LOAD_CAPACITY_EXCEEDED)

	ctx.states[slot] = st
	ctx.occupancy.write_slot(slot, cand.cells)
	ctx.graph.attach(slot, cand.parent_slot, cand.mates, cand.definition.mass_kg)
	ctx.budgets.add(cand.definition)
	ctx.spawn_proxy(slot, cand)

	EventBus.part_attached.emit(ctx.assembly_id, slot)
	return slot


## Removes [param slot], re-parenting what it was holding up where possible, per
## §9.2.
##
## Returns the slots that could not be re-parented and were removed with it. The
## garage shows that list in a confirmation prompt before calling this; it is
## returned rather than acted on so that the decision stays with the caller.
static func remove(ctx: BuildContext, slot: int) -> PackedByteArray:
	var cascaded := PackedByteArray()
	if ctx.state(slot) == null:
		push_error("PlacementValidator: removal of empty slot %d" % slot)
		return cascaded

	# Breadth-first over the parts that lose their support. Each iteration
	# releases exactly one slot, so the loop is bounded by the Assembly size;
	# only the parts that actually fail to find a new parent are ever visited.
	var pending := PackedByteArray()
	pending.append(slot)
	while not pending.is_empty():
		var dying := int(pending[0])
		pending.remove_at(0)

		# Orphan first, release second: the alternate-parent search below must
		# not see the dying part's cells, and ChassisGraph.detach requires a
		# childless slot.
		var orphans := ctx.graph.detach_orphaning_children(dying)
		_release(ctx, dying)
		if dying != slot:
			cascaded.append(dying)

		# Ascending by construction, so an orphan that could attach to either of
		# two survivors always picks the same one (Architectural Invariant I-9).
		for o in orphans:
			var orphan := int(o)
			var alt := _find_alternate_parent(ctx, orphan)
			if alt == SyndicateConstants.INVALID_SLOT:
				pending.append(orphan)
			else:
				ctx.graph.reparent(orphan, alt)
				ctx.states[orphan].parent_slot = alt

	EventBus.part_removed.emit(ctx.assembly_id, slot)
	return cascaded


## ===== THE CHAIN =======================================================


## §7.1. O(V) integer comparisons over the part's cells, typically 16–100.
static func _check_bounds(_ctx: BuildContext, cand: PlacementCandidate) -> Reject:
	return Reject.NONE if FootprintSolver.all_in_bounds(cand.cells) else Reject.OUT_OF_BOUNDS


## §7.2. The overlap test in its entirety — one array read per cell. There is no
## broadphase, no AABB tree, and no physics query, because the lattice [i]is[/i]
## the broadphase (Architectural Invariant I-6).
static func _check_occupancy(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
	for c in cand.cells:
		if not ctx.occupancy.is_free(Vector3i(c)):
			return Reject.CELL_OCCUPIED
	return Reject.NONE


## §7.3. A placement must produce at least one valid attachment pair.
##
## Fills [member PlacementCandidate.mates] with every accepted pair and picks
## the primary parent through [MateSelector].
##
## The first part in an empty lattice is the exception: it has nothing to mate
## with and must be the Core Module, which is the graph root and has no
## attachment pair by Architectural Invariant I-2 / §12 invariant 5. Requiring a
## mate of it would make an Assembly impossible to start.
static func _check_mating(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
	if ctx.is_empty():
		if cand.definition.part_class == PartEnums.PartClass.CORE_MODULE:
			return Reject.NONE
		return Reject.NO_MATING_NODE

	# Resolved nodes of each neighbouring slot, built once per slot rather than
	# once per candidate node: a solid part exposes one node per cell face, so
	# re-resolving per node would be quadratic in the neighbour's size.
	var neighbour_nodes: Dictionary = {}
	var accepted: Dictionary = {}  # other_slot -> MateRecord
	# The most-progressed failure seen, so the ghost names the real obstacle
	# rather than always saying "nothing to attach to".
	var best_failure := Reject.NO_MATING_NODE

	for own in cand.nodes:
		var target := own.mating_cell()
		var other_slot := ctx.occupancy.slot_at(target)
		if other_slot == SyndicateConstants.INVALID_SLOT:
			continue

		var others: Array[ResolvedNode] = neighbour_nodes.get(other_slot, [] as Array[ResolvedNode])
		if others.is_empty():
			others = _resolve_slot_nodes(ctx, other_slot)
			neighbour_nodes[other_slot] = others

		for other in others:
			if not own.is_face_paired(other):
				continue
			if not own.source.accepts_polarity(other.source.polarity):
				best_failure = _worse(best_failure, Reject.POLARITY_MISMATCH)
				continue
			var other_def := ctx.definition_at(other_slot)
			if (
				not own.source.accepts_class(int(other_def.part_class))
				or not other.source.accepts_class(int(cand.definition.part_class))
			):
				best_failure = _worse(best_failure, Reject.CLASS_NOT_ACCEPTED)
				continue
			# One physical joint per neighbouring part, even when several faces
			# meet: the strongest pair wins so a wide contact is rated by its
			# best node rather than by whichever face was scanned first.
			var rec := MateRecord.create(other_slot, own, other)
			var prev: MateRecord = accepted.get(other_slot, null)
			if prev == null or rec.joint_strength_n > prev.joint_strength_n:
				accepted[other_slot] = rec
			break

	if accepted.is_empty():
		return best_failure

	# Ascending by mated slot, so the mate list — and therefore the support edge
	# order in the Chassis Graph — never depends on node scan order (I-9).
	var slots: Array = accepted.keys()
	slots.sort()
	var mates: Array[MateRecord] = []
	for s: int in slots:
		mates.append(accepted[s])
	cand.mates = mates
	cand.parent_slot = MateSelector.choose_primary_slot(mates, ctx.graph)
	return Reject.NONE


## §7.4, class half. Exactly one Core Module per Assembly, and the per-class
## ceilings of [SyndicateConstants].
static func _check_class_limits(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
	var cls := cand.definition.part_class
	if cls == PartEnums.PartClass.CORE_MODULE:
		if ctx.budgets.count_of_class(int(PartEnums.PartClass.CORE_MODULE)) > 0:
			return Reject.DUPLICATE_CORE
		return Reject.NONE

	if cls == PartEnums.PartClass.EFFECTOR_MODULE:
		if (
			ctx.budgets.count_of_class(int(cls))
			>= SyndicateConstants.MAX_EFFECTORS_PER_ASSEMBLY
		):
			return Reject.CLASS_LIMIT_EXCEEDED
	elif cls == PartEnums.PartClass.MOTIVE_ASSEMBLY:
		if ctx.budgets.count_of_class(int(cls)) >= SyndicateConstants.MAX_MOTIVE_PER_ASSEMBLY:
			return Reject.CLASS_LIMIT_EXCEEDED
	return Reject.NONE


## §7.4, budget half. O(1) against totals the ledger maintains incrementally.
##
## The Core Module is exempt from its own mount budget: it is the thing offering
## the mounts, and charging it against itself would make an Assembly consisting
## of one Core Module illegal.
static func _check_budgets(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
	var def := cand.definition
	if def.part_class == PartEnums.PartClass.CORE_MODULE:
		return Reject.NONE

	if ctx.budgets.mount_used + def.mount_weight > ctx.budgets.mount_budget():
		return Reject.MOUNT_BUDGET_EXCEEDED

	var draw := ctx.budgets.power_draw_pu + def.power_draw_pu
	var available := ctx.budgets.power_available_pu() + def.power_supply_pu
	if draw > available and not is_equal_approx(draw, available):
		return Reject.POWER_BUDGET_EXCEEDED
	return Reject.NONE


## §7.5. A Motive Assembly must have unobstructed vertical travel over its full
## suspension range, or the suspension resolves into the Assembly's own
## colliders at runtime.
##
## Worth doing at build time because a blocked suspension is invisible in the
## garage and produces violent jitter in a match — catching it at placement
## eliminates an entire class of runtime physics instability.
static func _check_motive_clearance(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
	var def := cand.definition
	if def.part_class != PartEnums.PartClass.MOTIVE_ASSEMBLY:
		return Reject.NONE
	var mp := def.motive_profile
	if mp == null:
		return Reject.NONE

	var travel_cells := int(
		ceil(
			(
				(mp.suspension_rest_length_m + mp.suspension_travel_limit_m)
				/ SyndicateConstants.LATTICE_UNIT_M
			)
		)
	)
	var down := OrientationTable.rotate_face(cand.orientation_index, _LOCAL_DOWN)
	for c in cand.cells:
		var base := Vector3i(c)
		for step in range(1, travel_cells + 1):
			var probe := base + down * step
			# Leaving the lattice is clear air, not an obstruction: the travel
			# envelope of a Motive Assembly at the lattice floor extends below
			# the build volume by design.
			if not LatticeMath.in_bounds(probe):
				break
			if not ctx.occupancy.is_free(probe):
				return Reject.MOTIVE_GROUND_BLOCKED
	return Reject.NONE


## §7.6. A newly placed Effector Module must be able to traverse its declared
## yaw range without its muzzle line intersecting the Assembly's own occupancy.
## Sampled at fixed increments rather than swept continuously.
static func _check_effector_arc(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
	var def := cand.definition
	if def.part_class != PartEnums.PartClass.EFFECTOR_MODULE:
		return Reject.NONE
	var ep := def.effector_profile
	if ep == null or ep.muzzle_offsets_m.is_empty():
		return Reject.NONE

	var basis := OrientationTable.basis_for(cand.orientation_index)
	var muzzle_local := ep.muzzle_offsets_m[0]
	var muzzle_cell_f := (
		Vector3(cand.origin_cell)
		+ (basis * muzzle_local) / SyndicateConstants.LATTICE_UNIT_M
	)

	var blocked := 0
	var samples := 0
	var yaw := ep.yaw_limit_deg.x
	while yaw <= ep.yaw_limit_deg.y:
		samples += 1
		var dir := basis * _LOCAL_FORWARD.rotated(Vector3.UP, deg_to_rad(yaw))
		if _dda_blocked(ctx, muzzle_cell_f, dir, cand.cells):
			blocked += 1
		yaw += ARC_SAMPLE_STEP_DEG

	if samples == 0:
		return Reject.NONE
	var ratio := float(blocked) / float(samples)
	return Reject.EFFECTOR_ARC_BLOCKED if ratio > ARC_BLOCKED_REJECT_RATIO else Reject.NONE


## §7.7. The only physics query in the chain, and it runs last.
##
## Lattice occupancy prevents cell overlap, but collider primitives may be
## oriented in 15° multiples and may therefore protrude slightly beyond their
## owning cells. Skipped in a context without a physics space — §12 invariant 1
## permits that because the query may only reject, never accept.
static func _check_collider_interpenetration(
	ctx: BuildContext, cand: PlacementCandidate
) -> Reject:
	if not ctx.has_physics():
		return Reject.NONE
	var profile := cand.definition.collider_profile
	if profile == null:
		return Reject.NONE
	var state := ctx.space_state()
	if state == null:
		return Reject.NONE

	var world := cand.local_transform()
	for prim in profile.primitives:
		var rid := ctx.shape_cache.rid_for(prim)
		if not rid.is_valid():
			continue
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape_rid = rid
		params.transform = world * prim.local_transform()
		params.margin = INTERPENETRATION_MARGIN_M
		params.collision_mask = CollisionLayers.MASK_BUILD_GHOST
		params.collide_with_bodies = true
		params.collide_with_areas = false
		if not state.intersect_shape(params, 1).is_empty():
			return Reject.COLLIDER_INTERPENETRATION
	return Reject.NONE


## §7.8. The mating parent's [member PartDefinition.load_capacity_kg] must not be
## exceeded by the mass of the subtree that would hang from it.
##
## A single comparison: the subtree mass is maintained incrementally by the
## Chassis Graph. Soft in Sandbox — the placement is admitted and flagged
## [constant PartFlags.FLAG_STRAINED] — and hard in Ranked.
static func _check_structural_load(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
	if cand.parent_slot == SyndicateConstants.INVALID_SLOT:
		return Reject.NONE
	var parent_def := ctx.definition_at(cand.parent_slot)
	if parent_def == null:
		return Reject.NONE

	var added := ctx.graph.subtree_mass[cand.parent_slot] + cand.definition.mass_kg
	if added <= parent_def.load_capacity_kg or is_equal_approx(
		added, parent_def.load_capacity_kg
	):
		return Reject.NONE
	if ctx.enforce_hard_limits:
		return Reject.LOAD_CAPACITY_EXCEEDED
	cand.soft_reject = Reject.LOAD_CAPACITY_EXCEEDED
	return Reject.NONE


## ===== PRIVATE =========================================================


## Amanatides–Woo voxel traversal from [param start] along [param dir], stopping
## at the first occupied cell that is not the candidate's own.
##
## Own cells are skipped rather than treated as clear-and-stop: an effector's
## muzzle begins inside the effector, and every trace would otherwise report
## blocked on its first step.
static func _dda_blocked(
	ctx: BuildContext, start: Vector3, dir: Vector3, own: PackedVector3Array
) -> bool:
	var cell := Vector3i(int(floorf(start.x)), int(floorf(start.y)), int(floorf(start.z)))
	var step := Vector3i(
		signi(int(signf(dir.x))), signi(int(signf(dir.y))), signi(int(signf(dir.z)))
	)
	var t_delta := Vector3(
		INF if is_zero_approx(dir.x) else absf(1.0 / dir.x),
		INF if is_zero_approx(dir.y) else absf(1.0 / dir.y),
		INF if is_zero_approx(dir.z) else absf(1.0 / dir.z)
	)
	var t_max := Vector3(
		_initial_t(start.x, dir.x), _initial_t(start.y, dir.y), _initial_t(start.z, dir.z)
	)

	for _i in ARC_TRACE_LENGTH_CELLS:
		if t_max.x < t_max.y and t_max.x < t_max.z:
			cell.x += step.x
			t_max.x += t_delta.x
		elif t_max.y < t_max.z:
			cell.y += step.y
			t_max.y += t_delta.y
		else:
			cell.z += step.z
			t_max.z += t_delta.z
		# Leaving the lattice means the trace escaped the Assembly: clear.
		if not LatticeMath.in_bounds(cell):
			return false
		if own.has(Vector3(cell)):
			continue
		if not ctx.occupancy.is_free(cell):
			return true
	return false


## Distance along the ray to the first cell boundary crossing on one axis, in
## units of [param dir]'s length per cell.
static func _initial_t(coord: float, dir_component: float) -> float:
	if is_zero_approx(dir_component):
		return INF
	var cell := floorf(coord)
	var to_boundary := (cell + 1.0 - coord) if dir_component > 0.0 else (coord - cell)
	return to_boundary / absf(dir_component)


## Attachment nodes of a committed slot, resolved into the Assembly frame.
static func _resolve_slot_nodes(ctx: BuildContext, slot: int) -> Array[ResolvedNode]:
	var st := ctx.state(slot)
	var def := ctx.definition_at(slot)
	if st == null or def == null:
		return []
	return FootprintSolver.resolve_nodes(def, st.origin_cell, st.orientation_index)


## The more informative of two mating failures. A polarity mismatch means the
## player found the right face and the wrong part; "nothing to attach to" would
## send them looking in the wrong place.
static func _worse(current: Reject, candidate: Reject) -> Reject:
	return candidate if int(candidate) > int(current) else current


## Tears one slot out of the occupancy, the graph, the ledger, and the proxies.
##
## The slot must already be childless — [method ChassisGraph.detach_orphaning_children]
## is the caller's job, because what happens to the orphans is a garage/match
## decision this function cannot make.
static func _release(ctx: BuildContext, slot: int) -> void:
	var def := ctx.definition_at(slot)
	ctx.occupancy.erase_slot(slot)
	ctx.graph.detach(slot)
	if def != null:
		ctx.budgets.remove(def)
	ctx.despawn_proxy(slot)
	ctx.states[slot] = null


## An adjacent occupied slot that may take [param orphan] as a child.
##
## Prefers, in order: a node that bears load, then the highest joint strength,
## then the lowest slot index — the same ordering [MateSelector] uses, applied
## to the survivors. A candidate that is itself severed from the Core Module is
## refused: re-parenting onto a floating fragment would leave the graph claiming
## a connection the Assembly does not have.
static func _find_alternate_parent(ctx: BuildContext, orphan: int) -> int:
	var st := ctx.state(orphan)
	var def := ctx.definition_at(orphan)
	if st == null or def == null:
		return SyndicateConstants.INVALID_SLOT

	var cand := PlacementCandidate.new()
	cand.definition = def
	cand.origin_cell = st.origin_cell
	cand.orientation_index = st.orientation_index
	cand.resolve()

	var best := SyndicateConstants.INVALID_SLOT
	var best_rec: MateRecord = null
	for own in cand.nodes:
		var target := own.mating_cell()
		var other_slot := ctx.occupancy.slot_at(target)
		if other_slot == SyndicateConstants.INVALID_SLOT or other_slot == orphan:
			continue
		if not ctx.graph.is_alive(other_slot):
			continue
		# Would-be cycle: a part cannot be held up by something it holds up.
		if _is_in_subtree(ctx, other_slot, orphan):
			continue
		if not ctx.graph.is_connected_to_core(other_slot):
			continue

		for other in _resolve_slot_nodes(ctx, other_slot):
			if not own.is_face_paired(other):
				continue
			if not own.source.accepts_polarity(other.source.polarity):
				continue
			var other_def := ctx.definition_at(other_slot)
			if (
				not own.source.accepts_class(int(other_def.part_class))
				or not other.source.accepts_class(int(def.part_class))
			):
				continue
			var rec := MateRecord.create(other_slot, own, other)
			if best_rec == null or MateSelector.outranks(rec, best_rec, ctx.graph):
				best_rec = rec
				best = other_slot
			break
	return best


static func _is_in_subtree(ctx: BuildContext, slot: int, root: int) -> bool:
	return ctx.graph.subtree_slots(root).has(slot)
