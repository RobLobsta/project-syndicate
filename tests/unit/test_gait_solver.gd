extends TestCase
## [GaitSolver], from [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §13.
##
## Parameters are the shipping `mot.limb.strider.t4` of document 01 §10.3.

const LEG: float = 1.90
const DUTY: float = 0.62
const STEP: float = 1.10
const STANCE_K: float = 96000.0
const STANCE_C: float = 12000.0
const MAX_FOOT_N: float = 42000.0
const GAIN: float = 0.19
## §13.10's support polygon, as `mot.limb.strider.t4` authors it.
const FOOT_L: float = 0.60
const FOOT_W: float = 0.34

var _limb: LimbProfile = null
var _motive: MotiveAssemblyProfile = null


func before_all() -> void:
	_limb = LimbProfile.new()
	_limb.leg_length_m = LEG
	_limb.hip_offset_m = Vector3.ZERO
	_limb.foot_radius_m = 0.16
	_limb.foot_length_m = FOOT_L
	_limb.foot_width_m = FOOT_W
	_limb.stance_height_ratio = 0.86
	_limb.stance_stiffness_n_m = STANCE_K
	_limb.stance_damping_ns_m = STANCE_C
	_limb.max_foot_force_n = MAX_FOOT_N
	_limb.duty_factor = DUTY
	_limb.nominal_cadence_hz = 1.05
	_limb.max_cadence_hz = 2.20
	_limb.max_step_length_m = STEP
	_limb.step_height_m = 0.34
	_limb.placement_gain_s = GAIN
	_limb.turn_rate_deg_s = 45.0

	_motive = MotiveAssemblyProfile.new()
	_motive.traction_coefficient = 1.22


## ===== PHASE ASSIGNMENT ================================================


func test_two_limbs_alternate() -> void:
	var hips := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0)])
	var offsets := GaitSolver.assign_phase_offsets(hips, PackedInt32Array([1, 2]))
	check_approx(offsets[0], 0.0, "the left limb leads")
	check_approx(offsets[1], 0.5, "and the right is exactly half a cycle behind: bipedal walking")


## The whole point of reversing one side. Interleaving two same-direction
## orderings gives front-left, front-right, rear-left, rear-right — and because
## the swing window is one contiguous arc, the two limbs swinging together are
## the two front ones, leaving the Assembly on its rear pair and pitching forward
## every stride. Reversing makes the adjacent pair a diagonal.
func test_four_limbs_put_diagonals_adjacent_in_phase() -> void:
	# Fore is -Z. Indices: 0 = left-front, 1 = left-rear, 2 = right-front, 3 = right-rear.
	var hips := PackedVector3Array(
		[
			Vector3(-0.5, 0, -1.0),
			Vector3(-0.5, 0, 1.0),
			Vector3(0.5, 0, -1.0),
			Vector3(0.5, 0, 1.0),
		]
	)
	var offsets := GaitSolver.assign_phase_offsets(hips, PackedInt32Array([1, 2, 3, 4]))

	check_approx(offsets[0], 0.00, "left-front leads")
	check_approx(offsets[3], 0.25, "right-rear follows it: the diagonal partner")
	check_approx(offsets[1], 0.50, "left-rear is half a cycle out")
	check_approx(offsets[2], 0.75, "right-front last")

	check_approx(
		absf(offsets[0] - offsets[3]),
		0.25,
		"the diagonal pair is adjacent in phase, so they swing together"
	)
	check_true(
		absf(offsets[0] - offsets[2]) > 0.25,
		"and the two front limbs are not, so the Assembly never stands on its rear pair alone"
	)


func test_six_limbs_alternate_sides_through_the_cycle() -> void:
	var hips := PackedVector3Array(
		[
			Vector3(-0.5, 0, -1.0),
			Vector3(-0.5, 0, 0.0),
			Vector3(-0.5, 0, 1.0),
			Vector3(0.5, 0, -1.0),
			Vector3(0.5, 0, 0.0),
			Vector3(0.5, 0, 1.0),
		]
	)
	var offsets := GaitSolver.assign_phase_offsets(hips, PackedInt32Array([1, 2, 3, 4, 5, 6]))
	# Rebuild the cycle order and check the side alternates along it.
	var order: Array[int] = [0, 1, 2, 3, 4, 5]
	order.sort_custom(func(a: int, b: int) -> bool: return offsets[a] < offsets[b])
	for i: int in order.size() - 1:
		check_true(
			hips[order[i]].x * hips[order[i + 1]].x < 0.0,
			"consecutive phases are on opposite sides at step %d" % i
		)


func test_every_offset_is_distinct_and_evenly_spaced() -> void:
	var hips := PackedVector3Array(
		[Vector3(-0.5, 0, -1), Vector3(-0.5, 0, 1), Vector3(0.5, 0, -1), Vector3(0.5, 0, 1)]
	)
	var offsets := GaitSolver.assign_phase_offsets(hips, PackedInt32Array([1, 2, 3, 4]))
	var sorted: Array[float] = []
	for o: float in offsets:
		sorted.append(o)
	sorted.sort()
	for i: int in sorted.size():
		check_approx(sorted[i], float(i) / 4.0, "offset %d is i/n" % i)


func test_an_empty_limb_set_assigns_nothing() -> void:
	check_eq(
		GaitSolver.assign_phase_offsets(PackedVector3Array(), PackedInt32Array()).size(),
		0,
		"no limbs, no offsets, and no division by zero"
	)


## Ties break on slot index, which is what gives the ordering a total order. Two
## limbs at one position would otherwise be ordered by whatever the sort did.
func test_coincident_limbs_break_ties_on_slot() -> void:
	var hips := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(-0.5, 0, 0)])
	var high_first := GaitSolver.assign_phase_offsets(hips, PackedInt32Array([9, 4]))
	check_approx(high_first[1], 0.0, "the lower slot leads regardless of array order")
	check_approx(high_first[0], 0.5, "and the higher follows")


## ===== CADENCE =========================================================


func test_standing_freezes_the_gait() -> void:
	check_approx(
		GaitSolver.cadence_hz(_limb, 0.1),
		0.0,
		"below the standing threshold the cadence is zero and every foot stays planted"
	)
	check_approx(
		GaitSolver.advance_clock(0.4, 0.0, SyndicateConstants.PHYSICS_DT),
		0.4,
		"and a zero cadence holds the clock exactly where it was"
	)


func test_cadence_tracks_speed_over_step_length() -> void:
	check_approx(
		GaitSolver.cadence_hz(_limb, 2.0),
		2.0 / STEP,
		"the body advances one step length per stance, so cadence is speed over step"
	)


func test_cadence_clamps_to_the_authored_band() -> void:
	check_approx(GaitSolver.cadence_hz(_limb, 0.5), 1.05, "a slow walk holds the nominal cadence")
	check_approx(GaitSolver.cadence_hz(_limb, 40.0), 2.20, "and a sprint caps at the maximum")


func test_the_clock_wraps() -> void:
	check_approx(GaitSolver.advance_clock(0.9, 2.0, 0.1), 0.1, "0.9 plus 0.2 wraps to 0.1")
	check_approx(GaitSolver.phase_of(0.9, 0.5), 0.4, "and an offset wraps with it")


## ===== FOOT PLACEMENT ==================================================


func test_the_neutral_point_is_half_a_stance_of_travel_ahead() -> void:
	var hip := Vector3(0.0, 1.5, 0.0)
	var v := Vector3(1.0, 0.0, 0.0)
	var target := GaitSolver.foot_target(_limb, hip, 0.0, v, v, 1.0, 0.0)
	# stance = duty / cadence = 0.62 s, so the neutral offset is 1.0 * 0.31.
	check_approx(target.x, 0.31, "planting there leaves the body's velocity unchanged")
	check_approx(target.y, 0.0, "on the ground")
	check_approx(target.z, 0.0, "and straight ahead")


## Planting ahead of neutral brakes. With desired velocity zero the correction
## term adds a full placement_gain_s of travel, and a test using desired == v
## would not distinguish the two.
func test_a_velocity_error_shifts_the_plant_off_neutral() -> void:
	var hip := Vector3(0.0, 1.5, 0.0)
	var v := Vector3(1.0, 0.0, 0.0)
	var target := GaitSolver.foot_target(_limb, hip, 0.0, v, Vector3.ZERO, 1.0, 0.0)
	check_approx(target.x, 0.31 + GAIN, "the correction reaches ahead to brake")
	check_true(target.x > 0.31, "which is further than the neutral point")


func test_the_step_is_clamped_to_half_the_step_length() -> void:
	var hip := Vector3(0.0, 1.5, 0.0)
	var target := GaitSolver.foot_target(
		_limb, hip, 0.0, Vector3(20.0, 0, 0), Vector3.ZERO, 1.0, 0.0
	)
	check_approx(
		Vector2(target.x, target.z).length(), STEP * 0.5, "a sprint cannot outreach the step limit"
	)


## Clamped twice, step then reach. A leg cannot plant a foot it would have to
## over-extend to hold.
func test_the_reach_is_clamped_to_the_leg_length() -> void:
	var hip := Vector3(0.0, 3.0, 0.0)
	var target := GaitSolver.foot_target(
		_limb, hip, 0.0, Vector3(5.0, 0, 0), Vector3.ZERO, 1.0, 0.0
	)
	check_approx(hip.distance_to(target), LEG, "the foot lands exactly at full extension", 1e-4)


func test_a_frozen_gait_plants_under_the_hip() -> void:
	var hip := Vector3(2.0, 1.5, -3.0)
	var target := GaitSolver.foot_target(_limb, hip, 0.0, Vector3(1, 0, 0), Vector3.ZERO, 0.0, 0.0)
	check_approx(target.x, 2.0, "a standing Assembly plants directly beneath its hip")
	check_approx(target.z, -3.0, "on both axes")


## Yaw is placement. There is no yaw torque term in the ambulatory family, so a
## turn command has to move the foot or nothing turns.
func test_a_turn_command_rotates_the_plant_off_axis() -> void:
	var hip := Vector3(0.0, 1.5, 0.0)
	var v := Vector3(1.0, 0.0, 0.0)
	var straight := GaitSolver.foot_target(_limb, hip, 0.0, v, v, 1.0, 0.0)
	var turning := GaitSolver.foot_target(_limb, hip, 0.0, v, v, 1.0, 1.0)
	check_approx(
		Vector2(straight.x, straight.z).length(),
		Vector2(turning.x, turning.z).length(),
		"turning does not change how far the foot reaches",
		1e-4
	)
	check_ne(straight.z, turning.z, "only which way, so the stance force yaws the body")

	# The direction, which is the half a sign flip satisfies. §13.5: a right
	# demand rotates the plant target by a negative angle about the world up,
	# because that is what positive-is-right means everywhere else in doc 05 —
	# and for six sessions this file asserted only that the foot had moved.
	var flat_straight := Vector3(straight.x, 0.0, straight.z)
	var flat_turning := Vector3(turning.x, 0.0, turning.z)
	check_true(
		flat_straight.signed_angle_to(flat_turning, Vector3.UP) < 0.0,
		"a positive turn command swings the plant clockwise, which is right"
	)
	var left := GaitSolver.foot_target(_limb, hip, 0.0, v, v, 1.0, -1.0)
	check_true(
		flat_straight.signed_angle_to(Vector3(left.x, 0.0, left.z), Vector3.UP) > 0.0,
		"and a negative one swings it the other way"
	)
	# The magnitude is the authored rate over one stance, and it is symmetric.
	check_approx(
		absf(flat_straight.signed_angle_to(flat_turning, Vector3.UP)),
		absf(flat_straight.signed_angle_to(Vector3(left.x, 0.0, left.z), Vector3.UP)),
		"by the same angle either way",
		1e-4
	)


## ===== STANCE FORCE ====================================================


func test_the_stance_spring_holds_the_body_up() -> void:
	var rest := _limb.stance_rest_length_m()
	check_approx(rest, 0.86 * LEG, "rest length is the authored fraction of the leg")
	check_approx(
		GaitSolver.stance_axial_force_n(_limb, rest - 0.1, rest - 0.1, SyndicateConstants.PHYSICS_DT),
		STANCE_K * 0.1,
		"0.1 m of compression against 96 kN/m"
	)


func test_a_leg_pushes_and_never_pulls() -> void:
	var rest := _limb.stance_rest_length_m()
	check_approx(
		GaitSolver.stance_axial_force_n(_limb, rest + 0.2, rest + 0.2, SyndicateConstants.PHYSICS_DT),
		0.0,
		"an extended leg exerts nothing, the same rule §6.2 states for suspension"
	)


func test_the_foot_force_is_capped() -> void:
	var rest := _limb.stance_rest_length_m()
	check_approx(
		GaitSolver.stance_axial_force_n(_limb, rest - 1.0, rest - 1.0, SyndicateConstants.PHYSICS_DT),
		MAX_FOOT_N,
		"an overloaded limb sags at its rating rather than launching the Assembly"
	)


## The damper opposes the rate of change of leg length, so a limb being
## compressed resists harder than one held still.
func test_the_damper_resists_compression() -> void:
	var rest := _limb.stance_rest_length_m()
	var length := rest - 0.1
	var still := GaitSolver.stance_axial_force_n(
		_limb, length, length, SyndicateConstants.PHYSICS_DT
	)
	var compressing := GaitSolver.stance_axial_force_n(
		_limb, length, length + 0.01, SyndicateConstants.PHYSICS_DT
	)
	check_true(compressing > still, "a leg being compressed pushes back harder")
	check_approx(
		compressing,
		STANCE_K * 0.1 + STANCE_C * (0.01 * float(SyndicateConstants.PHYSICS_HZ)),
		"by exactly the damper against the shortening rate",
		0.5
	)


## ===== FRICTION ========================================================


func test_foot_mu_runs_through_the_shared_band_row() -> void:
	check_approx(
		GaitSolver.foot_mu(_motive, PartEnums.IntegrityBand.NOMINAL, 1.0), 1.22, "the authored value"
	)
	check_approx(
		GaitSolver.foot_mu(_motive, PartEnums.IntegrityBand.IMPAIRED, 1.0),
		1.22 * 0.60,
		"a damaged limb loses grip before it loses the ability to hold weight"
	)


func test_friction_leaves_a_force_inside_the_cone_alone() -> void:
	var f := Vector3(100.0, 1000.0, 0.0)
	check_eq(
		GaitSolver.limit_by_friction(f, Vector3.UP, 0.5),
		f,
		"a 0.1 shear ratio against a 0.5 coefficient is well inside the cone"
	)
	check_false(GaitSolver.would_slip(f, Vector3.UP, 0.5), "and would_slip agrees")


func test_friction_scales_back_a_force_outside_the_cone() -> void:
	var f := Vector3(100.0, 1000.0, 0.0)
	var limited := GaitSolver.limit_by_friction(f, Vector3.UP, 0.05)
	check_approx(limited.y, 1000.0, "the normal component is untouched")
	check_approx(limited.x, 50.0, "and the tangent is capped at mu times it")
	check_true(GaitSolver.would_slip(f, Vector3.UP, 0.05), "and would_slip agrees")


func test_a_foot_pulling_away_from_the_ground_transmits_nothing() -> void:
	check_eq(
		GaitSolver.limit_by_friction(Vector3(100.0, -1000.0, 0.0), Vector3.UP, 0.5),
		Vector3.ZERO,
		"a force directed into the air is not held by friction with the ground"
	)


## ===== SWING ===========================================================


func test_the_swing_arc_peaks_at_mid_swing() -> void:
	check_approx(GaitSolver.swing_height_m(_limb, 0.0), 0.0, "on the ground at lift-off")
	check_approx(GaitSolver.swing_height_m(_limb, 0.5), _limb.step_height_m, "peak at mid-swing")
	check_approx(GaitSolver.swing_height_m(_limb, 1.0), 0.0, "and back down at touchdown")


func test_swing_progress_spans_the_part_of_the_cycle_that_is_not_stance() -> void:
	# Zero at lift-off and one at touchdown, with the duty factor as the origin.
	# Written out against 0.62 rather than by calling the function twice: a
	# progress measured from the top of the cycle instead of from lift-off is
	# monotonic, in range, and wrong, and only a stated value catches it.
	check_approx(GaitSolver.swing_progress(DUTY, DUTY), 0.0, "lift-off is the start of swing")
	check_approx(GaitSolver.swing_progress(1.0, DUTY), 1.0, "and the top of the cycle its end")
	# 0.81 is half way from 0.62 to 1.0.
	check_approx(GaitSolver.swing_progress(0.81, DUTY), 0.5, "half way between them is mid-swing")


func test_a_limb_in_stance_reports_no_swing_progress() -> void:
	# Clamped rather than negative. The caller only asks while swinging, and a
	# negative progress would put the drawn foot behind the point it left.
	check_approx(GaitSolver.swing_progress(0.0, DUTY), 0.0, "the start of stance")
	check_approx(GaitSolver.swing_progress(DUTY * 0.5, DUTY), 0.0, "and the middle of it")


func test_a_limb_that_is_never_in_swing_divides_by_nothing() -> void:
	# A duty factor of 1.0 is a legal profile — a limb permanently in stance —
	# and the span it leaves for swing is zero.
	check_approx(GaitSolver.swing_progress(1.0, 1.0), 0.0, "no swing to be part-way through")


func test_the_drawn_foot_travels_from_the_plant_point_to_the_next_target() -> void:
	var from := Vector3(0.0, 0.0, 2.0)
	var to := Vector3(0.0, 0.0, -2.0)
	check_true(
		GaitSolver.swing_foot_world(_limb, from, to, 0.0).is_equal_approx(from),
		"it leaves from where it was planted"
	)
	check_true(
		GaitSolver.swing_foot_world(_limb, from, to, 1.0).is_equal_approx(to),
		"and arrives exactly where the placement law is reaching for"
	)
	# Both halves of mid-swing, because either alone is satisfied by a defect:
	# an arc that never lifts passes the horizontal test, and one that lifts
	# without advancing passes the vertical.
	var middle := GaitSolver.swing_foot_world(_limb, from, to, 0.5)
	check_approx(middle.z, 0.0, "half way along the ground between them at mid-swing")
	check_approx(middle.y, _limb.step_height_m, "and a full step height above the line")


func test_the_drawn_foot_never_leaves_the_swing_whatever_it_is_handed() -> void:
	# The progress is clamped inside the function as well as by its caller. A
	# limb whose phase overshoots between ticks would otherwise draw its foot
	# past the target and below the ground.
	var from := Vector3.ZERO
	var to := Vector3(0.0, 0.0, -2.0)
	check_true(
		GaitSolver.swing_foot_world(_limb, from, to, 1.8).is_equal_approx(to),
		"past touchdown is touchdown"
	)
	check_true(
		GaitSolver.swing_foot_world(_limb, from, to, -0.5).is_equal_approx(from),
		"and before lift-off is the plant point"
	)


## ===== §13.10 THE ANKLE ================================================


## The bound is the model. A foot carrying nothing can do nothing, and a foot at
## load can do exactly as much as its own size allows — no more, at any tilt.
func test_the_ankle_torque_is_bounded_by_the_load_and_the_foot() -> void:
	check_true(
		GaitSolver.ankle_torque_limit_nm(_limb, 0.0).is_zero_approx(),
		"a foot carrying no load has no ankle authority at all"
	)
	var limit := GaitSolver.ankle_torque_limit_nm(_limb, 10000.0)
	check_approx(limit.x, 10000.0 * FOOT_L * 0.5, "pitch is bounded by the fore-aft half extent")
	check_approx(limit.y, 10000.0 * FOOT_W * 0.5, "and roll by the lateral one")

	# Saturated by construction: a tilt far past anything the stiffness could
	# answer still cannot ask for more than the polygon allows.
	var far_over := Basis(Vector3.RIGHT, deg_to_rad(40.0))
	var tau := GaitSolver.ankle_torque_nm(_limb, 10000.0, far_over, Vector3.ZERO)
	check_true(
		tau.length() <= limit.x + limit.y + 1.0,
		"and 40 degrees of tilt cannot ask for more than the polygon allows"
	)


## [b]The sign, which is the assertion a flipped term passes every other test
## of.[/b] Doc 05 §13.10 makes the positive sense normative and §10 rule 14 makes
## asserting it mandatory: a magnitude is half a specification, and doc 05 §6.5's
## anti-roll bar shipped inverted for the life of the project behind a unit test
## that checked the number.
func test_the_ankle_torque_rights_the_machine_rather_than_pushing_it_over() -> void:
	# Pitched nose-down: rotated about +X by a positive angle takes the body's up
	# axis toward -Z. Righting it is a torque about -X.
	var nose_down := Basis(Vector3.RIGHT, deg_to_rad(5.0))
	var tau := GaitSolver.ankle_torque_nm(_limb, 20000.0, nose_down, Vector3.ZERO)
	check_true(
		tau.x < 0.0,
		"a nose-down hull gets a torque that pitches it back up (%.0f N·m about X)" % tau.x
	)

	# And the mirror, because a term that answered one sign and not the other
	# would satisfy the case above.
	var nose_up := Basis(Vector3.RIGHT, deg_to_rad(-5.0))
	check_true(
		GaitSolver.ankle_torque_nm(_limb, 20000.0, nose_up, Vector3.ZERO).x > 0.0,
		"and a nose-up one gets the opposite"
	)

	# Rolled right: about +Z. The restoring torque is about -Z.
	var rolled := Basis(Vector3.BACK, deg_to_rad(5.0))
	check_true(
		GaitSolver.ankle_torque_nm(_limb, 20000.0, rolled, Vector3.ZERO).z < 0.0,
		"and a rolled hull is rolled back"
	)


## §13.10 sets yaw to zero rather than clamping it, because §13.5 gives this
## family exactly one heading authority and it is placement. A second one would
## be two things fighting over the same axis.
func test_the_ankle_never_yaws() -> void:
	var yawing := Vector3(0.0, 3.0, 0.0)
	var tau := GaitSolver.ankle_torque_nm(
		_limb, 20000.0, Basis(Vector3.RIGHT, deg_to_rad(6.0)), yawing
	)
	check_approx(tau.y, 0.0, "a yaw rate produces no ankle torque about the vertical")


## A profile with no authored polygon behaves exactly as it did before §13.10.
## That is what makes the term opt-in per part rather than a change to every
## walking Assembly in the registry.
func test_a_foot_with_no_extent_has_no_ankle() -> void:
	var pointy := LimbProfile.new()
	pointy.leg_length_m = LEG
	check_true(
		GaitSolver.ankle_torque_nm(
			pointy, 20000.0, Basis(Vector3.RIGHT, deg_to_rad(8.0)), Vector3.ZERO
		).is_zero_approx(),
		"a point foot applies no torque at any tilt or load"
	)


## ===== §13.11 THE CAPTURE POINT ========================================


## The pendulum's time constant, and the floor that stands in for it when there
## is no pendulum to measure.
func test_the_capture_time_is_the_pendulum_and_the_gain_is_its_floor() -> void:
	var tau := GaitSolver.capture_time_s(_limb, 2.5)
	check_approx(
		tau, sqrt(2.5 / SyndicateConstants.GRAVITY_MPS2), "sqrt(h/g) at a real height"
	)
	check_true(tau > GAIN, "which on a machine this tall is well above the authored gain")
	check_approx(
		GaitSolver.capture_time_s(_limb, 0.0), GAIN,
		"and with no height to measure it falls back to the authored gain"
	)


## A body at rest captures under itself; a moving one captures ahead, downrange.
func test_the_capture_point_leads_a_moving_body_and_not_a_still_one() -> void:
	var com := Vector3(0.0, 2.5, 0.0)
	var still := GaitSolver.capture_point(com, Vector3.ZERO, 2.5)
	check_approx(still.x, 0.0, "a body at rest captures directly beneath itself (x)")
	check_approx(still.z, 0.0, "and (z)")
	check_approx(still.y, 0.0, "at the height of the foot rather than of the mass")

	var running := GaitSolver.capture_point(com, Vector3(0.0, 0.0, -4.0), 2.5)
	check_true(
		running.z < -1.0,
		"and a body running down -Z captures ahead of itself at %.2f m" % running.z
	)


## [b]The property §13.11 exists for, and the one the authored gain could not
## have.[/b] Doc 05 §13.9 measures the shipped family reversing 0.01 m in three
## seconds because the old correction could scale a disturbance and never create
## one. A demand has to move the plant target, and the two demands have to move
## it opposite ways.
##
## [b]A forward demand plants the foot behind the hip, and that is not a typo.[/b]
## §13.6's stance force acts along foot-to-hip, so a foot planted behind the body
## pushes it forward — which is why the sign of this assertion is the one thing in
## the file worth reading twice. Getting it backwards produces a machine that
## accelerates when told to stop, and every magnitude in it is identical.
func test_the_two_demands_plant_the_foot_opposite_sides_of_the_hip() -> void:
	var hip := Vector3(0.0, 1.4, 0.0)
	var forward := GaitSolver.foot_target(
		_limb, hip, 0.0, Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 1.0, 0.0, 2.0
	)
	var backward := GaitSolver.foot_target(
		_limb, hip, 0.0, Vector3.ZERO, Vector3(0.0, 0.0, 1.0), 1.0, 0.0, 2.0
	)
	check_true(
		forward.z > 0.05,
		(
			"a forward demand from a standstill plants %.2f m behind the hip, which "
			+ "is what pushes the body forward"
		) % forward.z
	)
	check_true(
		backward.z < -0.05,
		"and a reverse demand plants %.2f m ahead of it" % backward.z
	)
	check_true(
		absf(forward.z + backward.z) < 0.01,
		"symmetrically, because the demand enters as a signed velocity"
	)


## Braking is the same term with `v_desired` at zero: a body already moving
## plants ahead of itself, which is the direction that takes speed off.
func test_a_stop_demand_plants_the_foot_ahead_of_a_moving_body() -> void:
	var hip := Vector3(0.0, 1.4, 0.0)
	var braking := GaitSolver.foot_target(
		_limb, hip, 0.0, Vector3(0.0, 0.0, -1.0), Vector3.ZERO, 1.0, 0.0, 2.0
	)
	check_true(
		braking.z < -0.05,
		"a body running down -Z with no demand plants %.2f m ahead of itself"
		% braking.z
	)


## A taller machine has a longer pendulum, so the same momentum error asks for a
## longer step. That is the physics the authored gain flattened away.
##
## The velocity is small on purpose: §13.5's step-length clamp binds at
## `max_step_length_m / 2` and would flatten both cases onto the same number,
## which is a comparison that passes whatever the term does.
func test_a_taller_machine_reaches_further_for_the_same_error() -> void:
	var hip := Vector3(0.0, 1.4, 0.0)
	var low := GaitSolver.foot_target(
		_limb, hip, 0.0, Vector3(0.0, 0.0, -0.3), Vector3.ZERO, 1.0, 0.0, 0.5
	)
	var tall := GaitSolver.foot_target(
		_limb, hip, 0.0, Vector3(0.0, 0.0, -0.3), Vector3.ZERO, 1.0, 0.0, 3.0
	)
	check_true(
		absf(tall.z) > absf(low.z) + 0.01,
		"3.0 m of pendulum reaches %.3f m against %.3f at 0.5" % [tall.z, low.z]
	)
