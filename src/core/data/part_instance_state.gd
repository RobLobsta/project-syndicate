class_name PartInstanceState
extends RefCounted
## All mutable per-part state, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §8.
##
## Assemblies own a contiguous [code]Array[PartInstanceState][/code] indexed by
## slot, so iteration is cache-coherent and slot lookup is a single array index.
##
## Architectural Invariant I-11: per-instance modifiers live here and are never
## written back to the shared [PartDefinition].

var slot: int = SyndicateConstants.INVALID_SLOT
var part_def_id: int = 0
var origin_cell: Vector3i = Vector3i.ZERO
## 0..23. See [code]docs/GRID_SNAPPING_LOGIC.md[/code] §4.
var orientation_index: int = 0
var parent_slot: int = SyndicateConstants.INVALID_SLOT
var child_slots: PackedInt32Array = PackedInt32Array()
var integrity: float = 0.0
## Replicated explicitly. Architectural Invariant I-8 forbids clients deriving
## this from quantised integrity.
var integrity_band: PartEnums.IntegrityBand = PartEnums.IntegrityBand.NOMINAL
var accumulated_heat_hu: float = 0.0
## Bitfield; see [PartFlags].
var flags: int = 0
var visual_node_path: NodePath = NodePath()
var collider_shape_ids: PackedInt32Array = PackedInt32Array()


func integrity_fraction(def: PartDefinition) -> float:
	return clampf(integrity / def.integrity_max, 0.0, 1.0)


func has_flag(flag: int) -> bool:
	return (flags & flag) != 0


func set_flag(flag: int, value: bool) -> void:
	if value:
		flags |= flag
	else:
		flags &= ~flag


## True when this part no longer contributes to structure, mass, or function.
func is_inactive() -> bool:
	return (flags & PartFlags.MASK_INACTIVE) != 0


func is_root() -> bool:
	return parent_slot == SyndicateConstants.INVALID_SLOT
