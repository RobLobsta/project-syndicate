extends TestCase
## The deformation pipeline end to end, against
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §2.4, §4, §6, §8 and §9.2.
##
## Runs the system in [member GroundDeformSystem.synchronous] mode so that a
## request's effect on the field is observable in the same call. The stages and
## the arithmetic are identical to the threaded path — §8.2's determinism is a
## property of the solve, not of where it runs — so what this file asserts about
## the field holds for a match too.
##
## Presentation is off throughout. Building a 129×129 R16 image per chunk per
## deformation is stage 4's work and it has nothing to do with the height field;
## leaving it on would make the file slow and would assert nothing extra.

## The world origin, from §2.3's centred mapping: half of `WORLD_CHUNKS.x`
## chunks of 128 quads. It moves with doc 09 §2.1's world size and is stated by
## value here rather than derived, so a change to that size lands as a failure in
## this file rather than as a crater dug somewhere nobody looks.
const CENTRE_SAMPLE: int = 4096
const BLAST_RADIUS_M: float = 4.0
const BLAST_DAMAGE: float = 400.0  # §3.2's reference energy: depth is exactly K

var _array: GroundArray = null
var _system: GroundDeformSystem = null


func before_all() -> void:
	_array = GroundArray.new()
	_array.present_visuals = false
	_array.source = GroundSource.flat(0.0)
	EventBus.get_tree().root.add_child(_array)

	_system = GroundDeformSystem.new()
	_system.array = _array
	_system.synchronous = true
	EventBus.get_tree().root.add_child(_system)


func after_all() -> void:
	if _system != null:
		_system.get_parent().remove_child(_system)
		_system.queue_free()
	if _array != null:
		_array.get_parent().remove_child(_array)
		_array.queue_free()


## Resets the field between tests. The runner sorts test methods and none may
## depend on another's ordering, so every one starts from the baseline.
func _reset() -> void:
	_array.reset_to_base()


func _crater_at(centre: Vector3, damage: float = BLAST_DAMAGE) -> DeformRequest:
	var req := _system.request_crater(centre, BLAST_RADIUS_M, damage)
	_system.flush()
	return req


## §4.3 and §3.1: the bowl goes down and the rim comes up. Asserted as a shape
## rather than as two numbers, because a profile applied with the wrong sign
## still produces "a change at the centre".
func test_a_crater_digs_a_bowl_with_a_raised_rim() -> void:
	_reset()
	_crater_at(Vector3.ZERO)

	var centre := Vector2i(CENTRE_SAMPLE, CENTRE_SAMPLE)
	var floor_h := _array.sample_height_m(centre)
	check_true(floor_h < -0.5, "the crater floor is well below datum, got %.3f" % floor_h)

	# The rim peak sits at the middle of the annulus: u = (u_r + 1) / 2 of a
	# radius that is the blast radius times CRATER_RADIUS_FACTOR.
	var crater_radius := BLAST_RADIUS_M * 1.35
	var rim_u := (0.68 + 1.0) * 0.5
	var rim_samples := int(round(rim_u * crater_radius / 0.5))
	var rim_h := _array.sample_height_m(centre + Vector2i(rim_samples, 0))
	# §3.1: the rim peak is RIM_RATIO of the depth, which at the reference
	# energy on hardness 1.0 is 0.28 * 0.62. Asserted as a real fraction of the
	# specified height rather than as "greater than zero", because §4.3's
	# original formula produced 5.8% of it and that is still positive.
	var expected_rim := 0.28 * 0.62
	check_approx(rim_h, expected_rim, "the rim is RIM_RATIO of the depth", 0.02)

	# Outside the crater nothing moved. The tolerance is one height quantum:
	# the field stores quantised heights, so a baseline of exactly 0.0 reads
	# back as 0.00195 and always will (§2.1).
	var outside := int(ceil(crater_radius / 0.5)) + 2
	check_approx(
		_array.sample_height_m(centre + Vector2i(outside, 0)),
		0.0,
		"ground outside the crater is untouched",
		GroundConstants.HEIGHT_QUANTUM_M
	)


## §9.2. The crater interior reclassifies to DEFORMED, which is what gives the
## deformation tactical weight beyond the visual — 0.66 traction instead of 1.00.
func test_the_crater_interior_reclassifies_to_deformed() -> void:
	_reset()
	_crater_at(Vector3.ZERO)
	var centre := Vector2i(CENTRE_SAMPLE, CENTRE_SAMPLE)
	check_eq(
		_array.sample_surface(centre),
		int(SurfaceTable.Surface.DEFORMED),
		"the crater floor is reclassified"
	)
	var crater_radius := BLAST_RADIUS_M * 1.35
	var outside := int(ceil(crater_radius / 0.5)) + 2
	check_eq(
		_array.sample_surface(centre + Vector2i(outside, 0)),
		int(SurfaceTable.Surface.COMPACTED),
		"ground outside the crater keeps its classification"
	)


## §2.4 and Invariant 4. This is the assertion a chunk seam crack comes from:
## a sample on a boundary lives in two chunks and both copies must be written.
func test_a_crater_on_a_chunk_seam_writes_every_copy_of_the_shared_samples() -> void:
	_reset()
	# The seam between chunk (31,31) and (32,31) is sample x = 32 * 128 = 4096,
	# which is the world origin — so a crater at the origin straddles four
	# chunks by construction.
	var seam := Vector2i(CENTRE_SAMPLE, CENTRE_SAMPLE)
	var owners := GroundMath.shared_chunks(seam)
	if not check_eq(owners.size(), 4, "the origin is a four-chunk corner"):
		return

	_crater_at(Vector3.ZERO)

	# Read the same world sample through each chunk that stores it, by hand,
	# rather than through the array's own reader — which picks one copy and
	# would agree with itself whatever the others hold.
	var span := GroundConstants.CHUNK_SAMPLES - 1
	var seen: Array[float] = []
	for cc: Vector2i in owners:
		var chunk := _array.existing_chunk(cc)
		if not check_true(chunk != null, "chunk %s was materialised" % cc):
			return
		var local := seam - cc * span
		var q: int = chunk.live_heights[GroundChunk.local_index(local)]
		seen.push_back(GroundMath.dequantise(q))
	for i: int in range(1, seen.size()):
		check_approx(
			seen[i], seen[0], "every copy of the shared sample agrees (copy %d)" % i, 1e-6
		)
	check_true(seen[0] < -0.5, "and all four copies carry the crater, got %.3f" % seen[0])


## §4.4. Repeated bombardment asymptotes toward MAX_EROSION_M rather than
## digging through the world floor, and the hundredth shell still does
## something.
func test_repeated_craters_asymptote_rather_than_punching_through() -> void:
	_reset()
	var centre := Vector2i(CENTRE_SAMPLE, CENTRE_SAMPLE)
	var depths := PackedFloat32Array()
	for i: int in 40:
		# A fresh tick each time, so §4.2's coalescing does not merge them.
		MatchClock.tick += 1
		_crater_at(Vector3.ZERO, 3000.0)
		depths.push_back(-_array.sample_height_m(centre))

	var final_depth := depths[depths.size() - 1]
	check_true(
		final_depth < GroundDeformSystem.MAX_EROSION_M,
		"erosion never reaches the hard limit, got %.3f" % final_depth
	)
	check_true(
		final_depth > GroundDeformSystem.MAX_EROSION_M * 0.7,
		"but it does get past the soft start, got %.3f" % final_depth
	)
	# Monotonic and decelerating: each shell digs, and each digs less than the
	# one before once past the soft start.
	check_true(depths[1] > depths[0], "the second shell deepens the hole")
	var early_gain := depths[2] - depths[1]
	var late_gain := depths[39] - depths[38]
	check_true(late_gain >= 0.0, "the fortieth shell still does something, not nothing")
	check_true(
		late_gain < early_gain, "but less than the third did: %.5f vs %.5f" % [late_gain, early_gain]
	)


## §4.4. Rim uplift is deliberately unclamped — the limit exists to stop a pit
## swallowing vehicles, and a raised rim does not do that.
func test_the_erosion_clamp_does_not_hold_down_the_rim() -> void:
	_reset()
	var centre := Vector2i(CENTRE_SAMPLE, CENTRE_SAMPLE)
	var crater_radius := BLAST_RADIUS_M * 1.35
	var rim_samples := int(round((0.68 + 1.0) * 0.5 * crater_radius / 0.5))
	for i: int in 12:
		MatchClock.tick += 1
		_crater_at(Vector3.ZERO, 3000.0)
	var rim_h := _array.sample_height_m(centre + Vector2i(rim_samples, 0))
	check_true(rim_h > 0.0, "the rim is still above datum after twelve shells, got %.3f" % rim_h)


## §4.2. Two blasts on the same tick within COALESCE_DISTANCE_M merge into one
## request rather than producing two overlapping craters.
func test_blasts_on_the_same_tick_and_close_together_coalesce() -> void:
	_reset()
	var before := _system.pending_count()
	var a := _system.request_crater(Vector3.ZERO, BLAST_RADIUS_M, BLAST_DAMAGE)
	check_true(a != null, "the first request is admitted")
	check_eq(_system.pending_count(), before + 1, "and queued")
	# Well inside COALESCE_DISTANCE_M of 1.6 m, same tick.
	var b := _system.request_crater(Vector3(1.0, 0.0, 0.0), BLAST_RADIUS_M, BLAST_DAMAGE)
	check_eq(b, null, "the second request is folded into the first")
	check_eq(_system.pending_count(), before + 1, "and adds no queue entry")
	_system.flush()


func test_blasts_far_apart_do_not_coalesce() -> void:
	_reset()
	var a := _system.request_crater(Vector3.ZERO, BLAST_RADIUS_M, BLAST_DAMAGE)
	var b := _system.request_crater(Vector3(40.0, 0.0, 0.0), BLAST_RADIUS_M, BLAST_DAMAGE)
	check_true(a != null and b != null, "both distant requests are admitted")
	check_ne(a.deform_id, b.deform_id, "and they carry distinct ids")
	_system.flush()


## §8.2 and Invariant I-9. Two independently constructed arrays given the same
## request sequence must produce bit-identical fields — this is what lets §10
## replicate 34-byte events instead of geometry.
##
## Compared by hash over the quantised values rather than by float equality:
## the claim is bit-identical storage, and a tolerance would not be that claim.
func test_the_same_request_sequence_produces_an_identical_field() -> void:
	var hashes := PackedInt64Array()
	for run: int in 2:
		var arr := GroundArray.new()
		arr.present_visuals = false
		arr.source = GroundSource.basin(20260803, 11.0)
		EventBus.get_tree().root.add_child(arr)
		var sys := GroundDeformSystem.new()
		sys.array = arr
		sys.synchronous = true
		EventBus.get_tree().root.add_child(sys)

		# A fixed pseudo-random walk, seeded identically per run. Not the global
		# RNG: I-9 forbids it, and a shared generator would make run 2 continue
		# run 1's sequence rather than repeat it.
		var rng := RandomNumberGenerator.new()
		rng.seed = 991
		for i: int in 60:
			MatchClock.tick += 1
			var p := Vector3(rng.randf_range(-60.0, 60.0), 0.0, rng.randf_range(-60.0, 60.0))
			sys.request_crater(p, rng.randf_range(2.0, 7.0), rng.randf_range(120.0, 900.0))
		sys.flush()

		hashes.push_back(_field_hash(arr))

		sys.get_parent().remove_child(sys)
		sys.queue_free()
		arr.get_parent().remove_child(arr)
		arr.queue_free()

	check_eq(hashes[0], hashes[1], "two runs of the same request sequence agree bit for bit")
	check_ne(hashes[0], 0, "and the field was actually deformed")


## Invariant 7. A chunk deformed while unstreamed carries the deformation into
## the collision array it builds when it is later streamed in.
func test_a_chunk_deformed_while_unstreamed_streams_in_already_cratered() -> void:
	_reset()
	# Far from the origin and from anything else this file touches.
	var far := Vector3(300.0, 0.0, 300.0)
	var cc := GroundMath.sample_to_chunk(GroundMath.world_to_sample(far))
	_crater_at(far)

	var chunk := _array.existing_chunk(cc)
	if not check_true(chunk != null, "the chunk was materialised by the deformation"):
		return
	check_false(chunk.is_streamed(), "and it has no collision, having never been near anything")

	var heights := GroundDeformSystem.build_collision_array(chunk)
	var local := GroundMath.world_to_sample(far) - cc * (GroundConstants.CHUNK_SAMPLES - 1)
	var at_centre := heights[GroundChunk.local_index(local)]
	check_true(
		at_centre < -0.5,
		"the collision array built on stream-in carries the crater, got %.3f" % at_centre
	)


## Lazy allocation is the reason the world fits in memory. A deformation must
## materialise the chunks it touches and nothing else.
func test_a_deformation_materialises_only_the_chunks_it_touches() -> void:
	var arr := GroundArray.new()
	arr.present_visuals = false
	arr.source = GroundSource.flat(0.0)
	EventBus.get_tree().root.add_child(arr)
	var sys := GroundDeformSystem.new()
	sys.array = arr
	sys.synchronous = true
	EventBus.get_tree().root.add_child(sys)

	check_eq(arr.materialised_count(), 0, "a fresh array holds no chunks")
	# Well inside one chunk, away from every seam.
	sys.request_crater(Vector3(-1000.0, 0.0, -1000.0), 3.0, 200.0)
	sys.flush()
	check_true(
		arr.materialised_count() <= 4,
		"one crater materialises a handful of chunks, not 1024: got %d" % arr.materialised_count()
	)
	check_true(arr.materialised_count() >= 1, "but at least the one it landed in")

	sys.get_parent().remove_child(sys)
	sys.queue_free()
	arr.get_parent().remove_child(arr)
	arr.queue_free()


## §6. Ruts batch and flush as one request rather than one per contact.
func test_ruts_batch_into_a_single_request() -> void:
	_reset()
	var arr := GroundArray.new()
	arr.present_visuals = false
	arr.source = GroundSource.flat(0.0)
	# LOOSE is ruttable; COMPACTED is not, and the default source is COMPACTED.
	arr.source.default_surface = SurfaceTable.Surface.LOOSE
	EventBus.get_tree().root.add_child(arr)
	var sys := GroundDeformSystem.new()
	sys.array = arr
	sys.synchronous = true
	EventBus.get_tree().root.add_child(sys)

	var load_n := GroundDeformSystem.RUT_MIN_LOAD_N * 3.0
	var before := sys.pending_count()
	for i: int in 30:
		var p := Vector3(float(i) * 0.75, 0.0, 0.0)
		sys.accumulate_rut(p, load_n, SurfaceTable.Surface.LOOSE, 1)
	check_eq(sys.pending_count(), before, "thirty contacts queue no requests on their own")

	sys._flush_rut_batch()
	check_eq(sys.pending_count(), before + 1, "the batch flushes as exactly one request")
	sys.flush()

	var pressed := arr.sample_height_m(GroundMath.world_to_sample(Vector3(7.5, 0.0, 0.0)))
	check_true(pressed < 0.0, "and the ground under the track is pressed down, got %.4f" % pressed)

	sys.get_parent().remove_child(sys)
	sys.queue_free()
	arr.get_parent().remove_child(arr)
	arr.queue_free()


## §6. A contact under the load floor, or on ground that does not rut, deposits
## nothing. Both gates are asserted because either alone would let the other rot.
func test_ruts_respect_the_load_floor_and_the_surface_gate() -> void:
	var sys := GroundDeformSystem.new()
	sys.array = _array
	sys.synchronous = true
	EventBus.get_tree().root.add_child(sys)

	sys.accumulate_rut(
		Vector3.ZERO, GroundDeformSystem.RUT_MIN_LOAD_N * 0.5, SurfaceTable.Surface.LOOSE, 1
	)
	sys._flush_rut_batch()
	check_eq(sys.pending_count(), 0, "a contact below the load floor deposits nothing")

	sys.accumulate_rut(
		Vector3.ZERO, GroundDeformSystem.RUT_MIN_LOAD_N * 4.0, SurfaceTable.Surface.COMPACTED, 2
	)
	sys._flush_rut_batch()
	check_eq(sys.pending_count(), 0, "a heavy contact on unruttable ground deposits nothing")

	sys.get_parent().remove_child(sys)
	sys.queue_free()


## §10.3. The log is what a late joiner replays, so it has to carry every
## applied request in order.
func test_the_deform_log_records_every_applied_request_in_order() -> void:
	var arr := GroundArray.new()
	arr.present_visuals = false
	arr.source = GroundSource.flat(0.0)
	EventBus.get_tree().root.add_child(arr)
	var sys := GroundDeformSystem.new()
	sys.array = arr
	sys.synchronous = true
	EventBus.get_tree().root.add_child(sys)

	for i: int in 5:
		MatchClock.tick += 1
		sys.request_crater(Vector3(float(i) * 30.0, 0.0, 0.0), 4.0, 400.0)
	sys.flush()

	var log := sys.deform_log()
	check_eq(log.size(), 5, "every request is logged")
	for i: int in range(1, log.size()):
		check_true(
			log[i].deform_id > log[i - 1].deform_id, "log ids ascend at index %d" % i
		)
	check_false(sys.log_exceeds_snapshot_threshold(), "five requests is well under the threshold")

	sys.get_parent().remove_child(sys)
	sys.queue_free()
	arr.get_parent().remove_child(arr)
	arr.queue_free()


## §10.2. A replicated request produces the same field as an authored one, which
## is the whole basis for sending events instead of geometry.
func test_a_replicated_request_produces_the_same_field_as_an_authored_one() -> void:
	var authored_hash := 0
	var replicated_hash := 0
	var carried: DeformRequest = null

	for run: int in 2:
		var arr := GroundArray.new()
		arr.present_visuals = false
		arr.source = GroundSource.flat(0.0)
		EventBus.get_tree().root.add_child(arr)
		var sys := GroundDeformSystem.new()
		sys.array = arr
		sys.synchronous = true
		EventBus.get_tree().root.add_child(sys)

		if run == 0:
			carried = sys.request_crater(Vector3(12.0, 0.0, -7.0), 5.0, 650.0)
		else:
			sys.apply_replicated(carried)
		sys.flush()

		if run == 0:
			authored_hash = _field_hash(arr)
		else:
			replicated_hash = _field_hash(arr)

		sys.get_parent().remove_child(sys)
		sys.queue_free()
		arr.get_parent().remove_child(arr)
		arr.queue_free()

	check_ne(authored_hash, 0, "the authored run deformed something")
	check_eq(replicated_hash, authored_hash, "replaying the request reproduces the field exactly")


## A stable hash over every materialised chunk's quantised heights and surface
## ids, in deterministic chunk order.
func _field_hash(arr: GroundArray) -> int:
	var acc := 1469598103934665603
	for chunk: GroundChunk in arr.materialised_chunks():
		acc = _mix(acc, chunk.chunk_coord.x)
		acc = _mix(acc, chunk.chunk_coord.y)
		for i: int in GroundChunk.SAMPLE_COUNT:
			acc = _mix(acc, chunk.live_heights[i])
			acc = _mix(acc, int(chunk.surface_ids[i]))
	return acc


func _mix(acc: int, v: int) -> int:
	return ((acc ^ v) * 1099511628211) & 0x7FFFFFFFFFFFFFFF
