extends TestCase
## [IslandDetacher] — the island-to-debris conversion of doc 04 §6, and the whole
## destruction chain that reaches it.
##
## Everything below starts from [signal EventBusService.part_destroyed] and a
## tick, because that is the only way the chain runs in a match:
## [DetachmentScheduler] batches, [DetachmentSolver] decides what stopped being
## attached, and only then does anything get spawned. A test that called
## [code]IslandDetacher.detach[/code] with a hand-written island would pass with
## the solver returning the wrong slots, which is the failure the player actually
## sees — half a hull falling off, or none of it.
##
## Two properties are worth more than the rest. The debris body must carry the
## Assembly's [i]authored[/i] collider primitives (Architectural Invariant I-1
## surviving detachment, §6.1), and the hull it left must keep its shape indices
## exactly where they were (doc 08 §5.4) — a renumbering there turns one severed
## panel into mis-attributed hits across everything placed after it.

const CORE_KEY := &"core.command.compact.t2"
const PANEL_KEY := &"str.panel.medium.t2"

const CORE_ORIGIN := Vector3i(24, 4, 24)
## Three Structural Components stacked on the Core Module's deck, so that
## destroying the lowest severs the two above it as one island.
const DECK_ORIGIN := Vector3i(24, 8, 24)
const MID_ORIGIN := Vector3i(24, 9, 24)
const TOP_ORIGIN := Vector3i(24, 10, 24)

const ASSEMBLY := 3

## Published in doc 01 §10 and in the shipped [code].tres[/code]. Re-asserted
## below, so a balance change to either names itself here rather than quietly
## moving every expected number in this file.
const CORE_MASS := 1800.0
const PANEL_MASS := 100.0
## The panel is 4x1x4 cells at 0.25 m, so its inertia box is this.
const PANEL_HALF := Vector3(0.5, 0.125, 0.5)

var _core: PartDefinition = null
var _panel: PartDefinition = null
var _contexts: Array[BuildContext] = []
var _runtimes: Array[AssemblyRuntime] = []
var _pools: Array[DebrisPool] = []
var _schedulers: Array[DetachmentScheduler] = []
var _detached: Array = []


func before_all() -> void:
	_core = PartRegistry.definition_by_key(CORE_KEY)
	_panel = PartRegistry.definition_by_key(PANEL_KEY)
	EventBus.island_detached.connect(_on_island_detached)


func after_all() -> void:
	EventBus.island_detached.disconnect(_on_island_detached)
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


func test_fixture_masses_match_the_published_tables() -> void:
	check_approx(_core.mass_kg, CORE_MASS, "the Core Module's mass")
	check_approx(_panel.mass_kg, PANEL_MASS, "the Structural Component's mass")
	check_true(
		InertiaSolver.half_extents(_panel).is_equal_approx(PANEL_HALF),
		"and the panel's inertia box is its lattice bounds"
	)


## ===== THE CHAIN =======================================================


func test_a_destroyed_part_sheds_its_island_as_a_debris_body() -> void:
	#  CORE — 1 — 2 — 3      destroy 1; 2 and 3 have no other route to the core
	var fixture := _stack()
	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)

	check_eq(fixture.pool.in_flight_count(), 0, "nothing is spawned before the tick resolves")
	EventBus.tick_resolved.emit()

	check_eq(fixture.pool.in_flight_count(), 1, "one island, one body")
	var body := fixture.body()
	if not check_not_null(body, "the sink produced a debris body"):
		return
	check_eq(body.slots, PackedByteArray([2, 3]), "carrying everything above the destroyed part")
	check_eq(body.source_assembly_id, ASSEMBLY, "and remembering where it came from")
	check_eq(_detached.size(), 1, "island_detached was announced once")
	check_eq(_detached[0][0], ASSEMBLY, "for this Assembly")
	check_eq(_detached[0][1], PackedByteArray([2, 3]), "with the island's slots")
	check_eq(_detached[0][2], body.get_instance_id(), "and the body id §8.2 promises")


func test_the_destroyed_part_is_not_itself_debris() -> void:
	# A part that reached zero integrity has ceased to exist. Spawning debris for
	# it would mean every destruction leaves a wreck of the thing that blew up.
	var fixture := _stack()
	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()

	var body := fixture.body()
	if not check_not_null(body, "the island above it still became debris"):
		return
	check_false(body.slots.has(1), "but the destroyed slot is not in it")
	check_false(fixture.runtime.graph.is_alive(1), "and it is gone from the graph")


func test_losing_the_core_module_turns_the_survivors_into_debris() -> void:
	# §7.2 into §6. The three panels are one connected component, so the whole
	# remaining hull leaves as a single body rather than three.
	var fixture := _stack()
	EventBus.part_destroyed.emit(ASSEMBLY, ChassisGraph.CORE, 0)
	EventBus.tick_resolved.emit()

	check_eq(fixture.pool.in_flight_count(), 1, "one component, one body")
	var body := fixture.body()
	if not check_not_null(body, "the survivors became debris"):
		return
	check_eq(body.slots, PackedByteArray([1, 2, 3]), "every surviving part is in it")
	check_approx(body.mass, 3.0 * PANEL_MASS, "and the body weighs all three")


func test_an_empty_island_produces_no_body() -> void:
	# §6's DEBRIS_MIN_PARTS_FOR_BODY. Spending one of ninety-six bodies on
	# nothing is how a pool runs dry during the fight that matters.
	var fixture := _stack()
	var body := IslandDetacher.detach(fixture.runtime, PackedByteArray(), fixture.pool)
	check_null(body, "no body for an empty island")
	check_eq(fixture.pool.in_flight_count(), 0, "and nothing taken from the pool")


## ===== §6.1 COLLIDERS ==================================================


func test_the_debris_body_carries_the_assemblys_authored_primitives() -> void:
	# Architectural Invariant I-1 surviving detachment. The assertion goes to the
	# physics server and to the shape resource itself, because a debris body with
	# no registered geometry and one built from a mesh look identical from the
	# node tree.
	var fixture := _stack()
	var hull_shape := fixture.runtime.body.get_node(^"shape_s002_p0") as CollisionShape3D
	if not check_not_null(hull_shape, "the panel's primitive was on the hull to begin with"):
		return
	var authored := hull_shape.shape

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()
	var body := fixture.body()
	if not check_not_null(body, "the island became debris"):
		return

	check_eq(
		PhysicsServer3D.body_get_shape_count(body.get_rid()), 2,
		"one shape per authored primitive, registered with the server"
	)
	check_eq(body.active_shape_count(), 2, "and the body agrees")
	check_eq(
		_debris_shapes(body)[0].shape, authored,
		"the very same Shape3D the Assembly carried, shared rather than rebuilt"
	)


func test_the_hulls_shape_indices_do_not_move_when_an_island_leaves() -> void:
	# Doc 08 §5.4. Removing a shape renumbers every later index on the body, so
	# the island's colliders are disabled where they stand and re-registered on
	# the debris body instead of migrating to it.
	var fixture := _stack()
	var before := PhysicsServer3D.body_get_shape_count(fixture.runtime.body.get_rid())

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()

	check_eq(
		PhysicsServer3D.body_get_shape_count(fixture.runtime.body.get_rid()), before,
		"the hull's shape list is the same length, so no index moved"
	)
	check_eq(fixture.runtime.body.slot_for_shape_index(0), 0, "index 0 is still the Core Module")
	check_eq(fixture.runtime.body.slot_for_shape_index(3), 3, "and index 3 is still slot 3")
	check_true(_hull_shape(fixture, 2).disabled, "the departed part's shape is out of the hull")
	check_true(_hull_shape(fixture, 3).disabled, "for every part in the island")
	check_false(_hull_shape(fixture, 0).disabled, "and the survivors are untouched")


func test_the_colliders_are_rebased_onto_the_island_centre_of_mass() -> void:
	var fixture := _stack()
	var hull_origin := _hull_shape(fixture, 2).transform.origin
	var com := _expected_island_com()

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()
	var body := fixture.body()
	if not check_not_null(body, "the island became debris"):
		return

	var shape := _debris_shapes(body)[0]
	check_true(
		shape.transform.origin.is_equal_approx(hull_origin - com),
		"the shape keeps its place relative to the island, not to the Assembly"
	)
	check_true(
		shape.transform.basis.is_equal_approx(_hull_shape(fixture, 2).transform.basis),
		"and its orientation is unchanged — the rebase is a pure translation"
	)
	check_true(
		body.center_of_mass.is_equal_approx(Vector3.ZERO),
		"so the body's centre of mass is its own origin"
	)


## ===== §6 MASS PROPERTIES ==============================================


func test_the_body_is_placed_at_the_islands_centre_of_mass() -> void:
	var fixture := _stack()
	var pose := _world_pose()
	fixture.runtime.body.global_transform = pose

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()
	var body := fixture.body()
	if not check_not_null(body, "the island became debris"):
		return

	check_true(
		body.global_transform.origin.is_equal_approx(pose * _expected_island_com()),
		"the island's centre of mass carried through the Assembly's world pose"
	)
	check_false(
		body.global_transform.origin.is_equal_approx(
			pose.origin + _expected_island_com()
		),
		"rotated into world space rather than merely added to the Assembly's position"
	)
	check_true(
		body.global_transform.basis.is_equal_approx(pose.basis),
		"and the island keeps the Assembly's orientation at the instant it left"
	)


func test_the_island_is_weighed_and_its_inertia_taken_about_itself() -> void:
	# Written out as arithmetic against doc 01 §10's table rather than derived by
	# calling the solver: two 34 kg slabs of 1.0 x 0.25 x 1.0 m, stacked one cell
	# apart in Y, each shifted 0.125 m from the pair's centre of mass.
	var fixture := _stack()
	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()
	var body := fixture.body()
	if not check_not_null(body, "the island became debris"):
		return

	check_approx(body.mass, 2.0 * PANEL_MASS, "the body weighs both panels")

	var k := PANEL_MASS / 12.0
	var w := PANEL_HALF * 2.0
	var own_x := k * (w.y * w.y + w.z * w.z)
	var own_y := k * (w.x * w.x + w.z * w.z)
	var own_z := k * (w.x * w.x + w.y * w.y)
	var d := SyndicateConstants.LATTICE_UNIT_M * 0.5  # half a cell either side
	var shift := PANEL_MASS * d * d
	check_approx(
		body.inertia.x, 2.0 * own_x + 2.0 * shift, "Ixx: both boxes, both parallel-axis shifts"
	)
	check_approx(
		body.inertia.y, 2.0 * own_y,
		"Iyy: the stack axis, where the shift contributes nothing"
	)
	check_approx(body.inertia.z, 2.0 * own_z + 2.0 * shift, "Izz, by symmetry with Ixx")


func test_the_island_centre_of_mass_is_weighted_by_mass_not_by_part_count() -> void:
	# The stacked fixture cannot show this: two parts of equal mass put the mean
	# and the weighted mean in the same place, so a solver that ignored mass
	# entirely would pass every other test in this file. Two definitions of very
	# different mass are the only pair the registry currently offers.
	var runtime := _new_runtime()
	var heavy := _synthetic_state(runtime, 1, _core, Vector3i(24, 4, 24))
	var light := _synthetic_state(runtime, 2, _panel, Vector3i(24, 12, 24))
	var pool := _pool()

	var heavy_com := MassSolver.part_com_local(heavy, _core)
	var light_com := MassSolver.part_com_local(light, _panel)
	var expected := (
		(heavy_com * CORE_MASS + light_com * PANEL_MASS) / (CORE_MASS + PANEL_MASS)
	)

	var body := IslandDetacher.detach(runtime, PackedByteArray([1, 2]), pool)
	if not check_not_null(body, "the synthetic island produced a body"):
		return
	check_true(
		body.global_transform.origin.is_equal_approx(expected),
		"the body sits at the mass-weighted centre, far nearer the heavy part"
	)
	check_false(
		body.global_transform.origin.is_equal_approx((heavy_com + light_com) * 0.5),
		"rather than halfway between them, which is what ignoring mass gives"
	)


## ===== §11 INVARIANT 8 =================================================


func test_debris_inherits_the_tangential_velocity_of_a_spinning_assembly() -> void:
	# The omega-cross-r term. Without it a panel shorn off a spinning Assembly
	# drops straight down while the Assembly rotates out from under it — the
	# tell-tale artefact of a naive detachment implementation.
	var fixture := _stack()
	var pose := _world_pose()
	fixture.runtime.body.global_transform = pose
	var linear := Vector3(6.0, 0.0, -2.0)
	# Deliberately not parallel to the lever arm. An angular velocity along it
	# gives a zero cross product, under which the term being dropped and the term
	# being correct produce the same number.
	var angular := Vector3(1.5, 4.0, -2.0)
	fixture.runtime.body.linear_velocity = linear
	fixture.runtime.body.angular_velocity = angular

	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()
	var body := fixture.body()
	if not check_not_null(body, "the island became debris"):
		return

	var r := pose.basis * _expected_island_com()
	check_true(
		body.linear_velocity.is_equal_approx(linear + angular.cross(r)),
		"the island leaves with the velocity it actually had at its own centre"
	)
	check_false(
		body.linear_velocity.is_equal_approx(linear),
		"rather than the chassis velocity, which is what dropping the term gives"
	)
	check_true(
		body.angular_velocity.is_equal_approx(angular), "and it keeps spinning at the same rate"
	)


## ===== CONSEQUENCES ====================================================


func test_the_detached_parts_leave_the_mass_solve() -> void:
	var fixture := _stack()
	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()

	check_true(
		fixture.runtime.state(2).has_flag(PartFlags.FLAG_DETACHED), "the island's parts are flagged"
	)
	check_true(fixture.runtime.state(3).has_flag(PartFlags.FLAG_DETACHED), "all of them")
	var mp := MassSolver.compute(fixture.runtime.states, fixture.runtime.graph)
	check_approx(mp.total_mass, CORE_MASS, "and the Assembly is down to its Core Module")
	check_eq(mp.part_count, 1, "with one part left in the solve")


func test_the_body_is_handed_to_the_reaper() -> void:
	# §6's last line but one. A body spawned without a deadline never returns to
	# the pool, and ninety-six of those is a match with no debris at all.
	var fixture := _stack()
	var start := MatchClock.tick
	EventBus.part_destroyed.emit(ASSEMBLY, 1, 0)
	EventBus.tick_resolved.emit()
	var body := fixture.body()
	if not check_not_null(body, "the island became debris"):
		return

	check_eq(
		body.expires_at_tick,
		start + MatchClockService.ticks_for_seconds(IslandDetacher.DEBRIS_LIFETIME_S),
		"scheduled for §6's 22 s lifetime"
	)


## ===== FIXTURES ========================================================


func _on_island_detached(assembly_id: int, slots: PackedByteArray, body_id: int) -> void:
	_detached.append([assembly_id, slots, body_id])


## The hull's [CollisionShape3D] for [param slot]'s single authored primitive.
func _hull_shape(fixture: Fixture, slot: int) -> CollisionShape3D:
	return fixture.runtime.body.get_node(NodePath("shape_s%03d_p0" % slot)) as CollisionShape3D


## A debris body's live shapes, in registration order.
func _debris_shapes(body: DebrisBodyRef) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for child in body.get_children():
		var cs := child as CollisionShape3D
		if cs != null and not cs.disabled:
			out.append(cs)
	return out


## Centre of mass of the two-panel island, from the lattice and the published
## offset rather than from the solver under test.
func _expected_island_com() -> Vector3:
	var mid := LatticeMath.cell_to_local(MID_ORIGIN) + _panel.com_offset_m
	var top := LatticeMath.cell_to_local(TOP_ORIGIN) + _panel.com_offset_m
	return (mid + top) * 0.5


## Installs a part on [param runtime] without going through the placement chain,
## for the one rule the two shipped definitions cannot otherwise separate. It is
## never committed: commit resolves through [PartRegistry], and a fixture in the
## registry would change what every other test in the suite sees.
func _synthetic_state(
	runtime: AssemblyRuntime, slot: int, def: PartDefinition, cell: Vector3i
) -> PartInstanceState:
	var st := PartInstanceState.new()
	st.slot = slot
	st.part_def_id = def.runtime_id
	st.origin_cell = cell
	st.orientation_index = 0
	st.integrity = def.integrity_max
	runtime.states[slot] = st
	runtime.attach_part(slot)
	return st


## The Assembly's world pose in the two tests that need one.
##
## The rotation carries part-local +Y onto world +Z, which matters: the island
## sits directly above the Core Module, so a pose that left +Y alone could not
## tell a correctly rotated offset from one that was never rotated at all.
func _world_pose() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(PI * 0.5, 0.0, 0.0)), Vector3(12.0, 3.0, -5.0))


func _new_runtime() -> AssemblyRuntime:
	var runtime := AssemblyRuntime.new()
	_runtimes.append(runtime)
	EventBus.get_tree().root.add_child(runtime)
	return runtime


func _pool() -> DebrisPool:
	var pool := DebrisPool.new()
	_pools.append(pool)
	EventBus.get_tree().root.add_child(pool)
	return pool


## A Core Module with three Structural Components stacked on its deck, committed
## through the same [PlacementValidator] chain every other path uses, with the
## detachment chain wired to a pool exactly as the match scene will wire it.
func _stack() -> Fixture:
	var ctx := BuildContext.with_physics(ASSEMBLY)
	_contexts.append(ctx)
	PlacementValidator.commit(ctx, PlacementCandidate.create(_core, CORE_ORIGIN, 0))
	PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, DECK_ORIGIN, 0))
	PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, MID_ORIGIN, 0))
	PlacementValidator.commit(ctx, PlacementCandidate.create(_panel, TOP_ORIGIN, 0))

	var fixture := Fixture.new()
	fixture.runtime = _new_runtime()
	fixture.runtime.adopt(ctx)
	fixture.pool = _pool()

	fixture.registry = AssemblyRegistry.new()
	fixture.registry.register(fixture.runtime)
	fixture.pool.registry = fixture.registry

	var scheduler := DetachmentScheduler.new()
	scheduler.registry = fixture.registry
	_schedulers.append(scheduler)
	EventBus.get_tree().root.add_child(scheduler)
	# The production wiring, not a stand-in: this is the one assignment the match
	# scene makes to connect the two halves of detachment.
	scheduler.island_sink = fixture.pool.on_island_severed
	fixture.scheduler = scheduler
	return fixture


## The three objects the match scene owns, held together so a test can reach
## any of them.
class Fixture:
	extends RefCounted

	var runtime: AssemblyRuntime = null
	var pool: DebrisPool = null
	var registry: AssemblyRegistry = null
	var scheduler: DetachmentScheduler = null

	## The single body this fixture's one destruction produced, or null.
	func body() -> DebrisBodyRef:
		return null if pool.in_flight_count() != 1 else pool.in_flight_bodies()[0]
