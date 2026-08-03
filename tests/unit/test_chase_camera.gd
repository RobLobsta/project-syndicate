extends TestCase
## The match camera's geometry and rate arithmetic,
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §13.4 to §13.6.
##
## Everything asserted here is a [code]static func[/code], which is the whole
## reason it can be asserted at all: the rest of [ChaseCamera] needs a viewport,
## a world, and an interpolated node to follow. Handoff §2.0's lesson about
## static tests applies in reverse for once — the two rules most likely to be got
## wrong here are both pure functions, and the parts that need a tree are the
## parts that merely compose them.
##
## The figures are written out by hand from §13.5 rather than imported from the
## class. A test that reads the constant it is checking asserts nothing (§2.1).

## §13.4's degeneracy threshold, by value.
const HEADING_DEGENERATE_DOT := 0.985
## §13.5's chase lag, by value.
const HEADING_LAG_HZ := 3.2
const PITCH_MIN_DEG := -72.0
const PITCH_MAX_DEG := 34.0


## ===== §13.4 THE HORIZONTAL-HEADING RULE ===============================


func test_a_hull_facing_negative_z_reads_as_zero_yaw() -> void:
	# Doc 07 §7.2 fixes -Z as forward, and the camera's back vector is built as
	# (sin y, 0, cos y) — so a heading of zero must put the camera at +Z, behind
	# a hull facing -Z. Getting this pair consistent is the whole of §13.4.
	var yaw := ChaseCamera._hull_heading(Basis.IDENTITY, 12.0)
	check_approx(yaw, 0.0, "a hull at identity faces the zero heading")


func test_the_heading_turns_the_same_way_the_hull_does() -> void:
	# A magnitude here would pass against an inverted camera, which is handoff
	# §2's most productive defect class. The assertion is a direction.
	var left := Basis.from_euler(Vector3(0.0, deg_to_rad(30.0), 0.0))
	var right := Basis.from_euler(Vector3(0.0, deg_to_rad(-30.0), 0.0))
	check_approx(
		ChaseCamera._hull_heading(left, 0.0), deg_to_rad(30.0),
		"a hull yawed +30° reads +30°"
	)
	check_approx(
		ChaseCamera._hull_heading(right, 0.0), deg_to_rad(-30.0),
		"and one yawed -30° reads -30°, not +30°"
	)


func test_a_hull_standing_on_its_nose_holds_the_previous_heading() -> void:
	# §13.4's real content. The projected forward's *direction* is meaningless
	# exactly when its length approaches zero, so the camera must hold rather
	# than snap. An Assembly is one rigid body (I-3) and pitches all the way over
	# under its own recoil, so this is a state a player reaches in normal play.
	var previous := deg_to_rad(41.0)
	var nose_down := Basis.from_euler(Vector3(deg_to_rad(-90.0), 0.0, 0.0))
	check_approx(
		ChaseCamera._hull_heading(nose_down, previous), previous,
		"a hull pointing at the ground holds the last good heading"
	)
	var nose_up := Basis.from_euler(Vector3(deg_to_rad(90.0), 0.0, 0.0))
	check_approx(
		ChaseCamera._hull_heading(nose_up, previous), previous,
		"and so does one pointing at the sky"
	)


func test_the_degenerate_band_is_the_documented_one() -> void:
	# Asserted either side of the threshold, so a band that never triggers and a
	# band that always triggers are both caught. Just inside it must hold; just
	# outside it must follow.
	var previous := deg_to_rad(41.0)
	var inside := absf(cos(acos(HEADING_DEGENERATE_DOT) * 0.5))
	check_true(inside > HEADING_DEGENERATE_DOT, "the fixture's steep case is inside the band")

	var steep := Basis.from_euler(Vector3(-asin(inside), 0.0, 0.0))
	check_approx(
		ChaseCamera._hull_heading(steep, previous), previous, "inside the band, it holds"
	)

	var shallow := Basis.from_euler(Vector3(deg_to_rad(-40.0), 0.0, 0.0))
	check_approx(
		ChaseCamera._hull_heading(shallow, previous), 0.0,
		"outside it, a pitched hull still yields its real heading"
	)


func test_roll_never_reaches_the_heading() -> void:
	# §13.4: the camera takes yaw from the hull and nothing else from its
	# attitude. A camera that inherited roll would roll the whole screen when an
	# Assembly took a recoil impulse it could not carry.
	var rolled := Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(75.0)))
	check_approx(
		ChaseCamera._hull_heading(rolled, 9.0), 0.0,
		"a hull rolled 75° about its own forward still faces zero"
	)


## ===== §13.5 RATES =====================================================


func test_the_lag_is_frame_rate_independent() -> void:
	# The property the exponential form exists for, and the one a per-frame alpha
	# does not have. Two half-steps must leave the same residue as one full step:
	# exp(-r·dt/2)² = exp(-r·dt). A bare alpha would settle measurably further in
	# two steps, so the camera would feel different on a 144 Hz machine while
	# every simulated quantity stayed identical.
	var dt := 1.0 / 60.0
	var one_step := 1.0 - ChaseCamera._lag(HEADING_LAG_HZ, dt)
	var half := 1.0 - ChaseCamera._lag(HEADING_LAG_HZ, dt * 0.5)
	check_approx(half * half, one_step, "two half-steps equal one whole step", 1e-6)

	var naive := 1.0 - HEADING_LAG_HZ * dt
	check_ne(
		is_equal_approx(naive * naive, naive),
		true,
		"and the linear form this replaces does not have that property"
	)


func test_the_lag_is_bounded_and_monotonic() -> void:
	var dt := 1.0 / 60.0
	check_true(ChaseCamera._lag(HEADING_LAG_HZ, 0.0) == 0.0, "no time, no movement")
	check_true(ChaseCamera._lag(HEADING_LAG_HZ, dt) > 0.0, "some time, some movement")
	check_true(ChaseCamera._lag(HEADING_LAG_HZ, 10.0) < 1.0, "and it never overshoots")
	check_true(
		ChaseCamera._lag(HEADING_LAG_HZ, dt * 2.0) > ChaseCamera._lag(HEADING_LAG_HZ, dt),
		"a longer frame closes more of the gap"
	)


func test_the_heading_delta_takes_the_short_way_round() -> void:
	# A hull spinning through north must not take the camera the long way. The
	# assertion is a sign, because a magnitude passes against the long arc.
	var from := deg_to_rad(170.0)
	var to := deg_to_rad(-170.0)
	var delta := ChaseCamera._angle_delta(from, to)
	check_approx(delta, deg_to_rad(20.0), "170° to -170° is +20°, not -340°")
	check_true(absf(delta) <= PI, "and never more than half a turn")

	check_approx(
		ChaseCamera._angle_delta(deg_to_rad(-170.0), deg_to_rad(170.0)),
		deg_to_rad(-20.0),
		"and the reverse is -20°, not +340°"
	)


## ===== §13.5 FRAMING ===================================================


func test_the_pitch_limits_favour_looking_down() -> void:
	# §13.5 states the asymmetry as a decision rather than an accident: the
	# useful information in this game is on the ground, so travel spent looking
	# at the sky is travel wasted.
	check_true(
		absf(PITCH_MIN_DEG) > absf(PITCH_MAX_DEG),
		"the camera can look further down than up"
	)
	check_approx(ChaseCamera.PITCH_MIN_DEG, PITCH_MIN_DEG, "§13.5's down limit")
	check_approx(ChaseCamera.PITCH_MAX_DEG, PITCH_MAX_DEG, "§13.5's up limit")


func test_the_follow_distance_grows_with_the_assembly_and_then_stops() -> void:
	# A lattice build has no fixed silhouette, so the distance scales — and it is
	# capped, because a forty-part build framed by an uncapped rule is a map
	# rather than a vehicle.
	var small := ChaseCamera.CHASE_DISTANCE_BASE_M + ChaseCamera.CHASE_DISTANCE_PER_RADIUS * 2.0
	var large := ChaseCamera.CHASE_DISTANCE_BASE_M + ChaseCamera.CHASE_DISTANCE_PER_RADIUS * 40.0
	check_true(large > small, "a bigger Assembly is framed from further away")
	check_true(
		minf(large, ChaseCamera.CHASE_DISTANCE_MAX_M) == ChaseCamera.CHASE_DISTANCE_MAX_M,
		"and the ceiling binds before the build gets absurd"
	)


## ===== §13.8 WHAT THE AIM RAY STRUCK ===================================


## §14.3's target bracket asks one question of the ray's collider and the whole
## of the answer is a layer test. Asserted in both directions, because a
## predicate that answered true for everything would light the bracket over open
## ground — which is the exact confusion the bracket was added to remove.
func test_only_a_body_on_the_hull_layer_reads_as_a_target() -> void:
	var hull := StaticBody3D.new()
	hull.collision_layer = CollisionLayers.LAYER_ASSEMBLY_HULL
	var ground := StaticBody3D.new()
	ground.collision_layer = CollisionLayers.LAYER_GROUND
	var volume := StaticBody3D.new()
	volume.collision_layer = CollisionLayers.LAYER_STATIC_VOLUME

	check_true(ChaseCamera.is_hull(hull), "a chassis body is a target")
	check_false(ChaseCamera.is_hull(ground), "streamed ground is not")
	check_false(ChaseCamera.is_hull(volume), "a Static Volume section is not")
	check_false(ChaseCamera.is_hull(null), "and a ray that hit nothing is not")

	hull.free()
	ground.free()
	volume.free()


## A body presenting on more than one layer still counts, which is what stops the
## predicate being an equality test that happens to pass against the shipped
## chassis body's single layer.
func test_a_body_on_several_layers_still_reads_as_a_target() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = (
		CollisionLayers.LAYER_ASSEMBLY_HULL | CollisionLayers.LAYER_TRIGGER_VOLUME
	)
	check_true(ChaseCamera.is_hull(body), "the hull bit is tested, not the whole mask")
	body.free()
