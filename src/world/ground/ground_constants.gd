class_name GroundConstants
extends RefCounted
## Dynamic Ground Array dimensions and quantisation, owned by
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §2.1.
##
## Every figure here is referenced rather than duplicated elsewhere, per
## [code]CLAUDE.md[/code] §1.1. [CraterProfile] owns the crater shape constants
## and [SurfaceTable] owns the per-surface tables; neither is repeated here.

## Distance between adjacent height samples, in metres.
const SAMPLE_SPACING_M: float = 0.5

## Samples along one edge of a chunk: 128 quads plus the shared edge row. The
## shared row is what §2.4's four-way write exists to keep consistent.
const CHUNK_SAMPLES: int = 129

## Ground covered by one chunk, in metres. Derived, never authored separately.
const CHUNK_SPAN_M: float = float(CHUNK_SAMPLES - 1) * SAMPLE_SPACING_M

## Chunk grid covering the world.
##
## [b]64 × 64 chunks of 64 m is 4096 m square, and the ceiling is worth stating
## because it is not where most people would guess.[/b] Chunks are allocated
## sparsely — [GroundArray] holds only the ones something has touched — so the
## world span costs nothing until it is driven on. What bounds it is two things
## and neither is the chunk count:
##
## [enum]
## [*] [b]Height storage, fully explored.[/b] One `uint16` height and one `uint8`
##     surface id per sample at 0.5 m spacing: 4096 m is 8193 samples an edge,
##     which is 134 MB of height and 67 of surface if every chunk is visited.
##     8192 m would be 537 MB and 268, which is the point paging stops being
##     optional.
## [*] [b]Single-precision position.[/b] Godot builds float32 by default, so the
##     ULP at the far corner of a 4096 m world is 0.24 mm and at 8192 m it is
##     0.49. Physics jitter becomes visible somewhere past a millimetre, so 8 km
##     is roughly where a `precision=double` build starts being the honest answer.
## [/enum]
##
## For scale: the reference build's governed top speed is 22.6 m/s, so crossing
## 4096 m takes three minutes. The limit that actually bites is not this constant
## — it is that a match currently uses about thirty metres of it.
const WORLD_CHUNKS: Vector2i = Vector2i(64, 64)

const WORLD_SPAN_M: float = float(WORLD_CHUNKS.x) * CHUNK_SPAN_M

## Samples along one edge of the world, counting the far shared edge once.
const WORLD_SAMPLES: int = WORLD_CHUNKS.x * (CHUNK_SAMPLES - 1) + 1

## ===== HEIGHT QUANTISATION =============================================
## Height is stored as a 16-bit value spanning [constant HEIGHT_RANGE_M]. The
## resulting quantum is finer than any gameplay-relevant height difference and
## halves the memory a float32 field would take.

const HEIGHT_MIN_M: float = -128.0
const HEIGHT_MAX_M: float = 384.0
const HEIGHT_RANGE_M: float = HEIGHT_MAX_M - HEIGHT_MIN_M
const HEIGHT_QUANTUM_M: float = HEIGHT_RANGE_M / 65535.0  # ~7.81 mm
const HEIGHT_QUANTUM_MAX: int = 65535

## ===== COLLISION STREAMING =============================================

const COLLISION_STREAM_RADIUS_M: float = 180.0
const MAX_COLLISION_CHUNKS: int = 64


## Flat index of [param cc] into a row-major world chunk grid.
##
## Chunks are stored sparsely (see [GroundArray]), so this is an identity for
## diagnostics and ordering rather than an array offset. Iterating chunks in
## this order is what makes a deformation's chunk visit sequence deterministic,
## which Architectural Invariant I-9 requires.
static func chunk_order_key(cc: Vector2i) -> int:
	return cc.y * WORLD_CHUNKS.x + cc.x


## True when [param cc] addresses a chunk inside the world.
static func is_valid_chunk(cc: Vector2i) -> bool:
	return cc.x >= 0 and cc.y >= 0 and cc.x < WORLD_CHUNKS.x and cc.y < WORLD_CHUNKS.y


## True when [param s] addresses a sample inside the world.
static func is_valid_sample(s: Vector2i) -> bool:
	return s.x >= 0 and s.y >= 0 and s.x < WORLD_SAMPLES and s.y < WORLD_SAMPLES
