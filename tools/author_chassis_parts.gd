extends SceneTree
## One-shot authoring script for the two family-locked Core Modules of
## [code]docs/PART_DATA_SCHEMA.md[/code] §10.1.
##
## [codeblock]
## godot --headless --path . --script tools/author_chassis_parts.gd
## [/codeblock]
##
## [b]Run order matters and nothing declares it but this comment[/b]
## (LEARNED_FACTS.md §1 fact 76): this script writes two keys nothing else
## writes and reads none, so it goes last —
## [code]first[/code] → [code]combat[/code] → [code]locomotion[/code] →
## [code]appendage[/code] → [code]chassis[/code].
##
## Every number is quoted from §10.1 and §11. Re-running it rewrites the same
## bytes, and the manifest append is idempotent for the reason
## [code]tools/author_first_parts.gd[/code] gives: [code]part_def_id[/code] is
## serialised into save data and network packets.
##
## [b]Why two more Core Modules exist at all.[/b] Until now one chassis carried
## every locomotion family, so a limb and a rotor disc were bolted to a hull whose
## every published figure — a 24 m/s cap, a 5300 kg tolerance, a mount budget
## sized for four contacts and their stations — describes a machine that stands on
## the ground. §7.1's `locomotion_mask` makes the chassis declare what it is built
## to carry and [PlacementValidator] refuse the rest, which is doc 01 §4.1's
## reading applied one level down: an Assembly that flies is still one Assembly
## with one Core Module, and the *part* it is rooted on is no longer the part a
## wheeled machine is rooted on.

## Both chassis are the command core's width and height and shorter along `Z`.
##
## That is a decision rather than an accident. Six by four is what puts an AXLE
## station on a flank at `x` 19 or 27 and a deck at `y` +4, so every recipe cell
## that hangs off a flank or sits on a roof is unchanged by the split; thirteen
## cells of length is a wheelbase's requirement and neither of these families has
## a wheelbase. Nine cells is 2.25 m, which is the length that leaves a station at
## each end of an ambulatory stance and keeps a rotary hull's mass off the lever
## its disc line is the fulcrum of.
const CHASSIS_LO := Vector3i(-3, 0, -4)
const CHASSIS_HI := Vector3i(2, 3, 4)

## A roof to build on, exactly as [code]core.command.compact.t2[/code] offers.
const CHASSIS_FACES: Dictionary = {Vector3i(0, 1, 0): PartEnums.AttachmentPolarity.DECK}

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(0 if _run() else 1)
	return true


func _run() -> bool:
	var keys := PackedStringArray()
	keys.append(_author_core_ambulatory_strider_t3())
	keys.append(_author_core_rotary_lifter_t3())
	for key in keys:
		if key.is_empty():
			return false
	return PartAuthoring.append_to_manifest(keys)


## §10.1: `core.ambulatory.strider.t3`, 6×4×9 cells, 1350 kg, 3600 integrity,
## 20 armour, 560 PU capacity, 34 mounts, 12.0 m/s cap, 7400 kg mass tolerance.
## §11: the `core.ambulatory.*` resistance row.
##
## [b]The mount budget is the figure that changes a build.[/b] Four limbs cost
## four mounts apiece and their stations one each, which against the command
## core's twenty-eight left two — and an Energy Cell costs three. A walking
## Assembly therefore could not carry supply at all, which is recorded at
## [code]tests/combat_arena.gd[/code]'s `Recipe.AMBULATORY` as a constraint of the
## shipped part set. It was a constraint of the *wheeled* chassis it was borrowing.
##
## The speed cap is half the command core's because §13's gait moves an Assembly
## at a cadence rather than at a road speed, and the mass tolerance is above it
## because four limbs rated 4500 kg apiece carry more than four contacts rated
## 1100.
func _author_core_ambulatory_strider_t3() -> String:
	var key := &"core.ambulatory.strider.t3"
	var def := PartDefinition.new()
	def.part_key = key
	def.display_name_key = &"part.core.ambulatory.strider.t3.name"
	def.description_key = &"part.core.ambulatory.strider.t3.desc"
	def.part_class = PartEnums.PartClass.CORE_MODULE
	def.tier = PartEnums.TierGrade.REFINED

	def.occupancy_cells = PartAuthoring.box_cells(CHASSIS_LO, CHASSIS_HI)
	def.attachment_nodes = PartAuthoring.face_nodes(CHASSIS_LO, CHASSIS_HI, CHASSIS_FACES)

	# 400 kg/m³ of its own bounding box against the command core's 369: a body
	# slung between four limbs is a loaded spine and carries no suspension towers
	# to hollow it out.
	def.mass_kg = 1350.0
	def.com_offset_m = PartAuthoring.box_centre_m(CHASSIS_LO, CHASSIS_HI)
	def.inertia_box_half_extents_m = Vector3.ZERO  # Solver derives a box tensor from bounds.

	def.integrity_max = 3600.0
	def.resistance = PackedFloat32Array([0.18, 0.16, 0.30, 0.10, 0.05])
	def.armour_rating = 20.0
	# §10.1 publishes no load capacity for Core Modules; as with the command core,
	# the whole Assembly hangs off this part.
	def.load_capacity_kg = 9000.0
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID

	var core := CoreModuleProfile.new()
	core.locomotion_mask = PartEnums.CHASSIS_AMBULATORY
	core.power_capacity_pu = 560.0
	core.mount_budget = 34
	core.speed_cap_mps = 12.0
	core.control_authority = 1.0
	core.mass_tolerance_kg = 7400.0
	core.operator_seat_offset_m = Vector3(0.0, 0.35, 0.0)
	core.respawn_integrity_fraction = 1.0
	def.core_profile = core

	# §10 publishes no build costs. Scaled from the command core's 900 by §12's
	# Tier-2-to-Tier-3 step; it is the baseline of its own family, so rule 13 has
	# nothing to compare it against yet.
	def.build_cost = 1150
	def.mount_weight = 0

	return PartAuthoring.save_part(
		def,
		"core",
		PartAuthoring.single_box_collider(CHASSIS_LO, CHASSIS_HI),
		&"plate_std"
	)


## §10.1: `core.rotary.lifter.t3`, 6×4×9 cells, 900 kg, 2400 integrity, 10 armour,
## 640 PU capacity, 26 mounts, 34.0 m/s cap, 5200 kg mass tolerance.
## §11: the `core.rotary.*` resistance row.
##
## [b]Half the command core's mass, and that is the whole design.[/b] Nothing
## holds a rotary Assembly up but thrust, so every kilogram is lift the discs owe
## and shaft power the Prime Mover owes on top of it; and mass fore or aft of the
## disc line is trim the swashplate has to spend cone angle on before it can fly.
## `tests/combat_arena.gd`'s `ROTARY_POWER` records what that costs when it goes
## wrong — 0.31 m of offset asking for 23° of a 14° cone, and an Assembly that
## went over during the settle.
##
## The armour and the integrity are the price. It is the softest Core Module in
## the registry, which is correct: an airframe is stressed for lift and not for
## being shot at, and a rotary build's defence is that it is somewhere else.
func _author_core_rotary_lifter_t3() -> String:
	var key := &"core.rotary.lifter.t3"
	var def := PartDefinition.new()
	def.part_key = key
	def.display_name_key = &"part.core.rotary.lifter.t3.name"
	def.description_key = &"part.core.rotary.lifter.t3.desc"
	def.part_class = PartEnums.PartClass.CORE_MODULE
	def.tier = PartEnums.TierGrade.REFINED

	def.occupancy_cells = PartAuthoring.box_cells(CHASSIS_LO, CHASSIS_HI)
	def.attachment_nodes = PartAuthoring.face_nodes(CHASSIS_LO, CHASSIS_HI, CHASSIS_FACES)

	# 267 kg/m³ against the command core's 369 and the strider's 400.
	def.mass_kg = 900.0
	def.com_offset_m = PartAuthoring.box_centre_m(CHASSIS_LO, CHASSIS_HI)
	def.inertia_box_half_extents_m = Vector3.ZERO

	def.integrity_max = 2400.0
	def.resistance = PackedFloat32Array([0.08, 0.14, 0.12, 0.10, 0.05])
	def.armour_rating = 10.0
	def.load_capacity_kg = 7000.0
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID

	var core := CoreModuleProfile.new()
	core.locomotion_mask = PartEnums.CHASSIS_ROTARY
	# Two discs draw 150 PU each and an Effector Module the rest. A rotary build
	# that had to fit an Energy Cell before it could turn its second disc would
	# spend the mass it cannot afford on the supply it cannot lift.
	core.power_capacity_pu = 640.0
	core.mount_budget = 26
	core.speed_cap_mps = 34.0
	core.control_authority = 1.0
	core.mass_tolerance_kg = 5200.0
	core.operator_seat_offset_m = Vector3(0.0, 0.35, 0.0)
	core.respawn_integrity_fraction = 1.0
	def.core_profile = core

	def.build_cost = 1050
	def.mount_weight = 0

	return PartAuthoring.save_part(
		def,
		"core",
		PartAuthoring.single_box_collider(CHASSIS_LO, CHASSIS_HI),
		&"plate_std"
	)
