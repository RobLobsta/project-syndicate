class_name IslandDetacher
extends RefCounted
## Turns a severed island into an independent [RigidBody3D], per
## [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §6.
##
## This is the second half of detachment. [DetachmentSolver] decides which parts
## stopped being attached and takes them out of the [ChassisGraph];
## [DetachmentScheduler] announces them through [member
## DetachmentScheduler.island_sink]; and this converts what left into something
## the player can watch fall over. The split is deliberate — topology is
## authoritative and simulated, debris is a consequence, and an island is
## correctly severed whether or not a body is ever spawned for it.
##
## Architectural Invariant I-1 survives detachment intact (§6.1): the debris body
## takes the Assembly's authored collider primitives and nothing else.
##
## [b]Amendments to §6.[/b] Three, each recorded in the document:
##
## 1. [DebrisPool] and [DebrisReaper] are instances passed in rather than
##    globals. CLAUDE.md §4 freezes the autoload list at eight.
## 2. The graph writes §6 performs — [code]graph.alive[slot] = 0[/code] — are
##    already done by the time this runs. §5.3's [method ChassisGraph.remove_node]
##    is what severs an island, and doing it twice would be a second owner of the
##    one fact this whole subsystem turns on. This asserts it instead.
## 3. Colliders are re-registered rather than moved; see
##    [method AssemblyRuntime.detach_colliders_to] for why the nodes cannot
##    migrate.
##
## §6's [code]detach_visual_to[/code] is absent because no Assembly has meshes
## yet: [code]docs/EXTENSION_PIPELINE.md[/code] §9 owns their spawn, and inventing
## it here would pre-empt the asset pipeline (CLAUDE.md §10 rule 13).

## §6. How long a debris body survives before the reaper returns it to the pool.
const DEBRIS_LIFETIME_S: float = 22.0
## Islands smaller than this get no body at all.
const DEBRIS_MIN_PARTS_FOR_BODY: int = 1


## Spawns a debris body for [param island], a set of slots [DetachmentSolver] has
## already removed from [param runtime]'s graph. Returns it, or [code]null[/code]
## when the island carries nothing worth a body.
##
## The island's mass properties are solved about its own centre of mass and the
## colliders are rebased onto it, so the body's [member RigidBody3D.center_of_mass]
## is the origin. Doing it the other way — leaving the shapes in assembly-local
## space and offsetting the centre of mass — would put every debris body's origin
## at the Assembly it came from, and a panel shed at the far end of a hull would
## rotate about a point several metres outside itself.
static func detach(
	runtime: AssemblyRuntime, island: PackedByteArray, pool: DebrisPool
) -> DebrisBodyRef:
	assert(runtime != null, "island detach against a null runtime")
	assert(pool != null, "island detach with no debris pool")

	# §6's aggregation, over the slots that actually carry a state. A slot in the
	# island with none is a bug elsewhere, but skipping it keeps the centre of
	# mass finite rather than turning that bug into a NaN transform on a body.
	var carried := PackedByteArray()
	var total_mass := 0.0
	var weighted := Vector3.ZERO
	for s in island:
		var slot := int(s)
		var st := runtime.state(slot)
		if st == null:
			push_error(
				"IslandDetacher: slot %d of assembly %d has no state"
				% [slot, runtime.assembly_id]
			)
			continue
		assert(
			not runtime.graph.is_alive(slot),
			"slot %d is still live in the graph; §5.3 severs before §6 spawns" % slot
		)
		var def := PartRegistry.definition(st.part_def_id)
		var p := MassSolver.part_com_local(st, def)
		total_mass += def.mass_kg
		weighted += p * def.mass_kg
		carried.append(slot)
	# §6's minimum, applied to the parts that resolved rather than to the slots
	# that were asked for. Testing the argument instead would be a second owner of
	# the same rule, and with the minimum at one the two agree — so neither would
	# be load-bearing and either could be deleted without a test noticing.
	if carried.size() < DEBRIS_MIN_PARTS_FOR_BODY:
		return null
	var island_com_local := weighted / maxf(total_mass, MassSolver.MASS_FLOOR_KG)

	var body := pool.acquire()
	body.source_assembly_id = runtime.assembly_id
	body.slots = carried
	for s in carried:
		var slot := int(s)
		runtime.states[slot].flags |= PartFlags.FLAG_DETACHED
		runtime.detach_colliders_to(body, slot, island_com_local)

	var mp := MassSolver.MassProperties.new()
	mp.assembly_id = runtime.assembly_id
	mp.total_mass = total_mass
	# Already re-centred: the colliders were rebased onto the island centre of
	# mass as they were registered.
	mp.com_local = Vector3.ZERO
	mp.inertia_diag = InertiaSolver.island_inertia(runtime.states, carried, island_com_local)
	MassSolver.apply_mass_properties(body, mp)

	# Transform after shapes, never before. A body given its transform while it
	# is still empty keeps the broadphase entry it had with no geometry, and every
	# subsequent query against it returns nothing — a debris body nothing can hit
	# and nothing collides with, which reads exactly like debris that was never
	# spawned.
	body.global_transform = (
		runtime.body.global_transform * Transform3D(Basis(), island_com_local)
	)

	# §6, and §11 invariant 8. The tangential term is what separates this from a
	# naive detachment: without it a panel shorn off a spinning Assembly drops
	# straight down while the Assembly rotates out from under it.
	var r := runtime.body.global_transform.basis * island_com_local
	body.linear_velocity = (
		runtime.body.linear_velocity + runtime.body.angular_velocity.cross(r)
	)
	body.angular_velocity = runtime.body.angular_velocity

	pool.reaper.schedule(body, DEBRIS_LIFETIME_S)
	EventBus.island_detached.emit(runtime.assembly_id, carried, body.get_instance_id())
	return body
