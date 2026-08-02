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


## ===== RULE 17 — MOTIVE FAMILY PAYLOAD =================================

func test_a_kind_that_needs_a_family_payload_is_rejected_without_one() -> void:
	for kind: int in [
		PartEnums.MotiveKind.ROTOR_DISC,
		PartEnums.MotiveKind.AMBULATORY_LIMB,
		PartEnums.MotiveKind.TRACKED_SEGMENT,
	]:
		var def := _make_motive(kind)
		def.motive_profile.rotor_profile = null
		def.motive_profile.limb_profile = null
		def.motive_profile.track_profile = null
		check_true(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_MOTIVE_FAMILY_PAYLOAD),
			"kind %d needs a family payload and carrying none is a data error" % kind
		)


func test_a_ground_kind_carrying_a_family_payload_is_rejected() -> void:
	var def := _make_motive(PartEnums.MotiveKind.WHEELED_STEERED)
	def.motive_profile.rotor_profile = RotorProfile.new()
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_MOTIVE_FAMILY_PAYLOAD),
		"a wheel with a RotorProfile is a part nothing would read correctly"
	)


func test_two_family_payloads_at_once_are_rejected() -> void:
	var def := _make_motive(PartEnums.MotiveKind.ROTOR_DISC)
	def.motive_profile.limb_profile = LimbProfile.new()
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_MOTIVE_FAMILY_PAYLOAD),
		"exactly one payload matches the kind, mirroring the class payload rule"
	)


func test_a_correctly_paired_family_payload_passes() -> void:
	for kind: int in [
		PartEnums.MotiveKind.WHEELED_STEERED,
		PartEnums.MotiveKind.ROTOR_DISC,
		PartEnums.MotiveKind.AMBULATORY_LIMB,
		PartEnums.MotiveKind.TRACKED_SEGMENT,
	]:
		check_false(
			_rules_broken_by(_make_motive(kind)).has(
				PartRegistryValidator.RULE_MOTIVE_FAMILY_PAYLOAD
			),
			"kind %d with its matching payload is legal" % kind
		)


## ===== RULE 18 — AXLE KEYING ===========================================

func test_an_unkeyed_axle_station_is_rejected() -> void:
	var def := _make_panel()
	def.attachment_nodes[0].polarity = PartEnums.AttachmentPolarity.AXLE
	def.attachment_nodes[0].accepts_classes = PackedInt32Array()
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_AXLE_KEYING),
		"a drive station that accepts anything makes AXLE a slower FACE_NEUTRAL"
	)


func test_an_axle_station_keyed_to_the_wrong_class_is_rejected() -> void:
	var def := _make_panel()
	def.attachment_nodes[0].polarity = PartEnums.AttachmentPolarity.AXLE
	def.attachment_nodes[0].accepts_classes = PackedInt32Array(
		[PartEnums.PartClass.EFFECTOR_MODULE]
	)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_AXLE_KEYING),
		"an Effector Module has no business on a drive station"
	)


func test_a_correctly_keyed_axle_station_passes() -> void:
	var def := _make_panel()
	def.attachment_nodes[0].polarity = PartEnums.AttachmentPolarity.AXLE
	def.attachment_nodes[0].accepts_classes = PackedInt32Array(
		[PartEnums.PartClass.MOTIVE_ASSEMBLY]
	)
	check_false(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_AXLE_KEYING),
		"the shipping station's own arrangement is legal"
	)


## A Motive Assembly's own drive face needs no restriction: the station it mates
## with already carries it, and requiring it on both ends would be two owners of
## one invariant.
func test_a_motive_assemblys_own_axle_face_needs_no_restriction() -> void:
	var def := _make_motive(PartEnums.MotiveKind.WHEELED_STEERED)
	def.attachment_nodes[0].polarity = PartEnums.AttachmentPolarity.AXLE
	def.attachment_nodes[0].accepts_classes = PackedInt32Array()
	check_false(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_AXLE_KEYING),
		"the drive face of a Motive Assembly is the mating half, not the station"
	)


func test_an_axle_node_on_a_class_that_may_not_carry_one_is_rejected() -> void:
	var def := _make_effector()
	def.attachment_nodes[0].polarity = PartEnums.AttachmentPolarity.AXLE
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_AXLE_KEYING),
		"only Motive Assemblies and Structural Components may carry an AXLE node"
	)


## ===== RULE 19 — ROTOR =================================================

## The relationship the shipping coefficients are solved from. A disc that
## cannot lift its rating presents as an Assembly that silently refuses to fly.
func test_a_disc_that_cannot_lift_its_rating_is_rejected() -> void:
	var def := _make_motive(PartEnums.MotiveKind.ROTOR_DISC)
	def.motive_profile.rated_load_kg *= 2.0
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_ROTOR),
		"doubling the rating without touching the coefficients must fail"
	)


func test_a_disc_that_overshoots_its_rating_is_also_rejected() -> void:
	var def := _make_motive(PartEnums.MotiveKind.ROTOR_DISC)
	def.motive_profile.rotor_profile.thrust_coefficient *= 1.5
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_ROTOR),
		"the check is two-sided; a disc must not be quietly stronger than its row either"
	)


func test_a_disc_carrying_ground_fields_is_rejected() -> void:
	for field: String in [
		"traction_coefficient",
		"rolling_resistance",
		"max_steer_angle_deg",
		"suspension_stiffness_n_m",
		"suspension_rest_length_m",
		"suspension_damping_ns_m",
		"suspension_travel_limit_m",
	]:
		var def := _make_motive(PartEnums.MotiveKind.ROTOR_DISC)
		def.motive_profile.set(field, 1.0)
		check_true(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_ROTOR),
			"'%s' on a disc is a plausible value no code reads" % field
		)


func test_malformed_rotor_geometry_is_rejected() -> void:
	var cases := {
		"disc_radius_m": 0.0,
		"blade_count": 1,
		"spin_sign": 0,
		"nominal_rad_s": 0.0,
		"torque_reaction_ratio": 1.5,
	}
	for field: String in cases:
		var def := _make_motive(PartEnums.MotiveKind.ROTOR_DISC)
		def.motive_profile.rotor_profile.set(field, cases[field])
		check_true(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_ROTOR),
			"'%s' of %s is not a disc that can be simulated" % [field, cases[field]]
		)


func test_inverted_collective_limits_are_rejected() -> void:
	var def := _make_motive(PartEnums.MotiveKind.ROTOR_DISC)
	def.motive_profile.rotor_profile.collective_limit_deg = Vector2(14.0, -4.0)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_ROTOR),
		"a collective range whose minimum exceeds its maximum has no valid pitch"
	)


func test_a_well_formed_disc_passes() -> void:
	check_false(
		_rules_broken_by(_make_motive(PartEnums.MotiveKind.ROTOR_DISC)).has(
			PartRegistryValidator.RULE_ROTOR
		),
		"the fixture disc is solved from its own rating and must validate"
	)


## ===== RULE 20 — MELEE =================================================

func test_a_melee_module_without_a_melee_profile_is_rejected() -> void:
	var def := _make_melee()
	def.effector_profile.melee_profile = null
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_MELEE),
		"a melee kind with no melee payload describes nothing"
	)


func test_a_non_melee_module_carrying_a_melee_profile_is_rejected() -> void:
	var def := _make_effector()
	def.effector_profile.melee_profile = MeleeProfile.new()
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_MELEE),
		"a ballistic module has no swing to describe"
	)


func test_a_melee_module_carrying_emission_fields_is_rejected() -> void:
	var emission: Array[String] = [
		"muzzle_velocity_mps",
		"cycle_time_s",
		"recoil_impulse_ns",
		"spread_bloom_deg",
	]
	for field: String in emission:
		var def := _make_melee()
		def.effector_profile.set(field, 5.0)
		check_true(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_MELEE),
			"'%s' on a module that emits nothing must be zero, not ignored" % field
		)
	var mag := _make_melee()
	mag.effector_profile.magazine_rounds = 30
	check_true(
		_rules_broken_by(mag).has(PartRegistryValidator.RULE_MELEE),
		"and a melee module consumes no ammunition"
	)


## A mix that does not sum to one silently scales every strike the part ever
## lands, in a direction nothing reports.
func test_a_channel_mix_that_does_not_sum_to_one_is_rejected() -> void:
	var high := _make_melee()
	high.effector_profile.melee_profile.channel_mix = PackedFloat32Array([0.5, 0, 0.5, 0.5, 0])
	check_true(
		_rules_broken_by(high).has(PartRegistryValidator.RULE_MELEE),
		"a mix summing to 1.5 makes every strike half again as strong as its row"
	)
	var low := _make_melee()
	low.effector_profile.melee_profile.channel_mix = PackedFloat32Array([0.1, 0, 0.1, 0.1, 0])
	check_true(
		_rules_broken_by(low).has(PartRegistryValidator.RULE_MELEE),
		"and one summing to 0.3 quietly makes it a third as strong"
	)


func test_a_channel_mix_of_the_wrong_length_is_rejected() -> void:
	var def := _make_melee()
	def.effector_profile.melee_profile.channel_mix = PackedFloat32Array([0.5, 0.5])
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_MELEE),
		"a mix shorter than the channel count reads past its end"
	)


func test_melee_bounds_are_enforced() -> void:
	var cases := {
		"max_targets_per_swing": 0,
		"swing_samples": 1,
		"reaction_ratio": 1.4,
	}
	for field: String in cases:
		var def := _make_melee()
		def.effector_profile.melee_profile.set(field, cases[field])
		check_true(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_MELEE),
			"'%s' of %s is outside the bound CLAUDE.md §6 I-12 sets" % [field, cases[field]]
		)
	var over := _make_melee()
	over.effector_profile.melee_profile.max_targets_per_swing = 99
	check_true(
		_rules_broken_by(over).has(PartRegistryValidator.RULE_MELEE),
		"and the target budget has an upper bound too"
	)


func test_a_well_formed_melee_module_passes() -> void:
	check_false(
		_rules_broken_by(_make_melee()).has(PartRegistryValidator.RULE_MELEE),
		"the fixture edge is the shipping arrangement and must validate"
	)


## ===== RULE 21 — LIMB ==================================================

func test_a_limb_carrying_suspension_fields_is_rejected() -> void:
	for field: String in [
		"suspension_stiffness_n_m",
		"suspension_rest_length_m",
		"suspension_damping_ns_m",
		"suspension_travel_limit_m",
	]:
		var def := _make_motive(PartEnums.MotiveKind.AMBULATORY_LIMB)
		def.motive_profile.set(field, 1.0)
		check_true(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_LIMB),
			"'%s' on a limb: its compliance is commanded, not passive" % field
		)


func test_malformed_gait_parameters_are_rejected() -> void:
	var cases := {
		"duty_factor": 0.0,
		"leg_length_m": 0.0,
		"stance_height_ratio": 1.4,
	}
	for field: String in cases:
		var def := _make_motive(PartEnums.MotiveKind.AMBULATORY_LIMB)
		def.motive_profile.limb_profile.set(field, cases[field])
		check_true(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_LIMB),
			"'%s' of %s is not a gait that can be walked" % [field, cases[field]]
		)


func test_a_cadence_ceiling_below_its_floor_is_rejected() -> void:
	var def := _make_motive(PartEnums.MotiveKind.AMBULATORY_LIMB)
	def.motive_profile.limb_profile.max_cadence_hz = 0.5
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_LIMB),
		"a maximum below the nominal makes the cadence clamp invert"
	)


func test_a_step_longer_than_twice_the_leg_is_rejected() -> void:
	var def := _make_motive(PartEnums.MotiveKind.AMBULATORY_LIMB)
	def.motive_profile.limb_profile.max_step_length_m = (
		2.1 * def.motive_profile.limb_profile.leg_length_m
	)
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_LIMB),
		"such a step cannot be taken with a foot on the ground at either end of it"
	)


func test_a_well_formed_limb_passes() -> void:
	check_false(
		_rules_broken_by(_make_motive(PartEnums.MotiveKind.AMBULATORY_LIMB)).has(
			PartRegistryValidator.RULE_LIMB
		),
		"the fixture limb must validate"
	)


## ===== RULE 22 — TRACK =================================================

## A track that steered by angling its hub would be a wheel.
func test_a_track_with_a_steer_angle_is_rejected() -> void:
	var def := _make_motive(PartEnums.MotiveKind.TRACKED_SEGMENT)
	def.motive_profile.max_steer_angle_deg = 20.0
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_TRACK),
		"a track steers by differential drive alone"
	)


func test_malformed_track_parameters_are_rejected() -> void:
	var cases := {
		"road_stations": 0,
		"patch_length_m": 0.0,
		"differential_authority": 1.6,
		"internal_loss": 1.0,
		"lateral_grip_ratio": 0.0,
	}
	for field: String in cases:
		var def := _make_motive(PartEnums.MotiveKind.TRACKED_SEGMENT)
		def.motive_profile.track_profile.set(field, cases[field])
		check_true(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_TRACK),
			"'%s' of %s is not a patch that can be simulated" % [field, cases[field]]
		)


## §14 rule 23. A ground contact whose rest length does not reach past its own
## radius has a suspension that can never register compression, and everything
## downstream of it — normal force, traction, drive — is then zero. Both shipped
## ground rows were authored that way and nothing said a word, because every
## intermediate value is a legal number that an airborne contact produces.
func test_a_rest_length_inside_the_contact_radius_is_rejected() -> void:
	for kind: PartEnums.MotiveKind in [
		PartEnums.MotiveKind.WHEELED_STEERED, PartEnums.MotiveKind.TRACKED_SEGMENT
	]:
		var def := _make_motive(kind)
		def.motive_profile.contact_radius_m = 0.50
		def.motive_profile.suspension_rest_length_m = 0.32
		check_true(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_SUSPENSION_REACH),
			"a rest length of 0.32 m under a 0.50 m contact radius cannot drive"
		)


## The accept half. A rest length past the radius is legal, and the convention of
## radius plus travel is what the shipping rows use.
func test_a_rest_length_past_the_contact_radius_is_accepted() -> void:
	var def := _make_motive(PartEnums.MotiveKind.WHEELED_STEERED)
	def.motive_profile.contact_radius_m = 0.50
	def.motive_profile.suspension_travel_limit_m = 0.24
	def.motive_profile.suspension_rest_length_m = 0.74
	check_false(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_SUSPENSION_REACH),
		"radius plus travel is the documented convention and passes"
	)


## A rotary or ambulatory row has no suspension at all and rule 23 must not fire
## on it — rules 19 and 21 already require those fields to be exactly zero, and
## two rules failing one row makes neither of them load-bearing.
func test_rule_23_ignores_the_families_with_no_suspension() -> void:
	for kind: PartEnums.MotiveKind in [
		PartEnums.MotiveKind.ROTOR_DISC, PartEnums.MotiveKind.AMBULATORY_LIMB
	]:
		var def := _make_motive(kind)
		def.motive_profile.suspension_rest_length_m = 0.0
		check_false(
			_rules_broken_by(def).has(PartRegistryValidator.RULE_SUSPENSION_REACH),
			"a disc and a limb carry no suspension for the rule to check"
		)


func test_too_many_road_stations_are_rejected() -> void:
	var def := _make_motive(PartEnums.MotiveKind.TRACKED_SEGMENT)
	def.motive_profile.track_profile.road_stations = TrackProfile.MAX_ROAD_STATIONS + 1
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_TRACK),
		"the station count is the per-tick cost multiplier and is capped"
	)


func test_a_well_formed_track_passes() -> void:
	check_false(
		_rules_broken_by(_make_motive(PartEnums.MotiveKind.TRACKED_SEGMENT)).has(
			PartRegistryValidator.RULE_TRACK
		),
		"the fixture track must validate"
	)


## ===== RULE 24 — POWER SPLIT ===========================================

func test_a_prime_mover_that_makes_no_torque_is_rejected() -> void:
	# The rule the §10.4 split exists to enforce. Before it, a `0` in the torque
	# column was how a definition said "this one is really a cell", which is a
	# class distinction written as a magic value: nothing stopped it, nothing
	# told the garage, and one class answered two unrelated questions.
	var def := _make_prime_mover()
	def.prime_mover_profile.drive_torque_nm = 0.0
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_POWER_SPLIT),
		"a Prime Mover with no shaft torque is an Energy Cell and belongs in that class"
	)


func test_an_energy_cell_that_supplies_nothing_is_rejected() -> void:
	# The other half. A cell makes no torque, so supply is the whole of what it
	# contributes; a cell supplying nothing has no reason to be on the build.
	var no_supply := _make_energy_cell()
	no_supply.power_supply_pu = 0.0
	check_true(
		_rules_broken_by(no_supply).has(PartRegistryValidator.RULE_POWER_SPLIT),
		"an Energy Cell supplying no power contributes nothing at all"
	)

	var no_discharge := _make_energy_cell()
	no_discharge.energy_cell_profile.discharge_limit_pu = 0.0
	check_true(
		_rules_broken_by(no_discharge).has(PartRegistryValidator.RULE_POWER_SPLIT),
		"and neither half of the supply pair may be zero"
	)


func test_an_energy_cells_reserve_may_not_be_negative() -> void:
	var def := _make_energy_cell()
	def.energy_cell_profile.capacity_pu_s = -1.0
	check_true(
		_rules_broken_by(def).has(PartRegistryValidator.RULE_POWER_SPLIT),
		"a negative reserve is not a smaller reserve"
	)

	var recharge := _make_energy_cell()
	recharge.energy_cell_profile.recharge_pu_s = -1.0
	check_true(
		_rules_broken_by(recharge).has(PartRegistryValidator.RULE_POWER_SPLIT),
		"and neither is a negative recharge rate"
	)


func test_a_well_formed_power_pair_passes() -> void:
	check_false(
		_rules_broken_by(_make_prime_mover()).has(PartRegistryValidator.RULE_POWER_SPLIT),
		"the fixture Prime Mover must validate"
	)
	check_false(
		_rules_broken_by(_make_energy_cell()).has(PartRegistryValidator.RULE_POWER_SPLIT),
		"and so must the fixture Energy Cell"
	)


func test_rule_24_ignores_the_classes_it_does_not_own() -> void:
	# A Structural Component supplies nothing and makes no torque, and that is
	# not a finding. A rule that fired on every class would be caught by the
	# reference-definition test above, but only by accident.
	check_false(
		_rules_broken_by(_make_panel()).has(PartRegistryValidator.RULE_POWER_SPLIT),
		"rule 24 says nothing about a part that is neither half of the split"
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


## A melee Effector Module that passes every rule, arranged the way
## `eff.melee.beam_edge.t4` is: no emission fields, a mix summing to one.
func _make_melee() -> PartDefinition:
	var def := _make_panel()
	def.part_key = &"eff.melee.beam_edge.t4"
	def.part_class = PartEnums.PartClass.EFFECTOR_MODULE
	def.tier = PartEnums.TierGrade.PROTOTYPE

	var profile := EffectorModuleProfile.new()
	profile.kind = PartEnums.EffectorKind.ENERGY_MELEE
	profile.muzzle_velocity_mps = 0.0
	profile.cycle_time_s = 0.0
	profile.recoil_impulse_ns = 0.0
	profile.spread_base_deg = 0.0
	profile.spread_bloom_deg = 0.0
	profile.magazine_rounds = 0

	var melee := MeleeProfile.new()
	melee.channel_mix = PackedFloat32Array([0.10, 0.0, 0.15, 0.75, 0.0])
	melee.max_targets_per_swing = 3
	melee.swing_samples = 6
	melee.reaction_ratio = 0.35
	profile.melee_profile = melee

	def.effector_profile = profile
	return def


## A Motive Assembly of [param kind], carrying exactly the family payload that
## kind requires and nothing else.
##
## The rotary case solves its own rated load from its coefficients rather than
## quoting a number, so the fixture cannot drift out of rule 19's tolerance when
## a coefficient default changes — and a test that plants a fault against it is
## asserting against the rule rather than against a stale constant.
func _make_motive(kind: int) -> PartDefinition:
	var def := _make_panel()
	def.part_key = &"mot.wheeled.allroad.t2"
	def.part_class = PartEnums.PartClass.MOTIVE_ASSEMBLY

	var profile := MotiveAssemblyProfile.new()
	profile.kind = kind
	match kind:
		PartEnums.MotiveKind.ROTOR_DISC:
			var rotor := RotorProfile.new()
			profile.rotor_profile = rotor
			profile.rated_load_kg = rotor.max_thrust_n() / SyndicateConstants.GRAVITY_MPS2
			profile.traction_coefficient = 0.0
			profile.rolling_resistance = 0.0
			profile.max_steer_angle_deg = 0.0
			profile.suspension_rest_length_m = 0.0
			profile.suspension_stiffness_n_m = 0.0
			profile.suspension_damping_ns_m = 0.0
			profile.suspension_travel_limit_m = 0.0
		PartEnums.MotiveKind.AMBULATORY_LIMB:
			profile.limb_profile = LimbProfile.new()
			profile.suspension_rest_length_m = 0.0
			profile.suspension_stiffness_n_m = 0.0
			profile.suspension_damping_ns_m = 0.0
			profile.suspension_travel_limit_m = 0.0
		PartEnums.MotiveKind.TRACKED_SEGMENT:
			profile.track_profile = TrackProfile.new()
			profile.max_steer_angle_deg = 0.0

	def.motive_profile = profile
	return def


## A Prime Mover that passes every rule. The §10.4 split means the two power
## classes need separate fixtures: they share no payload field, and a test that
## reached for one to check the other would be asserting rule 6 by mistake.
func _make_prime_mover() -> PartDefinition:
	var def := _make_panel()
	def.part_key = &"pmv.combustion.standard.t2"
	def.part_class = PartEnums.PartClass.PRIME_MOVER
	def.power_supply_pu = 150.0
	def.prime_mover_profile = PrimeMoverProfile.new()
	return def


## An Energy Cell that passes every rule.
func _make_energy_cell() -> PartDefinition:
	var def := _make_panel()
	def.part_key = &"cel.static.standard.t3"
	def.part_class = PartEnums.PartClass.ENERGY_CELL
	def.tier = PartEnums.TierGrade.REFINED
	def.power_supply_pu = 260.0
	def.energy_cell_profile = EnergyCellProfile.new()
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
