class_name GroundArray
extends Node3D
## The Dynamic Ground Array: a chunked, mutable heightfield that permanently
## records the damage inflicted on it. Owned by
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §2.
##
## This class owns the height data and the nodes that present it. It does not
## decide what deforms it — [GroundDeformSystem] does that — and it does not
## decide which chunks carry collision — [GroundCollisionStreamer] does that.
## Splitting the three keeps the data structure testable without a physics space
## and without a worker pool.
##
## [b]Chunks are allocated lazily and never freed.[/b] A chunk costs about
## 215 KB and the world holds 1 024 of them, so materialising the lot would cost
## over 200 MB to represent terrain a match never visits. Allocation happens on
## the main thread through [method ensure_region], and the worker pipeline then
## only ever mutates arrays that already exist. That ordering is deliberate:
## growing a [Dictionary] while another thread reads it is a crash rather than a
## wrong answer, and no lock discipline is cheaper than not sharing the mutation
## at all.
##
## [b]Threading contract[/b] (§8.1). [member lock] guards the height and surface
## arrays. Public queries lock around the read; [GroundDeformSystem] locks around
## its solve and its array writes. The [code]_unlocked[/code] variants exist for
## callers that already hold the lock; calling a locking method while holding it
## deadlocks.
##
## [b]Amendment to §8.1 rule 3.[/b] The document specifies an [code]RWLock[/code].
## Godot 4 does not expose one to GDScript — [Mutex], [Semaphore], [Thread] and
## [WorkerThreadPool] are the whole set — so this is a plain mutex. The
## substitution costs nothing measurable here: writes happen only inside a
## deformation solve, a few times a second at most, and the readers are a handful
## of sample lookups per contact per tick. Serialising two readers that would
## have run concurrently is cheaper than the GDScript-level reader-writer lock
## that would avoid it.

## Guards [member GroundChunk.live_heights] and
## [member GroundChunk.surface_ids] against the worker pipeline. §8.1 rule 3,
## as amended above.
var lock: Mutex = Mutex.new()

## Provides [member GroundChunk.base_heights]. Pure in sample position, which is
## what makes lazy allocation safe — see [GroundSource].
var source: GroundSource = GroundSource.flat()

## Whether presentation nodes are built. Mirrors
## [code]SubsystemGate.is_enabled(&"ground_height_texture")[/code], captured at
## construction rather than queried per chunk.
var present_visuals: bool = true

## Material every chunk's render mesh shares. Null until [method _ready] builds
## it, and never built at all on a headless server.
var _chunk_material: ShaderMaterial = null

var _chunks: Dictionary = {}  # Vector2i -> GroundChunk

## Parent for streamed collision bodies, so a chunk's body can be freed without
## walking this node's whole child list.
var _collision_root: Node3D = null
var _visual_root: Node3D = null

const GROUND_SHADER_PATH: String = "res://src/vfx/shaders/ground_array.gdshader"


func _ready() -> void:
	_collision_root = Node3D.new()
	_collision_root.name = "ChunkCollision"
	add_child(_collision_root)
	if present_visuals:
		_visual_root = Node3D.new()
		_visual_root.name = "ChunkVisuals"
		add_child(_visual_root)
		_chunk_material = _build_material()


## ===== CHUNK ACCESS ====================================================


## The chunk at [param cc], creating and filling it if it does not yet exist.
##
## [b]Main thread only.[/b] This mutates the chunk dictionary.
func chunk_at(cc: Vector2i) -> GroundChunk:
	if not GroundConstants.is_valid_chunk(cc):
		return null
	var existing: GroundChunk = _chunks.get(cc, null)
	if existing != null:
		return existing
	var chunk := GroundChunk.new()
	chunk.fill_from(cc, source)
	_chunks[cc] = chunk
	return chunk


## The chunk at [param cc] if it has been materialised, else null. Safe to call
## from a worker, because it never grows the dictionary.
func existing_chunk(cc: Vector2i) -> GroundChunk:
	return _chunks.get(cc, null)


## Materialises every chunk within [param radius_m] of [param centre] and
## returns them in deterministic order.
##
## Called on the main thread before a deformation is dispatched, so that the
## worker finds every array it needs already allocated.
func ensure_region(centre: Vector3, radius_m: float) -> Array[GroundChunk]:
	var out: Array[GroundChunk] = []
	for cc: Vector2i in chunk_coords_for_region(centre, radius_m):
		var chunk := chunk_at(cc)
		if chunk != null:
			out.push_back(chunk)
	return out


## Chunk coordinates overlapping the disc of [param radius_m] about
## [param centre], in ascending [method GroundConstants.chunk_order_key] order.
func chunk_coords_for_region(centre: Vector3, radius_m: float) -> Array[Vector2i]:
	var lo := GroundMath.world_to_sample(centre - Vector3(radius_m, 0.0, radius_m))
	var hi := GroundMath.world_to_sample(centre + Vector3(radius_m, 0.0, radius_m))
	var span := GroundConstants.CHUNK_SAMPLES - 1
	var out: Array[Vector2i] = []
	# Step back one chunk on the low side: a sample exactly on a seam is also
	# the far edge of the previous chunk, and that copy has to be written too.
	var c_lo := Vector2i(lo.x / span - 1, lo.y / span - 1)
	var c_hi := Vector2i(hi.x / span, hi.y / span)
	for cz: int in range(maxi(c_lo.y, 0), mini(c_hi.y, GroundConstants.WORLD_CHUNKS.y - 1) + 1):
		for cx: int in range(maxi(c_lo.x, 0), mini(c_hi.x, GroundConstants.WORLD_CHUNKS.x - 1) + 1):
			out.push_back(Vector2i(cx, cz))
	return out


## Chunks that currently exist, in deterministic order.
func materialised_chunks() -> Array[GroundChunk]:
	var coords: Array[Vector2i] = []
	for cc: Vector2i in _chunks:
		coords.push_back(cc)
	coords.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return GroundConstants.chunk_order_key(a) < GroundConstants.chunk_order_key(b)
	)
	var out: Array[GroundChunk] = []
	for cc: Vector2i in coords:
		out.push_back(_chunks[cc])
	return out


func materialised_count() -> int:
	return _chunks.size()


## ===== SAMPLE QUERIES ==================================================


## Live height in metres at sample [param s]. Takes a read lock.
func sample_height_m(s: Vector2i) -> float:
	lock.lock()
	var h := sample_height_unlocked(s)
	lock.unlock()
	return h


## Live height in metres at sample [param s], without locking.
##
## Falls back to the [GroundSource] baseline for a chunk that has never been
## materialised, which is correct by construction: an unmaterialised chunk has
## never been deformed, so its live height is its baseline.
func sample_height_unlocked(s: Vector2i) -> float:
	if not GroundConstants.is_valid_sample(s):
		return source.height_at(s)
	var cc := _owning_chunk(s)
	var chunk: GroundChunk = _chunks.get(cc, null)
	if chunk == null:
		return source.height_at(s)
	var local := GroundMath.sample_in_chunk(s, cc)
	return GroundMath.dequantise(chunk.live_heights[GroundChunk.local_index(local)])


## Baseline height in metres at sample [param s], without locking.
##
## [member GroundChunk.base_heights] is never modified after fill (Invariant 5),
## so this needs no lock even from a worker.
func base_height_unlocked(s: Vector2i) -> float:
	if not GroundConstants.is_valid_sample(s):
		return source.height_at(s)
	var cc := _owning_chunk(s)
	var chunk: GroundChunk = _chunks.get(cc, null)
	if chunk == null:
		return source.height_at(s)
	var local := GroundMath.sample_in_chunk(s, cc)
	return GroundMath.dequantise(chunk.base_heights[GroundChunk.local_index(local)])


## Surface classification at sample [param s]. Takes a read lock.
func sample_surface(s: Vector2i) -> int:
	lock.lock()
	var id := sample_surface_unlocked(s)
	lock.unlock()
	return id


func sample_surface_unlocked(s: Vector2i) -> int:
	if not GroundConstants.is_valid_sample(s):
		return source.surface_at(s)
	var cc := _owning_chunk(s)
	var chunk: GroundChunk = _chunks.get(cc, null)
	if chunk == null:
		return source.surface_at(s)
	var local := GroundMath.sample_in_chunk(s, cc)
	return int(chunk.surface_ids[GroundChunk.local_index(local)])


## Bilinearly interpolated live height at world position [param p].
##
## The interpolation matters for gameplay reads — a rut accumulator or a ground
## clearance query stepping between samples would otherwise see the surface as a
## staircase 0.5 m wide.
func height_at_world(p: Vector3) -> float:
	lock.lock()
	var h := height_at_world_unlocked(p)
	lock.unlock()
	return h


func height_at_world_unlocked(p: Vector3) -> float:
	var half := GroundConstants.WORLD_SPAN_M * 0.5
	var fx := (p.x + half) / GroundConstants.SAMPLE_SPACING_M
	var fz := (p.z + half) / GroundConstants.SAMPLE_SPACING_M
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var h00 := sample_height_unlocked(Vector2i(x0, z0))
	var h10 := sample_height_unlocked(Vector2i(x0 + 1, z0))
	var h01 := sample_height_unlocked(Vector2i(x0, z0 + 1))
	var h11 := sample_height_unlocked(Vector2i(x0 + 1, z0 + 1))
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Surface classification at world position [param p]. Nearest sample rather
## than interpolated: a surface id is an enum and blending two of them is
## meaningless.
func surface_at_world(p: Vector3) -> int:
	return sample_surface(GroundMath.world_to_sample(p))


## ===== SAMPLE WRITES ===================================================
## Callers must hold the write lock. Every write goes to every chunk that stores
## a copy of the sample (§2.4, Invariant 4).


## Writes quantised height [param q] to sample [param s] in every chunk that
## stores it.
##
## Returns the number of copies written, which
## [code]tests/integration/test_ground_seams.gd[/code] asserts is 2 on an edge
## and 4 on a corner. A caller that wrote only one copy would leave a visible
## and collidable crack along the chunk seam.
func write_sample_unlocked(s: Vector2i, q: int) -> int:
	if not GroundConstants.is_valid_sample(s):
		return 0
	var written := 0
	for cc: Vector2i in GroundMath.shared_chunks(s):
		var chunk: GroundChunk = _chunks.get(cc, null)
		if chunk == null:
			continue
		var local := GroundMath.sample_in_chunk(s, cc)
		if not GroundChunk.contains_local(local):
			continue
		chunk.live_heights[GroundChunk.local_index(local)] = q
		chunk.mark_dirty(local.x, local.y)
		written += 1
	return written


## Writes surface id [param id] to sample [param s] in every chunk that stores
## it. §9.2.
func write_surface_unlocked(s: Vector2i, id: int) -> int:
	if not GroundConstants.is_valid_sample(s):
		return 0
	var written := 0
	for cc: Vector2i in GroundMath.shared_chunks(s):
		var chunk: GroundChunk = _chunks.get(cc, null)
		if chunk == null:
			continue
		var local := GroundMath.sample_in_chunk(s, cc)
		if not GroundChunk.contains_local(local):
			continue
		chunk.surface_ids[GroundChunk.local_index(local)] = id
		written += 1
	return written


## Restores every materialised chunk to its baseline, for a round restart.
func reset_to_base() -> void:
	lock.lock()
	for chunk: GroundChunk in materialised_chunks():
		chunk.reset_to_base()
	lock.unlock()


## ===== COLLISION AND PRESENTATION ======================================


## Builds and attaches collision for [param chunk] from [param heights].
##
## [param heights] is built on a worker (§4.5) and handed here already
## dequantised, because assigning [member HeightMapShape3D.map_data] is the one
## unavoidable main-thread cost and building the array is not.
##
## [b]The shape resource must be held.[/b] A [HeightMapShape3D] reachable only
## through a physics RID is freed the moment the last reference drops, and the
## body then silently stops colliding — see [code]HANDOFF.md[/code] §3.61.
func attach_collision(chunk: GroundChunk, heights: PackedFloat32Array) -> void:
	if chunk.collision_body != null:
		chunk.collision_shape.map_data = heights
		return
	var shape := HeightMapShape3D.new()
	shape.map_width = GroundConstants.CHUNK_SAMPLES
	shape.map_depth = GroundConstants.CHUNK_SAMPLES
	shape.map_data = heights

	var body := StaticBody3D.new()
	body.name = "GroundChunk_%d_%d" % [chunk.chunk_coord.x, chunk.chunk_coord.y]
	body.collision_layer = CollisionLayers.LAYER_GROUND
	body.collision_mask = 0

	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = shape
	# HeightMapShape3D has no sample-spacing property: its field is always one
	# unit per sample, centred on the shape origin. §2.1's 0.5 m spacing is
	# therefore a scale on the shape node, and the Y component stays 1 so that
	# heights remain metres.
	col.scale = Vector3(
		GroundConstants.SAMPLE_SPACING_M, 1.0, GroundConstants.SAMPLE_SPACING_M
	)
	body.add_child(col)
	_collision_root.add_child(body)
	body.global_position = GroundMath.chunk_centre_world(chunk.chunk_coord)

	chunk.collision_body = body
	chunk.collision_shape = shape


## Frees [param chunk]'s collision body. The height data is untouched — a chunk
## streamed out and back in rebuilds its shape from [member
## GroundChunk.live_heights], which already carries every deformation
## (Invariant 7).
func release_collision(chunk: GroundChunk) -> void:
	if chunk.collision_body == null:
		return
	_collision_root.remove_child(chunk.collision_body)
	chunk.collision_body.queue_free()
	chunk.collision_body = null
	chunk.collision_shape = null


## Builds [param chunk]'s render mesh and textures if presentation is on.
func attach_visual(chunk: GroundChunk, image: Image, surface_image: Image) -> void:
	if not present_visuals or _visual_root == null:
		return
	if chunk.render_mesh != null:
		chunk.height_texture.update(image)
		chunk.surface_texture.update(surface_image)
		return
	chunk.height_texture = ImageTexture.create_from_image(image)
	chunk.surface_texture = ImageTexture.create_from_image(surface_image)

	var mi := MeshInstance3D.new()
	mi.name = "GroundVisual_%d_%d" % [chunk.chunk_coord.x, chunk.chunk_coord.y]
	mi.mesh = _build_chunk_mesh()
	mi.layers = RenderLayers.LAYER_WORLD
	# Invariant I-1: nothing under a visual root carries collision, and the
	# simulation reads the HeightMapShape3D rather than this.
	var mat := _chunk_material.duplicate() as ShaderMaterial
	mat.set_shader_parameter(&"u_height", chunk.height_texture)
	mat.set_shader_parameter(&"u_surface", chunk.surface_texture)
	mi.material_override = mat
	# The displaced surface can reach anywhere in the representable band, and a
	# custom AABB stops the mesh being frustum-culled while its vertices are
	# still on screen.
	mi.custom_aabb = AABB(
		Vector3(
			-GroundConstants.CHUNK_SPAN_M * 0.5,
			GroundConstants.HEIGHT_MIN_M,
			-GroundConstants.CHUNK_SPAN_M * 0.5
		),
		Vector3(
			GroundConstants.CHUNK_SPAN_M,
			GroundConstants.HEIGHT_RANGE_M,
			GroundConstants.CHUNK_SPAN_M
		)
	)
	_visual_root.add_child(mi)
	mi.global_position = GroundMath.chunk_centre_world(chunk.chunk_coord)
	chunk.render_mesh = mi


## A flat grid of [constant GroundConstants.CHUNK_SAMPLES] squared vertices,
## one per height sample, with UVs on texel centres.
##
## Built here rather than from a [PlaneMesh] because the shader indexes the
## height texture by UV and the correspondence has to be exact. A plane's UV
## convention is the engine's business and has flipped between versions; a
## mirrored V would put the visible hills where the collision has hollows, which
## is a defect a player meets immediately and a test never sees.
##
## The mesh is flat. Every vertex is displaced in the vertex shader, which is
## why a deformation commit is a texture blit rather than a mesh rebuild.
func _build_chunk_mesh() -> ArrayMesh:
	var n := GroundConstants.CHUNK_SAMPLES
	var half := GroundConstants.CHUNK_SPAN_M * 0.5
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	verts.resize(n * n)
	uvs.resize(n * n)
	normals.resize(n * n)
	for z: int in n:
		for x: int in n:
			var i := z * n + x
			verts[i] = Vector3(
				float(x) * GroundConstants.SAMPLE_SPACING_M - half,
				0.0,
				float(z) * GroundConstants.SAMPLE_SPACING_M - half
			)
			# Texel centres: sample x maps to (x + 0.5) / n, so filter_linear
			# returns that sample exactly rather than a blend of two.
			uvs[i] = Vector2((float(x) + 0.5) / float(n), (float(z) + 0.5) / float(n))
			normals[i] = Vector3.UP

	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var w := 0
	for z: int in n - 1:
		for x: int in n - 1:
			var i00 := z * n + x
			var i10 := z * n + x + 1
			var i01 := (z + 1) * n + x
			var i11 := (z + 1) * n + x + 1
			# Counter-clockwise seen from +Y, which is what cull_back wants for
			# a surface being looked down on.
			indices[w] = i00; indices[w + 1] = i01; indices[w + 2] = i11
			indices[w + 3] = i00; indices[w + 4] = i11; indices[w + 5] = i10
			w += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var shader := load(GROUND_SHADER_PATH)
	if shader == null:
		push_error("GroundArray: ground shader missing at %s" % GROUND_SHADER_PATH)
		return mat
	mat.shader = shader
	mat.set_shader_parameter(&"u_height_min", GroundConstants.HEIGHT_MIN_M)
	mat.set_shader_parameter(&"u_height_range", GroundConstants.HEIGHT_RANGE_M)
	mat.set_shader_parameter(&"u_sample_spacing", GroundConstants.SAMPLE_SPACING_M)
	mat.set_shader_parameter(&"u_chunk_samples", float(GroundConstants.CHUNK_SAMPLES))
	return mat


## The chunk that owns [param s] as an interior sample, clamped to the world.
##
## Reads use one copy and it does not matter which, because every write updates
## all of them. Writes use [method GroundMath.shared_chunks] instead.
func _owning_chunk(s: Vector2i) -> Vector2i:
	var cc := GroundMath.sample_to_chunk(s)
	cc.x = mini(cc.x, GroundConstants.WORLD_CHUNKS.x - 1)
	cc.y = mini(cc.y, GroundConstants.WORLD_CHUNKS.y - 1)
	return cc
