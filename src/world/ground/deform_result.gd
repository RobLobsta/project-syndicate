class_name DeformResult
extends RefCounted
## The solved output of one [DeformRequest], produced on a worker thread and
## committed on the main thread. [code]docs/TERRAIN_CRATER_DEFORMER.md[/code]
## §4, stages 2 to 5.
##
## Everything expensive is precomputed into this object so that stage 5 is three
## assignments and a signal. The main thread never iterates samples.

var request: DeformRequest = null

## ===== STAGE 2 OUTPUT ==================================================
## Parallel arrays: sample (x, z) and its new quantised height. Packed rather
## than an [code]Array[Vector2i][/code] because a large crater touches a few
## thousand samples and this is the hot allocation of the whole pipeline.

var sample_x: PackedInt32Array = PackedInt32Array()
var sample_z: PackedInt32Array = PackedInt32Array()
var value: PackedInt32Array = PackedInt32Array()
## Height change in metres per sample, retained for §9.2's reclassification
## threshold and for the [signal EventBusService.ground_deformed] payload.
var delta_m: PackedFloat32Array = PackedFloat32Array()

## ===== STAGE 3 AND 4 OUTPUT ============================================
## Keyed by chunk coordinate. Only chunks that are streamed get a collision
## array; only chunks with a render mesh get images (Invariant 7).

var collision_arrays: Dictionary = {}  # Vector2i -> PackedFloat32Array
var height_images: Dictionary = {}  # Vector2i -> Image
var surface_images: Dictionary = {}  # Vector2i -> Image

## Chunks this deformation touched, in deterministic order.
var affected: Array[GroundChunk] = []

## Set by the worker when the solve produced nothing — a request entirely
## outside the world, or one whose every sample was already at the erosion
## limit. A no-op result still commits, so that the request leaves the in-flight
## set and the queue drains.
var empty: bool = false


func count() -> int:
	return sample_x.size()


func sample_at(i: int) -> Vector2i:
	return Vector2i(sample_x[i], sample_z[i])


func push(s: Vector2i, quantised: int, delta: float) -> void:
	sample_x.push_back(s.x)
	sample_z.push_back(s.y)
	value.push_back(quantised)
	delta_m.push_back(delta)
