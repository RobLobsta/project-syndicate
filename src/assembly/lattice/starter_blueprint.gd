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
## A wheeled build: a Core Module, a Prime Mover, an Energy Cell, an autocannon
## on the nose, and four contacts on four stations. Integer coordinates
## throughout (Invariant I-6).

const CORE_KEY: StringName = &"core.command.compact.t2"
const HUB_KEY: StringName = &"str.hub.axle_station.t2"
const WHEEL_KEY: StringName = &"mot.wheeled.allroad.t2"
const REAR_KEY: StringName = &"mot.wheeled.fixed_rear.t2"
const POWER_KEY: StringName = &"pmv.combustion.standard.t2"
const CELL_KEY: StringName = &"cel.static.standard.t3"
const EFFECTOR_KEY: StringName = &"eff.ballistic.autocannon_30.t3"

const CORE_CELL := Vector3i(24, 4, 24)
const POWER_CELL := Vector3i(24, 7, 24)
const CELL_CELL := Vector3i(24, 4, 29)
## On the nose, at the Core Module's own height. What decides whether a round of
## the shipped autocannon flips the shipped chassis is not the impulse but the
## height of the muzzle above the centre of mass, because the fore-aft offset is
## parallel to the recoil and contributes no moment at all. On the roof one round
## is 3.6 rad/s of pitch. Here it is a shove.
const EFFECTOR_CELL := Vector3i(24, 6, 21)

const HUB_CELLS: Array[Vector3i] = [
	Vector3i(22, 2, 23), Vector3i(26, 2, 23), Vector3i(22, 2, 27), Vector3i(26, 2, 27)
]
const CONTACT_CELLS: Array[Vector3i] = [
	Vector3i(19, 3, 22), Vector3i(19, 3, 28), Vector3i(28, 3, 21), Vector3i(28, 3, 27)
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
