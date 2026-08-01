class_name BuildBudgetLedger
extends RefCounted
## Running totals of everything §7.4 of [code]docs/GRID_SNAPPING_LOGIC.md[/code]
## checks a placement against.
##
## Maintained incrementally — attach adds, detach subtracts — so the budget half
## of the validation chain is O(1) rather than a re-sum over every part on every
## cursor move. At the 180-part reference Assembly the difference is the whole
## §11 budget for a rejected placement.
##
## The counters are only as good as their symmetry: an add without a matching
## remove leaves a budget permanently consumed by a part that is no longer
## there, and the symptom is a placement the player can see is legal being
## refused. [method recompute_from] exists so a test can prove the incremental
## totals match a full re-sum after an arbitrary sequence of edits.

## Slot-count per [enum PartEnums.PartClass], indexed by the enum value.
var class_counts: PackedInt32Array = PackedInt32Array()
## Σ [member PartDefinition.mount_weight] over every committed part.
var mount_used: int = 0
## Σ [member PartDefinition.power_draw_pu].
var power_draw_pu: float = 0.0
## Σ [member PartDefinition.power_supply_pu], excluding the Core Module's own
## capacity, which is a separate term in the §7.4 inequality.
var power_supply_pu: float = 0.0
## Σ [member PartDefinition.mass_kg]. Read by the garage stat panel and by the
## Core Module's mass-tolerance warning.
var total_mass_kg: float = 0.0
## Σ [member PartDefinition.build_cost].
var total_build_cost: int = 0

## The committed Core Module's profile, or null before one is placed. The two
## budget ceilings live on it, so every ceiling is zero until the Core Module
## exists — which is correct, because nothing but a Core Module may be placed
## first.
var core_profile: CoreModuleProfile = null


func _init() -> void:
	class_counts.resize(PartEnums.PART_CLASS_COUNT)
	class_counts.fill(0)


func clear() -> void:
	class_counts.fill(0)
	mount_used = 0
	power_draw_pu = 0.0
	power_supply_pu = 0.0
	total_mass_kg = 0.0
	total_build_cost = 0
	core_profile = null


func add(def: PartDefinition) -> void:
	class_counts[int(def.part_class)] += 1
	mount_used += def.mount_weight
	power_draw_pu += def.power_draw_pu
	power_supply_pu += def.power_supply_pu
	total_mass_kg += def.mass_kg
	total_build_cost += def.build_cost
	if def.part_class == PartEnums.PartClass.CORE_MODULE:
		core_profile = def.core_profile


func remove(def: PartDefinition) -> void:
	class_counts[int(def.part_class)] -= 1
	mount_used -= def.mount_weight
	power_draw_pu -= def.power_draw_pu
	power_supply_pu -= def.power_supply_pu
	total_mass_kg -= def.mass_kg
	total_build_cost -= def.build_cost
	if def.part_class == PartEnums.PartClass.CORE_MODULE:
		core_profile = null


func count_of_class(part_class: int) -> int:
	if part_class < 0 or part_class >= class_counts.size():
		return 0
	return class_counts[part_class]


## Mount points the Core Module offers, or 0 before one is committed.
func mount_budget() -> int:
	return 0 if core_profile == null else core_profile.mount_budget


## Total power available: the Core Module's capacity plus every Power Plant's
## supply, per the §7.4 inequality.
func power_available_pu() -> float:
	var capacity := 0.0 if core_profile == null else core_profile.power_capacity_pu
	return capacity + power_supply_pu


## Rebuilds every total from [param definitions]. Not used by the placement
## path — it is the O(n) re-sum the incremental counters are checked against,
## and the blueprint loader's cross-check after a bulk load.
func recompute_from(definitions: Array[PartDefinition]) -> void:
	clear()
	for def in definitions:
		if def != null:
			add(def)
