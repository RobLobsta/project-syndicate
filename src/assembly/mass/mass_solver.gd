class_name MassSolver
extends RefCounted
## Total mass, centre of mass, and inertia tensor of one Assembly, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §3.
##
## Architectural Invariant I-3: the whole Assembly is one [RigidBody3D], so
## "mass properties" is three numbers on one body rather than a per-part physics
## state. Losing a part is a change to those three numbers and to nothing else,
## which is what makes §5's centre-of-mass shift a gameplay mechanic instead of a
## solver stability problem.
##
## Architectural Invariant I-4: nothing here polls. §4 lists the five events that
## recompute, and [MassRecomputeScheduler] is the only thing that calls in on a
## tick boundary.
##
## [b]Threading.[/b] §4.3 runs the recompute on [WorkerThreadPool]. The solver is
## therefore split in two: [method capture] snapshots the live slot set on the
## main thread, and [method compute_from] does the arithmetic against that
## snapshot and touches nothing else. See [method capture] for why.

const MAX: int = SyndicateConstants.MAX_PARTS_PER_ASSEMBLY

## Floor for the centre-of-mass division. An Assembly with no live parts has no
## centre of mass; this keeps the expression finite so callers do not each need
## an empty-Assembly branch.
const MASS_FLOOR_KG: float = 0.001

## Godot treats a zero mass or a zero inertia component as "derive it from the
## shapes", which would silently replace the solved tensor with one computed from
## collider geometry — the exact coupling Architectural Invariant I-1 forbids.
const MIN_BODY_MASS_KG: float = 1.0
const MIN_BODY_INERTIA: float = 1.0


## §3.2. Mass properties of the live parts of [param graph].
##
## The synchronous entry point, for the garage stat panel and for tests. The
## match path goes through [method capture] and [method compute_from] instead.
static func compute(states: Array[PartInstanceState], graph: ChassisGraph) -> MassProperties:
	return compute_from(capture(0, states, graph, 0))


## Snapshots the live slot set into a flat record the worker thread can own.
##
## §4.3 launches the recompute while the tick that scheduled it is still running,
## and that tick may destroy parts, sever islands, and re-parent survivors.
## Reading [member ChassisGraph.alive] and the state array from the worker would
## therefore be a data race, and its symptom — a mass figure that is wrong for
## one tick and never reproduces — is close to undiagnosable. The snapshot is at
## most 255 entries of flat integer data and costs a fraction of the tensor
## accumulation it feeds.
##
## [PartDefinition] is not copied: it is immutable after
## [code]PartRegistry._ready()[/code] (Architectural Invariant I-11), so the
## worker may read it directly.
static func capture(
	assembly_id: int, states: Array[PartInstanceState], graph: ChassisGraph, source_tick: int
) -> MassInput:
	var input := MassInput.new()
	input.assembly_id = assembly_id
	input.source_tick = source_tick
	for slot in MAX:
		if graph.alive[slot] == 0:
			continue
		var st: PartInstanceState = states[slot]
		# §3.1's predicate exactly: alive in the graph and not detached. A part
		# that has reached zero integrity but has not been resolved yet is still
		# alive here, and correctly so — the recompute that follows a destruction
		# is triggered by the scheduler after `remove_node`, never before it.
		if st == null or (st.flags & PartFlags.FLAG_DETACHED) != 0:
			continue
		input.slots.append(slot)
		input.def_ids.append(st.part_def_id)
		input.origin_cells.append(Vector3(st.origin_cell))
		input.orientations.append(st.orientation_index)
	return input


## §3.1 through §3.3 over a snapshot. Pure: no node, no signal, no shared state.
static func compute_from(input: MassInput) -> MassProperties:
	var mp := MassProperties.new()
	mp.assembly_id = input.assembly_id
	mp.source_tick = input.source_tick
	mp.part_count = input.slots.size()

	# Two passes rather than one: the parallel-axis shift of §3.3 needs the
	# Assembly centre of mass, which is not known until every part has been
	# weighed. The per-part centres are kept from the first pass so the second
	# does not recompute a basis multiply for each of them.
	var coms := PackedVector3Array()
	coms.resize(mp.part_count)
	var weighted := Vector3.ZERO
	for i in mp.part_count:
		var def := PartRegistry.definition(input.def_ids[i])
		var p := cell_com_local(
			Vector3i(input.origin_cells[i]), int(input.orientations[i]), def
		)
		coms[i] = p
		mp.total_mass += def.mass_kg
		weighted += p * def.mass_kg
	mp.com_local = weighted / maxf(mp.total_mass, MASS_FLOOR_KG)

	var acc := InertiaSolver.zero()
	for i in mp.part_count:
		var def := PartRegistry.definition(input.def_ids[i])
		acc = InertiaSolver.add(
			acc,
			InertiaSolver.part_tensor(
				def, int(input.orientations[i]), coms[i] - mp.com_local
			)
		)
	mp.inertia_full = acc
	mp.inertia_diag = InertiaSolver.diagonal_of(acc)
	return mp


## §3.2. A part's centre of mass in assembly-local metres.
static func part_com_local(st: PartInstanceState, def: PartDefinition) -> Vector3:
	return cell_com_local(st.origin_cell, st.orientation_index, def)


## [method part_com_local] against loose fields, for the snapshot path where no
## [PartInstanceState] crosses the thread boundary.
static func cell_com_local(
	origin_cell: Vector3i, orientation_index: int, def: PartDefinition
) -> Vector3:
	return (
		LatticeMath.cell_to_local(origin_cell)
		+ OrientationTable.basis_for(orientation_index) * def.com_offset_m
	)


## §3.5. Writes solved properties onto the body.
##
## [member RigidBody3D.center_of_mass] is set rather than re-origining the
## colliders: the collider transforms stay in stable assembly-local space, so
## losing a part shifts the centre of mass without touching a single shape.
static func apply_mass_properties(body: RigidBody3D, mp: MassProperties) -> void:
	body.mass = maxf(mp.total_mass, MIN_BODY_MASS_KG)
	body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	body.center_of_mass = mp.com_local
	body.inertia = Vector3(
		maxf(mp.inertia_diag.x, MIN_BODY_INERTIA),
		maxf(mp.inertia_diag.y, MIN_BODY_INERTIA),
		maxf(mp.inertia_diag.z, MIN_BODY_INERTIA)
	)


## The result of one solve. §3.2 declares it; it crosses a thread boundary, so
## like [AssemblyStats] it holds no node reference and no shared mutable state.
class MassProperties:
	extends RefCounted

	var assembly_id: int = 0
	## Tick the snapshot was taken on, so a result arriving after a newer edit
	## can be recognised as superseded rather than applied blind.
	var source_tick: int = 0
	var total_mass: float = 0.0
	var com_local: Vector3 = Vector3.ZERO
	## The full 3x3 tensor about the centre of mass, including the products of
	## inertia §3.4's coupling correction needs.
	var inertia_full: Basis = Basis()
	## The diagonal Godot accepts. Discarding the off-diagonal terms is what
	## makes §3.4 necessary.
	var inertia_diag: Vector3 = Vector3.ONE
	var part_count: int = 0


## The worker thread's whole view of an Assembly. Parallel flat arrays rather
## than an array of records: it is built and consumed once per structural change,
## and packed arrays copy across the thread boundary without allocating 255
## objects.
class MassInput:
	extends RefCounted

	var assembly_id: int = 0
	var source_tick: int = 0
	## Slot of each entry, so a caller can relate a result back to the Assembly.
	var slots: PackedByteArray = PackedByteArray()
	var def_ids: PackedInt32Array = PackedInt32Array()
	## Lattice cells held as floats because there is no packed [Vector3i] array.
	## Cell coordinates are small non-negative integers and round-trip exactly.
	var origin_cells: PackedVector3Array = PackedVector3Array()
	var orientations: PackedByteArray = PackedByteArray()
