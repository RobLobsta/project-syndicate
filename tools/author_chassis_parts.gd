extends SceneTree
## One-shot authoring script for the four non-road Core Modules of
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

## [b]No two chassis in the registry are the same shape any more, and that is
## the reversal this file records.[/b]
##
## Until session 44 all four authored chassis were 6x4 in section and differed
## only along `Z`, on the reading that six by four is what puts an AXLE station on
## a flank at `x` 19 or 27 and a deck at `y` +4 — so every recipe cell that hung
## off a flank or sat on a roof was unchanged by the split. That bought a cell
## list which ported between families, and cost the only property of a part table
## no validator can see: [b]every Assembly was the same box with different running
## gear underneath.[/b]
##
## Each of the four is now derived from a photographic reference, and the section
## is the first thing every one of them disagrees about. Doc 01 §10.1 carries the
## table; the short version is that a walking machine's torso is taller than it is
## long, a rotorcraft's fuselage is ten times longer than it is wide, and neither
## of those is expressible in a section chosen to make a road car's axle stations
## line up.
##
## The cost is paid knowingly and it is real: [b]a recipe cell list no longer
## ports between families[/b], so each layout in `tests/combat_arena.gd` is
## derived against its own chassis's extents and says which.

## The ambulatory torso: 6x10x10 cells, 1.50 m wide, 2.50 m tall, 2.50 m long.
##
## [b]It replaces a 6x4x9 — 1.50 x 1.00 x 2.25 m — which was a box lying on its
## side.[/b] That is the silhouette `HANDOFF.md` §3.1.3 means when it says a
## walker is not a car with legs, and it was visible in a capture long before it
## was visible in a number: the same flat hull as the road car, standing on stubs.
## Two and a half metres of height on the same footprint is a body that reads as a
## torso, and it is the largest change to any silhouette in this rebuild.
##
## [b]It is not the reference's proportion, and the shortfall is architectural
## rather than a compromise anybody chose.[/b] The humanoid reference is a biped:
## measured off the artwork its torso is 1.85 times as tall as it is deep, and its
## legs are 0.50 of overall height against a torso of 0.24. Reproducing either
## number here requires a torso with almost no fore-and-aft depth — and doc 05
## §13's virtual leg is a single spring-damper force along the hip-to-foot line
## with a point foot, so [b]the fore-and-aft separation of the feet is the only
## pitch stability an ambulatory Assembly has.[/b] There is no ankle, no foot
## length, and no balance controller; `GaitSolver.stance_axial_force_n` returns
## one scalar along one line.
##
## So a humanoid torso on this model is a machine that face-plants on its first
## step, and the two numbers trade directly: every cell of torso depth removed is
## a cell of stance base removed. Ten cells keeps the 1.50 m stance the family was
## measured on while taking the height from 1.00 m to 2.50 m, which is the most
## verticality available without touching the gait model.
##
## [b]Closing the rest of the gap is doc 05 §13 architecture and is raised as
## such[/b] — a foot with a length and an ankle torque, or a balance controller
## that modulates stance force fore and aft. Either would make a biped tractable
## and neither is a data change. `HANDOFF.md` §3.1.3 carries it.
const AMBULATORY_LO := Vector3i(-3, 0, -5)
const AMBULATORY_HI := Vector3i(2, 9, 4)

## The rotary fuselage: 4x6x28 cells, 1.00 m wide, 1.50 m deep, 7.00 m long.
##
## [b]Ten times longer than it is wide, which is what a tandem-seat airframe is.[/b]
## The reference is a 35 ft — 10.67 m — rotorcraft with one seat abreast, a chin
## turret, and most of its length in a boom aft of the rotor line. Its fuselage
## width is about 0.10 of its length and its depth about 0.14; four cells by six
## against twenty-eight is 0.14 and 0.21, which is the same machine at a scale
## that fits a 12 m Build Lattice with its discs on outriggers.
##
## The old 6x4x9 was 1.50 x 1.00 x 2.25 m — wider than it was deep and barely
## longer than the discs it carried. Doc 01 §10.3 records the other half of the
## same repair: the discs came down from 2.60 m to 2.00 m of radius so that a pair
## of them is about 0.57 of the fuselage rather than 2.3 times it.
const ROTARY_LO := Vector3i(-2, 0, -14)
const ROTARY_HI := Vector3i(1, 5, 13)

## The tracked hull: 10x5x24 cells, 2.50 m wide, 1.25 m tall, 6.00 m long.
##
## [b]It is exactly as long as the track under it, and that is the family's
## repair.[/b] `mot.tracked.short_bogie.t2` runs 1.90 m of patch, so every tracked
## hull the project has shipped was see-sawing on a base shorter than itself: at
## 3.25 m the forward road stations carried 2527 N against 8169 at the rear and it
## sat 4.7° nose-up, and shortening the hull to 2.25 m improved the numbers
## without changing the shape of the problem. `HANDOFF.md` §3.1.2 named a longer
## bogie as the one change that makes the rest tractable, and
## `mot.tracked.long_bogie.t3` is it: 6.00 m of part with 5.60 m of patch under a
## 6.00 m hull, six road stations evenly spaced along it.
##
## Twenty-four cells and 1.25 m of height is also the reference's proportion — a
## long flat hull whose deck sits about a fifth of its length off the ground —
## and it is what gives `eff.ballistic.rifle_long.t3` somewhere to sit that leaves
## the barrel overhanging the nose rather than the machine balancing on it.
const TRACKED_LO := Vector3i(-5, 0, -12)
const TRACKED_HI := Vector3i(4, 4, 11)

## The utility hull: 10x6x20 cells, 2.50 m wide, 1.50 m tall, 5.00 m long.
##
## [b]The one chassis in the set that is as tall as it is wide.[/b] The protected
## utility reference measures 6.2 m by 2.5 m by 2.6 m: height is 0.42 of length
## and width 0.40, so it is very nearly square in section where the road car is
## 0.26 by 0.42. A slab-sided crew box is the silhouette, and no amount of
## re-laying parts on `core.command.compact.t2` produces one — a 1.00 m hull with
## a mover on the roof is a pickup, which is what the wheeled recipes have always
## looked like.
##
## Five metres of hull plus 1.50 m of bonnet ahead of it is a 6.50 m machine
## standing about 2.60 m to the top of its weapon station: 0.40 and 0.38 against
## the reference's 0.42 and 0.40. The bonnet is `pmv.combustion.standard.t2` mated
## to the `-Z` face — the square row rather than the flat one, because on this
## vehicle the engine is meant to read as a raised block forward of the cab.
const UTILITY_LO := Vector3i(-5, 0, -10)
const UTILITY_HI := Vector3i(4, 5, 9)

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
	keys.append(_author_core_tracked_hauler_t3())
	keys.append(_author_core_utility_hauler_t2())
	for key in keys:
		if key.is_empty():
			return false
	return PartAuthoring.append_to_manifest(keys)


## §10.1: `core.ambulatory.strider.t3`, 6×10×10 cells, 1800 kg, 3600 integrity,
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

	def.occupancy_cells = PartAuthoring.box_cells(AMBULATORY_LO, AMBULATORY_HI)
	def.attachment_nodes = PartAuthoring.face_nodes(
		AMBULATORY_LO, AMBULATORY_HI, CHASSIS_FACES
	)

	# 192 kg/m³ of its own bounding box, between the road hull's 257 and the
	# airframe's 105: a torso carried on four limbs is a loaded spine, and most of
	# the volume this one gained is the height it stands rather than structure.
	def.mass_kg = 1800.0
	def.com_offset_m = PartAuthoring.box_centre_m(AMBULATORY_LO, AMBULATORY_HI)
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
		PartAuthoring.single_box_collider(AMBULATORY_LO, AMBULATORY_HI),
		&"plate_std"
	)


## §10.1: `core.rotary.lifter.t3`, 4×6×28 cells, 1100 kg, 2400 integrity, 10 armour,
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

	def.occupancy_cells = PartAuthoring.box_cells(ROTARY_LO, ROTARY_HI)
	def.attachment_nodes = PartAuthoring.face_nodes(ROTARY_LO, ROTARY_HI, CHASSIS_FACES)

	# 105 kg/m³ — the lightest chassis in the registry by a wide margin, against
	# the road hull's 207 and the strider's 450. A 7.00 m airframe is mostly a
	# monocoque boom around air, and every kilogram of it is lift the discs owe.
	def.mass_kg = 1100.0
	def.com_offset_m = PartAuthoring.box_centre_m(ROTARY_LO, ROTARY_HI)
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
		PartAuthoring.single_box_collider(ROTARY_LO, ROTARY_HI),
		&"plate_std"
	)


## §10.1: `core.tracked.hauler.t3`, 10×5×24 cells, 4200 kg, 4600 integrity,
## 26 armour, 500 PU capacity, 30 mounts, 14.0 m/s cap, 9000 kg mass tolerance.
## §11: the `core.command.*` resistance row, which a tracked hull shares — it is
## the same steel box, differently proportioned.
##
## [b]The heaviest and slowest chassis in the registry, and both are the design.[/b]
## A tracked Assembly's argument is that it stands on a patch rather than on four
## points: it takes load its wheeled equivalent cannot and it goes nowhere quickly.
##
## 4200 kg is a section change and not a balance one. 2.50 × 1.25 × 6.00 m is
## 18.75 m³ where the 6×4×9 hull was 3.38, so the 1700 kg it published would be
## 91 kg/m³ on the new hull — a tracked gun platform built out of expanded foam.
## 224 kg/m³ puts it near the road chassis's 257 and below the walking torso's
## 450, which is the ordering a hull of mostly armour and running gear should have
## against a cabin and against a loaded spine.
##
## The speed cap is 14 m/s against the command core's 24, which is doc 05 §7.8's
## governor doing something real for the first time: a tracked build reaches its
## cap and holds it, and the cap is what a track is for rather than a number
## nobody enforces.
func _author_core_tracked_hauler_t3() -> String:
	var key := &"core.tracked.hauler.t3"
	var def := PartDefinition.new()
	def.part_key = key
	def.display_name_key = &"part.core.tracked.hauler.t3.name"
	def.description_key = &"part.core.tracked.hauler.t3.desc"
	def.part_class = PartEnums.PartClass.CORE_MODULE
	def.tier = PartEnums.TierGrade.REFINED

	def.occupancy_cells = PartAuthoring.box_cells(TRACKED_LO, TRACKED_HI)
	def.attachment_nodes = PartAuthoring.face_nodes(TRACKED_LO, TRACKED_HI, CHASSIS_FACES)

	def.mass_kg = 4200.0
	def.com_offset_m = PartAuthoring.box_centre_m(TRACKED_LO, TRACKED_HI)
	def.inertia_box_half_extents_m = Vector3.ZERO

	def.integrity_max = 4600.0
	def.resistance = PackedFloat32Array([0.12, 0.18, 0.16, 0.14, 0.08])
	def.armour_rating = 26.0
	def.load_capacity_kg = 14000.0
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID

	var core := CoreModuleProfile.new()
	core.locomotion_mask = PartEnums.CHASSIS_TRACKED
	core.power_capacity_pu = 500.0
	core.mount_budget = 30
	core.speed_cap_mps = 14.0
	core.control_authority = 1.0
	core.mass_tolerance_kg = 9000.0
	core.operator_seat_offset_m = Vector3(0.0, 0.35, 0.0)
	core.respawn_integrity_fraction = 1.0
	def.core_profile = core

	def.build_cost = 1300
	def.mount_weight = 0

	return PartAuthoring.save_part(
		def,
		"core",
		PartAuthoring.single_box_collider(TRACKED_LO, TRACKED_HI),
		&"plate_std"
	)


## §10.1: `core.utility.hauler.t2`, 10×6×20 cells, 3000 kg, 5200 integrity,
## 24 armour, 560 PU capacity, 32 mounts, 18.0 m/s cap, 8200 kg mass tolerance.
## §11: the `core.command.*` resistance row, which a protected utility hull
## shares — it is the same steel box in a taller section.
##
## [b]The only wheeled chassis in the registry that is as tall as it is wide, and
## it exists because one silhouette in the reference set cannot be built out of
## the other four.[/b] `core.command.compact.t2` is a 1.00 m road hull; the
## protected utility reference is 2.6 m to the roof over a 2.5 m beam, with the
## crew box standing clear above wheels that are 0.16 of its length. Laying a
## Prime Mover and an Energy Cell on a road hull's roof gets the height and reads
## as a pickup, because the height is stacked cargo rather than structure.
##
## Three published figures sit between the road hull and the tracked one, and
## each is the vehicle it describes: 3000 kg because a protected box is heavier
## than a monocoque and lighter than armour over a track; 18 m/s because it is
## geared for load rather than for speed; and 32 mounts because a utility hull is
## bought to carry things and the reference carries a remote weapon station, a
## bonnet, and four contacts twice the road car's size.
##
## `CHASSIS_WHEELED` alone rather than `CHASSIS_GROUND_TRANSITIONAL`: the tracked
## family has `core.tracked.hauler.t3`, and a hull authored for 1.00 m contacts
## and a 3.25 m wheelbase has no business accepting a 6.00 m bogie.
func _author_core_utility_hauler_t2() -> String:
	var key := &"core.utility.hauler.t2"
	var def := PartDefinition.new()
	def.part_key = key
	def.display_name_key = &"part.core.utility.hauler.t2.name"
	def.description_key = &"part.core.utility.hauler.t2.desc"
	def.part_class = PartEnums.PartClass.CORE_MODULE
	def.tier = PartEnums.TierGrade.STANDARD

	def.occupancy_cells = PartAuthoring.box_cells(UTILITY_LO, UTILITY_HI)
	def.attachment_nodes = PartAuthoring.face_nodes(UTILITY_LO, UTILITY_HI, CHASSIS_FACES)

	# 160 kg/m³, below the road hull's 257 and above the airframe's 105: a tall
	# box is mostly volume. The reference is 6.4 t over about 40 m³ of envelope,
	# which is the same figure.
	def.mass_kg = 3000.0
	def.com_offset_m = PartAuthoring.box_centre_m(UTILITY_LO, UTILITY_HI)
	def.inertia_box_half_extents_m = Vector3.ZERO

	def.integrity_max = 5200.0
	def.resistance = PackedFloat32Array([0.15, 0.20, 0.25, 0.10, 0.05])
	def.armour_rating = 24.0
	# §10.1 publishes no load capacity for Core Modules; as with every other
	# chassis, the whole Assembly hangs off this part.
	def.load_capacity_kg = 12000.0
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID

	var core := CoreModuleProfile.new()
	core.locomotion_mask = PartEnums.CHASSIS_WHEELED
	core.power_capacity_pu = 560.0
	core.mount_budget = 32
	core.speed_cap_mps = 18.0
	core.control_authority = 1.0
	core.mass_tolerance_kg = 8200.0
	core.operator_seat_offset_m = Vector3(0.0, 0.35, 0.0)
	core.respawn_integrity_fraction = 1.0
	def.core_profile = core

	# §10 publishes no build costs. Between the command core's 900 and the
	# tracked hull's 1300, which is where the vehicle sits in every other column.
	def.build_cost = 1100
	def.mount_weight = 0

	return PartAuthoring.save_part(
		def,
		"core",
		PartAuthoring.single_box_collider(UTILITY_LO, UTILITY_HI),
		&"plate_std"
	)
