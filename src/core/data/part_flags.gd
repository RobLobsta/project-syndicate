class_name PartFlags
extends RefCounted
## Bitfield layout of [member PartInstanceState.flags], owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §8.1.
##
## Bit positions are frozen: the low bits are replicated in the per-part
## snapshot record (see [code]docs/HEADLESS_NETWORK_SYNC.md[/code] §5).

const FLAG_DESTROYED: int = 1 << 0  # integrity reached zero
const FLAG_DETACHED: int = 1 << 1  # severed from the Chassis Graph
const FLAG_SUBMERGED: int = 1 << 2  # contact volume inside a fluid region
const FLAG_OVERHEATED: int = 1 << 3  # heat exceeded the thermal throttle
const FLAG_JAMMED: int = 1 << 4  # Effector Module in jam recovery
const FLAG_STRAINED: int = 1 << 5  # parent joint loaded beyond joint_strength_n
const FLAG_VISUAL_DIRTY: int = 1 << 6  # visual/fusion state needs a rebuild
const FLAG_NET_DIRTY: int = 1 << 7  # changed since last replicated snapshot
const FLAG_POWER_STARVED: int = 1 << 8  # assembly power budget insufficient
const FLAG_SUPPRESSED: int = 1 << 9  # temporarily disabled by an external effect

## Flags that describe simulation state and are therefore server-authoritative.
## The complement is local presentation bookkeeping a client may set freely.
const MASK_AUTHORITATIVE: int = (
	FLAG_DESTROYED
	| FLAG_DETACHED
	| FLAG_SUBMERGED
	| FLAG_OVERHEATED
	| FLAG_JAMMED
	| FLAG_STRAINED
	| FLAG_POWER_STARVED
	| FLAG_SUPPRESSED
)

## Flags that stop a part contributing to structure, mass, or function.
const MASK_INACTIVE: int = FLAG_DESTROYED | FLAG_DETACHED
