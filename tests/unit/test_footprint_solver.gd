extends TestCase
## [FootprintSolver] — placement resolution in integers only (I-6).
##
## The invariants worth guarding are structural: a rotation may move a footprint
## but must never change how many cells it occupies or its shape, and a node's
## face must stay an axis unit under every one of the 24 orientations. Both would
## fail silently — as a part that occupies the wrong cells, or an attachment that
## mates in a direction the geometry does not support.


func test_identity_orientation_offsets_by_the_origin() -> void:
	var def := _l_shape()
	var cells := FootprintSolver.resolve_cells(def, Vector3i(10, 4, 10), 0)
	check_eq(cells.size(), 4, "four cells resolved")
	check_eq(Vector3i(cells[0]), Vector3i(10, 4, 10), "pivot cell lands on the origin")
	check_eq(Vector3i(cells[1]), Vector3i(11, 4, 10), "+x cell offsets with the origin")
	check_eq(Vector3i(cells[3]), Vector3i(10, 5, 10), "+y cell offsets with the origin")


func test_out_parameter_fills_the_callers_buffer() -> void:
	# The ghost preview depends on this: it reuses one buffer every frame rather
	# than allocating. If packed arrays ever stop passing by reference, the
	# preview would silently render an empty footprint.
	var def := _l_shape()
	var buffer := PackedVector3Array()
	FootprintSolver.resolve(def, Vector3i(5, 5, 5), 0, buffer)
	check_eq(buffer.size(), 4, "the caller's buffer was resized and filled")
	check_eq(Vector3i(buffer[0]), Vector3i(5, 5, 5), "the caller sees resolved cells")


func test_reused_buffer_shrinks_for_a_smaller_part() -> void:
	var buffer := PackedVector3Array()
	FootprintSolver.resolve(_l_shape(), Vector3i.ZERO, 0, buffer)
	check_eq(buffer.size(), 4, "four cells for the L shape")
	FootprintSolver.resolve(_single_cell(), Vector3i.ZERO, 0, buffer)
	check_eq(buffer.size(), 1, "buffer shrinks; stale cells must not linger")


func test_every_orientation_preserves_cell_count() -> void:
	var def := _l_shape()
	for orientation in OrientationTable.COUNT:
		var cells := FootprintSolver.resolve_cells(def, Vector3i(24, 10, 24), orientation)
		check_eq(cells.size(), 4, "orientation %d must occupy four cells" % orientation)


func test_every_orientation_preserves_shape() -> void:
	# A rotation is rigid: the multiset of pairwise offsets from the pivot must
	# have the same extent in some axis permutation. Checking the bounding box
	# volume is the cheap invariant that catches a broken rotation matrix.
	var def := _l_shape()
	for orientation in OrientationTable.COUNT:
		var cells := FootprintSolver.resolve_cells(def, Vector3i(24, 10, 24), orientation)
		var box := FootprintSolver.bounds_of(cells)
		var size: Vector3i = box[1] - box[0] + Vector3i.ONE
		var volume := size.x * size.y * size.z
		check_eq(volume, 6, "orientation %d must keep a 3x2x1 bounding box" % orientation)


func test_every_orientation_produces_distinct_cells() -> void:
	# Two cells of one part collapsing onto each other would let a part overlap
	# itself, and LatticeOccupancy would then double-count the cell.
	var def := _l_shape()
	for orientation in OrientationTable.COUNT:
		var cells := FootprintSolver.resolve_cells(def, Vector3i(24, 10, 24), orientation)
		var seen := {}
		for c in cells:
			seen[Vector3i(c)] = true
		check_eq(seen.size(), cells.size(), "orientation %d must not fold cells together" % orientation)


func test_identity_orientation_is_a_no_op_on_cells() -> void:
	var def := _l_shape()
	var cells := FootprintSolver.resolve_cells(def, Vector3i.ZERO, OrientationTable.IDENTITY_INDEX)
	for i in def.occupancy_cells.size():
		check_eq(
			Vector3i(cells[i]),
			Vector3i(def.occupancy_cells[i]),
			"identity must return the authored cell %d unchanged" % i
		)


func test_all_in_bounds_detects_a_footprint_leaving_the_lattice() -> void:
	var def := _l_shape()
	check_true(
		FootprintSolver.all_in_bounds(FootprintSolver.resolve_cells(def, Vector3i(24, 4, 24), 0)),
		"a footprint at the lattice origin is in bounds"
	)
	check_false(
		FootprintSolver.all_in_bounds(FootprintSolver.resolve_cells(def, Vector3i(0, 0, 0), 4)),
		"a footprint rotated off the near corner is out of bounds"
	)
	var far := SyndicateConstants.LATTICE_EXTENT - Vector3i.ONE
	check_false(
		FootprintSolver.all_in_bounds(FootprintSolver.resolve_cells(def, far, 0)),
		"a footprint starting on the far corner extends past it"
	)


func test_nodes_rotate_with_the_part() -> void:
	var def := _l_shape()
	var nodes := FootprintSolver.resolve_nodes(def, Vector3i(20, 8, 20), 0)
	check_eq(nodes.size(), 2, "both authored nodes resolved")
	check_eq(nodes[0].cell, Vector3i(20, 8, 20), "node 0 sits on the pivot cell")
	check_eq(nodes[0].face, Vector3i(0, -1, 0), "node 0 faces down at identity")
	check_eq(nodes[1].face, Vector3i(0, 1, 0), "node 1 faces up at identity")


func test_node_faces_stay_axis_units_under_every_orientation() -> void:
	var def := _l_shape()
	for orientation in OrientationTable.COUNT:
		for node in FootprintSolver.resolve_nodes(def, Vector3i(24, 10, 24), orientation):
			var magnitude := absi(node.face.x) + absi(node.face.y) + absi(node.face.z)
			check_eq(magnitude, 1, "orientation %d must keep node faces on an axis" % orientation)


func test_resolved_nodes_carry_the_source_definition() -> void:
	# Architectural Invariant I-11: polarity and joint strength resolve against
	# the immutable definition, never a copy that could drift from it.
	var def := _l_shape()
	var nodes := FootprintSolver.resolve_nodes(def, Vector3i.ZERO, 0)
	check_eq(nodes[0].source, def.attachment_nodes[0], "node 0 carries its definition")
	check_eq(nodes[1].source, def.attachment_nodes[1], "node 1 carries its definition")


func test_mating_cell_steps_one_along_the_face() -> void:
	var node := ResolvedNode.new()
	node.source = AttachmentNodeDef.new()
	node.cell = Vector3i(10, 10, 10)
	node.face = Vector3i(0, 1, 0)
	check_eq(node.mating_cell(), Vector3i(10, 11, 10), "mating cell is one step along the face")


func test_opposing_nodes_mate_and_parallel_ones_do_not() -> void:
	var upward := _node(Vector3i(10, 10, 10), Vector3i(0, 1, 0), PartEnums.AttachmentPolarity.FACE_MALE)
	var downward := _node(
		Vector3i(10, 11, 10), Vector3i(0, -1, 0), PartEnums.AttachmentPolarity.FACE_FEMALE
	)
	check_true(upward.opposes(downward), "male up mates with female down in the next cell")
	check_true(downward.opposes(upward), "mating is symmetric")

	var same_direction := _node(
		Vector3i(10, 11, 10), Vector3i(0, 1, 0), PartEnums.AttachmentPolarity.FACE_FEMALE
	)
	check_false(upward.opposes(same_direction), "two nodes facing the same way do not mate")

	var too_far := _node(
		Vector3i(10, 12, 10), Vector3i(0, -1, 0), PartEnums.AttachmentPolarity.FACE_FEMALE
	)
	check_false(upward.opposes(too_far), "nodes two cells apart do not mate")


func test_two_way_adjacency_already_implies_opposing_faces() -> void:
	# [method ResolvedNode.is_face_paired] tests adjacency in both directions and
	# then tests that the faces oppose. The second test is provably redundant:
	# a.cell + a.face == b.cell and b.cell + b.face == a.cell together give
	# a.face == -b.face. It is kept because §7.3 states the rule and a reader
	# should not have to derive it — but it is kept knowingly, not because it
	# rejects anything the adjacency test admits, and this exhaustive sweep over
	# all thirty-six face pairings is what says so.
	var unopposed_but_adjacent := 0
	for a_face: Vector3i in AttachmentNodeDef.AXIS_NORMALS:
		for b_face: Vector3i in AttachmentNodeDef.AXIS_NORMALS:
			var a := _node(Vector3i(10, 10, 10), a_face, PartEnums.AttachmentPolarity.FACE_NEUTRAL)
			var b := _node(
				Vector3i(10, 10, 10) + a_face, b_face, PartEnums.AttachmentPolarity.FACE_NEUTRAL
			)
			var two_way := b.cell == a.mating_cell() and a.cell == b.mating_cell()
			if two_way and a_face != -b_face:
				unopposed_but_adjacent += 1
			check_eq(
				a.is_face_paired(b), two_way and a_face == -b_face,
				"faces %v and %v pair iff adjacent both ways and opposed" % [a_face, b_face]
			)
	check_eq(
		unopposed_but_adjacent, 0,
		"no face pairing is adjacent in both directions without also opposing"
	)


func test_incompatible_polarities_do_not_mate() -> void:
	var male_a := _node(Vector3i(0, 0, 0), Vector3i(0, 1, 0), PartEnums.AttachmentPolarity.FACE_MALE)
	var male_b := _node(Vector3i(0, 1, 0), Vector3i(0, -1, 0), PartEnums.AttachmentPolarity.FACE_MALE)
	check_false(male_a.opposes(male_b), "two male faces do not mate")

	var axle := _node(Vector3i(0, 0, 0), Vector3i(1, 0, 0), PartEnums.AttachmentPolarity.AXLE)
	var neutral := _node(
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0), PartEnums.AttachmentPolarity.FACE_NEUTRAL
	)
	check_false(axle.opposes(neutral), "an axle mates only with another axle")


func test_seated_origin_places_the_footprint_corner_on_the_target() -> void:
	var def := _l_shape()
	for orientation in OrientationTable.COUNT:
		var target := Vector3i(24, 6, 24)
		var origin := FootprintSolver.origin_for_seated_footprint(def, target, orientation)
		var cells := FootprintSolver.resolve_cells(def, origin, orientation)
		var box := FootprintSolver.bounds_of(cells)
		check_eq(box[0], target, "orientation %d seats its minimum corner on the target" % orientation)


func test_bounds_of_an_empty_footprint_is_a_zero_box() -> void:
	var box := FootprintSolver.bounds_of(PackedVector3Array())
	check_eq(box[0], Vector3i.ZERO, "empty minimum")
	check_eq(box[1], Vector3i.ZERO, "empty maximum")


## An L shape occupying four of the six cells of a 3x2x1 box, with a downward
## node on the pivot and an upward node on the raised cell. Asymmetric on all
## three axes so that a transposed rotation matrix cannot pass unnoticed.
func _l_shape() -> PartDefinition:
	var def := PartDefinition.new()
	def.occupancy_cells = PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(2, 0, 0),
		Vector3(0, 1, 0),
	])
	def.attachment_nodes = [
		_def_node(Vector3i(0, 0, 0), Vector3i(0, -1, 0), PartEnums.AttachmentPolarity.FACE_MALE),
		_def_node(Vector3i(0, 1, 0), Vector3i(0, 1, 0), PartEnums.AttachmentPolarity.FACE_FEMALE),
	]
	def._bake_derived_fields()
	return def


func _single_cell() -> PartDefinition:
	var def := PartDefinition.new()
	def.occupancy_cells = PackedVector3Array([Vector3.ZERO])
	def._bake_derived_fields()
	return def


func _def_node(
	cell: Vector3i, face: Vector3i, polarity: PartEnums.AttachmentPolarity
) -> AttachmentNodeDef:
	var node := AttachmentNodeDef.new()
	node.cell = cell
	node.face_normal = face
	node.polarity = polarity
	return node


func _node(
	cell: Vector3i, face: Vector3i, polarity: PartEnums.AttachmentPolarity
) -> ResolvedNode:
	var rn := ResolvedNode.new()
	rn.source = _def_node(Vector3i.ZERO, face, polarity)
	rn.cell = cell
	rn.face = face
	return rn
