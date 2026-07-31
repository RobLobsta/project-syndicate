# PART_DATA_SCHEMA.md

**Project Syndicate — System Architecture Specification, Document 01 of 13**
**Subsystem:** Global Part Registry, Module Attribute Model, Mass & Integrity Tables
**Status:** Normative. All code that reads, writes, or synthesises part data MUST conform to this document.

---

## 1. Purpose and Scope

This document defines the single canonical data model for every constructible object in Project Syndicate. Every other subsystem — lattice snapping, dependency graphing, mass solving, damage resolution, network replication, UI presentation, and the asset extension pipeline — derives its inputs from the structures defined here.

There is exactly **one** authoritative description of a part: the `PartDefinition` resource. There are no parallel dictionaries, no JSON side-cars that duplicate stats, no hard-coded stat tables in gameplay scripts. Any subsystem needing a part attribute resolves it through `PartRegistry`.

This eliminates the primary source of technical debt in legacy assembly games: **stat drift**, where the garage UI, the physics solver, and the damage model each read from divergent copies of the same number.

---

## 2. Canonical Vocabulary

Project Syndicate uses generic engineering nomenclature throughout code, data, and user-facing strings. The following table is binding. Aliases in the right column MUST NOT appear in identifiers, resource names, comments, or localisation keys.

| Canonical Term | Code Token | Prohibited Aliases |
|---|---|---|
| Core Module | `CORE_MODULE` | cabin, cockpit, cab |
| Structural Component | `STRUCTURAL_COMPONENT` | armor plate, armour, panel-armor |
| Motive Assembly | `MOTIVE_ASSEMBLY` | wheel, track, leg, hover |
| Power Plant | `POWER_PLANT` | engine, generator, motor |
| Effector Module | `EFFECTOR_MODULE` | weapon, gun, cannon |
| Support Module | `SUPPORT_MODULE` | radiator, ammo pack, cloak |
| Control Surface | `CONTROL_SURFACE` | spoiler, wing, aero |
| Dynamic Ground Array | `GROUND_ARRAY` | terrain, landscape, heightmap-world |
| Static Volume | `STATIC_VOLUME` | building, house, structure-prop |
| Assembly | `Assembly` | vehicle, car, craft, build |
| Build Lattice | `BuildLattice` | grid, voxel grid |
| Attachment Node | `AttachmentNode` | connector, socket, hardpoint (except effector-specific) |
| Chassis Graph | `ChassisGraph` | dependency tree, part tree |

`hardpoint` is permitted **only** in the narrow sense defined by `WEAPON_TARGETING_LOGIC.md` §3 — the rotational mount frame internal to an Effector Module. It never refers to a generic attachment point.

---

## 3. Global Constants

These constants live in `src/core/data/syndicate_constants.gd` as a `class_name SyndicateConstants` container of `const` members. No subsystem may redefine them locally.

```gdscript
class_name SyndicateConstants
extends RefCounted

## --- Spatial lattice ---------------------------------------------------
const LATTICE_UNIT_M: float = 0.25
const LATTICE_EXTENT: Vector3i = Vector3i(48, 32, 48)  # 12.0 m x 8.0 m x 12.0 m
const LATTICE_ORIGIN_CELL: Vector3i = Vector3i(24, 4, 24)
const ORIENTATION_COUNT: int = 24

## --- Assembly limits ---------------------------------------------------
const MAX_PARTS_PER_ASSEMBLY: int = 255   # slots 0..254
const INVALID_SLOT: int = 255
const CORE_SLOT: int = 0
const MAX_EFFECTORS_PER_ASSEMBLY: int = 16
const MAX_MOTIVE_PER_ASSEMBLY: int = 24

## --- Simulation cadence ------------------------------------------------
const PHYSICS_HZ: int = 60
const PHYSICS_DT: float = 1.0 / 60.0
const NET_SNAPSHOT_HZ: int = 30
const NET_INPUT_HZ: int = 60

## --- Integrity bands (fraction of max structural integrity) ------------
const BAND_STRESSED: float = 0.75
const BAND_IMPAIRED: float = 0.50
const BAND_CRITICAL: float = 0.30
const BAND_DESTROYED: float = 0.0

## --- Numeric hygiene ---------------------------------------------------
const EPSILON_LINEAR: float = 0.0001
const EPSILON_ANGULAR: float = 0.00017453  # ~0.01 degrees in radians
```

`LATTICE_UNIT_M` is `0.25`. Every dimension in every part table below is expressed in **cells**, never metres. Metre values are derived at load time by multiplication. This guarantees that a future rescale of the lattice is a one-constant change.

---

## 4. Enumerations

All enumerations are declared once in `src/core/data/part_enums.gd`. Integer values are frozen — they appear in serialised save data and network packets and MUST NOT be renumbered. New members append only.

```gdscript
class_name PartEnums
extends RefCounted

enum PartClass {
    CORE_MODULE           = 0,
    STRUCTURAL_COMPONENT  = 1,
    MOTIVE_ASSEMBLY       = 2,
    POWER_PLANT           = 3,
    EFFECTOR_MODULE       = 4,
    SUPPORT_MODULE        = 5,
    CONTROL_SURFACE       = 6,
}

enum MotiveKind {
    WHEELED_STEERED  = 0,
    WHEELED_FIXED    = 1,
    TRACKED_SEGMENT  = 2,
    OMNI_ROLLER      = 3,
    AMBULATORY_LIMB  = 4,
    REPULSOR_PAD     = 5,
}

enum EffectorKind {
    BALLISTIC_DIRECT   = 0,
    BALLISTIC_ARCED    = 1,
    CONTINUOUS_BEAM    = 2,
    GUIDED_ORDNANCE    = 3,
    KINETIC_MELEE      = 4,
}

enum DamageChannel {
    KINETIC    = 0,
    BLAST      = 1,
    IMPACT     = 2,
    THERMAL    = 3,
    CORROSIVE  = 4,
}
const DAMAGE_CHANNEL_COUNT: int = 5

enum IntegrityBand {
    NOMINAL   = 0,
    STRESSED  = 1,
    IMPAIRED  = 2,
    CRITICAL  = 3,
    DESTROYED = 4,
}

enum TierGrade {
    SALVAGE   = 1,
    STANDARD  = 2,
    REFINED   = 3,
    PROTOTYPE = 4,
    APEX      = 5,
}

enum AttachmentPolarity {
    FACE_MALE   = 0,  # protrudes; mates with FACE_FEMALE
    FACE_FEMALE = 1,  # recessed; mates with FACE_MALE
    FACE_NEUTRAL = 2, # mates with any face type
    AXLE        = 3,  # motive assemblies only
    DECK        = 4,  # upward-facing effector/support mounting surface
}

enum OcclusionProfile {
    OPAQUE_SOLID    = 0,  # blocks blast LOS fully
    LATTICE_POROUS  = 1,  # 50% blast LOS attenuation
    TRANSPARENT     = 2,  # no blast LOS attenuation
}
```

---

## 5. Identity and the Registry

### 5.1 Two-Layer Identity

Every part definition carries two identifiers:

| Identifier | Type | Purpose | Stability |
|---|---|---|---|
| `part_key` | `StringName` | Human-authored, dotted, hierarchical | Permanent. Never reused, never renamed. |
| `part_def_id` | `int` (uint16) | Compact network/save token | Assigned by manifest; permanent once shipped. |

`part_key` grammar (enforced by the validator in `tools/validate_part_registry.gd`):

```
part_key   := class_tag "." family "." variant "." tier_tag
class_tag  := "core" | "str" | "mot" | "pwr" | "eff" | "sup" | "ctl"
family     := [a-z][a-z0-9_]{2,23}
variant    := [a-z][a-z0-9_]{1,23}
tier_tag   := "t1" | "t2" | "t3" | "t4" | "t5"
```

Examples: `core.command.compact.t2`, `str.panel.medium.t2`, `mot.wheeled.offroad_heavy.t3`, `eff.ballistic.autocannon_30.t3`.

### 5.2 Manifest and ID Assignment

`data/parts/registry_manifest.tres` is a `PartManifest` resource holding an ordered `PackedStringArray` of `part_key` values. `part_def_id` is the array index plus one; index `0` is reserved for `INVALID_PART`. Order is append-only. The validator fails the build if any existing entry is reordered or removed. Deprecated parts are retained in the manifest and flagged `deprecated = true` in their definition so that historical saves and replays still resolve.

### 5.3 `PartRegistry` Autoload

```gdscript
class_name PartRegistryService
extends Node
## Autoload singleton: PartRegistry
## Immutable after _ready(). All accessors are O(1) and allocation-free.

var _by_id: Array[PartDefinition] = []
var _by_key: Dictionary = {}              # StringName -> PartDefinition
var _by_class: Dictionary = {}            # PartClass -> PackedInt32Array of ids
var _manifest_hash: int = 0

func _ready() -> void:
    var manifest: PartManifest = load("res://data/parts/registry_manifest.tres")
    _by_id.resize(manifest.keys.size() + 1)
    _by_id[0] = null
    for i in manifest.keys.size():
        var key := StringName(manifest.keys[i])
        var def: PartDefinition = load(_path_for_key(key))
        assert(def != null, "Manifest references missing definition: %s" % key)
        def._bind_runtime_id(i + 1)
        def._bake_derived_fields()
        _by_id[i + 1] = def
        _by_key[key] = def
        var bucket: PackedInt32Array = _by_class.get(def.part_class, PackedInt32Array())
        bucket.push_back(i + 1)
        _by_class[def.part_class] = bucket
    _manifest_hash = manifest.compute_content_hash()

func definition(part_def_id: int) -> PartDefinition:
    return _by_id[part_def_id]

func definition_by_key(key: StringName) -> PartDefinition:
    return _by_key.get(key, null)

func ids_of_class(part_class: int) -> PackedInt32Array:
    return _by_class.get(part_class, PackedInt32Array())

func manifest_hash() -> int:
    return _manifest_hash

func _path_for_key(key: StringName) -> String:
    var segments := String(key).split(".")
    return "res://data/parts/%s/%s.tres" % [segments[0], String(key)]
```

`manifest_hash()` is transmitted in the network handshake (see `HEADLESS_NETWORK_SYNC.md` §4.2). A mismatch between client and server hashes aborts the connection with `ERR_INCOMPATIBLE_CONTENT` rather than allowing silent desynchronisation.

---

## 6. The `PartDefinition` Resource

`PartDefinition` is a `Resource` subclass serialised as `.tres`. It is **read-only at runtime**; mutable per-instance state lives in `PartInstanceState` (§8).

```gdscript
class_name PartDefinition
extends Resource

## ===== IDENTITY =======================================================
@export var part_key: StringName = &""
@export var display_name_key: StringName = &""      # localisation key
@export var description_key: StringName = &""
@export var part_class: PartEnums.PartClass = PartEnums.PartClass.STRUCTURAL_COMPONENT
@export var tier: PartEnums.TierGrade = PartEnums.TierGrade.STANDARD
@export var deprecated: bool = false

## ===== LATTICE OCCUPANCY ==============================================
## Occupied cells in the part's own local lattice frame, orientation index 0.
## Cell (0,0,0) is the part's pivot cell and MUST be present.
@export var occupancy_cells: PackedVector3Array = PackedVector3Array()
## Axis-aligned bounding extent in cells, derived at bake time.
var bounds_min_cell: Vector3i = Vector3i.ZERO
var bounds_max_cell: Vector3i = Vector3i.ZERO

## ===== ATTACHMENT TOPOLOGY ============================================
@export var attachment_nodes: Array[AttachmentNodeDef] = []

## ===== MASS AND INERTIA ===============================================
@export var mass_kg: float = 30.0
## Offset of the part's centre of mass from its pivot cell centre, in metres.
@export var com_offset_m: Vector3 = Vector3.ZERO
## Inertia shape override; when ZERO the solver derives a box tensor from bounds.
@export var inertia_box_half_extents_m: Vector3 = Vector3.ZERO

## ===== STRUCTURAL INTEGRITY ===========================================
@export var integrity_max: float = 300.0
## Fraction of incoming damage nullified, indexed by DamageChannel.
@export var resistance: PackedFloat32Array = PackedFloat32Array([0,0,0,0,0])
## Effective armour rating opposing KINETIC penetration values.
@export var armour_rating: float = 12.0
## Structural load this part can carry before the dependency graph flags strain.
@export var load_capacity_kg: float = 400.0
@export var occlusion: PartEnums.OcclusionProfile = PartEnums.OcclusionProfile.OPAQUE_SOLID

## ===== POWER AND HEAT =================================================
@export var power_draw_pu: float = 0.0
@export var power_supply_pu: float = 0.0
@export var heat_generation_hu_s: float = 0.0
@export var heat_dissipation_hu_s: float = 0.0

## ===== CLASS-SPECIFIC PAYLOAD =========================================
## Exactly one of these is non-null, matching part_class. Enforced by validator.
@export var core_profile: CoreModuleProfile = null
@export var motive_profile: MotiveAssemblyProfile = null
@export var power_profile: PowerPlantProfile = null
@export var effector_profile: EffectorModuleProfile = null
@export var support_profile: SupportModuleProfile = null
@export var control_profile: ControlSurfaceProfile = null

## ===== PRESENTATION ===================================================
@export var visual_profile: PartVisualProfile = null   # see EXTENSION_PIPELINE.md
@export var collider_profile: ColliderProfile = null   # see §7
@export var fusion_profile: FusionProfile = null       # see PART_FUSION_SHADER.md

## ===== ECONOMY / LOADOUT VALIDATION ===================================
@export var build_cost: int = 100
@export var mount_weight: int = 1        # counts against Core Module mount budget

## ===== DERIVED (baked, not serialised) ================================
var runtime_id: int = 0
var occupancy_bitset: PackedByteArray = PackedByteArray()
var volume_cells: int = 0
var integrity_per_cell: float = 0.0

func _bind_runtime_id(id: int) -> void:
    runtime_id = id

func _bake_derived_fields() -> void:
    bounds_min_cell = Vector3i(2147483647, 2147483647, 2147483647)
    bounds_max_cell = Vector3i(-2147483648, -2147483648, -2147483648)
    for c in occupancy_cells:
        var ci := Vector3i(int(c.x), int(c.y), int(c.z))
        bounds_min_cell = bounds_min_cell.min(ci)
        bounds_max_cell = bounds_max_cell.max(ci)
    volume_cells = occupancy_cells.size()
    integrity_per_cell = integrity_max / maxf(1.0, float(volume_cells))
    occupancy_bitset = _pack_occupancy_bitset()
```

### 6.1 `AttachmentNodeDef`

```gdscript
class_name AttachmentNodeDef
extends Resource

@export var node_name: StringName = &"n0"
## Lattice cell (in part-local frame) that this node sits on the face of.
@export var cell: Vector3i = Vector3i.ZERO
## Outward face normal; MUST be one of the six axis unit vectors.
@export var face_normal: Vector3i = Vector3i(0, 1, 0)
@export var polarity: PartEnums.AttachmentPolarity = PartEnums.AttachmentPolarity.FACE_NEUTRAL
## Maximum tensile force this joint transmits before the graph marks it strained (newtons).
@export var joint_strength_n: float = 60000.0
## When true, this node may serve as a structural parent (load-bearing upstream link).
@export var can_bear_load: bool = true
## Restricts which part classes may mate here. Empty array = unrestricted.
@export var accepts_classes: PackedInt32Array = PackedInt32Array()
```

Face normals are constrained to `±X`, `±Y`, `±Z`. Diagonal mating is not supported; angled visual appearance is achieved through the fusion shader and skirting meshes (`PART_FUSION_SHADER.md`), never through arbitrary joint angles. This constraint is what keeps the lattice solver O(1) per placement query.

### 6.2 `ColliderProfile` — Decoupled Collision Architecture

**Architectural Invariant #1** (see `CLAUDE.md` §6): physics never touches a visual mesh. `ColliderProfile` describes the *only* geometry the physics server ever sees for this part.

```gdscript
class_name ColliderProfile
extends Resource

enum PrimitiveKind { BOX = 0, CYLINDER = 1, CAPSULE = 2, SPHERE = 3 }

class PrimitiveDef extends Resource:
    @export var kind: PrimitiveKind = PrimitiveKind.BOX
    @export var half_extents_m: Vector3 = Vector3(0.125, 0.125, 0.125)  # BOX
    @export var radius_m: float = 0.125                                  # CYL/CAP/SPH
    @export var height_m: float = 0.25                                   # CYL/CAP
    @export var local_offset_m: Vector3 = Vector3.ZERO
    @export var local_basis_euler_deg: Vector3 = Vector3.ZERO

@export var primitives: Array[PrimitiveDef] = []
## Hard ceiling. The validator rejects any profile exceeding this.
const MAX_PRIMITIVES_PER_PART: int = 3
```

Rules enforced by `tools/validate_part_registry.gd`:

1. `primitives.size()` is in `[1, 3]`.
2. Only `BOX`, `CYLINDER`, `CAPSULE`, `SPHERE` are permitted. `ConvexPolygonShape3D` and `ConcavePolygonShape3D` are **forbidden** on any Assembly part.
3. The union of primitives must cover at least 82% of `occupancy_cells` volume and must not exceed 118% of it. This tolerance band prevents both "phantom gap" exploits and oversized invisible hitboxes.
4. `local_basis_euler_deg` components must be multiples of 15° so that oriented primitives remain reproducible across platforms.

Visual meshes carry no collision data whatsoever. Every `MeshInstance3D` spawned for a part lives under a node whose `collision_layer` and `collision_mask` are both `0`, and no `StaticBody3D`/`CollisionShape3D` is ever generated from mesh geometry at runtime.

### 6.3 `FusionProfile`

Consumed by `PART_FUSION_SHADER.md`. Declares how this part participates in seam elimination.

```gdscript
class_name FusionProfile
extends Resource

## Radius of the procedural fillet applied where this part meets a neighbour, metres.
@export var fillet_radius_m: float = 0.045
## Whether this part contributes to the assembly-wide occupancy SDF used for blending.
@export var contributes_to_sdf: bool = true
## Whether smart skirting strips may be generated along this part's exposed edges.
@export var accepts_skirting: bool = true
## Panel family; only parts sharing a family fuse seamlessly. Cross-family seams
## receive a weld-bead strip instead of a smooth fillet.
@export var fusion_family: StringName = &"plate_std"
## Surface treatment index into the shared fusion material atlas (0..15).
@export var surface_variant: int = 0
```

---

## 7. Class-Specific Profiles

### 7.1 `CoreModuleProfile`

```gdscript
class_name CoreModuleProfile
extends Resource

@export var power_capacity_pu: float = 240.0
@export var mount_budget: int = 28
@export var speed_cap_mps: float = 22.0
@export var control_authority: float = 1.0     # steering responsiveness multiplier
@export var mass_tolerance_kg: float = 4200.0  # above this, handling penalties accrue
@export var operator_seat_offset_m: Vector3 = Vector3(0.0, 0.35, 0.0)
@export var respawn_integrity_fraction: float = 1.0
```

The Core Module is the graph root and the `RigidBody3D` owner. There is exactly one per Assembly and it is always slot `0`.

### 7.2 `MotiveAssemblyProfile`

```gdscript
class_name MotiveAssemblyProfile
extends Resource

@export var kind: PartEnums.MotiveKind = PartEnums.MotiveKind.WHEELED_STEERED
@export var contact_radius_m: float = 0.42
@export var contact_width_m: float = 0.26
@export var suspension_rest_length_m: float = 0.32
@export var suspension_stiffness_n_m: float = 42000.0
@export var suspension_damping_ns_m: float = 3400.0
@export var suspension_travel_limit_m: float = 0.24
@export var max_steer_angle_deg: float = 32.0
@export var steer_rate_deg_s: float = 140.0
@export var rated_load_kg: float = 620.0
@export var traction_coefficient: float = 1.05
@export var rolling_resistance: float = 0.014
@export var brake_torque_nm: float = 2600.0
@export var driven: bool = true
```

`traction_coefficient` is the *nominal* value. `DYNAMIC_MASS_PHYSICS.md` §6 and `COMPONENT_HEALTH_DAMAGE.md` §7 define the degradation multipliers applied on top of it.

### 7.3 `PowerPlantProfile`

```gdscript
class_name PowerPlantProfile
extends Resource

@export var drive_torque_nm: float = 3200.0
@export var torque_curve: Curve = null          # normalised RPM -> torque scalar
@export var peak_angular_rpm: float = 5200.0
@export var throttle_response_s: float = 0.18
@export var thermal_throttle_start_hu: float = 620.0
@export var thermal_shutdown_hu: float = 900.0
@export var detonation_blast_radius_m: float = 4.2
@export var detonation_blast_damage: float = 380.0
```

### 7.4 `EffectorModuleProfile`

Full semantics in `WEAPON_TARGETING_LOGIC.md`. Schema:

```gdscript
class_name EffectorModuleProfile
extends Resource

@export var kind: PartEnums.EffectorKind = PartEnums.EffectorKind.BALLISTIC_DIRECT
@export var yaw_limit_deg: Vector2 = Vector2(-180.0, 180.0)
@export var pitch_limit_deg: Vector2 = Vector2(-8.0, 34.0)
@export var yaw_rate_deg_s: float = 65.0
@export var pitch_rate_deg_s: float = 48.0
@export var muzzle_offsets_m: PackedVector3Array = PackedVector3Array([Vector3(0, 0, 0.6)])
@export var projectile_key: StringName = &"proj.kinetic.ap_30"
@export var muzzle_velocity_mps: float = 940.0
@export var cycle_time_s: float = 0.14
@export var burst_count: int = 0                # 0 = continuous fire
@export var burst_recovery_s: float = 0.0
@export var magazine_rounds: int = 0            # 0 = no magazine model
@export var reload_time_s: float = 0.0
@export var spread_base_deg: float = 0.25
@export var spread_bloom_deg: float = 0.09
@export var spread_decay_deg_s: float = 0.55
@export var recoil_impulse_ns: float = 1450.0
@export var heat_per_shot_hu: float = 7.5
@export var jam_clear_time_s: float = 1.6
```

### 7.5 `SupportModuleProfile`

```gdscript
class_name SupportModuleProfile
extends Resource

enum SupportRole { HEAT_SINK = 0, MAGAZINE_STORE = 1, INTEGRITY_FIELD = 2,
                   SIGNATURE_DAMPER = 3, REPAIR_EMITTER = 4 }

@export var role: SupportRole = SupportRole.HEAT_SINK
@export var effect_magnitude: float = 1.0
@export var effect_radius_m: float = 0.0        # 0 = assembly-wide
@export var activation_cooldown_s: float = 0.0
@export var active_duration_s: float = 0.0
@export var volatile_on_destruction: bool = false
```

### 7.6 `ControlSurfaceProfile`

```gdscript
class_name ControlSurfaceProfile
extends Resource

@export var reference_area_m2: float = 0.34
@export var lift_coefficient: float = -0.62     # negative = downforce
@export var drag_coefficient: float = 0.11
@export var stall_angle_deg: float = 14.0
@export var pressure_centre_offset_m: Vector3 = Vector3.ZERO
```

---

## 8. Runtime Instance State

`PartDefinition` is immutable; every mutable per-part value lives in a tightly packed `PartInstanceState`. Assemblies own a contiguous `Array[PartInstanceState]` indexed by slot, so iteration is cache-coherent and slot lookup is a single array index.

```gdscript
class_name PartInstanceState
extends RefCounted

var slot: int = SyndicateConstants.INVALID_SLOT
var part_def_id: int = 0
var origin_cell: Vector3i = Vector3i.ZERO
var orientation_index: int = 0                  # 0..23, see GRID_SNAPPING_LOGIC.md §4
var parent_slot: int = SyndicateConstants.INVALID_SLOT
var child_slots: PackedInt32Array = PackedInt32Array()
var integrity: float = 0.0
var integrity_band: PartEnums.IntegrityBand = PartEnums.IntegrityBand.NOMINAL
var accumulated_heat_hu: float = 0.0
var flags: int = 0                              # bitfield, see §8.1
var visual_node_path: NodePath = NodePath()
var collider_shape_ids: PackedInt32Array = PackedInt32Array()

func integrity_fraction(def: PartDefinition) -> float:
    return clampf(integrity / def.integrity_max, 0.0, 1.0)
```

### 8.1 Instance Flag Bits

| Bit | Name | Meaning |
|---|---|---|
| 0 | `FLAG_DESTROYED` | Integrity reached zero; awaiting despawn or already detached. |
| 1 | `FLAG_DETACHED` | Severed from the Chassis Graph; converted to debris. |
| 2 | `FLAG_SUBMERGED` | Contact volume inside a fluid region. |
| 3 | `FLAG_OVERHEATED` | Heat exceeded the part's thermal throttle threshold. |
| 4 | `FLAG_JAMMED` | Effector Module in jam-recovery state. |
| 5 | `FLAG_STRAINED` | Parent joint is carrying load beyond `joint_strength_n`. |
| 6 | `FLAG_VISUAL_DIRTY` | Visual/fusion state needs a rebuild this frame. |
| 7 | `FLAG_NET_DIRTY` | State changed since last replicated snapshot. |
| 8 | `FLAG_POWER_STARVED` | Assembly power budget insufficient to run this module. |
| 9 | `FLAG_SUPPRESSED` | Temporarily disabled by an external effect. |

---

## 9. Attribute Derivation Rules

Derived attributes are computed exactly once per relevant event — never per frame. The following table binds each derived value to its trigger.

| Derived Value | Formula | Recompute Trigger |
|---|---|---|
| Assembly total mass | `Σ mass_kg` over live slots | Part attach, part detach, part destroy |
| Assembly centre of mass | `Σ (mass_i · p_i) / Σ mass_i` | Same as above |
| Assembly inertia tensor | Parallel-axis sum of per-part box tensors | Same as above |
| Power balance | `Σ power_supply_pu − Σ power_draw_pu` | Part attach/detach/destroy, Power Plant band change |
| Mount usage | `Σ mount_weight` | Part attach/detach |
| Effective traction (per motive) | `traction_coefficient · band_mult · load_mult` | Band change, mass recompute, surface change |
| Heat capacity | `Σ heat_dissipation_hu_s` | Part attach/detach/destroy, Support Module band change |
| Structural load per joint | Downstream subtree mass × g × dynamic factor | Graph edit, mass recompute |

The rule is absolute: **no derived attribute is recomputed inside `_process` or `_physics_process`.** Recomputation is driven from `EventBus` signals listed in `DEPENDENCY_TREE_GRAPH.md` §8.

---

## 10. Mass and Integrity Tables

All tables below are the shipping baseline for Tier 2 (`STANDARD`) unless a tier column is given. Dimensions are in lattice cells (`0.25 m` each). These values are the source data for the `.tres` files under `data/parts/`.

### 10.1 Core Modules

| `part_key` | Cells (X×Y×Z) | Mass (kg) | Integrity | Armour | Power Cap (PU) | Mounts | Speed Cap (m/s) | Mass Tol. (kg) |
|---|---|---|---|---|---|---|---|---|
| `core.command.compact.t2` | 4×3×5 | 380 | 1450 | 18 | 240 | 28 | 24.0 | 3600 |
| `core.command.balanced.t2` | 5×4×6 | 520 | 1900 | 22 | 310 | 34 | 21.0 | 4800 |
| `core.command.bastion.t3` | 6×5×7 | 780 | 2850 | 31 | 380 | 40 | 17.5 | 7200 |
| `core.command.skirmish.t3` | 4×3×4 | 300 | 1150 | 15 | 260 | 24 | 28.0 | 2900 |
| `core.command.siege.t4` | 7×5×8 | 1140 | 4200 | 39 | 520 | 48 | 14.0 | 11000 |
| `core.command.vanguard.t4` | 5×4×6 | 560 | 2350 | 27 | 460 | 38 | 25.5 | 5400 |
| `core.command.apex_prime.t5` | 6×5×7 | 820 | 3600 | 35 | 640 | 46 | 23.0 | 8600 |

### 10.2 Structural Components

| `part_key` | Cells | Mass (kg) | Integrity | Armour | Load Cap (kg) | Occlusion |
|---|---|---|---|---|---|---|
| `str.panel.light.t1` | 4×1×4 | 14 | 160 | 6 | 220 | `OPAQUE_SOLID` |
| `str.panel.medium.t2` | 4×1×4 | 34 | 380 | 14 | 520 | `OPAQUE_SOLID` |
| `str.panel.heavy.t3` | 4×1×4 | 68 | 720 | 26 | 980 | `OPAQUE_SOLID` |
| `str.panel.composite.t4` | 4×1×4 | 52 | 810 | 31 | 900 | `OPAQUE_SOLID` |
| `str.beam.spar.t2` | 8×1×1 | 22 | 290 | 11 | 1400 | `OPAQUE_SOLID` |
| `str.beam.girder.t3` | 12×2×2 | 96 | 940 | 24 | 3200 | `OPAQUE_SOLID` |
| `str.wedge.forward.t2` | 4×2×4 | 41 | 430 | 19 | 480 | `OPAQUE_SOLID` |
| `str.wedge.forward.t3` | 4×2×4 | 79 | 800 | 30 | 900 | `OPAQUE_SOLID` |
| `str.frame.open.t2` | 4×2×4 | 19 | 240 | 8 | 760 | `LATTICE_POROUS` |
| `str.frame.cage.t3` | 6×4×6 | 74 | 690 | 17 | 2100 | `LATTICE_POROUS` |
| `str.bumper.impact.t2` | 6×2×2 | 45 | 560 | 21 | 640 | `OPAQUE_SOLID` |
| `str.bumper.impact.t4` | 6×2×2 | 71 | 1080 | 34 | 1150 | `OPAQUE_SOLID` |
| `str.deck.flat.t2` | 6×1×6 | 47 | 420 | 12 | 1600 | `OPAQUE_SOLID` |
| `str.riser.column.t2` | 2×4×2 | 26 | 330 | 13 | 1900 | `OPAQUE_SOLID` |
| `str.shell.curved.t3` | 6×3×4 | 88 | 900 | 27 | 820 | `OPAQUE_SOLID` |
| `str.aperture.port.t2` | 4×2×1 | 21 | 210 | 9 | 300 | `TRANSPARENT` |

### 10.3 Motive Assemblies

| `part_key` | Kind | Cells | Mass (kg) | Integrity | Rated Load (kg) | Traction | Steer (°) | Susp. k (N/m) | Susp. c (Ns/m) |
|---|---|---|---|---|---|---|---|---|---|
| `mot.wheeled.light_road.t1` | `WHEELED_STEERED` | 3×3×2 | 42 | 210 | 380 | 1.18 | 34 | 30000 | 2400 |
| `mot.wheeled.allroad.t2` | `WHEELED_STEERED` | 4×4×2 | 68 | 340 | 620 | 1.05 | 32 | 42000 | 3400 |
| `mot.wheeled.offroad_heavy.t3` | `WHEELED_STEERED` | 5×5×3 | 124 | 610 | 1180 | 0.96 | 28 | 68000 | 5200 |
| `mot.wheeled.fixed_rear.t2` | `WHEELED_FIXED` | 4×4×2 | 62 | 355 | 680 | 1.09 | 0 | 44000 | 3500 |
| `mot.wheeled.armoured.t4` | `WHEELED_STEERED` | 5×5×3 | 168 | 1050 | 1320 | 0.91 | 24 | 74000 | 5900 |
| `mot.tracked.short_bogie.t2` | `TRACKED_SEGMENT` | 8×4×3 | 210 | 900 | 2100 | 1.34 | 0 | 88000 | 7600 |
| `mot.tracked.long_bogie.t3` | `TRACKED_SEGMENT` | 12×4×3 | 320 | 1420 | 3400 | 1.41 | 0 | 112000 | 9800 |
| `mot.omni.roller.t3` | `OMNI_ROLLER` | 4×4×4 | 96 | 400 | 720 | 0.88 | 0 | 52000 | 4100 |
| `mot.limb.strider.t4` | `AMBULATORY_LIMB` | 3×8×3 | 185 | 720 | 1400 | 1.22 | 45 | 96000 | 12000 |
| `mot.repulsor.pad.t5` | `REPULSOR_PAD` | 5×2×5 | 140 | 480 | 1600 | 0.72 | 0 | 26000 | 8800 |

### 10.4 Power Plants

| `part_key` | Cells | Mass (kg) | Integrity | Torque (N·m) | Peak RPM | Supply (PU) | Heat (HU/s) | Blast R (m) | Blast Dmg |
|---|---|---|---|---|---|---|---|---|---|
| `pwr.combustion.compact.t1` | 3×3×4 | 95 | 260 | 1900 | 4600 | 90 | 5.2 | 3.0 | 210 |
| `pwr.combustion.standard.t2` | 4×3×5 | 155 | 420 | 3200 | 5200 | 150 | 7.4 | 4.2 | 380 |
| `pwr.combustion.forced.t3` | 5×4×6 | 240 | 610 | 5100 | 6100 | 215 | 11.8 | 5.4 | 620 |
| `pwr.turbine.axial.t4` | 5×4×7 | 285 | 700 | 6800 | 8800 | 300 | 16.5 | 6.1 | 880 |
| `pwr.cell.static.t3` | 4×3×4 | 175 | 540 | 0 | 0 | 260 | 1.1 | 3.4 | 300 |
| `pwr.cell.static.t5` | 4×3×4 | 205 | 780 | 0 | 0 | 420 | 0.7 | 4.0 | 460 |

### 10.5 Effector Modules

| `part_key` | Kind | Cells | Mass (kg) | Integrity | Draw (PU) | Cycle (s) | Muzzle (m/s) | Recoil (N·s) | Heat/shot |
|---|---|---|---|---|---|---|---|---|---|
| `eff.ballistic.autocannon_20.t2` | `BALLISTIC_DIRECT` | 4×3×7 | 118 | 340 | 42 | 0.11 | 880 | 980 | 5.4 |
| `eff.ballistic.autocannon_30.t3` | `BALLISTIC_DIRECT` | 5×4×9 | 196 | 480 | 68 | 0.14 | 940 | 1450 | 7.5 |
| `eff.ballistic.rifle_long.t3` | `BALLISTIC_DIRECT` | 4×3×12 | 165 | 400 | 55 | 1.35 | 1180 | 4200 | 14.0 |
| `eff.ballistic.scatter_short.t2` | `BALLISTIC_DIRECT` | 4×3×5 | 88 | 300 | 30 | 0.72 | 460 | 2600 | 9.2 |
| `eff.arced.mortar_medium.t3` | `BALLISTIC_ARCED` | 5×5×5 | 210 | 420 | 60 | 2.10 | 190 | 3100 | 12.5 |
| `eff.beam.emitter_mid.t4` | `CONTINUOUS_BEAM` | 4×4×6 | 175 | 380 | 130 | 0.05 | 0 | 0 | 18.0 |
| `eff.guided.pod_quad.t3` | `GUIDED_ORDNANCE` | 5×3×5 | 140 | 320 | 48 | 0.35 | 62 | 640 | 6.0 |
| `eff.guided.pod_heavy.t4` | `GUIDED_ORDNANCE` | 6×4×6 | 235 | 500 | 76 | 0.90 | 54 | 1100 | 10.5 |
| `eff.melee.ram_spike.t2` | `KINETIC_MELEE` | 5×3×3 | 130 | 900 | 0 | 0.00 | 0 | 0 | 0.0 |
| `eff.melee.rotor_blade.t4` | `KINETIC_MELEE` | 6×4×3 | 245 | 1300 | 90 | 0.00 | 0 | 0 | 4.5 |

### 10.6 Support Modules

| `part_key` | Role | Cells | Mass (kg) | Integrity | Draw (PU) | Magnitude | Volatile |
|---|---|---|---|---|---|---|---|
| `sup.heatsink.passive.t2` | `HEAT_SINK` | 3×2×3 | 38 | 190 | 0 | 12.0 HU/s | no |
| `sup.heatsink.active.t4` | `HEAT_SINK` | 4×3×4 | 72 | 300 | 34 | 31.0 HU/s | no |
| `sup.magazine.compact.t2` | `MAGAZINE_STORE` | 3×3×3 | 56 | 150 | 0 | +40% rounds | yes |
| `sup.magazine.hardened.t4` | `MAGAZINE_STORE` | 4×3×4 | 92 | 420 | 6 | +65% rounds | no |
| `sup.field.integrity.t3` | `INTEGRITY_FIELD` | 4×3×4 | 84 | 260 | 88 | +18% resist | no |
| `sup.damper.signature.t3` | `SIGNATURE_DAMPER` | 3×2×3 | 44 | 200 | 52 | −45% lock rate | no |
| `sup.emitter.repair.t4` | `REPAIR_EMITTER` | 4×3×4 | 96 | 340 | 105 | 22 int/s | no |

### 10.7 Control Surfaces

| `part_key` | Cells | Mass (kg) | Integrity | Area (m²) | C_L | C_D | Stall (°) |
|---|---|---|---|---|---|---|---|
| `ctl.spoiler.low.t2` | 8×1×2 | 18 | 140 | 0.34 | −0.62 | 0.11 | 14 |
| `ctl.spoiler.tall.t3` | 8×3×2 | 31 | 210 | 0.58 | −1.04 | 0.19 | 12 |
| `ctl.vane.canard.t3` | 4×1×3 | 12 | 120 | 0.22 | −0.41 | 0.08 | 16 |
| `ctl.diffuser.underbody.t4` | 10×1×6 | 46 | 300 | 1.10 | −1.35 | 0.14 | 20 |

---

## 11. Resistance Matrix

Resistance values are fractions in `[0.0, 0.85]`. The hard ceiling of `0.85` is enforced by the validator so that no configuration can achieve immunity. Values below are per part **family**, applied to every tier in that family.

| Family | KINETIC | BLAST | IMPACT | THERMAL | CORROSIVE |
|---|---|---|---|---|---|
| `core.command.*` | 0.15 | 0.20 | 0.25 | 0.10 | 0.05 |
| `str.panel.light` | 0.05 | 0.00 | 0.10 | 0.00 | 0.00 |
| `str.panel.medium` | 0.18 | 0.10 | 0.20 | 0.05 | 0.05 |
| `str.panel.heavy` | 0.34 | 0.22 | 0.30 | 0.10 | 0.10 |
| `str.panel.composite` | 0.28 | 0.42 | 0.24 | 0.38 | 0.20 |
| `str.beam.*` | 0.22 | 0.08 | 0.34 | 0.12 | 0.08 |
| `str.wedge.*` | 0.30 | 0.14 | 0.22 | 0.08 | 0.06 |
| `str.frame.*` | 0.10 | 0.46 | 0.12 | 0.20 | 0.04 |
| `str.bumper.*` | 0.20 | 0.16 | 0.58 | 0.06 | 0.06 |
| `mot.wheeled.*` | 0.08 | 0.12 | 0.30 | 0.02 | 0.00 |
| `mot.tracked.*` | 0.24 | 0.18 | 0.40 | 0.08 | 0.04 |
| `mot.limb.*` | 0.16 | 0.14 | 0.26 | 0.06 | 0.02 |
| `mot.repulsor.*` | 0.06 | 0.30 | 0.10 | 0.24 | 0.00 |
| `pwr.combustion.*` | 0.10 | 0.05 | 0.15 | 0.30 | 0.02 |
| `pwr.turbine.*` | 0.12 | 0.06 | 0.18 | 0.40 | 0.04 |
| `pwr.cell.*` | 0.14 | 0.02 | 0.12 | 0.08 | 0.02 |
| `eff.ballistic.*` | 0.12 | 0.10 | 0.18 | 0.14 | 0.06 |
| `eff.arced.*` | 0.14 | 0.12 | 0.20 | 0.12 | 0.06 |
| `eff.beam.*` | 0.08 | 0.14 | 0.12 | 0.44 | 0.10 |
| `eff.guided.*` | 0.06 | 0.04 | 0.10 | 0.06 | 0.04 |
| `eff.melee.*` | 0.36 | 0.20 | 0.62 | 0.14 | 0.10 |
| `sup.*` | 0.10 | 0.08 | 0.14 | 0.16 | 0.08 |
| `ctl.*` | 0.04 | 0.02 | 0.08 | 0.04 | 0.02 |

---

## 12. Tier Scaling Model

Rather than hand-authoring every tier of every family, the validator verifies that tier variants of the same family obey the scaling model below. Deviations greater than ±8% must be justified with an `@export var balance_exception_note: String` on the definition, which the validator prints in its report.

Let `t` be the tier grade (1..5) and `b` the Tier-2 baseline value.

```
integrity(t)   = b * (0.62, 1.00, 1.72, 2.48, 3.30)[t-1]
mass(t)        = b * (0.78, 1.00, 1.38, 1.62, 1.74)[t-1]
armour(t)      = b * (0.55, 1.00, 1.66, 2.20, 2.72)[t-1]
build_cost(t)  = b * (0.40, 1.00, 2.60, 6.40, 15.0)[t-1]
```

Note that `mass` scales sub-linearly relative to `integrity`. This is deliberate: higher tiers deliver better integrity-per-kilogram, which is the primary progression axis, while the steep `build_cost` curve is the balancing counterweight.

---

## 13. Serialisation Formats

### 13.1 Saved Assembly Blueprint (`.syn` container)

Blueprints are stored as a `PackedByteArray` inside a `Resource` wrapper, never as human-editable text, so that the format is versioned and validated rather than hand-patched.

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | Magic `0x53594E42` ("SYNB") |
| 4 | 2 | Format version (uint16, currently `3`) |
| 6 | 8 | Registry manifest hash (uint64) |
| 14 | 1 | Part count `N` (uint8) |
| 15 | 4 | Reserved flags (uint32) |
| 19 | `N × 12` | Part records |
| … | 2 | CRC-16/CCITT over bytes `[0, end-2)` |

Part record layout (12 bytes):

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | `part_def_id` (uint16) |
| 2 | 1 | `origin_cell.x` (uint8, 0..47) |
| 3 | 1 | `origin_cell.y` (uint8, 0..31) |
| 4 | 1 | `origin_cell.z` (uint8, 0..47) |
| 5 | 1 | `orientation_index` (uint8, 0..23) |
| 6 | 1 | `parent_slot` (uint8, 255 = root) |
| 7 | 1 | Cosmetic surface variant (uint8) |
| 8 | 4 | Colour tint, packed RGBA8 |

A blueprint whose manifest hash does not match the running registry is loaded in **compatibility mode**: unknown `part_def_id` values resolve to a visible `INVALID_PART` placeholder and the blueprint is flagged read-only until the player resolves the mismatch. It is never silently repaired.

### 13.2 Live Assembly Network State

Defined in `HEADLESS_NETWORK_SYNC.md` §5. `PART_DATA_SCHEMA.md` fixes only the quantisation:

- Integrity is transmitted as `uint8`, computed as `round(integrity_fraction × 255)`.
- `integrity_band` is transmitted as a 3-bit field and is authoritative for gameplay effects. Clients never derive band from the quantised fraction, because rounding at a band boundary would produce divergent degradation states.

---

## 14. Validation Rules

`tools/validate_part_registry.gd` runs in CI and as a pre-commit hook. It fails the build on any of the following:

1. `part_key` violates the §5.1 grammar.
2. `part_key` is absent from `registry_manifest.tres`, or the manifest order changed.
3. `occupancy_cells` does not contain `Vector3i(0,0,0)`.
4. `occupancy_cells` contains duplicates, or is not 6-connected (a part must be a single contiguous solid).
5. `occupancy_cells` extent exceeds `Vector3i(16, 16, 16)`.
6. The class-specific profile does not match `part_class`, or more than one profile is non-null.
7. `resistance` has a length other than `DAMAGE_CHANNEL_COUNT`, or any element is outside `[0.0, 0.85]`.
8. `collider_profile` violates any rule in §6.2.
9. Any `AttachmentNodeDef.face_normal` is not an axis unit vector.
10. Any `AttachmentNodeDef.cell` is not in `occupancy_cells`.
11. Two attachment nodes share the same `(cell, face_normal)` pair.
12. `mass_kg <= 0.0` or `integrity_max <= 0.0`.
13. Tier scaling deviates beyond ±8% without a `balance_exception_note`.
14. `visual_profile` references a mesh that carries any collision-generating flag.
15. A `CORE_MODULE` definition has `mount_budget < 8` or `power_capacity_pu <= 0`.
16. Any Effector Module has `yaw_limit_deg.x > yaw_limit_deg.y` or `pitch_limit_deg.x > pitch_limit_deg.y`.

The validator emits `res://.build/part_registry_report.md` summarising totals per class, mass histograms, integrity-per-kilogram outliers, and every exception note. This report is a required review artefact for any balance change.

---

## 15. Interfaces Consumed By Other Documents

| Consumer Document | Fields Consumed |
|---|---|
| `GRID_SNAPPING_LOGIC.md` | `occupancy_cells`, `occupancy_bitset`, `attachment_nodes`, `bounds_*` |
| `PART_FUSION_SHADER.md` | `fusion_profile`, `occupancy_cells`, `visual_profile` |
| `DEPENDENCY_TREE_GRAPH.md` | `attachment_nodes.joint_strength_n`, `can_bear_load`, `mass_kg`, `load_capacity_kg` |
| `DYNAMIC_MASS_PHYSICS.md` | `mass_kg`, `com_offset_m`, `inertia_box_half_extents_m`, `motive_profile`, `control_profile` |
| `AUTO_ASSEMBLE_ALGORITHM.md` | Every field; the solver is a constraint search over the full schema |
| `WEAPON_TARGETING_LOGIC.md` | `effector_profile`, `power_draw_pu`, `heat_generation_hu_s` |
| `COMPONENT_HEALTH_DAMAGE.md` | `integrity_max`, `resistance`, `armour_rating`, `occlusion`, band constants |
| `TERRAIN_CRATER_DEFORMER.md` | Blast fields on `power_profile` and projectile definitions |
| `PROCEDURAL_STRUCTURE_SLICING.md` | `collider_profile` conventions (shared with Static Volumes) |
| `RESPONSIVE_GARAGE_UI.md` | `display_name_key`, `tier`, `build_cost`, `mount_weight`, all stat fields |
| `HEADLESS_NETWORK_SYNC.md` | `part_def_id`, quantisation rules, `manifest_hash()` |
| `EXTENSION_PIPELINE.md` | `visual_profile`, `collider_profile`, `fusion_profile` |
