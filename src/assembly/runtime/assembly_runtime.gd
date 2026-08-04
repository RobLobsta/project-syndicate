class_name AssemblyRuntime
extends Node3D
## One Assembly in a match: its single rigid body, its collision geometry, its
## per-part state, and its Chassis Graph. The node structure is
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §2.
##
## [codeblock]
## AssemblyRuntime      (this node)
## ├── ChassisBody      (ChassisBodyRef)   the ONLY physics body
## │   ├── shape_s000_p0 (CollisionShape3D)
## │   ├── shape_s000_p1 (CollisionShape3D)
## │   ├── ...
## │   └── MotiveProbes (Node3D)           ShapeCast3D per Motive Assembly
## ├── VisualRoot       (Node3D)           interpolated; never a physics parent
## └── AudioRoot        (Node3D)
## [/codeblock]
##
## [b]Amendment to §2.[/b] The document places the shapes under a
## [code]ColliderRoot[/code] node inside the body. Godot registers a
## [CollisionShape3D] only when it is a [i]direct[/i] child of a
## [CollisionObject3D] — an intervening [Node3D] leaves it silently inert, with
## no error and no shape on the body — so the shapes are direct children of
## [code]ChassisBody[/code] and [code]ColliderRoot[/code] is gone. This is the
## worst class of failure for Architectural Invariant I-1: an Assembly with no
## collision geometry looks perfectly healthy until nothing can be shot.
## [code]MotiveProbes[/code] stays, because a [ShapeCast3D] is not a shape owner
## and works anywhere in the tree.
##
## Architectural Invariant I-1 in full: every shape here comes from an authored
## [ColliderPrimitiveDef] and nothing else, colliders never change with damage
## state or LOD, and no node under [member visual_root] is ever a physics parent.
## [method visual_decoupling_violations] checks the second half at spawn.
##
## Architectural Invariant I-4: no [code]_process[/code] and no
## [code]_physics_process[/code] here. Mass is recomputed by
## [MassRecomputeScheduler] on the events of §4.1; the visual transform is
## written by [AssemblyInterpolator]; this node holds the structure they act on.

const MAX: int = SyndicateConstants.MAX_PARTS_PER_ASSEMBLY
const INVALID: int = SyndicateConstants.INVALID_SLOT

## Probe sphere radius as a fraction of the part's contact radius (doc 05 §6.1).
## A shape cast rather than a ray: a ray through the contact centre drops into
## the gaps between ground triangles and off the edges of Static Volumes, and a
## sphere this size cannot.
const PROBE_RADIUS_RATIO: float = 0.85

## The rolling direction in a Motive Assembly's own local space, before its
## placement orientation is applied. A track's road stations are distributed
## along it (doc 05 §14.1) and it is the axis the authored footprints are long
## on: `mot.tracked.short_bogie.t2` is eight cells here and three across.
const ROLLING_AXIS_LOCAL: Vector3 = Vector3.RIGHT

## Subsystem tag gating the interpolator. A dedicated server disables it and no
## interpolator is constructed at all — §9.2 of doc 12 gates at construction, not
## per frame.
const TAG_INTERPOLATOR: StringName = &"assembly_interpolator"

## Subsystem tag gating the part meshes (doc 12 §9.2). A dedicated server leaves
## every [member visual_root] empty and builds no [ArrayMesh] at all — nothing
## simulated reads a mesh, which is Architectural Invariant I-1 stated as a
## capability rather than as a prohibition.
const TAG_PART_VISUAL: StringName = &"part_visual"

## Identifies this Assembly in every signal it takes part in.
##
## Stored on the body rather than duplicated here: a physics query hands back a
## [ChassisBodyRef] and nothing else, so the body has to know its own id, and two
## copies of it are two chances to disagree.
var assembly_id: int:
	get:
		return body.assembly_id
	set(value):
		body.assembly_id = value

var body: ChassisBodyRef = null
var motive_probes: Node3D = null
## Sibling of [member body], not a child of it (§11 invariant 2).
var visual_root: Node3D = null
var audio_root: Node3D = null
var interpolator: AssemblyInterpolator = null

## Slot -> its mutable state, or null for a free slot. Flat and indexed by slot,
## so lookup is one index and iteration is cache-coherent.
var states: Array[PartInstanceState] = []
var graph: ChassisGraph = null

## Last properties applied to [member body]. Read by the suspension retune of
## §6.4 and by the stability metrics of §5.1; written only by
## [method apply_mass_properties].
var mass_properties: MassSolver.MassProperties = null

## Shape index -> the [CollisionShape3D] holding it. The array index is the
## body's shape index, which holds because shapes are only ever appended.
var _shapes: Array[CollisionShape3D] = []

## Slot -> its suspension probes, fore to aft. Only Motive Assemblies appear,
## and a rotary one appears with an empty list: a disc touches nothing.
var _probes: Dictionary = {}

## Slot -> its [MeshInstance3D] under [member visual_root]. Empty on a dedicated
## server, where the [code]part_visual[/code] tag is off and nothing is built.
var _visuals: Dictionary = {}


func _init() -> void:
	states.resize(MAX)
	graph = ChassisGraph.new()

	body = ChassisBodyRef.new()
	body.name = "ChassisBody"
	body.collision_layer = CollisionLayers.LAYER_ASSEMBLY_HULL
	body.collision_mask = CollisionLayers.MASK_ASSEMBLY_HULL
	add_child(body)

	motive_probes = Node3D.new()
	motive_probes.name = "MotiveProbes"
	body.add_child(motive_probes)

	visual_root = Node3D.new()
	visual_root.name = "VisualRoot"
	add_child(visual_root)

	audio_root = Node3D.new()
	audio_root.name = "AudioRoot"
	add_child(audio_root)

	if SubsystemGate.is_enabled(TAG_INTERPOLATOR):
		interpolator = AssemblyInterpolator.new()
		interpolator.name = "Interpolator"
		interpolator.body = body
		interpolator.visual_root = visual_root
		add_child(interpolator)


## Takes over a validated [BuildContext] and builds the physics geometry for
## every part it committed.
##
## This is the one seam from the build lattice into a match. The garage, the
## auto-assembler, blueprint loading, and server-side re-validation all produce a
## context through the identical [PlacementValidator] chain (CLAUDE.md §10
## rule 8), and every one of them arrives here. Nothing else may populate a
## runtime, because nothing else has been through that chain.
##
## The context's build proxies are released as part of the transfer: they exist
## to answer §7.7's interpenetration query during construction, and the real
## body's shapes replace them.
func adopt(ctx: BuildContext) -> void:
	assert(ctx != null, "adopt of a null BuildContext")
	assert(_shapes.is_empty(), "adopt into a runtime that already holds parts")
	assembly_id = ctx.assembly_id
	graph = ctx.graph
	for slot in MAX:
		states[slot] = ctx.states[slot]
	# Ascending slot order, so the shape indices — and therefore the shape-index
	# to slot map every damage query reads — are reproducible for a given
	# blueprint on the server and on every client.
	var visuals := SubsystemGate.is_enabled(TAG_PART_VISUAL)
	for slot in MAX:
		if states[slot] != null:
			attach_part(slot)
			if visuals:
				spawn_visual(slot)
		ctx.despawn_proxy(slot)
	_assert_visual_decoupling()


## Builds [param slot]'s authored collider primitives onto the chassis body.
##
## Architectural Invariant I-1: the primitives are the part's [ColliderProfile]
## and nothing else. They are the same geometry the garage's build proxy used,
## which is what makes the placement the player saw accepted the placement the
## match simulates.
func attach_part(slot: int) -> void:
	var st := state(slot)
	if st == null:
		push_error("AssemblyRuntime: attach of empty slot %d" % slot)
		return
	var def := PartRegistry.definition(st.part_def_id)
	var profile := def.collider_profile
	if profile == null or profile.primitives.is_empty():
		push_warning(
			"AssemblyRuntime: '%s' at slot %d has no collider primitives"
			% [def.part_key, slot]
		)
		return

	var part_xform := Transform3D(
		OrientationTable.basis_for(st.orientation_index),
		LatticeMath.cell_to_local(st.origin_cell)
	)
	var indices := PackedInt32Array()
	for p in profile.primitives.size():
		var prim: ColliderPrimitiveDef = profile.primitives[p]
		var shape := prim.build_shape()
		if shape == null:
			push_error(
				"AssemblyRuntime: primitive %d of '%s' built no shape" % [p, def.part_key]
			)
			continue
		var node := CollisionShape3D.new()
		node.name = "shape_s%03d_p%d" % [slot, p]
		node.shape = shape
		node.transform = part_xform * prim.local_transform()
		var index := _shapes.size()
		_shapes.append(node)
		indices.append(index)
		body.add_child(node)
		body.register_shape(index, slot)
	st.collider_shape_ids = indices
	_build_motive_probes(slot, def, st)


## Builds [param slot]'s display mesh under [member visual_root]. Doc 13 §9.
##
## Architectural Invariant I-1, the other half of [method attach_part]: this
## reads [member PartDefinition.visual_profile] and that reads
## [member PartDefinition.collider_profile], and the two functions share no line.
## They can be read side by side and there is no point at which one influences
## the other — which is what makes "the simulation reads only the physics
## geometry" a checkable claim rather than an intention.
##
## The node is a [MeshInstance3D] and therefore not a [CollisionObject3D], so it
## cannot carry a layer or a mask at all. [method visual_decoupling_violations]
## walks the subtree after [method adopt] and is what proves that stayed true.
##
## The mesh, the material and the pose come from [PartMeshFactory], which the
## garage preview also builds its picture from. They are the same picture and one
## answer: a garage that composed the placement pose with the authored visual
## offset in the other order would show a player a build that assembles
## differently the moment they drove it.
func spawn_visual(slot: int) -> void:
	var st := state(slot)
	if st == null:
		push_error("AssemblyRuntime: visual spawn of empty slot %d" % slot)
		return
	var def := PartRegistry.definition(st.part_def_id)
	if def.visual_profile == null:
		push_warning(
			"AssemblyRuntime: '%s' at slot %d has no visual profile" % [def.part_key, slot]
		)
		return

	var node := PartMeshFactory.build(
		def, st.integrity_band, st.origin_cell, st.orientation_index
	)
	if node == null:
		return
	node.name = "part_s%03d" % slot
	visual_root.add_child(node)
	st.visual_node_path = visual_root.get_path_to(node)
	_visuals[slot] = node


## [param slot]'s display mesh, or null when it has none — a part spawned on a
## dedicated server, or one whose proxy could not be built.
func visual_of(slot: int) -> MeshInstance3D:
	var node: MeshInstance3D = _visuals.get(slot, null)
	if node != null and is_instance_valid(node):
		return node
	return null


func _set_visual_visible(slot: int, shown: bool) -> void:
	var node := visual_of(slot)
	if node != null:
		node.visible = shown


## Takes [param slot]'s collision geometry out of the simulation.
##
## The shapes are disabled rather than removed, and that is load-bearing.
## Removing a shape renumbers every later index on the body, which would
## invalidate the shape-index to slot map of doc 08 §5.4 for every part placed
## after the one that died — turning one destroyed panel into mis-attributed hits
## across the whole Assembly. Indices are assigned once and never move.
##
## The state slot is left populated: a destroyed part is still a part, with an
## integrity of zero and a band of [code]DESTROYED[/code], until the detachment
## solver decides whether it leaves as debris.
func release_part(slot: int) -> void:
	var st := state(slot)
	if st == null:
		return
	for i in st.collider_shape_ids:
		if i >= 0 and i < _shapes.size():
			_shapes[i].disabled = true
	# A part out of the simulation stops sweeping. The probes are disabled rather
	# than freed for the same reason the shapes are: repair puts the part back,
	# and rebuilding a probe would need the placement again.
	_set_probes_enabled(slot, false)
	# The mesh goes with the shapes, and this is the one place presentation is
	# obliged to follow the simulation rather than merely permitted to. A shipped
	# part's greybox is its collider exactly (doc 13 §2.1), so a mesh left behind
	# by a disabled shape is geometry the player can see and cannot hit — which
	# reads as a round passing through armour rather than as a part being gone.
	_set_visual_visible(slot, false)


## Re-registers [param slot]'s collider primitives against the debris body
## [param target], rebased onto [param island_com_local], and takes them out of
## this Assembly's simulation. Doc 04 §6's collider transfer.
##
## [b]Amendment to doc 04 §6.[/b] §6 speaks of transferring the colliders, and
## the nodes cannot move. A body's shape indices are assignment order, so
## removing one renumbers every later index and repoints the shape-index to slot
## map of doc 08 §5.4 for every part placed after the island — one severed panel
## turning into mis-attributed hits across the rest of the hull, which is the
## same failure [method release_part] exists to avoid. The primitives are instead
## registered on the debris body — the [i]same[/i] [Shape3D] resources, shared
## rather than rebuilt, which is what §6.1 means by reusing the authored
## primitives — and this body's copies are disabled where they stand.
##
## The rebase is a pure translation: the debris body's frame is this Assembly's
## translated onto the island centre of mass, so the shape keeps its orientation
## and loses the offset. [IslandDetacher] sets the body's transform afterwards,
## which is what makes that true.
func detach_colliders_to(
	target: DebrisBodyRef, slot: int, island_com_local: Vector3
) -> void:
	var st := state(slot)
	if st == null:
		push_error("AssemblyRuntime: collider detach of empty slot %d" % slot)
		return
	for i in st.collider_shape_ids:
		if i < 0 or i >= _shapes.size():
			continue
		var source := _shapes[i]
		target.adopt_shape(
			source.shape,
			Transform3D(source.transform.basis, source.transform.origin - island_com_local)
		)
		source.disabled = true
	# The island's Motive Assemblies are debris now. Debris does not steer, and a
	# probe still sweeping from a departed part would hand the motion layer a
	# contact for a wheel that is no longer attached.
	_set_probes_enabled(slot, false)
	# Same reason as [method release_part], and more visible: the island's shapes
	# are on the debris body now and moving away, so a mesh left on this hull is
	# a part that is simultaneously here and rolling down the road.
	_set_visual_visible(slot, false)


## Re-enables geometry that [method release_part] disabled, for the repair path
## of doc 08 §11.
func restore_part(slot: int) -> void:
	var st := state(slot)
	if st == null:
		return
	for i in st.collider_shape_ids:
		if i >= 0 and i < _shapes.size():
			_shapes[i].disabled = false
	_set_probes_enabled(slot, true)
	_set_visual_visible(slot, true)


## Builds [param slot]'s suspension probes under [code]MotiveProbes[/code], one
## per ground contact the part will carry. Doc 05 §6.1, and §14.1 for a track.
##
## A probe is not collision geometry and does not touch Architectural Invariant
## I-1: a [ShapeCast3D] is a query, not a shape owner, and it reads the world
## rather than presenting anything to it. It lives inside [member body] so that
## its origin and its downward sweep follow the chassis — suspension travel is
## along the chassis's own down, not along world down, which is the difference
## between a banked Assembly's springs working and its springs unloading.
##
## The mask is Ground Arrays and Static Volumes only (§11 invariant 5). Excluding
## [constant CollisionLayers.LAYER_ASSEMBLY_HULL] and
## [constant CollisionLayers.LAYER_DEBRIS] removes an entire family of exploits —
## climbing an opponent — and one of instabilities, two Assemblies' suspensions
## pushing against each other.
func _build_motive_probes(slot: int, def: PartDefinition, st: PartInstanceState) -> void:
	if def.part_class != PartEnums.PartClass.MOTIVE_ASSEMBLY:
		return
	var profile := def.motive_profile
	var nodes: Array[ShapeCast3D] = []
	_probes[slot] = nodes
	# A disc is the one family with no ground contact, so it gets no probe and
	# the empty list above is the answer, not a missing entry.
	if profile.locomotion_mode() == PartEnums.LocomotionMode.ROTARY:
		return

	var part_local := MassSolver.part_com_local(st, def)
	var origins := PackedVector3Array([part_local])
	# A wheel's or a station's sweep is its suspension travel; a limb's is its
	# leg. Rule 21 requires every `suspension_*` field on an ambulatory row to be
	# zero — a leg is a spring-loaded inverted pendulum, not a strut — so reading
	# the suspension reach on one gives a zero-length cast that finds nothing,
	# the contact never grounds, the foot is never planted, and the Assembly
	# stands still with a perfectly healthy-looking gait clock running.
	var reach := profile.suspension_rest_length_m + profile.suspension_travel_limit_m
	if profile.limb_profile != null:
		origins = PackedVector3Array([MotiveSystem.hip_local_of(def, st)])
		reach = profile.limb_profile.leg_length_m
	elif profile.track_profile != null:
		origins = TrackSolver.station_positions(
			profile.track_profile,
			part_local,
			OrientationTable.basis_for(st.orientation_index) * ROLLING_AXIS_LOCAL
		)

	for station: int in origins.size():
		var probe := ShapeCast3D.new()
		probe.name = "probe_s%03d_%d" % [slot, station]
		var sphere := SphereShape3D.new()
		sphere.radius = profile.contact_radius_m * PROBE_RADIUS_RATIO
		probe.shape = sphere
		probe.position = origins[station]
		probe.target_position = Vector3(0.0, -reach, 0.0)
		probe.collision_mask = CollisionLayers.MASK_GROUND | CollisionLayers.MASK_STATIC_VOLUME
		probe.max_results = 1
		probe.enabled = true
		nodes.append(probe)
		motive_probes.add_child(probe)


## [param slot]'s suspension probes, fore to aft. Empty for everything that is
## not a Motive Assembly, and for a rotary one.
func motive_probes_of(slot: int) -> Array[ShapeCast3D]:
	var nodes: Array[ShapeCast3D] = _probes.get(slot, [] as Array[ShapeCast3D])
	return nodes


func _set_probes_enabled(slot: int, enabled: bool) -> void:
	for probe: ShapeCast3D in motive_probes_of(slot):
		probe.enabled = enabled


func state(slot: int) -> PartInstanceState:
	if slot < 0 or slot >= MAX:
		return null
	return states[slot]


func definition_at(slot: int) -> PartDefinition:
	var st := state(slot)
	if st == null:
		return null
	return PartRegistry.definition(st.part_def_id)


## World position of [param slot]'s centre of mass.
##
## The one place the answer to "where is that part" lives. A blast epicentre, a
## muzzle origin, and a rotor's thrust application point are all this, and having
## three callers derive it three ways is how they end up disagreeing by the
## quarter-cell that an even-sized footprint's centre sits at.
##
## Falls back to the body origin for a slot with no state, because every caller
## is asking in order to place something in the world and none of them has a
## sensible thing to do with a failure.
func part_world_position(slot: int) -> Vector3:
	var st := state(slot)
	if st == null:
		return body.global_position
	return body.global_transform * MassSolver.part_com_local(st, PartRegistry.definition(st.part_def_id))


## §3.5. Writes solved mass properties onto the body and keeps them for the
## systems that read them between recomputes.
func apply_mass_properties(mp: MassSolver.MassProperties) -> void:
	mass_properties = mp
	MassSolver.apply_mass_properties(body, mp)
	_set_simulated(mp.part_count > 0)


## §3.7. A body with no live parts left is not simulated.
##
## §3.5 floors the mass at one kilogramme and the inertia at one, because the
## engine refuses a zero mass outright and reads a zero inertia as "derive it
## from the collision shapes" — the coupling Architectural Invariant I-1 forbids.
## Those floors are the engine's requirement and they are not a claim about the
## world: an Assembly that has lost every part is not a one-kilogramme object, it
## is nothing at all, and leaving it dynamic hands the solver a hull-sized
## collider on a gramme of mass. Anything that so much as brushes it launches it,
## which is precisely what doc 11 §16.2 says must not happen — the hulk is the
## visible record of the fight and it stays where it fell.
##
## [b]This is not §3.6's rule and does not weaken it.[/b] §3.6 stops the motion
## layer on a terminated Assembly and says explicitly that it is not "freeze the
## body": the wreck still falls, still rolls, still takes impacts, and still
## tumbles under §3.4. That remains true of a terminated Assembly with parts on
## it. This fires one condition further along — when the last part has gone — and
## by then there is no motion left to preserve, because there is no mass to carry
## it and, once the islands have detached, no live geometry either.
##
## [b]The ordering is what makes it safe.[/b] The solve that lands with no parts
## is the one triggered by the last island detaching, and doc 04 §6 has already
## read this body's linear and angular velocity to give the debris the [code]v +
## ω × r[/code] it left with. Freezing before that would drop every fragment
## straight down.
##
## Reversible, because doc 08 §10's repair path is not written yet and a latent
## one-way door is how it arrives broken: a solve that finds parts again puts the
## body back into the simulation.
func _set_simulated(simulated: bool) -> void:
	var frozen := not simulated
	if body.freeze == frozen:
		return
	if frozen:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = frozen


## Total shapes ever added to the body, disabled or not. Diagnostics and tests.
func shape_count() -> int:
	return _shapes.size()


## Node paths under [member visual_root] that violate §11 invariant 2, in tree
## order. Empty is the only acceptable answer.
##
## Returned rather than asserted so that a test can inspect the list, and so that
## the walk itself is not compiled out of a release build along with the assert
## that consumes it.
func visual_decoupling_violations() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_violations(visual_root, out)
	return out


func _collect_violations(node: Node, out: PackedStringArray) -> void:
	for child in node.get_children():
		if child is CollisionObject3D:
			var co := child as CollisionObject3D
			out.append(
				(
					"%s is a CollisionObject3D under VisualRoot (layer %d, mask %d)"
					% [get_path_to(child), co.collision_layer, co.collision_mask]
				)
			)
		elif child is CollisionShape3D:
			out.append("%s is a CollisionShape3D under VisualRoot" % get_path_to(child))
		_collect_violations(child, out)


## §2. Walks the visual subtree in debug builds; a violation is a programming
## error, not a recoverable condition, because it means physics and presentation
## have been coupled and every guarantee in Architectural Invariant I-1 is void.
func _assert_visual_decoupling() -> void:
	var violations := visual_decoupling_violations()
	assert(
		violations.is_empty(),
		"Architectural Invariant I-1: %s" % "; ".join(violations)
	)
