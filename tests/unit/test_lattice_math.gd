extends TestCase
## Conversions and indexing of [LatticeMath].
##
## The round-trip properties matter more than any individual value: the whole
## reason for a 0.25 m lattice unit is that cell/metre conversion is exact at
## every coordinate, and a regression there would show up as parts drifting by a
## fraction of a cell after a save/load cycle.


func test_origin_cell_maps_to_half_cell_offset() -> void:
	var p := LatticeMath.cell_to_local(SyndicateConstants.LATTICE_ORIGIN_CELL)
	var half := SyndicateConstants.LATTICE_UNIT_M * 0.5
	check_approx(p.x, half, "origin cell centre x")
	check_approx(p.y, half, "origin cell centre y")
	check_approx(p.z, half, "origin cell centre z")


func test_cell_to_local_round_trips_across_the_whole_lattice() -> void:
	# Every eleventh cell on each axis: coprime with all three extents, so the
	# sample sweeps the full range rather than hitting one plane repeatedly.
	var mismatches := 0
	for x in range(0, SyndicateConstants.LATTICE_EXTENT.x, 11):
		for y in range(0, SyndicateConstants.LATTICE_EXTENT.y, 11):
			for z in range(0, SyndicateConstants.LATTICE_EXTENT.z, 11):
				var cell := Vector3i(x, y, z)
				if LatticeMath.local_to_cell(LatticeMath.cell_to_local(cell)) != cell:
					mismatches += 1
	check_eq(mismatches, 0, "cell -> metres -> cell must be exact")


func test_local_to_cell_floors_rather_than_rounds() -> void:
	var u := SyndicateConstants.LATTICE_UNIT_M
	var origin := SyndicateConstants.LATTICE_ORIGIN_CELL
	# A point just inside the far face of the origin cell stays in that cell.
	var inside := Vector3(u * 0.99, u * 0.99, u * 0.99)
	check_eq(LatticeMath.local_to_cell(inside), origin, "0.99u stays in the origin cell")
	# One unit further out is the next cell, not a rounding of the same one.
	var next := Vector3(u * 1.01, u * 1.01, u * 1.01)
	check_eq(LatticeMath.local_to_cell(next), origin + Vector3i.ONE, "1.01u crosses the face")
	# A point just below zero belongs to the cell below, not to the origin cell.
	# Rounding rather than flooring here would make the cell straddling the
	# origin twice as thick as every other cell.
	var below := Vector3(-0.001, -0.001, -0.001)
	check_eq(LatticeMath.local_to_cell(below), origin - Vector3i.ONE, "negative side floors down")


func test_cell_index_is_bijective_over_the_lattice() -> void:
	var seen := {}
	var collisions := 0
	var out_of_range := 0
	for x in range(0, SyndicateConstants.LATTICE_EXTENT.x, 7):
		for y in range(0, SyndicateConstants.LATTICE_EXTENT.y, 5):
			for z in range(0, SyndicateConstants.LATTICE_EXTENT.z, 7):
				var cell := Vector3i(x, y, z)
				var idx := LatticeMath.cell_index(cell)
				if idx < 0 or idx >= LatticeMath.CELL_COUNT:
					out_of_range += 1
				if seen.has(idx):
					collisions += 1
				seen[idx] = true
				if LatticeMath.index_to_cell(idx) != cell:
					collisions += 1
	check_eq(collisions, 0, "cell_index must be collision-free and invertible")
	check_eq(out_of_range, 0, "every in-bounds cell indexes inside CELL_COUNT")


func test_cell_count_matches_extent() -> void:
	var e := SyndicateConstants.LATTICE_EXTENT
	check_eq(LatticeMath.CELL_COUNT, e.x * e.y * e.z, "CELL_COUNT derives from LATTICE_EXTENT")
	check_eq(LatticeMath.CELL_COUNT, 73728, "lattice is 48 x 32 x 48")


func test_in_bounds_rejects_every_face() -> void:
	var e := SyndicateConstants.LATTICE_EXTENT
	check_true(LatticeMath.in_bounds(Vector3i.ZERO), "origin corner is in bounds")
	check_true(LatticeMath.in_bounds(e - Vector3i.ONE), "far corner is in bounds")
	check_false(LatticeMath.in_bounds(Vector3i(-1, 0, 0)), "-x rejected")
	check_false(LatticeMath.in_bounds(Vector3i(0, -1, 0)), "-y rejected")
	check_false(LatticeMath.in_bounds(Vector3i(0, 0, -1)), "-z rejected")
	check_false(LatticeMath.in_bounds(Vector3i(e.x, 0, 0)), "+x face rejected")
	check_false(LatticeMath.in_bounds(Vector3i(0, e.y, 0)), "+y face rejected")
	check_false(LatticeMath.in_bounds(Vector3i(0, 0, e.z)), "+z face rejected")
