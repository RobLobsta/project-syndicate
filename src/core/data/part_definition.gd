class_name PartDefinition
extends Resource
## The single canonical description of a constructible part, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §6.
##
## Architectural Invariant I-11: this resource is read-only after
## [code]PartRegistry._ready()[/code]. There are no parallel dictionaries, no
## JSON side-cars duplicating stats, and no hard-coded stat tables in gameplay
## scripts. Every mutable per-part value lives on [PartInstanceState].
##
## Mutating a definition at runtime corrupts every Assembly sharing it, so the
## derived fields below are baked exactly once, by the registry, at load.

## ===== IDENTITY ========================================================
@export var part_key: StringName = &""
## Localisation key. Never a literal user-facing string.
@export var display_name_key: StringName = &""
@export var description_key: StringName = &""
@export var part_class: PartEnums.PartClass = PartEnums.PartClass.STRUCTURAL_COMPONENT
@export var tier: PartEnums.TierGrade = PartEnums.TierGrade.STANDARD
## Retained in the manifest so historical saves and replays still resolve.
@export var deprecated: bool = false

## ===== LATTICE OCCUPANCY ===============================================
## Occupied cells in the part's own local lattice frame at orientation index 0.
## Cell (0,0,0) is the pivot cell and MUST be present.
@export var occupancy_cells: PackedVector3Array = PackedVector3Array()

## ===== ATTACHMENT TOPOLOGY =============================================
@export var attachment_nodes: Array[AttachmentNodeDef] = []

## ===== MASS AND INERTIA ================================================
@export var mass_kg: float = 30.0
## Offset of the part's centre of mass from its pivot cell centre, in metres.
@export var com_offset_m: Vector3 = Vector3.ZERO
## Inertia shape override. When ZERO the solver derives a box tensor from bounds.
@export var inertia_box_half_extents_m: Vector3 = Vector3.ZERO

## ===== STRUCTURAL INTEGRITY ============================================
@export var integrity_max: float = 300.0
## Fraction of incoming damage nullified, indexed by [enum PartEnums.DamageChannel].
@export var resistance: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
## Effective armour rating opposing KINETIC penetration values.
@export var armour_rating: float = 12.0
## Structural load this part carries before the dependency graph flags strain.
@export var load_capacity_kg: float = 400.0
@export var occlusion: PartEnums.OcclusionProfile = PartEnums.OcclusionProfile.OPAQUE_SOLID

## ===== POWER AND HEAT ==================================================
@export var power_draw_pu: float = 0.0
@export var power_supply_pu: float = 0.0
@export var heat_generation_hu_s: float = 0.0
@export var heat_dissipation_hu_s: float = 0.0

## ===== CLASS-SPECIFIC PAYLOAD ==========================================
## Exactly one is non-null, matching [member part_class]. Enforced by the validator.
@export var core_profile: CoreModuleProfile = null
@export var motive_profile: MotiveAssemblyProfile = null
@export var prime_mover_profile: PrimeMoverProfile = null
@export var effector_profile: EffectorModuleProfile = null
@export var support_profile: SupportModuleProfile = null
@export var control_profile: ControlSurfaceProfile = null
@export var energy_cell_profile: EnergyCellProfile = null
@export var appendage_profile: AppendageProfile = null

## ===== PRESENTATION ====================================================
@export var visual_profile: PartVisualProfile = null
@export var collider_profile: ColliderProfile = null
@export var fusion_profile: FusionProfile = null

## ===== ECONOMY / LOADOUT VALIDATION ====================================
@export var build_cost: int = 100
## Counts against the Core Module's mount budget.
@export var mount_weight: int = 1

## ===== BALANCE =========================================================
## Justification for a deliberate departure from the tier scaling model of
## [code]docs/PART_DATA_SCHEMA.md[/code] §12. Empty means the part is expected to
## track its family's Tier-2 baseline within ±8%; the registry validator fails
## the build on an unexplained deviation and prints every note it finds in its
## report, so an exception is reviewable rather than invisible.
@export var balance_exception_note: String = ""

## ===== DERIVED (baked by the registry, never serialised) ===============
var runtime_id: int = 0
var bounds_min_cell: Vector3i = Vector3i.ZERO
var bounds_max_cell: Vector3i = Vector3i.ZERO
## Bounds-local occupancy bitset, one bit per cell of the bounding box. Lets the
## fusion SDF baker and the auto-assembler test containment without touching the
## PackedVector3Array.
var occupancy_bitset: PackedByteArray = PackedByteArray()
var volume_cells: int = 0
var integrity_per_cell: float = 0.0
## Extent of the bounding box in cells, inclusive of both faces.
var bounds_size_cells: Vector3i = Vector3i.ONE

## Sentinels for the bounds reduction. These are the 32-bit limits, not the
## 64-bit ones: [Vector3i] stores int32 components, so a 64-bit sentinel wraps
## on assignment and every bounds minimum comes out as -1.
const _CELL_MAX: int = 2147483647
const _CELL_MIN: int = -2147483648


func _bind_runtime_id(id: int) -> void:
	runtime_id = id


## Computes every derived field. Called exactly once, by the registry, before
## the definition is published. Idempotent, so validators may re-run it.
func _bake_derived_fields() -> void:
	bounds_min_cell = Vector3i(_CELL_MAX, _CELL_MAX, _CELL_MAX)
	bounds_max_cell = Vector3i(_CELL_MIN, _CELL_MIN, _CELL_MIN)
	for c in occupancy_cells:
		var ci := Vector3i(int(c.x), int(c.y), int(c.z))
		bounds_min_cell = bounds_min_cell.min(ci)
		bounds_max_cell = bounds_max_cell.max(ci)
	if occupancy_cells.is_empty():
		bounds_min_cell = Vector3i.ZERO
		bounds_max_cell = Vector3i.ZERO
	bounds_size_cells = bounds_max_cell - bounds_min_cell + Vector3i.ONE
	volume_cells = occupancy_cells.size()
	integrity_per_cell = integrity_max / maxf(1.0, float(volume_cells))
	occupancy_bitset = _pack_occupancy_bitset()


## True when the part-local cell [param c] is occupied. O(1), no allocation.
func occupies_local(c: Vector3i) -> bool:
	var rel := c - bounds_min_cell
	if (
		rel.x < 0
		or rel.y < 0
		or rel.z < 0
		or rel.x >= bounds_size_cells.x
		or rel.y >= bounds_size_cells.y
		or rel.z >= bounds_size_cells.z
	):
		return false
	var bit := _bounds_index(rel)
	@warning_ignore("integer_division")
	var byte := bit / 8
	return (occupancy_bitset[byte] & (1 << (bit % 8))) != 0


## Volume of the part's occupancy in cubic metres, used by the collider coverage
## check in [code]docs/PART_DATA_SCHEMA.md[/code] §6.2 rule 3.
func occupancy_volume_m3() -> float:
	var cell := SyndicateConstants.LATTICE_UNIT_M
	return float(volume_cells) * cell * cell * cell


## The profile matching [member part_class], or null when the definition is
## malformed. The validator treats null as a hard failure.
func class_payload() -> Resource:
	match part_class:
		PartEnums.PartClass.CORE_MODULE:
			return core_profile
		PartEnums.PartClass.MOTIVE_ASSEMBLY:
			return motive_profile
		PartEnums.PartClass.PRIME_MOVER:
			return prime_mover_profile
		PartEnums.PartClass.ENERGY_CELL:
			return energy_cell_profile
		PartEnums.PartClass.EFFECTOR_MODULE:
			return effector_profile
		PartEnums.PartClass.SUPPORT_MODULE:
			return support_profile
		PartEnums.PartClass.CONTROL_SURFACE:
			return control_profile
		PartEnums.PartClass.APPENDAGE:
			return appendage_profile
		PartEnums.PartClass.STRUCTURAL_COMPONENT:
			# Structural Components carry no class payload by design.
			return null
	return null


func _bounds_index(rel: Vector3i) -> int:
	return rel.x + rel.y * bounds_size_cells.x + rel.z * bounds_size_cells.x * bounds_size_cells.y


func _pack_occupancy_bitset() -> PackedByteArray:
	var total := bounds_size_cells.x * bounds_size_cells.y * bounds_size_cells.z
	var out := PackedByteArray()
	out.resize((total + 7) / 8)
	out.fill(0)
	for c in occupancy_cells:
		var rel := Vector3i(int(c.x), int(c.y), int(c.z)) - bounds_min_cell
		var bit := _bounds_index(rel)
		@warning_ignore("integer_division")
		var byte := bit / 8
		out[byte] = out[byte] | (1 << (bit % 8))
	return out
