class_name PartEnums
extends RefCounted
## Every enumeration in the part data model, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §4.
##
## Integer values are frozen: they appear in serialised save data and network
## packets and MUST NOT be renumbered. New members append only.

enum PartClass {
	CORE_MODULE = 0,
	STRUCTURAL_COMPONENT = 1,
	MOTIVE_ASSEMBLY = 2,
	PRIME_MOVER = 3,
	EFFECTOR_MODULE = 4,
	SUPPORT_MODULE = 5,
	CONTROL_SURFACE = 6,
	ENERGY_CELL = 7,
}

enum MotiveKind {
	WHEELED_STEERED = 0,
	WHEELED_FIXED = 1,
	TRACKED_SEGMENT = 2,
	OMNI_ROLLER = 3,
	AMBULATORY_LIMB = 4,
	REPULSOR_PAD = 5,
	ROTOR_DISC = 6,
}

## Which solver in [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] moves an Assembly
## carrying a given [enum MotiveKind]. Derived, never authored.
enum LocomotionMode {
	GROUND = 0,  # doc 05 §6 suspension + §7 traction
	ROTARY = 1,  # doc 05 §12 rotor lift and tilt
	AMBULATORY = 2,  # doc 05 §13 gait
	TRACKED = 3,  # doc 05 §14 road stations and differential drive
}

## Indexed by [enum MotiveKind], and frozen alongside the enum it indexes.
##
## This exists so that no subsystem outside [MotiveSystem] ever branches on
## [enum MotiveKind]: family selection is one array index, and a fourth family
## is an append here rather than a new branch in every consumer. Doc 01 §4.1.
const LOCOMOTION_OF_MOTIVE_KIND: Array[int] = [
	LocomotionMode.GROUND,  # WHEELED_STEERED
	LocomotionMode.GROUND,  # WHEELED_FIXED
	LocomotionMode.TRACKED,  # TRACKED_SEGMENT
	LocomotionMode.GROUND,  # OMNI_ROLLER
	LocomotionMode.AMBULATORY,  # AMBULATORY_LIMB
	LocomotionMode.GROUND,  # REPULSOR_PAD
	LocomotionMode.ROTARY,  # ROTOR_DISC
]

enum EffectorKind {
	BALLISTIC_DIRECT = 0,
	BALLISTIC_ARCED = 1,
	CONTINUOUS_BEAM = 2,
	GUIDED_ORDNANCE = 3,
	KINETIC_MELEE = 4,
	ENERGY_MELEE = 5,
}

enum DamageChannel {
	KINETIC = 0,
	BLAST = 1,
	IMPACT = 2,
	THERMAL = 3,
	CORROSIVE = 4,
}

const DAMAGE_CHANNEL_COUNT: int = 5

enum IntegrityBand {
	NOMINAL = 0,
	STRESSED = 1,
	IMPAIRED = 2,
	CRITICAL = 3,
	DESTROYED = 4,
}

enum TierGrade {
	SALVAGE = 1,
	STANDARD = 2,
	REFINED = 3,
	PROTOTYPE = 4,
	APEX = 5,
}

enum AttachmentPolarity {
	FACE_MALE = 0,  # protrudes; mates with FACE_FEMALE
	FACE_FEMALE = 1,  # recessed; mates with FACE_MALE
	FACE_NEUTRAL = 2,  # mates with any face type
	AXLE = 3,  # Motive Assemblies only
	DECK = 4,  # upward-facing Effector/Support mounting surface
}

enum OcclusionProfile {
	OPAQUE_SOLID = 0,  # blocks blast line of sight fully
	LATTICE_POROUS = 1,  # 50% blast LOS attenuation
	TRANSPARENT = 2,  # no blast LOS attenuation
}

## Number of distinct integrity bands. [code]DegradationTable[/code] arrays are
## validated against this length by tests/arch/test_degradation_table.gd.
const INTEGRITY_BAND_COUNT: int = 5

## Number of part classes; sizes the per-class bucket arrays in PartRegistry.
const PART_CLASS_COUNT: int = 8

## Number of attachment polarities; sizes the mating matrix in [AttachmentNodeDef].
const ATTACHMENT_POLARITY_COUNT: int = 5

## Number of Motive Assembly kinds. Asserted against
## [constant LOCOMOTION_OF_MOTIVE_KIND]'s length so that appending a kind
## without giving it a locomotion family fails the suite rather than reading
## GROUND off the end of the array.
const MOTIVE_KIND_COUNT: int = 7

## Number of Effector Module kinds.
const EFFECTOR_KIND_COUNT: int = 6


## The locomotion family that moves an Assembly carrying [param kind].
##
## The single point at which a [enum MotiveKind] becomes a solver choice.
## Out-of-range input returns GROUND and pushes an error rather than reading
## past the array: an unmapped kind is a data error, and silently treating it as
## a wheel is how one would ship.
static func locomotion_of(kind: int) -> int:
	if kind < 0 or kind >= LOCOMOTION_OF_MOTIVE_KIND.size():
		push_error("PartEnums: MotiveKind %d has no locomotion family" % kind)
		return LocomotionMode.GROUND
	return LOCOMOTION_OF_MOTIVE_KIND[kind]


## True when [param kind] is one of the two melee [enum EffectorKind] values.
##
## Melee is a property of two kinds rather than one, and every consumer that
## needs the distinction — the validator, the emission loop, the melee solver —
## would otherwise write the same two-way comparison and one of them would
## eventually forget [constant EffectorKind.ENERGY_MELEE].
static func is_melee_effector(kind: int) -> bool:
	return kind == EffectorKind.KINETIC_MELEE or kind == EffectorKind.ENERGY_MELEE
