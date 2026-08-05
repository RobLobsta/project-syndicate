extends TestCase
## [AssemblyRuntime] — the node structure of doc 05 §2, the collision geometry it
## builds from authored primitives, and the shape-index to slot map every damage
## query reads (doc 08 §5.4).
##
## Architectural Invariant I-1 is what this file exists to defend, and its
## failure mode is silence. A shape that never registers, an index that maps to
## the wrong slot, a collider parented under the visual tree — none of these
## raise an error. They produce an Assembly that cannot be hit, or one where
## every shot lands on the Core Module, and both look like a balance problem
## until someone thinks to check the physics server.
##
## So the assertions here go to the server and to the map rather than to the
## nodes that were meant to populate them. Counting [CollisionShape3D] children
## would have passed against the [code]ColliderRoot[/code] the document
## originally specified, under which not one of them was registered.

const CORE_KEY := &"core.command.compact.t2"
const PANEL_KEY := &"str.panel.medium.t2"

const CORE_ORIGIN := Vector3i(24, 4, 24)
const DECK_ORIGIN := Vector3i(24, 8, 24)

## Both shipped parts carry exactly one authored primitive; doc 01 §6.2 caps the
## count at three. Re-asserted below so a collider change names itself.
const CORE_PRIMITIVES := 1
const PANEL_PRIMITIVES := 1

var _core: PartDefinition = null
var _panel: PartDefinition = null
var _contexts: Array[BuildContext] = []
var _runtimes: Array[AssemblyRuntime] = []


func before_all() -> void:
	_core = PartRegistry.definition_by_key(CORE_KEY)
	_panel = PartRegistry.definition_by_key(PANEL_KEY)


func after_all() -> void:
	# A node left in the tree keeps its physics body alive and its interpolator
	# writing; a context dropped without disposal leaks a space that keeps
	# stepping for the life of the process.
	for runtime in _runtimes:
		runtime.free()
	_runtimes.clear()
	for ctx in _contexts:
		ctx.dispose()
	_contexts.clear()


func test_fixture_parts_carry_the_primitive_counts_below() -> void:
	check_eq(
		_core.collider_profile.primitives.size(), CORE_PRIMITIVES,
		"the Core Module's authored primitive count"
	)
	check_eq(
		_panel.collider_profile.primitives.size(), PANEL_PRIMITIVES,
		"the Structural Component's authored primitive count"
	)


## ===== §2 NODE STRUCTURE ===============================================


func test_the_runtime_builds_the_documented_tree() -> void:
	var runtime := _new_runtime()

	check_true(runtime.body is ChassisBodyRef, "the chassis body is a ChassisBodyRef")
	check_eq(runtime.body.name, &"ChassisBody", "named as §2 names it")
	check_eq(runtime.body.get_parent(), runtime, "the body hangs off the runtime")
	check_eq(
		runtime.motive_probes.get_parent(), runtime.body,
		"MotiveProbes is inside the body, where a probe's transform follows it"
	)
	check_eq(runtime.visual_root.get_parent(), runtime, "VisualRoot is a sibling of the body")
	check_eq(runtime.audio_root.get_parent(), runtime, "so is AudioRoot")


func test_the_visual_root_is_never_a_child_of_the_body() -> void:
	# §11 invariant 2. As a child its transform would be overwritten by the
	# physics server every tick and the interpolator would fight it; as a sibling
	# the interpolator's write is authoritative.
	var runtime := _new_runtime()
	var walk := runtime.visual_root.get_parent()
	while walk != null:
		check_false(walk is PhysicsBody3D, "no PhysicsBody3D above VisualRoot")
		walk = walk.get_parent()
	check_true(true, "the visual ancestry was walked")


func test_the_body_is_on_the_hull_layer_and_collides_with_the_world() -> void:
	var runtime := _new_runtime()
	check_eq(
		runtime.body.collision_layer, CollisionLayers.LAYER_ASSEMBLY_HULL,
		"the chassis body occupies the hull layer alone"
	)
	check_true(
		(runtime.body.collision_mask & CollisionLayers.LAYER_GROUND) != 0,
		"and collides with the ground"
	)
	check_true(
		(runtime.body.collision_mask & CollisionLayers.LAYER_BUILD_GHOST) == 0,
		"but never with the garage's build proxies"
	)


func test_the_assembly_id_lives_on_the_body() -> void:
	# A physics query hands back a ChassisBodyRef and nothing else, so the body
	# has to know which Assembly it is. Two copies of that id are two chances to
	# disagree about who just took a hit.
	var runtime := _new_runtime()
	runtime.assembly_id = 9
	check_eq(runtime.body.assembly_id, 9, "the body carries the id the runtime was given")
	check_eq(runtime.assembly_id, 9, "and reading it back goes to the same place")


## ===== COLLISION GEOMETRY ==============================================


func test_adopting_a_context_registers_every_primitive_with_the_server() -> void:
	var runtime := _adopted_runtime()
	var expected := CORE_PRIMITIVES + PANEL_PRIMITIVES

	check_eq(runtime.shape_count(), expected, "one CollisionShape3D per authored primitive")
	check_eq(
		PhysicsServer3D.body_get_shape_count(runtime.body.get_rid()), expected,
		"and the physics server holds every one of them"
	)


func test_shapes_are_direct_children_of_the_body() -> void:
	# The amendment to §2 in one assertion. An intervening Node3D leaves a
	# CollisionShape3D silently inert — no error, no shape on the body — and an
	# Assembly nothing can hit reads as a damage bug rather than a tree bug.
	var runtime := _adopted_runtime()
	var found := 0
	for child in runtime.body.get_children():
		if child is CollisionShape3D:
			found += 1
	check_eq(
		found, CORE_PRIMITIVES + PANEL_PRIMITIVES,
		"every shape hangs directly off the CollisionObject3D"
	)


func test_shape_transforms_compose_the_part_pose_onto_the_primitive_offset() -> void:
	var runtime := _adopted_runtime()
	var panel_shape := runtime.body.get_node(^"shape_s001_p0") as CollisionShape3D
	if not check_not_null(panel_shape, "the panel's primitive is named for its slot"):
		return
	var expected := (
		Transform3D(
			OrientationTable.basis_for(0), LatticeMath.cell_to_local(DECK_ORIGIN)
		)
		* _panel.collider_profile.primitives[0].local_transform()
	)
	check_true(
		panel_shape.transform.is_equal_approx(expected),
		"the shape sits where the part was placed, offset by the authored primitive"
	)


func test_a_rotated_part_rotates_its_primitive_offset_with_it() -> void:
	# At orientation 0 the composition order does not matter: both bases are the
	# identity, so the two transforms differ only in an addition that commutes.
	# Every shipped part sits that way today, which means the whole rule is
	# invisible until something is rotated — and by then the colliders of every
	# rotated part in the game have been in the wrong place for months.
	var runtime := _adopted_runtime()
	var pitch := _orientation_mapping_y_to(Vector3(0, 0, 1))
	if not check_ne(pitch, -1, "the orientation group contains a +Y to +Z rotation"):
		return

	var cell := Vector3i(30, 8, 30)
	var st := PartInstanceState.new()
	st.slot = 2
	st.part_def_id = _panel.runtime_id
	st.origin_cell = cell
	st.orientation_index = pitch
	st.integrity = _panel.integrity_max
	runtime.states[2] = st
	runtime.attach_part(2)

	var shape := runtime.body.get_node(^"shape_s002_p0") as CollisionShape3D
	if not check_not_null(shape, "the rotated part's primitive was built"):
		return
	var basis := OrientationTable.basis_for(pitch)
	var offset := _panel.collider_profile.primitives[0].local_offset_m
	var cell_centre := LatticeMath.cell_to_local(cell)
	check_true(
		shape.transform.origin.is_equal_approx(cell_centre + basis * offset),
		"the authored offset is rotated into the part's frame before it is added"
	)
	check_false(
		shape.transform.origin.is_equal_approx(cell_centre + offset),
		"rather than merely translated, which is what composing the other way gives"
	)
	check_true(shape.transform.basis.is_equal_approx(basis), "and the shape takes the rotation")


func test_every_shape_index_maps_back_to_the_slot_that_owns_it() -> void:
	var runtime := _adopted_runtime()
	check_eq(runtime.body.slot_for_shape_index(0), 0, "index 0 belongs to the Core Module")
	check_eq(runtime.body.slot_for_shape_index(1), 1, "index 1 belongs to the panel")
	check_eq(
		runtime.states[0].collider_shape_ids, PackedInt32Array([0]),
		"and the state records the indices it owns"
	)
	check_eq(runtime.states[1].collider_shape_ids, PackedInt32Array([1]), "for both parts")


func test_an_index_outside_the_map_is_invalid_and_not_the_core_module() -> void:
	# The document's version of §5.4 grows the map with a zero-filling resize,
	# and slot 0 is the Core Module — a real slot, and the one whose loss ends
	# the match. An unmapped index must not read as a hit on it.
	var runtime := _adopted_runtime()
	check_eq(
		runtime.body.slot_for_shape_index(64), SyndicateConstants.INVALID_SLOT,
		"an index past the end is invalid"
	)
	check_eq(
		runtime.body.slot_for_shape_index(-1), SyndicateConstants.INVALID_SLOT,
		"and so is a negative one"
	)
	var sparse := ChassisBodyRef.new()
	sparse.register_shape(3, 7)
	check_eq(sparse.slot_for_shape_index(0), SyndicateConstants.INVALID_SLOT, "a gap is invalid")
	check_eq(sparse.slot_for_shape_index(3), 7, "and the entry itself survives")
	sparse.free()


func test_releasing_a_part_disables_its_shapes_without_renumbering_the_rest() -> void:
	# Removing a shape renumbers every later index on the body, which would
	# repoint the whole map — one destroyed panel turning into mis-attributed
	# hits across the Assembly. Disabling keeps indices fixed for good.
	var runtime := _adopted_runtime()
	var before := PhysicsServer3D.body_get_shape_count(runtime.body.get_rid())
	runtime.release_part(0)

	check_eq(
		PhysicsServer3D.body_get_shape_count(runtime.body.get_rid()), before,
		"the server's shape list is the same length, so no index moved"
	)
	check_eq(runtime.shape_count(), before, "and so is the runtime's")
	check_eq(runtime.body.slot_for_shape_index(1), 1, "the panel's index still points at it")
	var core_shape := runtime.body.get_node_or_null(^"shape_s000_p0") as CollisionShape3D
	var panel_shape := runtime.body.get_node_or_null(^"shape_s001_p0") as CollisionShape3D
	if not check_not_null(core_shape, "the released part's shape is still on the body"):
		return
	if not check_not_null(panel_shape, "and so is its neighbour's"):
		return
	check_true(core_shape.disabled, "the released part's shape is out of the simulation")
	check_false(panel_shape.disabled, "and its neighbour is untouched")

	runtime.restore_part(0)
	check_false(core_shape.disabled, "repair puts it back")


func test_adoption_releases_the_contexts_build_proxies() -> void:
	# The proxies answer §7.7's interpenetration query while the player is
	# building. Once the real body holds the same primitives they are a second
	# set of colliders for the same Assembly, in a space nothing reads.
	var ctx := _context_with_core_and_panel()
	var runtime := _new_runtime()
	check_true(ctx.proxy_body(0).is_valid(), "the context had a proxy before adoption")
	runtime.adopt(ctx)
	check_false(ctx.proxy_body(0).is_valid(), "and none after it")
	check_false(ctx.proxy_body(1).is_valid(), "for every slot")


func test_adoption_takes_over_the_states_and_the_graph() -> void:
	var ctx := _context_with_core_and_panel()
	var runtime := _new_runtime()
	runtime.adopt(ctx)

	check_eq(runtime.assembly_id, ctx.assembly_id, "the runtime answers to the context's id")
	check_eq(runtime.graph, ctx.graph, "the Chassis Graph is carried across, not rebuilt")
	check_eq(runtime.states[0], ctx.states[0], "and so is every part's state")
	check_eq(
		runtime.definition_at(1).part_key, PANEL_KEY, "definitions resolve through the registry"
	)
	check_null(runtime.state(2), "an uncommitted slot is empty")
	check_null(runtime.state(-1), "and an out-of-range slot is not an error")


## ===== §11 INVARIANT 2 =================================================


func test_a_clean_visual_tree_reports_nothing() -> void:
	var runtime := _adopted_runtime()
	var decoration := Node3D.new()
	decoration.name = "part_s000"
	runtime.visual_root.add_child(decoration)
	check_eq(
		runtime.visual_decoupling_violations(), PackedStringArray(),
		"visual nodes that carry no collision are fine"
	)


func test_collision_under_the_visual_root_is_reported() -> void:
	var runtime := _adopted_runtime()
	var stray_body := StaticBody3D.new()
	stray_body.name = "StrayBody"
	runtime.visual_root.add_child(stray_body)
	var stray_shape := CollisionShape3D.new()
	stray_shape.name = "StrayShape"
	stray_shape.shape = BoxShape3D.new()
	runtime.visual_root.add_child(stray_shape)

	var violations := runtime.visual_decoupling_violations()
	check_eq(violations.size(), 2, "both offenders are named")
	check_true(
		"|".join(violations).contains("StrayBody"), "the physics body is reported"
	)
	check_true(
		"|".join(violations).contains("StrayShape"), "and so is the loose shape"
	)


func test_the_walk_reaches_nested_offenders() -> void:
	# A collider three levels down under a decorative pivot is exactly how this
	# invariant gets broken in practice, and a one-level check would miss it.
	var runtime := _adopted_runtime()
	var pivot := Node3D.new()
	runtime.visual_root.add_child(pivot)
	var inner := Node3D.new()
	pivot.add_child(inner)
	var buried := StaticBody3D.new()
	buried.name = "BuriedBody"
	inner.add_child(buried)

	var violations := runtime.visual_decoupling_violations()
	check_eq(violations.size(), 1, "the buried body is found")
	check_true("|".join(violations).contains("BuriedBody"), "and named")


## ===== §3.5 AND §10.2 ==================================================


func test_solved_mass_properties_reach_the_body() -> void:
	var runtime := _adopted_runtime()
	var mp := MassSolver.compute(runtime.states, runtime.graph)
	runtime.apply_mass_properties(mp)

	check_approx(
		runtime.body.mass, _core.mass_kg + _panel.mass_kg, "the body carries both parts"
	)
	check_eq(runtime.mass_properties, mp, "and the runtime keeps them for §6.4 to read")
	check_true(
		runtime.body.center_of_mass.is_equal_approx(mp.com_local),
		"the solved centre of mass is applied rather than derived from the shapes"
	)


func test_the_interpolator_is_wired_to_the_sibling_visual_root() -> void:
	var runtime := _adopted_runtime()
	if not check_not_null(runtime.interpolator, "a client build constructs an interpolator"):
		return
	check_eq(runtime.interpolator.body, runtime.body, "it reads the chassis body")
	check_eq(runtime.interpolator.visual_root, runtime.visual_root, "and writes VisualRoot")


func test_the_interpolator_blends_between_the_two_physics_transforms() -> void:
	var runtime := _adopted_runtime()
	var interp := runtime.interpolator
	if not check_not_null(interp, "a client build constructs an interpolator"):
		return

	runtime.body.global_position = Vector3(0.0, 0.0, 0.0)
	interp._physics_process(SyndicateConstants.PHYSICS_DT)
	runtime.body.global_position = Vector3(4.0, 0.0, 0.0)
	interp._physics_process(SyndicateConstants.PHYSICS_DT)

	check_approx(interp.interpolated(0.0).origin.x, 0.0, "at the tick boundary, the old pose")
	check_approx(interp.interpolated(0.5).origin.x, 2.0, "halfway through, halfway there")
	check_approx(interp.interpolated(1.0).origin.x, 4.0, "at the next boundary, the new pose")
	check_approx(
		interp.interpolated(1.6).origin.x, 4.0,
		"a fraction past the end is clamped rather than extrapolated"
	)


## ===== FIXTURES ========================================================


## Lowest orientation index whose basis carries part-local +Y onto [param axis].
func _orientation_mapping_y_to(axis: Vector3) -> int:
	for i in SyndicateConstants.ORIENTATION_COUNT:
		if (OrientationTable.basis_for(i) * Vector3(0, 1, 0)).is_equal_approx(axis):
			return i
	return -1


func _new_runtime() -> AssemblyRuntime:
	var runtime := AssemblyRuntime.new()
	_runtimes.append(runtime)
	# Physics shapes only register once the body is in a tree, so every
	# assertion against the server needs the runtime really parented.
	EventBus.get_tree().root.add_child(runtime)
	return runtime


func _adopted_runtime() -> AssemblyRuntime:
	var runtime := _new_runtime()
	runtime.adopt(_context_with_core_and_panel())
	return runtime


## A Core Module at the lattice origin with one Structural Component on its deck,
## committed through the same [PlacementValidator] chain every other path uses.
func _context_with_core_and_panel() -> BuildContext:
	var ctx := BuildContext.with_physics(3)
	_contexts.append(ctx)
	PlacementValidator.commit(ctx, PlacementCandidate.create(_core, CORE_ORIGIN, 0))
	PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0))
	return ctx
