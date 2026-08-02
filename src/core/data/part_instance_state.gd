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
## Per-channel offset applied on top of the definition's [code]resistance[/code],
## five entries long. Left empty until something first modifies it: §7.2's
## corrosive decay is the only writer, and a match with none in it should not pay
## for the array.
##
## This field is the reason Architectural Invariant I-11 is enforceable at all.
## Corrosive damage degrades resistance permanently, and writing that into the
## shared [PartDefinition] would weaken every copy of the part in the match, on
## every Assembly, for the rest of the session.
var resist_modifier: PackedFloat32Array = PackedFloat32Array()
## Bitfield; see [PartFlags].
var flags: int = 0
var visual_node_path: NodePath = NodePath()
var collider_shape_ids: PackedInt32Array = PackedInt32Array()


func integrity_fraction(def: PartDefinition) -> float:
	return clampf(integrity / def.integrity_max, 0.0, 1.0)


## This instance's resistance to [param channel], in [code][0, 1)[/code], after
## any corrosive decay.
##
## Returns the definition's own figure when nothing has modified it, which is
## every part in a match with no corrosive source in it.
func effective_resistance(def: PartDefinition, channel: int) -> float:
	var base := def.resistance[channel] if channel < def.resistance.size() else 0.0
	if channel >= resist_modifier.size():
		return base
	# No clamp. The modifier is written only by decay_resistance, which floors it
	# at -base, so the sum is already in [0, base] — and a guard whose condition
	# the surrounding arithmetic cannot produce is dead code wearing prudence.
	return base + resist_modifier[channel]


## Permanently reduces resistance on every channel by [param amount]. §7.2.
##
## Allocates the modifier array on first use, which is what keeps the common
## case free.
func decay_resistance(def: PartDefinition, amount: float) -> void:
	if amount <= 0.0:
		return
	if resist_modifier.is_empty():
		resist_modifier.resize(PartEnums.DAMAGE_CHANNEL_COUNT)
	for c: int in PartEnums.DAMAGE_CHANNEL_COUNT:
		var base := def.resistance[c] if c < def.resistance.size() else 0.0
		# Floored against the base rather than at zero, so repeated exposure
		# drives resistance to nothing and no further. A modifier allowed to run
		# negative without bound would make a long-corroded part take *more* than
		# raw damage once the clamp in effective_resistance was reached.
		resist_modifier[c] = maxf(resist_modifier[c] - amount, -base)


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
