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
## out, because a 6×4×13 Core Module has 312 cells and 308 face nodes and a
## hand-authored list of those is a transcription error waiting to happen.
##
## Re-running it rewrites the same bytes. It is committed rather than discarded
## so that the derivation of the data is reviewable next to the data itself, and
## so the next part authored has a worked example to copy.
##
## The manifest append is deliberately idempotent: [code]part_def_id[/code]
## values are serialised into save data and network packets, so an entry is
## added once and never reordered or removed.

## Face polarity maps for the two parts. A face absent from one is neutral.
const CORE_FACES: Dictionary = {Vector3i(0, 1, 0): PartEnums.AttachmentPolarity.DECK}

## The Core Module's two corner cells, and the one pair of numbers most of the
## reference build's proportions fall out of.
##
## It was 4x3x5. At `LATTICE_UNIT_M = 0.25` that is a 1.25 m cabin under a 2.25 m
## Effector Module — the weapon was half the Assembly's length and the cabin a
## quarter of it — and a chassis five cells deep has nowhere to put an axle
## station except under its own middle, which is what produced a 1.50 m wheelbase
## on a 4.25 m machine and a hull that stood on its front pair alone.
##
## 6x4x13 is 1.50 m by 1.00 m by 3.25 m. The stations reach the ends of it, the
## module tucks onto the roof instead of hanging past the front axle, and the
## whole Assembly comes out at 141 kg/m3 of its bounding box against a passenger
## car's 115 — where it used to be 46, a fifth of balsa.
const CORE_LO := Vector3i(-3, 0, -6)
const CORE_HI := Vector3i(2, 3, 6)

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
	return PartAuthoring.append_to_manifest(keys)


## §10.1: `core.command.compact.t2`, 6×4×13 cells, 1800 kg, 4200 integrity,
## 18 armour, 520 PU capacity, 28 mounts, 24.0 m/s cap, 5300 kg mass tolerance.
## §11: the `core.command.*` resistance row.
func _author_core_command_compact_t2() -> String:
	var key := &"core.command.compact.t2"
	var def := PartDefinition.new()
	def.part_key = key
	def.display_name_key = &"part.core.command.compact.t2.name"
	def.description_key = &"part.core.command.compact.t2.desc"
	def.part_class = PartEnums.PartClass.CORE_MODULE
	def.tier = PartEnums.TierGrade.STANDARD

	# X is 6 cells and Z is 13, so neither centres exactly on the pivot. The pivot
	# sits one cell right of centre on X and dead centre on Z; Y starts at the
	# pivot so the Core Module's underside is the Assembly's y = 0 datum.
	def.occupancy_cells = PartAuthoring.box_cells(CORE_LO, CORE_HI)
	def.attachment_nodes = PartAuthoring.face_nodes(CORE_LO, CORE_HI, CORE_FACES)

	def.mass_kg = 1800.0
	def.com_offset_m = PartAuthoring.box_centre_m(CORE_LO, CORE_HI)
	def.inertia_box_half_extents_m = Vector3.ZERO  # Solver derives a box tensor from bounds.

	def.integrity_max = 4200.0
	def.resistance = PackedFloat32Array([0.15, 0.20, 0.25, 0.10, 0.05])
	def.armour_rating = 18.0
	# §10.1 publishes no load capacity for Core Modules. The whole Assembly hangs
	# off this part, so it carries structurally what it tolerates dynamically.
	def.load_capacity_kg = 9000.0
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID

	var core := CoreModuleProfile.new()
	core.power_capacity_pu = 520.0
	core.mount_budget = 28
	core.speed_cap_mps = 24.0
	core.control_authority = 1.0
	core.mass_tolerance_kg = 5300.0
	core.operator_seat_offset_m = Vector3(0.0, 0.35, 0.0)
	core.respawn_integrity_fraction = 1.0
	def.core_profile = core

	# §10 publishes no build costs. This is the Tier-2 baseline of its family;
	# §12 scales every other tier of `core.command.compact` from it.
	def.build_cost = 900
	# The Core Module owns the mount budget and cannot consume it.
	def.mount_weight = 0

	return PartAuthoring.save_part(
		def,
		"core",
		PartAuthoring.single_box_collider(CORE_LO, CORE_HI),
		&"plate_std"
	)


## §10.2: `str.panel.medium.t2`, 4×1×4 cells, 100 kg, 380 integrity, 14 armour,
## 1560 kg load capacity, OPAQUE_SOLID. §11: the `str.panel.medium` row.
func _author_str_panel_medium_t2() -> String:
	var key := &"str.panel.medium.t2"
	var def := PartDefinition.new()
	def.part_key = key
	def.display_name_key = &"part.str.panel.medium.t2.name"
	def.description_key = &"part.str.panel.medium.t2.desc"
	def.part_class = PartEnums.PartClass.STRUCTURAL_COMPONENT
	def.tier = PartEnums.TierGrade.STANDARD

	# One cell thick, in the plane of the pivot cell.
	def.occupancy_cells = PartAuthoring.box_cells(Vector3i(-2, 0, -2), Vector3i(1, 0, 1))
	# A panel is generic structure: every face is neutral, including the top. It
	# is not a DECK, which would refuse a recessed face for no reason on a part
	# whose whole purpose is to be built on from any side.
	def.attachment_nodes = PartAuthoring.face_nodes(
		Vector3i(-2, 0, -2), Vector3i(1, 0, 1), {}
	)

	def.mass_kg = 100.0
	def.com_offset_m = PartAuthoring.box_centre_m(Vector3i(-2, 0, -2), Vector3i(1, 0, 1))
	def.inertia_box_half_extents_m = Vector3.ZERO

	def.integrity_max = 380.0
	def.resistance = PackedFloat32Array([0.18, 0.10, 0.20, 0.05, 0.05])
	def.armour_rating = 14.0
	def.load_capacity_kg = 1560.0
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID

	# Tier-2 baseline for `str.panel.medium`, as above.
	def.build_cost = 60
	def.mount_weight = 1

	return PartAuthoring.save_part(
		def,
		"str",
		PartAuthoring.single_box_collider(Vector3i(-2, 0, -2), Vector3i(1, 0, 1)),
		&"plate_std"
	)
