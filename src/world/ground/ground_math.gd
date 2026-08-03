class_name GroundMath
extends RefCounted
## Coordinate mapping and height quantisation for the Dynamic Ground Array,
## owned by [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §2.3.
##
## Every function here is a pure static over integers and floats, which is what
## lets §8.2's determinism claim be checked without a physics space: the same
## request sequence produces the same sample list and the same quantised values
## on every platform.
##
## [b]The world origin sits at the centre of the sample grid.[/b] Sample
## [code](0, 0)[/code] is at world
## [code](-WORLD_SPAN_M / 2, -WORLD_SPAN_M / 2)[/code], and the world's
## positive X and Z run along increasing sample indices. This matches
## [HeightMapShape3D]'s own layout, which stores
## [code]map_data[z * width + x][/code] with sample zero at the shape's
## negative corner — see [method GroundChunk.local_index].


## Sample containing the world position [param p], flooring toward negative
## infinity so that the mapping is continuous across the origin.
##
## [code]int()[/code] truncates toward zero and would fold the two cells either
## side of an axis onto the same index, which reads as a half-metre seam through
## the middle of the map.
static func world_to_sample(p: Vector3) -> Vector2i:
	return Vector2i(
		int(floor((p.x + GroundConstants.WORLD_SPAN_M * 0.5) / GroundConstants.SAMPLE_SPACING_M)),
		int(floor((p.z + GroundConstants.WORLD_SPAN_M * 0.5) / GroundConstants.SAMPLE_SPACING_M))
	)


## World XZ position of sample [param s].
static func sample_to_world_xz(s: Vector2i) -> Vector2:
	return Vector2(
		float(s.x) * GroundConstants.SAMPLE_SPACING_M - GroundConstants.WORLD_SPAN_M * 0.5,
		float(s.y) * GroundConstants.SAMPLE_SPACING_M - GroundConstants.WORLD_SPAN_M * 0.5
	)


## Chunk owning sample [param s] as an interior sample.
##
## A sample on a shared edge belongs to up to four chunks and this answers only
## the one that owns it as a low-index sample; [method shared_chunks] answers
## the full set, and a write must use that.
static func sample_to_chunk(s: Vector2i) -> Vector2i:
	var span := GroundConstants.CHUNK_SAMPLES - 1
	return Vector2i(s.x / span, s.y / span)


## Chunk indices along one axis that store a copy of sample index [param i].
##
## Chunk [code]c[/code] owns samples [code][c * span, c * span + span][/code]
## inclusive at both ends, so an index landing exactly on a multiple of the span
## is the low sample of one chunk and the high sample of the one before it.
static func _chunk_axis_indices(i: int) -> PackedInt32Array:
	var span := GroundConstants.CHUNK_SAMPLES - 1
	var out := PackedInt32Array()
	var high := i / span
	var low := high - 1 if i % span == 0 else high
	if low >= 0 and low < GroundConstants.WORLD_CHUNKS.x:
		out.push_back(low)
	if high != low and high >= 0 and high < GroundConstants.WORLD_CHUNKS.x:
		out.push_back(high)
	return out


## Every chunk that stores a copy of sample [param s], in ascending
## [method GroundConstants.chunk_order_key] order.
##
## §2.4: chunks share their boundary sample row and column, so a sample on a
## seam exists in two chunks and a sample on a four-chunk corner exists in four.
## A deformation that writes only one copy leaves a visible and collidable crack
## along the seam, which is why every write goes through this.
##
## The ordering is not cosmetic. Architectural Invariant I-9 requires a
## deformation to visit chunks in the same sequence on every peer, and a raw
## [Dictionary] key order would not give that.
static func shared_chunks(s: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var xs := _chunk_axis_indices(s.x)
	var zs := _chunk_axis_indices(s.y)
	for cz: int in zs:
		for cx: int in xs:
			out.push_back(Vector2i(cx, cz))
	return out


## Sample [param s] expressed relative to chunk [param cc], or a negative
## component when the sample lies outside that chunk.
static func sample_in_chunk(s: Vector2i, cc: Vector2i) -> Vector2i:
	var span := GroundConstants.CHUNK_SAMPLES - 1
	return s - cc * span


## Height in metres for the stored quantum [param q].
static func dequantise(q: int) -> float:
	return (
		GroundConstants.HEIGHT_MIN_M
		+ (float(q) / float(GroundConstants.HEIGHT_QUANTUM_MAX)) * GroundConstants.HEIGHT_RANGE_M
	)


## Stored quantum for [param height_m], clamped into the representable band.
##
## Clamping rather than wrapping matters: a deformation driven below
## [constant GroundConstants.HEIGHT_MIN_M] by an arithmetic error would
## otherwise reappear at the top of the range as a spike through the sky.
static func quantise(height_m: float) -> int:
	var clamped := clampf(height_m, GroundConstants.HEIGHT_MIN_M, GroundConstants.HEIGHT_MAX_M)
	var t := (clamped - GroundConstants.HEIGHT_MIN_M) / GroundConstants.HEIGHT_RANGE_M
	return int(round(t * float(GroundConstants.HEIGHT_QUANTUM_MAX)))


## World-space centre of chunk [param cc], at height zero.
##
## This is the position a chunk's collision body and render mesh are placed at,
## because [HeightMapShape3D] centres its field on the shape origin.
static func chunk_centre_world(cc: Vector2i) -> Vector3:
	var span := GroundConstants.CHUNK_SAMPLES - 1
	var corner := sample_to_world_xz(cc * span)
	var half := GroundConstants.CHUNK_SPAN_M * 0.5
	return Vector3(corner.x + half, 0.0, corner.y + half)
