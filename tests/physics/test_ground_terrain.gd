extends TestCase
## A real Assembly on a real Dynamic Ground Array, against
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §5, §7.1 and §7.3.
##
## The other ground files in this directory stand their builds on a flat
## [BoxShape3D] slab, which is what every measurement in them was taken against.
## This one puts the same recipe on the streamed heightfield and asks the three
## questions the slab could never answer: does the collision agree with the
## height data, does an Assembly settle on terrain rather than through it, and
## does a crater change how the ground under it behaves.
##
## [b]The first of those is the load-bearing one.[/b] [HeightMapShape3D] stores
## [code]map_data[z * width + x][/code] with sample zero at the shape's negative
## corner, one unit per sample, centred on the shape origin — so the Array has to
## place each chunk body at the chunk's centre and scale it by the sample
## spacing. A transpose, a half-chunk offset, or a missing scale all produce
## terrain that looks right and that vehicles drive through, and none of them is
## visible in the height data. Only a ray fired at a known world position against
## the shape the physics server actually holds can tell.

const CORE_KEY := &"core.command.compact.t2"
const HUB_KEY := &"str.hub.axle_station.t2"
const WHEEL_KEY := &"mot.wheeled.light_road.t1"
const REAR_KEY := &"mot.wheeled.light_fixed.t1"
const POWER_KEY := &"pmv.combustion.flat.t2"

const CORE_ORIGIN := Vector3i(24, 4, 24)
const POWER_ORIGIN := Vector3i(24, 4, 34)
const HUB_ORIGINS: Array[Vector3i] = [
	Vector3i(21, 2, 19), Vector3i(27, 2, 19), Vector3i(21, 2, 29), Vector3i(27, 2, 29)
]
const WHEEL_ORIGINS: Array[Vector3i] = [
	Vector3i(18, 3, 19), Vector3i(18, 3, 29), Vector3i(29, 3, 19), Vector3i(29, 3, 29)
]
const FRONT_AXLE_Z: int = 24

## Where the build is put down. Away from the origin so that a chunk-indexing
## error cannot be masked by everything being at sample zero, and away from a
## chunk seam so settling is not testing the seam logic as well.
const SPAWN_XZ := Vector2(-140.0, 92.0)
const DROP_CLEARANCE_M: float = 1.6

## Enough ticks for the suspension to settle. §3.44: assert a range, never a
## count — this is a duration to wait, not a measurement.
const SETTLE_TICKS: int = 90

var _ctx: BuildContext = null
var _runtime: AssemblyRuntime = null
var _motion: MotiveSystem = null
var _array: GroundArray = null
var _deform: GroundDeformSystem = null
var _streamer: GroundCollisionStreamer = null


func before_all() -> void:
	_array = GroundArray.new()
	_array.present_visuals = false
	_array.source = GroundSource.rolling(4242, 9.0)
	EventBus.get_tree().root.add_child(_array)

	_deform = GroundDeformSystem.new()
	_deform.array = _array
	_deform.synchronous = true
	EventBus.get_tree().root.add_child(_deform)

	_streamer = GroundCollisionStreamer.new()
	_streamer.array = _array
	_streamer.extra_anchors = PackedVector3Array([Vector3(SPAWN_XZ.x, 0.0, SPAWN_XZ.y)])
	EventBus.get_tree().root.add_child(_streamer)
	# prime(), not evaluate(): the per-evaluation cap spreads instantiation
	# across ticks and this fixture is about to drop a body onto ground that has
	# to already be there.
	_streamer.prime()

	_build_assembly()


func after_all() -> void:
	if _runtime != null:
		_runtime.free()
	if _ctx != null:
		_ctx.dispose()
	for node: Node in [_streamer, _deform, _array]:
		if node != null:
			node.get_parent().remove_child(node)
			node.queue_free()


func _build_assembly() -> void:
	var core := PartRegistry.definition_by_key(CORE_KEY)
	var hub := PartRegistry.definition_by_key(HUB_KEY)
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY)
	var rear := PartRegistry.definition_by_key(REAR_KEY)

	_ctx = BuildContext.with_physics(1)
	PlacementValidator.commit(_ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))
	PlacementValidator.commit(
		_ctx,
		PlacementCandidate.create(PartRegistry.definition_by_key(POWER_KEY), POWER_ORIGIN, 0)
	)
	for cell: Vector3i in HUB_ORIGINS:
		PlacementValidator.commit(_ctx, PlacementCandidate.create(hub, cell, 0))
	for cell: Vector3i in WHEEL_ORIGINS:
		var def := wheel if cell.z < FRONT_AXLE_Z else rear
		PlacementValidator.commit(
			_ctx, PlacementCandidate.create(def, cell, _wheel_orientation_for(cell))
		)

	_runtime = AssemblyRuntime.new()
	EventBus.get_tree().root.add_child(_runtime)
	_runtime.adopt(_ctx)
	_runtime.apply_mass_properties(MassSolver.compute(_runtime.states, _runtime.graph))

	_motion = MotiveSystem.new()
	_motion.runtime = _runtime
	_motion.input = ControlInput.new()
	_motion.ground = _array
	_motion.ground_deform = _deform
	_motion.power = PowerSystem.new()
	_motion.power.recompute(_runtime.states, _runtime.graph.alive)
	_runtime.add_child(_motion)
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var def := _runtime.definition_at(slot)
		if def != null and def.part_class == PartEnums.PartClass.MOTIVE_ASSEMBLY:
			_motion.register(slot, def, _runtime.states[slot])

	_place_over_ground(SPAWN_XZ)


func _wheel_orientation_for(cell: Vector3i) -> int:
	return _wheel_orientation(1.0 if cell.x < CORE_ORIGIN.x else -1.0)


## The orientation index whose forward face points along [param face_sign] on X
## and whose up is still up, so the disc rolls in the fore-aft plane rather than
## lying on its side. The same derivation `test_ground_assembly.gd` uses.
func _wheel_orientation(face_sign: float) -> int:
	for i: int in SyndicateConstants.ORIENTATION_COUNT:
		var basis := OrientationTable.basis_for(i)
		if not (basis * Vector3.FORWARD).is_equal_approx(Vector3(face_sign, 0.0, 0.0)):
			continue
		if (basis * Vector3.UP).is_equal_approx(Vector3.UP):
			return i
	return 0


func _place_over_ground(xz: Vector2) -> void:
	var h := _array.height_at_world(Vector3(xz.x, 0.0, xz.y))
	_runtime.body.linear_velocity = Vector3.ZERO
	_runtime.body.angular_velocity = Vector3.ZERO
	_runtime.body.global_transform = Transform3D(
		Basis(), Vector3(xz.x, h + DROP_CLEARANCE_M, xz.y)
	)


## Fires a ray straight down at [param xz] and returns the height the physics
## server reports, or NAN when nothing is there.
func _ray_ground(xz: Vector2) -> float:
	var space := _runtime.body.get_world_3d().direct_space_state
	var from := Vector3(xz.x, 400.0, xz.y)
	var to := Vector3(xz.x, -200.0, xz.y)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = CollisionLayers.MASK_GROUND
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


## ===== THE MAPPING =====================================================


## The central assertion of this file: the shape the physics server holds agrees
## with the height data the deformer writes, at real world positions.
##
## Checked at several places rather than one, because a single sample agrees
## under a transpose whenever the terrain happens to be locally symmetric, and
## the spacing scale is invisible at the chunk centre — an unscaled shape is
## wrong by a factor of two in how far each sample sits from the middle, which is
## zero error at the middle itself.
func test_the_collision_shape_agrees_with_the_height_data() -> void:
	await physics_frames(2)
	var probes: Array[Vector2] = [
		SPAWN_XZ,
		SPAWN_XZ + Vector2(7.5, 0.0),
		SPAWN_XZ + Vector2(0.0, 7.5),
		SPAWN_XZ + Vector2(-11.25, 4.0),
		SPAWN_XZ + Vector2(18.0, -13.5),
	]
	for xz: Vector2 in probes:
		var by_ray := _ray_ground(xz)
		if not check_true(not is_nan(by_ray), "the ray finds ground at %s" % xz):
			continue
		var by_data := _array.height_at_world(Vector3(xz.x, 0.0, xz.y))
		# The tolerance is the interpolation difference between a ray hitting a
		# triangle and a bilinear read of the four corners, which on this
		# terrain's gradient is a few centimetres. A transpose or a missing
		# spacing scale is metres out, not centimetres.
		check_approx(by_ray, by_data, "ray and data agree at %s" % xz, 0.12)


## A transpose is the specific error the multi-point check above is aimed at, so
## it gets an assertion that names it: two points that differ only in X must
## disagree in height by what the data says, not by what swapping the axes says.
func test_the_field_is_not_transposed() -> void:
	await physics_frames(2)
	# Find a pair of probes that genuinely differ in height. A pair that happens
	# to sit at the same elevation is satisfied by a transposed mapping too, so
	# the fixture has to establish the difference before it asserts on it.
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var best := 0.0
	# A wider ladder than the claim needs, because which pair differs is a property
	# of where this spawn lands in the noise field and that moved when doc 09 §2.1's
	# world span did: at 2048 m a 12–32 m ladder found 0.9 m of relief here and at
	# 4096 it found 0.23. Searching further is the honest fix; lowering the 0.5 m
	# floor would weaken the assertion to something a transposed mapping could pass.
	for step: float in [12.0, 16.0, 20.0, 26.0, 32.0, 40.0, 48.0, 56.0, 64.0, 72.0]:
		var pa := SPAWN_XZ + Vector2(step, 0.0)
		var pb := SPAWN_XZ + Vector2(0.0, step)
		var gap := absf(
			(
				_array.height_at_world(Vector3(pa.x, 0.0, pa.y))
				- _array.height_at_world(Vector3(pb.x, 0.0, pb.y))
			)
		)
		if gap > best:
			best = gap
			a = pa
			b = pb
	if not check_true(
		best > 0.5, "the fixture terrain differs across the two axes by %.3f m" % best
	):
		return

	var ray_a := _ray_ground(a)
	var ray_b := _ray_ground(b)
	if not check_true(not is_nan(ray_a) and not is_nan(ray_b), "both rays find ground"):
		return
	check_approx(
		ray_a, _array.height_at_world(Vector3(a.x, 0.0, a.y)), "the +X probe matches its data", 0.12
	)
	check_approx(
		ray_b, _array.height_at_world(Vector3(b.x, 0.0, b.y)), "the +Z probe matches its data", 0.12
	)
	# And the two disagree with each other by the amount the data says, which a
	# swapped mapping would report with the sign reversed.
	check_approx(ray_a - ray_b, best * signf(ray_a - ray_b), "the gap survives the round trip", 0.2)


## ===== SETTLING ========================================================


## §7.1: a crater is drivable with no additional code because the suspension
## probes are shape casts against MASK_GROUND. The same is true of terrain, and
## this is the assertion that the heightfield is something an Assembly rests on
## rather than falls through.
func test_an_assembly_settles_on_the_terrain() -> void:
	_place_over_ground(SPAWN_XZ)
	await physics_frames(SETTLE_TICKS)

	var body_y := _runtime.body.global_position.y
	var ground_y := _array.height_at_world(_runtime.body.global_position)
	check_true(
		body_y > ground_y,
		"the Assembly is above the ground, not through it (body %.3f, ground %.3f)"
			% [body_y, ground_y]
	)
	check_true(
		body_y - ground_y < 3.0,
		"and resting on it rather than hovering (clearance %.3f m)" % (body_y - ground_y)
	)
	check_true(
		absf(_runtime.body.linear_velocity.y) < 1.0,
		"and it has stopped falling, |vy| = %.3f" % absf(_runtime.body.linear_velocity.y)
	)
	check_true(_grounded_contacts() > 0, "at least one contact found the ground")


## §5. Collision exists near an anchor and nowhere else — this is what stops the
## world costing 1 024 heightfield bodies.
func test_collision_is_resident_only_near_an_anchor() -> void:
	check_true(_streamer.resident_count() > 0, "chunks near the anchor are resident")
	check_true(
		_streamer.resident_count() <= GroundConstants.MAX_COLLISION_CHUNKS,
		"and the resident set respects its cap, got %d" % _streamer.resident_count()
	)
	# The far corner of the world is 2 km away and must have no collision.
	var far := Vector2(900.0, 900.0)
	check_true(is_nan(_ray_ground(far)), "no collision 900 m from anything")
	check_false(
		_streamer.is_resident(Vector2i(0, 0)),
		"and the chunk at the world corner is not resident"
	)


## ===== CRATERS =========================================================


## §7.1 and §7.3 together: a crater is a hole an Assembly can drive into, its
## collision reflects the deformation, and its floor grips worse than the ground
## it replaced.
func test_a_crater_lowers_the_collision_and_changes_the_surface() -> void:
	var target := SPAWN_XZ + Vector2(24.0, 6.0)
	await physics_frames(2)

	var before_ray := _ray_ground(target)
	if not check_true(not is_nan(before_ray), "the ground under the target exists first"):
		return
	var before_surface := _array.surface_at_world(Vector3(target.x, 0.0, target.y))

	MatchClock.tick += 1
	_deform.request_crater(Vector3(target.x, before_ray, target.y), 5.0, 1200.0)
	_deform.flush()
	await physics_frames(2)

	var after_ray := _ray_ground(target)
	if not check_true(not is_nan(after_ray), "the ground is still there after the blast"):
		return
	check_true(
		after_ray < before_ray - 0.4,
		"the collision surface dropped into the crater: %.3f -> %.3f" % [before_ray, after_ray]
	)
	check_approx(
		after_ray,
		_array.height_at_world(Vector3(target.x, 0.0, target.y)),
		"and the shape still agrees with the data after a deformation",
		0.12
	)
	check_eq(
		_array.surface_at_world(Vector3(target.x, 0.0, target.y)),
		int(SurfaceTable.Surface.DEFORMED),
		"§9.2 reclassified the crater floor"
	)
	check_ne(
		_array.surface_at_world(Vector3(target.x, 0.0, target.y)),
		before_surface,
		"which is a change from what was there"
	)


## §7.3's tactical claim, measured where it acts: a contact standing in a crater
## reads the reclassified surface, so the traction multiplier the solver is
## handed is the crater's and not the open ground's.
func test_a_contact_in_a_crater_reads_the_deformed_surface() -> void:
	var here := Vector2(-140.0, 140.0)
	_place_over_ground(here)
	await physics_frames(SETTLE_TICKS)
	var settled := _runtime.body.global_position

	var open_multiplier := _contact_surface_multiplier()
	check_approx(
		open_multiplier,
		SurfaceTable.multiplier(SurfaceTable.Surface.COMPACTED),
		"on open ground the contacts read the reference surface"
	)

	# Crater the ground the Assembly is standing on, then let the contacts
	# resolve against it.
	MatchClock.tick += 1
	_deform.request_crater(Vector3(settled.x, settled.y - 1.0, settled.z), 8.0, 2400.0)
	_deform.flush()
	await physics_frames(30)

	var crater_multiplier := _contact_surface_multiplier()
	check_approx(
		crater_multiplier,
		SurfaceTable.multiplier(SurfaceTable.Surface.DEFORMED),
		"standing in the crater, they read DEFORMED"
	)
	check_true(
		crater_multiplier < open_multiplier,
		"§7.3: driving through a fresh crater grips worse than driving around it"
	)


## The traction multiplier the solver would be handed for the first grounded
## contact, read through the same table the solver reads.
func _contact_surface_multiplier() -> float:
	for slot: int in _motion.motive_slots():
		for i: int in _motion.contact_count(slot):
			var c := _motion.contact_at(slot, i)
			if c != null and c.grounded:
				return SurfaceTable.multiplier(c.surface_id)
	return NAN


## How many contacts found the ground this tick.
func _grounded_contacts() -> int:
	var n := 0
	for slot: int in _motion.motive_slots():
		for i: int in _motion.contact_count(slot):
			var c := _motion.contact_at(slot, i)
			if c != null and c.grounded:
				n += 1
	return n
