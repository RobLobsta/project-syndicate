class_name GroundChunk
extends RefCounted
## One chunk of the Dynamic Ground Array, owned by
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §2.2.
##
## A chunk holds [constant GroundConstants.CHUNK_SAMPLES] squared height
## samples and shares its boundary row and column with its neighbours — see
## [method GroundMath.shared_chunks], which every write goes through.
##
## [b]Chunks are allocated lazily.[/b] The world is 32 by 32 chunks and a chunk
## costs about 215 KB across its four arrays, so materialising all 1 024 up
## front would cost over 200 MB for a map of which a match touches a few dozen
## chunks. [GroundArray] creates a chunk the first time something reads or
## writes it and fills its baseline from a [GroundSource]. §2.2's field list is
## the contents of a chunk, not a claim that every chunk exists at load.

## Samples per chunk, cached from [GroundConstants] because every index
## calculation in this class uses it.
const SIDE: int = GroundConstants.CHUNK_SAMPLES
const SAMPLE_COUNT: int = SIDE * SIDE

var chunk_coord: Vector2i = Vector2i.ZERO

## ===== HEIGHT DATA =====================================================
## All three arrays hold quantised heights (see [method GroundMath.quantise]),
## not metres. Storing metres would double the memory and lose the exact
## equality that §8.2's determinism check depends on.

## Authored baseline. Never modified after the chunk is filled — Invariant 5.
## Kept alongside [member live_heights] because it buys an exact round reset, a
## cheap total-deformation query for the erosion clamp, and a network resync
## that sends a delta against a known baseline rather than an absolute field.
var base_heights: PackedInt32Array = PackedInt32Array()

## Live heights including every deformation applied so far.
var live_heights: PackedInt32Array = PackedInt32Array()

## Per-sample [enum SurfaceTable.Surface] classification. §9.
var surface_ids: PackedByteArray = PackedByteArray()

## ===== DIRTY TRACKING ==================================================

var dirty_min: Vector2i = Vector2i(SIDE, SIDE)
var dirty_max: Vector2i = Vector2i(-1, -1)

## ===== RUNTIME ATTACHMENTS =============================================
## Null until the chunk is streamed in. A chunk deformed while unstreamed keeps
## its dirty state and builds collision from [member live_heights] when it is
## later acquired, which is Invariant 7.

var collision_body: StaticBody3D = null
var collision_shape: HeightMapShape3D = null
var render_mesh: MeshInstance3D = null
## R16 height field sampled by the ground shader's vertex stage. §4.6.
var height_texture: ImageTexture = null
## R8 surface classification sampled by the ground shader's fragment stage. §9.2.
var surface_texture: ImageTexture = null

## Increments on each applied deformation. The value a network resync compares
## against to decide whether a client's chunk is current.
var revision: int = 0


## Allocates the arrays and fills them from [param source].
##
## Separate from [method _init] so that a chunk's identity exists before its
## 215 KB does, which is what lets [GroundArray] key a dictionary on chunks it
## has not yet paid for.
func fill_from(coord: Vector2i, source: GroundSource) -> void:
	chunk_coord = coord
	base_heights.resize(SAMPLE_COUNT)
	live_heights.resize(SAMPLE_COUNT)
	surface_ids.resize(SAMPLE_COUNT)
	var span := SIDE - 1
	var origin := coord * span
	for z: int in SIDE:
		for x: int in SIDE:
			var s := origin + Vector2i(x, z)
			var q := GroundMath.quantise(source.height_at(s))
			var i := z * SIDE + x
			base_heights[i] = q
			live_heights[i] = q
			surface_ids[i] = source.surface_at(s)


## Index into the flat arrays for local sample [param local].
##
## Row-major in Z then X, which is [HeightMapShape3D]'s own
## [code]map_data[z * width + x][/code] layout. Matching it means the collision
## array is a straight dequantising copy with no transpose, and a transpose here
## would mirror the world diagonally — visible immediately but easy to
## introduce.
static func local_index(local: Vector2i) -> int:
	return local.y * SIDE + local.x


## True when [param local] addresses a sample this chunk stores.
static func contains_local(local: Vector2i) -> bool:
	return local.x >= 0 and local.y >= 0 and local.x < SIDE and local.y < SIDE


func mark_dirty(x: int, z: int) -> void:
	dirty_min.x = mini(dirty_min.x, x)
	dirty_min.y = mini(dirty_min.y, z)
	dirty_max.x = maxi(dirty_max.x, x)
	dirty_max.y = maxi(dirty_max.y, z)


func has_dirty() -> bool:
	return dirty_max.x >= dirty_min.x


func clear_dirty() -> void:
	dirty_min = Vector2i(SIDE, SIDE)
	dirty_max = Vector2i(-1, -1)


func is_streamed() -> bool:
	return collision_shape != null


## Total deformation at local sample [param local], in metres, positive
## downward. Feeds the erosion clamp of §4.4.
func erosion_at(local: Vector2i) -> float:
	var i := local_index(local)
	return GroundMath.dequantise(base_heights[i]) - GroundMath.dequantise(live_heights[i])


## Restores every sample to its baseline, for a round restart.
func reset_to_base() -> void:
	live_heights = base_heights.duplicate()
	revision += 1
	mark_dirty(0, 0)
	mark_dirty(SIDE - 1, SIDE - 1)
