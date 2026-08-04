extends TestCase
## [PartMeshFactory]'s pose arithmetic, from
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §16.
##
## Three transforms share one placement pose and must not become three answers:
## where a part is drawn at rest, where it is drawn once its suspension has
## extended, and where a limb is drawn once it is pointing at its foot. Only the
## first of the three was ever asserted, and the other two are what a player
## watches for the whole of a match.
##
## Everything here is a synthetic [PartVisualProfile] with a stated offset and
## scale, because the two functions under test compose the placement pose with
## those in a fixed order and a profile that authors neither cannot tell a
## correct composition from any other.

## A non-zero authored offset and a non-uniform scale, so that neither function
## can be right by accident: a displacement composed on the wrong side of the
## placement pose is rotated by the part's orientation and moved by the offset,
## and a turn taken about the mesh origin rather than about the hip is visible
## only when the two are different points.
const OFFSET := Vector3(0.10, -0.20, 0.30)
const SCALE := Vector3(1.0, 1.4, 1.0)

const CELL := Vector3i(24, 4, 24)

## Enough to be unambiguous against the lattice quantum, and less than the
## shipped 0.24 m travel so the number is not one the source could confuse with
## a limit.
const DROOP: float = 0.17

var _vp: PartVisualProfile = null


func before_all() -> void:
	_vp = PartVisualProfile.new()
	_vp.visual_offset_m = OFFSET
	_vp.visual_scale = SCALE


## ===== §16.1 SUSPENSION TRAVEL =========================================


func test_a_drooping_part_is_drawn_below_where_it_was_placed() -> void:
	var placed := PartMeshFactory.pose(_vp, CELL, 0)
	var drawn := PartMeshFactory.contact_pose(_vp, CELL, 0, DROOP)
	# Below, and the sign is the whole assertion: a wheel drawn *up* by its
	# unconsumed travel moves exactly as much and disappears into the hull.
	check_approx(placed.origin.y - drawn.origin.y, DROOP, "lowered by the droop it was given")
	check_approx(drawn.origin.x, placed.origin.x, "and not moved across the hull")
	check_approx(drawn.origin.z, placed.origin.z, "nor along it")


func test_droop_leaves_the_part_pointing_where_it_was_placed() -> void:
	# A translation, never a rotation. A wheel that tilted as its suspension
	# moved would read as a bent axle.
	var placed := PartMeshFactory.pose(_vp, CELL, 7)
	var drawn := PartMeshFactory.contact_pose(_vp, CELL, 7, DROOP)
	check_true(drawn.basis.is_equal_approx(placed.basis), "the orientation is untouched")


func test_zero_droop_is_the_placement_pose_exactly() -> void:
	# The bottomed-out case, and the guarantee that §16 changes nothing about
	# where a part is drawn until a probe says something.
	check_true(
		PartMeshFactory.contact_pose(_vp, CELL, 11, 0.0).is_equal_approx(
			PartMeshFactory.pose(_vp, CELL, 11)
		),
		"a contact with no travel left to show is drawn at its placement"
	)


func test_the_droop_runs_down_the_chassis_and_not_down_the_part() -> void:
	# The one composition error this function exists to prevent. A Motive
	# Assembly mounted on its side is a legal build, and a droop composed onto
	# the right of the placement pose would carry it sideways along the hull
	# rather than downward — which reads as a wheel drifting out of its arch.
	var sideways := _orientation_carrying_down_onto(Vector3.RIGHT)
	if not check_true(sideways >= 0, "the orientation group carries local down onto +X"):
		return
	var placed := PartMeshFactory.pose(_vp, CELL, sideways)
	var drawn := PartMeshFactory.contact_pose(_vp, CELL, sideways, DROOP)
	check_approx(placed.origin.y - drawn.origin.y, DROOP, "still straight down the hull")
	check_approx(drawn.origin.x, placed.origin.x, "and not out along the part's own down")


## ===== §16.3 THE VIRTUAL LEG ===========================================


func test_a_limb_points_its_leg_axis_at_its_foot() -> void:
	var hip := Vector3(0.0, 1.0, 0.0)
	# Forward of the hip and below it, which is where a foot reaching for the
	# next plant point is.
	var foot := Vector3(0.0, -0.6, -1.2)
	var drawn := PartMeshFactory.limb_pose(_vp, CELL, 0, hip, foot)
	var leg := (drawn.basis.orthonormalized() * Vector3.DOWN).normalized()
	check_true(
		leg.is_equal_approx((foot - hip).normalized()),
		"the part's own down runs from the hip to the foot"
	)


func test_the_hip_is_the_pivot_and_does_not_move() -> void:
	# The property that makes this a leg rather than a part sliding about. The
	# hip is bolted to the chassis; only what hangs off it swings.
	var hip := Vector3(0.5, 1.0, -0.25)
	var foot := Vector3(1.4, -0.7, -0.9)
	var placed := PartMeshFactory.pose(_vp, CELL, 0)
	var drawn := PartMeshFactory.limb_pose(_vp, CELL, 0, hip, foot)
	# The hip expressed through each transform is the same world point, which is
	# what "pivoted about the hip" means and what a rotation about the mesh's own
	# origin would fail.
	check_approx(
		(drawn.origin - hip).length(),
		(placed.origin - hip).length(),
		"the mesh keeps its distance from the hip through the turn"
	)
	var swung := drawn.origin - placed.origin
	check_true(swung.length() > 0.05, "and it did turn rather than sit still")


func test_a_limb_hanging_straight_down_is_left_where_it_was_placed() -> void:
	# The rest case. A foot directly below the hip is exactly what the placement
	# pose already draws, so the turn must be the identity rather than merely
	# small.
	var hip := Vector3(0.0, 1.0, 0.0)
	var drawn := PartMeshFactory.limb_pose(_vp, CELL, 0, hip, hip + Vector3.DOWN * 1.6)
	check_true(
		drawn.is_equal_approx(PartMeshFactory.pose(_vp, CELL, 0)),
		"a foot under its hip needs no turn at all"
	)


func test_a_foot_at_the_hip_leaves_the_pose_alone() -> void:
	# Degenerate rather than erroneous: a zero-length leg has no direction to
	# point along, and normalising it would hand the basis a NaN that propagates
	# into the mesh's transform and takes the whole Assembly off screen.
	var hip := Vector3(0.0, 1.0, 0.0)
	check_true(
		PartMeshFactory.limb_pose(_vp, CELL, 0, hip, hip).is_equal_approx(
			PartMeshFactory.pose(_vp, CELL, 0)
		),
		"a foot at the hip draws the limb at its placement"
	)


func test_the_leg_axis_is_the_parts_own_down_and_not_the_hulls() -> void:
	# The one composition error §16.3 can make. A limb mounted on its side is a
	# legal placement, and turning the *hull's* down onto the hip-to-foot line
	# instead of the part's is the identity at orientation 0 — so every test
	# above passes against it — while pointing the drawn limb ninety degrees away
	# from its foot at this one.
	var sideways := _orientation_carrying_down_onto(Vector3.RIGHT)
	if not check_true(sideways >= 0, "the orientation group carries local down onto +X"):
		return
	var hip := Vector3(0.0, 1.0, 0.0)
	var foot := Vector3(1.1, -0.4, 0.0)
	var drawn := PartMeshFactory.limb_pose(_vp, CELL, sideways, hip, foot)
	var leg := (drawn.basis.orthonormalized() * Vector3.DOWN).normalized()
	check_true(
		leg.is_equal_approx((foot - hip).normalized()),
		"the part's own down reaches the foot from a sideways mounting too"
	)


## The orientation index carrying a part's local down onto [param axis] in
## assembly space, or -1.
##
## Searched rather than written down: which of the 24 does this is a property of
## [OrientationTable] and a literal index would survive a change to the table
## while meaning something else.
func _orientation_carrying_down_onto(axis: Vector3) -> int:
	for i: int in SyndicateConstants.ORIENTATION_COUNT:
		if (OrientationTable.basis_for(i) * Vector3.DOWN).is_equal_approx(axis):
			return i
	return -1
