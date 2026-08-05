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

`RigidBody3D.inertia` is a `Vector3`: it sets the diagonal of the inertia tensor in body space and takes the products of inertia to be zero. Real Assemblies are asymmetric — a single heavy Effector Module on one flank — so the true tensor has significant off-diagonal terms, and discarding them produces rotation that feels subtly wrong. A lopsided Assembly should precess and yaw-couple under roll input, and with a diagonal tensor it does not: it reads as a vehicle that is weightless rather than as a missing term.

**The server integrates `I_diag ω̇ = τ` and applies no gyroscopic term at all.** That is measured, not assumed: `tests/physics/test_inertia_coupling.gd::test_the_server_applies_no_gyroscopic_term_of_its_own` spins an Assembly whose three principal moments differ by 15% about its **intermediate** axis — the configuration that tumbles fastest in reality — and the angular velocity is unchanged to seven significant figures after five simulated seconds. A free rigid body cannot do that.

So the whole gyroscopic term of Euler's equation `I ω̇ + ω × (I ω) = τ` has to be supplied as an external torque:

```
τ_couple = − ω × (I_full ω)
```

**Evaluated at the midpoint of the tick, not at its start.** The continuous torque is perpendicular to `ω` and does no work, but sampling it once per tick and holding it across the step does: measured on a 6 rad/s spin, explicit Euler added about **16%** of the rotational energy over five seconds, which §11 invariant 10 forbids outright. Stepping `ω` half a tick along `ω̇ = I_diag⁻¹ τ` and re-evaluating there costs one extra cross product and turns that into a **3% loss** over the same soak. A correction that bleeds a little energy cannot destabilise an Assembly; one that adds it spins a wreck up out of nothing, so the asymmetry is the right way round and the test asserts the gain bound tightly and the loss bound loosely.

```gdscript
const COUPLING_TORQUE_LIMIT_NM := 24000.0

func _apply_coupling_torque(dt: float) -> void:
    var mp := runtime.mass_properties
    if mp == null:
        return
    var b := runtime.body.global_transform.basis
    var w := b.inverse() * runtime.body.angular_velocity
    var half := w + _angular_accel(mp, w) * (dt * 0.5)
    var tau := _gyroscopic_torque(mp, half).limit_length(COUPLING_TORQUE_LIMIT_NM)
    runtime.body.apply_torque(b * tau)
```

The `(I_diag − I_full) ω̇` term is omitted: the server divides by the diagonal tensor whatever is handed to it, and correcting for that too would need the torque premultiplied by `I_diag I_full⁻¹`. The steady-state coupling is exact without it and the transient is within a few percent. The clamp is what guarantees the omission can never inject energy faster than the solver removes it.

> **What this section used to say.** It derived the correction as the *difference* between the diagonal and full gyroscopic terms — `τ_couple = ω × (I_diag ω) − ω × (I_full ω)` — on the stated premise that "Godot solves this with `I_diag`", meaning that the server integrated the full Euler equation using the diagonal tensor. It does not, so the first half of that expression was cancelling a term nothing produced. The premise survived because it is what a reader expects a physics engine to do, and it was only falsified when a test span a body about its intermediate axis and watched it refuse to tumble.

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

**The two floors are the engine's requirement and not a modelling choice.** `RigidBody3D.mass = 0.0` is refused outright, and `inertia = Vector3.ZERO` is accepted and means "derive it from the collision shapes" — the exact physics/visual coupling Invariant I-1 forbids. So both are floored. The consequence is §3.6's and §3.7's, and it is the reason those sections exist: an Assembly that has lost every part is a **one-kilogramme body still carrying every collider and every suspension probe the intact build had**. §3.6 takes the motion layer off it and §3.7 takes it out of the simulation.

### 3.6 Liveness

Invariant I-2 ends an Assembly when slot 0 is destroyed. **The motion layer stops with it: `MotiveSystem.step` applies §3.4's coupling torque and returns.** No family runs, no contacts are gathered, no anti-roll is applied, and no ruts are deposited.

The question this answers is the one §3.4 leaves open. That section keeps the coupling torque running on a wreck deliberately — it is a property of the mass distribution rather than of what the Assembly is being asked to do, and a tumbling hulk is exactly where an asymmetric tensor is most visible. It says nothing about the **families**, and for five sessions they kept running.

What that cost is measured in `tests/physics/test_wreck_settles.gd`:

| | Intact | One tick after the Core Module is destroyed |
|---|---|---|
| Chassis body mass | 1107 kg | **1.0 kg** (§3.5's floor) |
| Contacts being solved | 4 | 4 |

Losing slot 0 orphans every part, the detachment scheduler severs the islands, and the debris pool takes them — so the body the motion layer is still solving for holds nothing but the floor, while §6's springs and §7's friction are computed from the same authored `rated_load_kg` figures they were before. An ordinary suspension force on a gramme of body is an enormous acceleration. On the arena's fifteen metres of relief the capture that first showed doc 11 §16.2's end card recorded the remains going from **17.3 m/s at the conclusion to 92.0 m/s fifty frames later**, climbing and crossing the basin, as the last thing a player sees.

Three things are worth stating about the shape of the rule.

- **It is a liveness test on slot 0, read from the part.** `AiDriver` already reads it the same way and for the same reason: a flag a system keeps for itself is a flag that can disagree with `DamageResolver`, which is the one authority on integrity.
- **It is not "freeze the body".** The wreck still falls, still rolls, still takes impacts, and still tumbles under §3.4. What stops is the layer that was pushing it, and nothing else.
- **A flat fixture cannot see it.** With a neutral control record on level ground the residual forces are roughly vertical and the remains do slow down, which is why a green suite never caught it. The slope is what turns them into a direction. So the assertion is a law rather than a speed: a terminated Assembly held at full throttle from rest does not move.

### 3.7 An Empty Body Is Not Simulated

§3.6 stops the motion layer. It does not stop the body, and it says so: the wreck still falls, still rolls, still takes impacts, and still tumbles under §3.4. That is the right rule for a terminated Assembly that still has parts on it, and this section does not weaken it.

One condition further along the same sequence, it stops being the right rule. Losing the Core Module orphans every part; §5.5 of `DEPENDENCY_TREE_GRAPH.md` severs the islands and §6 hands them to the debris pool. What is left is a body with **no live parts at all**, and §3.5's two floors then describe it as a one-kilogramme object with an inertia of one about every axis.

Those floors are the engine's requirement — a zero mass is refused outright and a zero inertia means "derive it from the collision shapes", the exact coupling Invariant I-1 forbids — and they are not a claim about the world. An Assembly that has lost every part is not a light object. It is not an object. Leaving it dynamic hands the solver a hull-sized collider on a gramme of mass, and anything that brushes it launches it: measured climbing past 27 m/s under the end card, which is the last thing a player sees and is exactly what `RESPONSIVE_GARAGE_UI.md` §16.2 decides must not happen. The hulk is the visible record of the fight and it stays where it fell.

**So a solve that finds no live parts freezes the body where it stands**, with `freeze_mode = FREEZE_MODE_STATIC` and both velocities zeroed. It keeps its transform, its remaining geometry, and its visibility to every query (a frozen body is still hit by a swept ray and still resolves damage), so it goes on being the obstacle `CLAUDE.md` §5.1's `MASK_ASSEMBLY_HULL` expects. What it stops doing is responding to impulses, which is the whole of what was wrong with it.

**The ordering is what makes this safe rather than merely correct.** The solve that finds no parts is the one triggered by the last island detaching (§4.1), and by the time it lands, `DEPENDENCY_TREE_GRAPH.md` §6 has already read this body's linear and angular velocity to give each fragment the `v + ω × r` it left with. Freezing any earlier would drop every fragment straight down.

It is **reversible**. `COMPONENT_HEALTH_DAMAGE.md` §10's repair path is not written, and a one-way door left in the mass layer is how it arrives broken: a solve that finds parts again returns the body to the simulation on the same test.

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

> **Locomotion dispatch.** Sections 6 and 7 describe how a **ground** Motive
> Assembly moves an Assembly. They are one of four families. `MotiveSystem`
> selects the family by `PartEnums.LOCOMOTION_OF_MOTIVE_KIND[kind]` — a single
> array index, never a branch on `MotiveKind` — and dispatches to §6+§7 for
> `GROUND`, to **§12** for `ROTARY`, to **§13** for `AMBULATORY`, and to
> **§14** for `TRACKED`. Everything outside this document sees one Motive
> Assembly class producing forces on one rigid body; only the force
> *derivation* differs. §6.0 states what the four families are required to have
> in common.
>
> §14 is the family that reuses the most of §6 and §7: a road station's
> suspension force is `_suspension_force` unchanged and its friction is the same
> Pacejka curve. That reuse is only available because both are pure static
> solvers taking a contact and a profile, which is worth preserving the next
> time one of them is tempted to reach for state.

### 6.0 The Contract Every Family Meets

A locomotion family is free to compute its forces however its physics demands,
and is bound by exactly five rules. They exist because the rest of the project
— mass, strain, damage, network, garage — was written against a Motive Assembly
that behaves like §6 and §7, and a family that broke any of these would need all
of it changed.

1. **It contributes only `apply_force` and `apply_torque` on `ChassisBody`.**
   No family may add a body, a joint, or a collision shape. Invariant I-3 is not
   relaxed for a walker whose legs look like they ought to be jointed, and §13.1
   explains why they need not be. §16 draws the result and is deliberately
   **not** a family: it runs once after the dispatch, so this rule stays
   literally true of every solver in §6, §12, §13 and §14.
2. **It reads the cached band multiplier array and never integrity.** Invariant
   I-5. A rotor at `IMPAIRED` loses thrust by indexing `DegradationTable`, the
   same way a wheel loses traction.
3. **It writes no state the mass solver owns.** Mass, COM, and inertia come from
   §3 and change only on structural events. A family carrying per-limb or
   per-disc state keeps it in its own flat arrays, indexed by slot.
4. **It is deterministic given (contacts, control input, its own state).** No
   global RNG, no wall-clock, no iteration over unordered keys. Invariant I-9,
   and the network layer replays these forces.
5. **Its per-slot state is bounded and slot-indexed.** `MAX_MOTIVE_PER_ASSEMBLY`
   is 24 for every family; a rotary or ambulatory build gets no larger budget
   than a wheeled one.

Rule 1 is the load-bearing one. It is what lets a rotorcraft take blast damage,
shed a wing panel, re-solve its mass, and keep flying with the new COM — without
a line of code in the damage or mass layers knowing that rotors exist.

**No family is asked for a force on a terminated Assembly.** §3.6 is enforced
above the dispatch rather than inside each family, so a sixth rule about what a
family does with a wreck would be a rule no family could reach.

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

**Where this runs.** The constructor is `AssemblyRuntime._build_motive_probes`, called from `attach_part`, so a probe set exists for exactly the parts whose colliders exist and is built from the same `PartInstanceState` (§2's tree, and doc 04 §6's release path disables both together). Probes are named `probe_s<slot>_<station>`: §2's `probe_s014` predates §14's road stations, and a tracked part needs one name per station. `MotiveContact.probe` holds the reference, bound once when the Motive Assembly registers — a part cannot move relative to the chassis, so resolving a formatted node name per tick would be a string build and a `NodePath` construction inside the tick loop for a node that is fixed from placement to destruction.

**Rest length is measured from the probe origin, and the probe origin is the contact centre.** §6.2 reads compression as `rest_length − distance`, and `distance` is from `part_com_local` down to the surface. A Motive Assembly resting on its own authored collider puts that distance at one `contact_radius_m`. **`suspension_rest_length_m` must therefore exceed `contact_radius_m`**, by the static sag the build is meant to settle at, or compression clamps to zero on every contact, the normal force is zero, `_apply_traction` returns before applying anything, and the Assembly rests on its colliders with the suspension inert and no drive force reaching the ground at all.

**Resolved: `suspension_rest_length_m = contact_radius_m + suspension_travel_limit_m`.** Both shipped ground rows were authored at 0.32 m against a 0.50 m rolling radius, and `tests/physics/test_ground_assembly.gd` measured the consequence on a four-contact Assembly settled on real ground: zero compression and zero normal force on every contact, and a full-throttle displacement of zero. The rows are now 0.74 m. The convention places full droop exactly one travel above the surface and makes the part's own collider the bump stop, so the two authored numbers determine the third and there is no third number to get wrong. §14 rule 23 of document 01 enforces the hard requirement — rest length strictly greater than contact radius — rather than the convention, because a shorter travel is a legitimate tuning choice and an inert spring is not.

> **The same trap has an ambulatory form and §13 carries it.** A limb's `suspension_*` fields are all zero by rule 21, so sizing its sweep from them gives a zero-length cast: the contact never grounds, the foot is never planted, and the Assembly stands still with a healthy-looking gait clock running. An ambulatory probe sweeps `leg_length_m` from the hip instead. Neither case announces itself — every intermediate value is a legal number that some airborne contact produces legitimately.

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

`MotiveSystem._rebuild_axle_pairs` runs on every registration change rather than per tick — pairing is a property of where the builder put the Motive Assemblies, and they do not move. Each contact is taken at most once and both loops run ascending by slot then station, so the pair set is a deterministic function of the build (Invariant I-9). The force is applied after the families have solved, because it differentiates the compressions they wrote this tick; running it first would couple the previous tick's roll into this one. Losing one end of an axle re-derives the set and leaves the survivor unpaired, rather than pushing against a probe that has left with a severed island.

---

## 7. Traction

### 7.0 Steer Angle

The contact frame of §7.1 is the **wheel's**, not the chassis's, and a steered wheel's rolling direction is not the hull centreline. `MotiveSystem` carries one steer angle per slot, advances it toward the commanded lock at the authored rate, and rotates that slot's contact frame about the contact normal before the friction solve:

```
target = clamp(steer_command, −1, +1) · max_steer_angle_deg
angle  = move_toward(angle, target, steer_rate_deg_s · band_multiplier · dt)
x̂, ẑ  = rotate(x̂, ẑ) about the contact normal by −angle
```

Three things follow, and each is why it is done here rather than as a yaw torque.

1. **The lateral force stays a genuine slip-angle force.** The wheel is pointed somewhere, the patch slides, and the Assembly turns because of what that slide produces. A model that applied yaw directly would turn just as well on ice.
2. **`DegradationTable.MOTIVE_STEER` finally has a consumer.** It scales the rate, so a Motive Assembly at `CRITICAL` turns at half speed and the Assembly understeers rather than failing outright.
3. **`WHEELED_FIXED` needs no second code path.** It authors `max_steer_angle_deg = 0` and falls through unchanged.

The rotation is about the **contact normal** rather than the chassis up, so a wheel on a camber steers in the plane it is standing on. It is negated because a positive rotation about the surface normal carries the forward axis to the left, and `RESPONSIVE_GARAGE_UI.md` §7.2 fixes positive steer as right on every input device.

**An Assembly on which every wheel steers does not turn — it crabs.** Four contact patches pointing the same way translate the hull sideways with its nose still forward, and there is no couple about the vertical axis at all. A yaw needs the axles to disagree, which is what `mot.wheeled.fixed_rear.t2` is for: a steering build is `WHEELED_STEERED` at the front and `WHEELED_FIXED` at the back, and the difference between the two rows is one authored number. `tests/physics/test_ground_assembly.gd` measured the crab before that part existed.

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

split back into longitudinal and lateral components in proportion to the slip that produced them:

```
F_long = +F_max · (κ / κ_peak) / s
F_lat  = −F_max · (tan α / tan α_peak) / s
```

This is a **friction circle**: a contact spending its grip on cornering has none left for acceleration, which is the correct and interesting behaviour.

**The two signs differ, and the asymmetry is real rather than a typo.** Both components oppose the contact patch's sliding, but §7.1 defines the two slip quantities with opposite senses. `κ` is `(ω·r − v_long)`, which is already the *negative* of the patch's slip velocity — a contact turning faster than the ground slides its patch backwards and is pushed forwards — so a driven contact has positive `κ` and must produce positive `F_long`. `tan α` follows `v_lat` directly, with no such inversion, so a contact sliding right is pushed left and keeps its minus sign.

§7.4's equation is the check: `I_c · ω̇ = τ_drive − τ_brake − F_long · r` only makes sense with `F_long` positive under drive, since that term is the ground *retarding* the spin-up of a driven contact.

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
    var kappa := (c.contact_omega * mp.contact_radius_m - v_long) / denom
    var tan_alpha := v_lat / denom

    var sx := kappa / KAPPA_PEAK
    var sy := tan_alpha / ALPHA_PEAK_TAN
    var s := sqrt(sx * sx + sy * sy)
    if s < 1e-5:
        return Vector2.ZERO

    var f := sin(PACEJKA_C * atan(PACEJKA_B * s)) / _pacejka_norm
    var mu := _effective_mu(mp, normal_n, band, c.surface_id)
    var f_max := mu * normal_n * f
    return Vector2(f_max * sx / s, -f_max * sy / s)
```

> **What this section used to say.** It wrote both components as negative, and the code block above carried the negative longitudinal sign for four sessions after the prose was corrected — so a reader following the code implemented an inverted throttle while a reader following the prose did not. It is wrong in a way that is invisible until something is asked to move: with a negative `F_long`, pressing the accelerator decelerates the Assembly. §7.2 and §7.4 disagreed, §7.4 was right, and the conflict was undetectable while nothing implemented either.

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

### 7.4 Contact Angular State

Each driven Motive Assembly integrates its own contact spin, which is what allows slip ratio to be meaningful:

```
I_c · ω̇ = τ_drive − τ_brake − F_long · r
I_c = ½ · m_contact · r²
```

```gdscript
func _integrate_contact(slot: int, drive_nm: float, brake_nm: float,
                        f_long: float, dt: float) -> void:
    var def := PartRegistry.definition(_states[slot].part_def_id)
    var mp := def.motive_profile
    var r := mp.contact_radius_m
    var i_c := 0.5 * def.mass_kg * r * r
    var brake_sign := -signf(_omega[slot])
    var tau := drive_nm + brake_sign * brake_nm - f_long * r
    _omega[slot] += (tau / maxf(i_c, 0.001)) * dt
    # Brake must not reverse the contact through zero within one tick.
    if brake_nm > 0.0 and signf(_omega[slot]) != signf(_omega[slot] - (tau/i_c)*dt):
        _omega[slot] = 0.0
```

The zero-crossing guard on braking is what prevents the contact from oscillating around zero and injecting energy — another classic stutter source.

> **Open defect — the integration of this balance is unstable, and rolling resistance is not in it.** Diagnosed and measured in session 32, deliberately not repaired in it. The balance above is right; what follows is about the step that integrates it.
>
> `F_long` is a very stiff function of `ω` near the rolling condition. Differentiating §7.2 through §7.1's two divisions:
>
> ```
> dF_long/dω = μ·N · f'(0) / κ_peak · r / max(|v_long|, V_REF)
> f'(0) = C·B / sin(C·atan(B)) = 12.415
> ```
>
> At the shipped `mot.wheeled.allroad.t2` figures — `I_c = 8.5 kg·m²`, `r = 0.5 m`, `μ = 1.05`, about 5 kN of load under a settled 1107 kg build — that is `2.9e5 N per rad/s`, so `dω̇/dω ≈ −1.7e4 s⁻¹` and explicit Euler is stable only below **117 µs**. This project runs a fixed 16.7 ms tick (§10.1). **The step is a factor of 142 outside its own stability limit**, and the lateral axis is stiffer still, because §7.1 floors its denominator at `V_REF` and a hull creeping sideways at 0.05 m/s already draws most of a friction budget.
>
> It does not diverge, because §7.2's curve saturates. It settles into a limit cycle. Measured on a build standing still on level ground with no throttle and no brake: `ω` reverses **every single tick** — +0.81, −4.29, +0.90, −4.43, +0.78, −4.44 rad/s — with the slip ratio swinging between +0.56 and −2.95 against a peak of 0.14, and two of the four contacts reading zero load throughout because the hull is rocking on the other two. That is §10's stutter arriving from the one place §10 does not look. What a player sees is the parked Assembly that shivers, wanders two to three metres over an engagement, and never comes to rest.
>
> **The repair is known, and it is not a smaller step, a softer curve, or a damping term.** It was built twice and reverted twice, and both wrong turns are recorded because each of them looks correct on paper.
>
> The scheme that works has three parts:
>
> 1. **Step the slip velocity, not the rate.** `u = ω·r − v_long` is the quantity the friction actually depends on, and `ω = (v_long + u) / r` is read back off it afterwards, so the contact follows an accelerating hull for free.
>
>    ```
>    u' = u + dt · ( r·τ/I_c − F_long · A ) / ( 1 + dt · A · k )
>    A  = r²/I_c + 1/m_share          # reciprocal reduced mass of the slip
>    ```
>
> 2. **Take `k` as the chord `|F|/|u|`, never the tangent at zero.** The tangent bounds every slope and is the natural choice; it also over-damps a contact far from the rolling condition by a factor of **317**, so one knocked to a slip of −0.05 m/s takes forty ticks to recover and drags kilonewtons the whole time. An implicit factor is a statement about how fast the state may move, so an overestimate is not conservative — it is a brake nobody meant to fit.
>
> 3. **Cap any friction force that would reverse the slip it opposes**, on both axes, answering instead with the force that lands the slip exactly on zero — the contact has stuck. On the lateral axis the arithmetic collapses to `|v_lat| · m_share / dt`, and that axis is the one that decides whether a stationary Assembly stays put. Both caps only ever *reduce* a force, so neither can inject energy (§11 invariant 10); both are exact at the transition rather than asymptotic; and both are silent under drive, so §7.6's launch and wheelspin behaviour is untouched.
>
> **The wrong turn worth naming**: damping `ω` implicitly instead of the slip. It is unconditionally stable and kills the limit cycle exactly as intended, and the fictitious inertia that damps the residual also resists a contact genuinely spinning up with an accelerating hull. Full throttle measured **0.20 m/s**.
>
> In isolation the scheme measures well — full throttle 6.06 m/s², quarter throttle 3.75 m/s over 150 ticks, and a build set rolling at 0.4 m/s actually comes to rest instead of coasting for ever. **In the game it does not, and the reason is not in this section.** With the integrator corrected, the shipped build produces 0.09 m/s under full throttle and a porpoising hull, because **two of its four contacts carry no load at all** — it has been standing on two wheels for the life of the project, and §7.4's chatter was producing enough force to hide it. `HANDOFF.md` §3.1.1 owns that, and it has to be closed first: on a two-wheeled stance a correct integrator looks like a broken one.
>
> `tests/physics/test_rest_stability.gd` measures the defect and is asserted as it fails.
>
> **Rolling resistance goes in with the repair and not before.** It is authored per part in doc 01 §7.2, given a degradation column in §7.3 above, implemented as `TractionSolver.rolling_resistance_n`, and called by nothing, so a coasting contact has no dissipation of any kind — §7.2's friction drives the slip toward zero and produces nothing there. It belongs in `τ` as a torque opposing the spin, summed with the brake before the sign is taken so neither is applied in the direction the other resists, and covered by the same zero-crossing guard. On its own, inside an unstable step, it is a small correct term inside a large wrong one.

**Amendment — naming.** This section originally wrote `wheel_omega`, `m_wheel`, and `_integrate_wheel`. `CLAUDE.md` §8 prohibits *wheel* in identifiers, and §7.1's own contact frame already uses the neutral vocabulary. The conflict was invisible while nothing implemented the section; it surfaced the moment the traction solver was written, and the document was corrected rather than the code allowed to diverge from it. `MotiveContact.contact_omega` is the field name throughout. The prose retains the word where it is explaining a physical intuition, which §8 permits and which is the same latitude §10.3 of document 01 already takes with its `mot.wheeled.*` family tags.

### 7.5 Torque Distribution

Available drive torque is the sum over live Prime Movers, scaled by the throttle curve and thermal state, divided among live driven Motive Assemblies weighted by normal load:

```
τ_slot = τ_total · N_slot / Σ N_driven
```

Load weighting means an unloaded wheel receives little torque, which naturally suppresses the wheelspin-on-airborne-wheel behaviour without a traction-control hack. A destroyed Prime Mover simply reduces `τ_total`; a destroyed wheel simply leaves the denominator.

---

### 7.6 Traction Control

Two loops, both acting **through the contacts**. Neither applies a force of its own.

```
# Slip limiting, per driven contact
allowed = TARGET_SLIP_RATIO · max(|v_long|, LAUNCH_REFERENCE_MPS)
excess  = max(|ω·r − v_long| − allowed, 0)
scale   = lerp(1, 1 / (1 + excess · SLIP_GAIN), authority)
τ_drive ← τ_drive · scale

# Yaw control, per Assembly
ω_target = −v_long · tan(δ) / wheelbase          # bicycle model
ω_target = clamp(ω_target, ±GRIP_YAW_MARGIN · μ · g / |v|)
error    = deadband(ω_y − ω_target, YAW_DEADBAND_RAD_S)
τ_brake  = min(|error| · YAW_GAIN_NM_PER_RAD_S · authority,
               brake_torque_nm · MAX_BRAKE_FRACTION)   on the flank sign(error)
```

| Constant | Value |
|---|---|
| `TARGET_SLIP_RATIO` | 0.14 |
| `LAUNCH_REFERENCE_MPS` | 5.0 |
| `SLIP_GAIN` | 1.2 |
| `YAW_GAIN_NM_PER_RAD_S` | 2600.0 |
| `YAW_DEADBAND_RAD_S` | 0.10 |
| `MAX_BRAKE_FRACTION` | 0.55 |
| `MIN_YAW_CONTROL_SPEED_MPS` | 1.5 |
| `GRIP_YAW_MARGIN` | 0.95 |

**An electronic aid may not apply a force the tyres could not.** A yaw controller that called `apply_torque` would turn an Assembly just as briskly on ice, on a slope, or with two wheels in the air, and would keep working after the contacts it is managing had stopped touching anything. Modulating one flank's brakes produces the same yaw moment through the same patches the driver is using, so it fades out exactly when grip does. This is what a real stability system does and it costs one extra term in §7.2's brake torque.

**The allowance is a slip velocity at low speed and a slip ratio once rolling.** §7.1 divides by `max(|v|, V_REF)`, so at a standstill any rotation at all reads as enormous slip; a limiter that believed the ratio would cut a stationary Assembly's torque to nothing and it would never move. Flooring the road speed at `LAUNCH_REFERENCE_MPS` turns the law into launch control below 5 m/s and into ordinary slip limiting above it, in one `maxf` rather than a second mode.

**The aid is an authority in `[0, 1]`, not a flag**, carried on `ControlInput` beside the throttle. The limiter is a `lerp` toward the managed torque, so 0.5 is a real intermediate state. At 0.0 the driver gets every newton-metre the Prime Movers make, wheelspin included — which is the only way to get a burnout out of a build with this much torque, and `tests/physics/test_ground_assembly.gd` asserts both sides of that switch against each other rather than either alone.

**GROUND only, deliberately.** A tracked Assembly steers *by* making its flanks disagree (§14.2), so a yaw controller that removed the disagreement would remove its steering. A rotary or ambulatory Assembly has no slip ratio to limit. The boundary is recorded here rather than left to be rediscovered by whoever notices a tracked build that will not pivot.

**What it fixes.** Deep slip is unstable by construction: past the peak of the §7.2 friction curve, more slip means less force, so once one flank hooks up before the other the Assembly yaws away and keeps yawing. Holding both patches inside the allowance is what stops the pull; the yaw loop trims what is left. Measured on the four-contact fixture, full throttle wandered about 20° in two and a half seconds with the aid off and holds inside 8° with it on.

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

Invariants 11 to 18 govern the rotary, ambulatory, and tracked families defined
in §12, §13, and §14, which follow this section. They are placed after it rather
than before because renumbering §11 would invalidate the "§11 invariant N"
references already written into `AssemblyRuntime`, `AssemblyInterpolator`, and
`MassRecomputeScheduler`.

1. One `RigidBody3D` per Assembly. No joints between parts. Ever.
2. `VisualRoot` is a sibling of `ChassisBody`, has `collision_layer = 0` and `collision_mask = 0` throughout, and **its own transform** is written only by the interpolator. The per-part nodes beneath it carry the part's placement pose, displaced for a Motive Assembly by §16's contact geometry. Nothing under `VisualRoot` is ever read by the simulation, which is what keeps that a presentation write rather than a second owner of the Assembly's pose.
3. Mass, COM, and inertia are recomputed only on structural events and consumable mass steps — never per frame.
4. Recompute runs off the main thread; results are applied at the start of a physics tick, never mid-tick.
5. Suspension probes are shape casts, masked to Ground Arrays and Static Volumes only.
6. Suspension force is clamped to be non-negative and is applied at the probe offset so load transfer is emergent.
7. Traction reads a cached `integrity_band` integer; it never computes health.
8. Degradation multipliers are shared constants indexed by band, identical across every degrading subsystem.
9. `physics_jitter_fix` is `0.0`; smoothness comes from explicit interpolation.
10. The coupling torque is clamped and may never inject net energy.
11. A locomotion family contributes only `apply_force` and `apply_torque` on `ChassisBody`. No family adds a body, a joint, or a collision shape (§6.0).
12. Family selection is `LOCOMOTION_OF_MOTIVE_KIND[kind]`, an array index. No subsystem outside `MotiveSystem` branches on `MotiveKind`.
13. Rotor thrust is applied along the tilted disc axis at the disc's own offset, so a rotor forward of the COM pitches the Assembly. Cyclic is limited on the resultant deflection, never per axis.
14. A rotor's reaction torque is `spin_sign · torque_reaction_ratio · Q` and is applied about the disc axis. An Assembly whose reaction torque exceeds its yaw authority is legal, flyable only with an opposed disc, and reported by the garage rather than prevented.
15. A limb applies force only while its phase is in stance and only along the hip-to-planted-foot vector, clamped non-negative and bounded by `max_foot_force_n`. Horizontal force is bounded by foot friction; exceeding it slides the plant point rather than adding grip.
16. Gait phase assignment is a deterministic function of the limb set's geometry and slot indices, identical on server and client, computed once per structural change.
17. A tracked Motive Assembly steers only by differential drive. No tracked kind has a steer angle, and its road stations are derived from `patch_length_m` and `road_stations`, never authored as a list.
18. Slew resistance is bounded by `SLEW_REFERENCE_RAD_S` and may only oppose an existing yaw rate. It is a resistance, never a brake, and can never reverse the sign of `ω_y`.

---

## 12. Rotor Lift and Tilt

A `ROTOR_DISC` Motive Assembly is a thrust source with a steerable axis. It
produces one force and up to two torques on `ChassisBody` and nothing else. It
runs no probe, touches no ground, and has no contact — which makes it, of the
three families, by far the cheapest per tick.

### 12.1 Disc State

```gdscript
class_name RotorDiscState
extends RefCounted

var slot: int = SyndicateConstants.INVALID_SLOT
var omega_rad_s: float = 0.0        # current angular rate; spools toward command
var collective_deg: float = 0.0     # current blade pitch, rate-limited
var cyclic_deg: Vector2 = Vector2.ZERO   # x = pitch deflection, y = roll deflection
var last_thrust_n: float = 0.0      # telemetry and the HUD lift meter
var last_shaft_w: float = 0.0       # feeds the power draw of §12.5
```

One per rotary Motive Assembly, in a flat array indexed by the same ordering the
ground family uses for its contacts. Nothing here is read by any other system.

### 12.2 Thrust

Momentum theory, with the disc area from the profile's own radius:

```
A = π · disc_radius_m²
T = C_T · ρ · A · (Ω R)² · (θ_collective / θ_collective_max)
```

The collective term is signed and normalised against the profile's **maximum**
collective, which is what `thrust_coefficient` is quoted at. A negative
collective therefore produces negative thrust — the disc pushes along its own
`−axis`, which is how a rotorcraft holds itself down against a gust, and is why
`collective_limit_deg.x` is authored negative rather than clamped at zero.

`ρ` is `SyndicateConstants.AIR_DENSITY_KG_M3`, shared with §8 for the reason
document 01 §3 gives.

Three regime multipliers modify `T`. All three are continuous, none has a
threshold that snaps, and each exists because its absence produces a specific
complaint:

```
ground_effect  = 1 + gain_ge · max(0, 1 − h / (ground_effect_radii · R))
translational  = 1 + gain_tl · min(1, v_horizontal / translational_lift_mps)
vortex_ring    = 1 − loss_vr · clamp(v_descent / vortex_ring_descent_mps, 0, 1)
                       · (1 − min(1, v_horizontal / translational_lift_mps))

T_effective = T · ground_effect · translational · vortex_ring
             · DegradationTable.MOTIVE_TRACTION[band]
```

- **Ground effect** is why a heavy rotorcraft can lift off but cannot climb out.
  Without it, hovering a metre above a Ground Array feels identical to hovering
  at two hundred, and the player never learns that the disc is working.
- **Translational lift** is why forward flight is more efficient than a hover,
  and is what makes a running takeoff a real technique rather than a cosmetic
  one.
- **Vortex ring state** is the punishment for descending vertically at speed
  into the disc's own downwash. The `(1 − v_horizontal/…)` factor is the escape:
  fly forward and it releases immediately, which is the actual recovery
  technique and is discoverable without a tutorial.

The band multiplier is `MOTIVE_TRACTION`, reused rather than given a rotary
column of its own. A rotor at `IMPAIRED` loses 40% of its thrust, exactly as a
wheel at `IMPAIRED` loses 40% of its grip. Invariant I-5 wants one table, and
splitting it so that the two families could drift apart would be a balance
liability, not a modelling gain.

### 12.3 Tilt

The disc axis in assembly space is the part's local `+Y` under its lattice
orientation:

```
axis_assembly = OrientationTable.basis_for(orientation_index) * Vector3.UP
```

Cyclic deflects the thrust vector away from that axis. The two components are
**not** clamped independently: a swashplate's authority is a cone, so the
resultant deflection is what `cyclic_limit_deg` bounds.

```gdscript
static func thrust_direction(orientation_index: int, cyclic_deg: Vector2,
                             limit_deg: float) -> Vector3:
    var b := OrientationTable.basis_for(orientation_index)
    var d := cyclic_deg.limit_length(limit_deg)      # cone, not box
    var dir := Vector3.UP
    dir = dir.rotated(Vector3.RIGHT, deg_to_rad(d.x))    # pitch about local X
    dir = dir.rotated(Vector3.BACK, deg_to_rad(d.y))     # roll about local Z
    return (b * dir).normalized()
```

Clamping per axis instead would let a stick held to a corner produce
`sqrt(2) × limit` of deflection, which is the classic diagonal-is-faster bug and
is immediately exploitable in a game where tilt is how you accelerate.

Thrust is applied **at the disc's own position**, not at the COM:

```gdscript
body.apply_force(thrust_dir_world * t_effective, disc_pos_world - body.global_position)
```

This is the same decision §6.3 makes for suspension and it buys the same thing:
a disc mounted forward of the centre of mass pitches the Assembly nose-down when
it lifts, so rotor placement is a real design problem with a real wrong answer,
and no explicit pitching-moment term exists anywhere in the code.

### 12.4 Reaction Torque and Yaw

A powered disc drags air around with it and the airframe feels the opposite:

```
Q = C_Q · ρ · A · (Ω R)² · R
τ_reaction = −spin_sign · torque_reaction_ratio · Q · axis_world
τ_yaw      = yaw_command · yaw_authority_nm · axis_world
```

`torque_reaction_ratio` is `0.0` for a coaxial disc, whose counter-rotating half
cancels the reaction inside the part, and `1.0` for a lone main disc, which
transmits all of it. The sum over an Assembly is what decides whether it can
hold a heading:

```
Σ (spin_sign_i · torque_reaction_ratio_i · Q_i)   must be coverable by   Σ yaw_authority_nm_i
```

Two `main_single` discs with opposite `spin_sign` cancel. One alone does not,
and the Assembly rotates under its own torque until something stops it. **This
is legal.** The garage reports the shortfall on the stat panel and the
auto-assembler's objective penalises it (`AUTO_ASSEMBLE_ALGORITHM.md` §3.1,
`rotorcraft` archetype), but nothing forbids building it, because a player who
discovers *why* their aircraft spins has learned something real about
helicopters and a validator that refused the build would have taught them
nothing.

### 12.5 Shaft Power

```
P = Q · Ω        watts
draw_pu = P / ROTOR_W_PER_PU        ROTOR_W_PER_PU = 4500.0
```

`ROTOR_W_PER_PU` is the exchange rate between the physical shaft power the rotor
genuinely needs and the abstract Power Unit the rest of the schema budgets in.
It is `4500` because that is the value at which `mot.rotor.coaxial_mid.t3` at
full collective draws **150 PU** — precisely the supply of one
`pmv.combustion.standard.t2`. The intended reading of a rotorcraft's power line
is therefore "one standard Prime Mover per mid disc", which is legible in the
garage without arithmetic.

When supply falls short, the Prime Mover layer scales the **commanded angular
rate**, not the thrust:

```
omega_command = nominal_rad_s · throttle · power_available_fraction
```

Scaling Ω rather than T is the honest model and the better feel. Thrust falls as
`Ω²`, so a 10% power shortfall costs 19% of lift; the disc audibly and visibly
slows; and because Ω is behind the spool filter of §12.6, the loss arrives over
seconds rather than instantly. A rotorcraft losing a Prime Mover sinks. It does
not switch off.

### 12.6 Spool

The angular rate approaches its command as a first-order lag, integrated with
the exact discrete solution rather than an Euler step:

```gdscript
static func spool(omega: float, command: float, tau_s: float, dt: float) -> float:
    if tau_s <= 0.0:
        return command
    return omega + (command - omega) * (1.0 - exp(-dt / tau_s))
```

Using `exp` makes the result independent of `dt`, which matters here for a
reason it does not elsewhere in this document: a client re-simulating a rotor
during rollback replays several ticks in one frame, and an Euler lag would
converge at a different rate under replay than it did live. Collective and
cyclic are **rate**-limited instead of lagged (`move_toward` against
`collective_rate_deg_s` and `cyclic_rate_deg_s`), because a swashplate is
mechanically driven and genuinely does move at a constant rate.

`spool_down_tau_s` is longer than `spool_up_tau_s` on every shipping disc. A
rotor with no power keeps turning, which is what makes an unpowered descent
survivable rather than a stone drop.

### 12.7 Cost

| Stage | Per disc per tick |
|---|---|
| Spool, collective, cyclic integration | 3 `move_toward`, 1 `exp` |
| Thrust magnitude and three regime multipliers | ~20 flops |
| Direction (two `rotated`, one basis multiply) | ~40 flops |
| Force and two torque applications | 3 server calls |

There is no query of any kind. A rotary Assembly is cheaper per Motive Assembly
than a wheeled one by roughly the cost of the shape cast it does not perform.

---

## 13. Ambulatory Locomotion

An `AMBULATORY_LIMB` Motive Assembly walks. This section specifies what
"walking" means for an Assembly that is, by Invariant I-3, a single rigid body
with no joints anywhere in it.

### 13.1 Why a Rigid Body Can Walk

The obvious objection is that legs are jointed and I-3 forbids joints. The
objection dissolves once the question is asked precisely: what does a leg
*contribute to the equations of motion of the body it carries?* Exactly one
thing — a force at the hip, directed along the line from the hip to whatever the
foot is standing on, bounded by what the foot can push and by what friction lets
it shear. The internal articulation that produces that force affects the body
only through it.

So the leg is simulated as a **virtual leg**: a spring-damper along the
hip-to-foot line, with a foot that is planted or swinging. This is the
Spring-Loaded Inverted Pendulum, which is the standard model of legged
locomotion in biomechanics and robotics precisely because it reproduces the
force profile of real walking and running from two parameters. The visible
articulation — thigh, shank, foot — is inverse kinematics under `VisualRoot`,
driven from the hip and foot positions the simulation already knows. It is
presentation, exactly like the hardpoint hierarchy of doc 07 §2, and Invariant
I-1 keeps it out of the physics.

What this buys is that a walker takes damage, sheds a limb, re-solves its mass,
and redistributes its weight across the remaining stance feet with no code in
the damage or mass layers aware that legs exist. What it costs is that a limb
cannot be a physical obstacle to anything but itself — a shot passes through the
visible shin and hits the authored `ColliderProfile` box, which is the same
trade doc 07 §2 makes for a turret barrel and is the correct one for the same
reasons.

**A limb occupies its hip and thigh, not its extended leg.** §13.1 puts the visible articulation under `VisualRoot` as inverse kinematics, and Invariant I-1 forbids a collider that follows it — so a footprint spanning the fully extended leg bakes a fixed collider around a shape the limb only ever has at full droop. On `mot.limb.strider.t4` that was a 2.0 m collider on a machine whose stance height is `0.86 × 1.90 = 1.63 m`, and the Assembly stood on its own shins with the stance spring never compressing: measured at 0.23 m of travel it could not reach. The row is now 3×5×3 and its reach is `leg_length_m`, exactly as `mot.rotor.*` occupies its mast and not its 2.6 m disc, for exactly the same reason.

### 13.2 Limb State

```gdscript
class_name LimbState
extends RefCounted

var slot: int = SyndicateConstants.INVALID_SLOT
## Position in the gait cycle, [0, 1). Stance while below duty_factor.
var phase: float = 0.0
## Phase this limb is offset to within the Assembly's gait. Assigned by §13.3.
var phase_offset: float = 0.0
var planted: bool = false
## World position the foot was planted at on touchdown. Meaningless in swing.
var foot_world: Vector3 = Vector3.ZERO
## Hip-to-foot distance last tick, for the damper term.
var prev_length_m: float = 0.0
## True when the last stance tick demanded more shear than friction allowed.
var slipping: bool = false
```

### 13.3 Phase Assignment

Every limb needs a phase offset, and the assignment must be identical on the
server and on every client, must be reproducible from the blueprint alone, and
must produce a gait that keeps the Assembly supported. It is computed once, on
`assembly_structure_changed`, and never per tick.

The rule, for `n` limbs:

1. Partition limbs by the sign of their hip position's lateral coordinate in
   assembly-local space. Zero goes to the left set, so a single centred limb is
   deterministic.
2. Sort the left set fore-to-aft and the right set **aft-to-fore**, breaking
   ties on slot index.
3. Interleave the two, left first.
4. Assign `phase_offset = i / n` over the interleaved ordering.

The reversal in step 2 is the whole design. Interleaving two same-direction
orderings gives a quadruped the sequence front-left, front-right, rear-left,
rear-right, and since the swing window is one contiguous arc of the cycle, the
two limbs that swing together are the two front ones — leaving the Assembly
standing on its rear pair and pitching forward every stride. Reversing one side
gives front-left, rear-right, rear-left, front-right, so the limbs that swing
together are a **diagonal pair** and the pair still planted is the other
diagonal. That is what a real quadruped does, and it falls out of one `reverse`.

The rule degenerates correctly at both ends: two limbs get offsets `0.0` and
`0.5` and alternate, which is bipedal walking; six give a wave gait with
alternating sides.

### 13.4 Cadence and the Standing State

```
if |v_command| < STANDING_SPEED_MPS:      gait is frozen, every foot planted
else  f = clamp(|v_command| / max_step_length_m, nominal_cadence_hz, max_cadence_hz)
phase = fract(phase_offset + gait_clock)   with  gait_clock += f · dt
```

`STANDING_SPEED_MPS = 0.15`. The frozen state is not an optimisation, it is the
behaviour: a walker asked to stand still stands, on every foot, rather than
marching in place. It is also the only state in which every limb contributes
stance force simultaneously, which is what makes a stationary walker rock-solid
and a moving one visibly bob — the correct relationship, and one that comes free.

Deriving `f` from step length rather than authoring it is what keeps the feet
from skating. The body advances one step length per stance, so a cadence that
did not track commanded speed would slide the planted foot across the ground
every stride, which reads as ice and is the single most common failure of
procedural walk cycles.

### 13.5 Foot Placement

On the swing→stance transition, the foot is planted at a target given by the
Raibert placement law:

```
p_foot = p_hip_ground + v · (T_stance / 2) + k_v · (v − v_desired)
T_stance = duty_factor / f
```

The first term is the **neutral point**: planting there leaves the body's
horizontal velocity unchanged across the stance, because the body's momentum
carries it over the foot symmetrically. The second is the correction — planting
*ahead* of neutral brakes, planting *behind* accelerates, and `placement_gain_s`
sets how hard. This is not a heuristic dressed as physics; it is the balance law
legged robots actually use, and it is the reason a walker in this game
accelerates by leaning and reaching rather than by having a force added to it.

Yaw is placement too. A turn command rotates the target about the Assembly's
vertical axis by `−turn_rate_deg_s · turn_command · T_stance`, so the feet land
off-axis and the resulting stance forces yaw the body. There is no yaw torque
term anywhere in the ambulatory family.

**The minus sign is normative.** `ControlInput.steer` is positive-is-right across
every family — §7.1 rotates a wheeled contact frame right on a positive demand,
§14.2 drives the right track slower — and a right turn is a *negative* rotation
about the world up. Rotating the plant target by `+turn_rate · turn_command`
therefore walks the Assembly **left** on a demand to go right, and makes the
ambulatory family the only thing in the game that steers backwards. A test of
this rotation asserts the direction the hull ends up facing; asserting that the
foot moved is a test a sign flip passes.

The target is clamped twice, in this order: the offset from the hip's ground
projection is limited to `max_step_length_m / 2`, then the whole hip-to-target
vector is limited to `leg_length_m`. A leg cannot reach past its own length, and
clamping the reach *after* the step length is what keeps a limb from planting a
foot it would have to over-extend to hold.

### 13.6 Stance Force

```
r  = p_hip_world − p_foot_world          (points from foot up to hip)
L  = |r|
L₀ = stance_height_ratio · leg_length_m
x  = L₀ − L                              (positive in compression)
L̇  = (L − L_prev) / dt
F_axial = clamp(k · x − c · L̇, 0, max_foot_force_n)
F = F_axial · r̂                          applied at the hip offset
```

The lower clamp at zero is the same rule §6.2 states for suspension and exists
for the same reason: a leg pushes and never pulls. The upper clamp is what makes
an overloaded walker sag rather than launch — a limb rated at 42 kN under a
build that puts 60 kN on it simply cannot hold the body up, and the Assembly
settles until enough limbs share the load or it sits down.

Friction bounds the shear. Split `F` into its component along the contact normal
and its tangent, and if the tangent exceeds what the normal load can hold, scale
it back and mark the foot slipping:

```
F_n = F · n̂
F_t = F − F_n · n̂
μ = traction_coefficient · SurfaceTable.multiplier(surface_id)
      · DegradationTable.MOTIVE_TRACTION[band]
if |F_t| > μ · F_n:
    F_t *= μ · F_n / |F_t|
    slipping = true
```

A slipping foot also **slides its plant point** by the residual, so a walker on
`SURFACE_SLICK` cannot accelerate, loses its footing progressively rather than
in one frame, and recovers when it reaches grip. Note that `μ` runs through the
same `MOTIVE_TRACTION` band multiplier the wheels use — a damaged limb loses
grip before it loses the ability to hold weight, which is the more interesting
of the two failure orders.

### 13.7 Swing

A swinging limb applies **no force**. Its share of the Assembly's weight is
taken up by the remaining stance limbs automatically, because the body sinks
fractionally and their springs compress further. This is the whole reason to use
a spring rather than a solved load distribution: the redistribution is a
consequence, it costs nothing, and it is correct when a limb is destroyed
mid-stride as well as when one is merely swinging.

The foot's visible position over the swing is a parabolic arc from the last
plant point to the next target, peaking at `step_height_m`, sampled from the
phase. It is written to `VisualRoot` and read by nothing in the simulation.

### 13.8 What This Section Does Not Do

Stated explicitly so a future session does not assume otherwise:

- **No flight phase.** Every shipping `duty_factor` is above `0.5`, so support
  is continuous. A run is expressible and is untuned.
- **No balance recovery beyond placement.** The Raibert term is the only balance
  authority. A walker shoved hard enough falls over, and falling over is just
  the rigid body doing what the forces say.
- **No terrain-aware footfall.** The plant target is projected onto whatever the
  probe finds beneath it; a limb does not search for a better foothold.
- **No inverse kinematics.** §13.1's visible articulation belongs to doc 13 with
  the rest of the mesh pipeline, and the simulation is complete without it.

---

## 14. Tracked Locomotion

A `TRACKED_SEGMENT` Motive Assembly is a ground contact that has been smeared
along the hull. It reuses §6.2's spring-damper and §7.2's friction curve
verbatim, once per road station, and adds two things a point contact has no term
for: a drive model that steers by rate difference rather than by angle, and a
resistance to slewing the patch across the ground.

### 14.1 Road Stations

`TrackProfile.station_offsets_m()` places `road_stations` probes evenly along
`patch_length_m`, symmetric about the part's pivot. Each is an ordinary §6.1
shape cast and produces an ordinary `MotiveContact`.

The consequence is the interesting part. Because each station carries its own
spring and each spring is applied at its own offset from the COM, a tracked
Assembly driving over a rise **conforms to it**: the forward stations compress,
the rear ones extend, the net force stays roughly constant, and the hull barely
moves. A single-point contact at the same place would ride up over the rise and
throw the whole Assembly. This is not modelled — it is what happens when four
springs are placed a foot apart and the rigid body is left to do its job.

It is also why `road_stations` is capped at `MAX_ROAD_STATIONS = 8`. Four tracked
Motive Assemblies at eight stations each is 32 shape casts on one Assembly,
already twice what a wheeled build of the same part count costs.

`station_load_share` is the fraction of the part's rated load one station is
expected to carry, and it is authored *below* `1 / road_stations` on both
shipping rows. That deliberate softness at the ends of the patch is what lets a
track conform rather than bridge rigidly, and it is the tuning knob to reach for
when a tracked build feels like it is on stilts.

### 14.2 Differential Drive

There is no steer angle. `max_steer_angle_deg` is zero on every tracked row and
§14 rule 22 of document 01 requires it. Steering is a difference in the drive
applied to the Assembly's left and right tracked Motive Assemblies, partitioned
by the sign of each part's lateral position in assembly-local space:

```
authority = differential_authority · (1 − clamp(|v| / pivot_taper_mps, 0, 1))
bias      = steer_command · authority                    ∈ [−1, 1]
τ_share   = ½ · drive_torque · (1 − internal_loss)
τ_left    = τ_share · clamp(throttle + bias, −1, +1)
τ_right   = τ_share · clamp(throttle − bias, −1, +1)
```

**Amendment.** This block previously read `τ_left = τ_share · (1 + bias)` and `τ_right = τ_share · (1 − bias)`, with `τ_share` scaled by the throttle. That formula cannot produce the behaviour the paragraph below it describes and always did. With `bias` bounded at 1 it never drives a side backwards — at full lock it gives one track everything and the other exactly zero, which pivots about the *stationary track* rather than about the Assembly — and because the whole expression scaled with the throttle, a stopped tracked Assembly received nothing on either side and could not turn at all under any input. Making throttle and steer additive terms is the standard skid-steer mixer and is what the prose already asked for. The consequence is that steering into a full throttle costs total drive, because the outer side is already at its limit and the only way to make a difference is to take torque off the inner one; that is correct and is why a tracked Assembly slows in a turn.

At rest `authority` is full, so `bias = ±1` drives one side forward and the
other backward and the Assembly counter-rotates on the spot. At
`pivot_taper_mps` authority is zero, both sides receive the same torque, and
steering is whatever the patch's lateral friction concedes — which, at
`lateral_grip_ratio` of 1.35 or more, is very little. A tracked Assembly
therefore pivots freely when stopped and commits to a long arc at speed, and
neither behaviour is a special case: they are one linear expression evaluated at
two speeds.

`internal_loss` is charged **before** the torque reaches the ground, not
afterwards, because that is where it physically goes — into the track's own
pins, links, and idlers. The visible result is that a tracked Assembly is slower
than a wheeled one of identical power, which is correct and is the cost the grip
and the ground pressure are bought with.

An Assembly with tracked Motive Assemblies on only one side is legal and drives
in circles. Nothing prevents it; the garage's stability line reports the
imbalance the same way it reports a rotor's unopposed reaction torque, for the
same reason §12.4 gives.

### 14.3 Slew Resistance

Turning a long patch shears the ground along its whole length. The resisting
torque about the Assembly's vertical axis is proportional to patch length, to
normal load, and to the rate of the slew:

```
τ_slew = −sign(ω_y) · slew_resistance_nm_per_n_m · patch_length_m · N_total
         · min(1, |ω_y| / SLEW_REFERENCE_RAD_S)          SLEW_REFERENCE_RAD_S = 1.2
```

The `min` is what keeps it a resistance rather than a brake: below the reference
rate it scales in, above it is constant, and it never exceeds what the friction
of the patch could actually supply. Without the cap a fast spin would generate
unbounded counter-torque and the Assembly would snap to a stop, which reads as
hitting a wall.

The `L · N` product is the design statement. A heavy tracked Assembly is
*committed*: doubling its armour doubles the torque needed to change its
heading, and no steering input overcomes it. That is the failure mode a
`bastion` build is meant to have, and it emerges from two authored numbers
rather than from a handling penalty applied on top.

### 14.4 Lateral Grip

A station's lateral friction coefficient is the part's `traction_coefficient`
scaled by `lateral_grip_ratio`, which is above 1.0 on both shipping rows. The
longitudinal coefficient is unscaled. This anisotropy is real — a track resists
sliding sideways far better than it resists being driven along — and it is
applied inside §7.2's combined-slip solve rather than after it, so the friction
circle becomes a friction **ellipse** and the trade between cornering grip and
drive grip stays correct.

Applying it afterwards would let a station spend lateral grip it never had on
longitudinal force, which presents as a tracked Assembly that accelerates faster
while sliding sideways than while going straight.

### 14.5 Cost

| Stage | Per tracked Motive Assembly per tick |
|---|---|
| Shape casts | `road_stations`, so 4 or 6 |
| Suspension force | `road_stations` × §6.2, unchanged |
| Traction force | `road_stations` × §7.2, unchanged |
| Drive partition and slew torque | Once per Assembly, not per part |

A four-station tracked Motive Assembly costs about four times a wheeled one.
The shipping budget of §10.5 assumes tracked builds run fewer Motive Assemblies
— two long bogies replace six wheels — so the totals land within a few percent
of each other.

---

## 15. Control Input

Every locomotion family reads one `ControlInput` and none of them knows where it
came from. That is the whole point of §6.0's contract: the record is eight
normalised numbers, and a keyboard, a stick, a bot, and a replayed packet are
indistinguishable to the solvers.

There are three producers. `ControlSystem` is the local player's, and it is the
one this section owns. The AI driver (`src/ai/ai_driver.gd`) is the second and
the network input channel of `HEADLESS_NETWORK_SYNC.md` §5 is the third; both
write the same fields and neither is permitted a field of its own.

### 15.1 Where It Runs

`ControlSystem` connects to `MatchClock.tick_started` and declares no per-frame
callback of its own.

`MatchClock` runs at `process_physics_priority = -1000`, so `tick_started` fires
before every other `_physics_process` in the tree — `MotiveSystem`'s included.
Sampling there guarantees that the intent a family reads was captured on the
tick it is being solved for, and it makes that ordering a property of the clock
rather than of scene-construction order. A `ControlSystem` that declared
`_physics_process` would sample before or after the motion layer depending on
where the match scene happened to add it, which is exactly the class of bug that
presents as one frame of input lag on some builds and not others.

The system is constructed only on a client that is driving something. There is
no runtime gate and no feature tag: `SubsystemGate` is queried at construction
(`HEADLESS_NETWORK_SYNC.md` §9.2), and the dedicated server's bootstrap never
builds one, so no branch is needed at the sampling site.

### 15.2 The Mapping

| `ControlInput` field | Actions |
|---|---|
| `throttle` | `veh_throttle` − `veh_brake` |
| `brake` | `veh_brake` |
| `steer` | `veh_steer_right` − `veh_steer_left` |
| `collective` | `veh_throttle` − `veh_brake` |
| `yaw` | `veh_steer_right` − `veh_steer_left` |
| `cyclic.x` | `veh_pitch_back` − `veh_pitch_forward` |
| `cyclic.y` | `veh_roll_left` − `veh_roll_right` |
| `handbrake` | `veh_handbrake` pressed |
| `boost` | `veh_boost` pressed |
| `traction_control` | not an action; see §15.5 |

Every analogue action goes through `Input.get_action_strength`, so a trigger, a
stick, and a key produce the same number without a special case, and the
deadzone that `project.godot` declares per action is the only deadzone in the
chain.

### 15.3 One Axis Serves Several Families

`throttle` and `collective` are the same axis, and so are `steer` and `yaw`.
This is deliberate and it is what lets one control layout drive four locomotion
families without a mode switch.

On a wheeled or tracked Assembly, `veh_throttle` is drive and `veh_steer_*` is
steering. On a rotary one the same two axes are the collective and the pedals:
holding throttle spools the disc *and* pitches it to climb (§12.2), and the
steer axis is the yaw authority of §12.4. On an ambulatory one both feed
`desired_velocity` and the gait's turn command (§13.5).

A family reads the fields it uses and ignores the rest. Nothing branches on
locomotion mode in the input layer, which matters because a build may carry more
than one family at once — a walker with a lift rotor is a legal Assembly, and it
gets a coherent control scheme out of this table rather than out of a priority
rule.

### 15.4 The Cyclic Sign

§12.3 builds the thrust direction by rotating the disc axis about `+X` by
`cyclic.x` and about `+Z` by `cyclic.y`. Under that rotation order a **positive**
`cyclic.x` carries the thrust vector toward `+Z`, which is *backwards*, and a
positive `cyclic.y` carries it toward `−X`, which is *left*.

So the mapping inverts both: a demand to pitch forward is a negative `cyclic.x`
and a demand to roll right is a negative `cyclic.y`. The inversion is real, it
belongs here rather than in the solver — §12.3's rotation order is the physics,
and this is the mapping onto it — and it is the reason
`tests/unit/test_control_system.gd` asserts the composition of the two rather
than the sign of either alone. A test that only checked `cyclic.x < 0` would
pass against a solver that tilted the other way.

### 15.5 Reverse Is Not a Mode

`veh_brake` produces both the brake demand and a negative throttle. Above a
walking pace the brake torque dominates and the Assembly slows; at rest the
negative drive torque backs it out. §7.2's brake zero-crossing guard is what
makes the two coexist — the brake may not drive a contact through zero, so it
cannot reverse anything, and only the drive term can.

The alternative was a reverse *state* entered when the Assembly is stopped and
the brake is held, which needs the input layer to know the Assembly's speed and
produces the familiar failure where a build rolling backwards down a slope
refuses to brake. One subtraction is cheaper and has no state to get wrong.

### 15.6 What It Does Not Do

**No smoothing and no rate limiting.** A keyboard produces a step from 0 to 1
and it stays a step. `MotiveSystem` already rate-limits the *steer angle* from
the part's authored `steer_rate_deg_s` (§7.0), and a Prime Mover's throttle
response is §7.5's; a ramp here would be a second owner of both, and would make
the authored numbers mean less than they say.

**No aid authority of its own.** `traction_control` is a driver setting, not an
intent: it is carried on `ControlSystem` as a property the settings screen
writes, defaulting to full, and copied onto the record each tick. §7.6's
authority is a dial and this is where the dial's position lives until
`RESPONSIVE_GARAGE_UI.md` gives it a control.

**No knowledge of which Assembly it drives.** One `ControlSystem` writes one
`ControlInput`. Which Assembly reads that record is the match scene's wiring
(§6 of the handoff's assembly recipe), and a spectator or a dead player is a
`ControlSystem` that was never constructed rather than a flag tested per tick.

### 15.7 The Second Producer: `AiDriver`

`src/ai/ai_driver.gd` is the second of §15's three producers. It writes the same
eight numbers as `ControlSystem`, from world state instead of from the input map,
and a locomotion family cannot tell the two apart. That indistinguishability is
the contract, and it is what makes an AI Assembly a genuine test of the motion
layer rather than a second, easier physics.

**Where it runs is identical to §15.1's answer.** `AiDriver` connects to
`MatchClock.tick_started` and declares no per-frame callback of its own, for the
same reason `ControlSystem` does: the intent a family reads must have been
produced on the tick it is being solved for, and making that a property of the
clock rather than of scene-construction order is what stops one build having a
frame of lag the next one does not.

**What it may not do.** It may not apply a force, write a hardpoint angle, or
call into a solver. Everything it does reaches the simulation through
`ControlInput` and through `EffectorSystem.aim_point_world` and the firing-group
trigger — which are exactly the two surfaces a human player reaches the same
systems through. An `AiDriver` that could do more would be able to fly a build a
player cannot fly, and the first thing anybody would learn from watching it
fight would be false.

**It may not read integrity per tick.** Invariant I-5 forbids a hot loop reading
integrity or deriving a band. Target scoring does read a Core Module's integrity
fraction — `WEAPON_TARGETING_LOGIC.md` §10 scores a wounded target higher — and
that read happens on the scan interval of that section, at 2.9 Hz, never in the
per-tick path. The per-tick path reads a body transform and nothing else.

#### 15.7.1 The Ground Tactic

One law, and it is the whole of the driving:

```gdscript
range_m  := to_target_flat.length()
closing  := range_m > stand_off_m
bearing  := forward.signed_angle_to(to_target_flat, Vector3.UP)
closure  := velocity_flat.dot(to_target_flat.normalized())
arrival  := arrival_brake(range_m, stand_off_m, closure)

input.steer    = clampf(-bearing / STEER_SATURATION_RAD, -1.0, 1.0)
input.brake    = arrival
input.throttle = approach_throttle(bearing, speed) * (1.0 - arrival) if closing else 0.0
```

Positive steer is right and a right turn is a **negative** rotation about the
world up, so the demand is the negated bearing error. That sign is the one thing
in this section a test must assert in both directions; it is invisible to any
assertion that only checks the Assembly turned.

The throttle is a **cosine of the heading error**, not a boolean, and that is
measured rather than tidy. At full throttle through a full-lock turn a wheeled
build drives an arc wider than the range it is closing: spawned facing away from
a target 40 m off it turned 53° in two and a half seconds, and the range *grew*
from 40 m to 46 m while the bearing sat at 135° — an outward spiral at constant
bearing, which is what pure pursuit does when the turn radius exceeds the range.
The cosine is the projection of the approach onto the direction the Assembly can
actually travel in: at 60° off the nose half the speed is closing the range and
the rest is widening the arc.

It cannot taper to zero. A steered contact needs road speed to generate any
lateral force at all, and an Assembly stopped dead with the lock over sits there
scrubbing its front contacts. `APPROACH_MIN_THROTTLE` is the floor it crawls at.

**The floor alone does not answer the standing start, and raising it is the wrong
fix.** Driven on the taper alone from 180° of heading error the reference build
settles at about 0.2 m/s and never comes round at all. The window between the two
failures was mapped on a flat slab, one build spawned facing away from a target
40 m off and driven for 330 ticks:

| Floor | Best bearing reached | Turned inside 30° | Final range |
|---|---|---|---|
| 0.35 | 77.4° | no | 48.6 m |
| 0.50 | 36.4° | no | 47.2 m |
| 0.60 | 16.6° | t = 314 | 46.2 m |
| 0.70 | 0.5° | t = 291 | 44.8 m |
| 0.80 | 0.1° | t = 270 | 43.3 m |
| 0.90 | 0.5° | t = 267 | 43.5 m |
| 1.00 | 41.8° | no | 45.3 m |

**And then 0.80 was shipped, and it broke the match.** On the arena's fifteen
metres of relief the opponents stopped reaching the player at all: milling about
at forty to seventy metres for the whole capture where the same scene at 0.35 had
them at contact range by frame 400 with the player down to 44%. Sustained heavy
throttle through a turn is the outward spiral this taper exists to prevent, and
on a slope it breaks traction as well. **The flat fixture could not see any of
it, and the suite was green.**

So the two failures get two different treatments, because they are two different
failures. The taper's floor stays at 0.35, which is what terrain says it can
carry. The standing start is answered as what it is — a stalled contact needing
to break away — by a demand that applies **only while the Assembly is barely
moving**:

```gdscript
demand := clampf(cos(bearing), APPROACH_MIN_THROTTLE, 1.0)
if speed < APPROACH_BREAKAWAY_SPEED_MPS:
    demand = maxf(demand, APPROACH_BREAKAWAY_THROTTLE)
```

It is self-limiting: it stops the instant the Assembly is rolling, so it never
becomes the sustained throttle that loses grip on a slope. Measured, the build
comes onto its bearing inside the same 330 ticks and the match plays as it did.

**The lesson is worth more than the constant.** A fixture on a flat slab and a
match on real ground are different physics, and a locomotion law tuned against
the first can be measurably better there and measurably worse in the game. Any
change to this section wants a capture, not just a green run.

**There was no brake on arrival, one was tried, and it is now back — because the
condition this section wrote down for its return turned out to be the shipped
match.** The original measurement stands and is worth keeping: cutting the
throttle at the stand-off leaves the Assembly coasting through it, which under
the flat 0.80 floor meant arriving at 11 m/s, running to 3.1 m, and setting off
on another lap; a brake demand fixed that, and against the breakaway law that
replaced the floor it then made no measurable difference at all — 6.4 m and 9
rounds with it, 5.8 m and 10 rounds without. It was removed rather than carried,
which was right: a demand nothing can distinguish from its absence is not a rule.
The condition named for bringing it back was **an approach that ends fast**.

That measurement was taken on a driver spawned facing *away* from its target. It
spends the whole approach on the cosine taper and arrives at walking pace, and
under those conditions there is genuinely nothing for a brake to do. A driver
spawned **facing** its target never touches the taper: it holds full throttle for
the entire run-in, and the shipped arena's nearest opponent spawn is 34 m away —
enough to arrive at **18.2 m/s**. A bare throttle cut does not stop 1107 kg from
there inside a six-metre stand-off. It does not stop at all; it drives over
whatever is standing on the mark, which is what the first five seconds of every
shipped match were.

#### The arrival law

```gdscript
func arrival_brake(range_m, stand_off_m, closure_mps) -> float:
    if closure_mps <= ARRIVAL_CLOSURE_DEADBAND_MPS:
        return 0.0
    var slack := range_m - stand_off_m
    if slack <= 0.0:
        return 1.0                       # inside the stand-off and still coming on
    var needed := closure_mps * closure_mps / (2.0 * slack)
    return clampf(needed / ARRIVAL_DECEL_MPS2 - 1.0, 0.0, 1.0)
```

It is a **stopping-distance law rather than a gain**, and that is the whole of
why it works where a speed cap would not. The quantity that decides whether a
driver arrives or rams is not its speed but `v² / 2s` — the deceleration the
remaining slack would require. The profile that falls out is
`v = sqrt(2 · a · slack)`: the driver still crosses open ground at fifteen metres
a second and still arrives at a walk, and no part of it is a function of how far
away the fight started. The demand is zero while the slack can absorb the closure
at the planned figure and full when it would need twice it.

`closure_mps` is the **component of velocity along the bearing**, not the speed.
A driver crossing in front of its target is not arriving at it, and braking on
speed alone would stop §15.7.5's outer rungs from ever taking station.

The brake and the throttle come out of that one number, so the two cannot fight:
at half demand the driver has lifted off and is braking gently, at full it is off
the throttle entirely. A demand that accelerated and braked at once would be
asking the same contacts for both.

`ARRIVAL_DECEL_MPS2` is well inside what the reference build can make: four
contacts at §7.4's 8300 N·m over a 0.5 m radius is 66 kN against 3630 kg, which
the tyres cut to about one g — so the plan is under two thirds of the authority.
That margin is deliberate and is what lets the same number hold on a slope
without the terrain problem the throttle floor had.

**It was 4.0 and it was authored against an 1107 kg build.** The reference build
is now 3630 kg with the braking authority to match, and at 4.0 the driver arrived
at its ten-metre stand-off still carrying enough speed to run through it into
contact: `tests/physics/test_ram_attitude.gd` measured the nearest approach at a
centimetre of hull overlap where it used to leave over a metre of clear air. The
law is a stopping-distance plan rather than a gain, so the figure it plans on has
to be a deceleration the build can actually make, and 6.0 m/s² is 0.61 g against
the 1.05 g four loaded contacts hold.

#### `closing` stays a line, and a band was tried

Recorded because the reasoning for a band is good and the measurement does not
support it, which is exactly the shape of thing that gets re-invented.

`closing` is a bare range comparison, so a driver parked on its demand crosses it
in both directions as its own hull settles and its target drifts — throttle on,
brake on, throttle on. It never quite stops, and this was already known: the
engagement test carries a note saying a driver "idles at a few metres a second
rather than at zero" and reads it as the law working. Against a target that can
be pushed that looked like a bulldoze, each swing of the cycle being a throttle
application into a nearby hull, so hysteresis was added: closing stops at the
stand-off and does not resume until the target has opened three metres past it.

It changed nothing. With the arrival brake in and the stand-off clear of the
hulls, the ram fixture's numbers are **identical** to the last decimal with the
band in and with it out, and a fault that deletes it survives a full sweep. The
premise was wrong rather than the reasoning: the shove that looked like a
bulldoze turned out to be the target's own drift (below), and at a ten-metre
stand-off there is no hull a metre from the driver's nose for the oscillation to
push. **The band was removed rather than carried, for the same reason the first
arrival brake was** — a demand nothing can distinguish from its absence is not a
rule. What brings it back is a target close enough to be pushed by the idle,
which now means a stand-off shorter than this section's.

#### The stand-off itself was shorter than the hulls

The largest of the three findings, and the one that no approach law could have
rescued. `GROUND_STAND_OFF_M` was 6.0 m, authored against an Assembly length
nobody had ever measured. `tests/physics/test_ram_attitude.gd` measures it from
the **colliders** — Invariant I-1 makes those the physical footprint — and the
reference wheeled build reaches **2.4 m** from its body origin to its nose. Two
of them therefore touch at **4.8 m** of origin separation.

So a six-metre stand-off was never a stand-off. It was nose-to-nose parking with
1.2 m of air, against an arrival overshoot of about the same, and the measurement
says exactly that: the nearest driver finished 4.8 m out with an **eight
centimetre** gap. `GROUND_STAND_OFF_M` went to 10.0 — the touching range plus a
full hull length of clear air, which is the smallest range at which an approach
that overshoots is still an approach.

**And ten was authored against an 1107 kg build, so it moved again when the
reference build did.** A stand-off has to exceed the machine's own stopping
distance. The rebuilt build is 3630 kg, reaches its mark at about 9.7 m/s and
plans on 6.0 m/s², so it needs 7.8 m to stop; from ten metres it arrived at 4.1 m
against a hull that now touches at 4.0. `GROUND_STAND_OFF_M` is **14.0**: the
touching range, plus the stopping distance, plus a hull length of clear air. The
general rule is worth more than the number — *a stand-off is a stopping distance
plus a clearance, and both of its terms are properties of the build rather than
of the tactic.*

| Measured, three drivers converging on a stationary build | Before | After |
|---|---|---|
| Worst roll of the target | **146.2°** | **0.3°** |
| Closest approach, origin to origin | 4.8 m | 7.9 m |
| Gap between the two hulls at that point | **0.08 m** | **3.16 m** |
| Fastest a driver was travelling | 18.2 m/s | 12.4 m/s |
| Fastest the *stationary* target was travelling | 8.4 m/s | 0.53 m/s |

The ambulatory family is exempt from all three and holds full throttle, because §13.5's
placement law walks it in the direction it is given rather than along its own
nose — a heading error does not widen its approach, so the taper would only slow
it down.

| Constant | Value | What it is |
|---|---|---|
| `STEER_SATURATION_RAD` | 0.35 | Heading error at which the steering demand saturates |
| `APPROACH_MIN_THROTTLE` | 0.35 | Throttle floor while the target is off the nose |
| `APPROACH_BREAKAWAY_SPEED_MPS` | 3.0 | Speed below which the taper is overridden to break away from a standstill |
| `APPROACH_BREAKAWAY_THROTTLE` | 0.80 | The demand it is overridden to |
| `ARRIVAL_DECEL_MPS2` | 6.0 | Deceleration a ground driver plans its arrival on |
| `ARRIVAL_CLOSURE_DEADBAND_MPS` | 0.5 | Closing speed under which no arrival brake is demanded |
| `GROUND_STAND_OFF_M` | 14.0 | Range a wheeled or tracked driver stops closing at — the 4.0 m hull-to-hull contact range plus a 7.8 m stopping distance plus clearance |
| `AMBULATORY_TURN_SATURATION_RAD` | 0.60 | The same as the first row, for a family that turns far more slowly |
| `AMBULATORY_YAW_DAMPING` | 0.55 | Steering demand per radian per second of hull yaw, opposing it |
| `AMBULATORY_STEER_AUTHORITY` | 0.5 | Ceiling on an ambulatory steering demand |
| `AMBULATORY_STAND_OFF_M` | 20.0 | Range an ambulatory driver plants and shoots from |

#### 15.7.2 Why the Ambulatory Family Is Steered on a Rate

An ambulatory Assembly is flown onto a **yaw rate**, not onto a heading, and the
reason is a hard number rather than a preference. `WEAPON_TARGETING_LOGIC.md`
§4.3 converges a mount at half a degree and §3.3 slews it at 65°/s, so a hull
turning faster than about 30°/s can never be tracked by its own gun: the mount
closes 1.08° a tick and the demand moves further than that. An ambulatory
Assembly steered like a wheeled one turns at exactly that rate and spends the
engagement one step behind its own target. `AMBULATORY_YAW_DAMPING` is what
holds it under the limit.

`AMBULATORY_STEER_AUTHORITY` is below one because §13.5 spends the same number on
the lateral half of the desired velocity: a saturated demand walks the Assembly
45° off its own nose, which is a circle rather than an approach.

The stand-off is longer for the same family, and that is gunnery rather than
survivability. Standing, §13.4 puts every foot down at once and the hull is
level to within a degree — the steadiest mount in the game. Walking, §13.8
allows no balance authority beyond foot placement, the hull bobs, and the gait
carries an intrinsic yaw drift no steering demand can null. So an ambulatory
driver plants and shoots, and the stand-off is set outside the range it is
likely to spawn at so that it takes a step or two to square up and then stops.

#### 15.7.3 What Is Deliberately Not Here

**The rotary family has no `AiDriver` tactic, and this is a decision rather than
a gap.** Holding a hover is not a tactic: it is three closed loops — collective
on altitude, cyclic on horizontal velocity, pedal on heading — that resolve a
demand into a world-space thrust direction and invert §12.3 back out into swash
angles. A **human** flying a rotary build needs precisely the same loops, so
putting them in `AiDriver` would give a bot stability augmentation a player does
not have, which §15.7 above forbids in as many words.

That controller therefore belongs in a stability-augmentation layer this document
does not yet have, sitting between *both* producers and the motion layer. Until
it exists, `tests/combat_arena.gd` carries the only implementation, as a fixture,
and says so. An `AiDriver` asked to drive a rotary Assembly writes a neutral
record rather than a wrong one.

**No pathfinding, no cover, no formation.** The driver closes on a bearing and
stops at a stand-off. `AUTO_ASSEMBLE_ALGORITHM.md`-scale decision machinery over
terrain is a system nobody has specified, and inventing it here would be worse
than the gap.

#### 15.7.4 Fire Discipline: An `AiDriver` Closes With Its Guns Cold

The trigger is held only while the driver is **not** closing — that is, once it
is inside its stand-off. This is not a preference about when a bot should shoot;
it is the difference between a driver that arrives and one that spirals, and the
number is large.

`WEAPON_TARGETING_LOGIC.md` §10.5 authors 1450 N·s of recoil a round and §8
applies it **at the muzzle**. On the reference wheeled build one round is 1.31
m/s of the Assembly's own speed, and a driver holding the trigger through its
approach cannot get out of its own way: measured, it never came round at all and
finished 59 m from a target it had started 43 m from, while the identical driver
with the trigger cold turned onto the bearing in 270 ticks, closed to its
stand-off and stopped there.

So the recoil is not a disturbance the steering can trim out — it is larger than
the authority the family has. Shooting from a halt is the doctrine that falls out
of that, and it is the same one §15.7.2 already reaches for the ambulatory family
from a different direction.

**This was recorded as a workaround for a data defect, and that reading was
wrong.** The defect named was the shipped autocannon's bore sitting half a cell
off the hull's centreline, on the reasoning that centring it would remove the yaw
and with it the need for this rule. `PART_DATA_SCHEMA.md` §14 rule 27 has since
centred it — measured at a millimetre of lateral lever — and the approach still
fails exactly as before.

`tests/physics/test_recoil_geometry.gd` is where the real number is. A driver
turning toward a target is by definition firing off its own nose, and a traversed
mount swings the recoil's line of action out to the 2.25 m it sits forward of the
centre of mass: one round at 90° of traverse yaws the hull at **0.85 rad/s**
against **0.013** for the same round fired dead ahead, a factor of sixty-five.
Centring the bore fixes the on-axis case and cannot reach that one.

**So this rule is not waiting on a data change.** What would remove it is a mount
whose recoil passes near the centre of mass, which is a question about where a
build puts its guns rather than about how a part is authored — and it is a real
design lever, because a player choosing a mounting point is choosing this.

The cost of carrying the rule is real and a player will see it: an AI Assembly
chasing a target that keeps running away never fires.

**A human player has no such rule and is not given one.** They can hold the
trigger while driving, and they will meet exactly the same yaw. That is honest —
both producers write the same eight numbers into the same physics — and it is
the strongest argument in this document for fixing the offset rather than the
driver.

#### 15.7.5 The Stand-Off Ladder: Several Drivers, One Target

Three opponents converging on one target at a six-metre stand-off end up in a
heap and fire through each other. Nothing in `src/combat/` knows what a team is —
`DamagePacket` names a source Assembly and `DamageResolver` never asks whose side
it is on — so a round that clips a friend on the way past does full damage, and
in the shipped arena at least one opponent dies to another before the player
fires a shot.

Whether friendly fire should exist is `COMPONENT_HEALTH_DAMAGE.md`'s question and
is the larger one underneath this. It is not this section's, and it should not
be answered by accident here: an AI that could shoot through its friends would be
a different game from one that could not, and the choice belongs in the document
that owns damage.

What *is* this section's is the geometry. A stand-off is a range, drivers already
have one, and a set of drivers converging on a point can be spread out along the
line to it without anyone negotiating with anyone:

```gdscript
steps := clampi(closer_allies, 0, ALLY_STAND_OFF_MAX_STEPS)
stand_off_m := base_m + steps * ALLY_STAND_OFF_STEP_M
```

`closer_allies` is the number of Assemblies on the driver's own side that are
**nearer the chosen target than it is**. That predicate is what makes the
arrangement work, and three properties fall out of it:

- **It is a strict ordering by range**, so the demands are mutually consistent
  without any driver knowing what another has decided. The nearest holds at the
  base stand-off, the second one step out, the third two.
- **It is stable under overtaking.** A driver that passes its neighbour inherits
  the shorter stand-off in the same swap that gives the neighbour the longer one,
  so the ladder re-forms rather than oscillating.
- **It costs nothing per tick.** The count is taken off `WEAPON_TARGETING_LOGIC.md`
  §10.1's candidate list, which is sampled on that section's 2.9 Hz scan
  interval, so the laddered range is resolved once per scan alongside the target
  and the aim error. The per-tick path still reads a body transform and nothing
  else.

Ties are not broken. Two friends at exactly equal range both count as not-closer
and share a rung, which is the correct answer for two Assemblies abreast.

The step was chosen as "a little over an Assembly's own length" — the smallest
spacing at which a hull is not between a friend and the target. **That premise is
wrong and the measurement that settled §15.7.1's stand-off is what falsified it.**
The reference wheeled build reaches 2.4 m from its body origin to its nose, so it
is 4.8 m long and the 4.5 m step is a little *under* its length rather than over
it. A friend one rung out is therefore still partly in the line.

The constant is deliberately left at 4.5 rather than corrected in the same change
as the stand-off. Moving it moves every engagement measurement in
`tests/physics/` at once, and unlike the stand-off it is not what was driving
over the player — the ladder's geometry works, it is its stated justification
that was arithmetic nobody had checked. Raising it to one measured hull length is
a `balance-review` decision and is recorded as open.

The cap exists because doc 07 §10 models no obscuration at all, so an uncapped
ladder would hold a fourth driver at a range where it is shooting at a hull it
could not resolve, and the extra range would cost more accuracy than the spacing
bought.

| Constant | Value | What it is |
|---|---|---|
| `ALLY_STAND_OFF_STEP_M` | 4.5 | Extra stand-off per friendly Assembly already closer to the target |
| `ALLY_STAND_OFF_MAX_STEPS` | 3 | Cap on the ladder, in steps |

**This does not stop friendly fire and is not meant to.** A round still does full
damage to whatever it reaches first. What it stops is three Assemblies standing
in each other's line at contact range for the whole engagement, which is the
form the problem actually takes.

---

## 16. Where the Contact Is Drawn

Everything above this section derives forces. This one derives a picture, and it
is here because the alternative was that nobody owned it: §10.2 places
`VisualRoot` from the body's transform, doc 13 owns the meshes, and between them
sat the question of where a wheel goes when the suspension moves — which is a
locomotion question, answerable only from quantities this document defines.

The gap was visible rather than theoretical. A Motive Assembly was drawn at the
lattice cell it was placed in and stayed there, so on fifteen metres of relief
the wheels hung in the air on every crest and the Assembly read as a prop sliding
over the ground rather than as something driving on it.

**This is presentation following the simulation, and Architectural Invariant I-1
permits exactly that direction.** What the invariant forbids is the reverse: a
collider derived from a mesh, or a visual transform a physics query can see. The
colliders here do not move — a part's physical footprint is fixed from placement
to destruction — and nothing in this section is read back by anything. An
Assembly with every mesh switched off simulates identically, which is what the
dedicated server does.

### 16.1 A Ground or Tracked Contact Hangs by Its Unconsumed Travel

```gdscript
static func droop_m(profile: MotiveAssemblyProfile, contact: MotiveContact) -> float:
    return profile.suspension_travel_limit_m - compression(profile, contact)
```

The mesh is drawn that many metres below its placement, **along the chassis's own
down axis** and not the part's — a wheel hangs down the hull, and the two
directions differ for every Motive Assembly not mounted upright.

Defining the offset as the travel the spring has *not* consumed, rather than from
the contact point, has three consequences worth stating:

- **It is bounded by construction.** The offset lives in `[0, travel_limit]`
  because `compression` is already clamped there, so no probe result — a hit
  inside the ground, a miss, a surface at a grazing angle — can throw the mesh
  anywhere a player would notice as a glitch.
- **It agrees with §6.1's authoring convention without depending on it.** That
  convention makes the rest length one full travel above the part's own collider,
  so full droop puts the wheel exactly on the surface and a bottomed-out one puts
  it in its placed cell. A row authored to a different convention is still drawn
  with its strut extended by the travel it has left, which is the honest answer
  either way.
- **An ungrounded contact reads zero compression and therefore full droop**, with
  no second code path. A wheel over a crest extends, which is what a real one
  does.

A tracked patch has one mesh and several road stations, so it is drawn at the
**mean** of its stations' droop. Averaging rather than picking one is what stops
a bogie snapping between stations as the ground passes under it.

### 16.2 A Rotor Disc Is Not Drawn From a Contact

The rotary family has no ground contact at all (§12), so there is nothing here
for it. Spinning the disc is doc 13's, and this section does not reach for it.

### 16.3 A Limb Is Drawn As the Virtual Leg It Is

§13.1 models a limb as one spring-damper along the hip-to-foot line and puts the
visible articulation under `VisualRoot`; §13.8 then states that no inverse
kinematics is specified here, and that stands. What is specified is one step
short of it and is the whole of what the model actually claims: **the part is
pivoted about its hip so that its leg axis points at its foot.**

The leg axis is the part's own local down under its placement orientation,
because §7.2.2 of document 01 puts `hip_offset_m` above everything the limb
occupies. A thigh that swings and reaches is the virtual leg drawn as what it is;
a jointed shank and a foot that flexes are a chain doc 13 may add later, and
nothing in this section forecloses one.

**The foot the presentation layer draws is not always the foot the simulation
planted.** While planted they are the same point. While swinging, §13.7's foot is
a parabolic arc from the point the limb left to the point it is reaching for,
peaking at `step_height_m`:

```gdscript
static func swing_foot_world(profile: LimbProfile, from_world: Vector3,
                             to_world: Vector3, t: float) -> Vector3:
    var u := clampf(t, 0.0, 1.0)
    return from_world.lerp(to_world, u) + Vector3.UP * swing_height_m(profile, u)
```

`t` is progress through the swing half of the cycle — zero at lift-off, one at
touchdown — and the target is **re-derived from §13.5's placement law every
tick** rather than frozen at lift-off. That is only safe because §13.7 applies no
force during swing: nothing drawn here can reach the physics, so a target that
tracks the body as it moves is honest rather than a feedback path, and the foot
lands where the next touchdown puts it instead of jumping there. The placement
law is called through one function with one set of arguments for both purposes,
because two derivations of one target would make the limb snap on every plant.

### 16.4 Where It Runs

`MotiveSystem.step` calls one pass after the families and after anti-roll, never
inside a family solver. §6.0 rule 1 says a family contributes `apply_force` and
`apply_torque` and nothing else, and that rule is worth keeping literally true;
the pass branches on the same `_family` array §11 invariant 12 sanctions, asking
a different question of it.

Cost is one dictionary lookup and one `Transform3D` composition per Motive
Assembly per tick, bounded by `MAX_MOTIVE_PER_ASSEMBLY`. On a dedicated server
the `part_visual` tag is off, every `AssemblyRuntime.visual_of` answers null, and
the pass is the lookup alone.

**The garage draws the placement pose, deliberately, and does not droop.** The
garage preview has no ground, no probes and no contacts, so there is no
compression to read and full droop would be the only answer available — which
would sink every wheel a full travel through the lattice floor the build is
standing on. What the garage shows is where the parts were *placed*, which is
what a build screen is for. The difference a player could see between the two
screens is the settled sag of a loaded spring, which is centimetres.
