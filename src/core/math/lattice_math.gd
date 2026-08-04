class_name LatticeMath
extends RefCounted
## Conversions between the three coordinate frames of
## [code]docs/GRID_SNAPPING_LOGIC.md[/code] §2, plus the dense lattice index.
##
## Axis convention matches Godot: +X right, +Y up, -Z forward. Lattice Z
## increases toward the rear of the Assembly.
##
## Every function here is a pure static; there is no hashing and no dictionary
## anywhere in the hot placement path.

const U: float = SyndicateConstants.LATTICE_UNIT_M
const ORIGIN: Vector3i = SyndicateConstants.LATTICE_ORIGIN_CELL
const EXTENT: Vector3i = SyndicateConstants.LATTICE_EXTENT

## Total addressable cells: 48 x 32 x 48 = 73 728, one byte each in the
## occupancy array, which keeps a full-Assembly sweep inside L2 cache.
const CELL_COUNT: int = EXTENT.x * EXTENT.y * EXTENT.z


## Centre of a lattice cell in assembly-local metres.
static func cell_to_local(cell: Vector3i) -> Vector3:
	return Vector3(
		(float(cell.x - ORIGIN.x) + 0.5) * U,
		(float(cell.y - ORIGIN.y) + 0.5) * U,
		(float(cell.z - ORIGIN.z) + 0.5) * U
	)


## Quantise an assembly-local metric point to the cell containing it.
static func local_to_cell(p: Vector3) -> Vector3i:
	return Vector3i(
		int(floorf(p.x / U)) + ORIGIN.x,
		int(floorf(p.y / U)) + ORIGIN.y,
		int(floorf(p.z / U)) + ORIGIN.z
	)


## Reflection of [param cell] in the Assembly's own centre plane, per
## [code]docs/GRID_SNAPPING_LOGIC.md[/code] §10.
##
## The plane runs between cells [code]ORIGIN.x - 1[/code] and [code]ORIGIN.x[/code]
## rather than through the middle of a cell, which is why the formula carries a
## [code]-1[/code]. That is not an arbitrary choice: the shipped Core Module is
## four cells wide and seated on the origin, so it spans 22..25 and the only
## plane that maps it onto itself is the one between 23 and 24. A build's
## symmetry is the Core Module's symmetry, because the Core Module is the root
## every other part hangs from (Invariant I-2).
##
## Cells only. Mirroring a [i]placement[/i] is a different question — a pivot is
## not the middle of a footprint and a mirrored part is rotated — and belongs to
## [method PlacementCandidate.mirrored_x].
static func mirror_x(cell: Vector3i) -> Vector3i:
	return Vector3i(2 * ORIGIN.x - cell.x - 1, cell.y, cell.z)


static func in_bounds(cell: Vector3i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.z >= 0
		and cell.x < EXTENT.x
		and cell.y < EXTENT.y
		and cell.z < EXTENT.z
	)


## Dense linear index. Collision-free for any in-bounds cell.
static func cell_index(cell: Vector3i) -> int:
	return cell.x + cell.y * EXTENT.x + cell.z * EXTENT.x * EXTENT.y


static func index_to_cell(idx: int) -> Vector3i:
	@warning_ignore("integer_division")
	var y := (idx / EXTENT.x) % EXTENT.y
	@warning_ignore("integer_division")
	var z := idx / (EXTENT.x * EXTENT.y)
	return Vector3i(idx % EXTENT.x, y, z)
