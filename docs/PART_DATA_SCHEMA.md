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
const GRAVITY_MPS2: float = 9.81
const AIR_DENSITY_KG_M3: float = 1.225
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

`GRAVITY_MPS2` is declared here rather than read from `ProjectSettings` because the strain model (`DEPENDENCY_TREE_GRAPH.md` §4.1), the suspension load split (`DYNAMIC_MASS_PHYSICS.md` §6), and the ballistic solver (`WEAPON_TARGETING_LOGIC.md` §5) must all agree on it exactly, and a project setting can be changed by an editor action that touches no code. It was added when the strain model became the first system to need it as a named value; the documents above previously each wrote the literal.

**Amendment.** `AIR_DENSITY_KG_M3` is declared here for the identical reason, and was added when rotor lift became the second consumer of it. `DYNAMIC_MASS_PHYSICS.md` §8 (Control Surface aerodynamics) and §12 (rotor thrust) both need `ρ`, and §12's momentum-theory thrust and §8's dynamic pressure must not be able to disagree about the atmosphere they are computed in — a rotorcraft carrying a Control Surface would otherwise generate lift and drag from two different airs. Document 05 continues to own every other aerodynamic constant; it owns only the *use* of this one, not its value.

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
    ROTOR_DISC       = 6,
}

## Which solver in DYNAMIC_MASS_PHYSICS.md moves an Assembly carrying this
## Motive Assembly. Derived from MotiveKind, never authored.
enum LocomotionMode {
    GROUND     = 0,   # doc 05 §6 suspension + §7 traction
    ROTARY     = 1,   # doc 05 §12 rotor lift and tilt
    AMBULATORY = 2,   # doc 05 §13 gait
    TRACKED    = 3,   # doc 05 §14 road stations and differential drive
}

## Indexed by MotiveKind. Frozen alongside the enum it indexes.
const LOCOMOTION_OF_MOTIVE_KIND: Array[int] = [
    LocomotionMode.GROUND,      # WHEELED_STEERED
    LocomotionMode.GROUND,      # WHEELED_FIXED
    LocomotionMode.TRACKED,     # TRACKED_SEGMENT
    LocomotionMode.GROUND,      # OMNI_ROLLER
    LocomotionMode.AMBULATORY,  # AMBULATORY_LIMB
    LocomotionMode.GROUND,      # REPULSOR_PAD
    LocomotionMode.ROTARY,      # ROTOR_DISC
]

enum EffectorKind {
    BALLISTIC_DIRECT   = 0,
    BALLISTIC_ARCED    = 1,
    CONTINUOUS_BEAM    = 2,
    GUIDED_ORDNANCE    = 3,
    KINETIC_MELEE      = 4,
    ENERGY_MELEE       = 5,
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

### 4.1 Three Locomotion Families, One Class

`ROTOR_DISC` and `ENERGY_MELEE` were appended when the project committed to shipping rotary-wing and ambulatory Assemblies alongside wheeled ones. They are appends, not a redesign, and that is the point: an Assembly that flies is not a different kind of object. It is the same `RigidBody3D`, the same Chassis Graph, the same damage model, and the same one Core Module — it merely has Motive Assemblies whose contribution to `F` and `τ` is computed by a different solver.

`LocomotionMode` exists so that no subsystem outside `MotiveSystem` ever branches on `MotiveKind`. A rotor is not a special case of a wheel with the traction turned off; it is a distinct force producer selected by one array index, and adding a fourth family later is an append to `LOCOMOTION_OF_MOTIVE_KIND` rather than a new branch in every consumer.

The three families and where their physics lives:

| Family | Kinds | Solver | Produces |
|---|---|---|---|
| Ground | `WHEELED_*`, `OMNI_ROLLER`, `REPULSOR_PAD` | doc 05 §6 + §7 | Suspension normal force at one hub, longitudinal and lateral friction |
| Tracked | `TRACKED_SEGMENT` | doc 05 §14 | The same, distributed across road stations, steered by differential drive |
| Rotary | `ROTOR_DISC` | doc 05 §12 | Thrust along a tiltable disc axis, reaction torque, shaft power draw |
| Ambulatory | `AMBULATORY_LIMB` | doc 05 §13 | Virtual-leg stance force at a planted foot, gait-phased |

`TRACKED` is its own family rather than a flag on `GROUND`, and the reason is worth stating because the opposite decision is the tempting one. A track reuses the ground family's *mathematics* — the same spring-damper of §6.2, the same Pacejka curve of §7.2 — but not its *shape*: it carries several contacts instead of one, it steers by driving its two sides at different rates instead of by angling a hub, and slewing its patch across the ground costs it grip in a way a point contact has no term for. Routed through `GROUND`, each of those becomes an `if kind == TRACKED_SEGMENT` inside a hot loop, which is precisely what `LOCOMOTION_OF_MOTIVE_KIND` exists to prevent. Routed through its own family, the shared mathematics stays shared because §6 and §7 are pure static solvers that `TrackSolver` calls.

### 4.2 `AXLE` Is a Keyed Connector — Resolved

`AttachmentPolarity.AXLE` mates only with `AXLE` (§7.3 of `GRID_SNAPPING_LOGIC.md`, and the matrix is asserted cell by cell in `tests/unit/test_attachment_polarity.gd`). Until the first Motive Assembly was authored it had no user, and the open question was whether a Motive Assembly's mounting face should be `AXLE` — which under rule 11 of §14 makes it *only* `AXLE`, since a cell face carries exactly one node — or `FACE_NEUTRAL` like everything else, which would leave `AXLE` permanently dead.

**Resolved in favour of the keyed reading.** A Motive Assembly's drive face carries `AXLE` and nothing else. It therefore cannot be mated to an arbitrary armour panel; it mates to a Structural Component that offers an `AXLE` station, whose nodes additionally restrict `accepts_classes` to `MOTIVE_ASSEMBLY`. The shipping station is `str.hub.axle_station.t2` (§10.2), a 2×2×2 block with `AXLE` on ±X and neutral faces elsewhere, so it bolts to structure through Z or Y and offers two drive stations on X.

**The two `accepts_classes` lists are not the same list.** The restriction to `MOTIVE_ASSEMBLY` belongs to the *station*; the drive face's own list must admit `STRUCTURAL_COMPONENT`, and the clearest authoring is to restrict it to exactly that. `PlacementValidator._check_mating` tests the restriction from both ends, so putting the station's list on the drive face makes the pair reject each other and leaves the Motive Assembly with nothing in the game it can attach to. §14 rule 18 now enforces both halves.

A second consequence of the station's geometry is worth stating because it is not obvious from the table: the station's two `AXLE` faces are **opposite each other**, so a station cannot bolt on through one and offer the other. It attaches through a neutral face — Y or Z at orientation 0 — and both drive faces stay free. A station mounted under a Core Module's corner therefore carries a Motive Assembly outboard on either side, and a station carrying a mast on `+Y` must itself attach sideways.

Three reasons this is the right reading rather than the convenient one:

1. **It is the only reading under which the polarity means anything.** A polarity that mates with everything is `FACE_NEUTRAL` with extra steps.
2. **It makes the drive train a build decision.** A wheel is not glue. Mounting one costs a hub, mass, and a mount station, which is exactly the trade the rest of the schema makes the player reason about.
3. **One station serves all three families.** The 24-orientation group points the station's drive axis anywhere, so the same part carries a wheel on a horizontal axis, a rotor mast on a vertical one, and a limb hip on a downward one. Rotary and ambulatory locomotion cost no new connector vocabulary at all — which is the strongest available evidence that the three families really are one class.

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

The primitive type is declared **top-level**, in its own file, and not as an inner class of `ColliderProfile`:

```gdscript
class_name ColliderPrimitiveDef        # src/core/data/collider_primitive_def.gd
extends Resource

enum PrimitiveKind { BOX = 0, CYLINDER = 1, CAPSULE = 2, SPHERE = 3 }

@export var kind: PrimitiveKind = PrimitiveKind.BOX
@export var half_extents_m: Vector3 = Vector3(0.125, 0.125, 0.125)  # BOX
@export var radius_m: float = 0.125                                  # CYL/CAP/SPH
@export var height_m: float = 0.25                                   # CYL/CAP
@export var local_offset_m: Vector3 = Vector3.ZERO
@export var local_basis_euler_deg: Vector3 = Vector3.ZERO
```

```gdscript
class_name ColliderProfile             # src/core/data/collider_profile.gd
extends Resource

@export var primitives: Array[ColliderPrimitiveDef] = []
## Hard ceiling. The validator rejects any profile exceeding this.
const MAX_PRIMITIVES_PER_PART: int = 3
```

> **Why top-level, and not an inner class.** This document originally specified
> `PrimitiveDef` as an inner class of `ColliderProfile`. Godot 4 cannot serialise
> an inner-class `Resource` into a `.tres`: saving writes the element script as
> an empty `[sub_resource type="GDScript"]` carrying no source, and on load every
> element fails typed-array validation and is silently dropped. A profile saved
> with three primitives loads back with **zero**, with no error reported to the
> caller.
>
> Because Invariant I-1 makes `ColliderProfile` the only source of Assembly
> collision geometry, that would ship every part in the game with an empty
> collider set and no hit registration at all — from what reads as a
> code-organisation preference. The type is therefore top-level, and
> `tests/unit/test_collider_profile_serialisation.gd` round-trips a populated
> profile through `.tres` on every CI run so the arrangement cannot regress.
>
> `ProxyPrimitiveDef` (`docs/EXTENSION_PIPELINE.md` §2) mirrors these fields and
> is a separate type for a different reason: a proxy visual is generated from the
> collider once, at promotion time, and the two evolve independently thereafter.
> Sharing one type would let an art edit move a hitbox.

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

## --- Family payload; exactly one non-null, matching `kind` -------------
@export var rotor_profile: RotorProfile = null   # ROTOR_DISC only
@export var limb_profile: LimbProfile = null     # AMBULATORY_LIMB only
```

`traction_coefficient` is the *nominal* value. `DYNAMIC_MASS_PHYSICS.md` §6 and `COMPONENT_HEALTH_DAMAGE.md` §7 define the degradation multipliers applied on top of it.

**Amendment — the family payload.** `MotiveAssemblyProfile` originally held one flat field set describing a ground contact. Rotary and ambulatory Motive Assemblies need parameters a wheel has no meaning for (disc radius, collective range, duty factor, step length) and would leave a wheel carrying a dozen fields it never reads. Rather than widen the profile until every kind ignores two thirds of it, the kind-specific parameters live in a sub-resource selected by `kind`, mirroring exactly the way `PartDefinition` selects a class payload — the same rule, the same validator shape, and the same failure mode when it is violated.

The fields that *survive* on the profile itself are the ones all three families genuinely share, and it is worth naming why each does:

| Field | Ground | Rotary | Ambulatory |
|---|---|---|---|
| `rated_load_kg` | Suspension retune datum (§6.4 of doc 05) | Disc loading at which lift is quoted | Load the stance spring holds without bottoming |
| `contact_radius_m` | Rolling radius | *Hub* radius, not disc radius — the collider's, not the aerodynamics' | Foot contact sphere radius |
| `traction_coefficient` | Tyre μ | Unused; validator requires `0.0` | Foot–ground μ |
| `suspension_*` | Spring, damper, travel | Unused; validator requires `0.0` | Unused — the stance spring is on `LimbProfile`, because a leg's compliance is commanded, not passive |
| `rolling_resistance` | Rolling loss | Unused | Unused |
| `driven` | Receives drive torque | Receives shaft power | Receives gait command |

`contact_radius_m` keeping its meaning across all three is deliberate: `GRID_SNAPPING_LOGIC.md` §7.5's ground-clearance check and the probe geometry of doc 05 §6.1 both read it, and neither should have to know which family it is looking at.

### 7.2.1 `RotorProfile`

```gdscript
class_name RotorProfile
extends Resource

## ===== DISC GEOMETRY ===================================================
@export var disc_radius_m: float = 2.60
@export var blade_count: int = 4
## +1 or -1. Paired contra-rotating discs cancel reaction torque.
@export var spin_sign: int = 1

## ===== SPOOL ===========================================================
@export var nominal_rad_s: float = 85.0
## Time constant of the first-order approach to commanded angular rate.
@export var spool_up_tau_s: float = 2.40
@export var spool_down_tau_s: float = 4.80

## ===== LIFT ============================================================
## Thrust coefficient at maximum collective: T = C_T · ρ · A · (Ω R)².
@export var thrust_coefficient: float = 0.020
## Shaft torque coefficient: Q = C_Q · ρ · A · (Ω R)² · R.
@export var torque_coefficient: float = 0.0024
@export var collective_limit_deg: Vector2 = Vector2(-4.0, 14.0)
@export var collective_rate_deg_s: float = 22.0

## ===== TILT ============================================================
## Maximum cyclic deflection of the thrust vector from the disc axis.
@export var cyclic_limit_deg: float = 14.0
@export var cyclic_rate_deg_s: float = 48.0
## Yaw torque available from differential collective across a coaxial pair, or
## from a tail station on a single-rotor build.
@export var yaw_authority_nm: float = 9600.0

## ===== REGIME ==========================================================
## Fraction of reaction torque transmitted to the chassis. 0.0 for a coaxial
## disc whose counter-rotating half cancels it; 1.0 for a lone main rotor.
@export var torque_reaction_ratio: float = 0.0
## Height above ground, in disc radii, below which ground effect adds thrust.
@export var ground_effect_radii: float = 1.0
## Peak ground-effect thrust gain at zero height.
@export var ground_effect_gain: float = 0.24
## Airspeed at which translational lift reaches its full value.
@export var translational_lift_mps: float = 14.0
@export var translational_lift_gain: float = 0.18
## Descent rate at which the disc enters its own downwash and loses thrust.
@export var vortex_ring_descent_mps: float = 6.0
@export var vortex_ring_loss: float = 0.32
```

Every one of these is consumed by `DYNAMIC_MASS_PHYSICS.md` §12, which owns their semantics and their formulas; this section owns only their existence and their units.

### 7.2.2 `LimbProfile`

```gdscript
class_name LimbProfile
extends Resource

## ===== GEOMETRY ========================================================
## Hip-to-foot distance at full extension.
@export var leg_length_m: float = 1.90
## Hip position relative to the part's pivot cell centre.
@export var hip_offset_m: Vector3 = Vector3(0.0, 0.75, 0.0)
@export var foot_radius_m: float = 0.16
## Height the stance controller holds the hip at, as a fraction of leg_length_m.
@export var stance_height_ratio: float = 0.86

## ===== STANCE ==========================================================
## Virtual-leg spring. Compliance is commanded, not passive: these are the
## gains of a controller, which is why they are here and not on the suspension
## fields of the parent profile.
@export var stance_stiffness_n_m: float = 96000.0
@export var stance_damping_ns_m: float = 12000.0
@export var max_foot_force_n: float = 42000.0

## ===== GAIT ============================================================
## Fraction of the gait cycle spent in stance. 0.60 walks, below 0.50 runs
## with a flight phase.
@export var duty_factor: float = 0.62
@export var nominal_cadence_hz: float = 1.05
@export var max_cadence_hz: float = 2.20
@export var max_step_length_m: float = 1.10
## Peak foot clearance over the swing arc.
@export var step_height_m: float = 0.34
## Raibert velocity-error gain on the foot placement law.
@export var placement_gain_s: float = 0.19
@export var turn_rate_deg_s: float = 45.0
```

### 7.2.3 `TrackProfile`

```gdscript
class_name TrackProfile
extends Resource

## ===== CONTACT PATCH ===================================================
## Length of the ground contact patch along the rolling axis.
@export var patch_length_m: float = 1.90
## Road stations along the patch. Each carries one suspension probe and one
## traction contact, so this multiplies the part's per-tick cost.
@export var road_stations: int = 4
@export var station_load_share: float = 0.25

## ===== DRIVE ===========================================================
@export var sprocket_rad_s: float = 22.0
## 1.0 permits a full counter-rotating pivot; 0.5 permits only a skid turn.
@export var differential_authority: float = 1.0
## Speed at which differential authority reaches zero.
@export var pivot_taper_mps: float = 9.0

## ===== SHEAR ===========================================================
## Torque resisting a slew of the patch, per metre of length per newton of load.
@export var slew_resistance_nm_per_n_m: float = 0.42
## Lateral friction multiplier on top of `traction_coefficient`.
@export var lateral_grip_ratio: float = 1.35
## Fraction of drive force lost to the track's own internal friction.
@export var internal_loss: float = 0.08

const MAX_ROAD_STATIONS: int = 8
```

`station_offsets_m()` derives the stations from `patch_length_m` and `road_stations` rather than accepting a list, evenly spaced and symmetric about the patch centre. An authored asymmetric list would move the part's effective contact centre away from its collider with nothing reporting it — the same class of silent divergence §6.2 exists to prevent between visual and physical geometry.

`differential_authority` and `pivot_taper_mps` together are what make a tracked Assembly feel tracked. At rest, authority is full and the two sides can counter-rotate, so the Assembly pivots on the spot. At `pivot_taper_mps` authority is zero and steering is whatever the lateral friction of the patch allows, which is very little — so a tracked build at speed turns in a long, deliberate arc. Nothing switches; the taper is linear and continuous, and both behaviours are the same expression evaluated at different speeds.

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

## Non-null for KINETIC_MELEE and ENERGY_MELEE, null for every other kind.
@export var melee_profile: MeleeProfile = null
```

### 7.4.1 `MeleeProfile`

A melee Effector Module emits no projectile. It sweeps a volume, and everything the emission fields describe — muzzle velocity, spread, magazine, projectile key — is meaningless for it. Those fields are required by the validator to be zero on a melee module, and the behaviour lives here instead. Semantics are owned by `WEAPON_TARGETING_LOGIC.md` §15.

```gdscript
class_name MeleeProfile
extends Resource

## ===== REACH ===========================================================
## Distance from the hardpoint pivot to the tip of the striking edge.
@export var reach_m: float = 2.40
## Radius of the swept capsule. The edge is a volume, not a line: a zero-radius
## sweep passes between two adjacent parts of a lattice-built Assembly.
@export var edge_radius_m: float = 0.18
## Angular extent of one swing about the hardpoint yaw axis.
@export var swing_arc_deg: float = 150.0
## Sweep samples per swing. Bounds the query cost; see doc 07 §15.3.
@export var swing_samples: int = 6

## ===== TIMING ==========================================================
@export var wind_up_s: float = 0.28
@export var swing_duration_s: float = 0.22
@export var recovery_s: float = 0.46

## ===== EFFECT ==========================================================
## Damage of one strike, split across channels by `channel_mix`.
@export var strike_damage: float = 640.0
## Fractions summing to 1.0, indexed by DamageChannel.
@export var channel_mix: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0])
## Impulse delivered to the struck Assembly, along the edge's travel direction.
@export var strike_impulse_ns: float = 2800.0
## Fraction of that impulse applied back to the wielder.
@export var reaction_ratio: float = 0.35
## Parts one swing may strike before it stops. Bounds the damage a single
## sweep can submit; see CLAUDE.md §6 I-12.
@export var max_targets_per_swing: int = 3

## ===== REGIME ==========================================================
## Closing speed below which a strike does nothing. A ram spike needs the
## Assembly to be moving; a powered edge does not, and authors 0.0.
@export var min_closing_speed_mps: float = 0.0
## True for a continuously energised edge that damages on contact for as long
## as it is held against a target, rather than on a discrete swing.
@export var sustained: bool = false
## Damage per second while sustained contact is maintained.
@export var sustained_damage_s: float = 0.0
## Power drawn while the edge is energised, on top of `power_draw_pu`.
@export var energised_draw_pu: float = 0.0
```

`channel_mix` is what separates the two melee kinds without a second code path. A `KINETIC_MELEE` ram spike authors `[0.15, 0, 0.85, 0, 0]` — overwhelmingly `IMPACT`. An `ENERGY_MELEE` edge authors `[0.10, 0, 0.15, 0.75, 0]` — overwhelmingly `THERMAL`, which is what makes it cut through a `str.panel.*` (thermal resistance 0.05) and struggle against a `str.panel.composite` (0.38) and an `eff.beam.*` mount (0.44). The kind enum selects the presentation and the power model; the channel mix does the balance work.

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
| `str.hub.axle_station.t2` | 2×2×2 | 29 | 340 | 16 | 2400 | `OPAQUE_SOLID` |

`str.hub.axle_station.t2` is the `AXLE` station of §4.2 and the only part in the shipping set that carries `AXLE` nodes. Its `AXLE` faces are ±X, restricted by `accepts_classes` to `MOTIVE_ASSEMBLY`; ±Y and ±Z are `FACE_NEUTRAL` so it can be built into a chassis from four sides. The load capacity is high for its mass because everything an Assembly's locomotion does to it passes through this one joint: a 1180 kg-rated Motive Assembly under a 2.4 g manoeuvre loads its station harder than any panel in the table ever sees.

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
| `mot.rotor.coaxial_mid.t3` | `ROTOR_DISC` | 4×6×4 | 265 | 690 | 2600 | 0.00 | 0 | 0 | 0 |
| `mot.rotor.coaxial_heavy.t4` | `ROTOR_DISC` | 5×7×5 | 410 | 1010 | 4400 | 0.00 | 0 | 0 | 0 |
| `mot.rotor.main_single.t3` | `ROTOR_DISC` | 4×6×4 | 210 | 620 | 2200 | 0.00 | 0 | 0 | 0 |
| `mot.limb.strider.t3` | `AMBULATORY_LIMB` | 3×7×3 | 132 | 500 | 980 | 1.18 | 42 | 68000 | 8600 |

The four zero columns on the rotary rows are not omissions. A `ROTOR_DISC` has no traction coefficient, no steer angle, and no suspension, and the validator requires those four fields to be exactly zero on it (§14 rule 19) rather than leaving a plausible-looking value that no code reads. Its actual parameters are in `RotorProfile`, tabulated separately below because they share no columns with a ground contact:

| `part_key` | Disc R (m) | Blades | Ω (rad/s) | C_T | C_Q | Collective (°) | Cyclic (°) | Reaction | Yaw (N·m) | Draw (PU) |
|---|---|---|---|---|---|---|---|---|---|---|
| `mot.rotor.coaxial_mid.t3` | 2.60 | 4 | 85.0 | 0.020 | 0.0024 | −4 … 14 | 14 | 0.00 | 9600 | 150 |
| `mot.rotor.coaxial_heavy.t4` | 3.40 | 6 | 65.0 | 0.020 | 0.0024 | −4 … 15 | 12 | 0.00 | 15400 | 196 |
| `mot.rotor.main_single.t3` | 3.10 | 3 | 55.0 | 0.020 | 0.0024 | −5 … 15 | 18 | 1.00 | 0 | 98 |

**These numbers are derived, not chosen, and the derivation is a validator rule.** `DYNAMIC_MASS_PHYSICS.md` §12.2 computes maximum thrust as `T = C_T · ρ · A · (Ω R)²` with `A = π R²`. Every row above is solved so that `T` at full collective equals the row's `rated_load_kg × g` to within 1%, which is what §14 rule 19 checks. A rotor that cannot lift its own rating is a data error that would present as an Assembly which simply refuses to leave the ground, with nothing in the logs, so it is checked rather than trusted.

Working the mid disc through: `A = π(2.6)² = 21.24 m²`, tip speed `ΩR = 85 × 2.6 = 221 m/s`, so `T = 0.020 × 1.225 × 21.24 × 221² = 25 410 N`, against `2600 × 9.81 = 25 506 N`. The tip speed of 221 m/s is not a coincidence either — it is where a real rotor lives, below the transonic blade tip, and all three rows share it. They also share `C_T`, which means they share a disc loading of `1200 N/m²`; that is about 2.7× a real utility helicopter and is the one deliberate departure from reality in the family, bought so that a rotor fits inside a 12 m Build Lattice.

`C_Q = 0.0024` follows from `C_T` rather than being independent: momentum theory gives induced velocity `v_i = sqrt(T / 2ρA) = 22.1 m/s`, so ideal `C_Q = C_T · v_i / (ΩR) = 0.0020`, and the shipping value carries 20% on top for profile power. Because the three rows share a disc loading they share `v_i`, and therefore share `C_Q` exactly.

The `Draw (PU)` column is `shaft_power / ROTOR_W_PER_PU` at full collective, with the constant owned by doc 05 §12.5. It is stored on the definition's `power_draw_pu` as the **full-collective** figure so that the garage's power budget is conservative: an Assembly that balances on paper can always hover.

`mot.rotor.main_single.t3` is the deliberate hard case: `torque_reaction_ratio = 1.00` and `yaw_authority_nm = 0`, so a build carrying one of them and nothing else spins under its own reaction torque and cannot stop. It is flyable only in a pair with opposed `spin_sign`, or with a second station mounted to produce anti-torque. That is real rotorcraft engineering surfaced as a build constraint, and the garage reports it: an Assembly whose net `Σ torque_reaction_ratio · spin_sign` is non-zero and whose `Σ yaw_authority_nm` cannot cover it fails the stability line in the stat panel. A coaxial disc is the forgiving option and costs mass for the privilege — 265 kg against 210 kg at the same tier.

Tracked rows carry the ground columns, and their `Steer (°)` of zero is required rather than incidental (§14 rule 22): a track that steered by angling its hub would be a wheel. Their remaining parameters:

| `part_key` | Patch (m) | Stations | Sprocket (rad/s) | Diff. auth. | Pivot taper (m/s) | Slew resist. | Lateral grip | Internal loss |
|---|---|---|---|---|---|---|---|---|
| `mot.tracked.short_bogie.t2` | 1.90 | 4 | 22.0 | 1.00 | 9.0 | 0.42 | 1.35 | 0.08 |
| `mot.tracked.long_bogie.t3` | 2.90 | 6 | 19.0 | 0.85 | 7.0 | 0.51 | 1.48 | 0.10 |

The long bogie is the deliberate trade and reads directly off the row: more patch and more stations buy it grip (`1.48` lateral against `1.35`) and the ability to bridge a wider gap, and cost it agility (`0.85` authority against `1.00`, tapering to nothing by 7 m/s instead of 9) and efficiency (`0.10` internal loss against `0.08`). A short-bogie Assembly pivots and darts; a long-bogie one holds a line and does not care what it drives over. Both are `TRACKED_SEGMENT` and neither needs a line of code the other does not.

`slew_resistance_nm_per_n_m` scales with patch length *and* with normal load, so the resistance to turning is `k · L · N`. That product is the whole reason a heavy tracked Assembly is committed once it is moving: doubling the armour doubles the torque required to change heading, and there is no steering input that can overcome it. This is the failure mode a `bastion` build is supposed to have.

Ambulatory rows carry the ground columns because a foot genuinely has a friction coefficient and a rated load. `Susp. k` and `Susp. c` on a limb row are the **stance** stiffness and damping and are stored on `LimbProfile`, not on the suspension fields of the parent profile — the parent's suspension fields are zero on a limb, for the reason §7.2 gives. The remaining gait parameters:

| `part_key` | Leg (m) | Duty | Cadence (Hz) | Max step (m) | Step height (m) | Foot force (N) | Turn (°/s) |
|---|---|---|---|---|---|---|---|
| `mot.limb.strider.t3` | 1.62 | 0.64 | 1.15 | 0.92 | 0.29 | 30000 | 42 |
| `mot.limb.strider.t4` | 1.90 | 0.62 | 1.05 | 1.10 | 0.34 | 42000 | 45 |

A `duty_factor` above `0.5` means more than half the gait cycle is spent in stance, so a two-limbed Assembly always has at least one foot planted and never leaves the ground. This is what makes a biped tractable under Invariant I-3: the chassis is one rigid body held up by whichever feet are currently in stance, and there is never a tick with no support. Duty factors below `0.5` describe a run with a flight phase and are outside the shipping set — not because the solver cannot express one, but because a flight phase makes support intermittent and the tuning is a separate piece of work.

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
| `eff.melee.beam_edge.t3` | `ENERGY_MELEE` | 3×3×6 | 68 | 290 | 98 | 0.00 | 0 | 0 | 8.0 |
| `eff.melee.beam_edge.t4` | `ENERGY_MELEE` | 3×3×8 | 96 | 420 | 145 | 0.00 | 0 | 0 | 11.0 |

The `Cycle`, `Muzzle`, and `Recoil` columns are zero on every melee row and are required to be (§14 rule 20). Melee timing is `wind_up_s + swing_duration_s + recovery_s` on `MeleeProfile`, and there is no muzzle and no projectile. `Draw (PU)` is non-zero on the powered edges because an energised edge draws continuously, which is the trade that distinguishes it from a spike: a ram spike costs no power and needs the Assembly to be moving, a beam edge costs 145 PU of the budget and cuts from a standstill.

| `part_key` | Reach (m) | Edge R (m) | Arc (°) | Wind-up / swing / recovery (s) | Strike | Channel mix | Impulse (N·s) | Sustained |
|---|---|---|---|---|---|---|---|---|
| `eff.melee.ram_spike.t2` | 1.30 | 0.22 | 0 | 0.00 / 0.10 / 0.30 | 480 | `[0.15, 0, 0.85, 0, 0]` | 5200 | no |
| `eff.melee.rotor_blade.t4` | 1.80 | 0.30 | 360 | 0.00 / 0.16 / 0.00 | 310 | `[0.40, 0, 0.60, 0, 0]` | 2400 | no |
| `eff.melee.beam_edge.t3` | 1.90 | 0.15 | 140 | 0.24 / 0.20 / 0.50 | 470 | `[0.10, 0, 0.15, 0.75, 0]` | 1900 | yes, 260/s |
| `eff.melee.beam_edge.t4` | 2.40 | 0.18 | 150 | 0.28 / 0.22 / 0.46 | 640 | `[0.10, 0, 0.15, 0.75, 0]` | 2800 | yes, 340/s |

`eff.melee.ram_spike.t2` authors `swing_arc_deg = 0` and `min_closing_speed_mps = 4.0`: it does not swing at all, it is a fixed edge that damages what the Assembly drives into, which is exactly what a ram is. `eff.melee.rotor_blade.t4` authors a full 360° arc with no wind-up and no recovery — a continuously spinning edge, modelled as a swing that never stops. Both fall out of the same `MeleeProfile` fields with no special case in the solver, which is the test of whether the schema is the right shape.

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
| `str.hub.*` | 0.26 | 0.10 | 0.44 | 0.10 | 0.06 |
| `mot.wheeled.*` | 0.08 | 0.12 | 0.30 | 0.02 | 0.00 |
| `mot.tracked.*` | 0.24 | 0.18 | 0.40 | 0.08 | 0.04 |
| `mot.limb.*` | 0.16 | 0.14 | 0.26 | 0.06 | 0.02 |
| `mot.repulsor.*` | 0.06 | 0.30 | 0.10 | 0.24 | 0.00 |
| `mot.rotor.*` | 0.04 | 0.08 | 0.06 | 0.10 | 0.00 |
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
17. A Motive Assembly's family payload does not match its `kind`: `ROTOR_DISC` without a `rotor_profile`, `AMBULATORY_LIMB` without a `limb_profile`, `TRACKED_SEGMENT` without a `track_profile`, any other kind with any of the three non-null, or more than one non-null at once.
18. A part carries an `AXLE` attachment node and is neither a `MOTIVE_ASSEMBLY` nor a `STRUCTURAL_COMPONENT` whose `AXLE` nodes restrict `accepts_classes` to `MOTIVE_ASSEMBLY` (§4.2). **Additionally**, a `MOTIVE_ASSEMBLY`'s `AXLE` node must not have a non-empty `accepts_classes` that excludes `STRUCTURAL_COMPONENT`. `PlacementValidator._check_mating` tests `accepts_class` in *both* directions, so a drive face carrying the station's own restriction refuses the station — and the part becomes unmountable on anything in the game. All four `mot.*` rows of §10.3 shipped that way and no rule, test, or conformance check noticed, because the fault is invisible until something attempts a placement.
19. A `ROTOR_DISC` Motive Assembly has a non-zero `traction_coefficient`, `rolling_resistance`, `max_steer_angle_deg`, or any non-zero `suspension_*` field; or `rotor_profile.disc_radius_m <= 0.0`, `blade_count < 2`, `spin_sign` not in `{-1, +1}`, `nominal_rad_s <= 0.0`, `collective_limit_deg.x > collective_limit_deg.y`, or `torque_reaction_ratio` outside `[0.0, 1.0]`. Additionally, maximum thrust `C_T · ρ · π R² · (Ω R)²` must equal `rated_load_kg · GRAVITY_MPS2` within 1% — a rotor that cannot lift its own rating presents as an Assembly that silently refuses to fly.
20. A melee Effector Module (`KINETIC_MELEE` or `ENERGY_MELEE`) has a null `melee_profile`, or a non-zero `muzzle_velocity_mps`, `cycle_time_s`, `recoil_impulse_ns`, `magazine_rounds`, or `spread_bloom_deg`; or a non-melee kind has a non-null `melee_profile`. Additionally `channel_mix` must have length `DAMAGE_CHANNEL_COUNT` and sum to `1.0` within `0.001`, `max_targets_per_swing` must be in `[1, 8]`, `swing_samples` in `[2, 16]`, and `reaction_ratio` in `[0.0, 1.0]`.
21. An `AMBULATORY_LIMB` Motive Assembly has a non-zero `suspension_*` field; or `limb_profile.duty_factor` outside `(0.0, 1.0)`, `leg_length_m <= 0.0`, `stance_height_ratio` outside `(0.0, 1.0]`, `max_cadence_hz < nominal_cadence_hz`, or `max_step_length_m > 2 · leg_length_m` — a step longer than twice the leg cannot be taken with a foot on the ground at either end of it.
22. A `TRACKED_SEGMENT` Motive Assembly has a non-zero `max_steer_angle_deg` — a track steers by differential drive, and one that angled its hub would be a wheel; or `track_profile.road_stations` outside `[1, MAX_ROAD_STATIONS]`, `patch_length_m <= 0.0`, `differential_authority` outside `[0.0, 1.0]`, `internal_loss` outside `[0.0, 1.0)`, or `lateral_grip_ratio <= 0.0`.

The validator emits `res://.build/part_registry_report.md` summarising totals per class, mass histograms, integrity-per-kilogram outliers, and every exception note. This report is a required review artefact for any balance change.

---

## 15. Interfaces Consumed By Other Documents

| Consumer Document | Fields Consumed |
|---|---|
| `GRID_SNAPPING_LOGIC.md` | `occupancy_cells`, `occupancy_bitset`, `attachment_nodes`, `bounds_*` |
| `PART_FUSION_SHADER.md` | `fusion_profile`, `occupancy_cells`, `visual_profile` |
| `DEPENDENCY_TREE_GRAPH.md` | `attachment_nodes.joint_strength_n`, `can_bear_load`, `mass_kg`, `load_capacity_kg` |
| `DYNAMIC_MASS_PHYSICS.md` | `mass_kg`, `com_offset_m`, `inertia_box_half_extents_m`, `motive_profile` and its `rotor_profile`/`limb_profile` payloads, `control_profile`, `AIR_DENSITY_KG_M3` |
| `AUTO_ASSEMBLE_ALGORITHM.md` | Every field; the solver is a constraint search over the full schema |
| `WEAPON_TARGETING_LOGIC.md` | `effector_profile` and its `melee_profile` payload, `power_draw_pu`, `heat_generation_hu_s` |
| `COMPONENT_HEALTH_DAMAGE.md` | `integrity_max`, `resistance`, `armour_rating`, `occlusion`, band constants |
| `TERRAIN_CRATER_DEFORMER.md` | Blast fields on `power_profile` and projectile definitions |
| `PROCEDURAL_STRUCTURE_SLICING.md` | `collider_profile` conventions (shared with Static Volumes) |
| `RESPONSIVE_GARAGE_UI.md` | `display_name_key`, `tier`, `build_cost`, `mount_weight`, all stat fields |
| `HEADLESS_NETWORK_SYNC.md` | `part_def_id`, quantisation rules, `manifest_hash()` |
| `EXTENSION_PIPELINE.md` | `visual_profile`, `collider_profile`, `fusion_profile` |
