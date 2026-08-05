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
	## An articulated appendage that carries an Effector Module in a GRIP rather
	## than bolting it to structure. Doc 01 §7.8.
	APPENDAGE = 8,
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

## Number of locomotion families; sizes the bit range of a chassis mask.
const LOCOMOTION_MODE_COUNT: int = 4

## ===== CHASSIS MASKS ===================================================
## Which locomotion families a Core Module is built to carry, as one bit per
## [enum LocomotionMode]. Owned by doc 01 §7.1 and read through
## [member CoreModuleProfile.locomotion_mask].
##
## A mask rather than a single family, because the two ground-contact families
## genuinely share a chassis: doc 01 §4.1 routes `TRACKED` through its own solver
## for the shape of its contact set and not because a tracked machine is built
## differently from a wheeled one. Rotary and ambulatory do not share with
## anything, which is the whole point of the split.

## A hull that stands on the ground, on contacts or on road stations.
const CHASSIS_GROUND: int = (1 << LocomotionMode.GROUND) | (1 << LocomotionMode.TRACKED)
## A body slung between limbs.
const CHASSIS_AMBULATORY: int = 1 << LocomotionMode.AMBULATORY
## A body slung under discs.
const CHASSIS_ROTARY: int = 1 << LocomotionMode.ROTARY

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
	## An Appendage's hand. Keyed exactly as AXLE is (doc 01 §4.2): it mates only
	## with another GRIP, so a held Effector Module cannot be bolted to structure
	## and a bolted one cannot be picked up. Doc 01 §4.3.
	GRIP = 5,
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
const PART_CLASS_COUNT: int = 9

## Number of attachment polarities; sizes the mating matrix in [AttachmentNodeDef].
const ATTACHMENT_POLARITY_COUNT: int = 6

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


## True when a chassis carrying [param mask] admits locomotion [param mode].
##
## An out-of-range family answers false rather than reading past the bit range:
## a locomotion mode with no bit is a data error, and admitting it silently is
## how a limb ends up on a chassis with no gait behind it.
static func chassis_carries(mask: int, mode: int) -> bool:
	if mode < 0 or mode >= LOCOMOTION_MODE_COUNT:
		push_error("PartEnums: LocomotionMode %d has no chassis bit" % mode)
		return false
	return (mask & (1 << mode)) != 0


## True when [param kind] is one of the two melee [enum EffectorKind] values.
##
## Melee is a property of two kinds rather than one, and every consumer that
## needs the distinction — the validator, the emission loop, the melee solver —
## would otherwise write the same two-way comparison and one of them would
## eventually forget [constant EffectorKind.ENERGY_MELEE].
static func is_melee_effector(kind: int) -> bool:
	return kind == EffectorKind.KINETIC_MELEE or kind == EffectorKind.ENERGY_MELEE


## Localisation key naming each [enum PartClass], indexed by the enum. Doc 01
## §2's terminology table, as the strings a player reads.
##
## Here rather than in the interface, because the vocabulary CLAUDE.md §8 makes
## binding is a property of the domain and not of one screen: the catalogue, the
## inspector, the validator's rejection strip and the diagnostics overlay all
## name a class, and four tables would be four chances to write "wheel".
const CLASS_NAME_KEYS: Array[StringName] = [
	&"part.class.core_module",
	&"part.class.structural_component",
	&"part.class.motive_assembly",
	&"part.class.prime_mover",
	&"part.class.effector_module",
	&"part.class.support_module",
	&"part.class.control_surface",
	&"part.class.energy_cell",
	&"part.class.appendage",
]

## Prefix on a tier grade, as it appears in a part key's last segment.
const TIER_PREFIX: String = "T"


## Localisation key for [param part_class].
##
## An out-of-range class answers the Structural Component key and pushes an
## error, for [method locomotion_of]'s reason: it is a data error, and reading
## past the array would take down the screen a player is building on.
static func class_key(part_class: int) -> StringName:
	if part_class < 0 or part_class >= CLASS_NAME_KEYS.size():
		push_error("PartEnums: PartClass %d has no name key" % part_class)
		return CLASS_NAME_KEYS[PartClass.STRUCTURAL_COMPONENT]
	return CLASS_NAME_KEYS[part_class]


## [param tier] as it is written on a part card and in a part key: "T2".
##
## Not localised, and deliberately: the grade is the number in
## [code]mot.wheeled.allroad.t2[/code], so a player reading a card and a player
## reading a key are reading the same token.
static func tier_label(tier: int) -> String:
	return TIER_PREFIX + str(tier)
