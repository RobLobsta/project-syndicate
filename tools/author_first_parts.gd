extends SceneTree
## One-shot authoring script for the two reference parts of
## [code]docs/PART_DATA_SCHEMA.md[/code] §10.1 and §10.2.
##
## [codeblock]
## godot --headless --path . --script tools/author_first_parts.gd
## [/codeblock]
##
## Every number here is quoted from the tables in document 01; nothing is
## invented but the two values §10 leaves open, which are commented where they
## are set. The occupancy cell lists, the attachment nodes, and the collider
## extents are *derived* from the documented cell dimensions rather than typed
## out, because a 4×3×5 Core Module has sixty cells and ninety-four face nodes
## and a hand-authored list of those is a transcription error waiting to happen.
##
## Re-running it rewrites the same bytes. It is committed rather than discarded
## so that the derivation of the data is reviewable next to the data itself, and
## so the next part authored has a worked example to copy.
##
## The manifest append is deliberately idempotent: [code]part_def_id[/code]
## values are serialised into save data and network packets, so an entry is
## added once and never reordered or removed.

const MANIFEST_PATH: String = PartRegistryService.MANIFEST_PATH

## §6.1 default. §10 publishes no per-part joint strength, so every node on both
## parts carries the schema's documented value rather than an invented one.
const JOINT_STRENGTH_N: float = 60000.0

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(0 if _run() else 1)
	return true


func _run() -> bool:
	var keys := PackedStringArray()
	keys.append(_author_core_command_compact_t2())
	keys.append(_author_str_panel_medium_t2())
	for key in keys:
		if key.is_empty():
			return false
	return _append_to_manifest(keys)


## §10.1: `core.command.compact.t2`, 4×3×5 cells, 380 kg, 1450 integrity,
## 18 armour, 240 PU capacity, 28 mounts, 24.0 m/s cap, 3600 kg mass tolerance.
## §11: the `core.command.*` resistance row.
func _author_core_command_compact_t2() -> String:
	var key := &"core.command.compact.t2"
	var def := PartDefinition.new()
	def.part_key = key
	def.display_name_key = &"part.core.command.compact.t2.name"
	def.description_key = &"part.core.command.compact.t2.desc"
	def.part_class = PartEnums.PartClass.CORE_MODULE
	def.tier = PartEnums.TierGrade.STANDARD

	# X is 4 cells and Z is 5, so neither centres exactly on the pivot. The pivot
	# sits one cell right of centre on X and dead centre on Z; Y starts at the
	# pivot so the Core Module's underside is the Assembly's y = 0 datum.
	def.occupancy_cells = _box_cells(Vector3i(-2, 0, -2), Vector3i(1, 2, 2))
	def.attachment_nodes = _box_face_nodes(
		Vector3i(-2, 0, -2), Vector3i(1, 2, 2), PartEnums.AttachmentPolarity.DECK
	)

	def.mass_kg = 380.0
	def.com_offset_m = _box_centre_m(Vector3i(-2, 0, -2), Vector3i(1, 2, 2))
	def.inertia_box_half_extents_m = Vector3.ZERO  # Solver derives a box tensor from bounds.

	def.integrity_max = 1450.0
	def.resistance = PackedFloat32Array([0.15, 0.20, 0.25, 0.10, 0.05])
	def.armour_rating = 18.0
	# §10.1 publishes no load capacity for Core Modules. The whole Assembly hangs
	# off this part, so it carries structurally what it tolerates dynamically.
	def.load_capacity_kg = 3600.0
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID

	var core := CoreModuleProfile.new()
	core.power_capacity_pu = 240.0
	core.mount_budget = 28
	core.speed_cap_mps = 24.0
	core.control_authority = 1.0
	core.mass_tolerance_kg = 3600.0
	core.operator_seat_offset_m = Vector3(0.0, 0.35, 0.0)
	core.respawn_integrity_fraction = 1.0
	def.core_profile = core

	# §10 publishes no build costs. This is the Tier-2 baseline of its family;
	# §12 scales every other tier of `core.command.compact` from it.
	def.build_cost = 900
	# The Core Module owns the mount budget and cannot consume it.
	def.mount_weight = 0

	return _save_part(def, "core", _single_box_collider(Vector3i(-2, 0, -2), Vector3i(1, 2, 2)))


## §10.2: `str.panel.medium.t2`, 4×1×4 cells, 34 kg, 380 integrity, 14 armour,
## 520 kg load capacity, OPAQUE_SOLID. §11: the `str.panel.medium` row.
func _author_str_panel_medium_t2() -> String:
	var key := &"str.panel.medium.t2"
	var def := PartDefinition.new()
	def.part_key = key
	def.display_name_key = &"part.str.panel.medium.t2.name"
	def.description_key = &"part.str.panel.medium.t2.desc"
	def.part_class = PartEnums.PartClass.STRUCTURAL_COMPONENT
	def.tier = PartEnums.TierGrade.STANDARD

	# One cell thick, in the plane of the pivot cell.
	def.occupancy_cells = _box_cells(Vector3i(-2, 0, -2), Vector3i(1, 0, 1))
	# A panel is generic structure: every face is neutral, including the top. It
	# is not a DECK, which would refuse a recessed face for no reason on a part
	# whose whole purpose is to be built on from any side.
	def.attachment_nodes = _box_face_nodes(
		Vector3i(-2, 0, -2), Vector3i(1, 0, 1), PartEnums.AttachmentPolarity.FACE_NEUTRAL
	)

	def.mass_kg = 34.0
	def.com_offset_m = _box_centre_m(Vector3i(-2, 0, -2), Vector3i(1, 0, 1))
	def.inertia_box_half_extents_m = Vector3.ZERO

	def.integrity_max = 380.0
	def.resistance = PackedFloat32Array([0.18, 0.10, 0.20, 0.05, 0.05])
	def.armour_rating = 14.0
	def.load_capacity_kg = 520.0
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID

	# Tier-2 baseline for `str.panel.medium`, as above.
	def.build_cost = 60
	def.mount_weight = 1

	return _save_part(def, "str", _single_box_collider(Vector3i(-2, 0, -2), Vector3i(1, 0, 1)))


## Writes the four files of `docs/EXTENSION_PIPELINE.md` §3 — definition plus its
## visual, collider, and fusion side-cars — and returns the part key, or "" on
## failure. The side-cars are saved first so the definition references them as
## external resources rather than inlining copies.
func _save_part(def: PartDefinition, class_dir: String, collider: ColliderProfile) -> String:
	var key := String(def.part_key)
	var dir := "%s/%s" % [PartManifest.PARTS_DIR, class_dir]
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		printerr("author_first_parts: cannot create %s" % dir)
		return ""

	if not _save(collider, "%s/%s.collider.tres" % [dir, key]):
		return ""
	if not _save(_proxy_visual(), "%s/%s.visual.tres" % [dir, key]):
		return ""
	if not _save(_fusion_profile(), "%s/%s.fusion.tres" % [dir, key]):
		return ""

	# Reloaded from disk rather than assigned from memory. ResourceSaver leaves
	# resource_path unset on the object it wrote, and a profile with no path
	# serialises into the definition as an inlined copy — which would leave the
	# side-car files dead and let a definition's collider silently diverge from
	# the one docs/EXTENSION_PIPELINE.md §7 hashes for the balance-review gate.
	def.collider_profile = _reload("%s/%s.collider.tres" % [dir, key])
	def.visual_profile = _reload("%s/%s.visual.tres" % [dir, key])
	def.fusion_profile = _reload("%s/%s.fusion.tres" % [dir, key])
	if not _save(def, "%s/%s.tres" % [dir, key]):
		return ""

	print("author_first_parts: wrote %s (%d cells, %d nodes)"
			% [key, def.occupancy_cells.size(), def.attachment_nodes.size()])
	return key


## Stage PROXY with no primitives of its own: `docs/EXTENSION_PIPELINE.md` §2.1
## then mirrors the ColliderProfile, so the greybox build is visually honest
## about exactly what it collides as.
func _proxy_visual() -> PartVisualProfile:
	var visual := PartVisualProfile.new()
	visual.stage = PartVisualProfile.Stage.PROXY
	return visual


## §6.3 defaults, except that skirting is off: §9.1 of document 13 requires a
## proxy to decline skirt runs, since it has no authored edge to run them along.
func _fusion_profile() -> FusionProfile:
	var fusion := FusionProfile.new()
	fusion.fillet_radius_m = 0.045
	fusion.contributes_to_sdf = true
	fusion.accepts_skirting = false
	fusion.fusion_family = &"plate_std"
	fusion.surface_variant = 0
	return fusion


func _save(resource: Resource, path: String) -> bool:
	# Captured before the write: ResourceSaver emits no uid of its own, so a
	# re-save would strip the id an existing file already carries and break
	# every uid:// reference to it.
	var existing := ResourceLoader.get_resource_uid(path)

	var err := ResourceSaver.save(resource, path)
	if err != OK:
		printerr("author_first_parts: saving %s failed with error %d" % [path, err])
		return false

	var uid := existing if existing != ResourceUID.INVALID_ID else ResourceUID.create_id()
	err = ResourceSaver.set_uid(path, uid)
	if err != OK:
		printerr("author_first_parts: setting uid on %s failed with error %d" % [path, err])
		return false
	return true


## Reads a just-written side-car back so the definition references it as an
## external resource. Cache mode REPLACE because a re-run must pick up the file
## it wrote this pass, not the copy the loader cached on the previous one.
static func _reload(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


## ===== DERIVATIONS =====================================================

## Every cell of the inclusive box from [param lo] to [param hi], in the order
## the lattice indexes them so the list is stable across runs.
static func _box_cells(lo: Vector3i, hi: Vector3i) -> PackedVector3Array:
	var out := PackedVector3Array()
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				out.append(Vector3(x, y, z))
	return out


## Centre of the inclusive cell box relative to the pivot cell centre, in metres.
static func _box_centre_m(lo: Vector3i, hi: Vector3i) -> Vector3:
	return Vector3(hi + lo) * 0.5 * SyndicateConstants.LATTICE_UNIT_M


## Half extents of the inclusive cell box in metres, including the half-cell of
## material either side of the outermost cell centres.
static func _box_half_extents_m(lo: Vector3i, hi: Vector3i) -> Vector3:
	var span := Vector3(hi - lo) + Vector3.ONE
	return span * 0.5 * SyndicateConstants.LATTICE_UNIT_M


## One BOX covering the occupancy exactly — 100% of the §6.2 coverage band. A
## rectangular part has no honest reason to be approximated by anything less.
static func _single_box_collider(lo: Vector3i, hi: Vector3i) -> ColliderProfile:
	var prim := ColliderPrimitiveDef.new()
	prim.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	prim.half_extents_m = _box_half_extents_m(lo, hi)
	prim.local_offset_m = _box_centre_m(lo, hi)
	prim.local_basis_euler_deg = Vector3.ZERO

	var profile := ColliderProfile.new()
	profile.primitives = [prim] as Array[ColliderPrimitiveDef]
	return profile


## One attachment node per exposed cell face of the box.
##
## Per-cell coverage is what `docs/GRID_SNAPPING_LOGIC.md` §6.4 assumes when it
## disambiguates between several nodes sharing a face, and what
## `docs/AUTO_ASSEMBLE_ALGORITHM.md` §373 assumes when it enumerates mount cells
## by upward-facing node. A part with one node per face would only ever snap at
## its own centre.
##
## [param top_polarity] applies to the +Y face alone; every other face is neutral.
static func _box_face_nodes(
	lo: Vector3i, hi: Vector3i, top_polarity: PartEnums.AttachmentPolarity
) -> Array[AttachmentNodeDef]:
	var out: Array[AttachmentNodeDef] = []
	for face in AttachmentNodeDef.AXIS_NORMALS:
		var tag := _face_tag(face)
		var index := 0
		for z in range(lo.z, hi.z + 1):
			for y in range(lo.y, hi.y + 1):
				for x in range(lo.x, hi.x + 1):
					var cell := Vector3i(x, y, z)
					if not _is_on_face(cell, lo, hi, face):
						continue
					var node := AttachmentNodeDef.new()
					node.node_name = StringName("%s_%02d" % [tag, index])
					node.cell = cell
					node.face_normal = face
					node.polarity = (
						top_polarity
						if face == Vector3i(0, 1, 0)
						else PartEnums.AttachmentPolarity.FACE_NEUTRAL
					)
					node.joint_strength_n = JOINT_STRENGTH_N
					node.can_bear_load = true
					node.accepts_classes = PackedInt32Array()
					out.push_back(node)
					index += 1
	return out


## True when [param cell] is on the [param face] boundary of the inclusive box,
## so the face points at open space rather than at the next cell of the part.
static func _is_on_face(cell: Vector3i, lo: Vector3i, hi: Vector3i, face: Vector3i) -> bool:
	var neighbour := cell + face
	return (
		neighbour.x < lo.x
		or neighbour.y < lo.y
		or neighbour.z < lo.z
		or neighbour.x > hi.x
		or neighbour.y > hi.y
		or neighbour.z > hi.z
	)


static func _face_tag(face: Vector3i) -> String:
	if face.x != 0:
		return "xp" if face.x > 0 else "xn"
	if face.y != 0:
		return "yp" if face.y > 0 else "yn"
	return "zp" if face.z > 0 else "zn"


## ===== MANIFEST ========================================================

## Appends any key not already listed. §5.2: order is append-only, because
## `part_def_id` is the index plus one and is serialised in save data and
## network packets.
func _append_to_manifest(keys: PackedStringArray) -> bool:
	var manifest: PartManifest = ResourceLoader.load(MANIFEST_PATH) as PartManifest
	if manifest == null:
		printerr("author_first_parts: no manifest at %s" % MANIFEST_PATH)
		return false

	var listed := manifest.keys
	var added := 0
	for key in keys:
		if listed.has(key):
			continue
		listed.append(key)
		added += 1
	if added == 0:
		print("author_first_parts: manifest already lists every key")
		return true

	manifest.keys = listed
	if not _save(manifest, MANIFEST_PATH):
		return false
	print("author_first_parts: appended %d keys; manifest now holds %d"
			% [added, manifest.keys.size()])
	return true
