class_name ProxyMeshBuilder
extends RefCounted
## Builds a stage-PROXY display mesh from a part's primitive list, owned by
## [code]docs/EXTENSION_PIPELINE.md[/code] §2.1.
##
## Architectural Invariant I-1: this produces a [Mesh] and never a [Shape3D]. It
## is the mirror image of [method ColliderPrimitiveDef.build_shape] and shares no
## code with it, deliberately — §2.1 keeps [ProxyPrimitiveDef] and
## [ColliderPrimitiveDef] as separate types so that an art edit can never move a
## hitbox, and merging the two builders would put back exactly the coupling that
## separation exists to prevent.
##
## [b]The mirroring default is what actually runs today.[/b] §2.1 falls back to
## generating the proxy primitives from the [ColliderProfile] when a part authors
## none, and
## [code]tests/integration/test_part_registry_data.gd[/code] asserts that every
## shipped part leaves [member PartVisualProfile.proxy_primitives] empty. So for
## the whole shipped set the greybox is the collider, exactly, and what a player
## sees is what a round hits. That is a property worth keeping: the first time
## visual and collider diverge should be a deliberate STAGE_FINAL decision that
## §7's validator measures, not an accident nobody can see.

## Radial resolution of the round primitives, §2.1's figure.
##
## Godot's own defaults are 64 radial segments on a [CylinderMesh], which is
## five times the triangles for geometry that exists to be replaced. At this
## count a 0.5 m contact disc is still round at the distance §13 of doc 11 puts
## the camera at.
const RADIAL_SEGMENTS: int = 12
const SPHERE_RINGS: int = 6


## The display mesh for [param def], or null if it has neither proxy primitives
## nor a collider to mirror.
##
## Callers should go through [ProxyMeshCache] rather than here: forty panels on
## one Assembly are one mesh, and this function builds a new one every call.
static func build(def: PartDefinition) -> ArrayMesh:
	if def == null:
		return null
	var prims: Array[ProxyPrimitiveDef] = []
	if def.visual_profile != null:
		prims = def.visual_profile.proxy_primitives
	if prims.is_empty():
		prims = mirror_collider(def.collider_profile)
	if prims.is_empty():
		push_warning(
			"ProxyMeshBuilder: '%s' has no proxy primitives and no collider to mirror"
			% def.part_key
		)
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var appended := 0
	for p: ProxyPrimitiveDef in prims:
		var sub := primitive_mesh(p)
		if sub == null:
			push_error(
				"ProxyMeshBuilder: primitive of '%s' built no mesh" % def.part_key
			)
			continue
		st.append_from(sub, 0, p.local_transform())
		appended += 1
	if appended == 0:
		return null
	st.generate_normals()
	st.index()
	return st.commit()


## §2.1's fallback: a proxy primitive per collider primitive, field for field.
##
## Returns new resources rather than the collider's own, because a
## [ColliderPrimitiveDef] is shared immutable data (Invariant I-11) and handing
## it to the visual path would be one edit away from an art change moving a
## hitbox.
static func mirror_collider(cp: ColliderProfile) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	if cp == null:
		return out
	for prim: ColliderPrimitiveDef in cp.primitives:
		var d := ProxyPrimitiveDef.new()
		d.kind = prim.kind
		d.half_extents_m = prim.half_extents_m
		d.radius_m = prim.radius_m
		d.height_m = prim.height_m
		d.local_offset_m = prim.local_offset_m
		d.local_basis_euler_deg = prim.local_basis_euler_deg
		out.append(d)
	return out


## One primitive as a mesh, at §2.1's radial resolution.
##
## [method ProxyPrimitiveDef.build_mesh] builds the same shapes at Godot's
## defaults and is what a caller outside the proxy pipeline should use. This
## applies the segment counts because the count is a property of the greybox
## stage rather than of the primitive.
static func primitive_mesh(p: ProxyPrimitiveDef) -> Mesh:
	var mesh := p.build_mesh()
	if mesh is CylinderMesh:
		var cyl := mesh as CylinderMesh
		cyl.radial_segments = RADIAL_SEGMENTS
		cyl.rings = 0
	elif mesh is CapsuleMesh:
		var cap := mesh as CapsuleMesh
		cap.radial_segments = RADIAL_SEGMENTS
		cap.rings = SPHERE_RINGS
	elif mesh is SphereMesh:
		var sph := mesh as SphereMesh
		sph.radial_segments = RADIAL_SEGMENTS
		sph.rings = SPHERE_RINGS
	return mesh
