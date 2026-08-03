extends TestCase
## Doc 02 §6's cursor-to-cell resolution — the integer half.
##
## §6 is the only place in the system where floating point influences a lattice
## decision, and its whole discipline is that the float ends immediately: a ray
## produces a hit position and a surface normal, and those become an integer face
## and an integer cell before anything else sees them. Invariant I-6.
##
## [b]The float half is not testable here and the integer half is all of the
## risk.[/b] A camera has to be in a viewport to project a ray, and a
## [SubViewport] has no [World3D] headless (LEARNED_FACTS.md §1 fact 28) — so
## what a test can reach is [method GaragePreview.dominant_axis],
## [method GaragePreview.solve_origin] and the anchor arithmetic between them,
## which is where a wrong answer is silent. A ray that misses is a ghost that
## does not appear and a player notices in the first second; an origin solved by
## subtracting an unrotated node cell is a part that lands one cell off at
## orientation 8 and looks like a placement rule nobody can find.

const PANEL_KEY: StringName = &"str.panel.medium.t2"
const CORE_KEY: StringName = &"core.command.compact.t2"
const HUB_KEY: StringName = &"str.hub.axle_station.t2"

## A cell in the middle of the lattice, so that no answer here is clamped by a
## bound rather than computed.
const HOST_CELL := Vector3i(24, 4, 24)


## §6.3. The mating face is the dominant axis of the surface normal, and a
## diagonal normal has to resolve to exactly one axis rather than to two.
func test_the_face_is_the_dominant_axis_of_the_normal() -> void:
	check_eq(GaragePreview.dominant_axis(Vector3.UP), Vector3i.UP, "straight up")
	check_eq(GaragePreview.dominant_axis(Vector3.DOWN), Vector3i.DOWN, "straight down")
	check_eq(GaragePreview.dominant_axis(Vector3.RIGHT), Vector3i.RIGHT, "+X")
	check_eq(GaragePreview.dominant_axis(Vector3.LEFT), Vector3i.LEFT, "-X")
	check_eq(
		GaragePreview.dominant_axis(Vector3.FORWARD),
		Vector3i.FORWARD,
		"and -Z is forward, which is the convention every muzzle and drive face uses"
	)
	check_eq(GaragePreview.dominant_axis(Vector3.BACK), Vector3i.BACK, "+Z")


## A normal from a real surface is never axis-aligned to the last bit. What
## matters is that a near-vertical one still answers "up" and that the answer is
## a unit axis rather than a rounded vector with two non-zero components.
func test_a_nearly_axis_aligned_normal_still_answers_one_axis() -> void:
	var tilted := Vector3(0.08, 0.99, -0.11).normalized()
	check_eq(GaragePreview.dominant_axis(tilted), Vector3i.UP, "a face tilted 8° is a face")
	var diagonal := Vector3(0.7, 0.71, 0.0).normalized()
	var answer := GaragePreview.dominant_axis(diagonal)
	check_eq(
		absi(answer.x) + absi(answer.y) + absi(answer.z),
		1,
		"a 45° normal resolves to exactly one axis rather than to two"
	)


## §6.4. The origin is solved by subtraction: the anchor cell must coincide with
## the candidate's own cell adjacent to the node whose rotated face is `−face`.
##
## Asserted as a round trip through [PlacementCandidate], because the claim is
## not "the arithmetic is this expression" but "the part's own cells land on the
## anchor". A solve that dropped the rotation would satisfy the first and fail
## the second at every orientation but zero.
func test_the_solved_origin_puts_a_cell_on_the_anchor() -> void:
	var def := PartRegistry.definition_by_key(PANEL_KEY)
	check_not_null(def, "the panel is registered")
	if def == null:
		return
	for orientation: int in SyndicateConstants.ORIENTATION_COUNT:
		var anchor := HOST_CELL + Vector3i.UP
		var origin := GaragePreview.solve_origin(def, orientation, anchor, Vector3i.UP)
		if origin == GaragePreview.NO_ORIGIN:
			# Not every orientation presents a downward-facing node, and a part
			# that cannot mate through this face is an honest "no answer".
			continue
		var candidate := PlacementCandidate.create(def, origin, orientation)
		check_true(
			candidate.cells.has(Vector3(anchor)),
			"at orientation %d the part occupies the anchor cell it was solved for" % orientation
		)


## The rotation is the half that a fixture at orientation 0 cannot see. The
## identity orientation makes the subtraction commute with everything, which is
## the fixture trap recorded for the collider path — so the assertion is that at
## least one non-identity orientation answers a [i]different[/i] origin.
func test_the_node_cell_is_rotated_before_it_is_subtracted() -> void:
	var def := PartRegistry.definition_by_key(HUB_KEY)
	check_not_null(def, "the station is registered")
	if def == null:
		return
	var anchor := HOST_CELL + Vector3i.UP
	var identity := GaragePreview.solve_origin(
		def, OrientationTable.IDENTITY_INDEX, anchor, Vector3i.UP
	)
	var differed := false
	for orientation: int in SyndicateConstants.ORIENTATION_COUNT:
		if orientation == OrientationTable.IDENTITY_INDEX:
			continue
		var origin := GaragePreview.solve_origin(def, orientation, anchor, Vector3i.UP)
		if origin != GaragePreview.NO_ORIGIN and origin != identity:
			differed = true
			break
	check_true(
		differed,
		"some orientation solves a different origin for the same anchor and face"
	)


## A part with no node facing the way the anchor needs has no answer, and the
## sentinel says so rather than returning a plausible cell.
##
## The sentinel is an int32 extreme rather than a 64-bit one, because a
## [Vector3i] component wraps silently (LEARNED_FACTS.md §1 fact 5) — a wrapped
## sentinel is a cell inside the lattice and would read as a legal placement.
func test_a_face_the_part_cannot_mate_through_has_no_answer() -> void:
	var def := PartRegistry.definition_by_key(CORE_KEY)
	check_not_null(def, "the Core Module is registered")
	if def == null:
		return
	var wanted := 0
	for node: AttachmentNodeDef in def.attachment_nodes:
		if OrientationTable.rotate_face(OrientationTable.IDENTITY_INDEX, node.face_normal) == Vector3i.DOWN:
			wanted += 1
	if wanted > 0:
		# The Core Module does present downward nodes, so the no-answer case is
		# staged with a face nothing can present: a zero face is not an axis.
		check_eq(
			GaragePreview.solve_origin(
				def, OrientationTable.IDENTITY_INDEX, HOST_CELL, Vector3i.ZERO
			),
			GaragePreview.NO_ORIGIN,
			"a face that is not an axis has no mating node"
		)
	check_false(
		LatticeMath.in_bounds(GaragePreview.NO_ORIGIN),
		"and the sentinel is outside the lattice, so a caller that ignored it is refused"
	)
	check_true(
		GaragePreview.NO_ORIGIN.x < 0,
		"stored without wrapping: %d" % GaragePreview.NO_ORIGIN.x
	)
