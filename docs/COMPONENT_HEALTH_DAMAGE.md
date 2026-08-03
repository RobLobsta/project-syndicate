# COMPONENT_HEALTH_DAMAGE.md

**Project Syndicate — System Architecture Specification, Document 08 of 13**
**Subsystem:** Damage Parsing, Structural Integrity, Functional Degradation, Visual Damage States
**Status:** Normative.

---

## 1. Purpose

Damage in Project Syndicate is **localised**. There is no vehicle-wide health bar. Every part carries its own structural integrity, resists each damage channel differently, and degrades functionally as it is worn down. Destroying the right part matters more than dealing raw damage — shooting the wheels of a fleeing Assembly is a real tactic, not a cosmetic one.

This document specifies:

- How an impact becomes a damage packet.
- How each of the five damage channels resolves against a part.
- The master degradation table that every functional subsystem indexes.
- How band transitions are detected and broadcast — the event source that keeps the whole architecture free of per-frame health polling.
- Visual damage state progression.

---

## 2. Damage Channels

Five channels, frozen enumeration (`PART_DATA_SCHEMA.md` §4):

| Channel | Primary source | Distinguishing behaviour |
|---|---|---|
| `KINETIC` | Direct-fire projectiles | Penetration vs armour rating; angle-sensitive; can overpenetrate and spall |
| `BLAST` | Explosive detonation | Radial falloff with line-of-sight occlusion; affects many parts at once |
| `IMPACT` | Collisions, ramming, melee | Derived from collision impulse; damages both parties |
| `THERMAL` | Beams, incendiary, engine fire | Applies over time; accumulates heat as well as damage |
| `CORROSIVE` | Sustained-area effects | Ignores a portion of armour; damages resistance itself |

---

## 3. The Damage Packet

Every damage source produces a `DamagePacket`. `DamageResolver` is the single entry point; nothing writes `PartInstanceState.integrity` directly.

```gdscript
class_name DamagePacket
extends RefCounted

var target_assembly_id: int = -1
var target_slot: int = SyndicateConstants.INVALID_SLOT
var channel: PartEnums.DamageChannel = PartEnums.DamageChannel.KINETIC
var raw_amount: float = 0.0
var penetration: float = 0.0            # KINETIC only
var impact_point_world: Vector3 = Vector3.ZERO
var impact_normal_world: Vector3 = Vector3.ZERO
var incoming_direction: Vector3 = Vector3.ZERO
var source_assembly_id: int = -1
var source_slot: int = SyndicateConstants.INVALID_SLOT
var source_tick: int = 0
var chain_depth: int = 0                # guards recursive blast/detonation
var flags: int = 0                      # PACKET_SPALL, PACKET_OVERPEN, PACKET_DOT
```

### 3.1 Resolver Entry Point

```gdscript
class_name DamageResolver
extends Node

const MAX_CHAIN_DEPTH := 3

func apply(packet: DamagePacket) -> DamageOutcome:
    if not NetAuthority.is_server:
        return DamageOutcome.rejected("client cannot author damage")
    var assembly := AssemblyRegistry.get(packet.target_assembly_id)
    if assembly == null:
        return DamageOutcome.rejected("no assembly")
    var st: PartInstanceState = assembly.states[packet.target_slot]
    if st == null or (st.flags & (PartFlags.FLAG_DESTROYED | PartFlags.FLAG_DETACHED)) != 0:
        return DamageOutcome.rejected("part not live")

    var def := PartRegistry.definition(st.part_def_id)
    var effective := _compute_effective(packet, st, def, assembly)
    if effective <= 0.0:
        EventBus.damage_negated.emit(packet.target_assembly_id, packet.target_slot,
                                     packet.channel)
        return DamageOutcome.negated()

    var band_before := st.integrity_band
    st.integrity = maxf(0.0, st.integrity - effective)
    var band_after := _band_for(st.integrity / def.integrity_max)

    if band_after != band_before:
        st.integrity_band = band_after
        _on_band_transition(assembly, st, def, band_before, band_after, packet)

    st.flags |= PartFlags.FLAG_NET_DIRTY
    EventBus.part_damaged.emit(packet.target_assembly_id, packet.target_slot,
                               effective, packet.channel)
    return DamageOutcome.applied(effective, band_after)
```

**Amendment: `AssemblyRegistry` is an object, not a global.** This section and §5.3 both write `AssemblyRegistry.get(aid)`. `CLAUDE.md` §4 freezes the autoload list at eight, and a `static var` holding the same dictionary would be that global with less of the visibility that makes an autoload reviewable — so the registry is an ordinary `RefCounted` owned by the match scene and handed to the systems that need it, exactly as `DEPENDENCY_TREE_GRAPH.md` §6.2's `DebrisPool` is. The lookup is `registry.get_runtime(aid)`; the name changed too, because `Object.get` already exists and shadowing it would make every property read on the registry go somewhere surprising.

The registry's `ids()` is ascending, which §5.3 depends on: a blast frequently destroys parts across several Assemblies, and the order they are resolved in determines the order of `part_destroyed`, which determines debris body ordering on the network.

---

## 4. Kinetic Resolution

### 4.1 Angle of Incidence

Sloped armour is more effective because a projectile must traverse more material. With `θ` the angle between the incoming direction and the surface normal:

```
cos θ = clamp( −d̂ · n̂ , 0, 1 )
A_eff = A / max(cos θ, COS_FLOOR)          COS_FLOOR = 0.20
```

`COS_FLOOR` caps the benefit at 5× effective armour. Without it, a grazing hit would produce infinite effective armour and a mathematically guaranteed ricochet, which players correctly perceive as broken.

### 4.2 Ricochet

A hit below the ricochet angle with insufficient penetration deflects entirely:

```
ricochet  ⟺  cos θ < cos(RICOCHET_ANGLE_DEG)  AND  P < A_eff · RICOCHET_PEN_FACTOR
RICOCHET_ANGLE_DEG = 72.0
RICOCHET_PEN_FACTOR = 1.15
```

A ricochet does not consume the projectile. It reflects with `0.62` of its speed about the surface normal, with a small randomised scatter, and can hit something else. Ricochets deal `0.10 ×` damage on the deflection itself, so an extremely oblique hit is not entirely free for the target.

### 4.3 Penetration Ratio

```
ρ = P / A_eff

damage_multiplier(ρ) =
    0.0                              ρ < 0.55                  (defeated)
    0.42 · ((ρ − 0.55)/0.45)²        0.55 ≤ ρ < 1.0            (partial)
    1.0 + 0.30 · min(ρ − 1.0, 1.5)   ρ ≥ 1.0                   (full, capped +45%)
```

The quadratic ramp in the partial band matters for game feel: it makes the region just under the penetration threshold sharply unrewarding, so the difference between "my gun works against this armour" and "it doesn't" is legible to the player rather than a gentle gradient.

```gdscript
const COS_FLOOR := 0.20
const RICOCHET_COS := 0.309          # cos(72 degrees)
const RICOCHET_PEN_FACTOR := 1.15
const PEN_DEFEAT := 0.55

static func kinetic_multiplier(pen: float, armour: float, cos_theta: float) -> float:
    var a_eff := armour / maxf(cos_theta, COS_FLOOR)
    var rho := pen / maxf(a_eff, 0.01)
    if rho < PEN_DEFEAT:
        return 0.0
    if rho < 1.0:
        var t := (rho - PEN_DEFEAT) / (1.0 - PEN_DEFEAT)
        return 0.42 * t * t
    return 1.0 + 0.30 * minf(rho - 1.0, 1.5)
```

### 4.4 Overpenetration and Spall

A projectile with `ρ ≥ OVERPEN_RATIO = 1.85` passes through and continues with reduced energy:

```
P' = P − A_eff · 1.0
v' = v · sqrt(max(0, 1 − A_eff / P))
```

The velocity relation follows from treating armour traversal as a fixed energy cost proportional to `A_eff`.

Overpenetration additionally generates **spall** — a secondary `BLAST`-channel packet applied to parts behind the penetrated one:

```gdscript
const SPALL_FRACTION := 0.28
const SPALL_CONE_DEG := 34.0
const SPALL_RANGE_M := 2.4

func _generate_spall(packet: DamagePacket, effective: float,
                     assembly: AssemblyRuntime) -> void:
    if packet.chain_depth >= MAX_CHAIN_DEPTH:
        return
    var behind := LatticeQuery.cells_in_cone(
        assembly.occupancy,
        assembly.world_to_lattice(packet.impact_point_world),
        assembly.world_dir_to_lattice(packet.incoming_direction),
        SPALL_CONE_DEG, SPALL_RANGE_M)
    var slots := LatticeQuery.unique_slots(assembly.occupancy, behind)
    if slots.is_empty():
        return
    var share := effective * SPALL_FRACTION / float(slots.size())
    for slot in slots:
        var p := DamagePacket.new()
        p.target_assembly_id = packet.target_assembly_id
        p.target_slot = slot
        p.channel = PartEnums.DamageChannel.BLAST
        p.raw_amount = share
        p.impact_point_world = packet.impact_point_world
        p.incoming_direction = packet.incoming_direction
        p.source_assembly_id = packet.source_assembly_id
        p.source_slot = packet.source_slot
        p.chain_depth = packet.chain_depth + 1
        p.flags |= PacketFlags.PACKET_SPALL
        apply(p)
```

Spall is what makes interior layout meaningful: a Prime Mover tucked directly behind thin frontal armour takes spall damage from hits that never actually reach it.

---

## 5. Blast Resolution

### 5.1 Falloff

```
f(d) = (1 − clamp(d / R, 0, 1))^BLAST_EXPONENT      BLAST_EXPONENT = 1.85
```

The exponent above 1.0 concentrates damage near the epicentre, which rewards accurate placement of explosive ordnance over spamming it in the general direction of a target.

### 5.2 Occlusion

Blast does not pass freely through structure. For each candidate part, the segment from the blast centre to the part's centre is walked through the Assembly's occupancy lattice using the shared DDA traversal (`GRID_SNAPPING_LOGIC.md` §7.6), accumulating attenuation from each intervening cell's `OcclusionProfile`:

| Profile | Attenuation per cell |
|---|---|
| `OPAQUE_SOLID` | 0.22 |
| `LATTICE_POROUS` | 0.11 |
| `TRANSPARENT` | 0.00 |

```
occlusion = clamp( Σ_cells attenuation , 0 , OCCLUSION_MAX )      OCCLUSION_MAX = 0.88
effective_falloff = f(d) · (1 − occlusion)
```

The `OCCLUSION_MAX` cap of `0.88` guarantees that a deeply buried part still takes at least 12% of the falloff-adjusted blast. Full immunity through burial would make a single well-protected Core Module effectively invulnerable to explosives, which is not the intent.

### 5.3 Candidate Gathering

Blast candidates are gathered with **one** physics query, not per-part:

```gdscript
func resolve_blast(centre: Vector3, radius: float, damage: float,
                   source_assembly: int, source_slot: int, chain_depth: int) -> void:
    var space := _world.direct_space_state
    var params := PhysicsShapeQueryParameters3D.new()
    var sphere := SphereShape3D.new()
    sphere.radius = radius
    params.shape = sphere
    params.transform = Transform3D(Basis(), centre)
    params.collision_mask = CollisionLayers.MASK_BLAST_QUERY
    var hits := space.intersect_shape(params, 96)

    var touched := {}                      # assembly_id -> {slot: true}
    for h in hits:
        var body = h.collider
        if body is not ChassisBodyRef:
            continue
        var slot := body.slot_for_shape_index(h.shape)
        if slot == SyndicateConstants.INVALID_SLOT:
            continue
        var set: Dictionary = touched.get(body.assembly_id, {})
        set[slot] = true
        touched[body.assembly_id] = set

    var assembly_ids := touched.keys(); assembly_ids.sort()
    for aid in assembly_ids:
        var assembly := AssemblyRegistry.get(aid)
        var slots := touched[aid].keys(); slots.sort()
        for slot in slots:
            _apply_blast_to_slot(assembly, slot, centre, radius, damage,
                                 source_assembly, source_slot, chain_depth)
```

Sorting assembly ids and slots is required for determinism. Blast frequently destroys multiple parts in one call, and the order in which they die determines the order of `part_destroyed` events, which determines debris body ordering on the network.

### 5.4 Shape-Index to Slot Mapping

The mapping from a Godot collision shape index back to a part slot is maintained at collider spawn time and never searched:

```gdscript
class_name ChassisBodyRef
extends RigidBody3D

var assembly_id: int = 0
var _shape_to_slot: PackedByteArray = PackedByteArray()

func register_shape(shape_index: int, slot: int) -> void:
    # Grown with INVALID_SLOT rather than a zero-filling resize: slot 0 is the
    # Core Module, so an index left unassigned would otherwise report a hit on
    # the one part whose loss terminates the Assembly.
    while _shape_to_slot.size() <= shape_index:
        _shape_to_slot.append(SyndicateConstants.INVALID_SLOT)
    _shape_to_slot[shape_index] = slot

func slot_for_shape_index(shape_index: int) -> int:
    if shape_index < 0 or shape_index >= _shape_to_slot.size():
        return SyndicateConstants.INVALID_SLOT
    return _shape_to_slot[shape_index]
```

Indices are assigned in ascending slot order when the Assembly spawns and never move afterwards, which is why the array can be flat. A part taken out of the simulation has its shapes **disabled**, not removed — see `DYNAMIC_MASS_PHYSICS.md` §2.

This is a one-byte array lookup. It is the entire mechanism by which "which part did I hit" is answered, and it is O(1) precisely because colliders are authored primitives with stable indices rather than generated geometry.

---

## 6. Impact Resolution

### 6.1 Impulse to Damage

Collision damage derives from the normal impulse `J` exchanged at the contact, the relative mass of the two bodies, and a threshold below which nothing happens.

```
m_rel = (m_a · m_b) / (m_a + m_b)
v_eff = |J| / m_rel
damage = IMPACT_K · max(0, v_eff − IMPACT_THRESHOLD_MPS)^IMPACT_EXPONENT
```

with `IMPACT_K = 2.4`, `IMPACT_THRESHOLD_MPS = 3.5`, `IMPACT_EXPONENT = 1.15`.

The threshold is essential. Without it, an Assembly resting on the ground takes continuous micro-damage from contact resolution noise.

```gdscript
const IMPACT_K := 2.4
const IMPACT_THRESHOLD_MPS := 3.5
const IMPACT_EXPONENT := 1.15
const IMPACT_MAX_PER_CONTACT := 900.0

func _on_body_contact(body_a: ChassisBodyRef, body_b: PhysicsBody3D,
                      contact: ContactRecord) -> void:
    var m_a := body_a.mass
    var m_b := body_b.mass if body_b is RigidBody3D else 1.0e9
    var m_rel := (m_a * m_b) / (m_a + m_b)
    var v_eff := contact.impulse.length() / maxf(m_rel, 0.001)
    if v_eff <= IMPACT_THRESHOLD_MPS:
        return
    var dmg := minf(IMPACT_K * pow(v_eff - IMPACT_THRESHOLD_MPS, IMPACT_EXPONENT),
                    IMPACT_MAX_PER_CONTACT)
    _submit_impact_damage(body_a, contact, dmg)
    if body_b is ChassisBodyRef:
        _submit_impact_damage(body_b, contact.mirrored(), dmg)
```

Both parties take damage. Ramming is a legitimate strategy, and it should hurt the rammer too — which is what makes dedicated ram Effector Modules (with their `0.62` IMPACT resistance) worth their mass.

### 6.2 Contact Rate Limiting

A sustained scrape produces a contact every tick. Without limiting, dragging along a wall would destroy an Assembly in seconds.

```gdscript
const IMPACT_COOLDOWN_S := 0.22

func _submit_impact_damage(body: ChassisBodyRef, contact: ContactRecord,
                           dmg: float) -> void:
    var slot := body.slot_for_shape_index(contact.local_shape)
    var key := body.assembly_id * 256 + slot
    var now := MatchClock.time_s
    if now - _last_impact_time.get(key, -999.0) < IMPACT_COOLDOWN_S:
        return
    _last_impact_time[key] = now
    # ... construct and apply the packet
```

Also, `deposit_impact_force` feeds the `F_impact(s)` term of the strain model (`DEPENDENCY_TREE_GRAPH.md` §4.1) with an exponentially decaying value. `IMPACT_DECAY_TAU_S` is `0.9` — a little over half a second to fall to a third, so a ram loads the joints it went through for about as long as the collision is still visible, and no longer. The deposit lives on the `ChassisGraph` alongside the recoil deposit, is decayed by the same `decay_deposits(dt)` call, and is dropped from the active set below `DEPOSIT_FLOOR_N = 1.0` newton, which is far under the resolution of any joint strength in the part tables:

```gdscript
func deposit_impact_force(slot: int, newtons: float) -> void:
    _impact_deposit[slot] = maxf(_impact_deposit[slot], newtons)
    _impact_decay_active = true

func _decay_impact_deposits(dt: float) -> void:
    if not _impact_decay_active:
        return                              # zero cost when nothing is loaded
    var any := false
    for slot in _impact_deposit.keys():
        _impact_deposit[slot] *= exp(-dt / IMPACT_DECAY_TAU_S)
        if _impact_deposit[slot] > 1.0:
            any = true
        else:
            _impact_deposit.erase(slot)
    _impact_decay_active = any
```

---

## 7. Thermal and Corrosive

### 7.1 Thermal

Thermal damage applies over time and simultaneously raises `accumulated_heat_hu`:

```
damage_per_second = raw_amount · (1 − resist_THERMAL)
heat_per_second   = raw_amount · THERMAL_HEAT_RATIO      THERMAL_HEAT_RATIO = 0.55
```

A part whose heat exceeds `THERMAL_IGNITION_HU = 480` gains `FLAG_OVERHEATED` and begins self-damaging at `4.0 damage/s` until heat drops below `320` — a hysteresis band that prevents flicker. Prime Movers ignite at their `thermal_shutdown_hu` and stop producing torque entirely.

### 7.2 Corrosive

Corrosive bypasses a flat fraction of armour and permanently degrades resistance:

```
effective_armour = A · (1 − CORROSIVE_ARMOUR_BYPASS)     CORROSIVE_ARMOUR_BYPASS = 0.40
resist[c] ← max(0, resist[c] − CORROSIVE_RESIST_DECAY · dt)   for all c
CORROSIVE_RESIST_DECAY = 0.035 per second of exposure
```

Resistance decay is stored as a per-instance `resist_modifier` array on `PartInstanceState`, not by mutating the shared `PartDefinition` — which is immutable by contract.

### 7.3 Damage-Over-Time Scheduling

DOT effects are not evaluated per part per frame. They live in a single flat list processed at 10 Hz:

```gdscript
class_name DotScheduler
extends Node

const TICK_INTERVAL_S := 0.1
var _entries: Array[DotEntry] = []
var _accum: float = 0.0

func _physics_process(dt: float) -> void:
    if _entries.is_empty():
        return                              # zero cost when nothing is burning
    _accum += dt
    if _accum < TICK_INTERVAL_S:
        return
    var elapsed := _accum
    _accum = 0.0
    var i := _entries.size() - 1
    while i >= 0:
        var e := _entries[i]
        e.remaining_s -= elapsed
        var p := e.build_packet(elapsed)
        DamageResolver.apply(p)
        if e.remaining_s <= 0.0:
            _entries.remove_at(i)
        i -= 1
```

The early return on an empty list is the important line: in a match with nothing on fire, the DOT system costs a single array size check per tick.

---

## 8. Integrity Bands and Functional Degradation

### 8.1 Band Definition

```gdscript
static func _band_for(fraction: float) -> int:
    if fraction <= 0.0:                                  return PartEnums.IntegrityBand.DESTROYED
    if fraction < SyndicateConstants.BAND_CRITICAL:      return PartEnums.IntegrityBand.CRITICAL
    if fraction < SyndicateConstants.BAND_IMPAIRED:      return PartEnums.IntegrityBand.IMPAIRED
    if fraction < SyndicateConstants.BAND_STRESSED:      return PartEnums.IntegrityBand.STRESSED
    return PartEnums.IntegrityBand.NOMINAL
```

### 8.2 Master Degradation Table

This is the canonical table. Every subsystem indexes it by band. No subsystem defines its own thresholds.

| Part class | Effect | NOMINAL | STRESSED | IMPAIRED | CRITICAL |
|---|---|---|---|---|---|
| `MOTIVE_ASSEMBLY` | Traction multiplier | 1.00 | 0.88 | **0.60** | 0.35 |
| | Rolling resistance multiplier | 1.00 | 1.00 | 1.35 | 1.90 |
| | Steer rate multiplier | 1.00 | 1.00 | 1.00 | 0.50 |
| | Suspension damping multiplier | 1.00 | 1.00 | 1.00 | 0.60 |
| | Spark VFX | off | off | **on** | heavy |
| `EFFECTOR_MODULE` | Slew rate multiplier | 1.00 | 0.92 | 0.74 | 0.45 |
| | Cycle time multiplier | 1.00 | 1.06 | 1.22 | 1.60 |
| | Spread multiplier | 1.00 | 1.15 | 1.45 | 2.10 |
| | Jam chance per shot | 0.00 | 0.00 | 0.00 | **0.18** |
| `PRIME_MOVER` | Torque multiplier | 1.00 | 0.90 | 0.68 | 0.38 |
| | Power supply multiplier | 1.00 | 0.94 | 0.75 | 0.45 |
| | Heat generation multiplier | 1.00 | 1.12 | 1.38 | 1.85 |
| | Smoke VFX | off | light | heavy | flame |
| `SUPPORT_MODULE` | Effect magnitude multiplier | 1.00 | 0.88 | 0.62 | 0.30 |
| `CONTROL_SURFACE` | Coefficient multiplier | 1.00 | 0.85 | 0.55 | 0.20 |
| `CORE_MODULE` | Control authority multiplier | 1.00 | 0.95 | 0.82 | 0.60 |
| | Speed cap multiplier | 1.00 | 1.00 | 0.90 | 0.72 |
| `STRUCTURAL_COMPONENT` | Load capacity multiplier | 1.00 | 0.90 | 0.65 | 0.30 |
| | Joint strength multiplier | 1.00 | 0.92 | 0.70 | 0.35 |
| `APPENDAGE` | Held-module cycle multiplier | 1.00 | 1.12 | 1.45 | 2.20 |
| **All classes** | Armour rating multiplier | 1.00 | 0.94 | 0.80 | 0.58 |

The two mandated behaviours appear here verbatim: a Motive Assembly below 50% integrity enters `IMPAIRED`, loses 40% of its traction (multiplier `0.60`), and sparks; an Effector Module below 30% enters `CRITICAL` and gains an 18% per-shot jam chance.

The `APPENDAGE` row is the only one in this table read against a slot **other than the one whose band changed**: it scales the cycle time of the Effector Module the arm is *holding*, not the arm's own. `EffectorSystem` resolves the holder by walking the Chassis Graph up from the module at registration, and the two cycle multipliers compose — an `IMPAIRED` edge in an `IMPAIRED` arm cycles at `1.22 x 1.45`. This is what makes shooting the arm a better idea than shooting the sword.

Note the last row. Armour rating degrades with integrity across all classes, which means a battered panel becomes progressively easier to penetrate. This creates a natural escalation: the first hits are absorbed, later hits go through.

### 8.3 The Table in Code

```gdscript
class_name DegradationTable
extends RefCounted

const MOTIVE_TRACTION  := [1.00, 0.88, 0.60, 0.35, 0.00]
const MOTIVE_ROLLING   := [1.00, 1.00, 1.35, 1.90, 0.00]
const MOTIVE_STEER     := [1.00, 1.00, 1.00, 0.50, 0.00]
const MOTIVE_SUSP_DAMP := [1.00, 1.00, 1.00, 0.60, 0.00]
const EFF_SLEW         := [1.00, 0.92, 0.74, 0.45, 0.00]
const EFF_CYCLE        := [1.00, 1.06, 1.22, 1.60, 0.00]
const EFF_SPREAD       := [1.00, 1.15, 1.45, 2.10, 0.00]
const EFF_JAM          := [0.00, 0.00, 0.00, 0.18, 0.00]
const POWER_TORQUE     := [1.00, 0.90, 0.68, 0.38, 0.00]
const POWER_SUPPLY     := [1.00, 0.94, 0.75, 0.45, 0.00]
const POWER_HEAT       := [1.00, 1.12, 1.38, 1.85, 0.00]
const SUPPORT_MAGNITUDE:= [1.00, 0.88, 0.62, 0.30, 0.00]
const CONTROL_COEFF    := [1.00, 0.85, 0.55, 0.20, 0.00]
const CORE_AUTHORITY   := [1.00, 0.95, 0.82, 0.60, 0.00]
const CORE_SPEED_CAP   := [1.00, 1.00, 0.90, 0.72, 0.00]
const STRUCT_LOAD      := [1.00, 0.90, 0.65, 0.30, 0.00]
const STRUCT_JOINT     := [1.00, 0.92, 0.70, 0.35, 0.00]
const ARMOUR_RATING    := [1.00, 0.94, 0.80, 0.58, 0.00]
```

A CI test (`tests/unit/test_degradation_table.gd`) asserts every array has exactly five entries, is monotonically non-increasing (except `MOTIVE_ROLLING`, `POWER_HEAT`, `EFF_CYCLE`, `EFF_SPREAD`, and `EFF_JAM`, which are non-decreasing by design), and ends with `0.00`.

### 8.4 Band Transition — The Event Source

Band transitions are where the entire event-driven architecture gets its energy. Nothing polls health; everything reacts to this one function.

```gdscript
func _on_band_transition(assembly: AssemblyRuntime, st: PartInstanceState,
                         def: PartDefinition, before: int, after: int,
                         packet: DamagePacket) -> void:
    st.flags |= PartFlags.FLAG_VISUAL_DIRTY | PartFlags.FLAG_NET_DIRTY

    EventBus.part_band_changed.emit(assembly.assembly_id, st.slot, before, after)

    match def.part_class:
        PartEnums.PartClass.MOTIVE_ASSEMBLY:
            assembly.motive_system.on_band_changed(st.slot, after)
        PartEnums.PartClass.EFFECTOR_MODULE:
            assembly.effector_system.on_band_changed(st.slot, after)
        PartEnums.PartClass.PRIME_MOVER:
            assembly.power_system.on_band_changed(st.slot, after)
        PartEnums.PartClass.SUPPORT_MODULE:
            assembly.support_system.on_band_changed(st.slot, after)
        PartEnums.PartClass.CONTROL_SURFACE:
            assembly.aero_system.on_band_changed(st.slot, after)
        PartEnums.PartClass.STRUCTURAL_COMPONENT:
            assembly.graph.on_joint_strength_changed(st.slot, after)
        PartEnums.PartClass.CORE_MODULE:
            assembly.control_system.on_band_changed(st.slot, after)

    VisualDamageController.apply_state(assembly, st, def, after)
    FusionInstanceWriter.write(assembly.visual_node(st.slot), st, def)

    if after == PartEnums.IntegrityBand.DESTROYED:
        _destroy_part(assembly, st, def, packet)
```

Each `on_band_changed` handler does the same thing: write a cached multiplier into a flat array that its hot loop already reads. For example:

```gdscript
# MotiveSystem
func on_band_changed(slot: int, band: int) -> void:
    _traction_mult[slot] = DegradationTable.MOTIVE_TRACTION[band]
    _rolling_mult[slot] = DegradationTable.MOTIVE_ROLLING[band]
    _steer_mult[slot] = DegradationTable.MOTIVE_STEER[band]
    _damp_mult[slot] = DegradationTable.MOTIVE_SUSP_DAMP[band]
    if band == PartEnums.IntegrityBand.IMPAIRED:
        SparkVfx.enable(slot, SparkVfx.Intensity.LIGHT)
    elif band == PartEnums.IntegrityBand.CRITICAL:
        SparkVfx.enable(slot, SparkVfx.Intensity.HEAVY)
    else:
        SparkVfx.disable(slot)
```

The physics loop then reads `_traction_mult[slot]` — a float array index. It never touches integrity, never computes a band, and never branches on health. This is the pattern the whole codebase follows.

### 8.5 Destruction

```gdscript
func _destroy_part(assembly: AssemblyRuntime, st: PartInstanceState,
                   def: PartDefinition, packet: DamagePacket) -> void:
    st.flags |= PartFlags.FLAG_DESTROYED
    st.integrity = 0.0

    # Volatile modules and Prime Movers detonate on destruction.
    if def.part_class == PartEnums.PartClass.PRIME_MOVER:
        var pp := def.prime_mover_profile
        _queue_detonation(assembly, st, pp.detonation_blast_radius_m,
                          pp.detonation_blast_damage, packet.chain_depth + 1)
    elif def.part_class == PartEnums.PartClass.SUPPORT_MODULE \
         and def.support_profile.volatile_on_destruction:
        var rounds := AmmoLedger.rounds_stored(assembly.assembly_id, st.slot)
        _queue_detonation(assembly, st, 3.2 + 0.004 * rounds,
                          140.0 + 0.9 * rounds, packet.chain_depth + 1)

    EventBus.part_destroyed.emit(assembly.assembly_id, st.slot, packet.channel)
```

`part_destroyed` is consumed by `DetachmentScheduler`, which batches it to end-of-tick (`DEPENDENCY_TREE_GRAPH.md` §5.5). Detonations are queued rather than applied immediately, for the same reason: applying a blast inside a damage resolution would re-enter the resolver mid-iteration.

```gdscript
func _queue_detonation(assembly, st, radius, damage, chain_depth) -> void:
    if chain_depth > MAX_CHAIN_DEPTH:
        return
    _detonation_queue.push_back({
        "centre": assembly.part_world_position(st.slot),
        "radius": radius, "damage": damage,
        "assembly": assembly.assembly_id, "slot": st.slot,
        "chain_depth": chain_depth})

func _flush_detonations() -> void:      # called from EventBus tick_resolved, PRIORITY_DAMAGE
    while not _detonation_queue.is_empty():
        var d = _detonation_queue.pop_front()
        resolve_blast(d.centre, d.radius, d.damage, d.assembly, d.slot, d.chain_depth)
```

`MAX_CHAIN_DEPTH = 3` bounds chain reactions. A magazine detonating a Prime Mover detonating a second magazine is spectacular; unbounded recursion is a server hang.

---

## 9. Visual Damage States

Visual damage has three independent layers, all driven by band transitions and none of them per-frame.

### 9.1 Layer A — Material Response

Handled entirely by the fusion shader through `INSTANCE_CUSTOM` (`PART_FUSION_SHADER.md` §3.4). Integrity fraction drives albedo darkening, roughness increase, and metallic reduction. Cost: one instance-uniform write per band change.

### 9.2 Layer B — Mesh State Swap

Parts may declare damage mesh variants in `PartVisualProfile`:

```gdscript
@export var mesh_nominal: Mesh = null
@export var mesh_impaired: Mesh = null       # optional; dents, missing detail
@export var mesh_critical: Mesh = null       # optional; torn, bent, exposed frame
```

```gdscript
class_name VisualDamageController
extends RefCounted

static func apply_state(assembly: AssemblyRuntime, st: PartInstanceState,
                        def: PartDefinition, band: int) -> void:
    var mi: MeshInstance3D = assembly.visual_node(st.slot)
    var vp := def.visual_profile
    var target: Mesh = vp.mesh_nominal
    if band >= PartEnums.IntegrityBand.CRITICAL and vp.mesh_critical != null:
        target = vp.mesh_critical
    elif band >= PartEnums.IntegrityBand.IMPAIRED and vp.mesh_impaired != null:
        target = vp.mesh_impaired
    if mi.mesh != target:
        mi.mesh = target
        EventBus.part_visual_swapped.emit(assembly.assembly_id, st.slot)
```

**The collider does not change.** A part with a torn-off corner in its critical mesh still occupies the same `ColliderProfile` box. This is Architectural Invariant #1 applied to damage: the physical footprint of a part is fixed for its entire life, from placement to destruction. Hit registration is therefore stable regardless of visual state, and the network never needs to replicate collider geometry.

The swap also marks the fusion SDF dirty, because a critical mesh may expose surfaces the nominal mesh did not — but the SDF is built from *lattice occupancy*, not from meshes, so in practice the SDF is unchanged and the rebuild is skipped by the change detector.

### 9.3 Layer C — Persistent Impact Decals

Individual hits leave decals independent of band. Decals are pooled per Assembly with a hard cap:

```gdscript
const MAX_DECALS_PER_ASSEMBLY := 48

func spawn_impact_decal(assembly: AssemblyRuntime, packet: DamagePacket,
                        effective: float) -> void:
    if effective < DECAL_MIN_DAMAGE:
        return
    var decal := assembly.decal_pool.acquire()      # recycles oldest when full
    decal.global_position = packet.impact_point_world
    decal.look_at_from_position(packet.impact_point_world,
        packet.impact_point_world - packet.impact_normal_world, Vector3.UP)
    decal.size = Vector3(_decal_size(effective), 0.4, _decal_size(effective))
    decal.texture_albedo = DecalAtlas.for_channel(packet.channel)
    decal.modulate.a = clampf(effective / 300.0, 0.35, 1.0)
    decal.cull_mask = RenderLayers.LAYER_ASSEMBLY_VISUAL
```

Decals are parented under `VisualRoot`, inherit its interpolated transform, and have no collision.

### 9.4 Layer D — Particle Effects

VFX are attached and detached at band transitions only, never evaluated per frame:

| Trigger | Effect |
|---|---|
| Motive `IMPAIRED` | Contact spark emitter, 12 particles/s, tied to contact point |
| Motive `CRITICAL` | Contact spark emitter, 34 particles/s, plus intermittent smoke puff |
| Prime Mover `STRESSED` | Light smoke column, 0.4 opacity |
| Prime Mover `IMPAIRED` | Heavy smoke column, 0.8 opacity |
| Prime Mover `CRITICAL` | Flame jet plus heavy smoke; audible alarm loop |
| Effector `CRITICAL` | Sparking at the breech on each fire attempt |
| Any part `DESTROYED` | One-shot debris burst; emitter released to pool |
| `FLAG_OVERHEATED` set | Heat shimmer distortion quad |

All emitters come from a shared `VfxPool` sized at 256 emitters globally, with distance-based culling beyond `65 m` and a hard budget of 24 simultaneous emitters per Assembly.

---

## 10. Repair

Repair Emitter Support Modules restore integrity over time to the **most damaged live part within radius**, one part at a time. Repairing broadly would make the whole system mushy; repairing the worst part first makes the module tactically legible.

```gdscript
func _repair_tick(assembly: AssemblyRuntime, emitter_slot: int, dt: float) -> void:
    var def := PartRegistry.definition(assembly.states[emitter_slot].part_def_id)
    var band := assembly.states[emitter_slot].integrity_band
    var rate := def.support_profile.effect_magnitude \
              * DegradationTable.SUPPORT_MAGNITUDE[band]

    var worst := SyndicateConstants.INVALID_SLOT
    var worst_fraction := 1.0
    for slot in assembly.graph.live_slots():
        var st: PartInstanceState = assembly.states[slot]
        var d := PartRegistry.definition(st.part_def_id)
        var f := st.integrity / d.integrity_max
        if f < worst_fraction and f > 0.0:
            worst_fraction = f
            worst = slot
    if worst == SyndicateConstants.INVALID_SLOT:
        return

    var st: PartInstanceState = assembly.states[worst]
    var d := PartRegistry.definition(st.part_def_id)
    var before := st.integrity_band
    st.integrity = minf(d.integrity_max, st.integrity + rate * dt)
    var after := DamageResolver._band_for(st.integrity / d.integrity_max)
    if after != before:
        st.integrity_band = after
        DamageResolver._on_band_transition(assembly, st, d, before, after, null)
```

Repair uses the same band transition path, so a repaired wheel restores its traction multiplier and disables its spark VFX through exactly the same code that degraded it. There is no separate "un-degrade" logic to drift out of sync.

**Destroyed parts are never repaired.** Once integrity reaches zero the part is detached and gone. Restoring it would require re-inserting into the occupancy lattice, the Chassis Graph, the mass solver, and the network state — an entire second lifecycle with its own failure modes, for a mechanic the design does not need.

---

## 11. Determinism and Network Authority

1. Damage is authored only on the server. `DamageResolver.apply` returns `rejected` on a client.
2. Blast candidate iteration is sorted by assembly id then slot.
3. Chain depth is bounded at 3.
4. Detonations are queued and flushed at `PRIORITY_DAMAGE` within `tick_resolved`, never applied re-entrantly.
5. `integrity` is replicated as `uint8` of the fraction; `integrity_band` is replicated as a separate 3-bit field and is authoritative. Clients never derive band from the quantised fraction, because a value rounding across a boundary would produce divergent degradation multipliers.
6. Clients apply predicted damage to their own Assembly for immediate feedback but reconcile to authoritative integrity on every snapshot, correcting over `0.15 s`.

---

## 12. Performance Budget

Reference target, 16-player match, active engagement:

| Operation | Budget | Typical |
|---|---|---|
| Kinetic packet resolution | 0.004 ms | 0.0016 ms |
| Blast resolution (1 detonation, 14 parts) | 0.45 ms | 0.22 ms |
| Impact contact processing (per contact) | 0.006 ms | 0.003 ms |
| DOT scheduler (10 Hz, 20 entries) | 0.08 ms | 0.03 ms |
| Band transition handling | 0.02 ms | 0.008 ms |
| Visual state swap | 0.05 ms | 0.02 ms |
| Decal spawn | 0.03 ms | 0.01 ms |
| **Peak tick (multi-Assembly blast)** | **2.20 ms** | **1.15 ms** |

Steady-state cost with no active damage is **zero**: the DOT scheduler returns on an empty list, the impact decay returns on an inactive flag, and nothing else runs.

---

## 13. Invariants

1. `DamageResolver.apply` is the only writer of `PartInstanceState.integrity` outside of repair, which routes through the same band transition path.
2. Colliders never change with damage state. Visual meshes may swap; the `ColliderProfile` is fixed for a part's entire life.
3. Functional degradation is applied through cached multiplier arrays written at band transitions. No hot loop reads integrity.
4. Every degradation threshold comes from `SyndicateConstants` band constants and `DegradationTable`. No subsystem defines its own.
5. Chain reactions are bounded at depth 3 and are queued, never re-entrant.
6. Blast iteration order is deterministic.
7. Destroyed parts are never restored.
8. All damage VFX are attached and detached on band transitions, never polled.
9. `integrity_band` is replicated explicitly and is authoritative over the quantised integrity fraction.
