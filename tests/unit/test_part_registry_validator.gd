extends TestCase
## Every rule of [code]docs/PART_DATA_SCHEMA.md[/code] §14 that a single
## definition can break, asserted by planting the fault and checking that the
## rule which is supposed to catch it does.
##
## Each test starts from a definition that passes cleanly and breaks exactly one
## thing. That is the only way to tell a rule that works from a rule that never
## fires: a validator asserted only against valid data passes just as happily
## when its checks are commented out.
##
## The cross-part rules — 2 (manifest) and 13 (tier scaling) — need more than one
## definition and are covered in
## [code]tests/integration/test_part_registry_data.gd[/code].


func test_a_well_formed_definition_passes() -> void:
	var validator := PartRegistryValidator.new()
	validator.validate_definition(_make_panel())
	check_eq(
		validator.failures().size(),
		0,
		"the reference definition must validate cleanly, else every fault test below is "
		+ "asserting against noise:\n      %s" % "\n      ".join(validator.failures())
	)


## ===== RULE 1 — KEY GRAMMAR ============================================

func test_key_grammar_accepts_the_documented_examples() -> void:
	# §5.1's own examples, one per class tag that appears in it.
	var keys: Array[StringName] = [
		&"core.command.compact.t2",
		&"str.panel.medium.t2",
		&"mot.wheeled.offroad_heavy.t3",
		&"eff.ballistic.autocannon_30.t3",
	]
	var classes: Array[PartEnums.PartClass] = [
		PartEnums.PartClass.CORE_MODULE,
		PartEnums.PartClass.STRUCTURAL_COMPONENT,
		PartEnums.PartClass.MOTIVE_ASSEMBLY,
		PartEnums.PartClass.EFFECTOR_MODULE,
	]
	var tiers: Array[PartEnums.TierGrade] = [
		PartEnums.TierGrade.STANDARD,
		PartEnums.TierGrade.STANDARD,
		PartEnums.TierGrade.REFINED,
		PartEnums.TierGrade.REFINED,
	]
	for i in keys.size():
		var def := _make_panel()
		def.part_key = keys[i]
		def.part_class = classes[i]
		def.tier = tiers[i]
		check_false(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_KEY_GRAMMAR),
			"§5.1 example '%s' must satisfy the grammar" % keys[i]
		)


func test_key_grammar_rejects_malformed_keys() -> void:
	var bad: Array[StringName] = [
		&"str.panel.medium",  # no tier tag
		&"str.panel.medium.t6",  # tier tag out of range
		&"xyz.panel.medium.t2",  # unknown class tag
		&"str.Panel.medium.t2",  # capital in the family
		&"str.pa.medium.t2",  # family below three characters
		&"str.panel.m.t2",  # variant below two characters
		&"str.panel.medium.t2.extra",  # a fifth segment
		&"",
	]
	for key in bad:
		var def := _make_panel()
		def.part_key = key
		check_true(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_KEY_GRAMMAR),
			"'%s' must be rejected by the §5.1 grammar" % key
		)


func test_key_class_tag_must_agree_with_part_class() -> void:
	var def := _make_panel()
	def.part_key = &"core.panel.medium.t2"
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_KEY_GRAMMAR),
		"a 'core' key on a STRUCTURAL_COMPONENT resolves to the wrong data/parts directory"
	)


func test_key_tier_tag_must_agree_with_the_tier_field() -> void:
	var def := _make_panel()
	def.tier = PartEnums.TierGrade.APEX
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_KEY_GRAMMAR),
		"a t2 key on an APEX part would scale against the wrong §12 row"
	)


## ===== RULES 3, 4, 5 — OCCUPANCY =======================================

func test_occupancy_must_contain_the_pivot_cell() -> void:
	var def := _make_panel()
	def.occupancy_cells = PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0)])
	_bake(def)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_PIVOT_CELL),
		"a part without cell (0,0,0) has no pivot for any frame conversion"
	)


func test_empty_occupancy_is_rejected() -> void:
	var def := _make_panel()
	def.occupancy_cells = PackedVector3Array()
	_bake(def)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_PIVOT_CELL),
		"an empty occupancy must be reported, not divided by"
	)


func test_duplicate_occupancy_cells_are_rejected() -> void:
	var def := _make_panel()
	def.occupancy_cells = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3.ZERO])
	_bake(def)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_OCCUPANCY_SOLID),
		"a duplicated cell double-counts volume, and volume divides integrity_per_cell"
	)


func test_disjoint_occupancy_is_rejected() -> void:
	var def := _make_panel()
	# Two cells with a gap between them: 6-connected only through empty space.
	def.occupancy_cells = PackedVector3Array([Vector3.ZERO, Vector3(2, 0, 0)])
	_bake(def)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_OCCUPANCY_SOLID),
		"a part must be one contiguous solid; the graph can never reach a detached cell"
	)


func test_diagonally_touching_cells_are_not_connected() -> void:
	# Corner contact is not 6-connectivity. This is the case a naive
	# adjacency test with a 26-neighbourhood would wrongly accept.
	var def := _make_panel()
	def.occupancy_cells = PackedVector3Array([Vector3.ZERO, Vector3(1, 1, 0)])
	_bake(def)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_OCCUPANCY_SOLID),
		"cells meeting only at an edge are not 6-connected"
	)


func test_connected_l_shape_is_accepted() -> void:
	var def := _make_panel()
	def.occupancy_cells = PackedVector3Array([
		Vector3.ZERO, Vector3(1, 0, 0), Vector3(1, 1, 0)
	])
	def.collider_profile = _box_collider(def)
	_bake(def)
	check_false(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_OCCUPANCY_SOLID),
		"a non-convex but contiguous footprint is legal"
	)


func test_occupancy_extent_is_capped() -> void:
	var def := _make_panel()
	var cells := PackedVector3Array()
	for x in PartRegistryValidator.MAX_EXTENT_CELLS + 1:
		cells.append(Vector3(x, 0, 0))
	def.occupancy_cells = cells
	def.collider_profile = _box_collider(def)
	_bake(def)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_OCCUPANCY_EXTENT),
		"an extent of %d cells exceeds the limit" % (PartRegistryValidator.MAX_EXTENT_CELLS + 1)
	)


## ===== RULE 6 — CLASS PAYLOAD ==========================================

func test_class_payload_must_match_part_class() -> void:
	var def := _make_panel()
	def.part_key = &"core.command.compact.t2"
	def.part_class = PartEnums.PartClass.CORE_MODULE
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_CLASS_PAYLOAD),
		"a CORE_MODULE with no core_profile has no mount budget or power capacity"
	)


func test_two_class_payloads_are_rejected() -> void:
	var def := _make_core()
	def.effector_profile = EffectorModuleProfile.new()
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_CLASS_PAYLOAD),
		"exactly one class profile may be non-null"
	)


func test_structural_component_must_carry_no_payload() -> void:
	var def := _make_panel()
	def.control_profile = ControlSurfaceProfile.new()
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_CLASS_PAYLOAD),
		"Structural Components have no class payload by design"
	)


func test_structural_component_with_no_payload_is_accepted() -> void:
	check_false(
		_rules_broken_by(_make_panel()).has(PartRegistryValidator.RULE_CLASS_PAYLOAD),
		"a bare Structural Component is the normal case, not a malformed one"
	)


## ===== RULE 7 — RESISTANCE =============================================

func test_resistance_length_must_match_the_channel_count() -> void:
	var def := _make_panel()
	def.resistance = PackedFloat32Array([0.1, 0.1, 0.1])
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_RESISTANCE),
		"a short resistance array indexes out of bounds on the missing channels"
	)


func test_resistance_above_the_ceiling_is_rejected() -> void:
	var def := _make_panel()
	def.resistance = PackedFloat32Array([0.86, 0.0, 0.0, 0.0, 0.0])
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_RESISTANCE),
		"the 0.85 ceiling exists so no configuration reaches immunity"
	)


func test_negative_resistance_is_rejected() -> void:
	var def := _make_panel()
	def.resistance = PackedFloat32Array([-0.01, 0.0, 0.0, 0.0, 0.0])
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_RESISTANCE),
		"negative resistance would amplify incoming damage"
	)


func test_resistance_exactly_at_the_ceiling_is_accepted() -> void:
	var def := _make_panel()
	def.resistance = PackedFloat32Array([0.85, 0.85, 0.85, 0.85, 0.85])
	check_false(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_RESISTANCE),
		"the ceiling is inclusive"
	)


## ===== RULE 8 — COLLIDER (§6.2) ========================================

func test_missing_collider_profile_is_rejected() -> void:
	var def := _make_panel()
	def.collider_profile = null
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_COLLIDER),
		"Invariant I-1: ColliderProfile is the only source of collision geometry"
	)


func test_empty_collider_profile_is_rejected() -> void:
	var def := _make_panel()
	def.collider_profile = ColliderProfile.new()
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_COLLIDER),
		"a part with no primitives has no hit registration at all"
	)


func test_too_many_collider_primitives_are_rejected() -> void:
	var def := _make_panel()
	var profile := ColliderProfile.new()
	for i in ColliderProfile.MAX_PRIMITIVES_PER_PART + 1:
		var prim := ColliderPrimitiveDef.new()
		prim.half_extents_m = Vector3(0.25, 0.0625, 0.25)
		profile.primitives.push_back(prim)
	def.collider_profile = profile
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_COLLIDER),
		"§6.2 caps a part at %d primitives" % ColliderProfile.MAX_PRIMITIVES_PER_PART
	)


func test_collider_below_the_coverage_band_is_rejected() -> void:
	var def := _make_panel()
	var prim := ColliderPrimitiveDef.new()
	prim.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	# Half the occupancy: a shot through the other half hits nothing.
	prim.half_extents_m = _panel_half_extents() * Vector3(0.5, 1.0, 1.0)
	var profile := ColliderProfile.new()
	profile.primitives.push_back(prim)
	def.collider_profile = profile
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_COLLIDER),
		"an undersized collider is the phantom-gap exploit §6.2 rule 3 exists to stop"
	)


func test_collider_above_the_coverage_band_is_rejected() -> void:
	var def := _make_panel()
	var prim := ColliderPrimitiveDef.new()
	prim.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	prim.half_extents_m = _panel_half_extents() * Vector3(1.5, 1.0, 1.0)
	var profile := ColliderProfile.new()
	profile.primitives.push_back(prim)
	def.collider_profile = profile
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_COLLIDER),
		"an oversized collider is an invisible hitbox around the part"
	)


func test_collider_euler_must_be_a_multiple_of_fifteen_degrees() -> void:
	var def := _make_panel()
	def.collider_profile.primitives[0].local_basis_euler_deg = Vector3(0.0, 17.0, 0.0)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_COLLIDER),
		"an arbitrary angle is not reproducible across platforms"
	)


func test_collider_euler_at_a_legal_step_is_accepted() -> void:
	var def := _make_panel()
	def.collider_profile.primitives[0].local_basis_euler_deg = Vector3(0.0, -45.0, 15.0)
	check_false(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_COLLIDER),
		"negative and positive multiples of 15° are both legal"
	)


## ===== RULES 9, 10, 11 — ATTACHMENT NODES ==============================

func test_non_axis_face_normal_is_rejected() -> void:
	var def := _make_panel()
	def.attachment_nodes[0].face_normal = Vector3i(1, 1, 0)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_NODE_NORMAL),
		"diagonal mating would cost the lattice solver its O(1) placement query"
	)


func test_node_on_an_unoccupied_cell_is_rejected() -> void:
	var def := _make_panel()
	def.attachment_nodes[0].cell = Vector3i(9, 9, 9)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_NODE_CELL),
		"a node off the part's own footprint resolves into another part's cell"
	)


func test_duplicate_cell_and_face_pair_is_rejected() -> void:
	var def := _make_panel()
	var clone := AttachmentNodeDef.new()
	clone.node_name = &"duplicate"
	clone.cell = def.attachment_nodes[0].cell
	clone.face_normal = def.attachment_nodes[0].face_normal
	def.attachment_nodes.push_back(clone)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_NODE_UNIQUE),
		"one cell face mates once; two nodes on it make mate selection ambiguous"
	)


func test_same_cell_with_different_faces_is_accepted() -> void:
	var def := _make_panel()
	var extra := AttachmentNodeDef.new()
	extra.node_name = &"other_face"
	extra.cell = def.attachment_nodes[0].cell
	extra.face_normal = -def.attachment_nodes[0].face_normal
	def.attachment_nodes.push_back(extra)
	check_false(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_NODE_UNIQUE),
		"a corner cell legitimately carries a node on each of its exposed faces"
	)


## ===== RULE 12 — POSITIVE SCALARS ======================================

func test_zero_mass_is_rejected() -> void:
	var def := _make_panel()
	def.mass_kg = 0.0
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_POSITIVE_SCALARS),
		"a massless part inverts the Assembly inertia tensor"
	)


func test_zero_integrity_is_rejected() -> void:
	var def := _make_panel()
	def.integrity_max = 0.0
	_bake(def)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_POSITIVE_SCALARS),
		"a part with no integrity is destroyed on spawn"
	)


## ===== RULE 14 — VISUAL COLLISION ======================================

func test_mesh_with_a_collision_import_suffix_is_rejected() -> void:
	var def := _make_panel()
	var mesh := BoxMesh.new()
	mesh.resource_name = "str_panel_medium_t2-colonly"
	def.visual_profile.stage = PartVisualProfile.Stage.FINAL
	def.visual_profile.mesh_nominal = mesh
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_VISUAL_COLLISION),
		"a '-colonly' mesh generates collision at import, which Invariant I-1 forbids"
	)


func test_mesh_with_collision_metadata_is_rejected() -> void:
	var def := _make_panel()
	var mesh := BoxMesh.new()
	mesh.set_meta("_collision", true)
	def.visual_profile.stage = PartVisualProfile.Stage.FINAL
	def.visual_profile.mesh_nominal = mesh
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_VISUAL_COLLISION),
		"collision metadata on a rendered mesh is collision derived from a visual"
	)


func test_a_clean_mesh_is_accepted() -> void:
	var def := _make_panel()
	var mesh := BoxMesh.new()
	mesh.resource_name = "str_panel_medium_t2"
	def.visual_profile.stage = PartVisualProfile.Stage.FINAL
	def.visual_profile.mesh_nominal = mesh
	check_false(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_VISUAL_COLLISION),
		"an ordinary mesh name must not trip the suffix scan"
	)


func test_missing_visual_profile_warns_without_failing() -> void:
	var def := _make_panel()
	def.visual_profile = null
	var validator := PartRegistryValidator.new()
	validator.validate_definition(def)
	check_false(
		validator.failed_rule(PartRegistryValidator.RULE_VISUAL_COLLISION),
		"§14 rule 14 is about a poisoned mesh, not an absent profile"
	)
	check_eq(validator.warnings().size(), 1, "an unrenderable part is still worth reporting")


## ===== RULE 15 — CORE BUDGETS ==========================================

func test_core_with_too_small_a_mount_budget_is_rejected() -> void:
	var def := _make_core()
	def.core_profile.mount_budget = PartRegistryValidator.MIN_CORE_MOUNT_BUDGET - 1
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_CORE_BUDGETS),
		"below %d mounts an Assembly cannot carry a usable loadout"
		% PartRegistryValidator.MIN_CORE_MOUNT_BUDGET
	)


func test_core_with_no_power_capacity_is_rejected() -> void:
	var def := _make_core()
	def.core_profile.power_capacity_pu = 0.0
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_CORE_BUDGETS),
		"a Core Module with no capacity powers nothing"
	)


func test_core_budget_rule_does_not_apply_to_other_classes() -> void:
	# The panel has no core_profile at all; rule 15 must skip it rather than
	# dereference null.
	check_false(
		_rules_broken_by(_make_panel()).has(PartRegistryValidator.RULE_CORE_BUDGETS),
		"rule 15 is scoped to CORE_MODULE"
	)


## ===== RULE 16 — EFFECTOR LIMITS =======================================

func test_inverted_yaw_limits_are_rejected() -> void:
	var def := _make_effector()
	def.effector_profile.yaw_limit_deg = Vector2(40.0, -40.0)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_EFFECTOR_LIMITS),
		"an inverted yaw range makes the arc sampler traverse nothing"
	)


func test_inverted_pitch_limits_are_rejected() -> void:
	var def := _make_effector()
	def.effector_profile.pitch_limit_deg = Vector2(34.0, -8.0)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_EFFECTOR_LIMITS),
		"an inverted pitch range makes the aim solver unsolvable"
	)


func test_ordered_limits_are_accepted() -> void:
	check_false(
		_rules_broken_by(_make_effector()).has(PartRegistryValidator.RULE_EFFECTOR_LIMITS),
		"the schema defaults are a legal arc"
	)


## ===== FIXTURES ========================================================

## The rules that [param def] breaks. Each call gets a fresh validator so no
## test can observe another's findings.
func _rules_broken_by(def: PartDefinition) -> PackedInt32Array:
	var validator := PartRegistryValidator.new()
	validator.validate_definition(def)
	return validator.failed_rules()


func _bake(def: PartDefinition) -> void:
	def._bake_derived_fields()


## A 2x1x2-cell Structural Component that passes every rule. Deliberately not the
## shipped panel: a fixture that loads real data would fail for reasons a fault
## test cannot distinguish from the fault it planted.
func _make_panel() -> PartDefinition:
	var def := PartDefinition.new()
	def.part_key = &"str.panel.medium.t2"
	def.display_name_key = &"part.str.panel.medium.t2.name"
	def.part_class = PartEnums.PartClass.STRUCTURAL_COMPONENT
	def.tier = PartEnums.TierGrade.STANDARD
	def.occupancy_cells = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1)
	])
	def.mass_kg = 34.0
	def.integrity_max = 380.0
	def.resistance = PackedFloat32Array([0.18, 0.10, 0.20, 0.05, 0.05])
	def.armour_rating = 14.0
	def.load_capacity_kg = 520.0
	def.visual_profile = PartVisualProfile.new()
	def.fusion_profile = FusionProfile.new()
	_bake(def)
	def.collider_profile = _box_collider(def)

	var node := AttachmentNodeDef.new()
	node.node_name = &"yp_00"
	node.cell = Vector3i.ZERO
	node.face_normal = Vector3i(0, 1, 0)
	node.polarity = PartEnums.AttachmentPolarity.FACE_NEUTRAL
	def.attachment_nodes = [node] as Array[AttachmentNodeDef]
	return def


func _make_core() -> PartDefinition:
	var def := _make_panel()
	def.part_key = &"core.command.compact.t2"
	def.part_class = PartEnums.PartClass.CORE_MODULE
	def.core_profile = CoreModuleProfile.new()
	return def


func _make_effector() -> PartDefinition:
	var def := _make_panel()
	def.part_key = &"eff.ballistic.autocannon_30.t2"
	def.part_class = PartEnums.PartClass.EFFECTOR_MODULE
	def.effector_profile = EffectorModuleProfile.new()
	return def


## Half extents in metres of the fixture panel's occupancy box.
func _panel_half_extents() -> Vector3:
	var unit := SyndicateConstants.LATTICE_UNIT_M
	return Vector3(2.0, 1.0, 2.0) * 0.5 * unit


## A single BOX covering [param def]'s bounding box exactly. Correct only for a
## part whose occupancy fills its bounds, which every fixture here does.
func _box_collider(def: PartDefinition) -> ColliderProfile:
	var unit := SyndicateConstants.LATTICE_UNIT_M
	var prim := ColliderPrimitiveDef.new()
	prim.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	prim.half_extents_m = Vector3(def.bounds_size_cells) * 0.5 * unit
	prim.local_offset_m = Vector3(def.bounds_max_cell + def.bounds_min_cell) * 0.5 * unit

	var profile := ColliderProfile.new()
	profile.primitives = [prim] as Array[ColliderPrimitiveDef]
	return profile
