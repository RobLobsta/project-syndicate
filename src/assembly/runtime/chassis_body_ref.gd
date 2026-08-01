class_name ChassisBodyRef
extends RigidBody3D
## The single [RigidBody3D] of one Assembly, owned by
## [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code] §5.4.
##
## Architectural Invariant I-3: there is exactly one of these per Assembly and
## there are no joints between parts. Every part's authored collider primitives
## are shapes on this one body.
##
## Its whole job beyond being that body is answering [i]which part did I hit[/i].
## A physics query returns a shape index; §5.4 maps that back to a slot through a
## one-byte array built at collider spawn time and never searched. The mapping is
## O(1) precisely because colliders are authored primitives with stable indices
## rather than geometry generated from a mesh.

const INVALID: int = SyndicateConstants.INVALID_SLOT

## Identifies this Assembly in every [EventBusService] signal and every damage
## packet that names it.
var assembly_id: int = 0

## Shape index -> owning slot.
##
## [b]Deviation from §5.4 as written.[/b] The document grows this array with a
## bare [method PackedByteArray.resize], which zero-fills — and slot 0 is the
## Core Module, not a free value. Any index left unassigned would therefore
## report a hit on the Core Module, which is both a real slot and the one whose
## loss terminates the Assembly. Growth fills with [constant INVALID] instead.
var _shape_to_slot: PackedByteArray = PackedByteArray()


## Records that [param shape_index] on this body belongs to [param slot].
func register_shape(shape_index: int, slot: int) -> void:
	if shape_index < 0:
		push_error("ChassisBodyRef: negative shape index %d" % shape_index)
		return
	while _shape_to_slot.size() <= shape_index:
		_shape_to_slot.append(INVALID)
	_shape_to_slot[shape_index] = slot


## Slot owning [param shape_index], or [constant INVALID] when the index is not
## one of this body's parts.
func slot_for_shape_index(shape_index: int) -> int:
	if shape_index < 0 or shape_index >= _shape_to_slot.size():
		return INVALID
	return _shape_to_slot[shape_index]


## Number of shape indices the map covers. Diagnostics and tests only.
func mapped_shape_count() -> int:
	return _shape_to_slot.size()
