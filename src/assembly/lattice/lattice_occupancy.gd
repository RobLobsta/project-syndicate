class_name LatticeOccupancy
extends RefCounted
## Dense cell-to-slot map for one Assembly's Build Lattice, owned by
## [code]docs/GRID_SNAPPING_LOGIC.md[/code] §3.
##
## Architectural Invariant I-6: this array is the sole authority on overlap.
## There is no separate broadphase for building, and no physics query decides
## whether a cell is free.
##
## [member _cells] is a [PackedByteArray] because [constant
## SyndicateConstants.MAX_PARTS_PER_ASSEMBLY] is 255 and [constant
## SyndicateConstants.INVALID_SLOT] is 255 — one byte per cell, 73 728 bytes
## total. A full clear is a single fill; a full-Assembly rebuild costs well under
## 0.1 ms and happens only on blueprint load, never during interactive editing.
##
## The per-slot cell lists are a flat array indexed by slot rather than the
## dictionary sketched in §3. The interface is identical; a flat array removes
## the hashing, and it makes [method slots_in_use] naturally ascending, which
## Architectural Invariant I-9 needs for deterministic iteration.

## Cell index -> slot id. [constant SyndicateConstants.INVALID_SLOT] means empty.
var _cells: PackedByteArray = PackedByteArray()
## Slot -> its cell indices, for O(size) removal without scanning the lattice.
var _slot_cells: Array[PackedInt32Array] = []
## Occupied cell count, maintained incrementally so no caller has to sweep.
var occupied_count: int = 0


func _init() -> void:
	_cells.resize(LatticeMath.CELL_COUNT)
	_slot_cells.resize(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY)
	clear()


func clear() -> void:
	_cells.fill(SyndicateConstants.INVALID_SLOT)
	for i in _slot_cells.size():
		_slot_cells[i] = PackedInt32Array()
	occupied_count = 0


## Slot occupying [param cell], or [constant SyndicateConstants.INVALID_SLOT]
## when the cell is empty or out of bounds. Out-of-bounds reads answer "empty"
## rather than failing, so callers sweeping a footprint that straddles the
## lattice edge need no special case; [method LatticeMath.in_bounds] is the
## check that rejects such a placement.
func slot_at(cell: Vector3i) -> int:
	if not LatticeMath.in_bounds(cell):
		return SyndicateConstants.INVALID_SLOT
	return _cells[LatticeMath.cell_index(cell)]


func is_free(cell: Vector3i) -> bool:
	return slot_at(cell) == SyndicateConstants.INVALID_SLOT


## True when every cell of [param cells] is in bounds and unoccupied.
##
## The overlap half of the validation chain, kept here so that the garage, the
## auto-assembler, and server-side blueprint validation share one implementation
## (CLAUDE.md §10 rule 8).
func is_footprint_free(cells: PackedVector3Array) -> bool:
	for c in cells:
		var cell := Vector3i(int(c.x), int(c.y), int(c.z))
		if not LatticeMath.in_bounds(cell):
			return false
		if _cells[LatticeMath.cell_index(cell)] != SyndicateConstants.INVALID_SLOT:
			return false
	return true


## Claims every cell of [param cells] for [param slot].
##
## The caller is responsible for having validated the footprint first: this
## writes unconditionally, because it sits at the bottom of the placement chain
## and re-validating here would double the cost of every blueprint load. Writing
## a footprint that overlaps another slot corrupts that slot's cell list, so the
## precondition is asserted.
func write_slot(slot: int, cells: PackedVector3Array) -> void:
	assert(slot >= 0 and slot < SyndicateConstants.MAX_PARTS_PER_ASSEMBLY,
			"slot out of range: %d" % slot)
	assert(_slot_cells[slot].is_empty(), "slot %d is already written; erase it first" % slot)
	assert(is_footprint_free(cells), "slot %d footprint overlaps or leaves the lattice" % slot)

	var indices := PackedInt32Array()
	indices.resize(cells.size())
	for i in cells.size():
		var idx := LatticeMath.cell_index(Vector3i(cells[i]))
		_cells[idx] = slot
		indices[i] = idx
	_slot_cells[slot] = indices
	occupied_count += cells.size()


## Releases every cell held by [param slot]. Erasing an unwritten slot is a
## no-op, so removal paths need no existence check.
func erase_slot(slot: int) -> void:
	assert(slot >= 0 and slot < SyndicateConstants.MAX_PARTS_PER_ASSEMBLY,
			"slot out of range: %d" % slot)
	var indices := _slot_cells[slot]
	for idx in indices:
		_cells[idx] = SyndicateConstants.INVALID_SLOT
	occupied_count -= indices.size()
	_slot_cells[slot] = PackedInt32Array()


## Cell indices held by [param slot], empty when the slot is unwritten.
func cells_of_slot(slot: int) -> PackedInt32Array:
	if slot < 0 or slot >= SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		return PackedInt32Array()
	return _slot_cells[slot]


func is_slot_used(slot: int) -> bool:
	if slot < 0 or slot >= SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		return false
	return not _slot_cells[slot].is_empty()


## Written slots in ascending order. Ascending by construction rather than by a
## sort, so every traversal built on it is reproducible (I-9).
func slots_in_use() -> PackedByteArray:
	var out := PackedByteArray()
	for slot in _slot_cells.size():
		if not _slot_cells[slot].is_empty():
			out.append(slot)
	return out


## Distinct slots occupying the six face-adjacent cells of [param cell], in
## ascending slot order. The neighbour query the Chassis Graph builds its
## support edges from.
func neighbours_of_cell(cell: Vector3i) -> PackedByteArray:
	var seen := PackedByteArray()
	for face in AttachmentNodeDef.AXIS_NORMALS:
		var slot := slot_at(cell + face)
		if slot != SyndicateConstants.INVALID_SLOT and not seen.has(slot):
			seen.append(slot)
	seen.sort()
	return seen
