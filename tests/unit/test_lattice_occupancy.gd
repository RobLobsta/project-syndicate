extends TestCase
## [LatticeOccupancy] — the sole authority on build-time overlap (I-6).
##
## The bookkeeping matters more than it looks: [member
## LatticeOccupancy.occupied_count] and the per-slot cell lists are maintained
## incrementally, so a write/erase asymmetry does not fail loudly. It leaves a
## cell permanently claimed by a part that no longer exists, and the symptom
## surfaces much later as a placement the player can see is legal being rejected.

var _occupancy: LatticeOccupancy = null


func before_all() -> void:
	_occupancy = LatticeOccupancy.new()


func test_starts_empty_across_the_whole_lattice() -> void:
	var fresh := LatticeOccupancy.new()
	check_eq(fresh.occupied_count, 0, "a new lattice holds nothing")
	check_eq(fresh.slots_in_use(), PackedByteArray(), "no slots in use")
	var occupied := 0
	for i in range(0, LatticeMath.CELL_COUNT, 97):
		if not fresh.is_free(LatticeMath.index_to_cell(i)):
			occupied += 1
	check_eq(occupied, 0, "every sampled cell reads free")


func test_write_then_read_back() -> void:
	var occ := LatticeOccupancy.new()
	var cells := _cells([Vector3i(10, 5, 10), Vector3i(11, 5, 10), Vector3i(10, 6, 10)])
	occ.write_slot(4, cells)

	check_eq(occ.occupied_count, 3, "three cells claimed")
	check_eq(occ.slot_at(Vector3i(10, 5, 10)), 4, "first cell belongs to slot 4")
	check_eq(occ.slot_at(Vector3i(10, 6, 10)), 4, "third cell belongs to slot 4")
	check_true(occ.is_free(Vector3i(12, 5, 10)), "an untouched neighbour stays free")
	check_true(occ.is_slot_used(4), "slot 4 reads as used")
	check_eq(occ.cells_of_slot(4).size(), 3, "slot 4 remembers its three cells")


func test_erase_restores_the_lattice_exactly() -> void:
	var occ := LatticeOccupancy.new()
	var cells := _cells([Vector3i(20, 8, 20), Vector3i(21, 8, 20)])
	occ.write_slot(7, cells)
	occ.erase_slot(7)

	check_eq(occ.occupied_count, 0, "occupied_count returns to zero")
	check_true(occ.is_free(Vector3i(20, 8, 20)), "erased cell is free again")
	check_false(occ.is_slot_used(7), "slot 7 is no longer in use")
	check_eq(occ.cells_of_slot(7), PackedInt32Array(), "slot 7 holds no cells")


func test_write_erase_cycles_do_not_drift() -> void:
	# The incremental count is the thing most likely to rot over an editing
	# session, and it never fails visibly on its own.
	var occ := LatticeOccupancy.new()
	var cells := _cells([Vector3i(30, 10, 30), Vector3i(31, 10, 30), Vector3i(32, 10, 30)])
	for i in 25:
		occ.write_slot(2, cells)
		check_eq(occ.occupied_count, 3, "count after write on cycle %d" % i)
		occ.erase_slot(2)
		check_eq(occ.occupied_count, 0, "count after erase on cycle %d" % i)


func test_erasing_an_unwritten_slot_is_a_no_op() -> void:
	var occ := LatticeOccupancy.new()
	occ.write_slot(1, _cells([Vector3i(5, 5, 5)]))
	occ.erase_slot(9)
	check_eq(occ.occupied_count, 1, "erasing an empty slot must not disturb the count")
	check_eq(occ.slot_at(Vector3i(5, 5, 5)), 1, "the written slot is untouched")


func test_erasing_one_slot_leaves_its_neighbour_intact() -> void:
	var occ := LatticeOccupancy.new()
	occ.write_slot(3, _cells([Vector3i(15, 5, 15)]))
	occ.write_slot(8, _cells([Vector3i(16, 5, 15)]))
	occ.erase_slot(3)

	check_true(occ.is_free(Vector3i(15, 5, 15)), "slot 3's cell is released")
	check_eq(occ.slot_at(Vector3i(16, 5, 15)), 8, "slot 8's cell is untouched")
	check_eq(occ.occupied_count, 1, "only slot 3's cell was released")


func test_clear_resets_everything() -> void:
	var occ := LatticeOccupancy.new()
	occ.write_slot(0, _cells([Vector3i(24, 4, 24)]))
	occ.write_slot(5, _cells([Vector3i(25, 4, 24)]))
	occ.clear()

	check_eq(occ.occupied_count, 0, "count cleared")
	check_eq(occ.slots_in_use(), PackedByteArray(), "no slots remain")
	check_true(occ.is_free(Vector3i(24, 4, 24)), "cells released")
	check_eq(occ.cells_of_slot(0), PackedInt32Array(), "slot lists cleared")


func test_out_of_bounds_cells_read_as_empty_not_as_an_error() -> void:
	var occ := LatticeOccupancy.new()
	check_eq(
		occ.slot_at(Vector3i(-1, 0, 0)),
		SyndicateConstants.INVALID_SLOT,
		"a cell below the lattice reads as empty"
	)
	check_eq(
		occ.slot_at(SyndicateConstants.LATTICE_EXTENT),
		SyndicateConstants.INVALID_SLOT,
		"a cell past the far corner reads as empty"
	)
	check_true(occ.is_free(Vector3i(0, -5, 0)), "is_free tolerates out-of-bounds")


func test_footprint_free_rejects_overlap_and_out_of_bounds() -> void:
	var occ := LatticeOccupancy.new()
	occ.write_slot(2, _cells([Vector3i(12, 6, 12)]))

	check_true(
		occ.is_footprint_free(_cells([Vector3i(13, 6, 12), Vector3i(14, 6, 12)])),
		"a clear footprint is free"
	)
	check_false(
		occ.is_footprint_free(_cells([Vector3i(11, 6, 12), Vector3i(12, 6, 12)])),
		"a footprint touching an occupied cell is not free"
	)
	check_false(
		occ.is_footprint_free(_cells([Vector3i(0, 0, 0), Vector3i(-1, 0, 0)])),
		"a footprint leaving the lattice is not free"
	)


func test_slots_in_use_is_ascending() -> void:
	var occ := LatticeOccupancy.new()
	# Written out of order; the result must still be ascending, because the
	# Chassis Graph's traversal order is derived from it (I-9).
	occ.write_slot(9, _cells([Vector3i(1, 1, 1)]))
	occ.write_slot(2, _cells([Vector3i(2, 1, 1)]))
	occ.write_slot(200, _cells([Vector3i(3, 1, 1)]))
	occ.write_slot(0, _cells([Vector3i(4, 1, 1)]))
	check_eq(
		occ.slots_in_use(),
		PackedByteArray([0, 2, 9, 200]),
		"slots_in_use must be ascending regardless of write order"
	)


func test_slot_254_is_addressable_and_255_is_the_empty_marker() -> void:
	# The byte-per-cell encoding gives exactly 255 usable slots, 0..254, with 255
	# reserved for "empty". An off-by-one here would make the last slot
	# indistinguishable from an empty cell.
	var occ := LatticeOccupancy.new()
	var last := SyndicateConstants.MAX_PARTS_PER_ASSEMBLY - 1
	check_eq(last, 254, "the highest addressable slot is 254")
	check_eq(SyndicateConstants.INVALID_SLOT, 255, "255 marks an empty cell")
	occ.write_slot(last, _cells([Vector3i(40, 20, 40)]))
	check_eq(occ.slot_at(Vector3i(40, 20, 40)), last, "slot 254 reads back correctly")
	check_false(occ.is_free(Vector3i(40, 20, 40)), "slot 254 is not mistaken for empty")


func test_neighbours_of_cell_finds_face_adjacent_slots_only() -> void:
	var occ := LatticeOccupancy.new()
	var centre := Vector3i(24, 10, 24)
	occ.write_slot(3, _cells([centre + Vector3i(1, 0, 0)]))
	occ.write_slot(1, _cells([centre + Vector3i(0, -1, 0)]))
	# Diagonal: shares only an edge, so it must not be reported as a neighbour.
	occ.write_slot(6, _cells([centre + Vector3i(1, 1, 0)]))

	check_eq(
		occ.neighbours_of_cell(centre),
		PackedByteArray([1, 3]),
		"only face-adjacent slots count, in ascending order"
	)


func test_neighbours_reports_a_multi_cell_slot_once() -> void:
	var occ := LatticeOccupancy.new()
	var centre := Vector3i(24, 10, 24)
	occ.write_slot(5, _cells([centre + Vector3i(1, 0, 0), centre + Vector3i(-1, 0, 0)]))
	check_eq(
		occ.neighbours_of_cell(centre),
		PackedByteArray([5]),
		"a slot touching two faces is still one neighbour"
	)


func _cells(list: Array[Vector3i]) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(list.size())
	for i in list.size():
		out[i] = Vector3(list[i])
	return out
