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
