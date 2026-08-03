class_name GroundCollisionStreamer
extends Node
## Keeps heightfield collision resident only near things that can touch it.
## Owned by [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §5.
##
## Instantiating 1 024 [HeightMapShape3D] bodies is neither necessary nor
## affordable. Collision exists within
## [constant GroundConstants.COLLISION_STREAM_RADIUS_M] of an anchor, capped at
## [constant GroundConstants.MAX_COLLISION_CHUNKS], and everything else is data.
##
## [b]Streaming and deformation are fully independent.[/b] A chunk deformed
## while unstreamed keeps its dirty state and builds its collision array from
## [member GroundChunk.live_heights], which already carries every deformation —
## so a crater dug in an empty corner is waiting, correctly shaped, the first
## time anything drives out there. That is Invariant 7 and it falls out of
## storing height data separately from the shape that presents it.

## §5. How often the resident set is recomputed. Chunks are 64 m across and the
## stream radius is 180 m, so nothing can cross a chunk boundary and reach an
## unstreamed one inside this interval at any speed the game produces.
const REEVALUATE_INTERVAL_S: float = 0.5

## Chunks instantiated per evaluation. Spreading instantiation across ticks is
## what keeps a fast Assembly crossing a chunk seam from paying for four bodies
## in one frame.
const MAX_ACQUIRES_PER_EVALUATION: int = 4

var array: GroundArray = null
## Assemblies whose positions anchor collision. Supplied by the match scene.
var registry: AssemblyRegistry = null

## Extra world positions that should hold collision resident — debris bodies and
## live projectiles (§5). Rewritten by the owner each evaluation rather than
## maintained as a subscription, because both populations turn over constantly
## and a stale anchor holds a chunk resident for no reason.
var extra_anchors: PackedVector3Array = PackedVector3Array()

var _resident: Dictionary = {}  # Vector2i -> GroundChunk
var _accum_s: float = 0.0


func _physics_process(dt: float) -> void:
	_accum_s += dt
	if _accum_s < REEVALUATE_INTERVAL_S:
		return
	_accum_s = 0.0
	evaluate()


## Recomputes the resident set. Public so a test, or a scene that has just
## teleported everything, can force it without waiting out the interval.
func evaluate(max_acquires: int = MAX_ACQUIRES_PER_EVALUATION) -> void:
	if array == null:
		return
	var anchors := _anchor_positions()
	var wanted := _wanted_chunks(anchors)

	# Release first, so that a frame in which the anchor set moves wholesale
	# does not transiently exceed the cap and refuse the chunks it is moving to.
	for cc: Vector2i in _resident.keys():
		if not wanted.has(cc):
			_release(cc)

	var added := 0
	for cc: Vector2i in _by_proximity(wanted.keys(), anchors):
		if _resident.has(cc):
			continue
		if _resident.size() >= GroundConstants.MAX_COLLISION_CHUNKS:
			break
		_acquire(cc)
		added += 1
		if added >= max_acquires:
			break


## Acquires the whole wanted set at once, ignoring the per-evaluation cap.
##
## For scene construction and for a test placing something on the ground before
## the first tick — neither is inside a frame, and both need the chunk under the
## thing they are about to drop to exist rather than to be fourth in a queue.
## The steady-state path keeps the cap, which is what §5's spreading is for.
func prime() -> void:
	evaluate(GroundConstants.MAX_COLLISION_CHUNKS)


func resident_count() -> int:
	return _resident.size()


func is_resident(cc: Vector2i) -> bool:
	return _resident.has(cc)


## Every chunk within the stream radius of an anchor.
func _wanted_chunks(anchors: PackedVector3Array) -> Dictionary:
	var wanted: Dictionary = {}
	var reach := int(
		ceil(GroundConstants.COLLISION_STREAM_RADIUS_M / GroundConstants.CHUNK_SPAN_M)
	)
	for anchor: Vector3 in anchors:
		var cs := GroundMath.sample_to_chunk(GroundMath.world_to_sample(anchor))
		for dz: int in range(-reach, reach + 1):
			for dx: int in range(-reach, reach + 1):
				var cc := cs + Vector2i(dx, dz)
				if GroundConstants.is_valid_chunk(cc):
					wanted[cc] = true
	return wanted


func _anchor_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	if registry != null:
		for aid: int in registry.ids():
			var runtime := registry.get_runtime(aid)
			if runtime != null and runtime.body != null:
				out.push_back(runtime.body.global_position)
	out.append_array(extra_anchors)
	return out


## The wanted set ordered nearest-anchor first, ties broken on chunk index.
##
## [b]Amendment to §5.[/b] The document iterates `wanted.keys()` and breaks after
## four acquisitions, which acquires whichever four a [Dictionary] happens to
## yield. Ordering them by chunk index instead — the obvious fix, and the one
## this class shipped first — is worse in a specific way: it acquires the
## lowest-indexed corner of the wanted region, which is the chunk **furthest**
## from the anchor in the direction nothing is travelling. Measured: an Assembly
## dropped 140 m from the origin fell through the world, because the four chunks
## the first evaluation acquired were 180 m away from it.
##
## Distance is the only ordering that makes the cap safe. The chunk something is
## standing on must be acquired first, and the chunk it is about to reach next;
## everything else can wait for the next evaluation. The index tie-break is what
## keeps it deterministic (I-9) when two chunks are equidistant, which at a
## symmetric spawn is most of them.
func _by_proximity(coords: Array, anchors: PackedVector3Array) -> Array:
	var out := coords.duplicate()
	var distance := func(cc: Vector2i) -> float:
		var centre := GroundMath.chunk_centre_world(cc)
		var best := INF
		for a: Vector3 in anchors:
			best = minf(best, Vector2(centre.x - a.x, centre.z - a.z).length_squared())
		return best
	out.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var da: float = distance.call(a)
			var db: float = distance.call(b)
			if not is_equal_approx(da, db):
				return da < db
			return GroundConstants.chunk_order_key(a) < GroundConstants.chunk_order_key(b)
	)
	return out


func _acquire(cc: Vector2i) -> void:
	var chunk := array.chunk_at(cc)
	if chunk == null:
		return
	# Built from live_heights, so a chunk deformed while unstreamed streams in
	# already cratered.
	array.lock.lock()
	var heights := GroundDeformSystem.build_collision_array(chunk)
	var height_image: Image = null
	var surface_image: Image = null
	if array.present_visuals:
		height_image = GroundDeformSystem.build_height_image(chunk)
		surface_image = GroundDeformSystem.build_surface_image(chunk)
	array.lock.unlock()

	array.attach_collision(chunk, heights)
	if height_image != null:
		array.attach_visual(chunk, height_image, surface_image)
	_resident[cc] = chunk


func _release(cc: Vector2i) -> void:
	var chunk: GroundChunk = _resident.get(cc, null)
	if chunk != null:
		array.release_collision(chunk)
	_resident.erase(cc)
