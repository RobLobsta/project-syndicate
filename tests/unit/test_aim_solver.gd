extends TestCase
## [AimSolver], and the [code]-Z[/code] convention the whole combat layer hangs
## off, owned by [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §3 and §4.
##
## The load-bearing test here is the round trip. §4.2's decomposition and §7.2's
## emission are two halves of one convention, and a sign error in either alone
## points a turret somewhere other than where it was asked to point — which is
## invisible to a test of either half on its own, and which the first duel
## between two real Assemblies is what found. Every angle assertion below is
## composed back into a direction for that reason.

## §4.3's tolerance, quoted rather than imported.
const DOC_AIM_TOLERANCE_RAD: float = 0.0087

## Full traverse, as the shipped autocannon authors it.
const FULL_YAW := Vector2(-180.0, 180.0)
## The shipped autocannon's pitch limits.
const GUN_PITCH := Vector2(-8.0, 34.0)


func test_the_tolerance_is_what_the_document_says() -> void:
	check_approx(
		AimSolver.AIM_TOLERANCE_RAD, DOC_AIM_TOLERANCE_RAD, "half a degree of convergence"
	)


## ===== THE CONVENTION ==================================================


func test_a_mount_at_rest_points_along_negative_z() -> void:
	# The whole convention in one assertion. Every Effector Module in the registry
	# authors its barrel or its blade along its own -Z, and §7.2 emits along
	# -basis.z; a solver whose zero-yaw direction were +Z would point every turret
	# in the game exactly backwards.
	var forward := AimSolver.direction_for(0.0, 0.0)
	check_true(forward.is_equal_approx(Vector3.FORWARD), "zero yaw and zero pitch is -Z")


func test_the_decomposition_and_the_composition_are_inverses() -> void:
	# The assertion a sign error cannot satisfy. Neither half is checked against a
	# number here; they are checked against each other, over directions spread
	# across the sphere.
	var directions: Array[Vector3] = [
		Vector3(0.0, 0.0, -1.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.3, 0.2, -0.9),
		Vector3(-0.6, -0.15, -0.4),
		Vector3(0.7, 0.5, 0.5),
	]
	for d: Vector3 in directions:
		var angles := AimSolver.angles_for(d)
		var round_trip := AimSolver.direction_for(angles.x, angles.y)
		check_true(
			round_trip.is_equal_approx(d.normalized()),
			"a mount solved for %v points back at %v, not %v" % [d, d.normalized(), round_trip]
		)


func test_a_target_to_the_right_yaws_right() -> void:
	# +X is right (doc 11 §7.2 fixes it for the steer axis and nothing else in the
	# project disagrees). A mount whose forward is -Z reaches +X by yawing
	# through -90 degrees, which is the sign this asserts.
	var angles := AimSolver.angles_for(Vector3.RIGHT)
	check_approx(angles.x, -PI * 0.5, "a target on +X is a quarter turn")
	check_true(
		AimSolver.direction_for(angles.x, angles.y).is_equal_approx(Vector3.RIGHT),
		"and composing it back points at +X"
	)


func test_a_target_above_pitches_up() -> void:
	var angles := AimSolver.angles_for(Vector3(0.0, 1.0, -1.0))
	check_approx(angles.y, PI * 0.25, "45 degrees up is a positive pitch")
	check_true(angles.y > 0.0, "up is positive, which is what the authored limits assume")


func test_a_zero_direction_asks_for_nothing() -> void:
	# A hardpoint whose muzzle is exactly on the aim point. Rare, but it happens
	# the tick an Assembly drives into what it was shooting at.
	check_true(AimSolver.angles_for(Vector3.ZERO).is_zero_approx(), "no direction, no command")


## ===== LIMITS (§3.1) ===================================================


func test_a_full_traverse_mount_is_not_clamped() -> void:
	# Clamping a 360-degree mount introduces a seam at whichever angle the limits
	# happen to start, and a turret that can turn all the way round has to be able
	# to cross it.
	check_approx(AimSolver.clamp_yaw(PI * 0.99, FULL_YAW), PI * 0.99, "near the back is fine")
	check_approx(AimSolver.clamp_yaw(-PI * 0.99, FULL_YAW), -PI * 0.99, "and so is the other side")


## The same rule, authored the other legal way round.
##
## The symmetric case above cannot tell the rule from its fallback: [constant
## FULL_YAW] is -180 to 180, so [code]clampf[/code] against it is the identity
## over every bearing [method AimSolver.angles_for] can produce, and deleting the
## full-traverse branch outright leaves both assertions green. Session 17's fault
## sweep is what said so.
##
## A mount authored from 0 to 360 has the same span and satisfies the same
## condition, and there the fallback is not equivalent but catastrophic: clamping
## a bearing to port into [code][0, 2pi][/code] pins it at zero, so the mount
## could only ever aim starboard.
func test_a_full_traverse_authored_from_zero_is_not_clamped() -> void:
	var from_zero := Vector2(0.0, 360.0)
	check_approx(
		AimSolver.clamp_yaw(-1.0, from_zero), -1.0,
		"a bearing to port survives a mount authored 0 to 360"
	)
	check_approx(
		AimSolver.clamp_yaw(-PI * 0.75, from_zero), -PI * 0.75,
		"and so does one over the shoulder"
	)
	check_approx(
		AimSolver.clamp_yaw(1.0, from_zero), 1.0,
		"and starboard is untouched either way"
	)


func test_a_limited_mount_is_clamped_to_its_arc() -> void:
	var limits := Vector2(-45.0, 45.0)
	check_approx(
		AimSolver.clamp_yaw(PI * 0.5, limits), deg_to_rad(45.0), "past the stop is at the stop"
	)
	check_approx(
		AimSolver.clamp_yaw(-PI * 0.5, limits), deg_to_rad(-45.0), "on both sides"
	)
	check_approx(AimSolver.clamp_yaw(0.2, limits), 0.2, "and inside the arc, untouched")


func test_pitch_is_clamped_asymmetrically_as_authored() -> void:
	# The shipped gun depresses 8 degrees and elevates 34. A turret that could
	# depress as far as it elevates would shoot its own hull.
	check_approx(
		AimSolver.clamp_pitch(deg_to_rad(-40.0), GUN_PITCH),
		deg_to_rad(-8.0),
		"depression stops at the authored 8 degrees"
	)
	check_approx(
		AimSolver.clamp_pitch(deg_to_rad(80.0), GUN_PITCH),
		deg_to_rad(34.0),
		"and elevation at 34"
	)


## ===== SLEW AND CONVERGENCE (§3.3, §4.3) ===============================


func test_slew_is_rate_limited_and_arrives() -> void:
	var dt := SyndicateConstants.PHYSICS_DT
	var stepped := AimSolver.slew(0.0, PI, 65.0, 1.0, dt)
	check_approx(stepped, deg_to_rad(65.0) * dt, "one tick is one tick of the authored rate")
	check_true(stepped < PI, "and a half turn takes more than one of them")
	check_approx(
		AimSolver.slew(0.0, 0.001, 65.0, 1.0, dt),
		0.001,
		"a target inside one step is reached exactly, not overshot"
	)


func test_a_damaged_mount_traverses_slowly_and_not_inaccurately() -> void:
	# §3.3. The band scales the rate; it does not add error. A turret that got
	# less accurate as it was damaged would be indistinguishable from spread and
	# would double-count the band's spread multiplier.
	var dt := SyndicateConstants.PHYSICS_DT
	var healthy := AimSolver.slew(0.0, PI, 65.0, 1.0, dt)
	var critical := AimSolver.slew(0.0, PI, 65.0, DegradationTable.EFF_SLEW[3], dt)
	check_approx(
		critical, healthy * DegradationTable.EFF_SLEW[3], "CRITICAL traverses at 0.45 of the rate"
	)
	check_true(critical > 0.0, "but it still traverses")


func test_convergence_wraps_yaw_and_does_not_wrap_pitch() -> void:
	# Yaw is a circle: the short way from -179 to +179 is two degrees. Pitch is an
	# arc with ends and a 358-degree pitch error is not a thing a mount can have,
	# so wrapping it would report a fully depressed mount as converged on a target
	# above it.
	check_true(
		AimSolver.is_converged(PI - 0.001, -PI + 0.001, 0.0, 0.0),
		"yaw either side of the seam is converged"
	)
	check_false(
		AimSolver.is_converged(0.0, 0.0, PI - 0.001, -PI + 0.001),
		"the same numbers in pitch are not"
	)


func test_convergence_is_exactly_the_documented_tolerance() -> void:
	check_true(
		AimSolver.is_converged(0.0, DOC_AIM_TOLERANCE_RAD * 0.99, 0.0, 0.0), "just inside"
	)
	check_false(
		AimSolver.is_converged(0.0, DOC_AIM_TOLERANCE_RAD * 1.01, 0.0, 0.0), "and just outside"
	)


## ===== SPREAD (§7.4) ===================================================


func test_a_zero_cone_returns_the_direction_untouched() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	check_true(
		AimSolver.cone_sample(Vector3.FORWARD, 0.0, rng).is_equal_approx(Vector3.FORWARD),
		"no spread, no deviation — and no generator draw either"
	)


func test_every_sample_lands_inside_the_cone() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260802
	var half_angle := deg_to_rad(3.0)
	var cos_limit := cos(half_angle)
	var worst := 1.0
	for i: int in 400:
		var sample := AimSolver.cone_sample(Vector3.FORWARD, half_angle, rng)
		worst = minf(worst, sample.dot(Vector3.FORWARD))
		check_approx(sample.length(), 1.0, "every sample is a unit direction")
	check_true(worst >= cos_limit - 1.0e-5, "and none of them escaped the cone")
	check_true(worst < cos(half_angle * 0.5), "while some of them reached its edge")


func test_the_spread_is_uniform_over_solid_angle_not_over_angle() -> void:
	# §7.4. Sampling the angle uniformly clusters shots toward the centre. Over a
	# cone, the fraction of samples inside half the half-angle should be about the
	# ratio of the solid angles — a quarter — not about half.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var half_angle := deg_to_rad(6.0)
	var inner := cos(half_angle * 0.5)
	var count := 0
	var total := 2000
	for i: int in total:
		if AimSolver.cone_sample(Vector3.FORWARD, half_angle, rng).dot(Vector3.FORWARD) > inner:
			count += 1
	var fraction := float(count) / float(total)
	check_true(
		fraction > 0.18 and fraction < 0.32,
		"about a quarter of the samples land in the inner half-cone, not about a half: %.3f"
		% fraction
	)


func test_the_spread_is_deterministic_for_a_seed() -> void:
	# Invariant I-9. A predicting client replays these rolls; two generators on
	# the same seed must produce the same shots or every predicted shot mismatches.
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	for i: int in 8:
		check_true(
			AimSolver.cone_sample(Vector3.FORWARD, 0.05, a).is_equal_approx(
				AimSolver.cone_sample(Vector3.FORWARD, 0.05, b)
			),
			"the same seed produces the same spread"
		)


func test_a_vertical_direction_still_spreads() -> void:
	# The basis fallback. A cross product with a parallel vector is zero, so a
	# naive up-reference would send every sample to the same place and a weapon
	# firing straight up would produce one perfect hole.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var first := AimSolver.cone_sample(Vector3.UP, deg_to_rad(4.0), rng)
	var second := AimSolver.cone_sample(Vector3.UP, deg_to_rad(4.0), rng)
	check_true(first.is_normalized(), "a vertical shot still produces a direction")
	check_false(first.is_equal_approx(second), "and two of them differ")
	check_true(first.dot(Vector3.UP) > cos(deg_to_rad(4.0)) - 1.0e-5, "inside the cone")
