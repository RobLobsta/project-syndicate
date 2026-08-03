class_name ManifoldChecker
extends RefCounted
## Decides whether a mesh is a closed solid that Godot's CSG will accept, as
## required by [code]docs/PROCEDURAL_STRUCTURE_SLICING.md[/code] §3.1.
##
## [b]This is a blocking gate, not a diagnostic.[/b] Godot 4.4 replaced the CSG
## implementation with the Manifold library, whose contract is that operands are
## watertight — and an operand that is not does not raise, does not warn, and
## does not fail the bake. It contributes nothing and the tree bakes cleanly
## without it. Measured against 4.7.1: an open two-triangle sheet unioned with a
## 1 m box bakes to exactly the box; a box with one face deleted bakes to
## nothing; a 9 408-triangle cylinder whose seam vertices differ by the 2.4e-16
## between [code]sin(0)[/code] and [code]sin(TAU)[/code] bakes to nothing and
## takes its twelve window cuts with it.
##
## So the failure mode a DCC-authored Static Volume produces is [b]a missing wall
## in an otherwise perfect building, with a green build log[/b]. Nothing
## downstream can detect it: a dropped operand leaves bake output that is
## impeccably manifold and simply missing a storey. The check therefore runs on
## the [i]input[/i] operands and refuses the bake.
##
## [b]The predicate must weld by position first.[/b] Counting edge uses by vertex
## index reports Godot's own [BoxMesh] as having 24 boundary edges, because a box
## is 24 vertices once split for UVs and normals — and the engine bakes that box
## perfectly, because Manifold welds by position internally. Degenerate triangles
## must [i]not[/i] disqualify either: [SphereMesh] ships 128 of them at its poles
## and bakes fine.
##
## Verified to agree with the engine on all six of [BoxMesh], [SphereMesh], a
## welded grid box, a float-seam cylinder, an open sheet, and a holed box.

## Grid the weld quantises positions to, in reciprocal metres. At 1/4096 m two
## vertices closer than about 0.24 mm are the same vertex — far below any
## intentional feature and far above the float error a DCC export introduces at
## a UV seam.
const WELD_QUANTUM: float = 4096.0


## The verdict on one surface of one mesh.
class Report:
	extends RefCounted

	## Whether the surface is a closed orientable solid CSG will accept.
	var ok: bool = false
	## Edges used by exactly one triangle: a hole.
	var boundary_edges: int = 0
	## Edges used by three or more: a fin, or a duplicated face.
	var excess_edges: int = 0
	## Triangles with two or more coincident corners. Reported, never fatal.
	var degenerate_triangles: int = 0
	var triangle_count: int = 0
	var welded_vertex_count: int = 0
	var raw_vertex_count: int = 0

	## A one-line explanation naming what is wrong and what it will cost.
	func summary() -> String:
		if ok:
			return (
				"closed solid: %d triangles, %d vertices welded from %d"
				% [triangle_count, welded_vertex_count, raw_vertex_count]
			)
		var parts := PackedStringArray()
		if boundary_edges > 0:
			parts.push_back("%d boundary edges (holes)" % boundary_edges)
		if excess_edges > 0:
			parts.push_back("%d edges shared by 3+ faces (fins or duplicate faces)" % excess_edges)
		if parts.is_empty():
			parts.push_back("no geometry")
		return (
			"NOT a closed solid: %s. Godot's CSG will discard this operand "
			+ "silently and bake the rest of the tree without it."
		) % ", ".join(parts)


## Checks surface [param surface] of [param mesh].
static func check_surface(mesh: Mesh, surface: int = 0) -> Report:
	var report := Report.new()
	if mesh == null or surface < 0 or surface >= mesh.get_surface_count():
		return report
	var arrays: Array = mesh.surface_get_arrays(surface)
	if arrays.is_empty():
		return report
	return check_arrays(arrays)


## Checks a raw surface array set, so a caller can validate geometry it has built
## but not yet committed to a [Mesh].
static func check_arrays(arrays: Array) -> Report:
	var report := Report.new()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return report
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		# An unindexed surface is a flat triangle soup; every vertex is its own
		# index and the weld below is what recovers the topology.
		idx = PackedInt32Array()
		idx.resize(verts.size())
		for i: int in verts.size():
			idx[i] = i

	report.raw_vertex_count = verts.size()
	report.triangle_count = idx.size() / 3

	var weld := _weld_by_position(verts)
	report.welded_vertex_count = _distinct_count(weld)

	# Edge use counts, keyed on the welded endpoint pair with the lower index
	# first so that the two directions of one edge are the same key.
	var use: Dictionary = {}
	for t: int in report.triangle_count:
		var a := weld[idx[t * 3]]
		var b := weld[idx[t * 3 + 1]]
		var c := weld[idx[t * 3 + 2]]
		if a == b or b == c or a == c:
			# A sliver with two corners welded together contributes no surface
			# and no boundary. SphereMesh ships 128 of these at its poles.
			report.degenerate_triangles += 1
			continue
		for e: Vector2i in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
			var key := Vector2i(mini(e.x, e.y), maxi(e.x, e.y))
			use[key] = int(use.get(key, 0)) + 1

	for key: Vector2i in use:
		var n := int(use[key])
		if n == 1:
			report.boundary_edges += 1
		elif n > 2:
			report.excess_edges += 1

	report.ok = (
		report.boundary_edges == 0 and report.excess_edges == 0 and not use.is_empty()
	)
	return report


## Checks every surface of [param mesh]. A multi-surface mesh is a solid only if
## all of its surfaces are.
static func check_mesh(mesh: Mesh) -> Report:
	if mesh == null or mesh.get_surface_count() == 0:
		return Report.new()
	var combined := check_surface(mesh, 0)
	for i: int in range(1, mesh.get_surface_count()):
		var r := check_surface(mesh, i)
		combined.ok = combined.ok and r.ok
		combined.boundary_edges += r.boundary_edges
		combined.excess_edges += r.excess_edges
		combined.degenerate_triangles += r.degenerate_triangles
		combined.triangle_count += r.triangle_count
		combined.raw_vertex_count += r.raw_vertex_count
	return combined


## Checks [param mesh] and pushes an error naming [param label] when it fails.
##
## The gate the bake calls. Returns whether the operand may be used, so a caller
## reads as [code]if not ManifoldChecker.require(m, path): return[/code].
static func require(mesh: Mesh, label: String) -> bool:
	var report := check_mesh(mesh)
	if report.ok:
		return true
	push_error("Static Volume operand '%s' is not usable: %s" % [label, report.summary()])
	return false


## Maps each vertex to an id shared by every vertex at the same quantised
## position, which is the weld Manifold performs internally.
static func _weld_by_position(verts: PackedVector3Array) -> PackedInt32Array:
	var key_to_id: Dictionary = {}
	var out := PackedInt32Array()
	out.resize(verts.size())
	for i: int in verts.size():
		var p := verts[i]
		var k := Vector3i(
			roundi(p.x * WELD_QUANTUM), roundi(p.y * WELD_QUANTUM), roundi(p.z * WELD_QUANTUM)
		)
		if not key_to_id.has(k):
			key_to_id[k] = key_to_id.size()
		out[i] = int(key_to_id[k])
	return out


static func _distinct_count(weld: PackedInt32Array) -> int:
	var seen: Dictionary = {}
	for v: int in weld:
		seen[v] = true
	return seen.size()
