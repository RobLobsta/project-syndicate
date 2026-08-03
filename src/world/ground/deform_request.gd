class_name DeformRequest
extends RefCounted
## One request to change the Ground Array, owned by
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §4.1.
##
## A request is the unit of replication (§10.1): it is what the server
## broadcasts and what a late-joining client replays, because the solve is
## deterministic (§8.2) and every peer therefore reaches the same heightfield
## from the same request sequence without any geometry crossing the wire.
##
## [b]The request is immutable once dispatched.[/b] Coalescing (§4.2) mutates a
## request that is still queued; nothing may mutate one that is running or
## logged, because a client replaying the log would then compute a different
## field from the same id.

enum Kind {
	## An explosive crater: a bowl with a raised rim, shaped by [CraterProfile].
	CRATER = 0,
	## Accumulated track and contact ruts, flushed as one batch. §6.
	RUT = 1,
	## A hard landing or a hull scraping the ground.
	SCRAPE = 2,
}

var centre_world: Vector3 = Vector3.ZERO
var radius_m: float = 0.0
var depth_m: float = 0.0
var kind: Kind = Kind.CRATER
var source_tick: int = 0
## Server-assigned and monotonic. Gives the log a total order and lets a client
## acknowledge how far it has applied.
var deform_id: int = 0
## Assembly that caused this, for §10.4's per-Assembly rate limit. Zero for
## world-sourced deformation.
var source_assembly_id: int = 0

## ===== RUT BATCH (§6) ==================================================
## Populated only for [constant Kind.RUT]. A rut request carries an explicit
## sample list rather than a radius, because the shape of a track's passage is
## the path it took and no profile function describes it.

var rut_sample_x: PackedInt32Array = PackedInt32Array()
var rut_sample_z: PackedInt32Array = PackedInt32Array()
var rut_depth_m: PackedFloat32Array = PackedFloat32Array()


static func crater(
	centre: Vector3, radius: float, depth: float, tick: int, id: int, assembly_id: int
) -> DeformRequest:
	var r := DeformRequest.new()
	r.centre_world = centre
	r.radius_m = radius
	r.depth_m = depth
	r.kind = Kind.CRATER
	r.source_tick = tick
	r.deform_id = id
	r.source_assembly_id = assembly_id
	return r


## Bounding radius of this request's influence, for the overlap and region
## checks. A rut batch's radius is derived from the spread of its samples.
func influence_radius_m() -> float:
	if kind != Kind.RUT:
		return radius_m
	var far := 0.0
	for i: int in rut_sample_x.size():
		var w := GroundMath.sample_to_world_xz(Vector2i(rut_sample_x[i], rut_sample_z[i]))
		far = maxf(far, w.distance_to(Vector2(centre_world.x, centre_world.z)))
	return far + GroundConstants.SAMPLE_SPACING_M


func sample_count() -> int:
	return rut_sample_x.size()
