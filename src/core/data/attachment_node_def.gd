class_name AttachmentNodeDef
extends Resource
## A single mating point on a part, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §6.1.
##
## Face normals are constrained to the six axis units. Diagonal mating is not
## supported; angled appearance comes from the fusion shader and skirting
## meshes, never from arbitrary joint angles. This constraint is what keeps the
## lattice solver O(1) per placement query.

@export var node_name: StringName = &"n0"
## Lattice cell, in the part-local frame, whose face this node sits on.
@export var cell: Vector3i = Vector3i.ZERO
## Outward face normal. MUST be one of the six axis unit vectors.
@export var face_normal: Vector3i = Vector3i(0, 1, 0)
@export var polarity: PartEnums.AttachmentPolarity = PartEnums.AttachmentPolarity.FACE_NEUTRAL
## Tensile force this joint transmits before the graph marks it strained.
@export var joint_strength_n: float = 60000.0
## When true, this node may serve as a structural parent.
@export var can_bear_load: bool = true
## Restricts which part classes may mate here. Empty = unrestricted.
@export var accepts_classes: PackedInt32Array = PackedInt32Array()

## The six legal face normals, in a fixed order used by the validator and by the
## mate solver's neighbour scan.
const AXIS_NORMALS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]


## True when [member face_normal] is one of the six axis units.
func has_axis_normal() -> bool:
	return AXIS_NORMALS.has(face_normal)


## The mating matrix of [code]docs/GRID_SNAPPING_LOGIC.md[/code] §7.3, flattened
## to [code]row * ATTACHMENT_POLARITY_COUNT + column[/code] where both indices are
## [enum PartEnums.AttachmentPolarity] values.
##
## A flat array rather than the dictionary the document sketches: the mate
## selector and the auto-assembler both read this per candidate node pair, and an
## integer-keyed [Dictionary] pays a hash for a lookup that is two adds.
##
##          male   female neutral axle   deck
const POLARITY_MATRIX: Array[bool] = [
	false, true, true, false, true,  # FACE_MALE
	true, false, true, false, false,  # FACE_FEMALE
	true, true, true, false, true,  # FACE_NEUTRAL
	false, false, false, true, false,  # AXLE
	true, false, true, false, false,  # DECK
]


## True when a node of [param other] polarity may mate with one of [param a].
##
## AXLE is exclusive — a Motive Assembly axle mates only with another axle. DECK
## is an upward-facing mounting surface, so it accepts a protruding or neutral
## face but never a recess and never a second deck: two decks facing each other
## describe no physical joint.
static func polarity_compatible(
	a: PartEnums.AttachmentPolarity, other: PartEnums.AttachmentPolarity
) -> bool:
	var count := PartEnums.ATTACHMENT_POLARITY_COUNT
	if a < 0 or other < 0 or a >= count or other >= count:
		return false
	return POLARITY_MATRIX[int(a) * count + int(other)]


## True when a node of [param other] polarity may mate with this one.
func accepts_polarity(other: PartEnums.AttachmentPolarity) -> bool:
	return polarity_compatible(polarity, other)


## True when a part of [param part_class] may mate at this node.
func accepts_class(part_class: int) -> bool:
	if accepts_classes.is_empty():
		return true
	return accepts_classes.has(part_class)
