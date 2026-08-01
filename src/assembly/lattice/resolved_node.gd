class_name ResolvedNode
extends RefCounted
## An [AttachmentNodeDef] transformed into lattice space, produced by
## [method FootprintSolver.resolve_nodes] per
## [code]docs/GRID_SNAPPING_LOGIC.md[/code] §5.
##
## The source definition is carried rather than copied so that polarity, joint
## strength, and class restrictions resolve against the immutable data
## (Architectural Invariant I-11) instead of against a snapshot that could drift.

## The immutable definition this was resolved from. Never mutated.
var source: AttachmentNodeDef = null
## Node's cell in the Assembly lattice frame.
var cell: Vector3i = Vector3i.ZERO
## Outward face normal after rotation. Always an axis unit vector.
var face: Vector3i = Vector3i.ZERO


## The cell this node mates into: one step along its outward face.
##
## Two nodes mate when each one's [method mating_cell] is the other's
## [member cell] and their faces oppose. Computing it here keeps that rule in a
## single place rather than repeated at every call site in the validator, the
## mate selector, and the auto-assembler.
func mating_cell() -> Vector3i:
	return cell + face


## True when [param other] is physically adjacent and facing this node: each
## one's [method mating_cell] is the other's [member cell], and the faces
## oppose.
##
## The geometric half of the mating rule on its own, because
## [code]PlacementValidator[/code] needs to separate a placement that found no
## adjacent face at all from one that found the right face and the wrong
## polarity — the two carry different [code]Reject[/code] codes and the garage
## phrases them differently. Splitting it here rather than restating the
## adjacency test inside the validator keeps one implementation of what
## "adjacent and facing" means.
func is_face_paired(other: ResolvedNode) -> bool:
	if other == null:
		return false
	if other.cell != mating_cell() or cell != other.mating_cell():
		return false
	return face == -other.face


## True when [param other] sits on the opposing face of the adjacent cell and
## its polarity accepts this node's. Class restrictions are checked separately
## by the validator, which knows the candidate's part class.
func opposes(other: ResolvedNode) -> bool:
	if other == null or source == null or other.source == null:
		return false
	if not is_face_paired(other):
		return false
	return source.accepts_polarity(other.source.polarity)
