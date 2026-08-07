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
const CORE_CELLS: Vector3i = Vector3i(8, 4, 14)
const CORE_MASS_KG: float = 1800.0
const CORE_INTEGRITY: float = 4200.0
const CORE_ARMOUR: float = 18.0
const CORE_POWER_CAPACITY_PU: float = 520.0
const CORE_MOUNT_BUDGET: int = 28
const CORE_SPEED_CAP_MPS: float = 24.0
const CORE_MASS_TOLERANCE_KG: float = 5300.0
const CORE_RESISTANCE: Array[float] = [0.15, 0.20, 0.25, 0.10, 0.05]

## §10.1's two family-locked chassis, quoted.
##
## [b]They no longer share a section, and the section is the assertion worth
## having.[/b] Both were 6x4x9 — the command core's box, shorter along Z — on the
## reading that a shared section keeps every flank and deck mount cell the same
## across families. §10.1 records why that was reversed in session 44: a walking
## torso is taller than it is long and a rotorcraft fuselage is ten times longer
## than it is wide, and one box expresses neither. Each is quoted separately
## below, because a shared constant is exactly how the two silently converged.
const STRIDER_KEY: StringName = &"core.ambulatory.strider.t3"
const LIFTER_KEY: StringName = &"core.rotary.lifter.t3"
const STRIDER_CELLS: Vector3i = Vector3i(6, 10, 10)
const LIFTER_CELLS: Vector3i = Vector3i(4, 6, 28)
const STRIDER_MASS_KG: float = 1800.0
const STRIDER_INTEGRITY: float = 3600.0
const STRIDER_ARMOUR: float = 20.0
const STRIDER_POWER_CAPACITY_PU: float = 560.0
const STRIDER_MOUNT_BUDGET: int = 34
const STRIDER_SPEED_CAP_MPS: float = 12.0
const STRIDER_MASS_TOLERANCE_KG: float = 7400.0
const STRIDER_RESISTANCE: Array[float] = [0.18, 0.16, 0.30, 0.10, 0.05]
const LIFTER_MASS_KG: float = 1100.0
const LIFTER_INTEGRITY: float = 2400.0
const LIFTER_ARMOUR: float = 10.0
const LIFTER_POWER_CAPACITY_PU: float = 640.0
const LIFTER_MOUNT_BUDGET: int = 26
const LIFTER_SPEED_CAP_MPS: float = 34.0
const LIFTER_MASS_TOLERANCE_KG: float = 5200.0
const LIFTER_RESISTANCE: Array[float] = [0.08, 0.14, 0.12, 0.10, 0.05]

const PANEL_KEY: StringName = &"str.panel.medium.t2"
const PANEL_CELLS: Vector3i = Vector3i(4, 1, 4)
const PANEL_MASS_KG: float = 100.0
const PANEL_INTEGRITY: float = 380.0
const PANEL_ARMOUR: float = 14.0
const PANEL_LOAD_CAPACITY_KG: float = 1560.0
const PANEL_RESISTANCE: Array[float] = [0.18, 0.10, 0.20, 0.05, 0.05]

## Exposed cell faces of a solid box, which is what both parts are. The Core
## Module's 8x4x14 gives 2*(8*4 + 4*14 + 8*14) = 400; the panel's 4x1x4 gives 48.
const CORE_NODE_COUNT: int = 400
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

## Every key the registry ships, in manifest order. Asserted as a list rather
## than a count: a count catches a part that vanished, and only the list catches
## a part that was reordered, which is the failure that reinterprets every
## blueprint ever written (§5.2).
const SHIPPED_KEYS: Array[String] = [
	"core.command.compact.t2",
	"str.panel.medium.t2",
	"str.hub.axle_station.t2",
	"mot.wheeled.allroad.t2",
	"mot.tracked.short_bogie.t2",
	"mot.rotor.coaxial_mid.t3",
	"mot.limb.strider.t4",
	"pmv.combustion.standard.t2",
	"eff.melee.beam_edge.t4",
	# Appended, never inserted. `part_def_id` is the manifest index plus one and
	# is serialised into save data and network packets, so a key that moved
	# reinterprets every blueprint ever written (§5.2). A wheeled part belongs
	# next to the other wheeled part in a catalogue and at the end of this list,
	# and those are different orderings on purpose.
	"mot.wheeled.fixed_rear.t2",
	"cel.static.standard.t3",
	"eff.ballistic.autocannon_30.t3",
	"apx.arm.manipulator.t3",
	"eff.ballistic.repeater_12.t2",
	"core.ambulatory.strider.t3",
	"core.rotary.lifter.t3",
	"core.tracked.hauler.t3",
	# Session 44's five reference vehicles. Four of these exist because a
	# silhouette the shipping set could not express needed them (doc 01 §10.1 and
	# §10.3): a 6.00 m gun, two 0.75 m road contacts, a bogie as long as the hull
	# it carries, a Prime Mover that lies down, and a hull as tall as it is wide.
	"eff.ballistic.rifle_long.t3",
	"mot.wheeled.light_road.t1",
	"mot.wheeled.light_fixed.t1",
	"mot.tracked.long_bogie.t3",
	"pmv.combustion.flat.t2",
	"core.utility.hauler.t2",
	# Session 44. The pylon exists because a 1.00 m fuselage cannot hold its own
	# discs apart (§10.2); the biped torso exists because doc 05 §13.10 gave a
	# foot an extent, which is what stopped fore-and-aft stability being the same
	# cells as torso depth (§10.1).
	"str.outrigger.pylon.t2",
	"core.biped.humanoid.t3",
	# Session 46. One Prime Mover per locomotion family, per doc 01 §7.3's mask.
	# Two movers used to carry four families between them — a tank, a mech and a
	# rotorcraft all ran a road car's 6400 N·m — so no family's torque could be
	# tuned without moving the other three.
	"pmv.turbine.tracked.t3",
	"pmv.combustion.strider.t3",
	"pmv.turboshaft.rotary.t3",
	# Session 47. A second limb row, because doc 05 §13.10's ankle clamp is
	# `N × half-extent` and a two-limbed Assembly in single support has nothing
	# else — so the foot that is generous under four limbs is 6.8° of recoverable
	# tilt under two, and the shipped biped landed on its face on every turn.
	"mot.limb.broad_foot.t4",
]


func test_registry_publishes_every_shipped_part() -> void:
	check_eq(PartRegistry.part_count(), SHIPPED_KEYS.size(), "every shipped part is registered")
	for i: int in SHIPPED_KEYS.size():
		var key := StringName(SHIPPED_KEYS[i])
		if not check_true(PartRegistry.has_key(key), "%s is registered" % key):
			continue
		# §5.2: part_def_id is the manifest index plus one. Asserting the id
		# against the position in this list is what makes an append-only
		# manifest testable — a reorder moves an id and this fails.
		check_eq(
			PartRegistry.definition_by_key(key).runtime_id,
			i + 1,
			"%s is manifest entry %d, so id %d" % [key, i, i + 1]
		)


## §5.2: part_def_id is the manifest index plus one, and index 0 is reserved.
## These ids go into save data and network packets, so a shift here silently
## reinterprets every blueprint ever written.
## The reserved id and the reverse direction of the id map.
##
## The forward direction — key to id — is owned by
## [code]test_registry_publishes_every_shipped_part[/code], which walks the whole
## manifest. This asserts only what that one does not: that id 0 stays reserved,
## and that an id resolves back to the definition it was taken from. Splitting
## them this way keeps one owner per invariant; asserting the forward map here as
## well would leave neither test load-bearing.
func test_part_ids_reverse_resolve() -> void:
	check_null(PartRegistry.definition(PartManifest.INVALID_PART_ID), "id 0 is INVALID_PART")
	for key_text: String in SHIPPED_KEYS:
		var def := PartRegistry.definition_by_key(StringName(key_text))
		if not check_not_null(def, "%s resolves by key" % key_text):
			continue
		check_eq(
			PartRegistry.definition(def.runtime_id),
			def,
			"id %d resolves back to %s" % [def.runtime_id, key_text]
		)


func test_class_buckets_are_populated() -> void:
	check_eq(
		PartRegistry.ids_of_class(PartEnums.PartClass.CORE_MODULE).size(),
		6,
		(
			"one chassis per locomotion family — wheeled, tracked, ambulatory, rotary — "
			+ "a second wheeled one because a road car and a utility truck disagree "
			+ "about the section before anything else, and a second ambulatory one "
			+ "because a biped's torso is not a quadruped's"
		)
	)
	check_eq(
		PartRegistry.ids_of_class(PartEnums.PartClass.STRUCTURAL_COMPONENT).size(),
		3,
		"the panel, the AXLE station and the rotor pylon"
	)
	check_eq(
		PartRegistry.ids_of_class(PartEnums.PartClass.MOTIVE_ASSEMBLY).size(),
		9,
		(
			"one Motive Assembly per locomotion family, plus a steered/fixed pair at "
			+ "0.75 m for the road car, a bogie long enough for a hull, and a second "
			+ "limb row whose foot is sized for a machine that stands on one of them"
		)
	)
	check_eq(
		PartRegistry.ids_of_class(PartEnums.PartClass.PRIME_MOVER).size(),
		5,
		(
			"five Prime Movers: the wheeled family's square and flat sections, and one "
			+ "each for the tracked, ambulatory and rotary families"
		)
	)
	check_eq(
		PartRegistry.ids_of_class(PartEnums.PartClass.ENERGY_CELL).size(), 1, "and one Energy Cell"
	)
	check_eq(
		PartRegistry.ids_of_class(PartEnums.PartClass.EFFECTOR_MODULE).size(),
		4,
		(
			"a powered edge and three direct-fire modules: one per resolution path, "
			+ "a second ballistic row so the recoil trade is a choice, and a 6.00 m "
			+ "gun for the family that is built around carrying one"
		)
	)
	check_eq(
		PartRegistry.ids_of_class(PartEnums.PartClass.SUPPORT_MODULE).size(),
		0,
		"no Support Modules are authored yet, and an empty bucket is not an error"
	)
	# The bucket sizes must account for every registered part, or a definition is
	# reaching the registry without landing in a class bucket at all.
	var total := 0
	for c: int in PartEnums.PART_CLASS_COUNT:
		total += PartRegistry.ids_of_class(c).size()
	check_eq(total, PartRegistry.part_count(), "every part lands in exactly one class bucket")


## Every locomotion family has a real part behind it, so nothing in the motion
## layer is exercised only by a synthetic fixture.
func test_every_locomotion_family_has_a_shipped_part() -> void:
	var seen := {}
	for id: int in PartRegistry.ids_of_class(PartEnums.PartClass.MOTIVE_ASSEMBLY):
		var profile := PartRegistry.definition(id).motive_profile
		if check_not_null(profile, "a Motive Assembly carries a motive_profile"):
			seen[profile.locomotion_mode()] = true
	for mode: int in [
		PartEnums.LocomotionMode.GROUND,
		PartEnums.LocomotionMode.TRACKED,
		PartEnums.LocomotionMode.ROTARY,
		PartEnums.LocomotionMode.AMBULATORY,
	]:
		check_true(seen.has(mode), "locomotion family %d has a shipped part" % mode)


func test_manifest_hash_is_order_sensitive_and_non_zero() -> void:
	check_ne(PartRegistry.manifest_hash(), 0, "a populated registry hashes to something")

	# The handshake must reject a peer whose manifest lists the same keys in a
	# different order: every part_def_id would disagree.
	var forward := PartManifest.new()
	forward.keys = PackedStringArray(SHIPPED_KEYS)
	var reversed := PartManifest.new()
	var backwards := SHIPPED_KEYS.duplicate()
	backwards.reverse()
	reversed.keys = PackedStringArray(backwards)
	check_eq(
		forward.compute_content_hash(),
		PartRegistry.manifest_hash(),
		"the shipped manifest is SHIPPED_KEYS in that order"
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
	check_eq(def.bounds_size_cells, CORE_CELLS, "§10.1 gives 8x4x14 cells")
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

	# §7.1's mask, as a set. One family per chassis throughout — `CHASSIS_GROUND`
	# used to carry GROUND and TRACKED together on the reading that a tracked
	# machine is a wheeled one with a different contact set, and that reading cost
	# the tracked family a hull thirteen cells long over a 1.42 m contact base.
	check_true(profile.carries(PartEnums.LocomotionMode.GROUND), "carries rolling contacts")
	# [b]This was asserted as a defect and the defect has closed.[/b] The road hull
	# accepted a bogie through `CHASSIS_GROUND_TRANSITIONAL`, which the comment
	# above said would go false "when the shipped recipe migrates onto
	# `core.tracked.hauler.t3`". Session 44 migrated it; §7.3's Prime Mover mask is
	# what finally made the vestigial bit cost something, because a hull declaring
	# a family it does not use refuses every mover that does not drive that family.
	check_false(
		profile.carries(PartEnums.LocomotionMode.TRACKED),
		"and no longer a bogie: the transitional ground mask is retired"
	)
	check_false(profile.carries(PartEnums.LocomotionMode.AMBULATORY), "and refuses a limb")
	check_false(profile.carries(PartEnums.LocomotionMode.ROTARY), "and refuses a disc")


## §10.1's two family chassis, and the mask that is the whole reason they exist.
##
## The masks are asserted as [i]sets[/i] — every family, admitted or refused —
## rather than by comparing the integer against [constant
## PartEnums.CHASSIS_AMBULATORY]. A test that reads the same constant the data
## does asserts nothing (LEARNED_FACTS.md §2): a mask authored as `CHASSIS_ROTARY`
## on the strider would satisfy the comparison the moment somebody changed the
## constant, and would satisfy nothing here.
func test_the_family_chassis_match_the_documented_table() -> void:
	_check_family_chassis(
		STRIDER_KEY,
		STRIDER_CELLS,
		STRIDER_MASS_KG,
		STRIDER_INTEGRITY,
		STRIDER_ARMOUR,
		STRIDER_RESISTANCE,
		PartEnums.LocomotionMode.AMBULATORY
	)
	_check_family_chassis(
		LIFTER_KEY,
		LIFTER_CELLS,
		LIFTER_MASS_KG,
		LIFTER_INTEGRITY,
		LIFTER_ARMOUR,
		LIFTER_RESISTANCE,
		PartEnums.LocomotionMode.ROTARY
	)

	var strider := PartRegistry.definition_by_key(STRIDER_KEY)
	var lifter := PartRegistry.definition_by_key(LIFTER_KEY)
	if strider == null or lifter == null:
		return
	check_approx(
		strider.core_profile.power_capacity_pu, STRIDER_POWER_CAPACITY_PU, "strider power capacity"
	)
	check_eq(strider.core_profile.mount_budget, STRIDER_MOUNT_BUDGET, "strider mount budget")
	check_approx(strider.core_profile.speed_cap_mps, STRIDER_SPEED_CAP_MPS, "strider speed cap")
	check_approx(
		strider.core_profile.mass_tolerance_kg,
		STRIDER_MASS_TOLERANCE_KG,
		"strider mass tolerance"
	)
	check_approx(
		lifter.core_profile.power_capacity_pu, LIFTER_POWER_CAPACITY_PU, "lifter power capacity"
	)
	check_eq(lifter.core_profile.mount_budget, LIFTER_MOUNT_BUDGET, "lifter mount budget")
	check_approx(lifter.core_profile.speed_cap_mps, LIFTER_SPEED_CAP_MPS, "lifter speed cap")
	check_approx(
		lifter.core_profile.mass_tolerance_kg, LIFTER_MASS_TOLERANCE_KG, "lifter mass tolerance"
	)

	# The four limbs and their stations cost twenty of these, which against the
	# ground chassis's twenty-eight left two and an Energy Cell costs three.
	# §10.1 records that as the figure that changes a build.
	check_true(
		strider.core_profile.mount_budget > PartRegistry.definition_by_key(
			CORE_KEY
		).core_profile.mount_budget,
		"a walking Assembly has the mounts for supply that a ground one does not"
	)


func _check_family_chassis(
	key: StringName,
	cells: Vector3i,
	mass_kg: float,
	integrity: float,
	armour: float,
	resistance: Array[float],
	family: int
) -> void:
	var def := PartRegistry.definition_by_key(key)
	if not check_not_null(def, "%s must load" % key):
		return
	check_eq(def.part_class, PartEnums.PartClass.CORE_MODULE, "%s class" % key)
	check_eq(def.tier, PartEnums.TierGrade.REFINED, "%s t3 is REFINED" % key)
	check_eq(def.bounds_size_cells, cells, "%s §10.1 gives %v cells" % [key, cells])
	check_approx(def.mass_kg, mass_kg, "%s mass" % key)
	check_approx(def.integrity_max, integrity, "%s integrity" % key)
	check_approx(def.armour_rating, armour, "%s armour" % key)
	_check_resistance(def, resistance)
	check_eq(def.mount_weight, 0, "%s costs no mounts" % key)

	var profile := def.core_profile
	if not check_not_null(profile, "%s payload must survive the round trip" % key):
		return
	for mode: int in PartEnums.LOCOMOTION_MODE_COUNT:
		check_eq(
			profile.carries(mode),
			mode == family,
			"%s carries family %d: %s" % [key, mode, mode == family]
		)


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
