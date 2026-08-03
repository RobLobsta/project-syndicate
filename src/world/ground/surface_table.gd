class_name SurfaceTable
extends RefCounted
## Per-surface gameplay coefficients, owned by
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §9.1.
##
## [constant TRACTION] is the array [code]docs/DYNAMIC_MASS_PHYSICS.md[/code]
## §7.3 indexes. There is exactly one definition and it is this one; the physics
## document references it rather than restating it, per [code]CLAUDE.md[/code]
## §1.1. [method MotiveSystem._surface_multiplier] is the single consumer.
##
## Every lookup clamps rather than asserting. A surface id arrives from a
## [PackedByteArray] written by the deformer and read by the tick loop, and a
## corrupt byte should degrade one contact's grip rather than halt the match.

enum Surface {
	## Packed earth, tarmac, rock. The reference surface; every multiplier is 1.
	COMPACTED = 0,
	## Sand, gravel, spoil. Drives loosely and takes ruts.
	LOOSE = 1,
	## Ice, mud, wet steel. The one surface that genuinely loses a vehicle.
	SLICK = 2,
	## Crater interiors and rut beds, written by §9.2's reclassification.
	DEFORMED = 3,
	## Static Volume surfaces. Present so the lookup is total; the heightfield
	## never carries this id, because a Static Volume is not part of it.
	STRUCTURE = 4,
}

## Number of entries every table below must have. Asserted by
## [code]tests/unit/test_surface_table.gd[/code] against [enum Surface].
const SURFACE_COUNT: int = 5

## Friction multiplier applied to a contact's peak grip. §9.1.
const TRACTION: Array[float] = [1.00, 0.78, 0.42, 0.66, 1.06]

## Resistance to excavation, dividing crater depth in §3.2. [constant
## Surface.STRUCTURE]'s 3.20 means a blast on a rooftop barely craters.
const HARDNESS: Array[float] = [1.00, 0.55, 0.80, 0.62, 3.20]

## Whether a loaded contact leaves a rut. §6.
const RUTTABLE: Array[bool] = [false, true, false, true, false]

## Rolling resistance coefficient. §9.1.
const ROLL_RESIST: Array[float] = [0.014, 0.031, 0.009, 0.026, 0.011]


## Clamps [param id] into the table range.
static func _safe(id: int) -> int:
	return clampi(id, 0, SURFACE_COUNT - 1)


## Friction multiplier for [param id]. Consumed by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §7.3.
static func multiplier(id: int) -> float:
	return TRACTION[_safe(id)]


## Excavation resistance for [param id]. Divides crater depth in
## [method CraterProfile.depth_for].
static func hardness(id: int) -> float:
	return HARDNESS[_safe(id)]


## Whether [param id] accumulates ruts under load. §6.
static func is_ruttable(id: int) -> bool:
	return RUTTABLE[_safe(id)]


## Rolling resistance coefficient for [param id].
static func roll_resist(id: int) -> float:
	return ROLL_RESIST[_safe(id)]
