extends TestCase
## The tracked and ambulatory families doing the thing they exist to do, on real
## ground, from shipped parts.
##
## `test_ground_assembly.gd` covers the wheeled family and
## `test_motive_force_application.gd` covers the rotary one. This file covers the
## other two, and it exists because both of them were silently inert until
## something asked them to move:
##
## [enum]
## [*] **A track had no differential drive.** `TrackSolver.drive_bias` and
##     `side_torques` were written, unit-tested, and never called — `MotiveSystem`
##     computed a suspension force and a slew resistance and drove both flanks
##     from the same undifferentiated share. A tracked Assembly could roll
##     forward and could not turn, and doc 05 §14.2 said how for two sessions
##     while nothing read it.
## [*] **A limb's probe had zero length.** §14 rule 21 requires every
##     `suspension_*` field on an ambulatory row to be zero — a leg is a
##     spring-loaded inverted pendulum, not a strut — and the probe constructor
##     sized its sweep from exactly those fields. The cast found nothing, the
##     contact never grounded, the foot was never planted, and the Assembly stood
##     still with a perfectly healthy gait clock running.
## [/enum]
##
## Neither is the kind of fault a unit test finds. Both solvers were asserted
## exactly, to the newton, against synthetic inputs nothing ever fed them.

const CORE_KEY := &"core.command.compact.t2"
const POWER_KEY := &"pmv.combustion.standard.t2"
const HUB_KEY := &"str.hub.axle_station.t2"
const TRACK_KEY := &"mot.tracked.short_bogie.t2"
const LIMB_KEY := &"mot.limb.strider.t4"

const CORE_ORIGIN := Vector3i(24, 4, 24)
const POWER_ORIGIN := Vector3i(24, 7, 24)

## Stations under the Core Module's flanks, and a bogie outboard of each. A track
## bolts on through its `-Z` drive face exactly as a wheel does; the orientation
## that carries that face inboard is derived, never written down.
const TRACK_HUBS: Array[Vector3i] = [Vector3i(22, 2, 24), Vector3i(26, 2, 24)]
const TRACK_ORIGINS: Array[Vector3i] = [Vector3i(19, 3, 24), Vector3i(28, 3, 23)]

## The walker is built high in the lattice because a limb hangs below its station
## and the lattice floor is at y = 0.
const WALKER_CORE := Vector3i(24, 14, 24)
const WALKER_POWER := Vector3i(24, 17, 24)
## Station origin and the limb that hangs off it. A station at orientation 8 puts
## its AXLE faces on ±Y, so it bolts to the Core Module's flank through a neutral
## face and offers a downward drive station; the limb's own AXLE face is its top.
const WALKER_LEGS: Array[Vector3i] = [
	Vector3i(20, 14, 23), Vector3i(20, 13, 22),
	Vector3i(26, 14, 23), Vector3i(27, 13, 22),
	Vector3i(20, 14, 26), Vector3i(20, 13, 26),
	Vector3i(26, 14, 26), Vector3i(27, 13, 26),
]
const HUB_AXLE_DOWN_ORIENTATION: int = 8

## Slack on the stance rest length, in metres. The spring is compressed by the
## Assembly's own weight, so a settled leg is a little shorter than `L₀`; this
## bounds it from the long side only.
const STANCE_TOLERANCE_M: float = 0.02

const SETTLE_TICKS: int = 300
const DRIVE_TICKS: int = 150
const GROUND_HALF_HEIGHT: float = 2.0
const GROUND_SPAN_M: float = 400.0

## Spawn points far enough apart that the two Assemblies never meet. Both live
## for the whole file: building one per test piles four tracked hulls on the same
## square metre, and they push each other over.
const TRACKED_SPAWN := Vector3(0.0, 2.0, 0.0)
const WALKER_SPAWN := Vector3(60.0, 4.0, 0.0)

var _contexts: Array[BuildContext] = []
var _runtimes: Array[AssemblyRuntime] = []
var _ground: StaticBody3D = null
var _tracked_rig: Array = []
var _walker_rig: Array = []


func before_all() -> void:
	_ground = StaticBody3D.new()
	_ground.collision_layer = CollisionLayers.LAYER_GROUND
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SPAN_M, GROUND_HALF_HEIGHT * 2.0, GROUND_SPAN_M)
	shape.shape = box
	_ground.add_child(shape)
	EventBus.get_tree().root.add_child(_ground)
	_ground.global_position = Vector3(0.0, -GROUND_HALF_HEIGHT, 0.0)
	_tracked_rig = _build_tracked()
	_walker_rig = _build_walker()


func after_all() -> void:
	for runtime: AssemblyRuntime in _runtimes:
		runtime.free()
	for ctx: BuildContext in _contexts:
		ctx.dispose()
	if _ground != null:
		_ground.queue_free()


## ===== TRACKED =========================================================


func test_a_tracked_assembly_settles_on_all_of_its_road_stations() -> void:
	var rig := await _reset(_tracked_rig, TRACKED_SPAWN)
	var runtime: AssemblyRuntime = rig[0]
	var motion: MotiveSystem = rig[1]
	var track := PartRegistry.definition_by_key(TRACK_KEY).motive_profile.track_profile

	check_eq(motion.motive_slot_count(), TRACK_ORIGINS.size(), "two bogies registered")
	for slot: int in motion.motive_slots():
		check_eq(
			motion.contact_count(slot),
			track.road_stations,
			"a bogie carries one contact per road station (§14.1)"
		)
		check_eq(
			runtime.motive_probes_of(slot).size(),
			track.road_stations,
			"and one probe for each of them"
		)

	check_true(
		runtime.body.global_transform.basis.y.dot(Vector3.UP) > 0.99,
		"it settles upright on the patch rather than rolling onto a flank"
	)
	var grounded := 0
	for slot: int in motion.motive_slots():
		for i: int in motion.contact_count(slot):
			if motion.contact_at(slot, i).grounded:
				grounded += 1
	check_eq(
		grounded,
		TRACK_ORIGINS.size() * track.road_stations,
		"and every station along both patches is in contact with the ground"
	)


func test_a_tracked_assembly_drives_straight_under_throttle() -> void:
	var rig := await _reset(_tracked_rig, TRACKED_SPAWN)
	var runtime: AssemblyRuntime = rig[0]
	var motion: MotiveSystem = rig[1]

	var heading := -runtime.body.global_transform.basis.z
	motion.input.throttle = 1.0
	await physics_frames(DRIVE_TICKS)
	var forward := -runtime.body.global_transform.basis.z
	var speed := runtime.body.linear_velocity.dot(forward)
	motion.input.throttle = 0.0

	check_true(speed > 2.0, "both flanks pull and the Assembly moves off")
	check_true(
		rad_to_deg(absf(heading.signed_angle_to(forward, Vector3.UP))) < 10.0,
		"and with no steering command it holds its heading"
	)


func test_a_tracked_assembly_pivots_on_the_spot() -> void:
	# §14.2's zero-radius turn, and the reason `side_torques` takes the throttle
	# and the steer as separate terms rather than as a product. With no throttle
	# at all, full lock drives one flank forward and the other backward: the
	# Assembly spins about itself and goes nowhere. A multiplicative mixer gives
	# both flanks nothing at zero throttle and a stopped track could not turn.
	var rig := await _reset(_tracked_rig, TRACKED_SPAWN)
	var runtime: AssemblyRuntime = rig[0]
	var motion: MotiveSystem = rig[1]

	var start := runtime.body.global_position
	var heading := -runtime.body.global_transform.basis.z
	motion.input.throttle = 0.0
	motion.input.steer = 1.0
	await physics_frames(DRIVE_TICKS)
	var turned := rad_to_deg(
		heading.signed_angle_to(-runtime.body.global_transform.basis.z, Vector3.UP)
	)
	var travelled := start.distance_to(runtime.body.global_position)
	motion.input.steer = 0.0

	check_true(absf(turned) > 20.0, "full lock at a standstill turns the Assembly")
	check_true(turned < 0.0, "to the right, which is the side positive steer asks for")
	# The radius of the arc it swept, against its own track gauge of about two
	# metres. A pivot is a turn whose radius is inside the vehicle.
	check_true(
		travelled < absf(turned) * 0.1,
		"and it turns about itself rather than driving round a circle"
	)


func test_a_tracked_assembly_resists_being_slewed() -> void:
	# §14.3. The resistance is what makes a heavy tracked build committed, and it
	# is the reason the pivot above takes a couple of seconds rather than
	# snapping round. Asserted as a torque opposing an imposed yaw, because the
	# behaviour it produces is an absence of motion and that is hard to see.
	var rig := await _reset(_tracked_rig, TRACKED_SPAWN)
	var runtime: AssemblyRuntime = rig[0]
	var motion: MotiveSystem = rig[1]

	runtime.body.angular_velocity = Vector3(0.0, 1.0, 0.0)
	await physics_frames(30)
	check_true(
		runtime.body.angular_velocity.y < 1.0,
		"an imposed yaw is bled off rather than carried"
	)
	check_true(
		runtime.body.angular_velocity.y > -1.0,
		"and never reversed, which would make it a brake rather than a resistance"
	)


## ===== AMBULATORY ======================================================


func test_a_walker_stands_on_its_feet_rather_than_on_its_shins() -> void:
	# The failure this replaces: a limb whose occupancy spanned the fully
	# extended leg baked a 2.0 m collider around a machine that stands 1.63 m
	# tall, so the Assembly rested on its own legs with the stance spring never
	# compressing. A limb occupies its hip and thigh; its reach is
	# `leg_length_m`, exactly as a rotor occupies its mast and not its disc.
	var rig := await _reset(_walker_rig, WALKER_SPAWN)
	var runtime: AssemblyRuntime = rig[0]
	var motion: MotiveSystem = rig[1]
	var limb := PartRegistry.definition_by_key(LIMB_KEY).motive_profile.limb_profile

	check_eq(motion.motive_slot_count(), 4, "four limbs registered")
	for slot: int in motion.motive_slots():
		check_eq(
			motion.family_of(slot),
			PartEnums.LocomotionMode.AMBULATORY,
			"and each dispatches to the gait solver"
		)
		var probe := runtime.motive_probes_of(slot)[0]
		check_approx(
			probe.target_position.y,
			-limb.leg_length_m,
			"whose probe sweeps the length of the leg, not of a suspension it has none of"
		)

	check_true(
		runtime.body.global_transform.basis.y.dot(Vector3.UP) > 0.99, "it stands upright"
	)
	var planted := 0
	for slot: int in motion.motive_slots():
		var contact := motion.contact_at(slot, 0)
		check_true(contact.grounded, "slot %d has found the ground" % slot)
		# Against the stance [b]rest[/b] length, not against full extension, and
		# the difference is the whole assertion. A leg standing at 1.87 m of a
		# 1.90 m reach is inside its full extension and is carrying nothing: the
		# spring in §13.6 cannot pull, so a leg longer than `L₀` produces zero
		# force and the Assembly is resting on its own thigh colliders with a
		# perfectly healthy gait clock running. That is exactly the state §4.6
		# was supposed to have ended, and this file asserted its way past it for
		# six sessions because full extension is a bound anything satisfies.
		check_true(
			contact.distance_m < limb.stance_rest_length_m() + STANCE_TOLERANCE_M,
			(
				"and is standing on it with the spring loaded: %.3f m against a rest of %.3f"
				% [contact.distance_m, limb.stance_rest_length_m()]
			)
		)
		if motion.limb_state(slot).planted:
			planted += 1
	# §13.4: "gait is frozen, every foot planted". Every one, not the 62% of the
	# cycle that happens to be in stance when the clock stops — the document
	# calls the standing state the only one in which every limb contributes
	# stance force at once, and that is what makes a stationary walk rock-solid.
	check_eq(planted, motion.motive_slot_count(), "on every foot, not just some")


func test_a_walker_walks_forward_when_told_to() -> void:
	var rig := await _reset(_walker_rig, WALKER_SPAWN)
	var runtime: AssemblyRuntime = rig[0]
	var motion: MotiveSystem = rig[1]

	var start := runtime.body.global_position
	var height := runtime.body.global_position.y
	motion.input.throttle = 1.0
	await physics_frames(DRIVE_TICKS)
	var forward := -runtime.body.global_transform.basis.z
	var travelled := start.distance_to(runtime.body.global_position)
	motion.input.throttle = 0.0

	check_true(travelled > 1.0, "the gait carries the Assembly across the ground")
	check_true(
		runtime.body.linear_velocity.dot(forward) > 0.5, "in the direction it is facing"
	)
	# Walking, not falling: the chassis stays at roughly the height it stood at.
	check_true(
		absf(runtime.body.global_position.y - height) < 0.5,
		"and stays up while it does it rather than collapsing onto its hull"
	)


func test_a_walker_spreads_its_limbs_around_the_gait_cycle() -> void:
	# §13.3. Four limbs at four evenly spaced offsets, with the right side
	# reversed so that diagonal pairs move together — the trot every quadruped
	# falls into. Asserted as the set of offsets rather than as four numbers,
	# because which slot gets which phase depends on where the builder put them.
	var rig := await _reset(_walker_rig, WALKER_SPAWN)
	var motion: MotiveSystem = rig[1]
	var offsets := PackedFloat32Array()
	for slot: int in motion.motive_slots():
		offsets.append(motion.limb_state(slot).phase_offset)
	offsets.sort()
	check_eq(offsets.size(), 4, "four limbs carry four offsets")
	for i: int in offsets.size():
		check_approx(
			offsets[i], float(i) * 0.25, "evenly spread around the cycle", 1e-4
		)


## ===== FIXTURES ========================================================


## A two-bogie tracked Assembly with a Prime Mover, built through the validator.
func _build_tracked() -> Array:
	var ctx := BuildContext.with_physics(31)
	_contexts.append(ctx)
	PlacementValidator.commit(
		ctx, PlacementCandidate.create(PartRegistry.definition_by_key(CORE_KEY), CORE_ORIGIN, 0)
	)
	PlacementValidator.commit(
		ctx,
		PlacementCandidate.create(PartRegistry.definition_by_key(POWER_KEY), POWER_ORIGIN, 0)
	)
	var hub := PartRegistry.definition_by_key(HUB_KEY)
	for cell: Vector3i in TRACK_HUBS:
		PlacementValidator.commit(ctx, PlacementCandidate.create(hub, cell, 0))
	var track := PartRegistry.definition_by_key(TRACK_KEY)
	for i: int in TRACK_ORIGINS.size():
		var inboard := Vector3.RIGHT if TRACK_ORIGINS[i].x < CORE_ORIGIN.x else Vector3.LEFT
		PlacementValidator.commit(
			ctx,
			PlacementCandidate.create(track, TRACK_ORIGINS[i], _drive_face_orientation(inboard))
		)
	return _rig(ctx, TRACKED_SPAWN)


## A four-limbed Assembly, each limb hanging from its own downward station.
func _build_walker() -> Array:
	var ctx := BuildContext.with_physics(32)
	_contexts.append(ctx)
	PlacementValidator.commit(
		ctx, PlacementCandidate.create(PartRegistry.definition_by_key(CORE_KEY), WALKER_CORE, 0)
	)
	PlacementValidator.commit(
		ctx,
		PlacementCandidate.create(PartRegistry.definition_by_key(POWER_KEY), WALKER_POWER, 0)
	)
	var hub := PartRegistry.definition_by_key(HUB_KEY)
	var limb := PartRegistry.definition_by_key(LIMB_KEY)
	for i: int in WALKER_LEGS.size() / 2:
		PlacementValidator.commit(
			ctx,
			PlacementCandidate.create(hub, WALKER_LEGS[i * 2], HUB_AXLE_DOWN_ORIENTATION)
		)
		PlacementValidator.commit(
			ctx, PlacementCandidate.create(limb, WALKER_LEGS[i * 2 + 1], 0)
		)
	return _rig(ctx, WALKER_SPAWN)


## Adopts [param ctx] into a runtime with a wired motion system, dropped in at
## [param spawn]. Returns `[runtime, motion]`.
func _rig(ctx: BuildContext, spawn: Vector3) -> Array:
	var runtime := AssemblyRuntime.new()
	EventBus.get_tree().root.add_child(runtime)
	_runtimes.append(runtime)
	runtime.adopt(ctx)
	runtime.apply_mass_properties(MassSolver.compute(runtime.states, runtime.graph))

	var motion := MotiveSystem.new()
	motion.runtime = runtime
	motion.input = ControlInput.new()
	motion.power = PowerSystem.new()
	motion.power.recompute(runtime.states, runtime.graph.alive)
	runtime.add_child(motion)
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var def := runtime.definition_at(slot)
		if def != null and def.part_class == PartEnums.PartClass.MOTIVE_ASSEMBLY:
			motion.register(slot, def, runtime.states[slot])
	motion.reassign_gait_phases()
	runtime.body.global_position = spawn
	return [runtime, motion]


## Puts [param rig] back on its spawn point, at rest and settled, so that each
## test starts from the same state whatever the one before it did. Methods run in
## sorted order and may not depend on each other.
func _reset(rig: Array, spawn: Vector3) -> Array:
	var runtime: AssemblyRuntime = rig[0]
	var motion: MotiveSystem = rig[1]
	motion.input.throttle = 0.0
	motion.input.steer = 0.0
	motion.input.brake = 0.0
	runtime.body.global_transform = Transform3D(Basis(), spawn)
	runtime.body.linear_velocity = Vector3.ZERO
	runtime.body.angular_velocity = Vector3.ZERO
	for slot: int in motion.motive_slots():
		for i: int in motion.contact_count(slot):
			motion.contact_at(slot, i).contact_omega = 0.0
	await physics_frames(SETTLE_TICKS)
	return rig


## The orientation carrying a part's `-Z` drive face onto [param face], upright.
func _drive_face_orientation(face: Vector3) -> int:
	for i: int in SyndicateConstants.ORIENTATION_COUNT:
		var basis := OrientationTable.basis_for(i)
		if not (basis * Vector3.FORWARD).is_equal_approx(face):
			continue
		if (basis * Vector3.UP).is_equal_approx(Vector3.UP):
			return i
	return 0
