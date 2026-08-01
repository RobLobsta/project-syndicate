# WEAPON_TARGETING_LOGIC.md

**Project Syndicate — System Architecture Specification, Document 07 of 13**
**Subsystem:** Effector Hardpoints, Aim Solving, Projectile Emission
**Status:** Normative.

---

## 1. Purpose

This document specifies how player and AI intent becomes a projectile in the world. It covers the two-degree-of-freedom hardpoint mechanism, rotation limits and slew rates, the aim-solve mathematics including ballistic lead and arced-trajectory solutions, the projectile emission loop and its pooling model, and the degradation behaviour that makes a damaged Effector Module jam.

The subsystem is server-authoritative. Clients run an identical predictive copy for responsiveness, but every projectile that can deal damage originates on the server. Section 11 defines exactly what is predicted and what is reconciled.

---

## 2. Hardpoint Node Structure

Every Effector Module instantiates a small, fixed node structure under `VisualRoot`. Note that the hardpoint hierarchy is **visual and kinematic only** — it carries no collision shapes. The Effector Module's collision presence remains the `ColliderProfile` primitives attached to `ChassisBody`, in its rest orientation. A rotated turret does not rotate its collider.

```
part_s014                  (Node3D)        ← part root, at the part's lattice position
└── HardpointYaw           (Node3D)        ← rotates about local +Y
    └── HardpointPitch     (Node3D)        ← rotates about local +X
        ├── Barrel         (MeshInstance3D)
        ├── Muzzle_0       (Marker3D)      ← muzzle_offsets_m[0]
        ├── Muzzle_1       (Marker3D)
        └── RecoilPivot    (Node3D)        ← animated recoil translation
```

This is a deliberate consequence of Architectural Invariant #1. A player shooting at a turret hits the boxy collider footprint, not the swung barrel. That is a gameplay simplification, and it is the correct one: it makes hit registration stable, cheap, and identical on client and server regardless of animation state, and it eliminates the entire category of "my shot passed through the barrel" desync complaints.

### 2.1 Kinematic State

```gdscript
class_name HardpointState
extends RefCounted

var slot: int = SyndicateConstants.INVALID_SLOT
var yaw_rad: float = 0.0          # current, within limits
var pitch_rad: float = 0.0
var yaw_target_rad: float = 0.0   # commanded
var pitch_target_rad: float = 0.0
var on_target: bool = false       # within convergence tolerance AND arc-clear
var blocked_sectors: PackedByteArray = PackedByteArray()   # 24 bits, 15deg each
var cycle_timer_s: float = 0.0
var burst_remaining: int = 0
var burst_recovery_s: float = 0.0
var rounds_in_magazine: int = 0
var reload_timer_s: float = 0.0
var jam_timer_s: float = 0.0
var heat_hu: float = 0.0
var spread_current_deg: float = 0.0
var next_muzzle_index: int = 0
```

All hardpoint state for an Assembly lives in a contiguous `Array[HardpointState]` sized to the Assembly's Effector Module count — at most 16. Iteration is a tight loop over a handful of objects.

---

## 3. Rotation Limits

### 3.1 Limit Frames

`yaw_limit_deg` and `pitch_limit_deg` from `EffectorModuleProfile` are expressed in the **part's rest frame**, before the part's lattice orientation is applied. A turret authored with `yaw_limit_deg = (-180, 180)` mounted rotated 90° about Y still traverses a full circle; a fixed forward mount authored `(-25, 25)` mounted facing rearward covers ±25° about rearward.

The rest-frame-to-assembly transform is the part's orientation basis:

```
B_part = OrientationTable.basis_for(orientation_index)
```

Aim directions are converted into the part rest frame before decomposition, so the limits apply in the frame they were authored in:

```gdscript
func _to_rest_frame(state: PartInstanceState, dir_assembly: Vector3) -> Vector3:
    return OrientationTable.basis_for(state.orientation_index).inverse() * dir_assembly
```

### 3.2 Yaw Wrapping

Yaw limits spanning the full circle (`x <= -180` and `y >= 180`) mark the hardpoint **unlimited**, and yaw is wrapped rather than clamped. This distinction matters: a clamped full-circle turret would refuse to cross the ±180° seam, producing the "turret spins the long way round" artefact.

```gdscript
func _apply_yaw_limit(profile: EffectorModuleProfile, desired: float,
                      current: float) -> float:
    var lo := deg_to_rad(profile.yaw_limit_deg.x)
    var hi := deg_to_rad(profile.yaw_limit_deg.y)
    if lo <= -PI + 0.001 and hi >= PI - 0.001:
        # Unlimited: take the shortest signed path across the seam.
        return current + wrapf(desired - current, -PI, PI)
    return clampf(desired, lo, hi)
```

### 3.3 Slew Rates and Degradation

Rotation is rate-limited per tick. The rate is scaled by the Effector Module's integrity band, using the shared degradation table family:

| Band | Slew multiplier | Cycle-time multiplier | Spread multiplier | Jam chance per shot |
|---|---|---|---|---|
| `NOMINAL` | 1.00 | 1.00 | 1.00 | 0.000 |
| `STRESSED` | 0.92 | 1.06 | 1.15 | 0.000 |
| `IMPAIRED` | 0.74 | 1.22 | 1.45 | 0.000 |
| `CRITICAL` | 0.45 | 1.60 | 2.10 | **0.18** |
| `DESTROYED` | — | — | — | — |

The `CRITICAL` band begins at 30% integrity, so "a weapon below 30% HP begins to jam" is expressed exactly: an 18% chance per shot of entering a jam state lasting `jam_clear_time_s`. `STRESSED` and `IMPAIRED` never jam — the progression is deliberately telegraphed through slower traverse, longer cycle time, and widening spread long before jams start, so the player feels the weapon degrading rather than being blindsided.

```gdscript
const EFF_SLEW_MULT   := [1.00, 0.92, 0.74, 0.45, 0.0]
const EFF_CYCLE_MULT  := [1.00, 1.06, 1.22, 1.60, 0.0]
const EFF_SPREAD_MULT := [1.00, 1.15, 1.45, 2.10, 0.0]
const EFF_JAM_CHANCE  := [0.00, 0.00, 0.00, 0.18, 0.0]

func _slew(hp: HardpointState, profile: EffectorModuleProfile,
           band: int, dt: float) -> void:
    var mult: float = EFF_SLEW_MULT[band]
    var yaw_step := deg_to_rad(profile.yaw_rate_deg_s) * mult * dt
    var pitch_step := deg_to_rad(profile.pitch_rate_deg_s) * mult * dt
    hp.yaw_rad = move_toward(hp.yaw_rad, hp.yaw_target_rad, yaw_step)
    hp.pitch_rad = move_toward(hp.pitch_rad, hp.pitch_target_rad, pitch_step)
```

Band is read from the cached `PartInstanceState.integrity_band` integer. No health arithmetic occurs in the targeting loop.

### 3.4 Blocked Sectors

`GRID_SNAPPING_LOGIC.md` §7.6 computes which yaw sectors are obstructed by the Assembly's own structure at build time. That result is stored as a 24-bit mask (one bit per 15° sector) on `HardpointState.blocked_sectors` and recomputed **only** when `assembly_structure_changed` fires — meaning a destroyed panel can *open* a previously blocked firing arc mid-match, which is a genuinely satisfying emergent behaviour.

```gdscript
func _sector_of(yaw_rad: float) -> int:
    return int(floor(wrapf(yaw_rad, 0.0, TAU) / (TAU / 24.0))) % 24

func _is_blocked(hp: HardpointState, yaw_rad: float) -> bool:
    var s := _sector_of(yaw_rad)
    return (hp.blocked_sectors[s >> 3] & (1 << (s & 7))) != 0
```

A hardpoint whose commanded yaw lands in a blocked sector still slews there — the barrel visibly points into the obstruction — but `on_target` is false and the emission gate refuses to fire. Refusing to fire is strictly better than firing into the Assembly's own hull, and better than silently redirecting aim, which would feel like the game fighting the player.

---

## 4. Aim Solving

### 4.1 The Aim Point

Aim input arrives as a world-space **aim point**, not a direction. For a human player it is produced by a camera ray cast against the world; for AI it is the output of the intercept solver (§5).

```gdscript
func _resolve_player_aim_point(camera: Camera3D, screen_pos: Vector2,
                               space: PhysicsDirectSpaceState3D) -> Vector3:
    var origin := camera.project_ray_origin(screen_pos)
    var dir := camera.project_ray_normal(screen_pos)
    var params := PhysicsRayQueryParameters3D.create(origin, origin + dir * AIM_RANGE_M)
    params.collision_mask = CollisionLayers.MASK_AIM_TRACE
    params.exclude = [_own_body_rid]
    var hit := space.intersect_ray(params)
    return hit.get("position", origin + dir * AIM_RANGE_M)
```

Excluding the player's own body is what allows aiming "through" one's own hull — otherwise the reticle would snap to the player's own armour whenever the camera looked across it.

### 4.2 Per-Hardpoint Convergence

Each hardpoint aims at the **same world aim point**, not along a shared parallel direction. This produces natural convergence: two spaced-apart weapons both point at the target rather than shooting parallel lines that never meet. It also means that at very close range, widely spaced hardpoints toe in noticeably, which is correct.

```gdscript
func _solve_hardpoint(hp: HardpointState, st: PartInstanceState,
                      def: PartDefinition, aim_point_world: Vector3,
                      assembly_xform: Transform3D) -> void:
    var muzzle_world := _muzzle_world_position(hp, st, def, assembly_xform, 0)
    var to_target := aim_point_world - muzzle_world
    if to_target.length_squared() < 0.01:
        return
    var dir_assembly := assembly_xform.basis.inverse() * to_target.normalized()
    var dir_rest := _to_rest_frame(st, dir_assembly)

    var desired_yaw := atan2(dir_rest.x, dir_rest.z)
    var horiz := sqrt(dir_rest.x * dir_rest.x + dir_rest.z * dir_rest.z)
    var desired_pitch := atan2(dir_rest.y, horiz)

    var p := def.effector_profile
    hp.yaw_target_rad = _apply_yaw_limit(p, desired_yaw, hp.yaw_rad)
    hp.pitch_target_rad = clampf(desired_pitch,
        deg_to_rad(p.pitch_limit_deg.x), deg_to_rad(p.pitch_limit_deg.y))
```

The yaw/pitch decomposition uses `atan2(x, z)` for yaw and `atan2(y, horizontal)` for pitch, which matches the node hierarchy (yaw node rotates about `+Y`, pitch node about `+X` inside it). Using a full look-at basis and extracting Euler angles would be equivalent but is more expensive and introduces a gimbal ambiguity at `pitch = ±90°` that the explicit decomposition simply does not have.

### 4.3 Convergence Test

```gdscript
const AIM_TOLERANCE_RAD := 0.0087    # 0.5 degrees

func _update_on_target(hp: HardpointState) -> void:
    var yaw_err := absf(wrapf(hp.yaw_target_rad - hp.yaw_rad, -PI, PI))
    var pitch_err := absf(hp.pitch_target_rad - hp.pitch_rad)
    hp.on_target = yaw_err <= AIM_TOLERANCE_RAD \
                and pitch_err <= AIM_TOLERANCE_RAD \
                and not _is_blocked(hp, hp.yaw_rad) \
                and hp.jam_timer_s <= 0.0 \
                and hp.reload_timer_s <= 0.0
```

---

## 5. Ballistic Lead and Trajectory Solving

### 5.1 Direct-Fire Intercept

For `BALLISTIC_DIRECT` weapons against a moving target, the aim point must lead the target. With target position `p_t`, target velocity `v_t`, muzzle position `p_m`, shooter velocity `v_s`, and muzzle speed `c`, the intercept time `t` satisfies:

```
‖ (p_t − p_m) + (v_t − v_s)·t ‖ = c·t
```

Expanding gives a quadratic in `t`:

```
a = ‖v_r‖² − c²          where v_r = v_t − v_s
b = 2 · (d · v_r)        where d = p_t − p_m
k = ‖d‖²
t = ( −b − sqrt(b² − 4ak) ) / (2a)      taking the smaller positive root
```

```gdscript
static func intercept_time(d: Vector3, v_rel: Vector3, speed: float) -> float:
    var a := v_rel.length_squared() - speed * speed
    var b := 2.0 * d.dot(v_rel)
    var k := d.length_squared()
    if absf(a) < 1e-5:
        # Target closing at exactly muzzle speed: linear degenerate case.
        return -k / b if absf(b) > 1e-5 else -1.0
    var disc := b * b - 4.0 * a * k
    if disc < 0.0:
        return -1.0                       # unreachable: target outruns the projectile
    var root := sqrt(disc)
    var t1 := (-b - root) / (2.0 * a)
    var t2 := (-b + root) / (2.0 * a)
    var lo := minf(t1, t2)
    var hi := maxf(t1, t2)
    return lo if lo > 0.0 else (hi if hi > 0.0 else -1.0)
```

### 5.2 Gravity and Drag Correction

The closed-form solution above ignores gravity and drag. Rather than solving the full transcendental problem, the aim point is corrected by **fixed-point iteration** — three passes converge to well under one milliradian at all engagement ranges the game supports.

```gdscript
const LEAD_ITERATIONS := 3

static func solve_lead(p_m: Vector3, v_s: Vector3, p_t: Vector3, v_t: Vector3,
                       proj: ProjectileDefinition) -> Vector3:
    var aim := p_t
    for _i in LEAD_ITERATIONS:
        var t := intercept_time(aim - p_m, v_t - v_s, proj.muzzle_velocity_mps)
        if t <= 0.0:
            return p_t                                  # no solution; aim direct
        var drop := 0.5 * proj.gravity_scale * 9.81 * t * t
        var drag_loss := _drag_range_loss(proj, t)
        aim = p_t + v_t * t + Vector3(0.0, drop + drag_loss, 0.0)
    return aim

## Range shortfall from quadratic drag, integrated analytically.
##   v(t) = v0 / (1 + k·v0·t),  s(t) = ln(1 + k·v0·t) / k
## The shortfall against the drag-free s0 = v0·t is compensated by
## additional elevation, which is what this term expresses.
static func _drag_range_loss(proj: ProjectileDefinition, t: float) -> float:
    var k := proj.drag_coefficient_per_m
    if k <= 0.0:
        return 0.0
    var v0 := proj.muzzle_velocity_mps
    var s_drag := log(1.0 + k * v0 * t) / k
    var s_free := v0 * t
    var shortfall := s_free - s_drag
    return shortfall * proj.gravity_scale * 0.5
```

The iteration is stable because each pass moves the aim point in the direction of the residual error, and `t` varies smoothly with aim distance. Divergence would require a target accelerating faster than the projectile, which is outside the game's parameter space.

### 5.3 Arced Trajectory Solve

`BALLISTIC_ARCED` weapons need the launch elevation that lands a projectile on a target at horizontal range `R` and height difference `h`, given muzzle speed `c`:

```
tan θ = ( c² ± sqrt( c⁴ − g(g·R² + 2h·c²) ) ) / (g·R)
```

The `−` root is the low (direct) arc; the `+` root is the high (lobbed) arc. Project Syndicate uses the **high** arc for arced Effector Modules, because clearing intervening cover is the entire point of the weapon class.

```gdscript
static func solve_arc_elevation(range_m: float, height_delta_m: float,
                                speed: float, high_arc: bool) -> float:
    var g := 9.81
    var c2 := speed * speed
    var disc := c2 * c2 - g * (g * range_m * range_m + 2.0 * height_delta_m * c2)
    if disc < 0.0:
        return NAN                        # out of range at this muzzle velocity
    var root := sqrt(disc)
    var num := c2 + root if high_arc else c2 - root
    return atan(num / (g * range_m))
```

`NAN` propagates to `on_target = false` and the UI shows an "out of range" reticle state. The maximum range is surfaced directly:

```
R_max = (c² / g) · sqrt(1 + 2·h·g/c²)      for a target at height difference h
```

Arced weapons additionally iterate lead against a moving target using the flight time `t = R / (c·cos θ)` from the elevation solution, feeding back into the range estimate for two passes.

### 5.4 Guided Ordnance

`GUIDED_ORDNANCE` does not lead at launch. The launcher aims at the target's current position within its limits, and guidance is delegated to the projectile:

```gdscript
class_name GuidedProjectileController
extends RefCounted

const NAV_CONSTANT := 3.6            # proportional navigation gain
const MAX_LATERAL_G := 14.0
const SEEKER_FOV_RAD := 0.61         # ~35 degrees half-angle

func step(p: ProjectileState, target: TargetHandle, dt: float) -> void:
    if not target.valid or not _within_seeker_cone(p, target):
        p.mode = ProjectileState.Mode.BALLISTIC
        return
    var los := target.position - p.position
    var los_rate := (los.normalized() - p.prev_los.normalized()) / dt
    p.prev_los = los
    var closing := -(target.velocity - p.velocity).dot(los.normalized())
    var accel_cmd := los_rate * (NAV_CONSTANT * closing)
    accel_cmd = accel_cmd.limit_length(MAX_LATERAL_G * 9.81)
    p.velocity += accel_cmd * dt
    p.velocity = p.velocity.normalized() * p.speed     # thrust maintains speed
```

Proportional navigation is used rather than pure pursuit because it produces the correct lead-collision course and, critically, is trivially reproducible on the client for visual prediction — it depends only on the projectile's own state and the target's replicated transform.

When the launching Effector Module is destroyed, in-flight guided ordnance transitions to `BALLISTIC` mode (`DEPENDENCY_TREE_GRAPH.md` §7). Missiles do not vanish, and they do not keep tracking from a weapon that no longer exists.

---

## 6. Firing Groups

Effector Modules are bound to firing groups in the garage. Groups are the unit of trigger input.

| Group | Default binding | Typical use |
|---|---|---|
| `GROUP_PRIMARY` | `effector_fire_primary` | Main armament |
| `GROUP_SECONDARY` | `effector_fire_secondary` | Secondary/burst armament |
| `GROUP_TERTIARY` | `effector_fire_tertiary` | Utility, melee, ordnance |

```gdscript
class_name FiringGroupBinding
extends Resource

@export var group_index: int = 0
@export var slots: PackedByteArray = PackedByteArray()
@export var sequence_mode: SequenceMode = SequenceMode.SALVO

enum SequenceMode {
    SALVO = 0,      # all bound effectors fire together when each is ready
    RIPPLE = 1,     # round-robin; one effector per trigger evaluation
    STAGGER = 2,    # evenly phase-offset cycles to smooth recoil and DPS
}
```

`STAGGER` computes a per-slot phase offset once, on binding change:

```gdscript
func _apply_stagger(binding: FiringGroupBinding, hardpoints: Array) -> void:
    var n := binding.slots.size()
    for i in n:
        var hp: HardpointState = hardpoints[binding.slots[i]]
        var def := PartRegistry.definition(_states[binding.slots[i]].part_def_id)
        hp.cycle_timer_s = def.effector_profile.cycle_time_s * float(i) / float(n)
```

Stagger exists because simultaneous discharge of four heavy Effector Modules delivers a recoil impulse spike that can visibly pitch or even destabilise a light Assembly. Staggering spreads the same total impulse across the cycle window, which is both better-feeling and better-behaved numerically.

---

## 7. Emission Loop

The emission loop runs once per physics tick per Assembly, iterating only over that Assembly's hardpoints.

```gdscript
class_name EffectorSystem
extends Node

func _physics_process(dt: float) -> void:
    if not NetAuthority.is_server and not NetAuthority.is_predicting_local:
        _tick_visual_only(dt)
        return
    for i in _hardpoints.size():
        var hp: HardpointState = _hardpoints[i]
        var st: PartInstanceState = _states[hp.slot]
        if st == null or (st.flags & (PartFlags.FLAG_DESTROYED
                                    | PartFlags.FLAG_DETACHED
                                    | PartFlags.FLAG_POWER_STARVED)) != 0:
            continue
        var def := PartRegistry.definition(st.part_def_id)
        var band := st.integrity_band

        _slew(hp, def.effector_profile, band, dt)
        _update_on_target(hp)
        _tick_timers(hp, def.effector_profile, band, dt)
        _decay_spread(hp, def.effector_profile, dt)

        if not _trigger_held(hp.group_index):
            continue
        if not _can_fire(hp, def, band):
            continue
        _emit(hp, st, def, band)
```

### 7.1 Fire Gate

```gdscript
func _can_fire(hp: HardpointState, def: PartDefinition, band: int) -> bool:
    if not hp.on_target:                                    return false
    if hp.cycle_timer_s > 0.0:                              return false
    if hp.burst_recovery_s > 0.0:                           return false
    if hp.jam_timer_s > 0.0:                                return false
    if hp.reload_timer_s > 0.0:                             return false
    var p := def.effector_profile
    if p.magazine_rounds > 0 and hp.rounds_in_magazine <= 0: return false
    if hp.heat_hu >= _heat_ceiling(def):                     return false
    if not AmmoLedger.has_rounds(_assembly_id, p.projectile_key): return false
    return true
```

Ordering is cheapest-first and short-circuiting, so the common "trigger held, weapon cycling" case exits after two integer comparisons.

### 7.2 Emission

```gdscript
func _emit(hp: HardpointState, st: PartInstanceState,
           def: PartDefinition, band: int) -> void:
    var p := def.effector_profile

    # --- Jam roll (CRITICAL band only) ---------------------------------
    if EFF_JAM_CHANCE[band] > 0.0 and _combat_rng.randf() < EFF_JAM_CHANCE[band]:
        hp.jam_timer_s = p.jam_clear_time_s
        st.flags |= PartFlags.FLAG_JAMMED
        EventBus.effector_jammed.emit(_assembly_id, hp.slot)
        return

    # --- Muzzle selection (cycles through multi-barrel offsets) ---------
    var muzzle_idx := hp.next_muzzle_index
    hp.next_muzzle_index = (hp.next_muzzle_index + 1) % p.muzzle_offsets_m.size()
    var muzzle_xform := _muzzle_world_transform(hp, st, def, muzzle_idx)

    # --- Direction with spread -----------------------------------------
    var base_dir := -muzzle_xform.basis.z
    var spread := deg_to_rad(hp.spread_current_deg * EFF_SPREAD_MULT[band])
    var dir := _apply_cone_spread(base_dir, spread)

    # --- Spawn ----------------------------------------------------------
    var proj_def := ProjectileRegistry.definition(p.projectile_key)
    ProjectileSystem.spawn(
        muzzle_xform.origin, dir * p.muzzle_velocity_mps + _chassis_velocity(),
        proj_def, _assembly_id, hp.slot, MatchClock.tick)

    # --- Consequences ---------------------------------------------------
    _apply_recoil(hp, st, def, muzzle_xform, dir)
    hp.heat_hu += p.heat_per_shot_hu
    hp.spread_current_deg = minf(hp.spread_current_deg + p.spread_bloom_deg,
                                 p.spread_base_deg + p.spread_bloom_deg * 12.0)
    hp.cycle_timer_s = p.cycle_time_s * EFF_CYCLE_MULT[band]
    if p.magazine_rounds > 0:
        hp.rounds_in_magazine -= 1
        if hp.rounds_in_magazine <= 0:
            hp.reload_timer_s = p.reload_time_s
    if p.burst_count > 0:
        hp.burst_remaining -= 1
        if hp.burst_remaining <= 0:
            hp.burst_remaining = p.burst_count
            hp.burst_recovery_s = p.burst_recovery_s
    AmmoLedger.consume(_assembly_id, p.projectile_key, 1)
    EventBus.effector_fired.emit(_assembly_id, hp.slot, MatchClock.tick)
```

### 7.3 Muzzle Velocity Inheritance

`dir * muzzle_velocity + _chassis_velocity()` matters. A projectile fired from a vehicle moving at 20 m/s inherits that velocity. Without inheritance, shooting sideways while driving produces visibly curved-looking tracers and a systematic aim bias that players compensate for by leading their own motion — an artefact, not a skill.

### 7.4 Cone Spread

Spread is sampled uniformly over the solid angle of the cone, not uniformly over the angle. Sampling the angle uniformly clusters shots toward the centre and produces a distinctly non-physical grouping pattern.

```gdscript
func _apply_cone_spread(dir: Vector3, half_angle_rad: float) -> Vector3:
    if half_angle_rad <= 0.0:
        return dir
    var cos_max := cos(half_angle_rad)
    var z := _combat_rng.randf_range(cos_max, 1.0)          # uniform in cos(theta)
    var phi := _combat_rng.randf() * TAU
    var s := sqrt(maxf(0.0, 1.0 - z * z))
    var local := Vector3(s * cos(phi), s * sin(phi), z)
    var basis := _basis_from_forward(dir)
    return (basis * local).normalized()
```

`_combat_rng` is a dedicated, seeded `RandomNumberGenerator`. On the server it is seeded from the match seed and advanced deterministically; on the client the same seed and tick produce the identical spread for predicted shots (§11).

### 7.5 Spread Decay

```gdscript
func _decay_spread(hp: HardpointState, p: EffectorModuleProfile, dt: float) -> void:
    hp.spread_current_deg = maxf(p.spread_base_deg,
        hp.spread_current_deg - p.spread_decay_deg_s * dt)
```

---

## 8. Recoil

Recoil is applied to the chassis body as an impulse at the muzzle position, which correctly produces both linear deceleration and a rotational moment.

```gdscript
func _apply_recoil(hp: HardpointState, st: PartInstanceState, def: PartDefinition,
                   muzzle_xform: Transform3D, dir: Vector3) -> void:
    var p := def.effector_profile
    if p.recoil_impulse_ns <= 0.0:
        return
    var impulse := -dir * p.recoil_impulse_ns
    var offset := muzzle_xform.origin - _body.global_position
    _body.apply_impulse(impulse, offset)

    # Feed the strain model: sustained recoil loads the mounting joint.
    var sustained_n := p.recoil_impulse_ns / maxf(p.cycle_time_s, 0.01)
    _graph.deposit_recoil_force(hp.slot, sustained_n)

    # Visual recoil is a local animation only; it never moves a collider.
    hp.recoil_visual_offset = p.recoil_impulse_ns * RECOIL_VISUAL_SCALE
```

`deposit_recoil_force` supplies the `F_recoil(s)` term in `DEPENDENCY_TREE_GRAPH.md` §4.1. It records a **peak**, not a running total: a second discharge inside the decay window is the same sustained load continuing, not a second load added to it. The deposit decays over `RECOIL_DECAY_TAU_S = 0.6` — roughly the cycle time of a slow Effector Module, so a module that keeps firing keeps its joint loaded and one that stops sheds the load over about a second. Without that decay a single shot would load the mounting joint for the rest of the match. A heavy Effector Module bolted to a thin panel will progressively strain its joint and eventually shear off from its own recoil — which is correct engineering behaviour and a genuinely instructive failure for the player.

---

## 9. Heat and Ammunition

### 9.1 Heat

```
heat_ceiling = 100 + Σ_support (heat_dissipation_hu_s · 8.0)
```

Heat accumulates per shot and dissipates continuously:

```gdscript
func _tick_heat(dt: float) -> void:
    var dissipation := _assembly_heat_dissipation_hu_s     # cached; event-updated
    for hp in _hardpoints:
        hp.heat_hu = maxf(0.0, hp.heat_hu - dissipation * dt * _heat_share)
```

`_assembly_heat_dissipation_hu_s` is recomputed on `assembly_structure_changed` only. `_heat_share` is `1.0 / effector_count`, also cached.

Reaching the ceiling forces a cool-down: the weapon cannot fire until heat drops below 60% of the ceiling. This hysteresis prevents the single-shot-per-tick stutter that a bare threshold produces.

### 9.2 Ammunition Ledger

`AmmoLedger` tracks rounds per projectile type per Assembly. Capacity derives from Magazine Store Support Modules:

```
capacity(key) = base_capacity(key) · (1 + Σ magazine_effect_magnitude)
```

Destroying a Magazine Store reduces capacity immediately; current rounds are clamped down to the new capacity. If the module was `volatile_on_destruction`, it additionally detonates with a blast proportional to remaining rounds — which is what makes interior placement (`AUTO_ASSEMBLE_ALGORITHM.md` §6.7) worth the volume cost.

---

## 10. Target Acquisition for AI

AI Assemblies use the same `EffectorSystem`. Only the aim point source differs.

```gdscript
class_name AiTargetSelector
extends RefCounted

const SCAN_INTERVAL_S := 0.35
const MAX_ENGAGEMENT_RANGE_M := 320.0

func select(ctx: AiContext) -> TargetHandle:
    var best: TargetHandle = null
    var best_score := -INF
    for candidate in ctx.visible_assemblies:
        if candidate.team == ctx.team:
            continue
        var d := candidate.position.distance_to(ctx.position)
        if d > MAX_ENGAGEMENT_RANGE_M:
            continue
        var score := 0.0
        score += 240.0 / maxf(d, 8.0)                        # proximity
        score += 1.6 * (1.0 - candidate.integrity_fraction)  # finish wounded targets
        score += 90.0 if candidate.id == ctx.last_attacker_id else 0.0
        score -= 140.0 * float(_arc_cost(ctx, candidate))    # slew time penalty
        if score > best_score:
            best_score = score
            best = candidate
    return best
```

Target selection runs at `SCAN_INTERVAL_S` (2.9 Hz), not per tick, and is staggered across AI Assemblies by seeding the initial timer from the Assembly id. Aim solving itself runs every tick, because it must — but it is only the §4.2 decomposition, which is a handful of `atan2` calls.

AI accuracy is modulated by a difficulty parameter applied as an aim-point offset, never as a hidden damage multiplier:

```gdscript
func _apply_difficulty_error(aim: Vector3, distance: float,
                             difficulty: float) -> Vector3:
    var sigma := lerpf(2.4, 0.15, clampf(difficulty, 0.0, 1.0)) * (distance / 100.0)
    return aim + Vector3(
        _ai_rng.randfn(0.0, sigma), _ai_rng.randfn(0.0, sigma * 0.5),
        _ai_rng.randfn(0.0, sigma))
```

This keeps AI shots physically honest — an AI miss is a real miss, visible as a real tracer going wide, and it can hit a third party.

---

## 11. Network Authority and Prediction

### 11.1 Split of Responsibility

| Quantity | Server | Local client | Remote client |
|---|---|---|---|
| Hardpoint yaw/pitch | Authoritative | Predicted from local input | Interpolated from snapshots |
| Fire gate decision | Authoritative | Predicted | Not evaluated |
| Projectile spawn (damaging) | Authoritative | — | — |
| Projectile spawn (cosmetic tracer) | — | Predicted immediately | On `effector_fired` event |
| Spread roll | Authoritative | Predicted with matching seed | — |
| Jam roll | Authoritative | **Not predicted** | — |
| Recoil impulse | Authoritative | Predicted | Not applied |
| Heat, ammo | Authoritative | Predicted, reconciled | Not tracked |

### 11.2 Deterministic Spread

The client must produce the same spread as the server for a predicted shot, or the predicted tracer will visibly diverge from the authoritative one. The spread RNG is therefore seeded per shot from values both sides know:

```gdscript
func _seed_for_shot(assembly_id: int, slot: int, tick: int, shot_index: int) -> int:
    var h := match_seed
    h = h * 1099511628211 ^ assembly_id
    h = h * 1099511628211 ^ slot
    h = h * 1099511628211 ^ tick
    h = h * 1099511628211 ^ shot_index
    return h
```

This is an FNV-style mix over values that are identical on both sides at the moment of firing.

### 11.3 Jam Is Never Predicted

Jamming is deliberately excluded from prediction. A predicted jam that the server does not confirm would produce a 1.6-second phantom stoppage — the single most frustrating possible misprediction. Instead the client fires optimistically and the server's `effector_jammed` event, arriving one round-trip later, halts subsequent shots. The cost is that a jammed weapon fires one extra client-side tracer that deals no damage; the benefit is that a jam never *invents* a stoppage that did not happen.

### 11.4 Reconciliation

On receiving an authoritative hardpoint snapshot, the client compares predicted and authoritative angles. Divergence beyond `RECONCILE_ANGLE_THRESHOLD = 0.035 rad` (2°) triggers a smoothed correction over `0.12 s` rather than a snap:

```gdscript
func reconcile(hp: HardpointState, auth_yaw: float, auth_pitch: float) -> void:
    var dy := absf(wrapf(auth_yaw - hp.yaw_rad, -PI, PI))
    var dp := absf(auth_pitch - hp.pitch_rad)
    if dy < RECONCILE_ANGLE_THRESHOLD and dp < RECONCILE_ANGLE_THRESHOLD:
        return
    _correction_from = Vector2(hp.yaw_rad, hp.pitch_rad)
    _correction_to = Vector2(auth_yaw, auth_pitch)
    _correction_t = 0.0
```

Full replication detail is in `HEADLESS_NETWORK_SYNC.md` §6.4.

---

## 12. Projectile System

### 12.1 Pooled, Non-Node Projectiles

Projectiles are **not** scene-tree nodes. Spawning 60 `RigidBody3D` nodes per second across 16 players would dominate the frame. Instead projectiles live in a flat, preallocated struct-of-arrays pool and are simulated by a single system.

```gdscript
class_name ProjectileSystem
extends Node

const POOL_SIZE := 2048

var _position: PackedVector3Array = PackedVector3Array()
var _velocity: PackedVector3Array = PackedVector3Array()
var _prev_position: PackedVector3Array = PackedVector3Array()
var _def_id: PackedInt32Array = PackedInt32Array()
var _owner_assembly: PackedInt32Array = PackedInt32Array()
var _owner_slot: PackedByteArray = PackedByteArray()
var _spawn_tick: PackedInt32Array = PackedInt32Array()
var _life_s: PackedFloat32Array = PackedFloat32Array()
var _flags: PackedByteArray = PackedByteArray()
var _free_list: PackedInt32Array = PackedInt32Array()
var _active_count: int = 0
```

Visual representation is a single `MultiMeshInstance3D` for tracers, whose per-instance transforms are written from `_position` and `_velocity` once per rendered frame. One draw call for every projectile in the match.

### 12.2 Integration and Hit Detection

```gdscript
func _physics_process(dt: float) -> void:
    var space := get_world_3d().direct_space_state
    for i in POOL_SIZE:
        if (_flags[i] & PROJ_ACTIVE) == 0:
            continue
        var def := ProjectileRegistry.definition(_def_id[i])
        _prev_position[i] = _position[i]

        # Quadratic drag, semi-implicit.
        var v := _velocity[i]
        var speed := v.length()
        if def.drag_coefficient_per_m > 0.0 and speed > 0.01:
            v -= v.normalized() * (def.drag_coefficient_per_m * speed * speed * dt)
        v.y -= 9.81 * def.gravity_scale * dt
        _velocity[i] = v
        _position[i] += v * dt

        _life_s[i] -= dt
        if _life_s[i] <= 0.0:
            _expire(i, def)
            continue
        _sweep_and_resolve(i, def, space)
```

Hit detection is a **swept ray** from `_prev_position` to `_position`, never a point test. At 940 m/s a projectile travels 15.7 m per tick; a point test would tunnel through every Assembly in the game.

```gdscript
func _sweep_and_resolve(i: int, def: ProjectileDefinition,
                        space: PhysicsDirectSpaceState3D) -> void:
    var params := PhysicsRayQueryParameters3D.create(_prev_position[i], _position[i])
    params.collision_mask = CollisionLayers.MASK_PROJECTILE_TARGET
    params.exclude = _self_exclusion(i)
    params.hit_from_inside = false
    var hit := space.intersect_ray(params)
    if hit.is_empty():
        return
    DamageResolver.submit_impact(ImpactRecord.new(
        hit.position, hit.normal, _velocity[i], def, _owner_assembly[i],
        _owner_slot[i], hit.collider, hit.shape))
    if def.penetrates_after_hit and _penetration_budget(i, def, hit) > 0.0:
        _position[i] = hit.position + _velocity[i].normalized() * 0.02
        return                                     # continue through the target
    _expire(i, def)
```

### 12.3 Self-Exclusion

A projectile must not hit its own Assembly during the first few centimetres of flight, but must be able to hit it later (a mortar shell landing on your own roof is legitimate).

```gdscript
const SELF_IMMUNITY_S := 0.06

func _self_exclusion(i: int) -> Array[RID]:
    var age := (MatchClock.tick - _spawn_tick[i]) * SyndicateConstants.PHYSICS_DT
    return _owner_rid[i] if age < SELF_IMMUNITY_S else []
```

### 12.4 Pool Exhaustion

When the pool is full, the **oldest** projectile is recycled rather than the newest being dropped. Dropping the newest would mean a player's shot silently never existed, which is unacceptable; recycling the oldest costs at most one distant tracer disappearing early. At 2048 slots and typical fire rates, exhaustion has not been observed outside stress tests with 32 simultaneous continuous-fire Assemblies.

---

## 13. Performance Budget

Reference target, 16-player match, 12 firing Assemblies, ~340 live projectiles:

| Stage | Budget | Measured |
|---|---|---|
| Hardpoint slew + aim solve (all Assemblies) | 0.30 ms | 0.12 ms |
| Fire gate evaluation | 0.10 ms | 0.03 ms |
| Emission (spawn + recoil + bookkeeping) | 0.25 ms | 0.09 ms |
| Projectile integration | 0.60 ms | 0.34 ms |
| Projectile sweep queries | 1.80 ms | 1.08 ms |
| MultiMesh transform write | 0.35 ms | 0.21 ms |
| AI target selection (amortised, 2.9 Hz staggered) | 0.15 ms | 0.06 ms |
| **Total** | **3.55 ms** | **1.93 ms** |

---

## 14. Invariants

1. Hardpoint nodes are visual and kinematic only. No `CollisionShape3D` exists under `HardpointYaw`, and rotating a turret never moves a collider.
2. All damaging projectiles originate on the server. Clients spawn cosmetic tracers only.
3. Rotation limits are evaluated in the part's authored rest frame, transformed by its lattice orientation.
4. Blocked firing sectors are recomputed only on `assembly_structure_changed`.
5. Degradation multipliers are indexed by the cached `integrity_band`. The targeting loop performs no health arithmetic.
6. Jamming occurs only in the `CRITICAL` band and is never client-predicted.
7. Projectiles are pooled struct-of-arrays data, never scene-tree nodes, and are rendered by a single `MultiMeshInstance3D`.
8. Hit detection is always a swept query between the previous and current positions.
9. Projectiles inherit the firing chassis's velocity.
10. Spread is sampled uniformly over solid angle, with a per-shot seed reproducible on client and server.
11. Recoil is applied as an impulse at the muzzle offset and is deposited into the strain model.
