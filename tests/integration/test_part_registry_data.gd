extends TestCase
## The shipped contents of [code]data/parts/[/code], validated end to end.
##
## [code]tests/unit/test_part_registry_validator.gd[/code] proves the rules fire
## on a planted fault. This proves the data satisfies them, and that the data
## survives the round trip through [code].tres[/code] and out of the registry
## with the same numbers document 01 §10 publishes.
##
## The round-trip half is not ceremony. A typed [code]Array[Resource][/code] that
## fails element validation on load is dropped silently, so a definition can lose
## every attachment node between the authoring script and the running game
## without one error being printed. That failure has already happened once in
## this repository, to [ColliderProfile].

## §10.1 and §10.2, quoted. A change to either table must be made here too, in
## the same commit, or this test is the thing that says so.
const CORE_KEY: StringName = &"core.command.compact.t2"
const CORE_CELLS: Vector3i = Vector3i(4, 3, 5)
const CORE_MASS_KG: float = 380.0
const CORE_INTEGRITY: float = 1450.0
const CORE_ARMOUR: float = 18.0
const CORE_POWER_CAPACITY_PU: float = 240.0
const CORE_MOUNT_BUDGET: int = 28
const CORE_SPEED_CAP_MPS: float = 24.0
const CORE_MASS_TOLERANCE_KG: float = 3600.0
const CORE_RESISTANCE: Array[float] = [0.15, 0.20, 0.25, 0.10, 0.05]

const PANEL_KEY: StringName = &"str.panel.medium.t2"
const PANEL_CELLS: Vector3i = Vector3i(4, 1, 4)
const PANEL_MASS_KG: float = 34.0
const PANEL_INTEGRITY: float = 380.0
const PANEL_ARMOUR: float = 14.0
const PANEL_LOAD_CAPACITY_KG: float = 520.0
const PANEL_RESISTANCE: Array[float] = [0.18, 0.10, 0.20, 0.05, 0.05]

## Exposed cell faces of a solid box, which is what both parts are. The Core
## Module's 4x3x5 gives 2*(4*3 + 3*5 + 4*5) = 94; the panel's 4x1x4 gives 48.
const CORE_NODE_COUNT: int = 94
const PANEL_NODE_COUNT: int = 48

var _validator: PartRegistryValidator = null


func before_all() -> void:
	_validator = PartRegistryValidator.new()
	_validator.validate_registry()


## ===== THE GATE ========================================================

func test_shipped_registry_breaks_no_rule() -> void:
	check_eq(
		_validator.failures().size(),
		0,
		"data/parts must satisfy every §14 rule:\n      %s"
		% "\n      ".join(_validator.failures())
	)


func test_shipped_registry_raises_no_warning() -> void:
	check_eq(
		_validator.warnings().size(),
		0,
		"warnings are findings a reviewer should see resolved:\n      %s"
		% "\n      ".join(_validator.warnings())
	)


func test_validator_sees_every_manifest_entry() -> void:
	var manifest: PartManifest = load(PartRegistryService.MANIFEST_PATH) as PartManifest
	if not check_not_null(manifest, "the manifest must load"):
		return
	check_eq(
		_validator.definitions().size(),
		manifest.keys.size(),
		"a definition the validator could not load would be silently unchecked"
	)


## ===== REGISTRY WIRING =================================================

func test_registry_publishes_both_parts() -> void:
	check_eq(PartRegistry.part_count(), 2, "two parts are authored")
	check_true(PartRegistry.has_key(CORE_KEY), "the Core Module is registered")
	check_true(PartRegistry.has_key(PANEL_KEY), "the Structural Component is registered")


## §5.2: part_def_id is the manifest index plus one, and index 0 is reserved.
## These ids go into save data and network packets, so a shift here silently
## reinterprets every blueprint ever written.
func test_part_ids_follow_manifest_order() -> void:
	check_null(PartRegistry.definition(PartManifest.INVALID_PART_ID), "id 0 is INVALID_PART")
	var core := PartRegistry.definition_by_key(CORE_KEY)
	var panel := PartRegistry.definition_by_key(PANEL_KEY)
	if not check_not_null(core, "core resolves by key") or not check_not_null(panel, "panel too"):
		return
	check_eq(core.runtime_id, 1, "the Core Module is manifest entry 0, so id 1")
	check_eq(panel.runtime_id, 2, "the panel is manifest entry 1, so id 2")
	check_eq(PartRegistry.definition(1), core, "id 1 resolves back to the Core Module")
	check_eq(PartRegistry.definition(2), panel, "id 2 resolves back to the panel")


func test_class_buckets_are_populated() -> void:
	var cores := PartRegistry.ids_of_class(PartEnums.PartClass.CORE_MODULE)
	var structural := PartRegistry.ids_of_class(PartEnums.PartClass.STRUCTURAL_COMPONENT)
	check_eq(cores.size(), 1, "one Core Module")
	check_eq(structural.size(), 1, "one Structural Component")
	check_eq(
		PartRegistry.ids_of_class(PartEnums.PartClass.EFFECTOR_MODULE).size(),
		0,
		"no Effector Modules are authored yet, and an empty bucket is not an error"
	)


func test_manifest_hash_is_order_sensitive_and_non_zero() -> void:
	check_ne(PartRegistry.manifest_hash(), 0, "a populated registry hashes to something")

	# The handshake must reject a peer whose manifest lists the same keys in a
	# different order: every part_def_id would disagree.
	var forward := PartManifest.new()
	forward.keys = PackedStringArray([String(CORE_KEY), String(PANEL_KEY)])
	var reversed := PartManifest.new()
	reversed.keys = PackedStringArray([String(PANEL_KEY), String(CORE_KEY)])
	check_eq(
		forward.compute_content_hash(),
		PartRegistry.manifest_hash(),
		"the shipped manifest is core then panel"
	)
	check_ne(
		reversed.compute_content_hash(),
		forward.compute_content_hash(),
		"reordering the manifest must change the handshake hash"
	)


## ===== ROUND TRIP ======================================================

func test_core_module_matches_the_documented_table() -> void:
	var def := PartRegistry.definition_by_key(CORE_KEY)
	if not check_not_null(def, "the Core Module must load"):
		return

	check_eq(def.part_class, PartEnums.PartClass.CORE_MODULE, "class")
	check_eq(def.tier, PartEnums.TierGrade.STANDARD, "t2 is STANDARD")
	check_eq(def.bounds_size_cells, CORE_CELLS, "§10.1 gives 4x3x5 cells")
	check_eq(def.volume_cells, CORE_CELLS.x * CORE_CELLS.y * CORE_CELLS.z, "a solid box")
	check_approx(def.mass_kg, CORE_MASS_KG, "mass")
	check_approx(def.integrity_max, CORE_INTEGRITY, "integrity")
	check_approx(def.armour_rating, CORE_ARMOUR, "armour")
	_check_resistance(def, CORE_RESISTANCE)

	var profile := def.core_profile
	if not check_not_null(profile, "the class payload must survive the round trip"):
		return
	check_approx(profile.power_capacity_pu, CORE_POWER_CAPACITY_PU, "power capacity")
	check_eq(profile.mount_budget, CORE_MOUNT_BUDGET, "mount budget")
	check_approx(profile.speed_cap_mps, CORE_SPEED_CAP_MPS, "speed cap")
	check_approx(profile.mass_tolerance_kg, CORE_MASS_TOLERANCE_KG, "mass tolerance")

	# The Core Module owns the mount budget; spending its own would be circular.
	check_eq(def.mount_weight, 0, "the Core Module costs no mounts")


func test_panel_matches_the_documented_table() -> void:
	var def := PartRegistry.definition_by_key(PANEL_KEY)
	if not check_not_null(def, "the panel must load"):
		return

	check_eq(def.part_class, PartEnums.PartClass.STRUCTURAL_COMPONENT, "class")
	check_eq(def.bounds_size_cells, PANEL_CELLS, "§10.2 gives 4x1x4 cells")
	check_eq(def.volume_cells, PANEL_CELLS.x * PANEL_CELLS.y * PANEL_CELLS.z, "a solid slab")
	check_approx(def.mass_kg, PANEL_MASS_KG, "mass")
	check_approx(def.integrity_max, PANEL_INTEGRITY, "integrity")
	check_approx(def.armour_rating, PANEL_ARMOUR, "armour")
	check_approx(def.load_capacity_kg, PANEL_LOAD_CAPACITY_KG, "load capacity")
	check_eq(def.occlusion, PartEnums.OcclusionProfile.OPAQUE_SOLID, "occlusion")
	_check_resistance(def, PANEL_RESISTANCE)
	check_null(def.class_payload(), "a Structural Component carries no class payload")


## The silent-drop guard: a typed Array[Resource] that fails element validation
## on load comes back empty with nothing logged.
func test_attachment_nodes_survive_serialisation() -> void:
	_check_nodes(CORE_KEY, CORE_NODE_COUNT)
	_check_nodes(PANEL_KEY, PANEL_NODE_COUNT)


func _check_nodes(key: StringName, expected: int) -> void:
	var def := PartRegistry.definition_by_key(key)
	if not check_not_null(def, "%s must load" % key):
		return
	check_eq(def.attachment_nodes.size(), expected, "%s exposes %d cell faces" % [key, expected])

	var faces := {}
	for node in def.attachment_nodes:
		if not check_not_null(node, "%s has a null attachment node" % key):
			continue
		check_true(node.has_axis_normal(), "%s node '%s' faces an axis" % [key, node.node_name])
		check_true(
			def.occupies_local(node.cell),
			"%s node '%s' sits on an occupied cell" % [key, node.node_name]
		)
		faces[node.face_normal] = int(faces.get(node.face_normal, 0)) + 1
	check_eq(faces.size(), 6, "%s carries nodes on all six faces" % key)


func test_collider_primitives_survive_serialisation() -> void:
	for key: StringName in [CORE_KEY, PANEL_KEY]:
		var def := PartRegistry.definition_by_key(key)
		if not check_not_null(def, "%s must load" % key):
			continue
		var profile := def.collider_profile
		if not check_not_null(profile, "%s has a collider profile" % key):
			continue
		check_eq(profile.primitives.size(), 1, "%s is one authored box" % key)
		check_eq(
			profile.primitives[0].kind,
			ColliderPrimitiveDef.PrimitiveKind.BOX,
			"%s uses a BOX primitive" % key
		)
		# §6.2 rule 3 in its own right: a rectangular part has no reason to be
		# approximated, so both parts sit at exactly 100% coverage.
		check_approx(
			profile.total_volume_m3(),
			def.occupancy_volume_m3(),
			"%s collider volume equals its occupancy volume" % key,
			1e-4
		)


## Invariant I-1 as data: the visual side and the collision side are separate
## resources, and neither is derived from the other.
func test_visual_and_collider_are_separate_resources() -> void:
	for key: StringName in [CORE_KEY, PANEL_KEY]:
		var def := PartRegistry.definition_by_key(key)
		if not check_not_null(def, "%s must load" % key):
			continue
		check_not_null(def.visual_profile, "%s has a visual profile" % key)
		check_not_null(def.fusion_profile, "%s has a fusion profile" % key)
		if def.visual_profile == null or def.collider_profile == null:
			continue
		check_ne(
			def.visual_profile.resource_path,
			def.collider_profile.resource_path,
			"%s must keep its visual and its collider in separate files" % key
		)
		check_true(
			def.collider_profile.resource_path.ends_with(".collider.tres"),
			"%s references its collider side-car rather than inlining a copy, so the "
			% key + "collider-baseline gate of doc 13 §7 has a file to hash"
		)


## Both parts ship at PROXY stage with no primitives of their own, so doc 13
## §2.1 mirrors the collider and the greybox is honest about its hitbox.
func test_parts_ship_as_honest_proxies() -> void:
	for key: StringName in [CORE_KEY, PANEL_KEY]:
		var def := PartRegistry.definition_by_key(key)
		if not check_not_null(def, "%s must load" % key):
			continue
		var visual := def.visual_profile
		if visual == null:
			continue
		check_eq(visual.stage, PartVisualProfile.Stage.PROXY, "%s is greybox" % key)
		check_eq(
			visual.proxy_primitives.size(),
			0,
			"%s leaves proxy_primitives empty so the collider is mirrored" % key
		)
		check_false(
			def.fusion_profile.accepts_skirting,
			"%s is a proxy and has no authored edge to run skirting along" % key
		)


func test_report_is_generated_and_deterministic() -> void:
	var first := _validator.report_markdown()
	check_true(first.begins_with("# Part Registry Report"), "the report has its heading")
	check_true(first.contains("CORE_MODULE"), "the report totals the Core Module")
	check_true(first.contains("STRUCTURAL_COMPONENT"), "and the Structural Component")

	# Carries no timestamp, so it diffs as cleanly as the data it describes.
	var again := PartRegistryValidator.new()
	again.validate_registry()
	check_eq(again.report_markdown(), first, "two runs over the same data produce one report")


func _check_resistance(def: PartDefinition, expected: Array[float]) -> void:
	if not check_eq(def.resistance.size(), expected.size(), "resistance channel count"):
		return
	for channel in expected.size():
		check_approx(
			def.resistance[channel],
			expected[channel],
			"§11 resistance for channel %d" % channel,
			1e-5
		)
