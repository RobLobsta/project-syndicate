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
const WORLD_CHUNKS: Vector2i = Vector2i(32, 32)

const WORLD_SPAN_M: float = 2048.0

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
