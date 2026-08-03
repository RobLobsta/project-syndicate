# TERRAIN_CRATER_DEFORMER.md

**Project Syndicate — System Architecture Specification, Document 09 of 13**
**Subsystem:** Dynamic Ground Arrays — Runtime Heightfield Deformation and Permanent Cratering
**Status:** Normative.

---

## 1. Purpose

A Dynamic Ground Array is Project Syndicate's terrain representation. It is a chunked, mutable heightfield that permanently records the damage inflicted on it. Explosive impacts carve craters with raised rims; those craters persist for the entire match, alter vehicle handling through a surface-type change, block line of sight for low-profile Assemblies, and become tactical features in their own right.

The engineering requirement is that this must happen without a frame hitch. Deforming a heightfield means touching height data, rebuilding a collision shape, updating a rendering mesh, and replicating the change to every client — four operations that a naive implementation performs synchronously on the main thread at the moment of detonation, producing a visible 30 ms stall exactly when the game is at its most intense.

This document specifies a pipeline where the main thread does almost nothing.

---

## 2. Data Model

### 2.1 Constants

```gdscript
class_name GroundConstants
extends RefCounted

const SAMPLE_SPACING_M: float = 0.5
const CHUNK_SAMPLES: int = 129              # 128 quads + 1 shared edge row
const CHUNK_SPAN_M: float = 64.0            # (CHUNK_SAMPLES - 1) * SAMPLE_SPACING_M
const WORLD_CHUNKS: Vector2i = Vector2i(32, 32)
const WORLD_SPAN_M: float = 2048.0

const HEIGHT_MIN_M: float = -128.0
const HEIGHT_MAX_M: float = 384.0
const HEIGHT_RANGE_M: float = 512.0
const HEIGHT_QUANTUM_M: float = HEIGHT_RANGE_M / 65535.0   # ~7.81 mm

const COLLISION_STREAM_RADIUS_M: float = 180.0
const MAX_COLLISION_CHUNKS: int = 64
```

Height is stored with a `7.81 mm` quantum, which is finer than any gameplay-relevant height difference.

**Amended: chunks are allocated lazily, and the 33 MB figure this paragraph used to quote was wrong.** §2.2 declares the height arrays as `PackedInt32Array`, which is 4 bytes per sample and not 2, so a chunk costs about 215 KB across its three arrays and the full 32×32 grid would cost roughly 220 MB — not 33 MB, and not affordable. Narrowing the storage to a genuine `uint16` would need manual bit packing in `PackedByteArray` and would put a shift-and-mask on every sample read in the deformation solve.

The cheaper answer is not to allocate terrain nobody visits. `GroundArray` materialises a chunk the first time something reads or writes it and fills its baseline from a `GroundSource`; a match touches a few dozen chunks, so the live cost is single-digit megabytes. This is what makes the `GroundSource` contract in §2.2 load-bearing: the baseline must be a **pure function of sample position**, because two peers materialise chunks in whatever order they happen to drive, and a baseline drawn from a sequential RNG would give them different terrain. An unmaterialised chunk has never been deformed, so its live height is its baseline and every query falls through to the source — which is why the sparse representation needs no special case anywhere else.

### 2.2 Chunk

```gdscript
class_name GroundChunk
extends RefCounted

var chunk_coord: Vector2i = Vector2i.ZERO
## Authored baseline, never modified after load. Used for reset and for
## computing total accumulated deformation.
var base_heights: PackedInt32Array = PackedInt32Array()     # uint16 values
## Live heights including all deformation.
var live_heights: PackedInt32Array = PackedInt32Array()
## Per-sample surface classification (see Section 9).
var surface_ids: PackedByteArray = PackedByteArray()
## Accumulated depth removed. Derived rather than stored — see below.

var dirty_min: Vector2i = Vector2i(9999, 9999)
var dirty_max: Vector2i = Vector2i(-1, -1)
var collision_body: StaticBody3D = null
var collision_shape: HeightMapShape3D = null
var render_mesh: MeshInstance3D = null
var height_texture: ImageTexture = null      # R16, sampled by the ground shader
var revision: int = 0                        # increments on each applied deformation

func mark_dirty(x: int, z: int) -> void:
    dirty_min.x = mini(dirty_min.x, x); dirty_min.y = mini(dirty_min.y, z)
    dirty_max.x = maxi(dirty_max.x, x); dirty_max.y = maxi(dirty_max.y, z)

func has_dirty() -> bool:
    return dirty_max.x >= dirty_min.x

func clear_dirty() -> void:
    dirty_min = Vector2i(9999, 9999)
    dirty_max = Vector2i(-1, -1)
```

Keeping `base_heights` alongside `live_heights` doubles a chunk's height storage but buys three things: an exact reset for round restarts, a cheap "total deformation" query for the accumulation clamp, and a trivially correct network resync (send the delta against a known baseline rather than the absolute field).

**Amended: there is no separate `erosion` array.** It would be a third full-size array carrying `base_heights[i] - live_heights[i]`, which is a subtraction of two values the chunk already holds. `GroundChunk.erosion_at()` performs that subtraction, `§4.4`'s clamp calls it, and the 66 KB per chunk is not spent. The field is listed above as derived so that nothing tries to reintroduce it as storage.

A chunk also carries a `surface_texture` alongside `height_texture`: §9.2's splat map is committed in Stage 5 exactly as the height image is, and it needs somewhere to live.

### 2.3 Coordinate Mapping

```gdscript
class_name GroundMath
extends RefCounted

static func world_to_sample(p: Vector3) -> Vector2i:
    return Vector2i(
        int(floor((p.x + GroundConstants.WORLD_SPAN_M * 0.5)
                  / GroundConstants.SAMPLE_SPACING_M)),
        int(floor((p.z + GroundConstants.WORLD_SPAN_M * 0.5)
                  / GroundConstants.SAMPLE_SPACING_M)))

static func sample_to_world_xz(s: Vector2i) -> Vector2:
    return Vector2(
        float(s.x) * GroundConstants.SAMPLE_SPACING_M
            - GroundConstants.WORLD_SPAN_M * 0.5,
        float(s.y) * GroundConstants.SAMPLE_SPACING_M
            - GroundConstants.WORLD_SPAN_M * 0.5)

static func sample_to_chunk(s: Vector2i) -> Vector2i:
    return Vector2i(s.x / (GroundConstants.CHUNK_SAMPLES - 1),
                    s.y / (GroundConstants.CHUNK_SAMPLES - 1))

static func quantise(height_m: float) -> int:
    var t := (clampf(height_m, GroundConstants.HEIGHT_MIN_M,
                     GroundConstants.HEIGHT_MAX_M) - GroundConstants.HEIGHT_MIN_M)
           / GroundConstants.HEIGHT_RANGE_M
    return int(round(t * 65535.0))

static func dequantise(q: int) -> float:
    return GroundConstants.HEIGHT_MIN_M \
         + (float(q) / 65535.0) * GroundConstants.HEIGHT_RANGE_M
```

### 2.4 Shared Edge Samples

Chunks share their boundary sample row and column: chunk `(0,0)` owns samples `x ∈ [0, 128]`, chunk `(1,0)` owns `x ∈ [128, 256]`. Sample `x = 128` exists in both. A deformation touching a shared sample must write **both** copies, or a visible and collidable crack appears along the chunk seam.

```gdscript
func _write_sample(global_s: Vector2i, value: int) -> void:
    # A sample on a shared edge belongs to up to four chunks.
    var span := GroundConstants.CHUNK_SAMPLES - 1
    for dx in [0, -1]:
        for dz in [0, -1]:
            var cc := Vector2i((global_s.x + dx) / span, (global_s.y + dz) / span)
            if not _valid_chunk(cc):
                continue
            var local := global_s - cc * span
            if local.x < 0 or local.y < 0 \
               or local.x >= GroundConstants.CHUNK_SAMPLES \
               or local.y >= GroundConstants.CHUNK_SAMPLES:
                continue
            var chunk := _chunks[cc.y * GroundConstants.WORLD_CHUNKS.x + cc.x]
            chunk.live_heights[local.y * GroundConstants.CHUNK_SAMPLES + local.x] = value
            chunk.mark_dirty(local.x, local.y)
```

The `[0, -1]` offset pairs are what catch the corner case: a sample at a four-chunk corner is written to all four.

---

## 3. The Crater Profile

### 3.1 Shape Function

A crater is not a hemisphere. Real explosive cratering produces a bowl with a raised rim of ejecta, and the rim is what makes a crater read as a crater rather than a dent. The profile is defined in normalised radius `u = d / R`:

```
                    ⎧  −D · (1 − (u/u_r)²)^p                      u < u_r      (bowl)
        Δh(u)   =   ⎨   H · sin(π · (u − u_r)/(1 − u_r))          u_r ≤ u ≤ 1  (rim)
                    ⎩   0                                          u > 1
```

with:

| Symbol | Meaning | Value |
|---|---|---|
| `R` | Crater outer radius | `blast_radius_m · CRATER_RADIUS_FACTOR` (1.35) |
| `D` | Bowl depth | `f(energy)`, §3.2 |
| `H` | Rim height | `D · RIM_RATIO` (0.28) |
| `u_r` | Bowl/rim boundary | 0.68 |
| `p` | Bowl sharpness exponent | 0.85 |

```gdscript
class_name CraterProfile
extends RefCounted

const CRATER_RADIUS_FACTOR := 1.35
const RIM_RATIO := 0.28
const RIM_BOUNDARY := 0.68
const BOWL_EXPONENT := 0.85

static func delta_height(u: float, depth: float) -> float:
    if u >= 1.0:
        return 0.0
    if u < RIM_BOUNDARY:
        var t := u / RIM_BOUNDARY
        return -depth * pow(maxf(0.0, 1.0 - t * t), BOWL_EXPONENT)
    var s := (u - RIM_BOUNDARY) / (1.0 - RIM_BOUNDARY)
    return depth * RIM_RATIO * sin(PI * s)
```

The rim term uses `sin(π s)`, which is zero at both ends. The profile is therefore continuous at `u = 1` (no hard step at the crater edge) and continuous at `u = u_r` because the bowl term also reaches zero there. `tests/unit/test_crater_profile.gd` asserts C0 continuity at both boundaries to within `1e-5`.

### 3.2 Depth From Blast Energy

Depth scales with the cube root of blast energy — the standard scaling law for explosive cratering — and is modulated by the ground material's resistance:

```
D = CRATER_DEPTH_K · (E / E_ref)^(1/3) · (1 / hardness)
```

with `CRATER_DEPTH_K = 0.62 m`, `E_ref = 400` (the reference blast damage value), and `hardness` from the surface table (§9).

```gdscript
const CRATER_DEPTH_K := 0.62
const CRATER_ENERGY_REF := 400.0
const CRATER_MAX_DEPTH_M := 3.4

static func depth_for(blast_damage: float, hardness: float) -> float:
    var d := CRATER_DEPTH_K * pow(maxf(blast_damage, 1.0) / CRATER_ENERGY_REF, 1.0/3.0)
    return minf(d / maxf(hardness, 0.15), CRATER_MAX_DEPTH_M)
```

### 3.3 Ejecta Fraction

The rim carries part of the excavated spoil back out onto the surface. Integrating the profile over the annulus:

```
V_bowl = 2π R² D ∫₀^{u_r} u (1 − (u/u_r)²)^p du
V_rim  = 2π R² H ∫_{u_r}^{1} u sin(π(u−u_r)/(1−u_r)) du
```

With the shipping constants (`u_r = 0.68`, `p = 0.85`) the two integrals evaluate to `0.124973` and `0.171123`. At `RIM_RATIO = 0.28` that gives:

| Quantity | Coefficient of `2πR²D` |
|---|---|
| `V_bowl` | `0.124973` |
| `V_rim` | `0.047915` |
| **Ejecta fraction** `V_rim / V_bowl` | **`0.3834`** |

**The rim deliberately does not conserve volume, and `RIM_RATIO` is a gameplay constant rather than a derived one.**

This section previously claimed the two volumes matched to within 1.2% on coefficients of `0.253` and `0.256`. Those figures are not what the integrals evaluate to and the claim was false in the direction that matters: the value it purported to justify, `0.28`, is right, but for a different reason. Volume conservation would require `RIM_RATIO = 0.730309`, and §7.1 is where that number is refused — a conserving rim on a typical `1.4 m` crater stands `1.02 m` high, which is not a lip that unsettles a light Assembly at speed but a wall that traps it at the bottom of every shell hole on the map. A crater the player cannot drive out of is a worse artefact than a crater that has lost some of its spoil.

Losing 62% of the ejecta is also the physically ordinary case. Real explosive cratering throws a large fraction of its spoil clear of the continuous ejecta blanket entirely, and compacts more of it into the bowl walls; a rim holding everything the bowl gave up is the unusual outcome, not the default.

`CraterProfile.rim_ratio_for_volume_match()` computes the conserving value from whatever `RIM_BOUNDARY` and `BOWL_EXPONENT` currently are. It exists so the trade-off stays visible when either shape constant is changed — the ratio it prints is the value that would conserve volume, and shipping it is a decision about whether players can leave craters, not a correction. `tests/unit/test_crater_profile.gd` asserts the shipped ejecta fraction and the §7.1 rim height by value, so a change to any of the three constants fails there and has to be argued rather than absorbed.

---

## 4. The Deformation Pipeline

Five stages. Only stages 1 and 5 touch the main thread, and both are trivially cheap.

```
Stage 1  Request       main thread  ~2 us    enqueue a DeformRequest
Stage 2  Height solve  worker       ~0.4 ms  compute new sample values
Stage 3  Collision     worker       ~1.1 ms  build the replacement height array
Stage 4  Mesh/Texture  worker       ~0.8 ms  build the replacement Image
Stage 5  Commit        main thread  ~0.15 ms swap shape data and texture
```

### 4.1 Stage 1 — Request

```gdscript
class_name DeformRequest
extends RefCounted

var centre_world: Vector3
var radius_m: float
var depth_m: float
var kind: int                      # CRATER, RUT, SCRAPE
var source_tick: int
var deform_id: int                 # server-assigned, monotonic; used for replication
```

```gdscript
class_name GroundDeformSystem
extends Node

var _queue: Array[DeformRequest] = []
var _next_deform_id: int = 1

func request_crater(centre: Vector3, blast_radius: float,
                    blast_damage: float) -> void:
    if not NetAuthority.is_server:
        return                                  # clients apply replicated deforms only
    var s := GroundMath.world_to_sample(centre)
    var hardness := SurfaceTable.hardness(_surface_at(s))
    var req := DeformRequest.new()
    req.centre_world = centre
    req.radius_m = blast_radius * CraterProfile.CRATER_RADIUS_FACTOR
    req.depth_m = CraterProfile.depth_for(blast_damage, hardness)
    req.kind = DeformKind.CRATER
    req.source_tick = MatchClock.tick
    req.deform_id = _next_deform_id
    _next_deform_id += 1
    if _should_coalesce(req):
        return
    _queue.push_back(req)
    NetGroundReplicator.broadcast_deform(req)
```

The request is broadcast to clients **immediately**, before it is applied locally. Clients therefore begin their own identical worker-thread solve at the same time, and the deformation appears simultaneously everywhere without waiting for a round trip on the resulting geometry (§10).

### 4.2 Coalescing

Two explosions within `COALESCE_DISTANCE_M` of each other during the same tick produce one merged crater rather than two overlapping ones:

```gdscript
const COALESCE_DISTANCE_M := 1.6

func _should_coalesce(req: DeformRequest) -> bool:
    for existing in _queue:
        if existing.source_tick != req.source_tick:
            continue
        if existing.centre_world.distance_to(req.centre_world) > COALESCE_DISTANCE_M:
            continue
        # Merge: take the deeper depth and the union radius.
        existing.depth_m = maxf(existing.depth_m, req.depth_m)
        existing.radius_m = maxf(existing.radius_m,
            existing.centre_world.distance_to(req.centre_world) + req.radius_m)
        return true
    return false
```

### 4.3 Stage 2 — Height Solve

```gdscript
func _solve_heights(req: DeformRequest) -> DeformResult:
    var centre_s := GroundMath.world_to_sample(req.centre_world)
    var radius_samples := int(ceil(req.radius_m / GroundConstants.SAMPLE_SPACING_M))
    var result := DeformResult.new()
    result.request = req

    var ground_y := _sample_height_m(centre_s)
    for dz in range(-radius_samples, radius_samples + 1):
        for dx in range(-radius_samples, radius_samples + 1):
            var s := centre_s + Vector2i(dx, dz)
            if not _valid_sample(s):
                continue
            var wp := GroundMath.sample_to_world_xz(s)
            var d := wp.distance_to(Vector2(req.centre_world.x, req.centre_world.z))
            var u := d / req.radius_m
            if u >= 1.0:
                continue

            var delta := CraterProfile.delta_height(u, req.depth_m)

            # Blend toward the blast's ground plane rather than the local surface,
            # so a crater on a slope produces a level floor, not a tilted dish.
            var current := _sample_height_m(s)
            var target := ground_y + delta
            var blend := 1.0 - smoothstep(0.0, 1.0, u)
            var new_h := lerpf(current, target, blend * SLOPE_LEVEL_STRENGTH)

            new_h = _apply_erosion_clamp(s, new_h)
            result.samples.push_back(s)
            result.values.push_back(GroundMath.quantise(new_h))
    return result

const SLOPE_LEVEL_STRENGTH := 0.85
```

Levelling toward the blast's ground plane is a genuine gameplay decision: a crater on a hillside becomes a flat shelf, which is a usable firing position. A crater that merely subtracted a bowl from the slope would leave a tilted depression that vehicles slide out of.

**Amended: the listing above destroys the rim, and the corrected form separates levelling from the profile.**

Blending the whole profile through `lerpf(current, ground_y + delta, blend * SLOPE_LEVEL_STRENGTH)` with `blend = 1 - smoothstep(0, 1, u)` attenuates every part of the crater by its distance from the centre — including the rim, which lives at `u ∈ [0.68, 1]` where `blend` has almost reached zero. At the rim's peak (`u = 0.84`) the weight is `0.0686`, so on flat ground the rim comes out at **5.8% of the height §3.1 specifies for it**. §7.1's worked example — a `0.39 m` rim on a `1.4 m` crater, "enough to unsettle a light Assembly at speed and enough to provide hull-down cover for a low-profile one" — would ship at `0.023 m` and provide neither.

Levelling and the profile are separate concerns. Levelling decides *what datum the crater is cut into*, and is only meaningful inside the bowl; the profile is the crater itself and is added on top. The corrected solve:

```gdscript
var current := _sample_height_m(s)
# Levelling falls to zero at the bowl's edge, so the rim is deposited on
# whatever surface is actually there — which is also what ejecta does.
var level := 1.0 - smoothstep(0.0, CraterProfile.RIM_BOUNDARY, u)
var datum := lerpf(current, ground_y, level * SLOPE_LEVEL_STRENGTH)
var new_h := datum + CraterProfile.delta_height(u, req.depth_m)
new_h = _apply_erosion_clamp(s, new_h)
```

This is continuous everywhere on any terrain: at `u = RIM_BOUNDARY` the levelling weight and the profile are both zero, so both sides of the boundary evaluate to `current`; at `u = 1` the profile is zero again. The bowl floor still flattens toward `ground_y - D` on a slope, which is the whole point of §4.3, and the rim is now exactly `RIM_RATIO · D` above the local surface as §3.1 and §7.1 both assume.

`tests/integration/test_ground_deform.gd` asserts the rim stands above datum after the solve, and `tests/unit/test_crater_profile.gd` asserts §7.1's `0.39 m` figure by value, so restoring the old formula fails both.

### 4.4 Erosion Accumulation Clamp

Without a limit, repeated bombardment of the same spot digs an arbitrarily deep pit that swallows vehicles and eventually punches through the world floor. Each sample tracks cumulative erosion and the deformation is attenuated as it approaches the limit:

```gdscript
const MAX_EROSION_M := 5.5
const EROSION_SOFT_START := 0.70          # fraction of MAX at which attenuation begins

func _apply_erosion_clamp(s: Vector2i, proposed_h: float) -> float:
    var base_h := _base_height_m(s)
    var eroded := base_h - proposed_h
    if eroded <= 0.0:
        return proposed_h                                # rim uplift is unclamped
    var soft := MAX_EROSION_M * EROSION_SOFT_START
    if eroded <= soft:
        return proposed_h
    var over := eroded - soft
    var range_left := MAX_EROSION_M - soft
    var attenuated := soft + range_left * (1.0 - exp(-over / range_left))
    return base_h - attenuated
```

The exponential approach means erosion asymptotes toward `MAX_EROSION_M` rather than hitting a hard wall, so the hundredth shell into a crater still visibly does *something* — just less than the first.

### 4.5 Stage 3 — Collision Rebuild

`HeightMapShape3D` in Godot takes a flat `PackedFloat32Array` of `map_width × map_depth` values. There is no partial-update API — the whole array must be reassigned. That reassignment is the single most expensive main-thread operation in this system, so the array is **built on the worker thread** and only the assignment happens on the main thread.

```gdscript
func _build_collision_array(chunk: GroundChunk) -> PackedFloat32Array:
    var n := GroundConstants.CHUNK_SAMPLES
    var out := PackedFloat32Array()
    out.resize(n * n)
    for i in n * n:
        out[i] = GroundMath.dequantise(chunk.live_heights[i])
    return out
```

Only chunks that (a) have dirty samples and (b) currently have streamed collision (§5) are rebuilt. A crater in an unpopulated corner of the map updates height data and rendering but creates no collision shape at all until an Assembly approaches.

### 4.6 Stage 4 — Height Texture Rebuild

The ground renders through a vertex-displacement shader sampling a per-chunk `R16` height texture rather than through a rebuilt `ArrayMesh`. This is a substantially cheaper update path: an `Image` blit versus a full mesh reconstruction with normal recalculation.

```gdscript
func _build_height_image(chunk: GroundChunk) -> Image:
    var n := GroundConstants.CHUNK_SAMPLES
    var img := Image.create(n, n, false, Image.FORMAT_RH)
    for z in n:
        for x in n:
            var q: int = chunk.live_heights[z * n + x]
            var h := GroundMath.dequantise(q)
            var norm := (h - GroundConstants.HEIGHT_MIN_M) / GroundConstants.HEIGHT_RANGE_M
            img.set_pixel(x, z, Color(norm, 0.0, 0.0, 1.0))
    return img
```

Normals are derived in the fragment shader from the height texture, so no normal data is transferred:

```glsl
// src/vfx/shaders/ground_array.gdshader (excerpt)
// CLAUDE.md §2 puts every .gdshader under src/vfx/shaders/; this document
// previously named a path inside src/world/ground/, which that layout forbids.
uniform sampler2D u_height : hint_default_black, filter_linear, repeat_disable;
uniform float u_height_min = -128.0;
uniform float u_height_range = 512.0;
uniform float u_sample_spacing = 0.5;
uniform float u_chunk_samples = 129.0;

float height_at(vec2 uv) {
    return u_height_min + texture(u_height, uv).r * u_height_range;
}

void vertex() {
    vec2 uv = UV;
    VERTEX.y = height_at(uv);
    v_uv = uv;
}

void fragment() {
    float texel = 1.0 / u_chunk_samples;
    float hl = height_at(v_uv - vec2(texel, 0.0));
    float hr = height_at(v_uv + vec2(texel, 0.0));
    float hd = height_at(v_uv - vec2(0.0, texel));
    float hu = height_at(v_uv + vec2(0.0, texel));
    vec3 n = normalize(vec3(hl - hr, 2.0 * u_sample_spacing, hd - hu));
    NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
    // ... surface splat blending follows, see Section 9
}
```

### 4.7 Stage 5 — Commit

```gdscript
func _process(_dt: float) -> void:
    var budget := COMMIT_BUDGET_MS
    var start := Time.get_ticks_usec()
    while not _ready_results.is_empty():
        if (Time.get_ticks_usec() - start) / 1000.0 > budget:
            break
        var r: DeformResult = _ready_results.pop_front()
        for chunk in r.affected_chunks:
            if chunk.collision_shape != null:
                chunk.collision_shape.map_data = r.collision_arrays[chunk.chunk_coord]
            chunk.height_texture.update(r.height_images[chunk.chunk_coord])
            chunk.revision += 1
            chunk.clear_dirty()
        EventBus.ground_deformed.emit(r.request.deform_id, r.request.centre_world,
                                      r.request.radius_m)

const COMMIT_BUDGET_MS := 1.5
```

The budget loop is what guarantees no hitch. A barrage producing twelve craters in one tick commits two or three per frame over the following few frames. The visual latency is 30–60 ms, which is well below the threshold at which a player notices, and it is entirely invisible next to the explosion VFX that covers the area anyway.

---

## 5. Collision Streaming

Instantiating 1 024 `HeightMapShape3D` bodies is neither necessary nor affordable. Collision exists only near things that can touch it.

```gdscript
class_name GroundCollisionStreamer
extends Node

const REEVALUATE_INTERVAL_S := 0.5

var _resident: Dictionary = {}          # Vector2i -> GroundChunk
var _accum: float = 0.0

func _physics_process(dt: float) -> void:
    _accum += dt
    if _accum < REEVALUATE_INTERVAL_S:
        return
    _accum = 0.0
    var wanted := {}
    for anchor in _collision_anchors():          # Assemblies, debris, live projectiles
        var cs := GroundMath.sample_to_chunk(GroundMath.world_to_sample(anchor))
        var r := int(ceil(GroundConstants.COLLISION_STREAM_RADIUS_M
                          / GroundConstants.CHUNK_SPAN_M))
        for dz in range(-r, r + 1):
            for dx in range(-r, r + 1):
                var cc := cs + Vector2i(dx, dz)
                if _valid_chunk(cc):
                    wanted[cc] = true
    for cc in _resident.keys():
        if not wanted.has(cc):
            _release_collision(cc)
    var added := 0
    for cc in wanted.keys():
        if _resident.has(cc):
            continue
        if _resident.size() >= GroundConstants.MAX_COLLISION_CHUNKS:
            break
        _acquire_collision(cc)
        added += 1
        if added >= 4:
            break                                # spread instantiation across ticks
```

`_acquire_collision` builds the `PackedFloat32Array` on a worker thread and assigns it on commit, using the same pipeline as a deformation. Streaming in a chunk therefore also cannot hitch.

**Amended: the acquisition order must be by distance to the nearest anchor.**

The listing above iterates `wanted.keys()` and breaks after four acquisitions, so which four are acquired is whatever order a `Dictionary` yields. That is non-deterministic, which Invariant I-9 forbids on its own — but the obvious repair, sorting by chunk index, is actively worse and was measured failing. Ascending chunk index acquires the **lowest-indexed corner of the wanted region**, which is the chunk furthest from the anchor in the direction nothing is heading. An Assembly dropped 140 m from the world origin fell straight through the terrain: 49 chunks were wanted, the four acquired were 180 m away, and the chunk it was standing on was 45th in the queue.

Order by squared distance from the chunk centre to the nearest anchor, and break ties on chunk index so the result is still reproducible. The chunk something is standing on is then always acquired first and the chunk it is about to reach second, which is what makes a four-per-evaluation cap safe rather than a lottery.

**A scene or a test placing something on the ground before the first tick needs the whole wanted set at once**, not four of it. `GroundCollisionStreamer.prime()` acquires up to `MAX_COLLISION_CHUNKS` in one call and is the construction-time path; `evaluate()` keeps the cap and is the steady-state one. Neither the match scene's setup nor a fixture is inside a frame budget, which is the same reasoning that gives `GroundDeformSystem` its `flush()`.

A chunk deformed while unstreamed carries its dirty state; when it is later streamed in, the collision array is built from `live_heights`, which already includes every deformation. Deformation and streaming are fully independent.

---

## 6. Rut and Scrape Deformation

Craters are not the only source of ground change. Tracked Motive Assemblies leave ruts, and a heavy Assembly landing hard leaves an impression.

```gdscript
const RUT_DEPTH_PER_KN_M := 0.00018
const RUT_MIN_LOAD_N := 26000.0
const RUT_SAMPLE_INTERVAL_M := 0.75

func accumulate_rut(contact_world: Vector3, normal_load_n: float,
                    surface_id: int) -> void:
    if not NetAuthority.is_server:
        return
    if normal_load_n < RUT_MIN_LOAD_N:
        return
    if not SurfaceTable.is_ruttable(surface_id):
        return
    var s := GroundMath.world_to_sample(contact_world)
    if _last_rut_sample.get(_current_track_id, Vector2i(-9999, -9999)) == s:
        return
    _last_rut_sample[_current_track_id] = s
    var depth := (normal_load_n - RUT_MIN_LOAD_N) * RUT_DEPTH_PER_KN_M * 0.001
    _rut_batch.push_back({"sample": s, "depth": minf(depth, 0.06)})
```

Ruts are accumulated into a batch and flushed once per second as a **single** deformation request covering all batched samples. Flushing per contact would produce hundreds of requests per second per Assembly, which is precisely the kind of unbounded work this architecture exists to avoid.

Ruts are also excluded from network replication as individual events. They are derived deterministically on each client from the replicated Assembly transforms, which every client already has. A client that joins late receives the accumulated rut field as part of the ground resync (§10.3).

---

## 7. Gameplay Consequences

### 7.1 Suspension Interaction

Motive Assembly suspension probes (`DYNAMIC_MASS_PHYSICS.md` §6.1) are shape casts against `MASK_GROUND`, which includes the streamed heightfield collision. A crater is therefore immediately drivable, with no additional code — the probe simply finds a lower contact.

The crater rim is the interesting part: at `RIM_RATIO = 0.28` of a typical `1.4 m` deep crater, the rim is `0.39 m` high, which is enough to unsettle a light Assembly at speed and enough to provide hull-down cover for a low-profile one.

### 7.2 Line of Sight

Crater rims occlude. Because the heightfield collision is on `LAYER_GROUND` and `MASK_PROJECTILE_TARGET` includes it, projectiles hit rims. No separate LOS system is needed; the geometry does the work.

### 7.3 Surface Change

Crater interiors are reclassified to `SURFACE_DEFORMED` (§9), which carries a traction multiplier of `0.66`. Driving through a fresh crater is measurably worse than driving around it, which gives the deformation tactical weight beyond the visual.

---

## 8. Threading and Determinism

### 8.1 Worker Pipeline

```gdscript
func _dispatch_pending() -> void:
    while not _queue.is_empty() and _in_flight < MAX_IN_FLIGHT_DEFORMS:
        var req: DeformRequest = _queue.pop_front()
        _in_flight += 1
        WorkerThreadPool.add_task(func():
            var result := _solve_heights(req)
            _apply_to_chunk_arrays(result)          # writes live_heights, erosion
            result.collision_arrays = _build_all_collision(result)
            result.height_images = _build_all_images(result)
            _ready_mutex.lock()
            _ready_results.push_back(result)
            _ready_mutex.unlock()
            _in_flight -= 1
        , true, "ground_deform")

const MAX_IN_FLIGHT_DEFORMS := 3
```

`_apply_to_chunk_arrays` mutates `live_heights` from the worker thread. This is safe because:

1. Only one deform task writes to any given chunk at a time — `_dispatch_pending` checks chunk overlap against in-flight requests and defers a conflicting request to the next dispatch.
2. Nothing on the main thread reads `live_heights` during a match. The main thread reads only the committed `HeightMapShape3D` and the committed texture.
3. `_sample_height_m` queries used by gameplay (rut accumulation, surface lookup) read through a lock held for the duration of `_apply_to_chunk_arrays`.

**Amended: the lock is a `Mutex`, not an `RWLock`.** Godot 4 exposes `Mutex`, `Semaphore`, `Thread` and `WorkerThreadPool` to GDScript and nothing else; there is no scripting-level reader-writer lock to use. Verified against 4.7.1. The substitution costs nothing measurable at this system's access pattern — writes happen only inside a deformation solve, a few times a second at worst, and readers are a handful of sample lookups per contact per tick — so serialising two readers that could have run concurrently is cheaper than the GDScript-level reader-writer lock that would avoid it. `GroundArray.lock` is that mutex and every query goes through it.

```gdscript
func _overlaps_in_flight(req: DeformRequest) -> bool:
    for f in _in_flight_requests:
        if f.centre_world.distance_to(req.centre_world) < (f.radius_m + req.radius_m):
            return true
    return false
```

### 8.2 Determinism

The deformation solve is fully deterministic: it uses no RNG, iterates samples in a fixed nested loop order, and quantises through the same `GroundMath.quantise` on every platform. Given the same `DeformRequest` sequence, every client produces bit-identical `live_heights`.

This is what allows the replication scheme in §10 to send only the request rather than the resulting geometry.

Determinism is verified by `tests/integration/test_ground_determinism.gd`, which applies 500 pseudo-random deform requests on two independently constructed Ground Arrays and asserts identical CRC-32 over all `live_heights`.

---

## 9. Surface Classification

### 9.1 Surface Table

```gdscript
class_name SurfaceTable
extends RefCounted

enum Surface {
    COMPACTED = 0,
    LOOSE     = 1,
    SLICK     = 2,
    DEFORMED  = 3,
    STRUCTURE = 4,
}

const TRACTION := [1.00, 0.78, 0.42, 0.66, 1.06]
const HARDNESS := [1.00, 0.55, 0.80, 0.62, 3.20]
const RUTTABLE := [false, true, false, true, false]
const ROLL_RESIST := [0.014, 0.031, 0.009, 0.026, 0.011]

static func multiplier(id: int) -> float:  return TRACTION[id]
static func hardness(id: int) -> float:    return HARDNESS[id]
static func is_ruttable(id: int) -> bool:  return RUTTABLE[id]
```

`TRACTION` here is the exact array consumed by `DYNAMIC_MASS_PHYSICS.md` §7.3. There is one definition, in this file, and the physics document indexes it.

`HARDNESS` feeds crater depth (§3.2). `STRUCTURE` at `3.20` means blasts on Static Volume rooftops barely crater — correct, since those are not part of the heightfield at all and the value exists only to make the lookup total.

### 9.2 Deformation Reclassification

```gdscript
const DEFORM_RECLASSIFY_THRESHOLD_M := 0.22

func _reclassify(s: Vector2i, delta_h: float) -> void:
    if absf(delta_h) < DEFORM_RECLASSIFY_THRESHOLD_M:
        return
    _write_surface(s, SurfaceTable.Surface.DEFORMED)
```

Reclassification writes to the `surface_ids` byte array and marks a splat-map region dirty. The splat map is a per-chunk `R8` texture committed alongside the height texture in Stage 5, and the ground shader blends four material layers by it.

---

## 10. Network Replication

### 10.1 Deform Events

Ground deformation replicates as **events, not geometry**. A `DeformRequest` is 34 bytes on the wire:

| Field | Bits | Encoding |
|---|---|---|
| `deform_id` | 24 | Monotonic counter |
| `centre_world.x` | 22 | Quantised to `2048 m / 4 mm` |
| `centre_world.y` | 18 | Quantised to `512 m / 2 mm` |
| `centre_world.z` | 22 | Quantised to `2048 m / 4 mm` |
| `radius_m` | 12 | Quantised to `0.01 m`, max `40.95 m` |
| `depth_m` | 10 | Quantised to `0.005 m`, max `5.115 m` |
| `kind` | 3 | Enum |
| `source_tick` | 16 | Wrapping tick |

Sent on a **reliable ordered** channel. Ordering matters because the erosion clamp is order-dependent: applying crater B then A produces a different field than A then B when they overlap.

### 10.2 Client Application

Clients run the identical worker pipeline on receipt. Because the solve is deterministic (§8.2), the resulting `live_heights` match the server exactly, and no geometry is ever transmitted.

### 10.3 Late Join and Resync

A joining client needs the accumulated deformation. Two mechanisms:

1. **Event replay** (default): the server retains the ordered `DeformRequest` log for the match. At 34 bytes each and a typical 900 deforms per 15-minute match, the full log is 30 KB — trivially small. The client replays it during the loading screen.
2. **Delta snapshot** (fallback, used when the log exceeds `LOG_SNAPSHOT_THRESHOLD = 4096` entries): the server sends, per dirty chunk, a run-length-encoded `int16` delta of `live_heights − base_heights`. Deltas are overwhelmingly zero outside crater regions, so RLE compresses a typical dirty chunk to 2–6 KB.

```gdscript
const LOG_SNAPSHOT_THRESHOLD := 4096

func build_late_join_payload() -> PackedByteArray:
    if _deform_log.size() <= LOG_SNAPSHOT_THRESHOLD:
        return _encode_deform_log()
    return _encode_delta_snapshot()
```

### 10.4 Rate Limiting

A malicious or malfunctioning source could spam deform requests. The server enforces:

- Maximum `MAX_DEFORMS_PER_SECOND = 24` globally, with excess coalesced into the nearest existing pending request.
- Maximum `MAX_DEFORMS_PER_ASSEMBLY_PER_SECOND = 6`.

Exceeding either produces a merged deformation rather than a dropped one, so the visual result stays honest.

---

## 11. Performance Budget

Reference target, 16-player match, active bombardment (6 craters/second):

| Stage | Thread | Budget | Measured |
|---|---|---|---|
| Request construction | Main | 0.01 ms | 0.002 ms |
| Height solve (R = 5.7 m, 23×23 samples) | Worker | 0.60 ms | 0.38 ms |
| Erosion clamp + reclassify | Worker | 0.15 ms | 0.07 ms |
| Collision array build (1 chunk) | Worker | 1.40 ms | 1.10 ms |
| Height image build (1 chunk) | Worker | 1.00 ms | 0.79 ms |
| Commit (shape + texture swap) | Main | 0.25 ms | 0.14 ms |
| Streaming re-evaluation (2 Hz) | Main | 0.20 ms | 0.09 ms |
| **Main-thread total per frame** | | **1.50 ms** (budgeted cap) | **0.31 ms** |

The main-thread cost is capped by construction at `COMMIT_BUDGET_MS = 1.5`, regardless of how many deformations are pending.

---

## 12. Invariants

1. Ground deformation is authored only on the server. Clients apply replicated `DeformRequest` events.
2. The deformation solve is deterministic and RNG-free; identical request sequences produce bit-identical heightfields.
3. Height solving, collision array construction, and image construction run on `WorkerThreadPool`. Only the shape/texture swap touches the main thread, under a hard `1.5 ms` per-frame budget.
4. Samples on chunk boundaries are written to every chunk that shares them.
5. `base_heights` is never modified after load.
6. Erosion is clamped with an exponential approach to `MAX_EROSION_M`; deformation never punches through the world floor.
7. Collision shapes exist only for streamed chunks; deformation of an unstreamed chunk updates data without instantiating collision.
8. Two deformations affecting overlapping regions never run concurrently.
9. Deform events replicate on a reliable ordered channel; ordering is required for correctness.
10. Ruts are batched and flushed at 1 Hz, never emitted per contact.
11. `SurfaceTable.TRACTION` is defined here and consumed by the physics document; there is no second copy.
