extends SceneTree
## Authors the Appendage family of [code]docs/PART_DATA_SCHEMA.md[/code] §10.6,
## and re-authors the beam edge of §10.5 as a held weapon.
##
##     godot --headless --path . --script tools/author_appendage_parts.gd
##
## Idempotent, with the caveat of HANDOFF §3.15: rerunning the same code is
## byte-stable, but a change to the surrounding authoring code churns every
## [code][sub_resource][/code] id. Diff with those lines filtered out.
##
## Two parts change here and the pairing is the point. An arm with nothing to
## hold is a bracket, and a sword nothing can hold is scenery, so the GRIP
## keying of §4.3 has to arrive on both faces in the same change or neither part
## can be placed.

const FACE_ZP: Vector3i = Vector3i(0, 0, 1)
const FACE_YN: Vector3i = Vector3i(0, -1, 0)

## §10.6's shoulder. The arm bolts to structure through its shoulder face and
## offers its hand at the far end.
const ARM_LO := Vector3i(-1, -5, -1)
const ARM_HI := Vector3i(1, 0, 1)


func _initialize() -> void:
	var keys := PackedStringArray()
	keys.append(_author_arm())
	keys.append(_reauthor_beam_edge())
	for key: String in keys:
		if key.is_empty():
			push_error("author_appendage_parts: a part failed to write")
			quit(1)
			return
	# Append only (CLAUDE.md rule 13): part_def_id is the manifest index and is
	# serialised into save data and network packets.
	if not PartAuthoring.append_to_manifest(PackedStringArray(["apx.arm.manipulator.t3"])):
		quit(1)
		return
	print("author_appendage_parts: wrote %s" % ", ".join(keys))
	quit()


## §10.6: [code]apx.arm.manipulator.t3[/code], 3x6x3, 410 kg, 460 integrity.
##
## Six cells of reach at 0.25 m the cell is 1.5 m of arm, and
## [member AppendageProfile.reach_m] is authored to match: the hand is where the
## occupancy ends, so what the player sees is where the sword goes. A grip rating
## of 28 800 N holds a 307 kg edge with room to spare, which is the trade §7.8
## wants a builder to meet.
##
## [b]The mass, the load capacity and the grip rating all scale with the edge they
## carry.[/b] Doc 01 §10.5's melee row went up by 3.2 when the reference build
## did; an arm left at 128 kg and a 260 kg capacity could not hold the sword it
## exists to hold, and the one build the Appendage class has would stop being a
## legal build.
func _author_arm() -> String:
	var def := PartDefinition.new()
	def.part_key = &"apx.arm.manipulator.t3"
	def.display_name_key = &"part.apx.arm.manipulator.t3.name"
	def.description_key = &"part.apx.arm.manipulator.t3.desc"
	def.part_class = PartEnums.PartClass.APPENDAGE
	def.tier = PartEnums.TierGrade.REFINED
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID
	def.inertia_box_half_extents_m = Vector3.ZERO
	def.occupancy_cells = PartAuthoring.box_cells(ARM_LO, ARM_HI)

	# The shoulder mounts upward into structure; the hand is the -Y face at the
	# bottom of the arm. Every other face is left bare, so an arm cannot be used
	# as a general bracket and cannot be stacked into a ladder of brackets.
	var nodes: Array[AttachmentNodeDef] = []
	for node: AttachmentNodeDef in PartAuthoring.face_nodes(
		ARM_LO, ARM_HI, {FACE_YN: PartEnums.AttachmentPolarity.GRIP},
		{FACE_YN: PackedInt32Array([PartEnums.PartClass.EFFECTOR_MODULE])}
	):
		if node.face_normal == FACE_YN:
			# Exactly one hand (rule 26). The lowest cell on the centre column is
			# the palm; the rest of the face is the back of the hand.
			if node.cell != Vector3i(0, ARM_LO.y, 0):
				continue
			node.node_name = &"hand"
		elif node.face_normal != Vector3i(0, 1, 0):
			continue
		nodes.push_back(node)
	def.attachment_nodes = nodes

	def.mass_kg = 410.0
	def.com_offset_m = PartAuthoring.box_centre_m(ARM_LO, ARM_HI)
	def.integrity_max = 460.0
	def.resistance = PackedFloat32Array([0.22, 0.16, 0.30, 0.12, 0.08])
	def.armour_rating = 15.0
	def.load_capacity_kg = 830.0
	def.power_draw_pu = 12.0
	def.heat_generation_hu_s = 0.0

	var arm := AppendageProfile.new()
	arm.grip_rating_n = 28800.0
	# Five cells from the shoulder pivot to the palm, at the 0.25 m lattice.
	arm.reach_m = 1.25
	arm.degrades_held_effector = true
	def.appendage_profile = arm

	return PartAuthoring.save_part(
		def, "apx", PartAuthoring.single_box_collider(ARM_LO, ARM_HI), &"plate_std"
	)


## §10.5's edge, re-authored as a held weapon.
##
## Its mounting face was [constant PartEnums.AttachmentPolarity.FACE_MALE] on
## -Y, which bolted it to any deck. It is now a single GRIP node on +Z — the
## hilt, opposite the blade that extends along -Z — and nothing else, so the edge
## can be held and cannot be welded to a roof.
##
## Nothing in the repository placed it before this change, which is the only
## reason a polarity change to a shipped part is safe: doc 01 §10.5 records the
## before and after, and the [member PartDefinition.part_key] is untouched, so
## rule 13's serialised ids are unaffected.
func _reauthor_beam_edge() -> String:
	var path := PartManifest.definition_path(&"eff.melee.beam_edge.t4")
	var def: PartDefinition = ResourceLoader.load(path) as PartDefinition
	if def == null:
		push_error("author_appendage_parts: no definition at %s" % path)
		return ""

	var hilt := AttachmentNodeDef.new()
	hilt.node_name = &"hilt"
	# The +Z end of the occupancy: the blade runs to -Z, so the hilt is the cell
	# a hand closes on.
	hilt.cell = Vector3i(0, 0, 0)
	hilt.face_normal = FACE_ZP
	hilt.polarity = PartEnums.AttachmentPolarity.GRIP
	hilt.joint_strength_n = PartAuthoring.JOINT_STRENGTH_N
	hilt.can_bear_load = false
	hilt.accepts_classes = PackedInt32Array([PartEnums.PartClass.APPENDAGE])

	var nodes: Array[AttachmentNodeDef] = [hilt]
	def.attachment_nodes = nodes
	return PartAuthoring.save_part(def, "eff", def.collider_profile, &"plate_std")
