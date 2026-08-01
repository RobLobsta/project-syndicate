class_name PartRegistryValidator
extends RefCounted
## The sixteen registry rules of [code]docs/PART_DATA_SCHEMA.md[/code] §14,
## plus the [ColliderProfile] rules of §6.2 that rule 8 defers to.
##
## Run through [code]tools/validate_part_registry.gd[/code] in CI, and over the
## shipped data on every test run by
## [code]tests/integration/test_part_registry_data.gd[/code].
##
## The validator reads the [code].tres[/code] files directly rather than the
## [code]PartRegistry[/code] autoload. It has to report on data the registry
## would reject or silently skip, and it has to run in tools that never build a
## scene tree.
##
## Findings carry the rule number that produced them so a failure names the rule
## it broke rather than only its symptom. A message that says only "invalid"
## gets the rule worked around instead of followed.

## ===== RULE IDS (docs/PART_DATA_SCHEMA.md §14) =========================

const RULE_KEY_GRAMMAR: int = 1
const RULE_MANIFEST: int = 2
const RULE_PIVOT_CELL: int = 3
const RULE_OCCUPANCY_SOLID: int = 4
const RULE_OCCUPANCY_EXTENT: int = 5
const RULE_CLASS_PAYLOAD: int = 6
const RULE_RESISTANCE: int = 7
const RULE_COLLIDER: int = 8
const RULE_NODE_NORMAL: int = 9
const RULE_NODE_CELL: int = 10
const RULE_NODE_UNIQUE: int = 11
const RULE_POSITIVE_SCALARS: int = 12
const RULE_TIER_SCALING: int = 13
const RULE_VISUAL_COLLISION: int = 14
const RULE_CORE_BUDGETS: int = 15
const RULE_EFFECTOR_LIMITS: int = 16
const RULE_MOTIVE_FAMILY_PAYLOAD: int = 17
const RULE_AXLE_KEYING: int = 18
const RULE_ROTOR: int = 19
const RULE_MELEE: int = 20
const RULE_LIMB: int = 21
const RULE_TRACK: int = 22

## ===== RULE CONSTANTS ==================================================

## §5.1 key grammar. The class tags are the seven directory names under
## [code]data/parts/[/code], in [enum PartEnums.PartClass] order.
const CLASS_TAGS: Array[String] = ["core", "str", "mot", "pwr", "eff", "sup", "ctl"]

const KEY_PATTERN: String = (
	"^(core|str|mot|pwr|eff|sup|ctl)\\.[a-z][a-z0-9_]{2,23}\\.[a-z][a-z0-9_]{1,23}\\.t[1-5]$"
)

## §14 rule 5. A part larger than this in any axis would not fit the lattice
## with room to mate on both sides.
const MAX_EXTENT_CELLS: int = 16

## §11. The ceiling exists so that no configuration can achieve immunity.
const MAX_RESISTANCE: float = 0.85

## §12 tier scaling, indexed by [enum PartEnums.TierGrade] minus one.
const TIER_INTEGRITY: Array[float] = [0.62, 1.00, 1.72, 2.48, 3.30]
const TIER_MASS: Array[float] = [0.78, 1.00, 1.38, 1.62, 1.74]
const TIER_ARMOUR: Array[float] = [0.55, 1.00, 1.66, 2.20, 2.72]
const TIER_BUILD_COST: Array[float] = [0.40, 1.00, 2.60, 6.40, 15.0]

## Fractional deviation from the scaling model tolerated without a
## [member PartDefinition.balance_exception_note].
const TIER_TOLERANCE: float = 0.08

## The tier every family's baseline is authored at.
const BASELINE_TIER: PartEnums.TierGrade = PartEnums.TierGrade.STANDARD

## Godot's mesh import suffixes that generate collision. None may appear in the
## name or path of a mesh a part renders — Invariant I-1 admits no exception,
## and a `-col` suffix is the single most likely way one arrives by accident.
const COLLISION_NAME_SUFFIXES: Array[String] = [
	"-col",
	"-convcol",
	"-colonly",
	"-convcolonly",
]

## Metadata keys a collision-generating import leaves behind on the mesh.
const COLLISION_META_KEYS: Array[String] = [
	"_collision",
	"_collision_shape",
	"_create_shape",
]

## Side-car suffixes that live beside a definition and are not definitions.
const PROFILE_SUFFIXES: Array[String] = [".visual.tres", ".collider.tres", ".fusion.tres"]

## §14 rule 15. Below this a Core Module cannot carry a usable loadout.
const MIN_CORE_MOUNT_BUDGET: int = 8

## Parts needed before the integrity-per-kilogram spread carries any signal.
const OUTLIER_MIN_SAMPLE: int = 4

## Distance from the mean, in standard deviations, at which the report calls a
## part out. Not a failure — an outlier is often the point of a part.
const OUTLIER_SIGMA: float = 2.0

## Upper edges of the report's mass buckets, in kilograms.
const MASS_BUCKET_EDGES: Array[float] = [25.0, 50.0, 100.0, 200.0, 400.0, 800.0]

var _failures: PackedStringArray = PackedStringArray()
var _failure_rules: PackedInt32Array = PackedInt32Array()
var _warnings: PackedStringArray = PackedStringArray()
var _definitions: Array[PartDefinition] = []


## Loads and validates every definition the manifest names, plus the manifest
## itself. Returns true when nothing failed. Warnings do not affect the result.
func validate_registry(manifest_path: String = PartRegistryService.MANIFEST_PATH) -> bool:
	_failures.clear()
	_failure_rules.clear()
	_warnings.clear()
	_definitions.clear()

	var manifest: PartManifest = ResourceLoader.load(manifest_path) as PartManifest
	if manifest == null:
		_fail(RULE_MANIFEST, manifest_path, "manifest missing or not a PartManifest")
		return false

	_check_manifest_keys(manifest)
	for i in manifest.keys.size():
		var key := StringName(manifest.keys[i])
		var path := PartManifest.definition_path(key)
		var def: PartDefinition = ResourceLoader.load(path) as PartDefinition
		if def == null:
			_fail(RULE_MANIFEST, key, "no PartDefinition at %s" % path)
			continue
		if def.part_key != key:
			_fail(
				RULE_MANIFEST,
				key,
				"%s declares part_key '%s'; manifest entry %d says '%s'"
				% [path, def.part_key, i, key]
			)
			continue
		def._bake_derived_fields()
		_definitions.push_back(def)
		validate_definition(def)

	_check_for_unlisted_definitions(manifest)
	_check_tier_scaling()
	return _failures.is_empty()


## Every per-part rule. Public so a test can drive a synthetic definition through
## the same code CI runs, rather than through a reimplementation of it.
##
## The caller is responsible for having baked [param def]; [method
## validate_registry] does so before calling here.
func validate_definition(def: PartDefinition) -> void:
	_check_key_grammar(def)
	_check_occupancy(def)
	_check_class_payload(def)
	_check_resistance(def)
	_check_collider(def)
	_check_attachment_nodes(def)
	_check_positive_scalars(def)
	_check_visual_collision(def)
	_check_core_budgets(def)
	_check_effector_limits(def)
	_check_motive_family_payload(def)
	_check_axle_keying(def)
	_check_rotor(def)
	_check_melee(def)
	_check_limb(def)
	_check_track(def)


func failures() -> PackedStringArray:
	return _failures


func warnings() -> PackedStringArray:
	return _warnings


## Definitions loaded by the last [method validate_registry], in manifest order.
func definitions() -> Array[PartDefinition]:
	return _definitions


## True when any failure came from [param rule]. Used by the unit tests to assert
## that a planted fault trips the rule it is supposed to trip and no other.
func failed_rule(rule: int) -> bool:
	return _failure_rules.has(rule)


## The distinct rules that failed, ascending. Deterministic ordering so a
## test can compare against a literal.
func failed_rules() -> PackedInt32Array:
	var out := PackedInt32Array()
	for r in _failure_rules:
		if not out.has(r):
			out.push_back(r)
	out.sort()
	return out


## Clears state between definitions in a test. [method validate_registry] does
## this itself.
func reset() -> void:
	_failures.clear()
	_failure_rules.clear()
	_warnings.clear()
	_definitions.clear()


## ===== RULE 1 — KEY GRAMMAR ============================================

func _check_key_grammar(def: PartDefinition) -> void:
	var key := String(def.part_key)
	var re := RegEx.create_from_string(KEY_PATTERN)
	if re == null or re.search(key) == null:
		_fail(
			RULE_KEY_GRAMMAR,
			def.part_key,
			"key does not match §5.1 grammar "
			+ "class_tag.family.variant.tier_tag (e.g. str.panel.medium.t2)"
		)
		return

	var segments := key.split(".")
	var expected_tag := CLASS_TAGS[int(def.part_class)]
	if segments[0] != expected_tag:
		_fail(
			RULE_KEY_GRAMMAR,
			def.part_key,
			"class tag '%s' contradicts part_class %s, whose tag is '%s'"
			% [segments[0], _class_label(def.part_class), expected_tag]
		)

	var key_tier := int(segments[3].substr(1))
	if key_tier != int(def.tier):
		_fail(
			RULE_KEY_GRAMMAR,
			def.part_key,
			"tier tag '%s' contradicts tier field %d" % [segments[3], int(def.tier)]
		)


## ===== RULE 2 — MANIFEST ===============================================

func _check_manifest_keys(manifest: PartManifest) -> void:
	var seen := {}
	for i in manifest.keys.size():
		var key: String = manifest.keys[i]
		if seen.has(key):
			_fail(
				RULE_MANIFEST,
				key,
				"duplicated in the manifest at entries %d and %d; part_def_id must be unique"
				% [int(seen[key]), i]
			)
			continue
		seen[key] = i


## A definition on disk that no manifest entry names has no `part_def_id`, so it
## can never be placed, saved, or replicated. It is almost always a manifest
## append that was forgotten.
func _check_for_unlisted_definitions(manifest: PartManifest) -> void:
	var listed := {}
	for key in manifest.keys:
		listed[key] = true

	for tag in CLASS_TAGS:
		var dir_path := "%s/%s" % [PartManifest.PARTS_DIR, tag]
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		var names := PackedStringArray(dir.get_files())
		names.sort()
		for file_name in names:
			var key := _definition_key_from_file(file_name)
			if key.is_empty() or listed.has(key):
				continue
			_fail(
				RULE_MANIFEST,
				key,
				"%s/%s is not listed in the manifest; append it so the part gets an id"
				% [dir_path, file_name]
			)


## The part key a file name denotes, or "" when the file is a profile side-car,
## an import artefact, or anything else that is not a definition.
static func _definition_key_from_file(file_name: String) -> String:
	var name := file_name.trim_suffix(".remap")
	if not name.ends_with(".tres"):
		return ""
	for suffix in PROFILE_SUFFIXES:
		if name.ends_with(suffix):
			return ""
	return name.trim_suffix(".tres")


## ===== RULES 3, 4, 5 — OCCUPANCY =======================================

func _check_occupancy(def: PartDefinition) -> void:
	if def.occupancy_cells.is_empty():
		_fail(RULE_PIVOT_CELL, def.part_key, "occupancy_cells is empty; the pivot cell is required")
		return

	var seen := {}
	var has_pivot := false
	for c in def.occupancy_cells:
		var ci := Vector3i(int(c.x), int(c.y), int(c.z))
		if ci == Vector3i.ZERO:
			has_pivot = true
		if seen.has(ci):
			_fail(
				RULE_OCCUPANCY_SOLID,
				def.part_key,
				"cell %v appears more than once in occupancy_cells" % ci
			)
			continue
		seen[ci] = true

	if not has_pivot:
		_fail(
			RULE_PIVOT_CELL,
			def.part_key,
			"occupancy_cells must contain the pivot cell (0, 0, 0); "
			+ "every frame conversion is relative to it"
		)

	_check_six_connected(def, seen)

	var size := def.bounds_size_cells
	if size.x > MAX_EXTENT_CELLS or size.y > MAX_EXTENT_CELLS or size.z > MAX_EXTENT_CELLS:
		_fail(
			RULE_OCCUPANCY_EXTENT,
			def.part_key,
			"occupancy extent %v exceeds the %d-cell limit on at least one axis"
			% [size, MAX_EXTENT_CELLS]
		)


## A part must be one contiguous solid. A disjoint footprint would place cells
## the Chassis Graph can never reach, so damage could never detach them and the
## fusion SDF would blend across empty space.
func _check_six_connected(def: PartDefinition, occupied: Dictionary) -> void:
	if occupied.is_empty():
		return

	var keys := occupied.keys()
	var start: Vector3i = keys[0]
	var reached := {start: true}
	var frontier: Array[Vector3i] = [start]
	while not frontier.is_empty():
		var cell: Vector3i = frontier.pop_back()
		for face in AttachmentNodeDef.AXIS_NORMALS:
			var next: Vector3i = cell + face
			if reached.has(next) or not occupied.has(next):
				continue
			reached[next] = true
			frontier.push_back(next)

	if reached.size() != occupied.size():
		_fail(
			RULE_OCCUPANCY_SOLID,
			def.part_key,
			"occupancy_cells is not 6-connected: %d of %d cells are unreachable from %v"
			% [occupied.size() - reached.size(), occupied.size(), start]
		)


## ===== RULE 6 — CLASS PAYLOAD ==========================================

func _check_class_payload(def: PartDefinition) -> void:
	var present: Array[String] = []
	if def.core_profile != null:
		present.push_back("core_profile")
	if def.motive_profile != null:
		present.push_back("motive_profile")
	if def.power_profile != null:
		present.push_back("power_profile")
	if def.effector_profile != null:
		present.push_back("effector_profile")
	if def.support_profile != null:
		present.push_back("support_profile")
	if def.control_profile != null:
		present.push_back("control_profile")

	if present.size() > 1:
		_fail(
			RULE_CLASS_PAYLOAD,
			def.part_key,
			"%d class profiles are non-null (%s); exactly one may be, matching part_class"
			% [present.size(), ", ".join(present)]
		)
		return

	# A Structural Component carries no class payload by design, which is why
	# there is no structural_profile field to hold one.
	if def.part_class == PartEnums.PartClass.STRUCTURAL_COMPONENT:
		if not present.is_empty():
			_fail(
				RULE_CLASS_PAYLOAD,
				def.part_key,
				"STRUCTURAL_COMPONENT carries %s; structural parts have no class payload"
				% present[0]
			)
		return

	if def.class_payload() == null:
		_fail(
			RULE_CLASS_PAYLOAD,
			def.part_key,
			"part_class %s has no matching class profile" % _class_label(def.part_class)
		)


## ===== RULE 7 — RESISTANCE =============================================

func _check_resistance(def: PartDefinition) -> void:
	if def.resistance.size() != PartEnums.DAMAGE_CHANNEL_COUNT:
		_fail(
			RULE_RESISTANCE,
			def.part_key,
			"resistance has %d entries; DamageChannel has %d"
			% [def.resistance.size(), PartEnums.DAMAGE_CHANNEL_COUNT]
		)
		return

	for channel in def.resistance.size():
		var value := def.resistance[channel]
		# Both bounds are inclusive, and `resistance` is a PackedFloat32Array:
		# an authored 0.85 reads back as 0.85000002, so a bare `>` would reject
		# the exact ceiling the tables are written to.
		var under := value < 0.0 and not is_zero_approx(value)
		var over := value > MAX_RESISTANCE and not is_equal_approx(value, MAX_RESISTANCE)
		if under or over:
			_fail(
				RULE_RESISTANCE,
				def.part_key,
				"resistance[%s] is %.3f; the range is [0.0, %.2f] so no part is immune"
				% [_channel_name(channel), value, MAX_RESISTANCE]
			)


## ===== RULE 8 — COLLIDER (§6.2) ========================================

func _check_collider(def: PartDefinition) -> void:
	var profile := def.collider_profile
	if profile == null:
		_fail(
			RULE_COLLIDER,
			def.part_key,
			"collider_profile is null; ColliderProfile is the only source of "
			+ "Assembly collision geometry (Invariant I-1)"
		)
		return

	var count := profile.primitives.size()
	if count < 1 or count > ColliderProfile.MAX_PRIMITIVES_PER_PART:
		_fail(
			RULE_COLLIDER,
			def.part_key,
			"collider has %d primitives; §6.2 permits 1 to %d"
			% [count, ColliderProfile.MAX_PRIMITIVES_PER_PART]
		)
		return

	for i in count:
		var prim := profile.primitives[i]
		if prim == null:
			_fail(RULE_COLLIDER, def.part_key, "collider primitive %d is null" % i)
			continue
		if int(prim.kind) < 0 or int(prim.kind) > int(ColliderPrimitiveDef.PrimitiveKind.SPHERE):
			_fail(
				RULE_COLLIDER,
				def.part_key,
				"collider primitive %d has kind %d; only BOX, CYLINDER, CAPSULE and "
				% [i, int(prim.kind)] + "SPHERE are permitted on an Assembly part"
			)
			continue
		_check_primitive_euler(def, i, prim)

	_check_collider_coverage(def, profile)


## Oriented primitives must land on the same basis on every platform, so the
## authored angles are restricted to a step that survives any trig path.
func _check_primitive_euler(def: PartDefinition, index: int, prim: ColliderPrimitiveDef) -> void:
	var euler := prim.local_basis_euler_deg
	var axes: PackedFloat32Array = PackedFloat32Array([euler.x, euler.y, euler.z])
	var names: Array[String] = ["x", "y", "z"]
	for a in axes.size():
		var degrees := axes[a]
		var steps := degrees / ColliderPrimitiveDef.EULER_STEP_DEG
		if not is_equal_approx(steps, roundf(steps)):
			_fail(
				RULE_COLLIDER,
				def.part_key,
				"collider primitive %d has local_basis_euler_deg.%s = %.4f; "
				% [index, names[a], degrees]
				+ "components must be multiples of %.0f°" % ColliderPrimitiveDef.EULER_STEP_DEG
			)


## §6.2 rule 3. Too little coverage is a "phantom gap" a shot passes through;
## too much is an invisible hitbox around the part.
func _check_collider_coverage(def: PartDefinition, profile: ColliderProfile) -> void:
	var occupancy := def.occupancy_volume_m3()
	if occupancy <= 0.0:
		return  # Rule 3 has already reported the empty occupancy.

	var ratio := profile.total_volume_m3() / occupancy
	if ratio < ColliderProfile.MIN_COVERAGE_RATIO or ratio > ColliderProfile.MAX_COVERAGE_RATIO:
		_fail(
			RULE_COLLIDER,
			def.part_key,
			"collider covers %.1f%% of the %.4f m³ occupancy; §6.2 requires %.0f%%–%.0f%%"
			% [
				ratio * 100.0,
				occupancy,
				ColliderProfile.MIN_COVERAGE_RATIO * 100.0,
				ColliderProfile.MAX_COVERAGE_RATIO * 100.0,
			]
		)


## ===== RULES 9, 10, 11 — ATTACHMENT NODES ==============================

func _check_attachment_nodes(def: PartDefinition) -> void:
	var seen := {}
	for i in def.attachment_nodes.size():
		var node := def.attachment_nodes[i]
		if node == null:
			_fail(RULE_NODE_NORMAL, def.part_key, "attachment node %d is null" % i)
			continue

		if not node.has_axis_normal():
			_fail(
				RULE_NODE_NORMAL,
				def.part_key,
				"node '%s' has face_normal %v; only the six axis units mate, because "
				% [node.node_name, node.face_normal]
				+ "diagonal joints would cost the lattice solver its O(1) placement query"
			)
			continue

		if not def.occupies_local(node.cell):
			_fail(
				RULE_NODE_CELL,
				def.part_key,
				"node '%s' sits on cell %v, which is not in occupancy_cells"
				% [node.node_name, node.cell]
			)

		var face_key := Vector4i(node.cell.x, node.cell.y, node.cell.z, _face_index(node.face_normal))
		if seen.has(face_key):
			_fail(
				RULE_NODE_UNIQUE,
				def.part_key,
				"nodes '%s' and '%s' share cell %v face %v; one face mates once"
				% [String(seen[face_key]), node.node_name, node.cell, node.face_normal]
			)
			continue
		seen[face_key] = node.node_name


## ===== RULE 12 — POSITIVE SCALARS ======================================

func _check_positive_scalars(def: PartDefinition) -> void:
	if def.mass_kg <= 0.0:
		_fail(
			RULE_POSITIVE_SCALARS,
			def.part_key,
			"mass_kg is %.3f; a massless part inverts the Assembly inertia tensor" % def.mass_kg
		)
	if def.integrity_max <= 0.0:
		_fail(
			RULE_POSITIVE_SCALARS,
			def.part_key,
			"integrity_max is %.3f; a part with no integrity is destroyed on spawn"
			% def.integrity_max
		)


## ===== RULE 13 — TIER SCALING (§12) ====================================

## Compares every family's tier variants against its Tier-2 baseline. Grouped on
## `class_tag.family.variant`, because §10 authors distinct variants of one
## family — `str.panel.light` against `str.panel.heavy` — with deliberately
## unrelated numbers, and only a variant's own tier ladder is expected to scale.
func _check_tier_scaling() -> void:
	var groups := {}
	for def in _definitions:
		var group := _variant_group(def.part_key)
		if group.is_empty():
			continue  # Rule 1 has already reported the malformed key.
		var members: Array[PartDefinition] = groups.get(group, [] as Array[PartDefinition])
		members.push_back(def)
		groups[group] = members

	var names := groups.keys()
	names.sort()
	for group: String in names:
		var members: Array[PartDefinition] = groups[group]
		if members.size() < 2:
			continue  # A lone tier has nothing to scale against.

		var baseline: PartDefinition = null
		for def in members:
			if def.tier == BASELINE_TIER:
				baseline = def
				break
		if baseline == null:
			_warn(
				"%s has %d tier variants but no Tier-2 baseline; §12 scaling is unchecked"
				% [group, members.size()]
			)
			continue

		for def in members:
			if def == baseline:
				continue
			_check_tier_member(def, baseline)


func _check_tier_member(def: PartDefinition, baseline: PartDefinition) -> void:
	var t := int(def.tier) - 1
	_check_tier_value(
		def, "integrity_max", def.integrity_max, baseline.integrity_max * TIER_INTEGRITY[t]
	)
	_check_tier_value(def, "mass_kg", def.mass_kg, baseline.mass_kg * TIER_MASS[t])
	_check_tier_value(
		def, "armour_rating", def.armour_rating, baseline.armour_rating * TIER_ARMOUR[t]
	)
	_check_tier_value(
		def, "build_cost", float(def.build_cost), float(baseline.build_cost) * TIER_BUILD_COST[t]
	)


func _check_tier_value(def: PartDefinition, field: String, actual: float, expected: float) -> void:
	if is_zero_approx(expected):
		return  # A baseline of zero (an unarmoured family) scales to zero at every tier.
	var deviation := actual / expected - 1.0
	if absf(deviation) <= TIER_TOLERANCE:
		return
	if not def.balance_exception_note.is_empty():
		return  # Recorded in the report instead; §12 requires it be reviewable, not absent.
	_fail(
		RULE_TIER_SCALING,
		def.part_key,
		"%s is %.2f, %+.1f%% off the §12 model's %.2f for tier %d; "
		% [field, actual, deviation * 100.0, expected, int(def.tier)]
		+ "deviations beyond ±%.0f%% need a balance_exception_note" % (TIER_TOLERANCE * 100.0)
	)


## ===== RULE 14 — VISUAL COLLISION ======================================

## Invariant I-1: no collision shape is ever generated from a visual mesh. This
## catches the mesh arriving pre-poisoned from import, which is the one route
## that bypasses every runtime guard.
func _check_visual_collision(def: PartDefinition) -> void:
	var vp := def.visual_profile
	if vp == null:
		_warn(
			"%s has no visual_profile; it cannot be rendered and validate_part_visuals "
			% def.part_key + "will reject it"
		)
		return

	var meshes: Array[Mesh] = [vp.blockout_mesh, vp.mesh_nominal, vp.mesh_impaired, vp.mesh_critical]
	var labels: Array[String] = ["blockout_mesh", "mesh_nominal", "mesh_impaired", "mesh_critical"]
	for i in meshes.size():
		var mesh := meshes[i]
		if mesh == null:
			continue
		_check_mesh_is_collision_free(def, labels[i], mesh)


func _check_mesh_is_collision_free(def: PartDefinition, label: String, mesh: Mesh) -> void:
	var identifiers: Array[String] = [mesh.resource_name, mesh.resource_path]
	for identifier in identifiers:
		var lowered := identifier.to_lower()
		for suffix in COLLISION_NAME_SUFFIXES:
			if not lowered.contains(suffix):
				continue
			_fail(
				RULE_VISUAL_COLLISION,
				def.part_key,
				"%s '%s' carries the '%s' import suffix, which generates collision; "
				% [label, identifier, suffix]
				+ "colliders come from ColliderProfile and nowhere else"
			)
			return

	for meta_key in COLLISION_META_KEYS:
		if not mesh.has_meta(meta_key):
			continue
		_fail(
			RULE_VISUAL_COLLISION,
			def.part_key,
			"%s carries collision metadata '%s'; a rendered mesh never produces collision"
			% [label, meta_key]
		)
		return


## ===== RULE 15 — CORE BUDGETS ==========================================

func _check_core_budgets(def: PartDefinition) -> void:
	if def.part_class != PartEnums.PartClass.CORE_MODULE:
		return
	var profile := def.core_profile
	if profile == null:
		return  # Rule 6 has already reported the missing payload.

	if profile.mount_budget < MIN_CORE_MOUNT_BUDGET:
		_fail(
			RULE_CORE_BUDGETS,
			def.part_key,
			"mount_budget is %d; below %d an Assembly cannot carry a usable loadout"
			% [profile.mount_budget, MIN_CORE_MOUNT_BUDGET]
		)
	if profile.power_capacity_pu <= 0.0:
		_fail(
			RULE_CORE_BUDGETS,
			def.part_key,
			"power_capacity_pu is %.2f; a Core Module with no capacity powers nothing"
			% profile.power_capacity_pu
		)


## ===== RULE 16 — EFFECTOR LIMITS =======================================

func _check_effector_limits(def: PartDefinition) -> void:
	if def.part_class != PartEnums.PartClass.EFFECTOR_MODULE:
		return
	var profile := def.effector_profile
	if profile == null:
		return  # Rule 6 has already reported the missing payload.

	if profile.yaw_limit_deg.x > profile.yaw_limit_deg.y:
		_fail(
			RULE_EFFECTOR_LIMITS,
			def.part_key,
			"yaw_limit_deg is (%.1f, %.1f); the minimum exceeds the maximum, so the "
			% [profile.yaw_limit_deg.x, profile.yaw_limit_deg.y]
			+ "arc sampler traverses nothing"
		)
	if profile.pitch_limit_deg.x > profile.pitch_limit_deg.y:
		_fail(
			RULE_EFFECTOR_LIMITS,
			def.part_key,
			"pitch_limit_deg is (%.1f, %.1f); the minimum exceeds the maximum"
			% [profile.pitch_limit_deg.x, profile.pitch_limit_deg.y]
		)


## ===== RULE 17 — MOTIVE FAMILY PAYLOAD =================================

## Fields on [MotiveAssemblyProfile] that describe a passive ground suspension.
## Zero on every family that does not have one.
const SUSPENSION_FIELDS: Array[String] = [
	"suspension_rest_length_m",
	"suspension_stiffness_n_m",
	"suspension_damping_ns_m",
	"suspension_travel_limit_m",
]


func _check_motive_family_payload(def: PartDefinition) -> void:
	if def.part_class != PartEnums.PartClass.MOTIVE_ASSEMBLY:
		return
	var profile := def.motive_profile
	if profile == null:
		return  # Rule 6 has already reported the missing payload.

	var present := 0
	if profile.rotor_profile != null:
		present += 1
	if profile.limb_profile != null:
		present += 1
	if profile.track_profile != null:
		present += 1
	if present > 1:
		_fail(
			RULE_MOTIVE_FAMILY_PAYLOAD,
			def.part_key,
			"carries %d family payloads; exactly one matches the kind" % present
		)

	var expected := profile.family_payload()
	match profile.kind:
		PartEnums.MotiveKind.ROTOR_DISC, PartEnums.MotiveKind.AMBULATORY_LIMB, \
		PartEnums.MotiveKind.TRACKED_SEGMENT:
			if expected == null:
				_fail(
					RULE_MOTIVE_FAMILY_PAYLOAD,
					def.part_key,
					"kind %d requires a family payload and carries none" % profile.kind
				)
		_:
			if present > 0:
				_fail(
					RULE_MOTIVE_FAMILY_PAYLOAD,
					def.part_key,
					"kind %d takes no family payload but carries one" % profile.kind
				)


## ===== RULE 18 — AXLE KEYING ===========================================

## §4.2: AXLE mates only with AXLE, so a station that accepted anything would
## make the polarity a slower FACE_NEUTRAL. A Structural Component offering one
## must key it to Motive Assemblies; a Motive Assembly's own drive face needs no
## restriction, because the station it mates with already carries it.
func _check_axle_keying(def: PartDefinition) -> void:
	for node: AttachmentNodeDef in def.attachment_nodes:
		if node.polarity != PartEnums.AttachmentPolarity.AXLE:
			continue
		if def.part_class == PartEnums.PartClass.MOTIVE_ASSEMBLY:
			continue
		if def.part_class != PartEnums.PartClass.STRUCTURAL_COMPONENT:
			_fail(
				RULE_AXLE_KEYING,
				def.part_key,
				(
					"node '%s' is AXLE on a part of class %d; only Motive Assemblies "
					% [node.node_name, def.part_class]
				)
				+ "and Structural Components may carry one"
			)
			continue
		if node.accepts_classes != PackedInt32Array(
			[PartEnums.PartClass.MOTIVE_ASSEMBLY]
		):
			_fail(
				RULE_AXLE_KEYING,
				def.part_key,
				(
					"node '%s' is an AXLE station but does not restrict accepts_classes "
					% node.node_name
				)
				+ "to MOTIVE_ASSEMBLY, so anything could be bolted to a drive station"
			)


## ===== RULE 19 — ROTOR =================================================

## §14 rule 19: maximum thrust must match rated load this closely. A rotor that
## cannot lift its own rating presents as an Assembly that silently refuses to
## leave the ground, with nothing in the logs.
const ROTOR_THRUST_TOLERANCE: float = 0.01


func _check_rotor(def: PartDefinition) -> void:
	if def.part_class != PartEnums.PartClass.MOTIVE_ASSEMBLY:
		return
	var profile := def.motive_profile
	if profile == null or profile.kind != PartEnums.MotiveKind.ROTOR_DISC:
		return

	_fail_if_nonzero(RULE_ROTOR, def, profile, "traction_coefficient", "a disc touches nothing")
	_fail_if_nonzero(RULE_ROTOR, def, profile, "rolling_resistance", "a disc does not roll")
	_fail_if_nonzero(RULE_ROTOR, def, profile, "max_steer_angle_deg", "a disc steers by cyclic")
	for field: String in SUSPENSION_FIELDS:
		_fail_if_nonzero(RULE_ROTOR, def, profile, field, "a disc has no suspension")

	var rotor := profile.rotor_profile
	if rotor == null:
		return  # Rule 17 has already reported it.

	if rotor.disc_radius_m <= 0.0:
		_fail(RULE_ROTOR, def.part_key, "disc_radius_m is %.3f" % rotor.disc_radius_m)
	if rotor.blade_count < 2:
		_fail(RULE_ROTOR, def.part_key, "blade_count is %d" % rotor.blade_count)
	if rotor.spin_sign != 1 and rotor.spin_sign != -1:
		_fail(RULE_ROTOR, def.part_key, "spin_sign is %d; must be +1 or -1" % rotor.spin_sign)
	if rotor.nominal_rad_s <= 0.0:
		_fail(RULE_ROTOR, def.part_key, "nominal_rad_s is %.3f" % rotor.nominal_rad_s)
	if rotor.collective_limit_deg.x > rotor.collective_limit_deg.y:
		_fail(
			RULE_ROTOR,
			def.part_key,
			(
				"collective_limit_deg is (%.1f, %.1f); the minimum exceeds the maximum"
				% [rotor.collective_limit_deg.x, rotor.collective_limit_deg.y]
			)
		)
	if rotor.torque_reaction_ratio < 0.0 or rotor.torque_reaction_ratio > 1.0:
		_fail(
			RULE_ROTOR,
			def.part_key,
			"torque_reaction_ratio is %.3f; outside [0, 1]" % rotor.torque_reaction_ratio
		)

	var required := profile.rated_load_kg * SyndicateConstants.GRAVITY_MPS2
	var actual := rotor.max_thrust_n()
	if required > 0.0 and absf(actual - required) / required > ROTOR_THRUST_TOLERANCE:
		_fail(
			RULE_ROTOR,
			def.part_key,
			(
				"max thrust is %.0f N against a rated load of %.0f N (%.1f%% out); "
				% [actual, required, 100.0 * (actual - required) / required]
			)
			+ "a disc that cannot lift its rating silently refuses to fly"
		)


## ===== RULE 20 — MELEE =================================================

## Emission fields that must be zero on a module that emits nothing.
const MELEE_ZERO_FIELDS: Array[String] = [
	"muzzle_velocity_mps",
	"cycle_time_s",
	"recoil_impulse_ns",
	"spread_bloom_deg",
]

const MELEE_MIX_TOLERANCE: float = 0.001


func _check_melee(def: PartDefinition) -> void:
	if def.part_class != PartEnums.PartClass.EFFECTOR_MODULE:
		return
	var profile := def.effector_profile
	if profile == null:
		return  # Rule 6 has already reported the missing payload.

	if not profile.is_melee():
		if profile.melee_profile != null:
			_fail(
				RULE_MELEE,
				def.part_key,
				"kind %d is not melee but carries a melee_profile" % profile.kind
			)
		return

	for field: String in MELEE_ZERO_FIELDS:
		_fail_if_nonzero(RULE_MELEE, def, profile, field, "a melee module emits nothing")
	if profile.magazine_rounds != 0:
		_fail(
			RULE_MELEE,
			def.part_key,
			"magazine_rounds is %d; a melee module consumes no ammunition"
			% profile.magazine_rounds
		)

	var melee := profile.melee_profile
	if melee == null:
		_fail(RULE_MELEE, def.part_key, "melee kind %d carries no melee_profile" % profile.kind)
		return

	if melee.channel_mix.size() != PartEnums.DAMAGE_CHANNEL_COUNT:
		_fail(
			RULE_MELEE,
			def.part_key,
			"channel_mix has %d entries; expected %d"
			% [melee.channel_mix.size(), PartEnums.DAMAGE_CHANNEL_COUNT]
		)
	elif absf(melee.channel_mix_sum() - 1.0) > MELEE_MIX_TOLERANCE:
		_fail(
			RULE_MELEE,
			def.part_key,
			(
				"channel_mix sums to %.4f; a mix that is not 1.0 silently scales every "
				% melee.channel_mix_sum()
			)
			+ "strike this part ever lands"
		)
	var target_cap := MeleeSolver.MAX_TARGETS_PER_SWING
	if melee.max_targets_per_swing < 1 or melee.max_targets_per_swing > target_cap:
		_fail(
			RULE_MELEE,
			def.part_key,
			"max_targets_per_swing is %d; outside [1, %d]"
			% [melee.max_targets_per_swing, MeleeSolver.MAX_TARGETS_PER_SWING]
		)
	if melee.swing_samples < 2 or melee.swing_samples > MeleeSolver.MAX_SWING_SAMPLES:
		_fail(
			RULE_MELEE,
			def.part_key,
			"swing_samples is %d; outside [2, %d]"
			% [melee.swing_samples, MeleeSolver.MAX_SWING_SAMPLES]
		)
	if melee.reaction_ratio < 0.0 or melee.reaction_ratio > 1.0:
		_fail(
			RULE_MELEE,
			def.part_key,
			"reaction_ratio is %.3f; outside [0, 1]" % melee.reaction_ratio
		)


## ===== RULE 21 — LIMB ==================================================

func _check_limb(def: PartDefinition) -> void:
	if def.part_class != PartEnums.PartClass.MOTIVE_ASSEMBLY:
		return
	var profile := def.motive_profile
	if profile == null or profile.kind != PartEnums.MotiveKind.AMBULATORY_LIMB:
		return

	for field: String in SUSPENSION_FIELDS:
		_fail_if_nonzero(
			RULE_LIMB, def, profile, field, "a limb's compliance is commanded, not passive"
		)

	var limb := profile.limb_profile
	if limb == null:
		return  # Rule 17 has already reported it.

	if limb.duty_factor <= 0.0 or limb.duty_factor >= 1.0:
		_fail(
			RULE_LIMB, def.part_key, "duty_factor is %.3f; outside (0, 1)" % limb.duty_factor
		)
	if limb.leg_length_m <= 0.0:
		_fail(RULE_LIMB, def.part_key, "leg_length_m is %.3f" % limb.leg_length_m)
	if limb.stance_height_ratio <= 0.0 or limb.stance_height_ratio > 1.0:
		_fail(
			RULE_LIMB,
			def.part_key,
			"stance_height_ratio is %.3f; outside (0, 1]" % limb.stance_height_ratio
		)
	if limb.max_cadence_hz < limb.nominal_cadence_hz:
		_fail(
			RULE_LIMB,
			def.part_key,
			"max_cadence_hz %.2f is below nominal_cadence_hz %.2f"
			% [limb.max_cadence_hz, limb.nominal_cadence_hz]
		)
	if limb.max_step_length_m > 2.0 * limb.leg_length_m:
		_fail(
			RULE_LIMB,
			def.part_key,
			(
				"max_step_length_m %.3f exceeds twice leg_length_m %.3f; such a step "
				% [limb.max_step_length_m, limb.leg_length_m]
			)
			+ "cannot be taken with a foot on the ground at either end of it"
		)


## ===== RULE 22 — TRACK =================================================

func _check_track(def: PartDefinition) -> void:
	if def.part_class != PartEnums.PartClass.MOTIVE_ASSEMBLY:
		return
	var profile := def.motive_profile
	if profile == null or profile.kind != PartEnums.MotiveKind.TRACKED_SEGMENT:
		return

	_fail_if_nonzero(
		RULE_TRACK,
		def,
		profile,
		"max_steer_angle_deg",
		"a track steers by differential drive; one that angled its hub would be a wheel"
	)

	var track := profile.track_profile
	if track == null:
		return  # Rule 17 has already reported it.

	if track.road_stations < 1 or track.road_stations > TrackProfile.MAX_ROAD_STATIONS:
		_fail(
			RULE_TRACK,
			def.part_key,
			"road_stations is %d; outside [1, %d]"
			% [track.road_stations, TrackProfile.MAX_ROAD_STATIONS]
		)
	if track.patch_length_m <= 0.0:
		_fail(RULE_TRACK, def.part_key, "patch_length_m is %.3f" % track.patch_length_m)
	if track.differential_authority < 0.0 or track.differential_authority > 1.0:
		_fail(
			RULE_TRACK,
			def.part_key,
			"differential_authority is %.3f; outside [0, 1]" % track.differential_authority
		)
	if track.internal_loss < 0.0 or track.internal_loss >= 1.0:
		_fail(
			RULE_TRACK,
			def.part_key,
			"internal_loss is %.3f; outside [0, 1)" % track.internal_loss
		)
	if track.lateral_grip_ratio <= 0.0:
		_fail(
			RULE_TRACK,
			def.part_key,
			"lateral_grip_ratio is %.3f; a track with no lateral grip slides sideways "
			% track.lateral_grip_ratio
			+ "without limit"
		)


## Reports [param field] on [param profile] when it is not zero.
##
## The zero-field checks of rules 19, 20, 21, and 22 are all the same shape: a
## family that has no use for a field must leave it at zero rather than carrying
## a plausible-looking value no code reads, because the next author to read the
## data cannot tell the difference.
func _fail_if_nonzero(
	rule: int, def: PartDefinition, profile: Resource, field: String, reason: String
) -> void:
	var value: float = profile.get(field)
	if is_zero_approx(value):
		return
	_fail(rule, def.part_key, "%s is %.4f but must be zero: %s" % [field, value, reason])


## ===== REPORT (§14) ====================================================

## The review artefact for any balance change: totals per class, the mass
## distribution, integrity-per-kilogram outliers, and every exception note.
##
## Carries no timestamp, so two runs over the same data produce byte-identical
## output and the report diffs as cleanly as the data it describes.
func report_markdown() -> String:
	var lines := PackedStringArray()
	lines.append("# Part Registry Report")
	lines.append("")
	lines.append("%d parts, %d failures, %d warnings."
			% [_definitions.size(), _failures.size(), _warnings.size()])
	lines.append("")

	_append_class_totals(lines)
	_append_mass_histogram(lines)
	_append_integrity_outliers(lines)
	_append_exception_notes(lines)
	_append_findings(lines)
	return "\n".join(lines) + "\n"


func _append_class_totals(lines: PackedStringArray) -> void:
	lines.append("## Totals by class")
	lines.append("")
	lines.append("| Class | Parts | Total mass (kg) | Mean integrity | Mean armour |")
	lines.append("|---|---:|---:|---:|---:|")
	for part_class in PartEnums.PART_CLASS_COUNT:
		var count := 0
		var mass := 0.0
		var integrity := 0.0
		var armour := 0.0
		for def in _definitions:
			if int(def.part_class) != part_class:
				continue
			count += 1
			mass += def.mass_kg
			integrity += def.integrity_max
			armour += def.armour_rating
		if count == 0:
			continue
		lines.append("| `%s` | %d | %.1f | %.1f | %.1f |"
				% [_class_label(part_class), count, mass, integrity / count, armour / count])
	lines.append("")


func _append_mass_histogram(lines: PackedStringArray) -> void:
	lines.append("## Mass distribution")
	lines.append("")
	var counts := PackedInt32Array()
	counts.resize(MASS_BUCKET_EDGES.size() + 1)
	counts.fill(0)
	for def in _definitions:
		counts[_mass_bucket(def.mass_kg)] += 1

	for i in counts.size():
		var label := (
			"%8.0f+   " % MASS_BUCKET_EDGES[MASS_BUCKET_EDGES.size() - 1]
			if i == MASS_BUCKET_EDGES.size()
			else "%8.0f–%-4.0f" % [0.0 if i == 0 else MASS_BUCKET_EDGES[i - 1], MASS_BUCKET_EDGES[i]]
		)
		lines.append("    %s kg | %s %d" % [label, "#".repeat(counts[i]), counts[i]])
	lines.append("")


static func _mass_bucket(mass_kg: float) -> int:
	for i in MASS_BUCKET_EDGES.size():
		if mass_kg < MASS_BUCKET_EDGES[i]:
			return i
	return MASS_BUCKET_EDGES.size()


## Integrity per kilogram is the progression axis §12 is built around, so a part
## far off its peers' ratio is either the point of the part or a data slip.
func _append_integrity_outliers(lines: PackedStringArray) -> void:
	lines.append("## Integrity per kilogram")
	lines.append("")
	if _definitions.size() < OUTLIER_MIN_SAMPLE:
		lines.append("Sample of %d is below the %d parts the spread needs to mean anything."
				% [_definitions.size(), OUTLIER_MIN_SAMPLE])
		lines.append("")
		return

	var ratios := PackedFloat32Array()
	var sum := 0.0
	for def in _definitions:
		var ratio := def.integrity_max / def.mass_kg
		ratios.push_back(ratio)
		sum += ratio
	var mean := sum / float(ratios.size())

	var variance := 0.0
	for ratio in ratios:
		variance += (ratio - mean) * (ratio - mean)
	var sigma := sqrt(variance / float(ratios.size()))

	lines.append("Mean %.2f integrity/kg, σ %.2f over %d parts." % [mean, sigma, ratios.size()])
	lines.append("")
	if is_zero_approx(sigma):
		lines.append("Every part shares the same ratio; no outliers.")
		lines.append("")
		return

	lines.append("| Part | Integrity/kg | Deviation |")
	lines.append("|---|---:|---:|")
	var flagged := 0
	for i in _definitions.size():
		var deviation := (ratios[i] - mean) / sigma
		if absf(deviation) < OUTLIER_SIGMA:
			continue
		flagged += 1
		lines.append("| `%s` | %.2f | %+.1fσ |" % [_definitions[i].part_key, ratios[i], deviation])
	if flagged == 0:
		lines.append("| _none beyond ±%.1fσ_ | | |" % OUTLIER_SIGMA)
	lines.append("")


func _append_exception_notes(lines: PackedStringArray) -> void:
	lines.append("## Balance exception notes")
	lines.append("")
	var found := 0
	for def in _definitions:
		if def.balance_exception_note.is_empty():
			continue
		found += 1
		lines.append("- `%s`: %s" % [def.part_key, def.balance_exception_note])
	if found == 0:
		lines.append("None. Every part tracks the §12 tier scaling model.")
	lines.append("")


func _append_findings(lines: PackedStringArray) -> void:
	lines.append("## Findings")
	lines.append("")
	if _failures.is_empty() and _warnings.is_empty():
		lines.append("None.")
		lines.append("")
		return
	for failure in _failures:
		lines.append("- **FAIL** %s" % failure)
	for warning in _warnings:
		lines.append("- WARN %s" % warning)
	lines.append("")


## ===== FINDING RECORDING ===============================================

func _fail(rule: int, subject: Variant, message: String) -> void:
	_failures.append("[R%02d] %s: %s" % [rule, String(subject), message])
	_failure_rules.push_back(rule)


func _warn(message: String) -> void:
	_warnings.append(message)


## ===== HELPERS =========================================================

## `class_tag.family.variant` of a key, or "" when the key is malformed. Tier is
## dropped because the group is precisely the set of tiers of one variant.
static func _variant_group(key: StringName) -> String:
	var segments := String(key).split(".")
	if segments.size() != 4:
		return ""
	return "%s.%s.%s" % [segments[0], segments[1], segments[2]]


static func _face_index(face: Vector3i) -> int:
	return AttachmentNodeDef.AXIS_NORMALS.find(face)


static func _class_label(part_class: int) -> String:
	var names := PartEnums.PartClass.keys()
	return String(names[part_class]) if part_class >= 0 and part_class < names.size() else "?"


static func _channel_name(channel: int) -> String:
	var names := PartEnums.DamageChannel.keys()
	return String(names[channel]) if channel >= 0 and channel < names.size() else "?"
