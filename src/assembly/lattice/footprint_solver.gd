class_name FootprintSolver
extends RefCounted
## Resolves a [PartDefinition] at an origin and orientation into the lattice
## cells and attachment nodes it occupies, per
## [code]docs/GRID_SNAPPING_LOGIC.md[/code] §5.
##
## The transform is [code]c_l(i) = origin_cell + R(orientation_index) · c_p(i)[/code],
## evaluated entirely in integers. Architectural Invariant I-6: no float appears
## anywhere in this path.


## Writes the Assembly-frame cells of [param def] into [param out].
##
## [param out] is supplied by the caller and resized in place. The ghost-preview
## system reuses one buffer across frames, so interactive placement performs no
## heap allocation per frame — which is why this returns nothing rather than a
## fresh array. Packed arrays pass by reference as arguments, so the caller sees
## the result; note that *assigning* one to a variable copies it, so a caller
## must read [param out] itself rather than stash a reference to it.
static func resolve(
	def: PartDefinition,
	origin_cell: Vector3i,
	orientation_index: int,
	out: PackedVector3Array
) -> void:
	out.resize(def.occupancy_cells.size())
	for i in def.occupancy_cells.size():
		var lc := Vector3i(def.occupancy_cells[i])
		out[i] = Vector3(origin_cell + OrientationTable.rotate_cell(orientation_index, lc))


## Allocating form of [method resolve], for validation and tooling paths that
## run once per placement rather than once per frame.
static func resolve_cells(
	def: PartDefinition, origin_cell: Vector3i, orientation_index: int
) -> PackedVector3Array:
	var out := PackedVector3Array()
	resolve(def, origin_cell, orientation_index, out)
	return out


## Attachment nodes of [param def] transformed into the Assembly lattice frame.
static func resolve_nodes(
	def: PartDefinition, origin_cell: Vector3i, orientation_index: int
) -> Array[ResolvedNode]:
	var result: Array[ResolvedNode] = []
	for node in def.attachment_nodes:
		var rn := ResolvedNode.new()
		rn.source = node
		rn.cell = origin_cell + OrientationTable.rotate_cell(orientation_index, node.cell)
		rn.face = OrientationTable.rotate_face(orientation_index, node.face_normal)
		result.append(rn)
	return result


## True when every cell of [param cells] lies inside the lattice.
##
## Separate from the occupancy overlap test because the two failures carry
## different [code]PlacementValidator.Reject[/code] codes, and the UI phrases
## "outside the build volume" differently from "something is already there".
static func all_in_bounds(cells: PackedVector3Array) -> bool:
	for c in cells:
		if not LatticeMath.in_bounds(Vector3i(int(c.x), int(c.y), int(c.z))):
			return false
	return true


## Assembly-frame bounding box of a resolved footprint, as [min, max] inclusive.
## Returns a zero-size box at the origin cell for an empty footprint.
static func bounds_of(cells: PackedVector3Array) -> Array[Vector3i]:
	if cells.is_empty():
		return [Vector3i.ZERO, Vector3i.ZERO]
	var lo := Vector3i(cells[0])
	var hi := lo
	for c in cells:
		var cell := Vector3i(c)
		lo = lo.min(cell)
		hi = hi.max(cell)
	return [lo, hi]


## Origin cell that places [param def] so its rotated footprint is centred on
## [param target_cell]'s column and rests with its lowest cell at
## [param target_cell]. Used by the auto-assembler and by drag placement, both
## of which think in terms of "put it here" rather than in pivot offsets.
static func origin_for_seated_footprint(
	def: PartDefinition, target_cell: Vector3i, orientation_index: int
) -> Vector3i:
	var probe := resolve_cells(def, Vector3i.ZERO, orientation_index)
	var box := bounds_of(probe)
	# box[0] is the rotated footprint's minimum corner relative to the pivot, so
	# subtracting it seats that corner exactly on the target cell.
	return target_cell - box[0]
