class_name CollisionLayers
extends RefCounted
## Physics layer assignments and the common masks built from them, owned by
## [code]CLAUDE.md[/code] §5.1.
##
## Layer numbers are frozen. Every value below is a bit mask ready to assign to
## [code]CollisionObject3D.collision_layer[/code] or
## [code]collision_mask[/code] — never a 1-based layer number, so there is no
## ambiguity about whether a caller still needs to shift.

const LAYER_ASSEMBLY_HULL: int = 1 << 0  # ChassisBody collision shapes
const LAYER_ASSEMBLY_MOTIVE: int = 1 << 1  # reserved for motive-specific volumes
const LAYER_GROUND: int = 1 << 2  # streamed Ground Array chunk collision
const LAYER_STATIC_VOLUME: int = 1 << 3  # Static Volume section bodies
const LAYER_PROJECTILE: int = 1 << 4  # reserved; projectiles are raycast
const LAYER_DEBRIS: int = 1 << 5  # detached islands, Static Volume fragments
const LAYER_TRIGGER_VOLUME: int = 1 << 6  # capture zones, kill volumes, spawns
const LAYER_BUILD_GHOST: int = 1 << 7  # garage-only build proxies
const LAYER_BUILD_FLOOR: int = 1 << 8  # garage-only ground plane
const LAYER_AIM_TRACE: int = 1 << 9  # aim raycast targets

## Debris deliberately excludes [constant LAYER_DEBRIS]: debris never collides
## with debris. A 96-body pile-up otherwise costs more than the rest of the
## physics tick combined.
const MASK_DEBRIS: int = LAYER_GROUND | LAYER_STATIC_VOLUME

const MASK_GROUND: int = LAYER_GROUND
const MASK_STATIC_VOLUME: int = LAYER_STATIC_VOLUME
const MASK_PROJECTILE_TARGET: int = (
	LAYER_ASSEMBLY_HULL | LAYER_GROUND | LAYER_STATIC_VOLUME | LAYER_DEBRIS
)
const MASK_BLAST_QUERY: int = LAYER_ASSEMBLY_HULL | LAYER_STATIC_VOLUME | LAYER_DEBRIS
const MASK_AIM_TRACE: int = LAYER_ASSEMBLY_HULL | LAYER_GROUND | LAYER_STATIC_VOLUME
const MASK_BUILD_GHOST: int = LAYER_BUILD_GHOST
