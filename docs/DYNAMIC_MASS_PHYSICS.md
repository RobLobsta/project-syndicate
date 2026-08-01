# DYNAMIC_MASS_PHYSICS.md

**Project Syndicate — System Architecture Specification, Document 05 of 13**
**Subsystem:** Mass Aggregation, Centre-of-Mass Shift, Suspension Load, Traction Degradation
**Status:** Normative.

---

## 1. The Foundational Decision: One Rigid Body Per Assembly

An Assembly of 180 parts is simulated as **exactly one `RigidBody3D`**. It is not a hierarchy of bodies joined by `Generic6DOFJoint3D`. It is not a soft-body network. It is one body carrying up to 540 primitive collision shapes (three per part, per `PART_DATA_SCHEMA.md` §6.2).

This is the single most consequential architectural choice in the physics subsystem, and it is the direct answer to the stuttering that plagues joint-based construction games. The failure mode is well understood: a chain of `N` constrained bodies requires the impulse solver to propagate corrections along the chain, one link per iteration. With the default 8 solver iterations, a 20-part chain never converges. The result is visible sag, oscillation that grows under load, and the characteristic "jelly vehicle" behaviour where a heavily built Assembly vibrates itself apart while sitting still.

A single rigid body has **zero constraints to converge**. It cannot sag, cannot oscillate, and cannot desynchronise from itself. Structural failure is modelled by the Chassis Graph as a discrete topological event (`DEPENDENCY_TREE_GRAPH.md` §5), not as a continuous constraint that might be violated — which is both cheaper and far more controllable.

The costs of this choice, and their mitigations:

| Cost | Mitigation |
|---|---|
| No visible flex or suspension travel *of the chassis itself* | Suspension travel is modelled per Motive Assembly via raycast wheels (§6); chassis rigidity is correct for welded steel anyway |
| Detachment requires rebuilding mass properties | Rebuild is event-driven and costs ~0.2 ms off the main thread (§4.4) |
| Many shapes on one body | Shapes are primitives only, and Godot's broadphase handles a single body's shape list efficiently; measured at 540 shapes the broadphase cost is 0.09 ms |
| Off-diagonal inertia is not directly settable in Godot | Handled by explicit coupling-torque correction (§3.4) |

---

## 2. Runtime Node Structure

```
AssemblyRuntime            (Node3D)
├── ChassisBody            (ChassisBodyRef : RigidBody3D)  ← the ONLY physics body
│   ├── shape_s000_p0      (CollisionShape3D)  ← one per authored primitive
│   ├── shape_s000_p1      (CollisionShape3D)
│   ├── ...
│   └── MotiveProbes       (Node3D)           ← ShapeCast3D per Motive Assembly
│       ├── probe_s014     (ShapeCast3D)
│       └── ...
├── VisualRoot             (Node3D)           ← interpolated; collision_layer/mask = 0 everywhere
│   ├── part_s000          (MeshInstance3D)
│   ├── part_s001          (MeshInstance3D)
│   ├── ...
│   └── SkirtingMesh       (MeshInstance3D)
└── AudioRoot              (Node3D)
```

**Amendment.** This document originally grouped the shapes under a `ColliderRoot` node inside the body. Godot registers a `CollisionShape3D` only when it is a **direct child** of a `CollisionObject3D`; an intervening `Node3D` leaves every shape under it inert, with no error, no warning at runtime, and no shape on the body. Applied to an Assembly that is the worst available failure — Architectural Invariant I-1 makes these primitives the only collision geometry that exists, so the result is a vehicle nothing can hit, and it presents as a damage bug rather than as a tree bug. The shapes are therefore direct children of `ChassisBody` and `ColliderRoot` no longer exists. `MotiveProbes` is unaffected: a `ShapeCast3D` is not a shape owner and works anywhere in the tree.

Shape indices are assigned in ascending slot order at spawn and **never move**. A part taken out of the simulation has its shapes disabled, not removed, because removing one renumbers every later index on the body and invalidates the shape-index to slot map of `COMPONENT_HEALTH_DAMAGE.md` §5.4 for every part placed after it.

`VisualRoot` is **not** a child of `ChassisBody`. It is a sibling, and its transform is written by the interpolation system (§10.2) from the body's previous and current physics transforms. This is what makes rendering smooth at any framerate independent of the 60 Hz physics tick.

Every node under `VisualRoot` has `collision_layer = 0` and `collision_mask = 0` and is never a child of a `PhysicsBody3D`. This is checked at spawn time by `AssemblyRuntime._assert_visual_decoupling()`, which runs in debug builds and walks the entire visual subtree.

---

## 3. Mass Properties

### 3.1 Total Mass

```
M = Σ_{s ∈ live} m_s
```

where `live` is the set of slots with `alive[s] == 1` and without `FLAG_DETACHED`.

### 3.2 Centre of Mass

Each part's centre of mass in assembly-local space:

```
p_s = cell_to_local(origin_cell_s) + R(orientation_s) · com_offset_s
```

The Assembly centre of mass:

```
C = ( Σ_s m_s · p_s ) / M
```

```gdscript
class_name MassSolver
extends RefCounted

class MassProperties extends RefCounted:
    var total_mass: float = 0.0
    var com_local: Vector3 = Vector3.ZERO
    var inertia_full: Basis = Basis()       # full 3x3 tensor about the COM
    var inertia_diag: Vector3 = Vector3.ONE # principal-ish diagonal for Godot
    var part_count: int = 0

static func compute(states: Array, graph: ChassisGraph) -> MassProperties:
    var mp := MassProperties.new()
    var weighted := Vector3.ZERO
    for slot in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
        if graph.alive[slot] == 0:
            continue
        var st: PartInstanceState = states[slot]
        if st == null or (st.flags & PartFlags.FLAG_DETACHED) != 0:
            continue
        var def := PartRegistry.definition(st.part_def_id)
        var p := part_com_local(st, def)
        mp.total_mass += def.mass_kg
        weighted += p * def.mass_kg
        mp.part_count += 1
    mp.com_local = weighted / maxf(mp.total_mass, 0.001)
    mp.inertia_full = InertiaSolver.accumulate(states, graph, mp.com_local)
    mp.inertia_diag = InertiaSolver.diagonal_of(mp.inertia_full)
    return mp

static func part_com_local(st: PartInstanceState, def: PartDefinition) -> Vector3:
    return LatticeMath.cell_to_local(st.origin_cell) \
         + OrientationTable.basis_for(st.orientation_index) * def.com_offset_m
```

### 3.3 Inertia Tensor

Each part is treated as a uniform-density rectangular box with half-extents `h`, either from `inertia_box_half_extents_m` or derived from the lattice bounds:

```
h = (bounds_max_cell - bounds_min_cell + 1) · LATTICE_UNIT_M / 2
```

Box inertia about the part's own COM, in the part's local frame:

```
I_xx = (m/12)(4h_y² + 4h_z²)
I_yy = (m/12)(4h_x² + 4h_z²)
I_zz = (m/12)(4h_x² + 4h_y²)
```

Rotated into assembly space by the part's orientation basis `R`:

```
I_part_assembly = R · diag(I_xx, I_yy, I_zz) · Rᵀ
```

Translated to the Assembly COM by the parallel-axis theorem, with `d = p_s − C`:

```
I_s = I_part_assembly + m_s · ( (d·d) I₃ − d ⊗ d )
```

Summed over all live parts:

```
I = Σ_s I_s
```

**Amendment.** This section originally wrote the accumulation as a private `MassSolver._accumulate_inertia`. It lives on a separate `InertiaSolver` instead, which `CLAUDE.md` §2 already named a file for, because `DEPENDENCY_TREE_GRAPH.md` §6 needs the identical arithmetic over an island's slots rather than the Assembly's. `MassSolver` owns the mass and centre-of-mass reduction and calls in here per part; the sum is `MassSolver`'s, because it already holds each part's centre from the pass that produced `C` and re-deriving them would cost a basis multiply per part per solve.

```gdscript
class_name InertiaSolver

const BOX_TENSOR_DENOM := 12.0

static func half_extents(def: PartDefinition) -> Vector3:
    if def.inertia_box_half_extents_m != Vector3.ZERO:
        return def.inertia_box_half_extents_m
    return Vector3(def.bounds_size_cells) * SyndicateConstants.LATTICE_UNIT_M * 0.5

static func box_tensor(mass_kg: float, h: Vector3) -> Vector3:
    var w := h + h                                   # full extents
    var k := mass_kg / BOX_TENSOR_DENOM
    return Vector3(k * (w.y*w.y + w.z*w.z),
                   k * (w.x*w.x + w.z*w.z),
                   k * (w.x*w.x + w.y*w.y))

static func part_tensor(def: PartDefinition, orientation_index: int,
                        offset: Vector3) -> Basis:
    var diag := box_tensor(def.mass_kg, half_extents(def))
    var r := OrientationTable.basis_for(orientation_index)
    var local := Basis(Vector3(diag.x, 0.0, 0.0),
                       Vector3(0.0, diag.y, 0.0),
                       Vector3(0.0, 0.0, diag.z))
    return add(r * local * r.transposed(), parallel_axis(def.mass_kg, offset))

static func parallel_axis(mass_kg: float, d: Vector3) -> Basis:
    var dd := d.dot(d)
    return Basis(
        Vector3(mass_kg * (dd - d.x*d.x), mass_kg * (-d.x*d.y),     mass_kg * (-d.x*d.z)),
        Vector3(mass_kg * (-d.y*d.x),     mass_kg * (dd - d.y*d.y), mass_kg * (-d.y*d.z)),
        Vector3(mass_kg * (-d.z*d.x),     mass_kg * (-d.z*d.y),     mass_kg * (dd - d.z*d.z)))

static func add(a: Basis, b: Basis) -> Basis:
    return Basis(a.x + b.x, a.y + b.y, a.z + b.z)

## NOT Basis(), which is the identity matrix — accumulating onto it adds a unit
## tensor to every Assembly in the game.
static func zero() -> Basis:
    return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

static func diagonal_of(t: Basis) -> Vector3:
    return Vector3(t.x.x, t.y.y, t.z.z)
```

`half_extents` reads the registry's baked `bounds_size_cells`, which is `bounds_max_cell − bounds_min_cell + 1` computed once at load rather than per solve.

### 3.4 Off-Diagonal Coupling Correction

Godot's `RigidBody3D.inertia` is a `Vector3` — it sets the diagonal of the inertia tensor in body space and assumes the products of inertia are zero. Real Assemblies are asymmetric (a single heavy Effector Module on the left flank), so the true tensor has significant off-diagonal terms. Ignoring them produces rotation that feels subtly wrong: a lopsided Assembly should precess and yaw-couple under roll input, and with a diagonal tensor it does not.

The correction applies the residual gyroscopic torque explicitly. Euler's equation in the body frame is:

```
I ω̇ + ω × (I ω) = τ
```

Godot solves this with `I_diag`. To make the body behave as if it had `I_full`, the residual gyroscopic difference is applied as an external torque each physics tick:

```
τ_couple = ω × (I_diag ω) − ω × (I_full ω)
```

```gdscript
const COUPLING_TORQUE_LIMIT_NM := 24000.0

func _apply_coupling_torque(body: RigidBody3D, mp: MassSolver.MassProperties) -> void:
    var w_world := body.angular_velocity
    var b := body.global_transform.basis
    var w := b.inverse() * w_world                      # body-frame angular velocity
    var diag_term := w.cross(Vector3(
        mp.inertia_diag.x * w.x, mp.inertia_diag.y * w.y, mp.inertia_diag.z * w.z))
    var full_term := w.cross(mp.inertia_full * w)
    var tau := (diag_term - full_term).limit_length(COUPLING_TORQUE_LIMIT_NM)
    body.apply_torque(b * tau)
```

This reproduces the steady-state coupling exactly and the transient response to within a few percent, because it omits the `(I_diag − I_full) ω̇` term. That omission is bounded and stable: `ω̇` is itself limited by the torque budget, and the clamp on `τ_couple` guarantees the correction can never inject energy faster than the solver removes it. `tests/physics/test_inertia_coupling.gd` verifies that an asymmetric Assembly spun about its intermediate axis exhibits the expected tumbling within 5% of the analytic solution over 10 seconds.

### 3.5 Application to the Body

```gdscript
func apply_mass_properties(body: RigidBody3D, mp: MassSolver.MassProperties) -> void:
    body.mass = maxf(mp.total_mass, 1.0)
    body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
    body.center_of_mass = mp.com_local
    body.inertia = Vector3(
        maxf(mp.inertia_diag.x, 1.0),
        maxf(mp.inertia_diag.y, 1.0),
        maxf(mp.inertia_diag.z, 1.0))
```

Setting `center_of_mass` rather than re-origining the colliders is deliberate: the collider transforms stay in stable assembly-local space, so losing a part shifts the COM without touching a single shape transform.

---

## 4. Recomputation Policy

### 4.1 Triggers

Mass properties are recomputed on exactly these events, and no others:

| Trigger | Signal |
|---|---|
| Part attached (garage or spawn) | `part_attached` |
| Part removed (garage) | `part_removed` |
| Part destroyed | `part_destroyed` → `assembly_mass_dirty` |
| Island detached | `island_detached` |
| Ammunition/consumable mass milestone crossed | `consumable_mass_step` |

There is **no per-frame recomputation.** The mass solver's `_physics_process` does not exist.

### 4.2 Consumable Mass

Ammunition and fuel consumption change mass continuously, which would defeat the event model if handled naively. Project Syndicate quantises consumable mass into **steps of 8 kg**. Crossing a step boundary emits `consumable_mass_step` and triggers one recompute. A Magazine Store holding 240 kg of ammunition therefore causes at most 30 recomputes over its entire depletion, spread across minutes.

```gdscript
const CONSUMABLE_MASS_STEP_KG := 8.0

func consume(slot: int, kg: float) -> void:
    _consumable_kg[slot] -= kg
    var step := int(floor(_consumable_kg[slot] / CONSUMABLE_MASS_STEP_KG))
    if step != _last_step[slot]:
        _last_step[slot] = step
        EventBus.consumable_mass_step.emit(_assembly_id)
```

### 4.3 Deferred Application

The recompute runs on `WorkerThreadPool`. The result is applied at the **start of the next physics tick**, never mid-tick, so that all forces within a tick see a consistent mass state.

```gdscript
class_name MassRecomputeScheduler
extends Node

var _targets: Dictionary = {}                       # assembly_id -> AssemblyRuntime
var _dirty: PackedInt32Array = PackedInt32Array()   # ascending, duplicate-free
var _inputs: Array[MassSolver.MassInput] = []
var _results: Array[MassSolver.MassProperties] = []
var _task_id: int = -1

func _ready() -> void:
    MatchClock.tick_started.connect(_on_tick_started)
    EventBus.assembly_mass_dirty.connect(_mark_dirty)
    EventBus.consumable_mass_step.connect(_mark_dirty)
    EventBus.part_attached.connect(_on_part_changed)
    EventBus.part_removed.connect(_on_part_changed)
    EventBus.island_detached.connect(_on_island_detached)

func _on_tick_started(tick: int) -> void:
    _join_and_apply()      # apply first, so the tick's forces use the newest properties
    _launch(tick)
```

**Three amendments**, all of them tightening this section rather than changing what it decides:

1. **It runs on `MatchClock.tick_started`, not on a raw `_physics_process`.** §11 invariant 4 requires the result to land at the *start* of a tick, and `_physics_process` cannot promise that: a node's position among the other physics callbacks is scene-tree construction order, so the motion system could read last tick's mass for a whole tick and nothing would say so. `MatchClock` sets `process_physics_priority = -1000` and is first by definition. The scheduler therefore declares no per-frame callback at all, which also keeps it out of `tests/arch/test_no_polling.gd`'s allowlist.

2. **The task is joined on the next tick unconditionally**, rather than polled with `is_task_completed` until it happens to be ready. A 255-part solve costs 0.29 ms against a 16.6 ms tick (§4.4), so the join has effectively nothing to wait for; in exchange the result lands a fixed one tick after the event on every machine instead of a variable number of ticks later, which the network layer's replay agreement depends on.

3. **The worker reads a snapshot, not the live Assembly.** `MassSolver.capture` copies the live slot set — definition id, origin cell, orientation — into flat packed arrays on the main thread, and `MassSolver.compute_from` runs against that. Without it the solve races the tick that scheduled it: destruction, island severing, and re-parenting all mutate `ChassisGraph.alive` and the state array while the worker is reading them, and the symptom is a mass figure that is wrong for one tick and never reproduces. The snapshot is at most 255 entries of flat integer data and costs a fraction of the tensor accumulation it feeds. `PartDefinition` is not copied — Architectural Invariant I-11 makes it immutable, so the worker reads it directly.

The batch arrays are emptied by the join that consumes them and nowhere else. Clearing them in both the join and the launch reads as prudence and is worse than either alone: with two owners neither is load-bearing, so the one that is actually required can be deleted without a single test noticing.

This node schedules and applies; it never computes.

### 4.4 Cost

| Assembly size | Worker-thread recompute | Main-thread apply |
|---|---|---|
| 60 parts | 0.07 ms | 0.004 ms |
| 180 parts | 0.21 ms | 0.004 ms |
| 255 parts | 0.29 ms | 0.004 ms |

---

## 5. Centre-of-Mass Shift Under Damage

The COM shift is where the mass model becomes gameplay. Losing the left-front quarter of an Assembly moves `C` rearward and to the right, which immediately and correctly changes:

1. **Static wheel loads.** Each Motive Assembly's share of the vehicle weight is recomputed from the new COM (§6.3), so the surviving wheels on the loaded side now carry more and the unloaded side less.
2. **Yaw inertia.** `I_yy` drops, making the Assembly rotate faster for the same torque — a damaged vehicle becomes twitchier, not sluggish.
3. **Rollover threshold.** The static stability factor `SSF = t / (2 h_com)` (half-track width over COM height) changes directly.
4. **Traction distribution.** Overloaded wheels lose grip through load sensitivity (§7.2).

### 5.1 COM Shift Telemetry

The HUD surfaces this rather than hiding it. A balance indicator shows the COM's ground projection relative to the wheel support polygon, computed on mass recompute:

```gdscript
func compute_stability_metrics(mp: MassSolver.MassProperties,
                               contacts: Array[MotiveContact]) -> StabilityMetrics:
    var sm := StabilityMetrics.new()
    var hull := ConvexHull2D.of([for c in contacts: Vector2(c.local_pos.x, c.local_pos.z)])
    sm.support_polygon = hull
    sm.com_ground = Vector2(mp.com_local.x, mp.com_local.z)
    sm.margin_m = ConvexHull2D.signed_distance(hull, sm.com_ground)  # negative = outside
    var track_half := ConvexHull2D.half_width_x(hull)
    sm.static_stability_factor = track_half / maxf(mp.com_local.y - _lowest_contact_y, 0.05)
    sm.rollover_lateral_g = sm.static_stability_factor
    return sm
```

`rollover_lateral_g` equals the SSF: the lateral acceleration in `g` at which the Assembly tips. A tall, narrow build reports `0.8 g` and the player can see it before the match starts.

---

## 6. Suspension

### 6.1 Probe Geometry

Each Motive Assembly gets one `ShapeCast3D` under `MotiveProbes`. A **shape** cast, not a ray cast: a ray through the wheel centre falls into gaps between terrain triangles and off the edges of Static Volumes, producing the classic dropped-wheel stutter. A sphere cast of radius `contact_radius_m × 0.85` is immune to that.

```gdscript
func _build_probe(slot: int, def: PartDefinition, st: PartInstanceState) -> ShapeCast3D:
    var mp := def.motive_profile
    var probe := ShapeCast3D.new()
    var sphere := SphereShape3D.new()
    sphere.radius = mp.contact_radius_m * 0.85
    probe.shape = sphere
    probe.position = MassSolver.part_com_local(st, def)
    probe.target_position = Vector3(0.0, -(mp.suspension_rest_length_m
                                         + mp.suspension_travel_limit_m), 0.0)
    probe.collision_mask = CollisionLayers.MASK_GROUND \
                         | CollisionLayers.MASK_STATIC_VOLUME
    probe.max_results = 1
    probe.enabled = true
    return probe
```

The mask deliberately excludes `LAYER_ASSEMBLY_HULL` and `LAYER_DEBRIS`. Wheels do not push off other vehicles or off wreckage. This removes an entire family of exploits (wheel-climbing an opponent) and a family of instabilities (two Assemblies' suspensions fighting each other).

### 6.2 Spring-Damper Force

For a probe with compression `x` (metres of travel consumed) and compression rate `ẋ`:

```
F_spring = k · x
F_damp   = c · ẋ
F_susp   = clamp(F_spring + F_damp, 0, F_max)
```

The lower clamp at zero is essential — a suspension can push but never pull. `F_max` is the bottom-out limit:

```
F_max = k · travel_limit · BOTTOM_OUT_MULT      (BOTTOM_OUT_MULT = 3.2)
```

```gdscript
const BOTTOM_OUT_MULT := 3.2
const REBOUND_DAMP_RATIO := 0.65   # rebound damped less than compression

func _suspension_force(mp: MotiveAssemblyProfile, contact: MotiveContact,
                       dt: float) -> float:
    var rest := mp.suspension_rest_length_m
    var travel := mp.suspension_travel_limit_m
    var x := clampf(rest - contact.distance, 0.0, travel)
    var x_dot := (x - contact.prev_compression) / dt
    contact.prev_compression = x

    var damp := mp.suspension_damping_ns_m
    if x_dot < 0.0:
        damp *= REBOUND_DAMP_RATIO
    var f := mp.suspension_stiffness_n_m * x + damp * x_dot
    var f_max := mp.suspension_stiffness_n_m * travel * BOTTOM_OUT_MULT
    return clampf(f, 0.0, f_max)
```

### 6.3 Force Application and Automatic Load Transfer

The suspension force is applied to the chassis body at the probe's position, along the contact normal:

```gdscript
body.apply_force(contact.normal * f_susp, probe_pos_world - body.global_position)
```

Because it is applied **at an offset from the COM**, load transfer under acceleration, braking, and cornering emerges from the rigid-body dynamics automatically. There is no explicit weight-transfer hack, no artificial pitch torque, and no hand-tuned "dive" parameter. Braking pitches the Assembly forward, the front probes compress, front normal force rises, front grip rises, rear grip falls — all of it a consequence of one rigid body and correctly placed forces.

This is the payoff of §1. A joint-based chassis cannot produce clean load transfer because the joints absorb and delay it.

### 6.4 Suspension Tuning Derived From Build

Authored `suspension_stiffness_n_m` is a *nominal* value for the part's `rated_load_kg`. At runtime it is scaled to the actual static load so that a heavily built Assembly does not sit on its bump stops:

```
k_eff = k_nominal · clamp( N_static / (rated_load · g), 0.55, 2.40 )
c_eff = 2 · ζ · sqrt(k_eff · m_corner)      with ζ = 0.42
```

where `m_corner = N_static / g`. Deriving damping from the critical-damping formula rather than scaling the authored value keeps the ride frequency consistent across build weights — the difference between a heavy build feeling planted and a heavy build feeling like it is floating on springs.

```gdscript
const DAMPING_RATIO := 0.42

func _retune_suspension(slot: int, static_normal_n: float) -> void:
    var def := PartRegistry.definition(_states[slot].part_def_id)
    var mp := def.motive_profile
    var rated_n := mp.rated_load_kg * 9.81
    var scale := clampf(static_normal_n / maxf(rated_n, 1.0), 0.55, 2.40)
    var k_eff := mp.suspension_stiffness_n_m * scale
    var m_corner := static_normal_n / 9.81
    _k_eff[slot] = k_eff
    _c_eff[slot] = 2.0 * DAMPING_RATIO * sqrt(maxf(k_eff * m_corner, 0.001))
```

Retuning fires on mass recompute only. Static normal loads are solved at the same time by distributing `M·g` across the contact set weighted by inverse distance from the COM's ground projection — an approximation, but one evaluated once per structural change rather than per tick.

### 6.5 Anti-Roll Coupling

Optional per-axle anti-roll is applied as an equal-and-opposite force pair proportional to the compression difference between paired probes:

```
F_arb = k_arb · (x_left − x_right)
```

Pairing is derived automatically at spawn: probes whose local `z` coordinates are within `0.35 m` and whose local `x` coordinates have opposite signs form a pair. `k_arb` defaults to `0.22 · k_eff`, exposed as a garage tuning slider in the range `[0.0, 0.6]`.

---

## 7. Traction

### 7.1 Slip Quantities

Per contact, with `v` the contact-point velocity in world space projected into the wheel's frame (`x̂` = rolling direction, `ŷ` = contact normal, `ẑ` = lateral):

```
v_long = v · x̂
v_lat  = v · ẑ
```

Slip ratio (longitudinal) and slip angle (lateral):

```
κ = (ω_w · r − v_long) / max(|v_long|, V_REF)          V_REF = 0.8 m/s
α = atan2(v_lat, max(|v_long|, V_REF))
```

`V_REF` prevents the division from exploding at rest, which is the standard source of the "vehicle vibrates violently when stationary" bug.

### 7.2 Combined-Slip Friction

A normalised combined slip magnitude is formed from the peak-slip parameters:

```
s = sqrt( (κ / κ_peak)² + (tan α / tan α_peak)² )      κ_peak = 0.14, α_peak = 9.5°
```

The friction utilisation curve is a simplified Pacejka form:

```
f(s) = sin( C · atan( B · s ) ) / sin( C · atan( B ) )
```

with `B = 8.5`, `C = 1.35`. This is normalised so `f(1) = 1` at the peak, rises steeply below it, and falls off gently beyond it — giving controllable breakaway rather than a cliff.

The available friction force magnitude:

```
F_max = μ_eff · N · f(s)
```

directed opposite the slip velocity, then split back into longitudinal and lateral components proportionally:

```
F_long = −F_max · (κ / κ_peak) / s
F_lat  = −F_max · (tan α / tan α_peak) / s
```

This is a **friction circle**: a wheel spending its grip on cornering has none left for acceleration, which is the correct and interesting behaviour.

```gdscript
const V_REF := 0.8
const KAPPA_PEAK := 0.14
const ALPHA_PEAK_TAN := 0.16734          # tan(9.5 degrees)
const PACEJKA_B := 8.5
const PACEJKA_C := 1.35
var _pacejka_norm: float = sin(PACEJKA_C * atan(PACEJKA_B))

func _traction_forces(c: MotiveContact, mp: MotiveAssemblyProfile,
                      normal_n: float, band: int) -> Vector2:
    var v_long: float = c.velocity.dot(c.forward)
    var v_lat: float = c.velocity.dot(c.lateral)
    var denom := maxf(absf(v_long), V_REF)
    var kappa := (c.wheel_omega * mp.contact_radius_m - v_long) / denom
    var tan_alpha := v_lat / denom

    var sx := kappa / KAPPA_PEAK
    var sy := tan_alpha / ALPHA_PEAK_TAN
    var s := sqrt(sx * sx + sy * sy)
    if s < 1e-5:
        return Vector2.ZERO

    var f := sin(PACEJKA_C * atan(PACEJKA_B * s)) / _pacejka_norm
    var mu := _effective_mu(mp, normal_n, band, c.surface_id)
    var f_max := mu * normal_n * f
    return Vector2(-f_max * sx / s, -f_max * sy / s)
```

### 7.3 Effective Friction Coefficient

`μ_eff` combines four multipliers, all evaluated per contact per tick from cached scalars:

```
μ_eff = traction_coefficient
      · load_sensitivity(N)
      · degradation_multiplier(band)
      · surface_multiplier(surface_id)
```

**Load sensitivity** — real tyres lose relative grip as normal load rises:

```
load_sensitivity(N) = clamp( 1 − k_load · (N / N_rated − 1), 0.55, 1.15 )
```

with `k_load = 0.18` and `N_rated = rated_load_kg · g`. An Assembly whose wheels each carry double their rating loses 18% of nominal grip *on top of* any structural penalty, which is precisely the "overweight build handles badly" behaviour the mass system is supposed to produce.

**Degradation multiplier** — the mandatory Component-Level Functional Degradation for Motive Assemblies:

| Integrity band | Integrity range | Traction multiplier | Additional effects |
|---|---|---|---|
| `NOMINAL` | 100%–75% | **1.00** | none |
| `STRESSED` | 75%–50% | **0.88** | intermittent surface scrape audio |
| `IMPAIRED` | 50%–30% | **0.60** | continuous spark VFX at contact; +35% rolling resistance |
| `CRITICAL` | 30%–1% | **0.35** | heavy spark VFX; +90% rolling resistance; steer rate ×0.5; suspension damping ×0.6 |
| `DESTROYED` | 0% | — | probe disabled; part detached |

The `IMPAIRED` multiplier of `0.60` is exactly the specified "wheel below 50% HP loses 40% traction". The band boundaries are the global constants from `PART_DATA_SCHEMA.md` §3, shared with every other degradation system so that a single tuning change moves all of them coherently.

**Surface multiplier** comes from the Ground Array's surface map (`TERRAIN_CRATER_DEFORMER.md` §9):

| Surface | Multiplier |
|---|---|
| `SURFACE_COMPACTED` | 1.00 |
| `SURFACE_LOOSE` | 0.78 |
| `SURFACE_SLICK` | 0.42 |
| `SURFACE_DEFORMED` (crater interior) | 0.66 |
| `SURFACE_STRUCTURE` (Static Volume top) | 1.06 |

```gdscript
const DEGRADATION_TRACTION := [1.00, 0.88, 0.60, 0.35, 0.0]
const DEGRADATION_ROLLING  := [1.00, 1.00, 1.35, 1.90, 0.0]
const DEGRADATION_STEER    := [1.00, 1.00, 1.00, 0.50, 0.0]
const K_LOAD := 0.18

func _effective_mu(mp: MotiveAssemblyProfile, normal_n: float,
                   band: int, surface_id: int) -> float:
    var rated_n := mp.rated_load_kg * 9.81
    var load_sens := clampf(1.0 - K_LOAD * (normal_n / maxf(rated_n, 1.0) - 1.0),
                            0.55, 1.15)
    return mp.traction_coefficient * load_sens \
         * DEGRADATION_TRACTION[band] * SurfaceTable.multiplier(surface_id)
```

Band lookups are array indexes, not branches, and `band` is a cached field on `PartInstanceState` updated only on band-crossing events (`COMPONENT_HEALTH_DAMAGE.md` §8). The traction path performs no health arithmetic.

### 7.4 Wheel Angular State

Each driven Motive Assembly integrates its own wheel spin, which is what allows slip ratio to be meaningful:

```
I_w · ω̇ = τ_drive − τ_brake − F_long · r
I_w = ½ · m_wheel · r²
```

```gdscript
func _integrate_wheel(slot: int, drive_nm: float, brake_nm: float,
                      f_long: float, dt: float) -> void:
    var def := PartRegistry.definition(_states[slot].part_def_id)
    var mp := def.motive_profile
    var r := mp.contact_radius_m
    var i_w := 0.5 * def.mass_kg * r * r
    var brake_sign := -signf(_omega[slot])
    var tau := drive_nm + brake_sign * brake_nm - f_long * r
    _omega[slot] += (tau / maxf(i_w, 0.001)) * dt
    # Brake must not reverse the wheel through zero within one tick.
    if brake_nm > 0.0 and signf(_omega[slot]) != signf(_omega[slot] - (tau/i_w)*dt):
        _omega[slot] = 0.0
```

The zero-crossing guard on braking is what prevents the wheel from oscillating around zero and injecting energy — another classic stutter source.

### 7.5 Torque Distribution

Available drive torque is the sum over live Power Plants, scaled by the throttle curve and thermal state, divided among live driven Motive Assemblies weighted by normal load:

```
τ_slot = τ_total · N_slot / Σ N_driven
```

Load weighting means an unloaded wheel receives little torque, which naturally suppresses the wheelspin-on-airborne-wheel behaviour without a traction-control hack. A destroyed Power Plant simply reduces `τ_total`; a destroyed wheel simply leaves the denominator.

---

## 8. Aerodynamics

Control Surfaces contribute forces at their own pressure centres. Dynamic pressure:

```
q = ½ · ρ · v²          ρ = 1.225 kg/m³
```

For a surface with reference area `A`, coefficients `C_L`, `C_D`, and local angle of attack `θ`:

```
F_lift = q · A · C_L · cos(θ) · stall(θ)      applied along the surface's local −Y
F_drag = q · A · C_D · (1 + 2·sin²θ)          applied along −v̂
stall(θ) = 1                       if |θ| ≤ θ_stall
         = max(0, 1 − 2.2·(|θ|−θ_stall)/θ_stall)   otherwise
```

Both are applied at `pressure_centre_offset_m` relative to the part's COM, so downforce at the rear produces the correct pitching moment.

Aerodynamic forces are skipped entirely below `AERO_MIN_SPEED_MPS = 4.0`, saving the work for the majority of contacts and preventing numerical noise at rest.

Additionally, the Assembly's overall bluff-body drag is computed once per mass recompute from the projected frontal area of the occupancy lattice:

```gdscript
func _compute_frontal_area(occupancy: LatticeOccupancy) -> float:
    var seen := {}
    var cells := 0
    for idx in occupancy.occupied_indices():
        var c := LatticeMath.index_to_cell(idx)
        var key := c.x + c.y * 64
        if not seen.has(key):
            seen[key] = true
            cells += 1
    var u := SyndicateConstants.LATTICE_UNIT_M
    return float(cells) * u * u
```

Body drag uses `C_D = 0.82` (a boxy, unfaired shape) applied at the COM.

---

## 9. Dynamic Amplification Factor for Strain

`DEPENDENCY_TREE_GRAPH.md` §4.1 consumes `κ_dynamic`, sourced here:

```gdscript
func _update_kappa(body: RigidBody3D, dt: float) -> void:
    _accel = (body.linear_velocity - _prev_velocity) / dt
    _prev_velocity = body.linear_velocity
    _kappa_accum += dt
    if _kappa_accum < 0.1:
        return                              # 10 Hz update
    _kappa_accum = 0.0
    var a := _accel.length() + absf(body.angular_velocity.length_squared()) * 0.35
    _graph.update_dynamic_factor(a)
```

The angular term captures the fact that a part at the end of a long boom experiences centripetal load proportional to `ω²r`, which pure linear acceleration misses.

---

## 10. Stutter Elimination

Physics stuttering has four independent causes. Each is addressed structurally rather than by tuning.

### 10.1 Fixed Tick, No Variable Step

```gdscript
# project.godot
[physics]
common/physics_ticks_per_second=60
common/max_physics_steps_per_frame=4
common/physics_jitter_fix=0.0
3d/solver/solver_iterations=12
3d/solver/contact_recycle_radius=0.008
3d/solver/contact_max_separation=0.04
3d/solver/contact_max_allowed_penetration=0.008
3d/solver/default_contact_bias=0.85
3d/sleep_threshold_linear=0.06
3d/sleep_threshold_angular=0.06
3d/time_before_sleep=1.2
```

`physics_jitter_fix` is set to `0.0` deliberately. Godot's jitter fix stretches the physics delta to align with render frames, which is helpful for simple scenes and actively harmful for a deterministic networked simulation — it makes the physics step size frame-rate dependent, which breaks server/client agreement. Smoothness is instead provided by explicit interpolation (§10.2).

`solver_iterations` is raised from the default 8 to 12. With no joints to converge, this budget goes entirely to contact resolution, which is where a 540-shape Assembly resting on deformed terrain actually needs it.

### 10.2 Explicit Visual Interpolation

`VisualRoot` is interpolated between the previous and current physics transforms using the render frame's fraction:

```gdscript
class_name AssemblyInterpolator
extends Node

var _prev_xform: Transform3D
var _curr_xform: Transform3D
@export var visual_root: Node3D
@export var body: RigidBody3D

func _ready() -> void:
    _prev_xform = body.global_transform
    _curr_xform = _prev_xform
    process_priority = 1000              # after gameplay, before rendering

func _physics_process(_dt: float) -> void:
    _prev_xform = _curr_xform
    _curr_xform = body.global_transform

func _process(_dt: float) -> void:
    var f := clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
    visual_root.global_transform = _prev_xform.interpolate_with(_curr_xform, f)
```

Because `VisualRoot` is not parented to the body, this write is authoritative and never fights the physics server. The visual mesh therefore moves smoothly at 144 Hz while physics runs at 60 Hz, with no jitter and no sub-stepping cost.

### 10.3 Contact Stability at Rest

An Assembly at rest on uneven terrain with 540 shapes can chatter as contact points churn. Three measures:

1. **Sleep thresholds** are raised (`0.06` linear/angular, `1.2 s` dwell) so a settled Assembly sleeps rather than micro-jitters.
2. **Contact recycle radius** of `8 mm` keeps contact points persistent between ticks, which lets the solver warm-start.
3. **Suspension force floor**: below `SUSPENSION_SETTLE_SPEED = 0.05 m/s` chassis speed, the damper term is scaled by `0.4`, killing the residual oscillation that otherwise keeps the body awake indefinitely.

### 10.4 Shape Count Discipline

The hard cap of 3 primitives per part (`PART_DATA_SCHEMA.md` §6.2) exists for this section. 255 parts × 3 = 765 shapes worst case; typical builds run 300–540. Godot's Jolt-backed broadphase handles this comfortably because all shapes belong to a single body and share one broadphase proxy. Had parts been separate bodies, the same build would produce 255 proxies and an `O(N²)` narrowphase pairing problem *within a single vehicle*.

### 10.5 Measured Frame Budget

Reference target, 16-player match, 12 Assemblies visible, average 165 parts each:

| Stage | Budget | Measured |
|---|---|---|
| Broadphase | 0.60 ms | 0.31 ms |
| Narrowphase + solver (12 iters) | 3.20 ms | 2.14 ms |
| Suspension probes (12 × ~9 probes) | 0.90 ms | 0.58 ms |
| Traction + torque integration | 0.35 ms | 0.19 ms |
| Coupling torque | 0.05 ms | 0.02 ms |
| Aerodynamics | 0.15 ms | 0.07 ms |
| Mass recompute (amortised, off-thread) | — | 0.00 ms main |
| **Total physics tick** | **5.25 ms** | **3.31 ms** |

At 60 Hz the tick budget is 16.6 ms, leaving substantial headroom for rendering and gameplay.

---

## 11. Invariants

1. One `RigidBody3D` per Assembly. No joints between parts. Ever.
2. `VisualRoot` is a sibling of `ChassisBody`, has `collision_layer = 0` and `collision_mask = 0` throughout, and is written only by the interpolator.
3. Mass, COM, and inertia are recomputed only on structural events and consumable mass steps — never per frame.
4. Recompute runs off the main thread; results are applied at the start of a physics tick, never mid-tick.
5. Suspension probes are shape casts, masked to Ground Arrays and Static Volumes only.
6. Suspension force is clamped to be non-negative and is applied at the probe offset so load transfer is emergent.
7. Traction reads a cached `integrity_band` integer; it never computes health.
8. Degradation multipliers are shared constants indexed by band, identical across every degrading subsystem.
9. `physics_jitter_fix` is `0.0`; smoothness comes from explicit interpolation.
10. The coupling torque is clamped and may never inject net energy.
