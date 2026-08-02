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
## [b]It found three things, and all three are now fixed.[/b]
##
## [enum]
## [*] All four `mot.*` parts carried the AXLE [i]station's[/i] `accepts_classes`
##     restriction on their own drive face, and since [code]_check_mating[/code]
##     tests the restriction in both directions, every Motive Assembly in the
##     registry rejected the only class §4.2 lets it mount on. Nothing with
##     locomotion could be built at all.
## [*] `suspension_rest_length_m` was authored below `contact_radius_m`, so the
##     probe could never register compression, no normal force reached the
##     contact, and full throttle moved the Assembly exactly nothing. Doc 05 §6.1
##     now states the relationship and §14 rule 23 enforces it.
## [*] Every wheel steered, which is not a steering system — four contact patches
##     pointing the same way translate the Assembly sideways with its nose still
##     forward. `mot.wheeled.fixed_rear.t2` is the rear axle, and the difference
##     between the two rows is one authored number.
## [/enum]

const CORE_KEY := &"core.command.compact.t2"
const HUB_KEY := &"str.hub.axle_station.t2"
const WHEEL_KEY := &"mot.wheeled.allroad.t2"
const REAR_KEY := &"mot.wheeled.fixed_rear.t2"
const POWER_KEY := &"pmv.combustion.standard.t2"

## On the Core Module's roof, on the centreline, so it does not bias the build.
const POWER_ORIGIN := Vector3i(24, 7, 24)

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
## The right-hand pivots sit one cell forward of the left-hand ones, and that is
## a correction rather than a slip. A disc's authored centre of mass is the
## centre of an even-sized footprint, so the two mirrored orientations put it a
## quarter-cell apart on Z; matching the cells would leave the two flanks'
## contact patches 0.25 m out of line, which loads them unevenly and makes the
## Assembly veer under power. Matching the *probes* is what makes it a mirror.
const WHEEL_ORIGINS: Array[Vector3i] = [
	Vector3i(19, 3, 22), Vector3i(19, 3, 28), Vector3i(28, 3, 21), Vector3i(28, 3, 27)
]

## Pivot Z below which a wheel is on the front axle and steers.
const FRONT_AXLE_Z: int = 24

## 380 kg Core Module, 355 kg Prime Mover, four 29 kg stations, two 68 kg steered
## discs and two 62 kg fixed ones.
const EXPECTED_MASS_KG: float = 911.0

## Doc 05 §6.1's probe radius ratio, quoted rather than imported.
##
## Importing [constant AssemblyRuntime.PROBE_RADIUS_RATIO] here would make the
## assertion below a tautology — it moves with whatever the source says, and a
## probe sphere five times too big passes. Fault injection said exactly that.
## A published constant is asserted against the document, once, and the code is
## asserted against the assertion.
const DOC_PROBE_RADIUS_RATIO: float = 0.85

## Core, Prime Mover, four stations, four discs.
const EXPECTED_PART_COUNT: int = 10

## Ticks to fall two metres and settle onto the contact.
const SETTLE_TICKS: int = 260

## A second of driving: long enough to reach a real speed, short enough that a
## file with six driving tests in it still runs in seconds.
const DRIVE_TICKS: int = 150

## Enough throttle to move cleanly, well below the wheelspin threshold.
const PART_THROTTLE: float = 0.25

## Ticks to sample the steer sweep at. Chosen so the wheels are part-way to the
## stop: 140 deg/s reaches a 32 degree lock in 0.23 s, and this is 0.1 s.
const STEER_SAMPLE_TICKS: int = 6

## A short launch — under a second — so that the comparison is about getting off
## the mark rather than about terminal speed, which the two runs share.
const LAUNCH_TICKS: int = 45

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
		"a Core Module, a Prime Mover, four AXLE stations and four Motive Assemblies"
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
	await _at_rest()

	check_true(
		_runtime.body.global_transform.basis.y.dot(Vector3.UP) > 0.999,
		"a symmetric four-contact build settles upright rather than tipping"
	)
	# A four-spring Assembly on a flat slab never goes exactly still — the
	# suspension keeps a residual oscillation that §10.3's settle scaling damps
	# rather than kills. What matters is that it is settling rather than driving
	# away, so the assertion is on the scale of the motion, not on zero.
	check_true(
		_runtime.body.linear_velocity.length() < 0.25,
		"and is settling in place rather than drifting off"
	)
	# Ride height is where the springs settle: the probe sits its own local height
	# below the body, and the surface is one contact distance below that. Derived
	# from what the probes actually report rather than recorded, because the sag
	# depends on the build's weight and this fixture's weight will change.
	var contact := _motion.contact_at(_motion.motive_slots()[0], 0)
	check_approx(
		_runtime.body.global_position.y,
		contact.distance_m - _probe_local_y,
		"and rests on its springs at the height they settled to",
		0.05
	)


func test_every_probe_finds_the_ground_beneath_its_wheel() -> void:
	await _at_rest()
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY)
	for slot: int in _motion.motive_slots():
		var contact := _motion.contact_at(slot, 0)
		if not check_true(contact.grounded, "slot %d found the surface" % slot):
			continue
		# Between the rolling radius and the full rest length: closer than the
		# rest length means the spring is compressed and carrying load, and no
		# closer than the radius means the disc is not inside the ground.
		var profile := wheel.motive_profile
		check_true(
			contact.distance_m > profile.contact_radius_m,
			"the disc is above the surface rather than buried in it"
		)
		check_true(
			contact.distance_m < profile.suspension_rest_length_m,
			"and inside its rest length, so the spring is carrying"
		)
		check_true(
			contact.normal_world.dot(Vector3.UP) > 0.99, "with the surface normal upward"
		)


## ===== THE FINDING =====================================================


func test_the_suspension_carries_the_whole_build() -> void:
	await _at_rest()
	# The inversion of the measurement this file used to record. Doc 05 §6.1 now
	# requires `suspension_rest_length_m > contact_radius_m`; below it the probe
	# can never register compression and every number downstream is zero.
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY)
	var profile := wheel.motive_profile
	check_true(
		profile.suspension_rest_length_m > profile.contact_radius_m,
		"the authored rest length reaches past the rolling radius"
	)

	var carried := 0.0
	for slot: int in _motion.motive_slots():
		var contact := _motion.contact_at(slot, 0)
		var def := _runtime.definition_at(slot)
		check_true(
			SuspensionSolver.compression(def.motive_profile, contact) > 0.0,
			"slot %d consumes travel" % slot
		)
		check_true(contact.normal_force_n > 0.0, "and carries load")
		carried += contact.normal_force_n
	# The springs hold the Assembly up and nothing else does. Asserted against
	# the weight rather than against a recorded number, so a change to any part's
	# mass moves the expectation with it.
	check_approx(
		carried,
		EXPECTED_MASS_KG * SyndicateConstants.GRAVITY_MPS2,
		"and between them they carry the build's whole weight",
		EXPECTED_MASS_KG * SyndicateConstants.GRAVITY_MPS2 * 0.10
	)


func test_part_throttle_drives_the_assembly_forward_in_a_straight_line() -> void:
	await _at_rest()
	_motion.input.throttle = PART_THROTTLE
	await physics_frames(DRIVE_TICKS)
	var forward := -_runtime.body.global_transform.basis.z
	var speed := _runtime.body.linear_velocity.dot(forward)
	var sideways := _runtime.body.linear_velocity.dot(_runtime.body.global_transform.basis.x)
	_motion.input.throttle = 0.0

	check_true(speed > 2.0, "a quarter throttle moves it forward at a real speed")
	check_true(
		absf(sideways) < speed * 0.1,
		"and it goes where it is pointing rather than sliding across the ground"
	)


func test_the_brake_stops_it() -> void:
	await _at_rest()
	_motion.input.throttle = PART_THROTTLE
	await physics_frames(DRIVE_TICKS)
	var rolling := _runtime.body.linear_velocity.length()
	_motion.input.throttle = 0.0
	_motion.input.brake = 1.0
	await physics_frames(DRIVE_TICKS)
	var braked := _runtime.body.linear_velocity.length()
	_motion.input.brake = 0.0

	check_true(rolling > 2.0, "it was moving")
	check_true(braked < rolling * 0.5, "and the brake took most of it off")


func test_steering_yaws_the_assembly_toward_the_side_it_is_asked_for() -> void:
	# §7.1's contact frame doing its job. Positive steer is right on every input
	# device (doc 11 §7.2), and a positive rotation about the surface normal
	# carries the forward axis *left*, so the sign here is the whole assertion:
	# a steering model that turned the wrong way would pass every other test in
	# this file.
	await _at_rest()
	_motion.input.throttle = PART_THROTTLE
	_motion.input.steer = 1.0
	await physics_frames(DRIVE_TICKS)
	var yaw_rate := _runtime.body.angular_velocity.y
	var front := _motion.motive_slots()[0]
	var steer := _motion.steer_angle_deg(front)
	_motion.input.throttle = 0.0
	_motion.input.steer = 0.0

	var profile := PartRegistry.definition_by_key(WHEEL_KEY).motive_profile
	check_approx(steer, profile.max_steer_angle_deg, "the front wheels reach full lock", 0.5)
	# Forward is -Z and right is +X, so turning right is a *negative* rotation
	# about +Y under the right-hand rule.
	check_true(yaw_rate < -0.2, "and a right-hand lock yaws the Assembly to the right")


func test_the_wheels_take_time_to_reach_full_lock() -> void:
	# `steer_rate_deg_s` is what stops an Assembly changing direction instantly,
	# and a test that waits for the lock to settle cannot tell a rate limit from
	# an assignment. Sampled part-way through the sweep instead, against the
	# authored rate: at 140 deg/s a 32 degree lock takes 0.23 s, so a tenth of a
	# second in the wheels should be about two thirds of the way there and
	# certainly not at the stop.
	await _at_rest()
	var profile := PartRegistry.definition_by_key(WHEEL_KEY).motive_profile
	var front := _motion.motive_slots()[0]
	_motion.input.steer = 1.0
	await physics_frames(STEER_SAMPLE_TICKS)
	var part_way := _motion.steer_angle_deg(front)
	_motion.input.steer = 0.0

	var elapsed := float(STEER_SAMPLE_TICKS) * SyndicateConstants.PHYSICS_DT
	check_approx(
		part_way,
		profile.steer_rate_deg_s * elapsed,
		"the lock advances at the authored rate rather than arriving at once",
		1.0
	)
	check_true(part_way < profile.max_steer_angle_deg, "and is not at the stop yet")


func test_a_rear_wheel_does_not_steer_at_all() -> void:
	await _at_rest()
	_motion.input.steer = 1.0
	await physics_frames(DRIVE_TICKS)
	_motion.input.steer = 0.0
	for slot: int in _motion.motive_slots():
		var def := _runtime.definition_at(slot)
		if def.part_key == REAR_KEY:
			check_approx(
				_motion.steer_angle_deg(slot), 0.0, "the fixed rear axle stays straight"
			)


func test_full_throttle_spins_the_wheels_and_lightens_the_nose() -> void:
	# Two emergent behaviours, neither of them written anywhere as a feature.
	#
	# The drive torque this Prime Mover makes is more than the contact patches
	# can hold at a standstill, so the wheels accelerate past the peak of the
	# friction curve and settle on its falling side: a burnout. And because
	# traction is applied at the contact and the centre of mass is above it, the
	# couple pitches the Assembly nose-up and unloads the front axle — the first
	# part of a wheelie, arriving from the same rigid body and the same offset
	# forces that produce brake dive.
	await _at_rest()
	var resting_front := _motion.contact_at(_motion.motive_slots()[0], 0).normal_force_n
	# The aid off, which is the only way to see either of these. With it on the
	# limiter holds the patch inside its allowance and there is no burnout to
	# have — that is `test_traction_control_stops_the_wheels_running_away`.
	_motion.input.traction_control = 0.0
	_motion.input.throttle = 1.0
	await physics_frames(DRIVE_TICKS)

	var wheel := PartRegistry.definition_by_key(WHEEL_KEY).motive_profile
	var forward := -_runtime.body.global_transform.basis.z
	var road_speed := _runtime.body.linear_velocity.dot(forward)
	var patch_speed := (
		_motion.contact_at(_motion.motive_slots()[0], 0).contact_omega * wheel.contact_radius_m
	)
	var front_load := _motion.contact_at(_motion.motive_slots()[0], 0).normal_force_n
	_motion.input.throttle = 0.0
	_motion.input.traction_control = 1.0

	check_true(
		patch_speed > road_speed * 1.5,
		"the contact patch is outrunning the road, which is what a burnout is"
	)
	# Down to about a third of its resting load on this build. A full wheelie is
	# not a scripted state here and does not need to be — the nose comes up
	# because the tractive force acts at the ground while the centre of mass is
	# most of a metre above it, and the same offset-force model makes braking
	# dive. A lighter Assembly on the same Prime Mover lifts the axle outright.
	check_true(
		front_load < resting_front * 0.5,
		"and the nose has lightened sharply: load transferred off the front axle"
	)


## Puts the Assembly back on the spot, at rest, so that a drive test starts from
## a known state whatever the test before it did. Test methods run in sorted
## order and must not depend on each other.
func _at_rest() -> void:
	_runtime.body.global_transform = Transform3D(Basis(), Vector3(0.0, 1.0, 0.0))
	_runtime.body.linear_velocity = Vector3.ZERO
	_runtime.body.angular_velocity = Vector3.ZERO
	_motion.input.throttle = 0.0
	_motion.input.steer = 0.0
	_motion.input.brake = 0.0
	_motion.input.traction_control = 1.0
	# The contacts' angular rates are integrated across ticks and survive a
	# teleport. A wheel left spinning at 90 rad/s by the burnout test would drive
	# the next one off the mark before it began.
	for slot: int in _motion.motive_slots():
		for i: int in _motion.contact_count(slot):
			_motion.contact_at(slot, i).contact_omega = 0.0
	await physics_frames(SETTLE_TICKS)


## ===== TRACTION CONTROL (doc 05 §7.6) ==================================


func test_traction_control_stops_the_wheels_running_away() -> void:
	# The same full-throttle launch as the burnout test, with the aid on. The
	# limiter is the whole difference between the two, and the pair of them is
	# the assertion: neither one alone shows that the aid is doing anything
	# rather than the Assembly simply not having the torque to spin its wheels.
	await _at_rest()
	_motion.input.traction_control = 1.0
	_motion.input.throttle = 1.0
	await physics_frames(DRIVE_TICKS)

	var wheel := PartRegistry.definition_by_key(WHEEL_KEY).motive_profile
	var forward := -_runtime.body.global_transform.basis.z
	var road := _runtime.body.linear_velocity.dot(forward)
	var patch := (
		_motion.contact_at(_motion.motive_slots()[0], 0).contact_omega * wheel.contact_radius_m
	)
	_motion.input.throttle = 0.0

	check_true(road > 2.0, "the Assembly still gets going")
	check_true(
		patch - road < TractionControl.TARGET_SLIP_RATIO * road + 2.0,
		"and the patch stays inside its slip allowance instead of running away"
	)


func test_traction_control_keeps_full_throttle_pointing_straight() -> void:
	# The wander, which is what the aid was asked for. Deep slip is unstable by
	# construction — past the friction peak more slip means less force — so once
	# one flank hooks up before the other the Assembly yaws away. Holding both
	# patches inside the allowance is what stops that, and the yaw controller
	# trims what is left.
	await _at_rest()
	var straight := -_runtime.body.global_transform.basis.z
	_motion.input.traction_control = 1.0
	_motion.input.throttle = 1.0
	await physics_frames(DRIVE_TICKS)
	var drifted := rad_to_deg(
		absf(straight.signed_angle_to(-_runtime.body.global_transform.basis.z, Vector3.UP))
	)
	_motion.input.throttle = 0.0

	check_true(drifted < 8.0, "full throttle holds a heading with the aid on")


func test_the_aid_can_be_turned_off() -> void:
	# Same launch, same ticks, aid off. Asserted against the managed run above
	# rather than against a number, because what matters is that the two differ:
	# a test that only measured the unmanaged case would pass with the whole of
	# §7.6 deleted.
	await _at_rest()
	_motion.input.traction_control = 1.0
	_motion.input.throttle = 1.0
	await physics_frames(DRIVE_TICKS)
	var managed := _peak_slip()

	await _at_rest()
	_motion.input.traction_control = 0.0
	_motion.input.throttle = 1.0
	await physics_frames(DRIVE_TICKS)
	var unmanaged := _peak_slip()
	_motion.input.throttle = 0.0
	_motion.input.traction_control = 1.0

	check_true(
		unmanaged > managed * 2.0,
		"the driver gets every newton-metre and the wheels show it"
	)


func test_the_aid_does_not_cost_the_launch() -> void:
	# The other half of §7.6's launch floor, and the reason it exists. A slip
	# *ratio* is meaningless at a standstill, so a limiter that believed it would
	# throttle a stopped Assembly to a crawl and take several seconds to get
	# going. Asserted against the unmanaged run rather than against a speed: the
	# aid may cost some acceleration and may not cost most of it, and removing
	# the floor from the allowance costs most of it.
	await _at_rest()
	_motion.input.traction_control = 0.0
	_motion.input.throttle = 1.0
	await physics_frames(LAUNCH_TICKS)
	var open_loop := _forward_speed()

	await _at_rest()
	_motion.input.traction_control = 1.0
	_motion.input.throttle = 1.0
	await physics_frames(LAUNCH_TICKS)
	var managed := _forward_speed()
	_motion.input.throttle = 0.0

	check_true(open_loop > 1.0, "the unmanaged launch is a launch")
	check_true(
		managed > open_loop * 0.6,
		"and the managed one keeps most of it rather than bogging down"
	)


## Speed along the Assembly's own forward axis, in m/s.
func _forward_speed() -> float:
	return _runtime.body.linear_velocity.dot(-_runtime.body.global_transform.basis.z)


func test_the_yaw_controller_brakes_the_flank_that_opposes_the_error() -> void:
	# §7.6's sign, isolated from the physics. Braking the left flank yaws the
	# Assembly left, so an Assembly rotating right harder than it was asked to is
	# corrected on the left — and a controller that braked the other side would
	# add to the spin it is supposed to be trimming, which no test of "does it
	# drive straight" reliably distinguishes from a controller that is off.
	check_eq(
		TractionControl.brake_side(-1.0), -1, "yawing right too fast brakes the left flank"
	)
	check_eq(TractionControl.brake_side(1.0), 1, "and yawing left too fast brakes the right")

	# Positive steer is right, and right is a negative yaw rate.
	var target := TractionControl.target_yaw_rate_rad_s(10.0, deg_to_rad(20.0), 2.5)
	check_true(target < 0.0, "a right-hand lock asks for a right-hand yaw")
	check_approx(
		target, -10.0 * tan(deg_to_rad(20.0)) / 2.5, "at the bicycle model's rate"
	)


func test_the_yaw_controller_leaves_a_straight_run_alone() -> void:
	# The deadband. An aid that trimmed continuously would have the brakes on
	# every tick of every straight, and the Assembly would be slower for it with
	# nothing to show.
	check_approx(
		TractionControl.yaw_error_rad_s(
			TractionControl.YAW_DEADBAND_RAD_S * 0.5, 0.0, INF
		),
		0.0,
		"an error inside the deadband is no error"
	)
	check_true(
		absf(TractionControl.yaw_error_rad_s(1.0, 0.0, INF)) > 0.0,
		"and one outside it is"
	)
	# The grip clamp: a lock the contacts could never follow is not chased.
	check_approx(
		TractionControl.yaw_error_rad_s(0.0, -9.0, 1.0),
		1.0 - TractionControl.YAW_DEADBAND_RAD_S,
		"a yaw target past the grip limit is clamped to it before the error is taken"
	)


func test_the_wheelbase_is_derived_from_where_the_contacts_are() -> void:
	# The bicycle model needs one, and it is a property of the build. Four cells
	# of Z between the axles on this fixture, which is 1.5 m.
	var probes := PackedFloat32Array()
	for slot: int in _motion.motive_slots():
		probes.append(_runtime.motive_probes_of(slot)[0].position.z)
	probes.sort()
	check_approx(
		_motion.wheelbase_m(),
		probes[probes.size() - 1] - probes[0],
		"the wheelbase spans the outermost contacts"
	)
	check_true(_motion.wheelbase_m() > 0.5, "and is a real distance rather than zero")


## Highest patch overspeed seen on the front-left contact, in m/s.
func _peak_slip() -> float:
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY).motive_profile
	var contact := _motion.contact_at(_motion.motive_slots()[0], 0)
	var forward := -_runtime.body.global_transform.basis.z
	return (
		contact.contact_omega * wheel.contact_radius_m
		- _runtime.body.linear_velocity.dot(forward)
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
