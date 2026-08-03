class_name GroundDeformSystem
extends Node
## The five-stage ground deformation pipeline, owned by
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §4, §6, §8 and §10.4.
##
## [codeblock]
## Stage 1  Request       main thread   enqueue a DeformRequest
## Stage 2  Height solve  worker        compute new sample values
## Stage 3  Collision     worker        build the replacement height array
## Stage 4  Mesh/Texture  worker        build the replacement Images
## Stage 5  Commit        main thread   swap shape data and textures
## [/codeblock]
##
## Only stages 1 and 5 touch the main thread and both are trivially cheap. The
## commit loop runs under [constant COMMIT_BUDGET_MS], so a barrage producing
## twelve craters in one tick commits two or three per frame over the following
## few frames rather than stalling on all twelve. That latency is invisible
## behind the explosion effects covering the same ground.
##
## [b]Dispatch is strictly in queue order.[/b] §10.1 records that the erosion
## clamp is order-dependent — applying crater B then A gives a different field
## than A then B when they overlap — so a request whose region is busy stops
## dispatch for the frame rather than being skipped. Reordering here would make
## two peers disagree about the terrain from an identical request log, which is
## exactly what §8.2's determinism claim forbids.

## §4.2. Two explosions this close during the same tick merge into one crater.
const COALESCE_DISTANCE_M: float = 1.6

## §4.3. How strongly a crater's bowl levels toward the blast's ground plane
## rather than following the local slope. A crater on a hillside becomes a flat
## shelf, which is a usable firing position; a pure subtraction would leave a
## tilted depression that vehicles slide out of.
##
## [b]Amendment to §4.3.[/b] The document blends the levelling weight over the
## whole crater as [code]1 - smoothstep(0, 1, u)[/code] and applies the profile
## through the same [code]lerp[/code]. That attenuates the rim to 5.8% of the
## height §3.1 specifies for it — §7.1's cover-providing 0.39 m lip on a 1.4 m
## crater would ship at 0.023 m, which is nothing at all. The two effects are
## separate concerns and are now separated: levelling chooses the [i]datum[/i]
## and falls to zero at [constant CraterProfile.RIM_BOUNDARY], and the profile
## is added on top of it. Ejecta lands on whatever surface is there, which is
## also the physically ordinary reading.
const SLOPE_LEVEL_STRENGTH: float = 0.85

## §4.4. Cumulative excavation asymptotes toward this rather than hitting a
## wall, so the hundredth shell into a crater still visibly does something.
const MAX_EROSION_M: float = 5.5
const EROSION_SOFT_START: float = 0.70

## §9.2. Height change below this leaves the surface classification alone.
const DEFORM_RECLASSIFY_THRESHOLD_M: float = 0.22

## §8.1.
const MAX_IN_FLIGHT_DEFORMS: int = 3

## §4.7. The hard cap that makes a hitch structurally impossible.
const COMMIT_BUDGET_MS: float = 1.5

## §6.
const RUT_DEPTH_PER_KN_M: float = 0.00018
const RUT_MIN_LOAD_N: float = 26000.0
const RUT_MAX_DEPTH_M: float = 0.06
const RUT_FLUSH_INTERVAL_S: float = 1.0

## §10.4. Excess is coalesced into the nearest pending request rather than
## dropped, so the visual result stays honest under a spam attempt.
const MAX_DEFORMS_PER_SECOND: int = 24
const MAX_DEFORMS_PER_ASSEMBLY_PER_SECOND: int = 6

## §10.3. Beyond this many logged requests, a late joiner gets a delta snapshot
## rather than the log.
const LOG_SNAPSHOT_THRESHOLD: int = 4096

## The array this system deforms. Supplied by the match scene.
var array: GroundArray = null

## Runs the worker stages inline instead of on [WorkerThreadPool].
##
## Not a test affordance bolted on: a dedicated server that is already
## thread-saturated, and every test that needs to assert the field immediately
## after a request, both want the same single-threaded execution. The stages and
## their results are identical either way — §8.2's determinism is a property of
## the arithmetic, not of where it runs.
var synchronous: bool = false

## Ordered log of every applied request, for §10.3's late-join replay.
var _log: Array[DeformRequest] = []

var _queue: Array[DeformRequest] = []
var _next_deform_id: int = 1

## Requests whose worker task is still running. Guarded by [member _run_mutex]
## because the worker clears its own entry.
var _running: Array[DeformRequest] = []
var _run_mutex: Mutex = Mutex.new()

var _ready_results: Array[DeformResult] = []
var _ready_mutex: Mutex = Mutex.new()

## ===== RUT ACCUMULATION (§6) ===========================================
## Ruts are batched and flushed once per second as a single request. Flushing
## per contact would produce hundreds of requests per second per Assembly, which
## is precisely the unbounded work this architecture exists to avoid.

var _rut_batch: Dictionary = {}  # encoded sample -> depth
var _last_rut_sample: Dictionary = {}  # track key -> Vector2i
var _rut_accum_s: float = 0.0

## ===== RATE LIMITING (§10.4) ===========================================

var _second_accum_s: float = 0.0
var _deforms_this_second: int = 0
var _per_assembly_this_second: Dictionary = {}


## §4.1. Requests a crater from a blast, on the server only.
##
## Clients never author deformation (Invariant 1); they apply the replicated
## request through [method apply_replicated]. Returns the request so a caller
## can broadcast it, or null when it was coalesced or refused.
func request_crater(
	centre: Vector3, blast_radius_m: float, blast_damage: float, source_assembly_id: int = 0
) -> DeformRequest:
	if array == null or not NetAuthority.is_authoritative():
		return null
	if blast_radius_m <= 0.0:
		return null

	var hardness := SurfaceTable.hardness(array.surface_at_world(centre))
	var req := DeformRequest.crater(
		centre,
		CraterProfile.radius_for(blast_radius_m),
		CraterProfile.depth_for(blast_damage, hardness),
		MatchClock.tick,
		_next_deform_id,
		source_assembly_id
	)
	if _coalesce_into_pending(req):
		return null
	if not _admit(req):
		return null
	_next_deform_id += 1
	_enqueue(req)
	return req


## Applies a request authored elsewhere — a replicated event from the server, or
## a log entry replayed on join. §10.2.
##
## Bypasses the rate limit and the authority check, both of which the
## originating server already applied. It does not bypass coalescing, because a
## replayed log is already coalesced and a second pass finds nothing.
func apply_replicated(req: DeformRequest) -> void:
	if array == null:
		return
	_next_deform_id = maxi(_next_deform_id, req.deform_id + 1)
	_enqueue(req)


## §6. Accumulates one contact's rut into the pending batch.
##
## [param track_key] distinguishes contacts so that a single contact standing
## still does not re-deposit into the same sample every tick; pass a stable
## per-contact identity such as [code]assembly_id * 256 + slot[/code].
func accumulate_rut(
	contact_world: Vector3, normal_load_n: float, surface_id: int, track_key: int
) -> void:
	if array == null or not NetAuthority.is_authoritative():
		return
	if normal_load_n < RUT_MIN_LOAD_N:
		return
	if not SurfaceTable.is_ruttable(surface_id):
		return
	var s := GroundMath.world_to_sample(contact_world)
	if not GroundConstants.is_valid_sample(s):
		return
	if _last_rut_sample.get(track_key, Vector2i(-9999, -9999)) == s:
		return
	_last_rut_sample[track_key] = s
	var depth := minf((normal_load_n - RUT_MIN_LOAD_N) * RUT_DEPTH_PER_KN_M * 0.001,
		RUT_MAX_DEPTH_M)
	var key := _encode_sample(s)
	_rut_batch[key] = maxf(float(_rut_batch.get(key, 0.0)), depth)


## §10.3. The ordered request log, for a late joiner to replay.
func deform_log() -> Array[DeformRequest]:
	return _log.duplicate()


## Whether a late joiner should be sent a delta snapshot instead of the log.
func log_exceeds_snapshot_threshold() -> bool:
	return _log.size() > LOG_SNAPSHOT_THRESHOLD


func pending_count() -> int:
	return _queue.size()


func running_count() -> int:
	_run_mutex.lock()
	var n := _running.size()
	_run_mutex.unlock()
	return n


## Drives every request to completion, for a test or a load-time replay that
## must not spread commits across frames.
##
## Ignores [constant COMMIT_BUDGET_MS] deliberately: the budget exists to
## protect a frame, and neither caller is inside one.
func flush() -> void:
	var guard := 0
	while (not _queue.is_empty() or running_count() > 0 or not _ready_results.is_empty()):
		_dispatch_pending()
		_commit(INF)
		guard += 1
		if guard > 4096:
			push_error("GroundDeformSystem.flush did not converge")
			return


func _process(dt: float) -> void:
	_tick_rate_window(dt)
	_tick_ruts(dt)
	_dispatch_pending()
	_commit(COMMIT_BUDGET_MS)


## ===== STAGE 1: REQUEST ================================================


func _enqueue(req: DeformRequest) -> void:
	# Chunks are materialised here, on the main thread, so that the worker only
	# ever mutates arrays that already exist. Growing the chunk dictionary from
	# a worker while the tick loop reads it is a crash rather than a wrong
	# answer, and this is what makes the lock discipline sufficient.
	array.ensure_region(req.centre_world, req.influence_radius_m())
	_queue.push_back(req)
	_log.push_back(req)


## §4.2. Merges [param req] into a queued request at the same tick and within
## [constant COALESCE_DISTANCE_M].
func _coalesce_into_pending(req: DeformRequest) -> bool:
	for existing: DeformRequest in _queue:
		if existing.source_tick != req.source_tick:
			continue
		if existing.kind != req.kind:
			continue
		var separation := existing.centre_world.distance_to(req.centre_world)
		if separation > COALESCE_DISTANCE_M:
			continue
		existing.depth_m = maxf(existing.depth_m, req.depth_m)
		existing.radius_m = maxf(existing.radius_m, separation + req.radius_m)
		# The merged request now reaches further than when its chunks were
		# materialised, so the region has to be re-ensured.
		array.ensure_region(existing.centre_world, existing.influence_radius_m())
		return true
	return false


## §10.4. Rate limit. Returns false when the request must be refused outright.
func _admit(req: DeformRequest) -> bool:
	var per_assembly := int(_per_assembly_this_second.get(req.source_assembly_id, 0))
	if _deforms_this_second >= MAX_DEFORMS_PER_SECOND:
		return _coalesce_into_nearest(req)
	if req.source_assembly_id != 0 and per_assembly >= MAX_DEFORMS_PER_ASSEMBLY_PER_SECOND:
		return _coalesce_into_nearest(req)
	_deforms_this_second += 1
	_per_assembly_this_second[req.source_assembly_id] = per_assembly + 1
	return true


## Folds a rate-limited request into the nearest pending one, so that exceeding
## the limit produces a merged deformation rather than a dropped one.
func _coalesce_into_nearest(req: DeformRequest) -> bool:
	var best: DeformRequest = null
	var best_d := INF
	for existing: DeformRequest in _queue:
		var d := existing.centre_world.distance_to(req.centre_world)
		if d < best_d:
			best_d = d
			best = existing
	if best == null:
		return false
	best.depth_m = maxf(best.depth_m, req.depth_m)
	best.radius_m = maxf(best.radius_m, best_d + req.radius_m)
	array.ensure_region(best.centre_world, best.influence_radius_m())
	return false


func _tick_rate_window(dt: float) -> void:
	_second_accum_s += dt
	if _second_accum_s < 1.0:
		return
	_second_accum_s = 0.0
	_deforms_this_second = 0
	_per_assembly_this_second.clear()


func _tick_ruts(dt: float) -> void:
	_rut_accum_s += dt
	if _rut_accum_s < RUT_FLUSH_INTERVAL_S:
		return
	_rut_accum_s = 0.0
	_flush_rut_batch()


## §6. Emits the accumulated ruts as a single request.
func _flush_rut_batch() -> void:
	if _rut_batch.is_empty() or array == null:
		return
	var keys: Array = _rut_batch.keys()
	keys.sort()  # I-9: never a raw Dictionary key order
	var req := DeformRequest.new()
	req.kind = DeformRequest.Kind.RUT
	req.source_tick = MatchClock.tick
	req.deform_id = _next_deform_id
	_next_deform_id += 1
	var sum := Vector2.ZERO
	for key: int in keys:
		var s := _decode_sample(key)
		req.rut_sample_x.push_back(s.x)
		req.rut_sample_z.push_back(s.y)
		req.rut_depth_m.push_back(float(_rut_batch[key]))
		sum += GroundMath.sample_to_world_xz(s)
	var centre := sum / float(keys.size())
	req.centre_world = Vector3(centre.x, 0.0, centre.y)
	_rut_batch.clear()
	_enqueue(req)


## ===== STAGES 2 TO 4: THE WORKER =======================================


func _dispatch_pending() -> void:
	while not _queue.is_empty():
		_run_mutex.lock()
		var busy := _running.size()
		var overlaps := _overlaps_running_unlocked(_queue[0])
		_run_mutex.unlock()
		if busy >= MAX_IN_FLIGHT_DEFORMS:
			return
		# Strictly head-of-queue: a blocked request stops dispatch rather than
		# being skipped, because §10.1's ordering requirement is a correctness
		# property and not a preference.
		if overlaps:
			return
		var req: DeformRequest = _queue.pop_front()
		_run_mutex.lock()
		_running.push_back(req)
		_run_mutex.unlock()
		if synchronous:
			_run_stages(req)
		else:
			WorkerThreadPool.add_task(_run_stages.bind(req), true, "ground_deform")


func _overlaps_running_unlocked(req: DeformRequest) -> bool:
	for f: DeformRequest in _running:
		var reach := f.influence_radius_m() + req.influence_radius_m()
		if f.centre_world.distance_to(req.centre_world) < reach:
			return true
	return false


## Stages 2 to 4, on the worker. The only place [member GroundChunk.live_heights]
## is written.
func _run_stages(req: DeformRequest) -> void:
	var result := DeformResult.new()
	result.request = req

	array.lock.lock()
	if req.kind == DeformRequest.Kind.RUT:
		_solve_ruts(req, result)
	else:
		_solve_crater(req, result)
	_apply_to_chunk_arrays(result)
	array.lock.unlock()

	_build_chunk_payloads(result)

	_ready_mutex.lock()
	_ready_results.push_back(result)
	_ready_mutex.unlock()

	_run_mutex.lock()
	_running.erase(req)
	_run_mutex.unlock()


## §4.3. Stage 2 for a crater.
##
## Reads live heights and writes nothing: every new value lands in
## [param result] and [method _apply_to_chunk_arrays] commits them together.
## That ordering is what makes the solve a pure function of the pre-deformation
## field, which is in turn what makes it reproducible on every peer.
func _solve_crater(req: DeformRequest, result: DeformResult) -> void:
	var centre_s := GroundMath.world_to_sample(req.centre_world)
	var radius_samples := int(ceil(req.radius_m / GroundConstants.SAMPLE_SPACING_M))
	var centre_xz := Vector2(req.centre_world.x, req.centre_world.z)
	# The blast's own ground plane, which the bowl levels toward.
	var ground_y := array.sample_height_unlocked(centre_s)

	for dz: int in range(-radius_samples, radius_samples + 1):
		for dx: int in range(-radius_samples, radius_samples + 1):
			var s := centre_s + Vector2i(dx, dz)
			if not GroundConstants.is_valid_sample(s):
				continue
			var wp := GroundMath.sample_to_world_xz(s)
			var u := wp.distance_to(centre_xz) / maxf(req.radius_m, 0.0001)
			if u >= 1.0:
				continue
			var current := array.sample_height_unlocked(s)
			# The datum this sample's profile is measured from. Levelling pulls
			# the bowl toward the blast's own ground plane so a crater on a
			# hillside becomes a flat shelf rather than a tilted dish a vehicle
			# slides out of — and it falls to zero at the bowl's edge, so the
			# rim is deposited on whatever surface is actually there.
			var level := 1.0 - smoothstep(0.0, CraterProfile.RIM_BOUNDARY, u)
			var datum := lerpf(current, ground_y, level * SLOPE_LEVEL_STRENGTH)
			var new_h := datum + CraterProfile.delta_height(u, req.depth_m)
			new_h = _apply_erosion_clamp(s, new_h)
			result.push(s, GroundMath.quantise(new_h), new_h - current)
	result.empty = result.count() == 0


## §6. Stage 2 for a rut batch: each sample is pressed down by its own depth,
## with no profile and no levelling.
func _solve_ruts(req: DeformRequest, result: DeformResult) -> void:
	for i: int in req.sample_count():
		var s := Vector2i(req.rut_sample_x[i], req.rut_sample_z[i])
		if not GroundConstants.is_valid_sample(s):
			continue
		var current := array.sample_height_unlocked(s)
		var new_h := _apply_erosion_clamp(s, current - req.rut_depth_m[i])
		result.push(s, GroundMath.quantise(new_h), new_h - current)
	result.empty = result.count() == 0


## §4.4. Attenuates excavation as it approaches [constant MAX_EROSION_M].
##
## Rim uplift is deliberately unclamped: the limit exists to stop repeated
## bombardment digging a pit that swallows vehicles and punches through the
## world floor, and a raised rim does neither.
func _apply_erosion_clamp(s: Vector2i, proposed_h: float) -> float:
	var base_h := array.base_height_unlocked(s)
	var eroded := base_h - proposed_h
	if eroded <= 0.0:
		return proposed_h
	var soft := MAX_EROSION_M * EROSION_SOFT_START
	if eroded <= soft:
		return proposed_h
	var over := eroded - soft
	var range_left := MAX_EROSION_M - soft
	var attenuated := soft + range_left * (1.0 - exp(-over / range_left))
	return base_h - attenuated


## Writes the solved values into the chunk arrays and reclassifies surfaces.
## Every write goes to every chunk sharing the sample (Invariant 4).
func _apply_to_chunk_arrays(result: DeformResult) -> void:
	for i: int in result.count():
		var s := result.sample_at(i)
		array.write_sample_unlocked(s, result.value[i])
		# §9.2: a change large enough to be a crater floor or a rut bed
		# reclassifies, which is what gives the deformation tactical weight
		# beyond the visual — DEFORMED carries 0.66 traction.
		if absf(result.delta_m[i]) >= DEFORM_RECLASSIFY_THRESHOLD_M:
			array.write_surface_unlocked(s, SurfaceTable.Surface.DEFORMED)


## Stages 3 and 4: build the replacement collision arrays and images for every
## chunk this deformation dirtied.
##
## Only chunks that are streamed get a collision array, and only chunks with a
## render mesh get images. A crater in an unpopulated corner of the map updates
## height data and creates no collision shape at all until something approaches
## (Invariant 7).
func _build_chunk_payloads(result: DeformResult) -> void:
	var touched: Dictionary = {}
	for i: int in result.count():
		for cc: Vector2i in GroundMath.shared_chunks(result.sample_at(i)):
			touched[cc] = true
	var coords: Array = touched.keys()
	coords.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return GroundConstants.chunk_order_key(a) < GroundConstants.chunk_order_key(b)
	)
	array.lock.lock()
	for cc: Vector2i in coords:
		var chunk := array.existing_chunk(cc)
		if chunk == null:
			continue
		result.affected.push_back(chunk)
		if chunk.is_streamed():
			result.collision_arrays[cc] = build_collision_array(chunk)
		if chunk.render_mesh != null:
			result.height_images[cc] = build_height_image(chunk)
			result.surface_images[cc] = build_surface_image(chunk)
	array.lock.unlock()


## §4.5. [HeightMapShape3D] has no partial-update API, so the whole array is
## rebuilt — on the worker, which is the entire point.
static func build_collision_array(chunk: GroundChunk) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(GroundChunk.SAMPLE_COUNT)
	for i: int in GroundChunk.SAMPLE_COUNT:
		out[i] = GroundMath.dequantise(chunk.live_heights[i])
	return out


## §4.6. The R16 height field the ground shader displaces by.
static func build_height_image(chunk: GroundChunk) -> Image:
	var n := GroundConstants.CHUNK_SAMPLES
	var img := Image.create(n, n, false, Image.FORMAT_RH)
	for z: int in n:
		for x: int in n:
			var h := GroundMath.dequantise(chunk.live_heights[z * n + x])
			var norm := (h - GroundConstants.HEIGHT_MIN_M) / GroundConstants.HEIGHT_RANGE_M
			img.set_pixel(x, z, Color(norm, 0.0, 0.0, 1.0))
	return img


## §9.2. The R8 splat carrying the surface ordinal per sample.
static func build_surface_image(chunk: GroundChunk) -> Image:
	var n := GroundConstants.CHUNK_SAMPLES
	var img := Image.create(n, n, false, Image.FORMAT_R8)
	for z: int in n:
		for x: int in n:
			var id := float(chunk.surface_ids[z * n + x]) / 255.0
			img.set_pixel(x, z, Color(id, 0.0, 0.0, 1.0))
	return img


## ===== STAGE 5: COMMIT =================================================


## §4.7. Swaps shape data and textures under [param budget_ms].
##
## The budget loop is what guarantees no hitch, and it is checked before each
## result rather than after, so one commit can overrun but a queue of them
## cannot.
func _commit(budget_ms: float) -> void:
	var start := Time.get_ticks_usec()
	while true:
		_ready_mutex.lock()
		var have := not _ready_results.is_empty()
		_ready_mutex.unlock()
		if not have:
			return
		if (Time.get_ticks_usec() - start) / 1000.0 > budget_ms:
			return
		_ready_mutex.lock()
		var r: DeformResult = _ready_results.pop_front()
		_ready_mutex.unlock()
		_commit_one(r)


func _commit_one(r: DeformResult) -> void:
	for chunk: GroundChunk in r.affected:
		var cc := chunk.chunk_coord
		if chunk.collision_shape != null and r.collision_arrays.has(cc):
			chunk.collision_shape.map_data = r.collision_arrays[cc]
		if chunk.render_mesh != null and r.height_images.has(cc):
			chunk.height_texture.update(r.height_images[cc])
			chunk.surface_texture.update(r.surface_images[cc])
		chunk.revision += 1
		chunk.clear_dirty()
	EventBus.ground_deformed.emit(
		r.request.deform_id, r.request.centre_world, r.request.influence_radius_m()
	)


## ===== SAMPLE KEY ENCODING =============================================
## A sample packs into one int so the rut batch can be a dictionary keyed by
## something sortable, which I-9 requires — iterating raw Vector2i keys would
## make the flush order hash-dependent.


static func _encode_sample(s: Vector2i) -> int:
	return s.y * GroundConstants.WORLD_SAMPLES + s.x


static func _decode_sample(key: int) -> Vector2i:
	return Vector2i(key % GroundConstants.WORLD_SAMPLES, key / GroundConstants.WORLD_SAMPLES)
