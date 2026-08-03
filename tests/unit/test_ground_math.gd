extends TestCase
## [GroundConstants], [GroundMath] and [SurfaceTable] against
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §2 and §9.
##
## Published values are written out by hand. §9.1's tables in particular are
## consumed by [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §7.3, so a silent edit
## to one of them is a balance change to every vehicle in the game.

## §2.1's table, quoted.
const DOC_SAMPLE_SPACING_M: float = 0.5
const DOC_CHUNK_SAMPLES: int = 129
const DOC_CHUNK_SPAN_M: float = 64.0
const DOC_WORLD_CHUNKS: Vector2i = Vector2i(32, 32)
const DOC_WORLD_SPAN_M: float = 2048.0
const DOC_HEIGHT_MIN_M: float = -128.0
const DOC_HEIGHT_MAX_M: float = 384.0
const DOC_HEIGHT_RANGE_M: float = 512.0
const DOC_HEIGHT_QUANTUM_M: float = 512.0 / 65535.0
const DOC_COLLISION_STREAM_RADIUS_M: float = 180.0
const DOC_MAX_COLLISION_CHUNKS: int = 64

## §9.1's tables, quoted.
const DOC_TRACTION: Array[float] = [1.00, 0.78, 0.42, 0.66, 1.06]
const DOC_HARDNESS: Array[float] = [1.00, 0.55, 0.80, 0.62, 3.20]
const DOC_RUTTABLE: Array[bool] = [false, true, false, true, false]
const DOC_ROLL_RESIST: Array[float] = [0.014, 0.031, 0.009, 0.026, 0.011]


func test_the_published_dimensions_are_what_the_document_says() -> void:
	check_approx(GroundConstants.SAMPLE_SPACING_M, DOC_SAMPLE_SPACING_M, "SAMPLE_SPACING_M")
	check_eq(GroundConstants.CHUNK_SAMPLES, DOC_CHUNK_SAMPLES, "CHUNK_SAMPLES")
	check_approx(GroundConstants.CHUNK_SPAN_M, DOC_CHUNK_SPAN_M, "CHUNK_SPAN_M")
	check_eq(GroundConstants.WORLD_CHUNKS, DOC_WORLD_CHUNKS, "WORLD_CHUNKS")
	check_approx(GroundConstants.WORLD_SPAN_M, DOC_WORLD_SPAN_M, "WORLD_SPAN_M")
	check_approx(GroundConstants.HEIGHT_MIN_M, DOC_HEIGHT_MIN_M, "HEIGHT_MIN_M")
	check_approx(GroundConstants.HEIGHT_MAX_M, DOC_HEIGHT_MAX_M, "HEIGHT_MAX_M")
	check_approx(GroundConstants.HEIGHT_RANGE_M, DOC_HEIGHT_RANGE_M, "HEIGHT_RANGE_M")
	check_approx(
		GroundConstants.HEIGHT_QUANTUM_M, DOC_HEIGHT_QUANTUM_M, "HEIGHT_QUANTUM_M", 1e-9
	)
	check_approx(
		GroundConstants.COLLISION_STREAM_RADIUS_M,
		DOC_COLLISION_STREAM_RADIUS_M,
		"COLLISION_STREAM_RADIUS_M"
	)
	check_eq(
		GroundConstants.MAX_COLLISION_CHUNKS, DOC_MAX_COLLISION_CHUNKS, "MAX_COLLISION_CHUNKS"
	)


## §2.1: the chunk span is derived, and the world span has to be the chunk grid
## times the chunk span or the two coordinate systems disagree at the edges.
func test_the_dimensions_are_mutually_consistent() -> void:
	check_approx(
		GroundConstants.CHUNK_SPAN_M,
		float(DOC_CHUNK_SAMPLES - 1) * DOC_SAMPLE_SPACING_M,
		"chunk span is (samples - 1) * spacing"
	)
	check_approx(
		float(DOC_WORLD_CHUNKS.x) * DOC_CHUNK_SPAN_M,
		DOC_WORLD_SPAN_M,
		"the chunk grid exactly covers the world span"
	)
	check_eq(
		GroundConstants.WORLD_SAMPLES,
		DOC_WORLD_CHUNKS.x * (DOC_CHUNK_SAMPLES - 1) + 1,
		"world samples counts the far shared edge once"
	)


## §2.3. The world origin is the centre of the sample grid, and the mapping must
## be continuous across it — flooring rather than truncating is the whole point,
## because truncation folds the two cells either side of an axis together.
func test_world_and_sample_coordinates_round_trip() -> void:
	var half := DOC_WORLD_SPAN_M * 0.5
	var centre := GroundMath.world_to_sample(Vector3.ZERO)
	check_eq(
		centre,
		Vector2i(int(half / DOC_SAMPLE_SPACING_M), int(half / DOC_SAMPLE_SPACING_M)),
		"the origin sits at the centre sample"
	)
	check_eq(
		GroundMath.world_to_sample(Vector3(-half, 0.0, -half)),
		Vector2i(0, 0),
		"the negative corner is sample zero"
	)
	for s: Vector2i in [Vector2i(0, 0), Vector2i(1, 7), Vector2i(2048, 2048), Vector2i(4096, 4096)]:
		var w := GroundMath.sample_to_world_xz(s)
		check_eq(
			GroundMath.world_to_sample(Vector3(w.x, 0.0, w.y)),
			s,
			"sample %s round-trips through world space" % s
		)


func test_the_mapping_does_not_fold_across_the_origin() -> void:
	# Two positions a quarter-metre either side of the X axis must land in
	# different samples. int() truncation would put both in the same one.
	var left := GroundMath.world_to_sample(Vector3(-0.25, 0.0, 0.0))
	var right := GroundMath.world_to_sample(Vector3(0.25, 0.0, 0.0))
	check_ne(left.x, right.x, "samples either side of the origin are distinct")
	check_eq(right.x - left.x, 1, "and adjacent")


## §2.3. Quantisation is exact at the ends and within half a quantum everywhere.
func test_height_quantisation_round_trips_within_a_quantum() -> void:
	check_eq(GroundMath.quantise(DOC_HEIGHT_MIN_M), 0, "the floor quantises to zero")
	check_eq(GroundMath.quantise(DOC_HEIGHT_MAX_M), 65535, "the ceiling quantises to 65535")
	check_approx(GroundMath.dequantise(0), DOC_HEIGHT_MIN_M, "zero dequantises to the floor")
	check_approx(
		GroundMath.dequantise(65535), DOC_HEIGHT_MAX_M, "65535 dequantises to the ceiling", 1e-3
	)
	for h: float in [-127.5, -10.0, 0.0, 1.234, 40.0, 383.0]:
		var back := GroundMath.dequantise(GroundMath.quantise(h))
		check_approx(back, h, "height %.3f round-trips" % h, DOC_HEIGHT_QUANTUM_M)


## Clamping rather than wrapping. A deformation driven below the floor by an
## arithmetic error must not reappear at the top of the range as a spike.
func test_quantisation_clamps_rather_than_wrapping() -> void:
	check_eq(GroundMath.quantise(-9999.0), 0, "far below the floor clamps to zero")
	check_eq(GroundMath.quantise(9999.0), 65535, "far above the ceiling clamps to the top")


## §2.4. A sample on a seam belongs to two chunks and one on a four-chunk corner
## belongs to four. This is the rule a crack along a chunk boundary comes from.
func test_shared_samples_report_every_chunk_that_stores_them() -> void:
	var span := DOC_CHUNK_SAMPLES - 1

	var interior := GroundMath.shared_chunks(Vector2i(span / 2, span / 2))
	check_eq(interior.size(), 1, "an interior sample belongs to one chunk")
	check_eq(interior[0], Vector2i(0, 0), "and it is the chunk containing it")

	var on_x_seam := GroundMath.shared_chunks(Vector2i(span, span / 2))
	check_eq(on_x_seam.size(), 2, "a sample on an X seam belongs to two chunks")
	check_true(on_x_seam.has(Vector2i(0, 0)), "the chunk to the left stores it")
	check_true(on_x_seam.has(Vector2i(1, 0)), "the chunk to the right stores it")

	var on_z_seam := GroundMath.shared_chunks(Vector2i(span / 2, span))
	check_eq(on_z_seam.size(), 2, "a sample on a Z seam belongs to two chunks")

	var corner := GroundMath.shared_chunks(Vector2i(span, span))
	check_eq(corner.size(), 4, "a four-chunk corner sample belongs to four chunks")
	for cc: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		check_true(corner.has(cc), "corner sample is stored by chunk %s" % cc)


## The world edge has no neighbour to share with, so the count drops rather than
## naming a chunk outside the world.
func test_shared_samples_at_the_world_edge_have_no_phantom_neighbour() -> void:
	check_eq(
		GroundMath.shared_chunks(Vector2i(0, 0)).size(), 1, "the origin corner has one chunk"
	)
	var far := GroundConstants.WORLD_SAMPLES - 1
	var far_corner := GroundMath.shared_chunks(Vector2i(far, far))
	check_eq(far_corner.size(), 1, "the far corner has one chunk")
	check_eq(
		far_corner[0],
		Vector2i(DOC_WORLD_CHUNKS.x - 1, DOC_WORLD_CHUNKS.y - 1),
		"and it is the last chunk"
	)


## I-9. A deformation must visit chunks in the same order on every peer.
func test_shared_chunks_are_returned_in_deterministic_order() -> void:
	var span := DOC_CHUNK_SAMPLES - 1
	var corner := GroundMath.shared_chunks(Vector2i(span, span))
	for i: int in range(1, corner.size()):
		check_true(
			(
				GroundConstants.chunk_order_key(corner[i - 1])
				< GroundConstants.chunk_order_key(corner[i])
			),
			"chunk order is strictly ascending at index %d" % i
		)


## The local index must be row-major in Z then X, which is HeightMapShape3D's
## own map_data layout. A transpose here mirrors the world diagonally.
func test_the_chunk_index_layout_matches_the_collision_shape() -> void:
	check_eq(GroundChunk.local_index(Vector2i(0, 0)), 0, "sample (0,0) is index 0")
	check_eq(GroundChunk.local_index(Vector2i(1, 0)), 1, "X advances by one")
	check_eq(
		GroundChunk.local_index(Vector2i(0, 1)),
		DOC_CHUNK_SAMPLES,
		"Z advances by a whole row"
	)


## §9.1. These are the arrays doc 05 §7.3 indexes; there is one definition.
func test_the_surface_tables_are_what_the_document_says() -> void:
	check_eq(SurfaceTable.SURFACE_COUNT, DOC_TRACTION.size(), "the table length")
	for id: int in DOC_TRACTION.size():
		check_approx(SurfaceTable.multiplier(id), DOC_TRACTION[id], "TRACTION[%d]" % id)
		check_approx(SurfaceTable.hardness(id), DOC_HARDNESS[id], "HARDNESS[%d]" % id)
		check_eq(SurfaceTable.is_ruttable(id), DOC_RUTTABLE[id], "RUTTABLE[%d]" % id)
		check_approx(SurfaceTable.roll_resist(id), DOC_ROLL_RESIST[id], "ROLL_RESIST[%d]" % id)


## The enum ordinals are what the byte array stores and what the shader decodes,
## so they are part of the wire format rather than an implementation detail.
func test_the_surface_ordinals_are_frozen() -> void:
	check_eq(int(SurfaceTable.Surface.COMPACTED), 0, "COMPACTED is 0")
	check_eq(int(SurfaceTable.Surface.LOOSE), 1, "LOOSE is 1")
	check_eq(int(SurfaceTable.Surface.SLICK), 2, "SLICK is 2")
	check_eq(int(SurfaceTable.Surface.DEFORMED), 3, "DEFORMED is 3")
	check_eq(int(SurfaceTable.Surface.STRUCTURE), 4, "STRUCTURE is 4")


## A corrupt byte should cost one contact its grip, not halt the match.
func test_surface_lookups_are_total() -> void:
	check_approx(SurfaceTable.multiplier(-1), DOC_TRACTION[0], "a negative id clamps low")
	check_approx(SurfaceTable.multiplier(255), DOC_TRACTION[4], "an oversized id clamps high")


## §7.3's tactical claim: driving through a fresh crater is measurably worse
## than driving around it.
func test_a_deformed_surface_grips_worse_than_the_ground_it_replaced() -> void:
	check_true(
		(
			SurfaceTable.multiplier(SurfaceTable.Surface.DEFORMED)
			< SurfaceTable.multiplier(SurfaceTable.Surface.COMPACTED)
		),
		"§7.3: a crater interior grips worse than the compacted ground it replaced"
	)
	check_true(
		SurfaceTable.is_ruttable(SurfaceTable.Surface.DEFORMED),
		"a crater floor takes further ruts"
	)
