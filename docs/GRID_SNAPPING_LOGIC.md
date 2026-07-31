# GRID_SNAPPING_LOGIC.md

**Project Syndicate — System Architecture Specification, Document 02 of 13**
**Subsystem:** Build Lattice, Vector Snapping, Multi-Axial Orientation, Placement Safety
**Status:** Normative.

---

## 1. Purpose and Scope

This document defines how a part is converted from a floating cursor position into a legal, committed occupancy in the Build Lattice. It covers:

- The three coordinate frames and the exact conversions between them.
- The 24-element discrete orientation group and its integer basis representation.
- The occupancy structure and O(1) overlap testing.
- Attachment-node mating rules.
- The complete pre-commit safety check chain.
- Removal, re-parenting, and the undo model.

Snapping is **pure integer arithmetic**. No placement decision is ever made from a float comparison. Floats appear only when converting a mouse ray into a candidate cell, and that conversion is immediately quantised. This is the single most important property of the system: it guarantees that a blueprint placed on one machine reconstructs bit-identically on every other machine and on the headless server, which is a precondition for the network model in `HEADLESS_NETWORK_SYNC.md`.

---

## 2. Coordinate Frames

| Frame | Symbol | Units | Origin | Description |
|---|---|---|---|---|
| Part-local cell | `c_p` | cells (`Vector3i`) | Part pivot cell | Authored occupancy from `PartDefinition.occupancy_cells` |
| Lattice cell | `c_l` | cells (`Vector3i`) | `LATTICE_ORIGIN_CELL` | Assembly-wide integer build space |
| Assembly-local metric | `p_a` | metres (`Vector3`) | Core Module pivot centre | Feeds Godot node transforms and physics |

Axis convention matches Godot: **+X right, +Y up, −Z forward.** The lattice `Z` axis increases toward the rear of the Assembly. `LATTICE_ORIGIN_CELL = Vector3i(24, 4, 24)` places the origin near the lattice centre with extra headroom above and clearance below for Motive Assemblies.

### 2.1 Conversions

```gdscript
class_name LatticeMath
extends RefCounted

const U := SyndicateConstants.LATTICE_UNIT_M
const ORIGIN := SyndicateConstants.LATTICE_ORIGIN_CELL
const EXTENT := SyndicateConstants.LATTICE_EXTENT

## Centre of a lattice cell in assembly-local metres.
static func cell_to_local(cell: Vector3i) -> Vector3:
    return Vector3(
        (float(cell.x - ORIGIN.x) + 0.5) * U,
        (float(cell.y - ORIGIN.y) + 0.5) * U,
        (float(cell.z - ORIGIN.z) + 0.5) * U)

## Quantise an assembly-local metric point to the cell containing it.
static func local_to_cell(p: Vector3) -> Vector3i:
    return Vector3i(
        int(floor(p.x / U)) + ORIGIN.x,
        int(floor(p.y / U)) + ORIGIN.y,
        int(floor(p.z / U)) + ORIGIN.z)

static func in_bounds(cell: Vector3i) -> bool:
    return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 \
        and cell.x < EXTENT.x and cell.y < EXTENT.y and cell.z < EXTENT.z

## Dense linear index. Guaranteed collision-free within EXTENT.
static func cell_index(cell: Vector3i) -> int:
    return cell.x + cell.y * EXTENT.x + cell.z * EXTENT.x * EXTENT.y

static func index_to_cell(idx: int) -> Vector3i:
    var x := idx % EXTENT.x
    var y := (idx / EXTENT.x) % EXTENT.y
    var z := idx / (EXTENT.x * EXTENT.y)
    return Vector3i(x, y, z)
```

`cell_index` maps the full `48 × 32 × 48` lattice onto `[0, 73728)`, which fits comfortably in a flat `PackedInt32Array`. There is no hashing and no dictionary in the hot placement path.

### 2.2 Why 0.25 m

The lattice unit is `0.25 m`. This is a deliberate compromise:

- Fine enough that Structural Components can approximate curved silhouettes at a `1.0 m` panel size (4 cells) without visible stair-stepping once the fusion shader is applied.
- Coarse enough that the dense occupancy array stays at 73 728 entries — small enough to memset in microseconds and to hold entirely in L2 cache during a full-Assembly validation sweep.
- An exact binary fraction, so `cell_to_local` and `local_to_cell` round-trip without accumulating floating-point error at any lattice coordinate.

---

## 3. Occupancy Structure

```gdscript
class_name LatticeOccupancy
extends RefCounted

## Dense array of slot ids. INVALID_SLOT means empty.
var _cells: PackedByteArray = PackedByteArray()
## Per-slot cell lists, for O(size) removal without scanning the lattice.
var _slot_cells: Dictionary = {}          # int slot -> PackedInt32Array
## Count of occupied cells, maintained incrementally.
var occupied_count: int = 0

func _init() -> void:
    var total := SyndicateConstants.LATTICE_EXTENT.x \
               * SyndicateConstants.LATTICE_EXTENT.y \
               * SyndicateConstants.LATTICE_EXTENT.z
    _cells.resize(total)
    clear()

func clear() -> void:
    for i in _cells.size():
        _cells[i] = SyndicateConstants.INVALID_SLOT
    _slot_cells.clear()
    occupied_count = 0

func slot_at(cell: Vector3i) -> int:
    if not LatticeMath.in_bounds(cell):
        return SyndicateConstants.INVALID_SLOT
    return _cells[LatticeMath.cell_index(cell)]

func is_free(cell: Vector3i) -> bool:
    return slot_at(cell) == SyndicateConstants.INVALID_SLOT

func write_slot(slot: int, cells: PackedVector3Array) -> void:
    var indices := PackedInt32Array()
    indices.resize(cells.size())
    for i in cells.size():
        var c := Vector3i(cells[i])
        var idx := LatticeMath.cell_index(c)
        _cells[idx] = slot
        indices[i] = idx
    _slot_cells[slot] = indices
    occupied_count += cells.size()

func erase_slot(slot: int) -> void:
    var indices: PackedInt32Array = _slot_cells.get(slot, PackedInt32Array())
    for idx in indices:
        _cells[idx] = SyndicateConstants.INVALID_SLOT
    occupied_count -= indices.size()
    _slot_cells.erase(slot)
```

`_cells` is `PackedByteArray` because `MAX_PARTS_PER_ASSEMBLY` is 255 and `INVALID_SLOT` is 255 — one byte per cell, 73 728 bytes total. A full clear is a single tight loop; a full-Assembly rebuild costs well under 0.1 ms and is only performed on blueprint load, never during interactive editing.

---

## 4. The 24-Element Orientation Group

### 4.1 Definition

An Assembly part may be oriented in any of the 24 rotations of the proper octahedral group — the rotations that map an axis-aligned cube onto itself. Mirroring is excluded: mirrored parts would require mirrored collider primitives and mirrored attachment polarities, which doubles the validation surface for no gameplay benefit. Asymmetric parts that need a mirrored form ship as an explicit second `PartDefinition`.

Orientations are indexed `0..23`. The index is stored in `PartInstanceState.orientation_index` and in the blueprint format. **The index-to-basis mapping is frozen** — it appears in saved data. It is generated deterministically at startup by the following construction, which is defined as normative rather than as a lookup table so that the ordering is reproducible and auditable.

### 4.2 Construction

Index decomposes as `orientation_index = up_facing * 4 + roll_quarter`, where:

- `up_facing ∈ [0, 6)` selects which part-local axis becomes the world `+Y`, in the fixed order `[+Y, −Y, +X, −X, +Z, −Z]`.
- `roll_quarter ∈ [0, 4)` selects the number of 90° rotations about the resulting up axis.

```gdscript
class_name OrientationTable
extends RefCounted

const COUNT := SyndicateConstants.ORIENTATION_COUNT

static var _bases: Array[Basis] = []
static var _inverse_index: PackedInt32Array = PackedInt32Array()

## Order is normative and MUST NOT change: it is serialised in blueprints.
const UP_AXES: Array[Vector3i] = [
    Vector3i(0, 1, 0),   # 0: identity up
    Vector3i(0, -1, 0),  # 1: inverted
    Vector3i(1, 0, 0),   # 2: rolled right
    Vector3i(-1, 0, 0),  # 3: rolled left
    Vector3i(0, 0, 1),   # 4: pitched back
    Vector3i(0, 0, -1),  # 5: pitched forward
]

static func _static_init() -> void:
    _bases.resize(COUNT)
    for up_facing in 6:
        var align := _basis_aligning_y_to(UP_AXES[up_facing])
        for roll in 4:
            var spin := Basis(Vector3(0, 1, 0), float(roll) * PI * 0.5)
            var b := (spin * align).orthonormalized()
            _bases[up_facing * 4 + roll] = _snap_basis_to_integers(b)
    _build_inverse_table()

## Shortest rotation carrying part-local +Y onto the requested axis.
static func _basis_aligning_y_to(axis: Vector3i) -> Basis:
    var a := Vector3(axis)
    if a.is_equal_approx(Vector3(0, 1, 0)):
        return Basis()
    if a.is_equal_approx(Vector3(0, -1, 0)):
        return Basis(Vector3(1, 0, 0), PI)
    var rot_axis := Vector3(0, 1, 0).cross(a).normalized()
    return Basis(rot_axis, PI * 0.5)

## Rounds every element to the nearest integer, eliminating trig residue.
static func _snap_basis_to_integers(b: Basis) -> Basis:
    var out := Basis()
    for col in 3:
        var v := b.get_column(col)
        out.set_column(col, Vector3(roundf(v.x), roundf(v.y), roundf(v.z)))
    return out

static func basis_for(index: int) -> Basis:
    return _bases[index & 31 if index < COUNT else 0]

## Integer rotation of a cell offset. No floating point involved.
static func rotate_cell(index: int, c: Vector3i) -> Vector3i:
    var b := _bases[index]
    var x := b.x  # column 0
    var y := b.y  # column 1
    var z := b.z  # column 2
    return Vector3i(
        int(x.x) * c.x + int(y.x) * c.y + int(z.x) * c.z,
        int(x.y) * c.x + int(y.y) * c.y + int(z.y) * c.z,
        int(x.z) * c.x + int(y.z) * c.y + int(z.z) * c.z)

static func inverse_of(index: int) -> int:
    return _inverse_index[index]

static func _build_inverse_table() -> void:
    _inverse_index.resize(COUNT)
    for i in COUNT:
        for j in COUNT:
            if _compose_index(i, j) == 0:
                _inverse_index[i] = j
                break

static func _compose_index(a: int, b: int) -> int:
    var probe := Vector3i(1, 2, 3)   # distinct-magnitude probe uniquely identifies a rotation
    var target := rotate_cell(a, rotate_cell(b, probe))
    for k in COUNT:
        if rotate_cell(k, probe) == target:
            return k
    return 0
```

The probe vector `(1, 2, 3)` has three distinct absolute components, so no two distinct elements of the octahedral group map it to the same result. This makes `_compose_index` an exact identification, not an approximation.

### 4.3 Rotation Input Model

The garage exposes three rotation actions, each stepping 90° about a world axis relative to the current orientation:

| Action | Effect |
|---|---|
| `build_rotate_yaw` | Compose with a 90° rotation about world `+Y` |
| `build_rotate_pitch` | Compose with a 90° rotation about world `+X` |
| `build_rotate_roll` | Compose with a 90° rotation about world `−Z` |

Each is implemented by table composition, never by accumulating Euler angles:

```gdscript
func apply_rotation_step(current_index: int, step: StringName) -> int:
    var step_index := _STEP_INDEX[step]   # precomputed orientation index of the 90° step
    return OrientationTable.compose(step_index, current_index)
```

Because composition is table-driven, the orientation state is a small integer that can never drift, never accumulate gimbal error, and never require re-normalisation. This is a direct answer to the legacy-engine failure mode where rotating a part 40 times produced a basis with visible skew.

### 4.4 Attachment Node Rotation

An attachment node's face normal rotates with the part:

```gdscript
static func rotate_face(index: int, face: Vector3i) -> Vector3i:
    return rotate_cell(index, face)
```

Since `face` is always an axis unit vector and the basis is integral, the result is always an axis unit vector. No normalisation is required.

---

## 5. Footprint Resolution

Given a `PartDefinition`, an `origin_cell`, and an `orientation_index`, the occupied lattice cells are:

```
c_l(i) = origin_cell + R(orientation_index) · c_p(i)
```

```gdscript
class_name FootprintSolver
extends RefCounted

static func resolve(def: PartDefinition, origin_cell: Vector3i,
                    orientation_index: int, out: PackedVector3Array) -> void:
    out.resize(def.occupancy_cells.size())
    for i in def.occupancy_cells.size():
        var lc := Vector3i(def.occupancy_cells[i])
        out[i] = Vector3(origin_cell + OrientationTable.rotate_cell(orientation_index, lc))

static func resolve_nodes(def: PartDefinition, origin_cell: Vector3i,
                          orientation_index: int) -> Array[ResolvedNode]:
    var result: Array[ResolvedNode] = []
    for node in def.attachment_nodes:
        var rn := ResolvedNode.new()
        rn.source = node
        rn.cell = origin_cell + OrientationTable.rotate_cell(orientation_index, node.cell)
        rn.face = OrientationTable.rotate_face(orientation_index, node.face_normal)
        result.push_back(rn)
    return result
```

`out` is passed in and reused across frames by the ghost-preview system, so interactive placement performs zero heap allocation per frame.

---

## 6. Cursor-to-Cell Resolution

Converting the player's pointer into a placement candidate proceeds in four stages. It is the only place in the system where floating point influences a lattice decision, and its output is quantised before anything else consumes it.

### 6.1 Stage 1 — Ray Construction

```gdscript
func _build_pick_ray(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
    return {
        "origin": camera.project_ray_origin(screen_pos),
        "direction": camera.project_ray_normal(screen_pos),
    }
```

### 6.2 Stage 2 — Surface Hit

The ray is tested against a dedicated set of **build proxy colliders** on collision layer `LAYER_BUILD_GHOST` (layer 8). Each committed part contributes one `BoxShape3D` per occupied cell region derived from its `ColliderProfile`, but these proxies exist only while the garage scene is active and are on a layer that no gameplay system queries.

```gdscript
func _query_surface(space: PhysicsDirectSpaceState3D, ray: Dictionary) -> Dictionary:
    var params := PhysicsRayQueryParameters3D.create(
        ray.origin, ray.origin + ray.direction * PICK_DISTANCE_M)
    params.collision_mask = CollisionLayers.MASK_BUILD_GHOST | CollisionLayers.MASK_BUILD_FLOOR
    params.collide_with_areas = false
    return space.intersect_ray(params)
```

If nothing is hit, the candidate falls back to the intersection of the ray with the build floor plane `y = 0` in assembly-local space, so a part can always be placed on the ground plane of an empty lattice.

### 6.3 Stage 3 — Face Extraction and Anchor Cell

The hit provides a position and a surface normal. The normal is snapped to the dominant axis, which yields the mating face:

```gdscript
static func dominant_axis(n: Vector3) -> Vector3i:
    var ax := absf(n.x); var ay := absf(n.y); var az := absf(n.z)
    if ax >= ay and ax >= az:
        return Vector3i(signi(int(signf(n.x))), 0, 0)
    if ay >= az:
        return Vector3i(0, signi(int(signf(n.y))), 0)
    return Vector3i(0, 0, signi(int(signf(n.z))))
```

The anchor cell is the cell **just outside** the hit surface. Nudging the hit point backward along the normal by a quarter unit before quantising avoids the classic edge-case where a hit exactly on a cell boundary quantises into the wrong cell:

```gdscript
func _anchor_cell(hit_pos: Vector3, face: Vector3i) -> Vector3i:
    var inside := hit_pos - Vector3(face) * (SyndicateConstants.LATTICE_UNIT_M * 0.25)
    var host_cell := LatticeMath.local_to_cell(inside)
    return host_cell + face
```

### 6.4 Stage 4 — Origin Solve

The anchor cell must coincide with one of the candidate part's own cells — specifically, the cell adjacent to the attachment node whose rotated face is `−face`. The origin is solved by subtraction:

```gdscript
func solve_origin(def: PartDefinition, orientation_index: int,
                  anchor_cell: Vector3i, mating_face: Vector3i) -> Dictionary:
    var want := -mating_face
    for node in def.attachment_nodes:
        var rf := OrientationTable.rotate_face(orientation_index, node.face_normal)
        if rf != want:
            continue
        var rc := OrientationTable.rotate_cell(orientation_index, node.cell)
        return {"ok": true, "origin": anchor_cell - rc, "node": node}
    return {"ok": false}
```

When several nodes share the required face, the one whose resolved cell is nearest the raw hit point is selected — a float comparison used purely to disambiguate between already-legal integer candidates, which cannot introduce cross-machine divergence because the chosen result is re-validated as an integer placement.

---

## 7. Placement Safety Check Chain

Every candidate placement passes through an ordered chain of checks. The chain is **short-circuiting** and ordered cheapest-first, so the interactive ghost costs a handful of integer comparisons in the common rejection case.

```gdscript
class_name PlacementValidator
extends RefCounted

enum Reject {
    NONE = 0,
    OUT_OF_BOUNDS,
    CELL_OCCUPIED,
    NO_MATING_NODE,
    POLARITY_MISMATCH,
    CLASS_NOT_ACCEPTED,
    MOUNT_BUDGET_EXCEEDED,
    POWER_BUDGET_EXCEEDED,
    CLASS_LIMIT_EXCEEDED,
    MOTIVE_GROUND_BLOCKED,
    EFFECTOR_ARC_BLOCKED,
    COLLIDER_INTERPENETRATION,
    LOAD_CAPACITY_EXCEEDED,
    DUPLICATE_CORE,
}

func validate(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
    var r := _check_bounds(ctx, cand);              if r: return r
    r = _check_occupancy(ctx, cand);                if r: return r
    r = _check_mating(ctx, cand);                   if r: return r
    r = _check_class_limits(ctx, cand);             if r: return r
    r = _check_budgets(ctx, cand);                  if r: return r
    r = _check_motive_clearance(ctx, cand);         if r: return r
    r = _check_effector_arc(ctx, cand);             if r: return r
    r = _check_collider_interpenetration(ctx, cand);if r: return r
    r = _check_structural_load(ctx, cand);          if r: return r
    return Reject.NONE
```

### 7.1 Bounds

Every resolved cell must satisfy `LatticeMath.in_bounds`. Cost: `O(V)` integer comparisons where `V` is the part's cell count (typically 16–100).

### 7.2 Occupancy

Every resolved cell must satisfy `occupancy.is_free`. This is the overlap test in its entirety — one array read per cell. There is no broadphase, no AABB tree, and no physics query, because the lattice **is** the broadphase.

```gdscript
func _check_occupancy(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
    for c in cand.cells:
        if not ctx.occupancy.is_free(Vector3i(c)):
            return Reject.CELL_OCCUPIED
    return Reject.NONE
```

### 7.3 Mating

A placement must produce at least one valid attachment pair. A pair `(A.node, B.node)` is valid when all of the following hold:

1. `A.cell + A.face == B.cell` and `B.face == -A.face` (physically adjacent, facing each other).
2. Polarity is compatible: `FACE_MALE↔FACE_FEMALE`, or either side is `FACE_NEUTRAL`. `AXLE` mates only with `AXLE`; `DECK` mates only with `FACE_NEUTRAL` or `FACE_MALE`.
3. `accepts_classes` on both sides is empty or contains the other side's `part_class`.

```gdscript
const _POLARITY_MATRIX := {
    # [male, female, neutral, axle, deck]
    0: [false, true,  true,  false, true ],   # FACE_MALE
    1: [true,  false, true,  false, false],   # FACE_FEMALE
    2: [true,  true,  true,  false, true ],   # FACE_NEUTRAL
    3: [false, false, false, true,  false],   # AXLE
    4: [true,  false, true,  false, false],   # DECK
}

static func polarity_compatible(a: int, b: int) -> bool:
    return _POLARITY_MATRIX[a][b]
```

The matrix is symmetric by construction; the validator asserts this at startup.

### 7.4 Class Limits and Budgets

- Exactly one `CORE_MODULE` per Assembly (`DUPLICATE_CORE`).
- `MAX_EFFECTORS_PER_ASSEMBLY` = 16, `MAX_MOTIVE_PER_ASSEMBLY` = 24.
- `Σ mount_weight ≤ core_profile.mount_budget`.
- `Σ power_draw_pu ≤ core_profile.power_capacity_pu + Σ power_supply_pu`.

Budget sums are maintained incrementally on the `BuildContext` — attach adds, detach subtracts — so this check is `O(1)`, not a re-sum over all parts.

### 7.5 Motive Ground Clearance

A Motive Assembly must have unobstructed vertical travel over its full suspension range, or the suspension will resolve into the Assembly's own colliders at runtime. The check sweeps the contact volume through the travel envelope in lattice space:

```gdscript
func _check_motive_clearance(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
    var def := cand.definition
    if def.part_class != PartEnums.PartClass.MOTIVE_ASSEMBLY:
        return Reject.NONE
    var mp := def.motive_profile
    var travel_cells := int(ceil(
        (mp.suspension_rest_length_m + mp.suspension_travel_limit_m)
        / SyndicateConstants.LATTICE_UNIT_M))
    var down := OrientationTable.rotate_face(cand.orientation_index, Vector3i(0, -1, 0))
    for c in cand.cells:
        var base := Vector3i(c)
        for step in range(1, travel_cells + 1):
            var probe := base + down * step
            if not LatticeMath.in_bounds(probe):
                break
            if not ctx.occupancy.is_free(probe):
                return Reject.MOTIVE_GROUND_BLOCKED
    return Reject.NONE
```

This is why the check is worth doing at build time: a blocked suspension is invisible in the garage but produces violent jitter in a match. Catching it at placement eliminates an entire class of runtime physics instability.

### 7.6 Effector Firing Arc

A newly placed Effector Module must be able to traverse its declared yaw range without its muzzle line intersecting the Assembly's own occupancy. Rather than a continuous sweep, the arc is sampled at fixed 15° increments across the declared yaw limits and traced through the lattice with a 3D DDA walk.

```gdscript
const ARC_SAMPLE_STEP_DEG := 15.0
const ARC_TRACE_LENGTH_CELLS := 24

func _check_effector_arc(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
    var def := cand.definition
    if def.part_class != PartEnums.PartClass.EFFECTOR_MODULE:
        return Reject.NONE
    var ep := def.effector_profile
    var muzzle_local := ep.muzzle_offsets_m[0]
    var basis := OrientationTable.basis_for(cand.orientation_index)
    var muzzle_cell_f := Vector3(cand.origin_cell) + (basis * muzzle_local) \
                       / SyndicateConstants.LATTICE_UNIT_M
    var blocked := 0
    var samples := 0
    var yaw := ep.yaw_limit_deg.x
    while yaw <= ep.yaw_limit_deg.y:
        samples += 1
        var dir := basis * Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(yaw))
        if _dda_blocked(ctx, muzzle_cell_f, dir, cand.cells):
            blocked += 1
        yaw += ARC_SAMPLE_STEP_DEG
    # Reject only when the traversable arc collapses below a usable fraction.
    return Reject.EFFECTOR_ARC_BLOCKED if float(blocked) / float(samples) > 0.6 \
        else Reject.NONE
```

The 60% threshold is a design decision: a partially obstructed effector is a legitimate trade-off (a turret tucked behind a Structural Component has cover but limited arc), whereas a fully buried one is always a mistake. The garage surfaces the computed free-arc percentage in the part inspector so the trade-off is explicit rather than hidden.

`_dda_blocked` is a standard Amanatides–Woo voxel traversal over the occupancy array, skipping cells belonging to the candidate itself:

```gdscript
func _dda_blocked(ctx: BuildContext, start: Vector3, dir: Vector3,
                  own: PackedVector3Array) -> bool:
    var cell := Vector3i(floor(start.x), floor(start.y), floor(start.z))
    var step := Vector3i(signi(int(signf(dir.x))), signi(int(signf(dir.y))),
                         signi(int(signf(dir.z))))
    var t_delta := Vector3(
        INF if is_zero_approx(dir.x) else absf(1.0 / dir.x),
        INF if is_zero_approx(dir.y) else absf(1.0 / dir.y),
        INF if is_zero_approx(dir.z) else absf(1.0 / dir.z))
    var t_max := Vector3(
        _initial_t(start.x, dir.x), _initial_t(start.y, dir.y), _initial_t(start.z, dir.z))
    for _i in ARC_TRACE_LENGTH_CELLS:
        if t_max.x < t_max.y and t_max.x < t_max.z:
            cell.x += step.x; t_max.x += t_delta.x
        elif t_max.y < t_max.z:
            cell.y += step.y; t_max.y += t_delta.y
        else:
            cell.z += step.z; t_max.z += t_delta.z
        if not LatticeMath.in_bounds(cell):
            return false
        if own.has(Vector3(cell)):
            continue
        if not ctx.occupancy.is_free(cell):
            return true
    return false
```

### 7.7 Collider Interpenetration

Lattice occupancy prevents cell overlap, but `ColliderProfile` primitives may be *oriented* (up to 15° multiples) and may therefore protrude slightly beyond their owning cells. The final geometric check runs one `PhysicsServer3D` shape query per candidate primitive against the committed build proxies, with a small negative margin so that intended face contact is not reported as penetration.

```gdscript
const INTERPENETRATION_MARGIN_M := -0.008

func _check_collider_interpenetration(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
    for prim in cand.definition.collider_profile.primitives:
        var params := PhysicsShapeQueryParameters3D.new()
        params.shape_rid = ctx.shape_cache.rid_for(prim)
        params.transform = cand.world_transform * ColliderProfile.local_transform(prim)
        params.margin = INTERPENETRATION_MARGIN_M
        params.collision_mask = CollisionLayers.MASK_BUILD_GHOST
        if not ctx.space.intersect_shape(params, 1).is_empty():
            return Reject.COLLIDER_INTERPENETRATION
    return Reject.NONE
```

This is the **only** physics query in the placement chain, and it runs last, after every integer check has already passed. On a typical rejection the query is never reached.

### 7.8 Structural Load

The mating parent's `load_capacity_kg` must not be exceeded by the mass of the subtree that would hang from it, including the candidate. The subtree mass is maintained incrementally by the Chassis Graph (`DEPENDENCY_TREE_GRAPH.md` §5), so this check is a single comparison:

```gdscript
func _check_structural_load(ctx: BuildContext, cand: PlacementCandidate) -> Reject:
    var parent_def := PartRegistry.definition(ctx.state(cand.parent_slot).part_def_id)
    var added := ctx.graph.subtree_mass(cand.parent_slot) + cand.definition.mass_kg
    return Reject.LOAD_CAPACITY_EXCEEDED if added > parent_def.load_capacity_kg \
        else Reject.NONE
```

Exceeding load capacity is a **soft** rejection in Sandbox mode (placement allowed, part flagged `FLAG_STRAINED`, joint fails earlier under combat stress) and a **hard** rejection in Ranked mode. The mode flag lives on `BuildContext.enforce_hard_limits`.

---

## 8. Ghost Preview Rendering

The ghost is a single `MeshInstance3D` whose mesh is swapped when the candidate part changes and whose transform is updated each frame. It uses a dedicated unshaded material with a validity colour:

| State | Albedo | Alpha | Additional cue |
|---|---|---|---|
| Valid | `#39D98A` | 0.45 | Attachment node highlighted with a pulsing ring |
| Soft-warned | `#F2C14E` | 0.45 | Warning glyph over the strained joint |
| Rejected | `#E0554E` | 0.30 | Rejection reason string in the inspector strip |

The ghost never enters the occupancy array, never spawns colliders, and never participates in the Chassis Graph. It is presentation only. Its `collision_layer` and `collision_mask` are both `0`.

Ghost update is throttled: the validation chain runs only when `(anchor_cell, orientation_index, part_def_id)` changes, not every frame. A stationary cursor performs zero validation work.

---

## 9. Commit, Removal, and Re-Parenting

### 9.1 Commit

```gdscript
func commit(ctx: BuildContext, cand: PlacementCandidate) -> int:
    assert(validate(ctx, cand) == Reject.NONE)
    var slot := ctx.allocate_slot()
    var st := PartInstanceState.new()
    st.slot = slot
    st.part_def_id = cand.definition.runtime_id
    st.origin_cell = cand.origin_cell
    st.orientation_index = cand.orientation_index
    st.parent_slot = cand.parent_slot
    st.integrity = cand.definition.integrity_max
    ctx.states[slot] = st
    ctx.occupancy.write_slot(slot, cand.cells)
    ctx.graph.attach(slot, cand.parent_slot, cand.mating_node_strength)
    ctx.budgets.add(cand.definition)
    ctx.spawn_visual(slot)
    ctx.spawn_colliders(slot)
    EventBus.part_attached.emit(ctx.assembly_id, slot)
    return slot
```

`EventBus.part_attached` is what wakes the mass solver, the fusion rebuild, and the UI stat panel. Nothing polls.

### 9.2 Removal

Removing a part orphans its subtree. In the garage, orphaned parts are **not** deleted — they are re-parented if a legal alternative parent exists, and otherwise removed together with a confirmation prompt listing the affected count.

```gdscript
func remove(ctx: BuildContext, slot: int) -> void:
    var orphans := ctx.graph.subtree_slots(slot)
    orphans.remove_at(orphans.find(slot))
    ctx.occupancy.erase_slot(slot)
    ctx.graph.detach(slot)
    ctx.budgets.remove(PartRegistry.definition(ctx.states[slot].part_def_id))
    ctx.despawn_visual(slot)
    ctx.despawn_colliders(slot)
    ctx.states[slot] = null
    for o in orphans:
        var new_parent := _find_alternate_parent(ctx, o)
        if new_parent == SyndicateConstants.INVALID_SLOT:
            _queue_cascade_removal(ctx, o)
        else:
            ctx.graph.reparent(o, new_parent)
    EventBus.part_removed.emit(ctx.assembly_id, slot)
```

`_find_alternate_parent` scans the orphan's resolved attachment nodes for an adjacent occupied cell whose owning slot is still connected to the Core Module. It prefers, in order: a node with `can_bear_load = true`, then the highest `joint_strength_n`, then the lowest slot index for determinism.

### 9.3 Undo Model

The garage maintains a command stack of `BuildCommand` objects. Each command stores enough state to invert itself exactly:

```gdscript
class_name BuildCommand
extends RefCounted

enum Kind { ATTACH, REMOVE, REPAINT, REORIENT }

var kind: Kind
var slot: int
var part_def_id: int
var origin_cell: Vector3i
var orientation_index: int
var parent_slot: int
var prior_parent_slot: int
var prior_orientation_index: int
var prior_tint: Color
var cascade: Array[BuildCommand] = []   # child commands undone/redone atomically
```

Undo depth is capped at 128 commands. Because every command is expressed in integer lattice terms, undo is exact — there is no float drift between the original placement and its restoration.

---

## 10. Symmetry Mirroring

The garage offers an X-axis mirror mode. Mirroring is a **build-time convenience only**: it produces a second, independently committed part. There is no runtime mirror link, so destroying one mirrored part has no effect on its twin.

```gdscript
static func mirror_x(cell: Vector3i) -> Vector3i:
    var o := SyndicateConstants.LATTICE_ORIGIN_CELL
    return Vector3i(2 * o.x - cell.x - 1, cell.y, cell.z)

static func mirror_orientation_x(index: int) -> int:
    # Reflection is not in the rotation group; select the rotation whose
    # forward and up axes best match the reflected frame.
    var b := OrientationTable.basis_for(index)
    var want_fwd := Vector3(-b.z.x, b.z.y, b.z.z)
    var want_up := Vector3(-b.y.x, b.y.y, b.y.z)
    var best := index
    var best_score := -INF
    for k in SyndicateConstants.ORIENTATION_COUNT:
        var kb := OrientationTable.basis_for(k)
        var score := kb.z.dot(want_fwd) + kb.y.dot(want_up)
        if score > best_score:
            best_score = score
            best = k
    return best
```

When the mirrored placement fails validation, the mirror is skipped and the primary placement still commits, with a non-blocking notification. Mirror mode never blocks a legal placement.

---

## 11. Performance Budget

Measured on the reference target (mid-range 2021 desktop, Forward+ renderer, 180-part Assembly):

| Operation | Budget | Typical |
|---|---|---|
| Cursor cell resolution (ray + quantise) | 0.08 ms | 0.03 ms |
| Full validation chain, rejected early | 0.02 ms | 0.004 ms |
| Full validation chain, all checks pass | 0.35 ms | 0.19 ms |
| Effector arc check (24 samples × DDA) | 0.22 ms | 0.11 ms |
| Commit (occupancy + graph + spawn) | 1.20 ms | 0.62 ms |
| Full lattice rebuild from blueprint | 6.00 ms | 3.10 ms |

Validation runs only on candidate change (§8), so steady-state garage cost with a stationary cursor is effectively zero. The commit cost is a one-off spike hidden by the fact that it coincides with a user click.

---

## 12. Invariants

1. Placement decisions are integer-only. The single physics query (§7.7) runs last and may only *reject*, never *accept*, a placement that integer checks rejected.
2. `orientation_index ∈ [0, 24)` at all times; the index-to-basis mapping is frozen and serialised.
3. Every occupied cell maps to exactly one slot. The occupancy array is the sole authority on overlap.
4. The ghost preview has zero collision layers and zero collision masks and never mutates build state.
5. A committed part always has at least one valid attachment pair, except slot 0 (the Core Module), which is the graph root and has none.
6. Undo/redo is exact; no operation may lose or approximate lattice state.
7. Validation never runs per-frame on an unchanged candidate.
