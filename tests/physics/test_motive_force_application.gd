extends TestCase
## [MotiveSystem] applying a force to a real rigid body, integrated by the
## physics server — the step every other test of the motion layer stops short of.
##
## The solvers are asserted exactly by their own unit tests, and
## [code]tests/integration/test_motive_system.gd[/code] asserts the dispatch and
## the bookkeeping. What neither can reach is the last hop: whether the force a
## family solved actually arrives on [code]ChassisBody[/code] with the magnitude,
## the direction, and the offset it was solved with. Until the suite could step
## physics that hop was the largest untested surface in the project, and
## [code]apply_force[/code] with a transposed argument, a dropped offset, or a
## world-space vector applied in body space would have passed every test there
## was.
##
## The rotary family is the subject because it is the one that needs no ground
## contact: a disc produces thrust from its own state, so this file tests the
## force path without also depending on doc 05 §6's suspension.
##
## Method: one tick, from rest, with gravity and damping removed. From rest the
## damping term is zero and the body has not rotated, so `Δv = F·dt/m` holds
## exactly rather than approximately, and the assertion is an equality rather
## than a trend. The thrust value itself is [RotorSolver]'s and is not what is
## under test here — [code]tests/unit/test_rotor_solver.gd[/code] owns that. What
## is under test is that the number reaches the body.

const CORE_KEY := &"core.command.compact.t2"
const POWER_KEY := &"pmv.combustion.standard.t2"
const ROTOR_KEY := &"mot.rotor.coaxial_mid.t3"

const CORE_ORIGIN := Vector3i(24, 4, 24)
## Deliberately off the Core Module's centreline on both X and Z. A disc over the
## centre of mass would apply pure lift and
## [method test_the_thrust_is_applied_at_the_disc_rather_than_the_origin] would
## have nothing to see — the offset is the assertion.
const POWER_ORIGIN := Vector3i(21, 1, 20)
const ROTOR_ORIGIN := Vector3i(20, 4, 21)

## 380 kg Core Module, 355 kg Prime Mover, 65 kg disc.
const EXPECTED_MASS_KG: float = 800.0

var _ctx: BuildContext = null
var _runtime: AssemblyRuntime = null
var _motion: MotiveSystem = null
var _rotor_slot: int = SyndicateConstants.INVALID_SLOT


func before_all() -> void:
	_ctx = BuildContext.with_physics(2)
	PlacementValidator.commit(
		_ctx,
		PlacementCandidate.create(PartRegistry.definition_by_key(CORE_KEY), CORE_ORIGIN, 0)
	)
	PlacementValidator.commit(
		_ctx,
		PlacementCandidate.create(PartRegistry.definition_by_key(POWER_KEY), POWER_ORIGIN, 0)
	)
	PlacementValidator.commit(
		_ctx,
		PlacementCandidate.create(PartRegistry.definition_by_key(ROTOR_KEY), ROTOR_ORIGIN, 0)
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
			_rotor_slot = slot

	# Free flight, and nothing between the applied force and the integrator.
	# Replacing the damp rather than zeroing the project default is deliberate:
	# a project-wide damping change would otherwise silently loosen this test.
	_runtime.body.gravity_scale = 0.0
	_runtime.body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_runtime.body.linear_damp = 0.0
	_runtime.body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_runtime.body.angular_damp = 0.0
	_runtime.body.global_position = Vector3(0.0, 50.0, 0.0)


func after_all() -> void:
	if _runtime != null:
		_runtime.free()
	if _ctx != null:
		_ctx.dispose()


func test_the_fixture_is_a_rotary_assembly_with_power_to_spin_it() -> void:
	check_ne(_rotor_slot, SyndicateConstants.INVALID_SLOT, "a disc registered")
	check_eq(
		_motion.family_of(_rotor_slot),
		PartEnums.LocomotionMode.ROTARY,
		"and dispatches to the rotary family"
	)
	check_eq(
		_runtime.motive_probes_of(_rotor_slot).size(),
		0,
		"a disc touches nothing, so it sweeps no probe"
	)
	check_approx(_motion.power.available_fraction(), 1.0, "the Prime Mover covers the draw")
	check_approx(_runtime.mass_properties.total_mass, EXPECTED_MASS_KG, "the solved mass")


func test_a_spinning_disc_accelerates_the_body_by_its_own_thrust() -> void:
	var disc := _spun_up()
	_motion.input.throttle = 1.0
	_motion.input.collective = 1.0

	await physics_frames(1)

	var dv := _runtime.body.linear_velocity
	var expected := disc.last_thrust_n / EXPECTED_MASS_KG * SyndicateConstants.PHYSICS_DT
	check_true(disc.last_thrust_n > 0.0, "the disc solved a thrust to apply")
	check_approx(dv.length(), expected, "one tick of it changes velocity by F·dt/m", 1e-4)
	check_approx(dv.y, expected, "along the disc axis, which is up at orientation 0", 1e-4)
	check_approx(dv.x, 0.0, "with nothing sideways", 1e-4)
	check_approx(dv.z, 0.0, "and nothing fore or aft", 1e-4)


func test_the_thrust_is_applied_at_the_disc_rather_than_the_origin() -> void:
	# §11 invariant 13: a rotor off the centre of mass pitches the Assembly. If
	# the offset were dropped from `apply_force` the linear result above would be
	# identical and only this would notice — which is exactly the shape of bug
	# that survives a test suite with no physics step in it.
	var disc := _spun_up()
	_motion.input.throttle = 1.0
	_motion.input.collective = 1.0

	await physics_frames(1)

	var lever := (
		_runtime.body.global_transform * MassSolver.part_com_local(
			_runtime.states[_rotor_slot], _runtime.definition_at(_rotor_slot)
		)
		- _runtime.body.global_position
		- _runtime.mass_properties.com_local
	)
	var torque := lever.cross(Vector3.UP * disc.last_thrust_n)
	var omega := _runtime.body.angular_velocity

	check_true(omega.length() > 0.0, "the body picked up rotation from the offset thrust")
	# Sign rather than magnitude: the server integrates against the diagonal
	# tensor, so omega is not parallel to the torque, but a positive-diagonal
	# tensor cannot flip a component's sign.
	check_true(
		signf(omega.x) == signf(torque.x), "pitching the way the lever arm says it should"
	)
	check_true(signf(omega.z) == signf(torque.z), "and rolling the way it says too")


func test_a_disc_at_rest_applies_nothing() -> void:
	# The rejection half. A test that only ever asserts a force appears passes
	# against a system that applies one unconditionally.
	var disc := _motion.disc_state(_rotor_slot)
	disc.omega_rad_s = 0.0
	disc.collective_deg = 0.0
	_motion.input.throttle = 0.0
	_motion.input.collective = 0.0
	_runtime.body.linear_velocity = Vector3.ZERO
	_runtime.body.angular_velocity = Vector3.ZERO

	await physics_frames(1)

	check_approx(disc.last_thrust_n, 0.0, "a stationary disc solves no thrust")
	check_approx(
		_runtime.body.linear_velocity.length(), 0.0, "and the body does not move", 1e-4
	)


## ===== FIXTURES ========================================================


## Puts the disc at its nominal rate and full collective without waiting out the
## spool, and returns the body to rest so that one tick's `Δv` is the whole
## effect. Setting the state directly rather than spooling for ten seconds keeps
## the test deterministic and keeps it under a second of wall time.
func _spun_up() -> RotorDiscState:
	var rotor := _runtime.definition_at(_rotor_slot).motive_profile.rotor_profile
	var disc := _motion.disc_state(_rotor_slot)
	disc.omega_rad_s = rotor.nominal_rad_s
	disc.collective_deg = rotor.collective_limit_deg.y
	disc.cyclic_deg = Vector2.ZERO
	_runtime.body.global_transform = Transform3D(Basis(), Vector3(0.0, 50.0, 0.0))
	_runtime.body.linear_velocity = Vector3.ZERO
	_runtime.body.angular_velocity = Vector3.ZERO
	return disc
