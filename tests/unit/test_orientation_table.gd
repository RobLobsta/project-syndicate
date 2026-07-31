extends TestCase
## Group properties of [OrientationTable].
##
## The index-to-basis mapping is serialised in blueprints and network packets,
## so these tests are as much a change detector as a correctness check. If
## [method test_frozen_index_mapping] fails, either the construction changed —
## which breaks every saved Assembly in existence — or a Godot upgrade altered
## [Basis] semantics. Neither is a test to "just update".


func test_table_has_exactly_twenty_four_entries() -> void:
	check_eq(OrientationTable.COUNT, 24, "proper octahedral group order")
	check_eq(
		OrientationTable.COUNT,
		SyndicateConstants.ORIENTATION_COUNT,
		"table size tracks the owning constant"
	)


func test_every_basis_is_integral_and_a_rotation() -> void:
	for i in OrientationTable.COUNT:
		var b := OrientationTable.basis_for(i)
		var columns: Array[Vector3] = [b.x, b.y, b.z]
		for col in 3:
			var v := columns[col]
			for axis in 3:
				var c: float = v[axis]
				if not (is_equal_approx(c, 0.0) or is_equal_approx(absf(c), 1.0)):
					fail("orientation %d column %d is not integral: %v" % [i, col, v])
		# Determinant +1 excludes mirrors, which the design deliberately omits.
		check_approx(b.determinant(), 1.0, "orientation %d must be a proper rotation" % i)


func test_all_twenty_four_rotations_are_distinct() -> void:
	var seen := {}
	for i in OrientationTable.COUNT:
		var image := OrientationTable.rotate_cell(i, OrientationTable.PROBE)
		if seen.has(image):
			fail("orientations %d and %d are the same rotation" % [seen[image], i])
		seen[image] = i
	check_eq(seen.size(), OrientationTable.COUNT, "24 distinct group elements")


func test_identity_is_index_zero() -> void:
	check_eq(
		OrientationTable.rotate_cell(OrientationTable.IDENTITY_INDEX, OrientationTable.PROBE),
		OrientationTable.PROBE,
		"index 0 must be the identity"
	)


func test_up_axis_ordering_is_frozen() -> void:
	# up_facing selects which part-local axis becomes world +Y. Index
	# up_facing * 4 is that rotation with zero roll.
	for up_facing in 6:
		var index := up_facing * 4
		var mapped := OrientationTable.rotate_cell(index, Vector3i(0, 1, 0))
		check_eq(
			mapped,
			OrientationTable.UP_AXES[up_facing],
			"orientation %d must carry local +Y onto UP_AXES[%d]" % [index, up_facing]
		)


func test_composition_is_closed_and_associative() -> void:
	var out_of_range := 0
	for a in OrientationTable.COUNT:
		for b in OrientationTable.COUNT:
			var c := OrientationTable.compose(a, b)
			if c < 0 or c >= OrientationTable.COUNT:
				out_of_range += 1
	check_eq(out_of_range, 0, "composition never leaves the group")

	# Associativity on a sample: (a*b)*c == a*(b*c). Exhaustive would be 13 824
	# triples, which is affordable but adds nothing over a strided sample.
	var mismatches := 0
	for a in range(0, OrientationTable.COUNT, 5):
		for b in range(0, OrientationTable.COUNT, 3):
			for c in range(0, OrientationTable.COUNT, 7):
				var left := OrientationTable.compose(OrientationTable.compose(a, b), c)
				var right := OrientationTable.compose(a, OrientationTable.compose(b, c))
				if left != right:
					mismatches += 1
	check_eq(mismatches, 0, "composition must be associative")


func test_composition_matches_sequential_rotation() -> void:
	var probe := Vector3i(3, -5, 7)
	var mismatches := 0
	for a in OrientationTable.COUNT:
		for b in OrientationTable.COUNT:
			var composed := OrientationTable.rotate_cell(OrientationTable.compose(a, b), probe)
			var sequential := OrientationTable.rotate_cell(a, OrientationTable.rotate_cell(b, probe))
			if composed != sequential:
				mismatches += 1
	check_eq(mismatches, 0, "compose(a,b) must equal applying b then a")


func test_inverse_table_is_a_true_inverse() -> void:
	for i in OrientationTable.COUNT:
		var inv := OrientationTable.inverse_of(i)
		check_eq(
			OrientationTable.compose(i, inv),
			OrientationTable.IDENTITY_INDEX,
			"orientation %d composed with its inverse %d must be identity" % [i, inv]
		)
		check_eq(
			OrientationTable.compose(inv, i),
			OrientationTable.IDENTITY_INDEX,
			"inverse must commute to identity for orientation %d" % i
		)


func test_rotate_face_preserves_axis_units() -> void:
	for i in OrientationTable.COUNT:
		for face in AttachmentNodeDef.AXIS_NORMALS:
			var rotated := OrientationTable.rotate_face(i, face)
			var magnitude := absi(rotated.x) + absi(rotated.y) + absi(rotated.z)
			check_eq(magnitude, 1, "orientation %d must map %v to an axis unit" % [i, face])


func test_index_of_basis_recovers_every_orientation() -> void:
	for i in OrientationTable.COUNT:
		check_eq(
			OrientationTable.index_of_basis(OrientationTable.basis_for(i)),
			i,
			"index_of_basis must invert basis_for at %d" % i
		)


func test_index_of_basis_rejects_a_non_member() -> void:
	# A 45-degree yaw is not in the octahedral group.
	var skew := Basis(Vector3(0, 1, 0), PI * 0.25)
	check_eq(OrientationTable.index_of_basis(skew), -1, "non-member basis must return -1")


func test_frozen_index_mapping() -> void:
	# Guards the serialised mapping. Each entry is the image of PROBE (1,2,3)
	# under that orientation, captured from the normative construction.
	var expected := [
		Vector3i(1, 2, 3),
		Vector3i(3, 2, -1),
		Vector3i(-1, 2, -3),
		Vector3i(-3, 2, 1),
		Vector3i(1, -2, -3),
		Vector3i(-3, -2, -1),
		Vector3i(-1, -2, 3),
		Vector3i(3, -2, 1),
		Vector3i(2, -1, 3),
		Vector3i(3, -1, -2),
		Vector3i(-2, -1, -3),
		Vector3i(-3, -1, 2),
		Vector3i(-2, 1, 3),
		Vector3i(3, 1, 2),
		Vector3i(2, 1, -3),
		Vector3i(-3, 1, -2),
		Vector3i(1, -3, 2),
		Vector3i(2, -3, -1),
		Vector3i(-1, -3, -2),
		Vector3i(-2, -3, 1),
		Vector3i(1, 3, -2),
		Vector3i(-2, 3, -1),
		Vector3i(-1, 3, 2),
		Vector3i(2, 3, 1),
	]
	for i in OrientationTable.COUNT:
		check_eq(
			OrientationTable.rotate_cell(i, OrientationTable.PROBE),
			expected[i],
			"orientation %d has changed; saved blueprints would decode wrongly" % i
		)
