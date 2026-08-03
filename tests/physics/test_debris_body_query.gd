extends TestCase
## A severed island is findable in the physics space, at its own centre of mass,
## by doc 08 §5.3's blast query.
##
## Every other assertion about a debris body reads the [b]node[/b] — its
## [member Node3D.global_transform], its shape list, its collision layer.
## [code]tests/integration/test_island_detachment.gd[/code] does all of that
## thoroughly. None of it asks the question the game asks, which is whether the
## space agrees: a wreck the blast query cannot see soaks no fragments and
## shields nothing behind it, and it renders in exactly the right place while it
## does so. This file uses §5.3's real mask for that reason.
##
## [b]It does not defend the ordering rule, and session 17 measured why.[/b]
## §3.19 records that a body handed its transform while still shapeless keeps the
## broadphase entry it had when empty, and §5 proposed exactly this file as the
## fault that would finally catch it. It does not. The transform was moved ahead
## of the shapes — both as an extra early write and as the only write — and this
## query still finds the body, because the [code]await physics_frames[/code] that
## §3.28 makes mandatory is itself what flushes the stale entry. A test that must
## step the engine to ask the question cannot also observe a fault that a step
## repairs. Whatever closes the ordering rule has to query inside the same frame
## the body was built in, and §3.28 says a same-frame query reads a stale pose
## anyway — so the honest position is that the ordering is currently
## unverifiable, and the comment in [IslandDetacher] is the record of why it is
## written the way it is.

const CORE_KEY := &"core.command.compact.t2"
const PANEL_KEY := &"str.panel.medium.t2"

const CORE_ORIGIN := Vector3i(24, 4, 24)
## Three Structural Components stacked on the deck, so destroying the lowest
## severs the two above it as one island — the same shape as the integration
## fixture, for the same reason.
const DECK_ORIGIN := Vector3i(24, 7, 24)
const MID_ORIGIN := Vector3i(24, 8, 24)
const TOP_ORIGIN := Vector3i(24, 9, 24)

const ASSEMBLY := 41

## Far from every other fixture in [code]tests/physics/[/code]. Those build
## ground slabs around the origin and §3.45 is what happens when two of them
## share a coordinate.
const SPAWN := Vector3(300.0, 80.0, -300.0)

## Enough to flush the broadphase; §3.28 needs one and the second costs nothing.
const FLUSH_FRAMES := 2

## Small enough that finding the body proves it is where it says it is, rather
## than proving the space contains something somewhere.
const PROBE_RADIUS_M := 0.3

## A control point with nothing near it, so the probe is shown to be capable of
## answering "no".
const CONTROL_OFFSET := Vector3(50.0, 0.0, 0.0)

var _core: PartDefinition = null
var _panel: PartDefinition = null
var _contexts: Array[BuildContext] = []
var _runtimes: Array[AssemblyRuntime] = []
var _pools: Array[DebrisPool] = []
var _schedulers: Array[DetachmentScheduler] = []

var _measured: bool = false
var _body: DebrisBodyRef = null
var _shapes_on_body: int = 0
var _found_at_com: bool = false
var _found_at_control: bool = false


func before_all() -> void:
	_core = PartRegistry.definition_by_key(CORE_KEY)
	_panel = PartRegistry.definition_by_key(PANEL_KEY)


func after_all() -> void:
	for scheduler in _schedulers:
		scheduler.free()
	_schedulers.clear()
	for pool in _pools:
		pool.free()
	_pools.clear()
	for runtime in _runtimes:
		runtime.free()
	_runtimes.clear()
	for ctx in _contexts:
		ctx.dispose()
	_contexts.clear()


## ===== THE FIXTURE IS ABLE TO FAIL =====================================

## Asserted before anything else, because every assertion below it is vacuous if
## the island never became a body or the body never took a shape. This is the
## same ordering [code]test_overpenetration_bounds.gd[/code] uses: establish that
## the geometry can answer the question before asking it.
func test_the_severed_island_became_a_body_carrying_shapes() -> void:
	await _measure()
	if not check_not_null(_body, "the destruction produced a debris body"):
		return
	check_eq(
		_body.slots, PackedByteArray([2, 3]),
		"carrying the two Structural Components above the destroyed part"
	)
	check_true(
		_shapes_on_body > 0,
		"and the physics server holds shapes for it — %d" % _shapes_on_body
	)


## ===== THE SPACE AGREES WITH THE NODE ==================================

## The assertion the file exists for. It is live rather than decorative —
## dropping [constant CollisionLayers.LAYER_DEBRIS] from the pooled body makes it
## fail — but see the class comment for the one fault it was written for and
## does not catch.
func test_a_blast_query_at_the_wreck_finds_it() -> void:
	await _measure()
	check_true(
		_found_at_com,
		"doc 08 §5.3's blast query finds the debris body at its centre of mass"
	)


## Assert the rejection, not just the acceptance (§9). A query that answers yes
## everywhere would satisfy the check above without proving anything about where
## the body is.
func test_the_same_query_finds_nothing_where_the_wreck_is_not() -> void:
	await _measure()
	check_false(
		_found_at_control,
		"and finds nothing %.0f m away, so the probe is capable of a no"
		% CONTROL_OFFSET.length()
	)


## ===== FIXTURE =========================================================

## Builds the stack, severs the island through the real chain, steps the engine
## so the broadphase catches up, and records what the space answers.
##
## Run once and read by three methods: the runner sorts method names, and a
## destruction cannot be repeated (§3.43).
func _measure() -> void:
	if _measured:
		return
	_measured = true

	var ctx := BuildContext.with_physics(ASSEMBLY)
	_contexts.append(ctx)
	PlacementValidator.commit(ctx, PlacementCandidate.create(_core, CORE_ORIGIN, 0))
	PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0))
	PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, MID_ORIGIN, 0))
	PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, TOP_ORIGIN, 0))

	var runtime := AssemblyRuntime.new()
	_runtimes.append(runtime)
	EventBus.get_tree().root.add_child(runtime)
	runtime.adopt(ctx)
	runtime.body.global_transform = Transform3D(Basis(), SPAWN)

	var pool := DebrisPool.new()
	_pools.append(pool)
	EventBus.get_tree().root.add_child(pool)

	var registry := AssemblyRegistry.new()
	registry.register(runtime)
	pool.registry = registry

	var scheduler := DetachmentScheduler.new()
	scheduler.registry = registry
	_schedulers.append(scheduler)
	EventBus.get_tree().root.add_child(scheduler)
	scheduler.island_sink = pool.on_island_severed

	# The real chain, not a direct call: destroy the lowest panel and let the
	# scheduler batch it, the solver decide what came away, and the sink spawn.
	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()

	if pool.in_flight_count() == 1:
		_body = pool.in_flight_bodies()[0]
	if _body == null:
		return
	_shapes_on_body = PhysicsServer3D.body_get_shape_count(_body.get_rid())

	await physics_frames(FLUSH_FRAMES)

	# Read the pose after the step: the body is falling, and the question is
	# whether the space agrees with wherever it is now.
	var com := _body.global_transform.origin
	_found_at_com = _query_finds_body(com)
	_found_at_control = _query_finds_body(com + CONTROL_OFFSET)


## True when doc 08 §5.3's blast query, at [param where], reports the debris
## body's own RID.
##
## Membership rather than a count: the Assembly this island came off is on
## [constant CollisionLayers.LAYER_ASSEMBLY_HULL], which the blast mask also
## covers, so "something was found" is not the question being asked.
func _query_finds_body(where: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = PROBE_RADIUS_M

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), where)
	params.collision_mask = CollisionLayers.MASK_BLAST_QUERY

	var space := EventBus.get_tree().root.world_3d.direct_space_state
	var hits := space.intersect_shape(params)
	var wanted := _body.get_rid()
	for hit: Dictionary in hits:
		if hit.get("rid") == wanted:
			return true
	return false
