class_name StarterBlueprint
extends RefCounted
## The hand-authored build a player opens the garage on and every opponent is
## spawned from, named by doc 06 §12's onboarding row.
##
## Doc 06's generator will eventually produce an opponent from an archetype and a
## seed. Until it does, a match needs a build that is known to fight, and the
## garage needs something on the lattice when it opens — a player dropped into an
## empty build volume with a catalogue and no Core Module has to guess the one
## rule (Invariant I-2) that nothing on the screen states.
##
## [b]This is the one place the shipped recipe is written down.[/b] It lived in
## [MatchScreen] as a block of constants and in [code]tests/combat_arena.gd[/code]
## as another; the arena keeps its own because a fixture that shared the
## production build would stop being able to vary it, and that is the
## [i]deliberate[/i] second copy CLAUDE.md §1.1 tolerates. A third would not be.

## ===== THE SKIRMISHER ==================================================
## A mid-engine road car: a Core Module, a Prime Mover behind the cabin, a
## rapid-fire Effector Module on the rear deck, and four contacts on four
## stations. Integer coordinates throughout (Invariant I-6).

const CORE_KEY: StringName = &"core.command.compact.t2"
const HUB_KEY: StringName = &"str.hub.axle_station.t2"
## The 0.75 m contacts. Doc 01 §10.3 sizes them off the reference road car, whose
## wheel is 0.15 of its own length; `mot.wheeled.allroad.t2` at 1.00 m is 0.20 of
## this machine and is the utility truck's contact rather than this one's.
const WHEEL_KEY: StringName = &"mot.wheeled.light_road.t1"
const REAR_KEY: StringName = &"mot.wheeled.light_fixed.t1"
## `pmv.combustion.flat.t2` rather than `pmv.combustion.standard.t2`, and the two
## are the same twenty-four cells of section with identical published figures
## (doc 01 §10.4). What differs is where it can go: the square row is 1.00 m tall
## and has to stand on the deck of a 1.00 m hull, which doubles the height of the
## vehicle and makes a mid-engine road car read as a pickup. The flat row mates to
## the hull's tail at deck level and is the engine bay behind the cabin.
const POWER_KEY: StringName = &"pmv.combustion.flat.t2"
const CELL_KEY: StringName = &"cel.static.standard.t3"
## `eff.ballistic.repeater_12.t2` rather than `eff.ballistic.autocannon_30.t3`,
## and this one line is most of what a first-time player feels.
##
## Doc 07 §8 applies the recoil at the muzzle, so a mount traversed across the
## hull yaws it by `impulse × lever ÷ I_yy` — and the shipped autocannon's
## 1450 N·s through this mount's lever is 0.85 rad/s of yaw from a single round,
## which is more than the wheeled family's whole steering authority. An Assembly
## carrying it could drive or shoot and not both, which is the first thing a
## player tries to do. The repeater's 26 N·s is thirty times less sustained
## torque for two thirds of the throughput, and doc 01 §10.5 records the trade in
## full. The autocannon is still in the catalogue and is still the module that
## punches through a hull; it is no longer the one a player is handed before they
## know what a mount does.
const EFFECTOR_KEY: StringName = &"eff.ballistic.repeater_12.t2"

## The Core Module spans `x` 20–27, `y` 4–7 and `z` 17–30, which is the fact every
## cell below is placed against.
##
## [b]It is a mid-engine road car now, and the shape is measured rather than
## chosen.[/b] Doc 01 §10.1 derives 8×4×14 — 2.00 m by 1.00 m by 3.50 m — from a
## reference whose height is 0.26 of its length and whose width is 0.42 of it. The
## hull it replaces was 6×4×13 and produced a finished Assembly about 2.75 m tall
## on a 4.00 m footprint, which is a ratio of 0.69: the right density and the
## wrong machine.
const CORE_CELL := Vector3i(24, 4, 24)
## Behind the cabin at deck level rather than on the roof, which is the whole of
## why this reads as a car. See [constant POWER_KEY].
const POWER_CELL := Vector3i(24, 4, 34)
## In the tail behind the engine bay, for a build that wants supply.
const CELL_CELL := Vector3i(24, 4, 39)
## On the rear deck, over the cabin's back half. What decides whether a round
## flips the chassis is not the impulse alone but the height of the muzzle above
## the centre of mass, because the fore-aft offset is parallel to the recoil and
## contributes no moment at all — so a mount at the Core Module's own height
## costs a rock rather than a backflip.
const EFFECTOR_CELL := Vector3i(24, 8, 29)

## The stations sit inboard of the two flanks at `x` 20–21 and 26–27, under the
## cabin's two ends at `z` 18–19 and 28–29. That is a 2.50 m wheelbase under a
## 5.00 m machine — 50%, against the reference's 58%.
const HUB_CELLS: Array[Vector3i] = [
	Vector3i(21, 2, 19), Vector3i(27, 2, 19), Vector3i(21, 2, 29), Vector3i(27, 2, 29)
]
## [b]The two flanks are square with each other, and they did not use to be.[/b]
## `mot.wheeled.allroad.t2` is four cells across so its local extent runs −2..1
## and is off-centre by one; mirroring it shifted its world span by a cell, and
## these cells carried a one-cell offset between flanks with a comment insisting
## it was not doc 02 §10's old off-by-one. `mot.wheeled.light_road.t1` is three
## across — −1..1, symmetric — so the mirror is exact and both flanks take the
## same `z`. `test_the_shipped_starter_is_its_own_mirror` still guards it.
const CONTACT_CELLS: Array[Vector3i] = [
	Vector3i(18, 3, 19), Vector3i(18, 3, 29), Vector3i(29, 3, 19), Vector3i(29, 3, 29)
]
## Contacts forward of this row steer; the pair behind it is fixed. An Assembly
## on which every contact steers crabs instead of turning; see CHANGE_LOG.md,
## session 12.
const FRONT_AXLE_Z: int = 24


## The skirmisher, as a construction sequence.
##
## The order is the order a player has to build in and is not cosmetic: the
## Energy Cell precedes the autocannon because doc 05 §7.4's power budget is
## checked against what the context holds at the moment of the placement, and the
## stations precede the contacts they carry.
static func skirmisher() -> Blueprint:
	var bp := Blueprint.new()
	bp.add(CORE_KEY, CORE_CELL)
	bp.add(POWER_KEY, POWER_CELL)
	bp.add(CELL_KEY, CELL_CELL)
	bp.add(EFFECTOR_KEY, EFFECTOR_CELL)
	for cell: Vector3i in HUB_CELLS:
		bp.add(HUB_KEY, cell)
	for cell: Vector3i in CONTACT_CELLS:
		var key := WHEEL_KEY if cell.z < FRONT_AXLE_Z else REAR_KEY
		# The drive face points inboard, so the two flanks are mirror images
		# rather than four copies of one part facing the same way.
		var inboard := Vector3.RIGHT if cell.x < CORE_CELL.x else Vector3.LEFT
		bp.add(key, cell, OrientationTable.upright_facing(inboard))
	return bp


## ===== ONE PRESET PER LOCOMOTION FAMILY ================================
## [b]A reference build for each way of getting around, so that a physics change
## has five known machines to be measured against rather than one.[/b]
##
## Every layout below is the one `tests/combat_arena.gd` fights with, cell for
## cell. That is deliberately a [b]second[/b] copy and not a third: CLAUDE.md §1.1
## tolerates exactly two — this file, which is what a player gets, and the arena,
## which is what the suite measures — and `tests/unit/test_family_presets.gd`
## asserts that the two agree part for part, so a layout that moves in one and not
## the other fails the build rather than quietly becoming two different machines.
##
## Each preset is authored in [b]placement order[/b], which is the order a player
## has to build in and the order [PlacementValidator] enforces: a station before
## the Motive Assembly that hangs off it, supply before draw, and an Appendage
## before anything it is asked to hold.

const TRACKED_CORE_KEY: StringName = &"core.tracked.hauler.t3"
const AMBULATORY_CORE_KEY: StringName = &"core.ambulatory.strider.t3"
const BIPED_CORE_KEY: StringName = &"core.biped.humanoid.t3"
const ROTARY_CORE_KEY: StringName = &"core.rotary.lifter.t3"
const UTILITY_CORE_KEY: StringName = &"core.utility.hauler.t2"

const TRACK_KEY: StringName = &"mot.tracked.long_bogie.t3"
const LIMB_KEY: StringName = &"mot.limb.strider.t4"
const ROTOR_KEY: StringName = &"mot.rotor.coaxial_mid.t3"
const UTILITY_WHEEL_KEY: StringName = &"mot.wheeled.allroad.t2"
const UTILITY_REAR_KEY: StringName = &"mot.wheeled.fixed_rear.t2"
const PYLON_KEY: StringName = &"str.outrigger.pylon.t2"
const ARM_KEY: StringName = &"apx.arm.manipulator.t3"
## The upright Prime Mover, for the hulls with the headroom for it. The
## skirmisher uses the flat row because its roof is 1.00 m off its own floor.
const BLOCK_POWER_KEY: StringName = &"pmv.combustion.standard.t2"
const CANNON_KEY: StringName = &"eff.ballistic.rifle_long.t3"
const AUTOCANNON_KEY: StringName = &"eff.ballistic.autocannon_30.t3"

## The orientation that points a station's AXLE faces up and down, for a limb or
## a rotor mast rather than a wheel.
const AXLE_DOWN_ORIENTATION: int = 8

const TRACKED_CORE_CELL := Vector3i(24, 4, 24)
const TRACKED_POWER_CELL := Vector3i(24, 9, 33)
const TRACKED_GUN_CELL := Vector3i(24, 9, 25)
const TRACK_HUB_CELLS: Array[Vector3i] = [Vector3i(20, 2, 24), Vector3i(28, 2, 24)]
const TRACK_CELLS: Array[Vector3i] = [Vector3i(17, 3, 24), Vector3i(30, 3, 23)]

const AMBULATORY_CORE_CELL := Vector3i(24, 14, 24)
const AMBULATORY_POWER_CELL := Vector3i(24, 10, 24)
const AMBULATORY_GUN_CELL := Vector3i(24, 24, 26)
## Station, then the limb hanging off it, four times.
const AMBULATORY_LEG_CELLS: Array[Vector3i] = [
	Vector3i(19, 14, 20), Vector3i(20, 13, 20),
	Vector3i(27, 14, 20), Vector3i(27, 13, 20),
	Vector3i(19, 14, 28), Vector3i(20, 13, 28),
	Vector3i(27, 14, 28), Vector3i(27, 13, 28),
]

const BIPED_CORE_CELL := Vector3i(24, 14, 24)
const BIPED_POWER_CELL := Vector3i(24, 10, 24)
const BIPED_GUN_CELL := Vector3i(24, 24, 26)
const BIPED_BACKPACK_CELL := Vector3i(24, 17, 29)
const BIPED_LEG_CELLS: Array[Vector3i] = [
	Vector3i(19, 14, 24), Vector3i(20, 13, 24),
	Vector3i(27, 14, 24), Vector3i(27, 13, 24),
]
const BIPED_SHOULDER_CELLS: Array[Vector3i] = [Vector3i(19, 21, 22), Vector3i(28, 21, 22)]
const BIPED_ARM_CELLS: Array[Vector3i] = [Vector3i(19, 20, 21), Vector3i(28, 20, 21)]

const ROTARY_CORE_CELL := Vector3i(24, 4, 24)
const ROTARY_POWER_CELL := Vector3i(24, 0, 24)
const ROTARY_CELL_CELL := Vector3i(24, 10, 32)
const ROTARY_GUN_CELL := Vector3i(24, 10, 16)
const ROTARY_PYLON_CELLS: Array[Vector3i] = [Vector3i(20, 5, 24), Vector3i(27, 5, 24)]
const ROTARY_MAST_CELLS: Array[Vector3i] = [Vector3i(17, 5, 24), Vector3i(29, 5, 24)]
const ROTARY_DISC_CELLS: Array[Vector3i] = [Vector3i(18, 7, 24), Vector3i(30, 7, 24)]

const UTILITY_CORE_CELL := Vector3i(24, 4, 24)
const UTILITY_POWER_CELL := Vector3i(24, 4, 11)
const UTILITY_GUN_CELL := Vector3i(24, 10, 26)
const UTILITY_HUB_CELLS: Array[Vector3i] = [
	Vector3i(20, 2, 17), Vector3i(28, 2, 17), Vector3i(20, 2, 31), Vector3i(28, 2, 31),
]
## The right flank sits one cell forward, because the contact's own pivot is
## off-centre in its footprint: cells that are symmetric are metres that are not
## (LEARNED_FACTS.md fact 74).
const UTILITY_CONTACT_CELLS: Array[Vector3i] = [
	Vector3i(17, 3, 17), Vector3i(17, 3, 31), Vector3i(30, 3, 16), Vector3i(30, 3, 30),
]
const UTILITY_FRONT_AXLE_Z: int = 24


## The tracked gun platform: 6.00 m of hull over 6.00 m of track, carrying the
## one barrel in the registry that overhangs its own nose.
static func tracked() -> Blueprint:
	var bp := Blueprint.new()
	bp.add(TRACKED_CORE_KEY, TRACKED_CORE_CELL)
	bp.add(BLOCK_POWER_KEY, TRACKED_POWER_CELL)
	bp.add(CANNON_KEY, TRACKED_GUN_CELL)
	for cell: Vector3i in TRACK_HUB_CELLS:
		bp.add(HUB_KEY, cell)
	for cell: Vector3i in TRACK_CELLS:
		var inboard := Vector3.RIGHT if cell.x < TRACKED_CORE_CELL.x else Vector3.LEFT
		bp.add(TRACK_KEY, cell, OrientationTable.upright_facing(inboard))
	return bp


## The four-limbed walking machine, on the chassis every gait measurement in
## `tests/physics/` was taken against.
static func ambulatory() -> Blueprint:
	var bp := Blueprint.new()
	bp.add(AMBULATORY_CORE_KEY, AMBULATORY_CORE_CELL)
	bp.add(BLOCK_POWER_KEY, AMBULATORY_POWER_CELL)
	bp.add(AUTOCANNON_KEY, AMBULATORY_GUN_CELL)
	for i: int in AMBULATORY_LEG_CELLS.size() / 2:
		bp.add(HUB_KEY, AMBULATORY_LEG_CELLS[i * 2], AXLE_DOWN_ORIENTATION)
		bp.add(LIMB_KEY, AMBULATORY_LEG_CELLS[i * 2 + 1])
	return bp


## The humanoid: two limbs, a torso taller than it is deep, a shoulder joint on
## each flank with an arm hanging from it, and a backpack that is ballast before
## it is supply.
##
## The arms are the last thing on and the shoulders the second last, which is the
## order the validator forces: an Appendage mates through its own top face and
## has nothing to mate to until the joint above it exists.
static func biped() -> Blueprint:
	var bp := Blueprint.new()
	bp.add(BIPED_CORE_KEY, BIPED_CORE_CELL)
	bp.add(BLOCK_POWER_KEY, BIPED_POWER_CELL)
	bp.add(AUTOCANNON_KEY, BIPED_GUN_CELL)
	for i: int in BIPED_LEG_CELLS.size() / 2:
		bp.add(HUB_KEY, BIPED_LEG_CELLS[i * 2], AXLE_DOWN_ORIENTATION)
		bp.add(LIMB_KEY, BIPED_LEG_CELLS[i * 2 + 1])
	bp.add(CELL_KEY, BIPED_BACKPACK_CELL)
	for cell: Vector3i in BIPED_SHOULDER_CELLS:
		bp.add(PYLON_KEY, cell)
	for cell: Vector3i in BIPED_ARM_CELLS:
		bp.add(ARM_KEY, cell)
	return bp


## The twin-disc rotorcraft. Supply before draw: the second disc is refused if
## the Energy Cell covering it is not on yet, which is the same rule a player
## meets in the garage.
static func rotary() -> Blueprint:
	var bp := Blueprint.new()
	bp.add(ROTARY_CORE_KEY, ROTARY_CORE_CELL)
	bp.add(BLOCK_POWER_KEY, ROTARY_POWER_CELL)
	bp.add(CELL_KEY, ROTARY_CELL_CELL)
	for cell: Vector3i in ROTARY_PYLON_CELLS:
		bp.add(PYLON_KEY, cell)
	for cell: Vector3i in ROTARY_MAST_CELLS:
		bp.add(HUB_KEY, cell, AXLE_DOWN_ORIENTATION)
	for cell: Vector3i in ROTARY_DISC_CELLS:
		bp.add(ROTOR_KEY, cell)
	bp.add(AUTOCANNON_KEY, ROTARY_GUN_CELL)
	return bp


## The protected utility truck: the second wheeled silhouette, on the one chassis
## in the registry that is as tall as it is wide.
static func utility() -> Blueprint:
	var bp := Blueprint.new()
	bp.add(UTILITY_CORE_KEY, UTILITY_CORE_CELL)
	bp.add(BLOCK_POWER_KEY, UTILITY_POWER_CELL)
	bp.add(EFFECTOR_KEY, UTILITY_GUN_CELL)
	for cell: Vector3i in UTILITY_HUB_CELLS:
		bp.add(HUB_KEY, cell)
	for cell: Vector3i in UTILITY_CONTACT_CELLS:
		var key := UTILITY_WHEEL_KEY if cell.z < UTILITY_FRONT_AXLE_Z else UTILITY_REAR_KEY
		var inboard := Vector3.RIGHT if cell.x < UTILITY_CORE_CELL.x else Vector3.LEFT
		bp.add(key, cell, OrientationTable.upright_facing(inboard))
	return bp


## Every preset, by the locomotion family it demonstrates. The one place a
## caller that wants "a build of each kind" should read, so that adding a family
## is an append here rather than a new branch in every consumer.
static func presets() -> Dictionary:
	return {
		&"skirmisher": skirmisher(),
		&"utility": utility(),
		&"tracked": tracked(),
		&"ambulatory": ambulatory(),
		&"biped": biped(),
		&"rotary": rotary(),
	}
