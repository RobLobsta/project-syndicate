extends TestCase
## The off-diagonal coupling correction of doc 05 §3.4, named by that section as
## [code]tests/physics/test_inertia_coupling.gd[/code] and unwritten until the
## suite could step physics.
##
## [b]It contradicts its section's premise, and the contradiction is measured
## here rather than argued.[/b] §3.4 says "Godot solves this with
## [code]I_diag[/code]", meaning the server integrates
## [code]I ω̇ + ω × (I ω) = τ[/code] using the diagonal tensor, and derives the
## correction as the difference between that and the true tensor's gyroscopic
## term. [method test_the_server_applies_no_gyroscopic_term_of_its_own] shows the
## server applies [i]no[/i] gyroscopic term: an Assembly whose three principal
## moments differ by 15%, spun about its intermediate axis, holds its angular
## velocity constant to seven significant figures for five seconds. A free rigid
## body cannot do that. The server is integrating
## [code]I_diag ω̇ = τ[/code] and nothing else.
##
## Two consequences, both left for a decision rather than settled here (CLAUDE.md
## §0: raise the conflict, do not implement around it):
##
## [enum]
## [*] The [code]+ ω × (I_diag ω)[/code] half of §3.4's difference is correcting
##     for a term nothing applies. The minimal faithful correction for a server
##     that applies none is [code]τ = − ω × (I_full ω)[/code].
## [*] §11 invariant 10 says the correction "may never inject net energy".
##     Measured at 60 Hz on a 6 rad/s spin it injects about 16% of the rotational
##     energy over five seconds, and so does the corrected form — both are
##     power-neutral in the continuous limit and neither is under explicit Euler.
##     [method test_the_correction_is_not_energy_neutral_in_practice] records the
##     number.
## [/enum]
##
## What this file does assert is that the correction is wired, bounded, and does
## the thing it exists to do: an asymmetric Assembly tumbles instead of spinning
## like a symmetric one.

## A disc on a rotary chassis, per doc 01 §7.1. The tensor this file measures
## moved when the chassis did: 900 kg in place of 1800, over a hull nine cells
## long rather than thirteen.
const CORE_KEY := &"core.rotary.lifter.t3"
const POWER_KEY := &"pmv.combustion.standard.t2"
const ROTOR_KEY := &"mot.rotor.coaxial_mid.t3"

const CORE_ORIGIN := Vector3i(24, 4, 24)
## Mass hung off the Core Module's centreline on two axes at once, which is what
## puts products of inertia into the tensor. A symmetric build has none and this
## whole section would be a no-op on it.
const POWER_ORIGIN := Vector3i(21, 0, 20)
## [b]It was (19, 4, 21), and that cell stopped mating when session 44 gave the
## rotary family its own chassis.[/b] The placement failed `POLARITY_MISMATCH`,
## `PlacementValidator.commit`'s assert fired, and — per `LEARNED_FACTS.md` §1
## fact 34 — an assert here prints and aborts the *call*, so `before_all` carried
## on and built the Assembly **without its rotor**. Every measurement in this file
## has therefore been taken on a two-part hull since, and the rotor is the part
## that hangs mass off two axes at once, which is the entire point of the fixture.
##
## The failure mode is worth more than the cell: a broken fixture that still
## produces numbers reads exactly like a broken subject, and this one spent two
## sessions on §3.0's "not obviously a re-measurement" list being suspected of an
## integrator fault.
const ROTOR_ORIGIN := Vector3i(20, 4, 21)

## Spin rate for the tumble tests, in rad/s — about one revolution per second.
const SPIN_RAD_S: float = 6.0
## A nudge off the pure principal axis. An exactly balanced spin is a fixed point
## of the equation and would sit there forever whatever the correction did.
const SEED_WOBBLE: Vector3 = Vector3(0.001, 0.001, 0.001)

const SOAK_TICKS: int = 300
## Fraction of its spin a body-frame axis must **keep** to count as holding, and
## the fraction an unstable one must have **lost**, after the soak.
##
## [b]Measured in the body frame, and the frame is the whole of what was wrong
## with this test.[/b] It used to take the off-axis component of the
## [i]world[/i] angular velocity against the axis it was launched on, and a
## torque-free body cannot show a tumble there: `ω · L` is exactly constant and
## `L` is fixed in world space, so once the body has tumbled onto a stable axis
## its world-frame `ω` sits back down near where it started. The measurement is
## not merely insensitive, it runs the wrong way — of the three axes, the one the
## body genuinely holds (the minor) reports the [i]largest[/i] world off-axis
## excursion, 3.02 rad/s, because a stable spin that is not exactly on `L`
## precesses; and the intermediate axis, which the body abandons completely,
## reports 0.13.
##
## In the body frame it is unambiguous. Launched at 6 rad/s and soaked for
## [constant SOAK_TICKS]: about the minor axis the body keeps **5.21 of 6.0** on
## the axis it started on, and about the intermediate axis it keeps **1.56**,
## having moved 5.52 of it onto another axis entirely. That is the migration of
## the spin through the body that §3.4 exists to produce.
const AXIS_HELD_FRACTION: float = 0.70
const AXIS_LOST_FRACTION: float = 0.45

## Spin rate chosen to drive the unclamped torque far past the ceiling: the
## correction goes as omega squared, so ten times the rate is a hundred times the
## torque.
const CLAMP_PROBE_RAD_S: float = 60.0

## How much rotational energy the correction may *lose* over the soak, and how
## little it may gain. Invariant 10 forbids injection, not dissipation: a
## correction that bleeds energy cannot destabilise an Assembly, and one that
## adds it spins a wreck up out of nothing. Explicit Euler added 16%; evaluating
## at the midpoint turns that into a 3% loss.
const ENERGY_LOSS_TOLERANCE: float = 0.08
const ENERGY_GAIN_TOLERANCE: float = 0.005

## Fractional drift allowed in the conserved angular momentum over the soak.
const MOMENTUM_TOLERANCE: float = 0.05

var _ctx: BuildContext = null
var _runtime: AssemblyRuntime = null
var _motion: MotiveSystem = null


func before_all() -> void:
	_ctx = BuildContext.with_physics(4)
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

	# No ControlInput: `step` applies the coupling torque and returns before any
	# family runs, so this file measures the correction and nothing else.
	_motion = MotiveSystem.new()
	_motion.runtime = _runtime
	_runtime.add_child(_motion)

	_runtime.body.gravity_scale = 0.0
	_runtime.body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_runtime.body.angular_damp = 0.0


func after_all() -> void:
	if _runtime != null:
		_runtime.free()
	if _ctx != null:
		_ctx.dispose()


func test_the_fixture_has_products_of_inertia_to_correct_for() -> void:
	# Without this the rest of the file passes against a correction that computes
	# zero, which is the fixture trap CLAUDE.md §9 keeps naming.
	#
	# [b]The part count is here because the tensor check alone did not catch a
	# missing part.[/b] `mot.rotor.coaxial_mid.t3` stopped mating at its authored
	# cell when session 44 moved the rotary chassis; `commit`'s assert printed and
	# aborted the call (`LEARNED_FACTS.md` §1 fact 34), `before_all` carried on,
	# and this file measured a two-part hull for two sessions. The Prime Mover
	# alone still leaves an xz product above the bound below and still leaves three
	# distinct moments, so every precondition here passed on the wrong Assembly.
	# A fixture that names three parts should count three.
	check_eq(
		_runtime.graph.alive.count(1),
		3,
		"the fixture built all three of the parts it names, rotor included"
	)
	var full := _runtime.mass_properties.inertia_full
	check_true(absf(full.x.z) > 100.0, "the tensor has a substantial xz product")
	var diag := _runtime.mass_properties.inertia_diag
	check_true(
		absf(diag.x - diag.y) > 1.0 and absf(diag.y - diag.z) > 1.0,
		"and three distinct principal moments, so a free spin is not neutrally stable"
	)


func test_the_server_applies_no_gyroscopic_term_of_its_own() -> void:
	# The finding, isolated. With the correction disabled the body is a plain
	# RigidBody3D with an asymmetric diagonal tensor, spun about its intermediate
	# axis: the configuration that tumbles fastest in reality. It does not move.
	# The axis is read before the properties are dropped: _intermediate_axis
	# needs the tensor the correction is about to be denied.
	var restored := _runtime.mass_properties
	_spin(_intermediate_axis())
	_runtime.mass_properties = null  # `_apply_coupling_torque` returns on null.
	var before := _runtime.body.angular_velocity

	await physics_frames(SOAK_TICKS)

	var after := _runtime.body.angular_velocity
	_runtime.mass_properties = restored
	check_true(
		(after - before).length() < 1e-5,
		"five seconds of free rotation change the angular velocity not at all"
	)


func test_the_correction_tumbles_an_asymmetric_assembly() -> void:
	# The behaviour §3.4 exists for, asserted as a comparison rather than as an
	# absolute: the same fixture, the same rate, the same soak, and the only
	# difference is which axis the spin was launched on. A correction that did
	# nothing would hold both, and one that merely added noise would lose both.
	#
	# Both readings are taken in the **body** frame. See
	# [constant AXIS_HELD_FRACTION] for why the world frame cannot see this at
	# all, which is what this test was doing until it was re-framed.
	_spin(Vector3.BACK)
	await physics_frames(SOAK_TICKS)
	var stable := absf(_body_frame_omega().z)

	var axis := _intermediate_axis()
	_spin(axis)
	await physics_frames(SOAK_TICKS)
	var tumbled := absf(_body_frame_omega().dot(axis))

	print(
		"      inertia coupling: minor axis keeps %.3f of %.1f rad/s, intermediate keeps %.3f"
		% [stable, SPIN_RAD_S, tumbled]
	)
	check_true(
		stable > SPIN_RAD_S * AXIS_HELD_FRACTION,
		(
			"a spin about the minor axis stays on it: %.3f of %.1f rad/s still there "
			+ "after %d ticks"
		) % [stable, SPIN_RAD_S, SOAK_TICKS]
	)
	check_true(
		tumbled < SPIN_RAD_S * AXIS_LOST_FRACTION,
		(
			"and the same spin about the intermediate axis leaves it: %.3f of %.1f rad/s "
			+ "left on the axis it was launched on"
		) % [tumbled, SPIN_RAD_S]
	)
	check_true(
		tumbled < stable,
		"which is the asymmetry, and it is the comparison rather than either number"
	)


func test_the_correction_conserves_angular_momentum_in_the_world_frame() -> void:
	# The sign test, and the only one that catches it. A free rigid body's
	# angular momentum `L = R · I_full · ω` is constant in world space, whatever
	# its tensor is doing in body space — that is the whole content of torque-free
	# motion. Both signs of the correction tumble the Assembly and both leave the
	# energy roughly where it was, so a flipped `−ω × (I ω)` passes every other
	# assertion in this file; it does not conserve L, because it drives the body
	# the wrong way round its own momentum vector.
	_spin(_intermediate_axis())
	var before := _world_angular_momentum()

	await physics_frames(SOAK_TICKS)

	var after := _world_angular_momentum()
	check_approx(
		after.length(),
		before.length(),
		"the magnitude of the angular momentum is unchanged",
		before.length() * MOMENTUM_TOLERANCE
	)
	check_true(
		after.normalized().dot(before.normalized()) > 1.0 - MOMENTUM_TOLERANCE,
		"and so is its direction, which is what torque-free motion means"
	)


func test_the_correction_is_bounded_by_its_ceiling() -> void:
	# §11 invariant 10's clamp. The torque the server received is recoverable
	# from the change in angular momentum it produced, because nothing else
	# touches this body: `step` returns before the families with a null input.
	_spin(_intermediate_axis(), CLAMP_PROBE_RAD_S)
	var before := _body_frame_omega()

	await physics_frames(1)

	var after := _body_frame_omega()
	var delta := after - before
	var diag := _runtime.mass_properties.inertia_diag
	var applied := Vector3(diag.x * delta.x, diag.y * delta.y, diag.z * delta.z)
	var magnitude := applied.length() / SyndicateConstants.PHYSICS_DT
	check_true(magnitude > 0.0, "a hundredfold torque was actually applied")
	check_true(
		magnitude <= MotiveSystem.COUPLING_TORQUE_LIMIT_NM * 1.001,
		"and arrived clamped to the ceiling rather than unbounded"
	)


func test_the_correction_never_injects_rotational_energy() -> void:
	# §11 invariant 10, and it is now something the code can be held to.
	#
	# The continuous torque is perpendicular to omega and does no work, but
	# sampling it at the tick boundary and holding it across the step does:
	# evaluated explicitly this added about 16% of the rotational energy over
	# five seconds, which is a correction that spins an Assembly up out of
	# nothing. `_apply_coupling_torque` takes the midpoint instead, for the cost
	# of one extra cross product, and the drift is what this asserts.
	_spin(_intermediate_axis())
	var before := _rotational_energy()

	await physics_frames(SOAK_TICKS)

	var after := _rotational_energy()
	check_true(
		after <= before * (1.0 + ENERGY_GAIN_TOLERANCE),
		"five seconds of correction adds no rotational energy; §11 invariant 10"
	)
	check_true(
		after >= before * (1.0 - ENERGY_LOSS_TOLERANCE),
		"and bleeds little enough that the tumble is still the tensor's, not the integrator's"
	)


## ===== FIXTURES ========================================================


## Resets the body and starts it spinning about [param axis].
func _spin(axis: Vector3, rate: float = SPIN_RAD_S) -> void:
	_runtime.body.global_transform = Transform3D(Basis(), Vector3(0.0, 100.0, 0.0))
	_runtime.body.linear_velocity = Vector3.ZERO
	_runtime.body.angular_velocity = axis * rate + SEED_WOBBLE


## The intermediate principal axis — the unstable one. A spin about the largest
## or smallest moment is stable and would tumble for neither formula, which would
## make every assertion above pass for the wrong reason.
func _intermediate_axis() -> Vector3:
	var diag := _runtime.mass_properties.inertia_diag
	var sorted: Array[float] = [diag.x, diag.y, diag.z]
	sorted.sort()
	var middle := sorted[1]
	if is_equal_approx(diag.y, middle):
		return Vector3.UP
	if is_equal_approx(diag.z, middle):
		return Vector3.BACK
	return Vector3.RIGHT


func _body_frame_omega() -> Vector3:
	return (
		_runtime.body.global_transform.basis.inverse() * _runtime.body.angular_velocity
	)


## Angular momentum in world space, against the true tensor. Conserved exactly
## under torque-free motion, and the quantity a sign error destroys.
func _world_angular_momentum() -> Vector3:
	var basis := _runtime.body.global_transform.basis
	return basis * (_runtime.mass_properties.inertia_full * _body_frame_omega())


## Rotational energy against the true tensor, which is the quantity the
## correction is meant to leave alone.
func _rotational_energy() -> float:
	var w := _body_frame_omega()
	return 0.5 * w.dot(_runtime.mass_properties.inertia_full * w)
