extends TestCase
## A real four-wheeled Assembly, built through [PlacementValidator], adopted into
## an [AssemblyRuntime], and dropped onto ground the physics server integrates.
##
## Everything here is shipped data. The build is the first in the project's
## history to put a Motive Assembly through the validator, which is what doc 01
## §4.2's `AXLE` keying was resolved for and what doc 02 §7.5's ground-clearance
## check exists to reject — until this file neither had ever been exercised by a
## placement, only by a unit test against synthetic candidates.
##
## [b]It found two things.[/b] The first was a data defect and is fixed: all four
## `mot.*` parts carried the AXLE [i]station's[/i] `accepts_classes` restriction
## on their own drive face, and since [code]_check_mating[/code] tests the
## restriction in both directions, every Motive Assembly in the registry rejected
## the only part §4.2 lets it mount on. Nothing could be built with locomotion at
## all. The second is recorded by
## [method test_the_suspension_carries_no_load_on_shipped_data] below and is
## [i]not[/i] fixed here, because resolving it is a balance decision under
## CLAUDE.md §12 rather than a defect with one correct answer.

const CORE_KEY := &"core.command.compact.t2"
const HUB_KEY := &"str.hub.axle_station.t2"
const WHEEL_KEY := &"mot.wheeled.allroad.t2"

const CORE_ORIGIN := Vector3i(24, 4, 24)
## Hub stations under the Core Module's four lower corners. They mate to its
## underside on +Y, which is what leaves both AXLE faces free: the station's two
## drive faces are opposite each other, so a station that bolted on through one
## of them would have nowhere to put a wheel.
const HUB_ORIGINS: Array[Vector3i] = [
	Vector3i(22, 2, 23), Vector3i(26, 2, 23), Vector3i(22, 2, 27), Vector3i(26, 2, 27)
]
## Wheel pivots outboard of each station. Four cells apart on Z because the disc
## is four cells across it, and a closer pair overlaps into `CELL_OCCUPIED`.
##
## **Committed one flank at a time, and that ordering is the fixture.** Slots are
## assigned in commit order, so committing left-front, right-front, left-rear,
## right-rear would leave the pairing loop's own ascending order already equal to
## the correct answer — and §6.5's side test could be deleted outright without
## `test_each_axle_pair_straddles_the_centreline` moving. Fault injection made
## exactly that deletion and the test passed. Both left discs first means the
## naive pairing produces a same-side pair, which is the thing the rule forbids.
const WHEEL_ORIGINS: Array[Vector3i] = [
	Vector3i(19, 3, 22), Vector3i(19, 3, 28), Vector3i(28, 3, 22), Vector3i(28, 3, 28)
]

## 380 kg Core Module, four 29 kg stations, four 68 kg discs.
const EXPECTED_MASS_KG: float = 768.0

## Doc 05 §6.1's probe radius ratio, quoted rather than imported.
##
## Importing [constant AssemblyRuntime.PROBE_RADIUS_RATIO] here would make the
## assertion below a tautology — it moves with whatever the source says, and a
## probe sphere five times too big passes. Fault injection said exactly that.
## A published constant is asserted against the document, once, and the code is
## asserted against the assertion.
const DOC_PROBE_RADIUS_RATIO: float = 0.85
const EXPECTED_PART_COUNT: int = 9

## Ticks to fall two metres and settle onto the contact.
const SETTLE_TICKS: int = 260

const GROUND_HALF_HEIGHT: float = 2.0
const GROUND_SPAN_M: float = 200.0

var _ctx: BuildContext = null
var _runtime: AssemblyRuntime = null
var _motion: MotiveSystem = null
var _ground: StaticBody3D = null
## Assembly-local height of every wheel probe. Identical on all four by
## construction, and re-read from the runtime rather than written down here so
## that a change to the wheel's authored centre of mass moves the expectation
## with it.
var _probe_local_y: float = 0.0


func before_all() -> void:
	var core := PartRegistry.definition_by_key(CORE_KEY)
	var hub := PartRegistry.definition_by_key(HUB_KEY)
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY)

	_ctx = BuildContext.with_physics(1)
	PlacementValidator.commit(_ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))
	for cell: Vector3i in HUB_ORIGINS:
		PlacementValidator.commit(_ctx, PlacementCandidate.create(hub, cell, 0))
	for cell: Vector3i in WHEEL_ORIGINS:
		PlacementValidator.commit(
			_ctx, PlacementCandidate.create(wheel, cell, _wheel_orientation_for(cell))
		)

	_runtime = AssemblyRuntime.new()
	EventBus.get_tree().root.add_child(_runtime)
	_runtime.adopt(_ctx)
	_runtime.apply_mass_properties(MassSolver.compute(_runtime.states, _runtime.graph))

	_motion = MotiveSystem.new()
	_motion.runtime = _runtime
	_motion.input = ControlInput.new()
	_motion.power = PowerSystem.new()
	_motion.power.recompute(_runtime.states, _runtime.graph.alive)
	_runtime.add_child(_motion)
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var def := _runtime.definition_at(slot)
		if def != null and def.part_class == PartEnums.PartClass.MOTIVE_ASSEMBLY:
			_motion.register(slot, def, _runtime.states[slot])
			_probe_local_y = _runtime.motive_probes_of(slot)[0].position.y

	_ground = _make_ground()
	_runtime.body.global_position = Vector3(0.0, 2.0, 0.0)


func after_all() -> void:
	if _runtime != null:
		_runtime.free()
	if _ctx != null:
		_ctx.dispose()
	if _ground != null:
		_ground.queue_free()


## ===== THE BUILD =======================================================


func test_every_placement_was_accepted() -> void:
	check_eq(
		_ctx.committed_definitions().size(),
		EXPECTED_PART_COUNT,
		"a Core Module, four AXLE stations and four Motive Assemblies committed"
	)
	check_eq(_motion.motive_slot_count(), WHEEL_ORIGINS.size(), "all four discs registered")
	check_approx(
		_runtime.mass_properties.total_mass, EXPECTED_MASS_KG, "the solved mass of the build"
	)
	check_approx(
		_runtime.mass_properties.com_local.x,
		0.0,
		"and a symmetric build's centre of mass is on the centreline"
	)


func test_a_motive_assembly_may_not_bolt_straight_onto_the_core() -> void:
	# §4.2's keying, exercised by a placement rather than by a unit test. The
	# drive face is AXLE and nothing else, so the Core Module's neutral faces
	# reject it and the station is not optional decoration — it is the only way
	# a wheel reaches an Assembly.
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY)
	var flush_against_core := Vector3i(21, 5, 24)
	var reject := PlacementValidator.validate(
		_ctx, PlacementCandidate.create(wheel, flush_against_core, _wheel_orientation(1.0))
	)
	check_ne(reject, PlacementValidator.Reject.NONE, "a wheel on bare structure is rejected")


func test_every_wheel_carries_exactly_one_probe() -> void:
	for slot: int in _motion.motive_slots():
		check_eq(
			_runtime.motive_probes_of(slot).size(),
			1,
			"a wheeled Motive Assembly sweeps one contact (doc 05 §6.1)"
		)
		check_eq(_motion.contact_count(slot), 1, "and carries one contact for it")
		check_eq(
			_motion.contact_at(slot, 0).probe,
			_runtime.motive_probes_of(slot)[0],
			"and the contact is bound to it"
		)


func test_the_probe_is_the_documented_sphere_under_the_documented_node() -> void:
	# Geometry rather than behaviour, and deliberately so: on flat ground a
	# probe sphere of any radius finds the same surface at the same distance, so
	# nothing this file settles can tell 0.85 from 4.0. Both were planted as
	# faults and both survived every behavioural assertion here. The sphere size
	# is what stops a ray-like probe dropping into the gaps between ground
	# triangles (§6.1) and the only test that could distinguish it by behaviour
	# is one with a step or a crevice in the fixture, which wants doc 09's Ground
	# Array rather than a slab.
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY)
	var profile := wheel.motive_profile
	check_approx(
		AssemblyRuntime.PROBE_RADIUS_RATIO,
		DOC_PROBE_RADIUS_RATIO,
		"the source's ratio is the one doc 05 §6.1 publishes"
	)
	for slot: int in _motion.motive_slots():
		var probe := _runtime.motive_probes_of(slot)[0]
		var sphere := probe.shape as SphereShape3D
		if not check_not_null(sphere, "the probe casts a sphere, not a ray"):
			continue
		check_approx(
			sphere.radius,
			profile.contact_radius_m * DOC_PROBE_RADIUS_RATIO,
			"sized from the contact radius, not from the shape's default"
		)
		check_approx(
			probe.target_position.y,
			-(profile.suspension_rest_length_m + profile.suspension_travel_limit_m),
			"and sweeps rest length plus full travel, straight down the chassis"
		)
		# §2's tree. MotiveProbes is not decoration: it is where every consumer
		# of this Assembly's probes expects to find them, and a ShapeCast3D works
		# equally well anywhere in the tree, which is exactly why nothing else
		# notices when one is put somewhere else.
		check_eq(
			probe.get_parent(), _runtime.motive_probes, "hanging off MotiveProbes"
		)


func test_the_probes_are_masked_to_the_world_and_not_to_other_assemblies() -> void:
	# §11 invariant 5. The exclusion is what stops two Assemblies' suspensions
	# pushing against each other, and what stops a player driving up an opponent.
	var probe := _runtime.motive_probes_of(_motion.motive_slots()[0])[0]
	check_true(
		(probe.collision_mask & CollisionLayers.LAYER_GROUND) != 0, "probes see the ground"
	)
	check_true(
		(probe.collision_mask & CollisionLayers.LAYER_STATIC_VOLUME) != 0,
		"and Static Volumes"
	)
	check_eq(
		probe.collision_mask & CollisionLayers.LAYER_ASSEMBLY_HULL, 0, "never another hull"
	)
	check_eq(probe.collision_mask & CollisionLayers.LAYER_DEBRIS, 0, "and never wreckage")


func test_the_four_probes_pair_into_two_axles() -> void:
	# §6.5's pairing, derived at spawn from where the builder put the discs
	# rather than authored. Two rows of two, so two pairs.
	check_eq(_motion.axle_pair_count(), 2, "front and rear")


func test_each_axle_pair_straddles_the_centreline() -> void:
	# The count above is not the assertion. Four probes make two pairs whether
	# they were matched across the Assembly or down one flank, so a test that
	# only counts passes against pairing that ignores the sign test — the one
	# thing §6.5 exists to do. Fault injection made exactly that substitution and
	# the count did not move.
	var seen: Array[MotiveContact] = []
	for pair: int in _motion.axle_pair_count():
		var left := _motion.axle_pair_end(pair, false)
		var right := _motion.axle_pair_end(pair, true)
		if not check_not_null(left, "pair %d has a left end" % pair):
			continue
		if not check_not_null(right, "pair %d has a right end" % pair):
			continue
		check_true(
			left.probe.position.x < 0.0,
			"pair %d's left end is on the negative-x side" % pair
		)
		check_true(
			right.probe.position.x > 0.0,
			"and its right end is on the positive-x side"
		)
		check_true(
			absf(left.probe.position.z - right.probe.position.z)
			<= SuspensionSolver.AXLE_PAIR_TOLERANCE_M,
			"and the two sit on one axle rather than diagonally across the hull"
		)
		# A probe in two pairs would be pushed twice by the same roll, which is a
		# doubled anti-roll rate that no authored number accounts for.
		check_false(seen.has(left), "pair %d's left end is not already spoken for" % pair)
		check_false(seen.has(right), "nor its right end")
		seen.append(left)
		seen.append(right)
	check_eq(seen.size(), 4, "all four contacts were paired, each exactly once")


## ===== SETTLING ========================================================


func test_the_assembly_settles_level_on_its_contacts() -> void:
	await physics_frames(SETTLE_TICKS)

	check_true(
		_runtime.body.global_transform.basis.y.dot(Vector3.UP) > 0.999,
		"a symmetric four-contact build settles upright rather than tipping"
	)
	check_true(
		_runtime.body.linear_velocity.length() < 0.01, "and comes to rest rather than drifting"
	)
	# Ride height is the contact radius plus the probe's height above the disc
	# centre, less the solver's contact slop. Derived rather than recorded, so a
	# change to either authored number moves the expectation with it.
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY)
	var expected := wheel.motive_profile.contact_radius_m - _probe_local_y
	check_approx(
		_runtime.body.global_position.y,
		expected,
		"and rests one rolling radius above the surface",
		0.02
	)


func test_every_probe_finds_the_ground_beneath_its_wheel() -> void:
	await physics_frames(SETTLE_TICKS)
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY)
	for slot: int in _motion.motive_slots():
		var contact := _motion.contact_at(slot, 0)
		if not check_true(contact.grounded, "slot %d found the surface" % slot):
			continue
		check_approx(
			contact.distance_m,
			wheel.motive_profile.contact_radius_m,
			"at one rolling radius below the disc centre",
			0.02
		)
		check_true(
			contact.normal_world.dot(Vector3.UP) > 0.99, "with the surface normal upward"
		)


## ===== THE FINDING =====================================================


func test_the_suspension_carries_no_load_on_shipped_data() -> void:
	# Not an assertion that this is correct. It is a measurement, written down so
	# that the next session inherits the number instead of the argument.
	#
	# §6.1 puts the probe origin at the disc's centre of mass and §6.2 reads
	# compression as `rest_length - distance`. A disc resting on its own authored
	# collider puts that distance at one rolling radius, so compression is
	# positive only while `suspension_rest_length_m > contact_radius_m`. Shipped,
	# they are 0.32 m and 0.50 m: compression clamps to zero on every contact,
	# the normal force is zero, `_apply_traction` returns before it applies
	# anything, and a ground Assembly at full throttle does not move.
	#
	# The resolution is a balance change to doc 01 §10.3 — a rest length longer
	# than the rolling radius by the intended static sag, which also turns the
	# disc's collider into the bump stop it should be. It is deliberately not
	# made here: it changes how every ground build in the game feels, and
	# CLAUDE.md §12 puts that behind a balance review rather than inside a test.
	await physics_frames(SETTLE_TICKS)
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY)
	var profile := wheel.motive_profile
	check_true(
		profile.suspension_rest_length_m < profile.contact_radius_m,
		"the authored rest length is shorter than the rolling radius"
	)
	for slot: int in _motion.motive_slots():
		var contact := _motion.contact_at(slot, 0)
		check_approx(
			SuspensionSolver.compression(profile, contact),
			0.0,
			"so slot %d consumes no travel" % slot
		)
		check_approx(contact.normal_force_n, 0.0, "and carries no normal force")


func test_full_throttle_moves_nothing_while_the_contacts_carry_no_load() -> void:
	# The consequence, stated as behaviour rather than as arithmetic. This test
	# is expected to be *inverted* by whoever resolves the rest length: it should
	# become "full throttle accelerates the Assembly forward", and the fact that
	# it cannot be written that way today is the whole point of keeping it.
	await physics_frames(SETTLE_TICKS)
	var start := _runtime.body.global_position
	_motion.input.throttle = 1.0
	await physics_frames(60)
	_motion.input.throttle = 0.0
	check_true(
		start.distance_to(_runtime.body.global_position) < 0.01,
		"a second of full throttle moves an Assembly whose contacts carry nothing"
	)


## ===== FIXTURES ========================================================


## The orientation that points a disc's AXLE face inboard, towards the station
## it mounts on. Derived from the 24-orientation group rather than written down:
## the wheel's drive face is its local -Z (doc 01 §10.3), and which index carries
## that onto the Assembly's +X is a property of [OrientationTable], not of this
## test.
func _wheel_orientation_for(cell: Vector3i) -> int:
	return _wheel_orientation(1.0 if cell.x < CORE_ORIGIN.x else -1.0)


func _wheel_orientation(face_sign: float) -> int:
	for i: int in SyndicateConstants.ORIENTATION_COUNT:
		var basis := OrientationTable.basis_for(i)
		if not (basis * Vector3.FORWARD).is_equal_approx(Vector3(face_sign, 0.0, 0.0)):
			continue
		# Upright too, so the disc rolls in the Assembly's fore-aft plane rather
		# than lying flat. Without this the first accepted index is a wheel on
		# its side, which mates perfectly well and drives nowhere.
		if (basis * Vector3.UP).is_equal_approx(Vector3.UP):
			return i
	return 0


## A static slab on the ground layer. Not a Dynamic Ground Array — doc 09 owns
## that and nothing here pre-empts it.
func _make_ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = CollisionLayers.LAYER_GROUND
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SPAN_M, GROUND_HALF_HEIGHT * 2.0, GROUND_SPAN_M)
	shape.shape = box
	body.add_child(shape)
	EventBus.get_tree().root.add_child(body)
	body.global_position = Vector3(0.0, -GROUND_HALF_HEIGHT, 0.0)
	return body
