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
	POWER_PLANT = 3,
	EFFECTOR_MODULE = 4,
	SUPPORT_MODULE = 5,
	CONTROL_SURFACE = 6,
}

enum MotiveKind {
	WHEELED_STEERED = 0,
	WHEELED_FIXED = 1,
	TRACKED_SEGMENT = 2,
	OMNI_ROLLER = 3,
	AMBULATORY_LIMB = 4,
	REPULSOR_PAD = 5,
}

enum EffectorKind {
	BALLISTIC_DIRECT = 0,
	BALLISTIC_ARCED = 1,
	CONTINUOUS_BEAM = 2,
	GUIDED_ORDNANCE = 3,
	KINETIC_MELEE = 4,
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
const PART_CLASS_COUNT: int = 7

## Number of attachment polarities; sizes the mating matrix in [AttachmentNodeDef].
const ATTACHMENT_POLARITY_COUNT: int = 5
