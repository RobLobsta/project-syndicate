class_name PartAuthoring
extends RefCounted
## Shared derivations for the committed part-authoring tools.
##
## Extracted from [code]tools/author_first_parts.gd[/code] when the second tool
## needed the same box, node, and side-car logic. Every function is static and
## every one is a [i]derivation[/i]: occupancy cell lists, attachment nodes, and
## collider extents are computed from documented cell dimensions rather than
## typed out, because a 4x3x5 Core Module has sixty cells and ninety-four face
## nodes and a hand-authored list of those is a transcription error waiting to
## happen.
##
## Nothing here reads at runtime. It exists so the derivation of the data is
## reviewable next to the data itself.

## §6.1 default. Document 01 §10 publishes no per-part joint strength, so parts
## carry the schema's documented value rather than an invented one unless the
## part has a structural reason to differ.
const JOINT_STRENGTH_N: float = 60000.0


## Every cell of the inclusive box from [param lo] to [param hi], in the order
## the lattice indexes them so the list is stable across runs.
static func box_cells(lo: Vector3i, hi: Vector3i) -> PackedVector3Array:
	var out := PackedVector3Array()
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				out.append(Vector3(x, y, z))
	return out


## [method box_cells] with the four corner columns of the X/Y face removed.
##
## A disc footprint, for a part whose collider is a cylinder. An inscribed
## cylinder is only pi/4 of its bounding box, which fails the 82% coverage floor
## of §6.2 rule 3 against a box occupancy — and correctly so: a wheel is not a
## box, and authoring it as one would claim hitbox volume in four corners where
## there is nothing to hit.
static func disc_cells(lo: Vector3i, hi: Vector3i) -> PackedVector3Array:
	var out := PackedVector3Array()
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var corner_x := x == lo.x or x == hi.x
				var corner_y := y == lo.y or y == hi.y
				if corner_x and corner_y:
					continue
				out.append(Vector3(x, y, z))
	return out


## Centre of the inclusive cell box relative to the pivot cell centre, in metres.
static func box_centre_m(lo: Vector3i, hi: Vector3i) -> Vector3:
	return Vector3(hi + lo) * 0.5 * SyndicateConstants.LATTICE_UNIT_M


## Half extents of the inclusive cell box in metres, including the half-cell of
## material either side of the outermost cell centres.
static func box_half_extents_m(lo: Vector3i, hi: Vector3i) -> Vector3:
	var span := Vector3(hi - lo) + Vector3.ONE
	return span * 0.5 * SyndicateConstants.LATTICE_UNIT_M


## One BOX covering the occupancy exactly — 100% of the §6.2 coverage band. A
## rectangular part has no honest reason to be approximated by anything less.
static func single_box_collider(lo: Vector3i, hi: Vector3i) -> ColliderProfile:
	var prim := ColliderPrimitiveDef.new()
	prim.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	prim.half_extents_m = box_half_extents_m(lo, hi)
	prim.local_offset_m = box_centre_m(lo, hi)
	prim.local_basis_euler_deg = Vector3.ZERO

	var profile := ColliderProfile.new()
	profile.primitives = [prim] as Array[ColliderPrimitiveDef]
	return profile


## One CYLINDER about the Z axis, for a part authored with [method disc_cells].
##
## Godot's [CylinderShape3D] is Y-aligned, so the profile carries a 90 degree
## rotation about X — a multiple of 15, as §6.2 rule 4 requires.
static func cylinder_z_collider(lo: Vector3i, hi: Vector3i) -> ColliderProfile:
	var half := box_half_extents_m(lo, hi)
	var prim := ColliderPrimitiveDef.new()
	prim.kind = ColliderPrimitiveDef.PrimitiveKind.CYLINDER
	prim.radius_m = maxf(half.x, half.y)
	prim.height_m = half.z * 2.0
	prim.local_offset_m = box_centre_m(lo, hi)
	prim.local_basis_euler_deg = Vector3(90.0, 0.0, 0.0)

	var profile := ColliderProfile.new()
	profile.primitives = [prim] as Array[ColliderPrimitiveDef]
	return profile


## One attachment node per exposed cell face of the box.
##
## Per-cell coverage is what [code]docs/GRID_SNAPPING_LOGIC.md[/code] §6.4
## assumes when it disambiguates between several nodes sharing a face, and what
## [code]docs/AUTO_ASSEMBLE_ALGORITHM.md[/code] assumes when it enumerates mount
## cells by upward-facing node. A part with one node per face would only ever
## snap at its own centre.
##
## [param face_polarity] maps a face normal to the polarity its nodes carry;
## faces absent from it are [constant PartEnums.AttachmentPolarity.FACE_NEUTRAL].
## [param face_classes] does the same for [member
## AttachmentNodeDef.accepts_classes], which is what keeps an Effector Module off
## an AXLE station (§14 rule 18).
static func face_nodes(
	lo: Vector3i,
	hi: Vector3i,
	face_polarity: Dictionary,
	face_classes: Dictionary = {},
	cells: PackedVector3Array = PackedVector3Array()
) -> Array[AttachmentNodeDef]:
	var out: Array[AttachmentNodeDef] = []
	var occupied := cells if not cells.is_empty() else box_cells(lo, hi)
	for face: Vector3i in AttachmentNodeDef.AXIS_NORMALS:
		var tag := face_tag(face)
		var index := 0
		for c: Vector3 in occupied:
			var cell := Vector3i(int(c.x), int(c.y), int(c.z))
			# A face is exposed when the cell beyond it is not part of the part.
			# Testing membership rather than the bounding box is what lets a
			# disc footprint carry nodes on its stepped rim.
			if occupied.has(Vector3(cell + face)):
				continue
			var node := AttachmentNodeDef.new()
			node.node_name = StringName("%s_%02d" % [tag, index])
			node.cell = cell
			node.face_normal = face
			node.polarity = face_polarity.get(face, PartEnums.AttachmentPolarity.FACE_NEUTRAL)
			node.joint_strength_n = JOINT_STRENGTH_N
			node.can_bear_load = true
			node.accepts_classes = face_classes.get(face, PackedInt32Array())
			out.push_back(node)
			index += 1
	return out


static func face_tag(face: Vector3i) -> String:
	if face.x != 0:
		return "xp" if face.x > 0 else "xn"
	if face.y != 0:
		return "yp" if face.y > 0 else "yn"
	return "zp" if face.z > 0 else "zn"


## Stage PROXY with no primitives of its own: [code]docs/EXTENSION_PIPELINE.md[/code]
## §2.1 then mirrors the [ColliderProfile], so the greybox build is visually
## honest about exactly what it collides as.
static func proxy_visual() -> PartVisualProfile:
	var visual := PartVisualProfile.new()
	visual.stage = PartVisualProfile.Stage.PROXY
	return visual


## §6.3 defaults, except that skirting is off: §9.1 of document 13 requires a
## proxy to decline skirt runs, since it has no authored edge to run them along.
static func fusion_profile(family: StringName = &"plate_std") -> FusionProfile:
	var fusion := FusionProfile.new()
	fusion.fillet_radius_m = 0.045
	fusion.contributes_to_sdf = true
	fusion.accepts_skirting = false
	fusion.fusion_family = family
	fusion.surface_variant = 0
	return fusion


## Writes the four files of [code]docs/EXTENSION_PIPELINE.md[/code] §3 —
## definition plus its visual, collider, and fusion side-cars — and returns the
## part key, or "" on failure.
##
## The side-cars are saved first so the definition references them as external
## resources rather than inlining copies.
static func save_part(
	def: PartDefinition, class_dir: String, collider: ColliderProfile, fusion_family: StringName
) -> String:
	var key := String(def.part_key)
	var dir := "%s/%s" % [PartManifest.PARTS_DIR, class_dir]
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		printerr("part_authoring: cannot create %s" % dir)
		return ""

	if not save(collider, "%s/%s.collider.tres" % [dir, key]):
		return ""
	if not save(proxy_visual(), "%s/%s.visual.tres" % [dir, key]):
		return ""
	if not save(fusion_profile(fusion_family), "%s/%s.fusion.tres" % [dir, key]):
		return ""

	# Reloaded from disk rather than assigned from memory. ResourceSaver leaves
	# resource_path unset on the object it wrote, and a profile with no path
	# serialises into the definition as an inlined copy — which would leave the
	# side-car files dead and let a definition's collider silently diverge from
	# the one docs/EXTENSION_PIPELINE.md §7 hashes for the balance-review gate.
	def.collider_profile = reload("%s/%s.collider.tres" % [dir, key])
	def.visual_profile = reload("%s/%s.visual.tres" % [dir, key])
	def.fusion_profile = reload("%s/%s.fusion.tres" % [dir, key])
	if not save(def, "%s/%s.tres" % [dir, key]):
		return ""

	print(
		(
			"part_authoring: wrote %s (%d cells, %d nodes)"
			% [key, def.occupancy_cells.size(), def.attachment_nodes.size()]
		)
	)
	return key


static func save(resource: Resource, path: String) -> bool:
	# Captured before the write: ResourceSaver emits no uid of its own, so a
	# re-save would strip the id an existing file already carries and break
	# every uid:// reference to it.
	var existing := ResourceLoader.get_resource_uid(path)

	var err := ResourceSaver.save(resource, path)
	if err != OK:
		printerr("part_authoring: saving %s failed with error %d" % [path, err])
		return false

	var uid := existing if existing != ResourceUID.INVALID_ID else ResourceUID.create_id()
	err = ResourceSaver.set_uid(path, uid)
	if err != OK:
		printerr("part_authoring: setting uid on %s failed with error %d" % [path, err])
		return false
	return true


## Reads a just-written side-car back so the definition references it as an
## external resource. Cache mode REPLACE because a re-run must pick up the file
## it wrote this pass, not the copy the loader cached on the previous one.
static func reload(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


## Appends any key not already listed to the registry manifest.
##
## §5.2: order is append-only, because [code]part_def_id[/code] is the index plus
## one and is serialised into save data and network packets. An entry is added
## once and never reordered or removed.
static func append_to_manifest(keys: PackedStringArray) -> bool:
	var path := PartRegistryService.MANIFEST_PATH
	var manifest: PartManifest = ResourceLoader.load(path) as PartManifest
	if manifest == null:
		printerr("part_authoring: no manifest at %s" % path)
		return false

	var listed := manifest.keys
	var added := 0
	for key: String in keys:
		if listed.has(key):
			continue
		listed.append(key)
		added += 1
	if added == 0:
		print("part_authoring: manifest already lists every key")
		return true

	manifest.keys = listed
	if not save(manifest, path):
		return false
	print(
		"part_authoring: appended %d keys; manifest now holds %d" % [added, manifest.keys.size()]
	)
	return true
