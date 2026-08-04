class_name PartMeshFactory
extends RefCounted
## Builds the [MeshInstance3D] that displays one placed part, for the two places
## that display one: the match, through [method AssemblyRuntime.spawn_visual],
## and the garage preview.
##
## It exists because those two are the same picture and must not be two answers.
## A garage that composed the placement pose with the authored visual offset in
## the other order — the fixture trap [code]CHANGE_LOG.md[/code] records for the
## collider path, invisible at orientation 0 — would show a player a build that
## assembles differently the moment they drive it.
##
## [b]It reads [member PartDefinition.visual_profile] and nothing else.[/b]
## Architectural Invariant I-1: the collider profile is read by
## [method AssemblyRuntime.attach_part] and by [method BuildContext.spawn_proxy],
## and this function shares no line with either. The two can be read side by side
## and there is no point at which one influences the other.
##
## The node it returns is unnamed and unparented. Naming is the caller's, because
## the two callers name their nodes differently — the match by slot, the garage
## by cell — and neither convention belongs in here.


## The display node for [param def] placed at [param origin_cell] in
## [param orientation_index], showing [param band]'s mesh.
##
## Returns null when the part has no visual profile at all, or when its profile
## resolves to no mesh — a part mid-promotion through doc 13's stages. Both are
## the caller's to report: the match warns, and the garage draws nothing rather
## than bringing down the screen a player is building on.
static func build(
	def: PartDefinition,
	band: PartEnums.IntegrityBand,
	origin_cell: Vector3i,
	orientation_index: int
) -> MeshInstance3D:
	var vp := def.visual_profile
	if vp == null:
		return null

	var mesh: Mesh = vp.mesh_for_band(band)
	var material: Material = null
	if mesh == null:
		# STAGE_PROXY, which is every shipped part today: the mesh is generated
		# from the primitive list, or mirrored from the collider when — as the
		# whole shipped set does — the part authors none.
		mesh = ProxyMeshCache.get_or_build(def)
		material = GreyboxMaterial.for_class(def.part_class, vp.proxy_tint)
	elif vp.stage == PartVisualProfile.Stage.BLOCKOUT:
		material = GreyboxMaterial.for_class(def.part_class, vp.proxy_tint)
	if mesh == null:
		return null

	var node := MeshInstance3D.new()
	node.mesh = mesh
	if material != null:
		node.material_override = material
	node.transform = pose(vp, origin_cell, orientation_index)
	node.layers = RenderLayers.LAYER_ASSEMBLY_VISUAL
	node.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if vp.casts_shadow
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return node


## The part's placement pose composed with its authored visual offset, in that
## order.
##
## Composing them the other way round would rotate the offset by the part's
## orientation twice. It is invisible at orientation 0 and wrong at every other
## one, which is exactly the shape of fixture error that survives a test suite.
static func pose(
	vp: PartVisualProfile, origin_cell: Vector3i, orientation_index: int
) -> Transform3D:
	return (
		Transform3D(
			OrientationTable.basis_for(orientation_index),
			LatticeMath.cell_to_local(origin_cell)
		)
		* Transform3D(Basis().scaled(vp.visual_scale), vp.visual_offset_m)
	)


## [method pose] lowered by [param droop_m] metres of unconsumed suspension
## travel. Doc 05 §16.1.
##
## The translation is applied in the [i]chassis[/i] frame rather than the part's,
## which is why it is added to the origin rather than composed onto the right of
## the placement pose: a wheel hangs down the hull's own down axis, not down its
## own, and the two differ for every Motive Assembly that is not mounted upright.
##
## The part's placement is untouched — this returns where the mesh goes and
## nothing reads it back. Architectural Invariant I-1 fixes the collider from
## placement to destruction, and this function is the reason presentation can
## move without it.
static func contact_pose(
	vp: PartVisualProfile, origin_cell: Vector3i, orientation_index: int, droop_m: float
) -> Transform3D:
	var t := pose(vp, origin_cell, orientation_index)
	t.origin += Vector3.DOWN * droop_m
	return t


## [method pose] pivoted about [param hip_local] so that the part's leg axis
## points at [param foot_local]. Doc 05 §16.3.
##
## Both points are in the chassis frame, which is the frame the returned
## transform lives in. The leg axis is the part's own local down under its
## placement orientation, because [member LimbProfile.hip_offset_m] puts the hip
## above everything the limb occupies — so a limb drawn along that axis is doc 05
## §13.1's virtual leg drawn as what it is, rather than an inverse-kinematics
## chain §13.8 deliberately does not specify.
##
## A foot at the hip has no direction to point at and leaves the rest pose alone.
static func limb_pose(
	vp: PartVisualProfile,
	origin_cell: Vector3i,
	orientation_index: int,
	hip_local: Vector3,
	foot_local: Vector3
) -> Transform3D:
	var rest := pose(vp, origin_cell, orientation_index)
	var to_foot := foot_local - hip_local
	if to_foot.length() < SyndicateConstants.EPSILON_LINEAR:
		return rest
	var leg_axis := OrientationTable.basis_for(orientation_index) * Vector3.DOWN
	var turn := Basis(Quaternion(leg_axis.normalized(), to_foot.normalized()))
	return Transform3D(turn * rest.basis, hip_local + turn * (rest.origin - hip_local))
