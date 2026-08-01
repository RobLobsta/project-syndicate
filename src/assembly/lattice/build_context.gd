class_name BuildContext
extends RefCounted
## Everything one Assembly-under-construction consists of: its occupancy, its
## Chassis Graph, its per-slot state, its budget totals, and the build proxy
## colliders §7.7 queries against.
##
## The garage, the auto-assembler, blueprint loading, and server-side blueprint
## re-validation all construct one of these and hand it to the same
## [PlacementValidator] (CLAUDE.md §10 rule 8). There is no second path into the
## lattice, which is why a blueprint a client sends cannot describe a placement
## the garage would have refused.
##
## [b]Presentation is not here.[/b] §9.1 sketches [code]spawn_visual[/code] and
## [code]spawn_colliders[/code] as context calls, but its very next sentence is
## that [signal EventBusService.part_attached] is what wakes the mass solver,
## the fusion rebuild, and the stat panel, and that nothing polls. Meshes are
## therefore driven by the event (Architectural Invariant I-4) and no
## presentation hook exists here to be left unimplemented on the dedicated
## server. The build proxies below are the exception: they are physics, they are
## what §7.7 queries, and they are created here.

const MAX: int = SyndicateConstants.MAX_PARTS_PER_ASSEMBLY
const INVALID: int = SyndicateConstants.INVALID_SLOT

## Identifies this Assembly in every [EventBusService] signal it emits.
var assembly_id: int = 0
var occupancy: LatticeOccupancy = null
var graph: ChassisGraph = null
var budgets: BuildBudgetLedger = null
var shape_cache: BuildShapeCache = null
## Slot -> its mutable state, or null for a free slot. A flat array indexed by
## slot, so lookup is one index and iteration is cache-coherent.
var states: Array[PartInstanceState] = []

## Ranked mode rejects a placement that exceeds a soft limit; Sandbox commits it
## with [constant PartFlags.FLAG_STRAINED] set. See §7.8.
var enforce_hard_limits: bool = false

## Physics space holding the build proxies. [constant RID] is invalid in a
## context created without physics, in which case §7.7 is skipped — see
## [method has_physics].
var space: RID = RID()

## Per-slot proxy body, or an invalid RID when the slot has none.
var _proxy_bodies: Array[RID] = []
## True when this context created [member space] and must free it.
var _owns_space: bool = false


func _init() -> void:
	occupancy = LatticeOccupancy.new()
	graph = ChassisGraph.new()
	budgets = BuildBudgetLedger.new()
	shape_cache = BuildShapeCache.new()
	states.resize(MAX)
	_proxy_bodies.resize(MAX)
	for i in MAX:
		states[i] = null
		_proxy_bodies[i] = RID()


## A context with its own physics space, for the garage and for any caller that
## needs the collider interpenetration check of §7.7.
##
## The space is isolated from the world space: build proxies live on
## [constant CollisionLayers.LAYER_BUILD_GHOST], which no gameplay system
## queries, and putting them in their own space means a garage open behind a
## running match cannot perturb it.
static func with_physics(id: int = 0) -> BuildContext:
	var ctx := BuildContext.new()
	ctx.assembly_id = id
	ctx.space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(ctx.space, true)
	ctx._owns_space = true
	return ctx


## A context with no physics space, for the dedicated server.
##
## Server-side blueprint re-validation runs every integer check — which is every
## check that can reject a placement a client could have constructed by hand.
## §7.7 exists to catch authored primitives that protrude past their cells at a
## 15° rotation, and it is skipped here rather than paying for a physics space
## per connecting player. §12 invariant 1 permits this precisely because the
## query may only reject, never accept: skipping it cannot admit a placement the
## integer checks refused.
static func headless(id: int = 0) -> BuildContext:
	var ctx := BuildContext.new()
	ctx.assembly_id = id
	return ctx


## True when §7.7 can run in this context.
func has_physics() -> bool:
	return space.is_valid()


func state(slot: int) -> PartInstanceState:
	if slot < 0 or slot >= MAX:
		return null
	return states[slot]


func definition_at(slot: int) -> PartDefinition:
	var st := state(slot)
	if st == null:
		return null
	return PartRegistry.definition(st.part_def_id)


## Lowest free slot, or [constant INVALID] when the Assembly is full.
##
## Lowest-first rather than a bump counter: it makes the Core Module land on
## slot 0 without a special case (Architectural Invariant I-2), it keeps slot
## ids dense so the snapshot encoder's per-part records stay compact, and it is
## reproducible after an arbitrary sequence of removals.
func allocate_slot() -> int:
	for s in MAX:
		if states[s] == null:
			return s
	return INVALID


func is_empty() -> bool:
	return occupancy.occupied_count == 0


## Committed definitions in ascending slot order. Used by the budget re-sum and
## by the blueprint encoder.
func committed_definitions() -> Array[PartDefinition]:
	var out: Array[PartDefinition] = []
	for s in MAX:
		if states[s] != null:
			out.append(PartRegistry.definition(states[s].part_def_id))
	return out


## ===== BUILD PROXIES ===================================================


## Creates the build proxy body for [param slot] from its authored
## [ColliderProfile].
##
## Architectural Invariant I-1: the proxy is the part's authored primitives and
## nothing else. It is not derived from a visual mesh, and it is not a
## simplification of one — it is the same geometry the match will collide with,
## which is what makes the garage's interpenetration answer match the match's.
func spawn_proxy(slot: int, cand: PlacementCandidate) -> void:
	if not has_physics():
		return
	var profile := cand.definition.collider_profile
	if profile == null or profile.primitives.is_empty():
		return

	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(body, space)
	PhysicsServer3D.body_set_collision_layer(body, CollisionLayers.LAYER_BUILD_GHOST)
	PhysicsServer3D.body_set_collision_mask(body, CollisionLayers.MASK_BUILD_GHOST)
	for prim in profile.primitives:
		var rid := shape_cache.rid_for(prim)
		if rid.is_valid():
			PhysicsServer3D.body_add_shape(body, rid, prim.local_transform())
	# The transform is written last, and that ordering is load-bearing. A body
	# positioned before it has any shapes keeps the broadphase entry it had when
	# it was empty, and every query against it returns nothing — which reads
	# exactly like a legal placement rather than like a missing proxy.
	PhysicsServer3D.body_set_state(
		body, PhysicsServer3D.BODY_STATE_TRANSFORM, cand.local_transform()
	)
	_proxy_bodies[slot] = body


func despawn_proxy(slot: int) -> void:
	var body: RID = _proxy_bodies[slot]
	if body.is_valid():
		PhysicsServer3D.free_rid(body)
		_proxy_bodies[slot] = RID()


func proxy_body(slot: int) -> RID:
	if slot < 0 or slot >= MAX:
		return RID()
	return _proxy_bodies[slot]


## Direct space state for the §7.7 query, or null without physics.
func space_state() -> PhysicsDirectSpaceState3D:
	if not has_physics():
		return null
	return PhysicsServer3D.space_get_direct_state(space)


## Releases every proxy body and the space, if this context created it.
##
## Godot frees a [RefCounted] deterministically, but physics server RIDs are not
## reference counted and leak silently: a garage opened and closed a hundred
## times leaves a hundred spaces stepping forever. Call this when the context
## dies.
func dispose() -> void:
	for s in MAX:
		despawn_proxy(s)
	shape_cache.clear()
	if _owns_space and space.is_valid():
		PhysicsServer3D.free_rid(space)
	space = RID()
	_owns_space = false
