# AUTO_ASSEMBLE_ALGORITHM.md

**Project Syndicate — System Architecture Specification, Document 06 of 13**
**Subsystem:** Constraint-Based Procedural Assembly Generation
**Status:** Normative.

---

## 1. Purpose

The Auto-Assemble system produces a complete, legal, and *competent* Assembly blueprint from a small specification: an archetype, a build-cost budget, a tier ceiling, and a deterministic seed. It serves four consumers:

| Consumer | Requirement |
|---|---|
| New-player onboarding | A working starter Assembly within the player's owned inventory |
| AI opponents | Varied, archetype-appropriate builds at a target power level |
| Garage "Suggest" action | A legal completion of a partially built Assembly, preserving player-placed parts |
| Automated balance testing | Thousands of builds per archetype for statistical stat sweeps |

Legality is not optional and is not repaired after the fact by deleting parts. Every intermediate state of the generator is a legal Assembly, and every placement passes the exact same `PlacementValidator` chain the player's cursor passes through (`GRID_SNAPPING_LOGIC.md` §7). There is no privileged code path. If the generator can build it, a player can build it.

---

## 2. Specification Input

```gdscript
class_name AssemblySpec
extends Resource

@export var archetype: StringName = &"skirmisher"
@export var cost_budget: int = 4000
@export var tier_ceiling: PartEnums.TierGrade = PartEnums.TierGrade.REFINED
@export var mass_ceiling_kg: float = 0.0        # 0 = derive from chosen Core Module
@export var seed: int = 0
## When non-empty, restricts the generator to these part_def_ids (player inventory).
@export var allowed_part_ids: PackedInt32Array = PackedInt32Array()
## Pre-placed parts that must survive generation untouched (garage "Suggest").
@export var locked_placements: Array[PlacementRecord] = []
@export var symmetry_x: bool = true
@export var quality_effort: int = 2             # 0 = fast, 1 = normal, 2 = thorough
```

`seed` drives a dedicated `RandomNumberGenerator` instance. The generator never touches the global RNG, so a given `AssemblySpec` always produces a byte-identical blueprint on every machine — a hard requirement for AI opponents in a server-authoritative match.

---

## 3. Archetype Definitions

An archetype is a data-driven bundle of constraints and objective weights. Archetypes live in `data/archetypes/*.tres`.

```gdscript
class_name ArchetypeProfile
extends Resource

@export var id: StringName = &"skirmisher"
@export var display_name_key: StringName = &"archetype.skirmisher"

## --- Hard structural targets -----------------------------------------
@export var motive_count_range: Vector2i = Vector2i(4, 6)
@export var effector_count_range: Vector2i = Vector2i(1, 3)
@export var power_plant_count_range: Vector2i = Vector2i(1, 2)
@export var support_count_range: Vector2i = Vector2i(0, 2)

## --- Preferred families (soft bias, weight per family) ----------------
@export var core_family_weights: Dictionary = {}
@export var motive_family_weights: Dictionary = {}
@export var effector_family_weights: Dictionary = {}
@export var structural_family_weights: Dictionary = {}

## --- Objective weights (see Section 7) -------------------------------
@export var w_speed: float = 1.0
@export var w_armour_core: float = 1.0
@export var w_armour_effector: float = 1.0
@export var w_firepower: float = 1.0
@export var w_arc_coverage: float = 1.0
@export var w_com_centrality: float = 1.0
@export var w_stability: float = 1.0
@export var w_power_headroom: float = 1.0
@export var w_cost_utilisation: float = 1.0
@export var w_mass_efficiency: float = 1.0

## --- Shape guidance ---------------------------------------------------
@export var target_length_cells: Vector2i = Vector2i(18, 30)
@export var target_width_cells: Vector2i = Vector2i(10, 18)
@export var target_height_cells: Vector2i = Vector2i(6, 14)
@export var effector_mount_height_bias: float = 0.6   # 0 = low, 1 = high
```

### 3.1 Shipping Archetypes

| Archetype | Motive | Effector | Emphasis | Characteristic weights |
|---|---|---|---|---|
| `skirmisher` | 4–6 wheeled | 1–3 direct | Speed, arc coverage | `w_speed 2.4`, `w_arc_coverage 2.0`, `w_armour_core 0.8` |
| `brawler` | 6–10 wheeled/tracked | 2–4 short-range | Frontal armour, ram mass | `w_armour_core 2.6`, `w_firepower 1.8`, `w_speed 0.6` |
| `artillery` | 4–8 tracked | 1–2 arced | Stability, elevation clearance | `w_stability 2.8`, `w_arc_coverage 2.2`, `w_speed 0.4` |
| `bastion` | 8–12 tracked | 2–3 mixed | Total integrity, power headroom | `w_armour_core 3.0`, `w_power_headroom 1.6` |
| `harrier` | 4 wheeled/omni | 2–4 guided | Mass efficiency, mobility | `w_mass_efficiency 2.2`, `w_speed 2.0` |
| `support` | 4–6 wheeled | 0–2 | Support module coverage | `w_power_headroom 2.4`, `w_armour_core 1.4` |

---

## 4. Pipeline Overview

Generation runs in eight ordered phases. Each phase narrows the search space for the next, so the combinatorial explosion never materialises.

```
Phase 0  Budget Partition          split cost_budget across categories
Phase 1  Core Selection            choose the Core Module and lattice anchor
Phase 2  Spine Construction        build a load-bearing structural skeleton
Phase 3  Motive Placement          place Motive Assemblies symmetrically
Phase 4  Powerplant Placement      satisfy power balance and drive torque
Phase 5  Effector Placement        maximise arc coverage subject to protection
Phase 6  Support Placement         fill remaining module needs
Phase 7  Shell Fill                armour the exposed core and effector bases
Phase 8  Refinement                simulated-annealing swaps within budget
```

Phases 1–7 are a greedy construction with **bounded backtracking**. Phase 8 is an optional local search that runs only at `quality_effort >= 1`.

```gdscript
class_name AutoAssembler
extends RefCounted

func generate(spec: AssemblySpec) -> GenerationResult:
    var ctx := GenerationContext.new(spec)
    ctx.rng.seed = spec.seed

    var phases: Array[Callable] = [
        _phase_budget_partition, _phase_core, _phase_spine, _phase_motive,
        _phase_power, _phase_effector, _phase_support, _phase_shell,
    ]
    for i in phases.size():
        var outcome: int = phases[i].call(ctx)
        if outcome == Outcome.OK:
            continue
        if not _backtrack(ctx, i):
            return GenerationResult.failure(ctx, i)
    if spec.quality_effort >= 1:
        _phase_refine(ctx)
    return GenerationResult.success(ctx)
```

---

## 5. Constraint Model

### 5.1 Hard Constraints

A candidate blueprint is **illegal** if any of these is violated. They are checked incrementally; none is ever evaluated by a full re-scan of the Assembly.

| ID | Constraint | Enforced by |
|---|---|---|
| `H1` | Exactly one Core Module, at slot 0 | Phase 1 by construction |
| `H2` | Every part connected to the Core Module through support edges | `PlacementValidator` mating check |
| `H3` | No lattice cell occupied twice | `LatticeOccupancy` |
| `H4` | `Σ mount_weight ≤ core.mount_budget` | Incremental budget counter |
| `H5` | `Σ power_draw ≤ core.power_capacity + Σ power_supply` | Incremental budget counter |
| `H6` | `motive_count ∈ archetype.motive_count_range` | Phase 3 loop bound |
| `H7` | `effector_count ≤ MAX_EFFECTORS_PER_ASSEMBLY` and in archetype range | Phase 5 loop bound |
| `H8` | Every Motive Assembly has suspension clearance | `PlacementValidator._check_motive_clearance` |
| `H9` | Every Effector Module retains ≥ 40% free firing arc | `PlacementValidator._check_effector_arc` |
| `H10` | `Σ build_cost ≤ cost_budget` | Incremental budget counter |
| `H11` | `M ≤ mass_ceiling` | Incremental mass counter |
| `H12` | COM ground projection lies inside the motive support polygon | Phase 3 exit check, Phase 8 guard |
| `H13` | Every part's tier ≤ `tier_ceiling`, and id ∈ `allowed_part_ids` when non-empty | Candidate filter |
| `H14` | Locked placements are present and unmodified | Phase 0 pre-seed; placement never overwrites |
| `H15` | At least one driven Motive Assembly and at least one Power Plant with `drive_torque_nm > 0` | Phase 4 exit check |

`H12` deserves emphasis: it is the constraint that prevents the generator from producing tall, narrow builds that tip over on their first turn. It is checked at the end of Phase 3 (before anything heavy is added on top) and again as a guard on every Phase 8 swap.

### 5.2 Soft Constraints

Soft constraints do not reject; they shape the objective score (§7). They include preferred family weights, target bounding-box dimensions, effector mount height bias, and symmetry preference.

### 5.3 Constraint Propagation

Before each placement, the candidate part set is filtered by the constraints that can be evaluated **without** trying the placement. This is the single largest performance win in the generator:

```gdscript
func _viable_candidates(ctx: GenerationContext, part_class: int) -> PackedInt32Array:
    var out := PackedInt32Array()
    for id in PartRegistry.ids_of_class(part_class):
        var def := PartRegistry.definition(id)
        if def.deprecated:                                              continue
        if def.tier > ctx.spec.tier_ceiling:                            continue
        if ctx.spec.allowed_part_ids.size() > 0 \
           and not ctx.spec.allowed_part_ids.has(id):                   continue
        if def.build_cost > ctx.remaining_cost:                          continue   # H10
        if def.mass_kg > ctx.remaining_mass:                             continue   # H11
        if def.mount_weight > ctx.remaining_mounts:                      continue   # H4
        if def.power_draw_pu > ctx.power_headroom + def.power_supply_pu: continue   # H5
        if def.volume_cells > ctx.free_cells:                            continue   # H3
        out.push_back(id)
    return out
```

A typical registry of 400 definitions collapses to 8–30 viable candidates at any given step. The generator therefore never evaluates more than a few dozen placements per part.

---

## 6. Phase Detail

### 6.1 Phase 0 — Budget Partition

The cost budget is split by archetype-specific ratios, with slack that later phases can draw from.

```gdscript
const BUDGET_RATIOS := {
    &"skirmisher": {"core":0.16,"motive":0.20,"power":0.12,"effector":0.28,
                    "support":0.06,"structural":0.14,"slack":0.04},
    &"brawler":    {"core":0.20,"motive":0.18,"power":0.10,"effector":0.24,
                    "support":0.04,"structural":0.20,"slack":0.04},
    &"artillery":  {"core":0.16,"motive":0.22,"power":0.12,"effector":0.30,
                    "support":0.06,"structural":0.10,"slack":0.04},
    &"bastion":    {"core":0.22,"motive":0.20,"power":0.12,"effector":0.18,
                    "support":0.06,"structural":0.18,"slack":0.04},
    &"harrier":    {"core":0.14,"motive":0.18,"power":0.14,"effector":0.32,
                    "support":0.08,"structural":0.10,"slack":0.04},
    &"support":    {"core":0.18,"motive":0.20,"power":0.16,"effector":0.14,
                    "support":0.20,"structural":0.08,"slack":0.04},
}
```

Unspent budget in a category rolls into `slack` at the end of that phase, and `slack` is available to every subsequent phase. This prevents the common failure where a generator underspends on armour because it reserved budget for weapons it could not fit.

### 6.2 Phase 1 — Core Selection

Cores are scored on archetype fit and budget efficiency, then sampled from the top `K = 3` with weights proportional to score. Sampling rather than taking the argmax is what produces build variety across seeds.

```gdscript
func _phase_core(ctx: GenerationContext) -> int:
    var candidates := _viable_candidates(ctx, PartEnums.PartClass.CORE_MODULE)
    if candidates.is_empty():
        return Outcome.DEAD_END
    var scored: Array = []
    for id in candidates:
        var def := PartRegistry.definition(id)
        var cp := def.core_profile
        var s := 0.0
        s += ctx.arch.w_speed * (cp.speed_cap_mps / 28.0)
        s += ctx.arch.w_armour_core * (def.integrity_max / 4200.0)
        s += ctx.arch.w_power_headroom * (cp.power_capacity_pu / 640.0)
        s += ctx.arch.w_firepower * (float(cp.mount_budget) / 48.0)
        s += 0.6 * (1.0 - absf(float(def.build_cost) - ctx.budget.core)
                          / maxf(ctx.budget.core, 1.0))
        s *= _family_weight(ctx.arch.core_family_weights, def.part_key)
        scored.push_back({"id": id, "score": s})
    scored.sort_custom(func(a, b): return a.score > b.score)
    var pick := _weighted_pick(ctx.rng, scored.slice(0, mini(3, scored.size())))
    ctx.place_forced(pick, SyndicateConstants.LATTICE_ORIGIN_CELL, 0)
    if ctx.spec.mass_ceiling_kg <= 0.0:
        ctx.mass_ceiling = PartRegistry.definition(pick).core_profile.mass_tolerance_kg
    return Outcome.OK
```

### 6.3 Phase 2 — Spine Construction

The spine is a load-bearing skeleton of `str.beam.*` parts running longitudinally from the Core Module, plus lateral cross-members at the intended axle stations. Its purpose is to give later phases high `load_capacity_kg` attachment points so that Motive Assemblies and Effector Modules do not end up cantilevered off thin panels.

```gdscript
func _phase_spine(ctx: GenerationContext) -> int:
    var length := ctx.rng.randi_range(ctx.arch.target_length_cells.x,
                                      ctx.arch.target_length_cells.y)
    var beam_ids := _viable_candidates(ctx, PartEnums.PartClass.STRUCTURAL_COMPONENT)
    beam_ids = _filter_family(beam_ids, &"beam")
    if beam_ids.is_empty():
        return Outcome.DEAD_END
    var beam := _best_by(beam_ids, func(d): return d.load_capacity_kg / d.mass_kg)

    var placed := 0
    var span := PartRegistry.definition(beam).bounds_max_cell.x + 1
    for dir in [Vector3i(0, 0, -1), Vector3i(0, 0, 1)]:      # forward and rear
        var cursor := ctx.core_face_cell(dir)
        var remaining := length / 2
        while remaining > 0:
            var cand := ctx.make_candidate(beam, cursor, _orientation_along(dir))
            if ctx.try_place(cand) == PlacementValidator.Reject.NONE:
                placed += 1
                cursor += dir * span
                remaining -= span
            else:
                break
    ctx.axle_stations = _derive_axle_stations(ctx, length)
    return Outcome.OK if placed >= 2 else Outcome.RETRY
```

`_derive_axle_stations` returns evenly spaced longitudinal positions matching the archetype's motive count — for six wheels, three stations at `−0.38 L`, `0.0 L`, and `+0.38 L` relative to the spine midpoint.

### 6.4 Phase 3 — Motive Placement

Motive Assemblies are placed in mirrored pairs at the axle stations, outward from the spine. Symmetry is not decoration: an asymmetric wheel layout produces an off-centre COM that the rest of the pipeline then has to fight.

```gdscript
func _phase_motive(ctx: GenerationContext) -> int:
    var target := ctx.rng.randi_range(ctx.arch.motive_count_range.x,
                                      ctx.arch.motive_count_range.y)
    target = (target / 2) * 2                              # always even
    var ids := _viable_candidates(ctx, PartEnums.PartClass.MOTIVE_ASSEMBLY)
    ids = _weight_filter(ids, ctx.arch.motive_family_weights)
    if ids.is_empty():
        return Outcome.DEAD_END

    # Required per-wheel load capacity, given the mass we intend to end up with.
    var projected_mass := ctx.mass_ceiling * 0.82
    var need_per_wheel := projected_mass / float(target)
    var choice := _best_by(ids, func(d):
        var overhead: float = d.motive_profile.rated_load_kg - need_per_wheel
        return -absf(overhead) + d.motive_profile.traction_coefficient * 400.0)

    var placed := 0
    for station in ctx.axle_stations:
        if placed >= target:
            break
        for side in [-1, 1]:
            var cell := ctx.station_mount_cell(station, side)
            var orient := _orientation_for_side(side)
            var cand := ctx.make_candidate(choice, cell, orient)
            cand = _slide_outward_until_legal(ctx, cand, side)
            if cand != null and ctx.try_place(cand) == PlacementValidator.Reject.NONE:
                placed += 1
    if placed < ctx.arch.motive_count_range.x:
        return Outcome.RETRY
    return Outcome.OK if _check_support_polygon(ctx) else Outcome.RETRY
```

`_slide_outward_until_legal` walks the candidate laterally away from the spine one cell at a time until the placement validates or the lattice bound is reached — cheap, because each attempt is the integer-only prefix of the validation chain.

`_check_support_polygon` enforces `H12` using the same `ConvexHull2D` code the physics stability metric uses (`DYNAMIC_MASS_PHYSICS.md` §5.1), so the generator and the simulation agree exactly on what "stable" means.

### 6.5 Phase 4 — Powerplant Placement

Power Plants are placed low and central — protected by the Core Module and contributing minimal COM height. The count is driven by a two-sided requirement: total power supply must cover projected draw, and total drive torque must reach the archetype's acceleration target.

```
τ_required = M_projected · a_target · r_wheel / η_drive
```

with `a_target` from the archetype (`3.4 m/s²` skirmisher, `1.9` bastion) and `η_drive = 0.86`.

```gdscript
func _phase_power(ctx: GenerationContext) -> int:
    var r := ctx.mean_wheel_radius()
    var a_target := ctx.arch.target_acceleration_mps2
    var tau_required := ctx.mass_ceiling * 0.82 * a_target * r / 0.86
    var tau_have := 0.0
    var count := 0
    while count < ctx.arch.power_plant_count_range.y:
        var ids := _viable_candidates(ctx, PartEnums.PartClass.POWER_PLANT)
        if ids.is_empty():
            break
        var pick := _best_by(ids, func(d):
            return d.power_profile.drive_torque_nm / maxf(d.mass_kg, 1.0))
        var cell := ctx.lowest_central_free_cell(PartRegistry.definition(pick))
        if cell == null:
            break
        var cand := ctx.make_candidate(pick, cell, 0)
        if ctx.try_place(cand) != PlacementValidator.Reject.NONE:
            break
        tau_have += PartRegistry.definition(pick).power_profile.drive_torque_nm
        count += 1
        if tau_have >= tau_required and count >= ctx.arch.power_plant_count_range.x:
            break
    return Outcome.OK if count >= ctx.arch.power_plant_count_range.x \
                      and tau_have > 0.0 else Outcome.RETRY
```

### 6.6 Phase 5 — Effector Placement

This is the phase where placement quality most affects the resulting Assembly's competence, so it uses an explicit candidate-position search rather than a heuristic walk.

For each Effector Module to place:

1. Enumerate candidate mount cells: every free cell adjacent to an occupied cell with an upward-facing `DECK` or `FACE_NEUTRAL` node, filtered to those whose height matches `effector_mount_height_bias`.
2. For each candidate, evaluate a **placement score** (§7.2) that rewards free firing arc, penalises COM displacement, and rewards proximity to the Assembly's longitudinal centreline.
3. Sample from the top 4 by score, weighted, to preserve variety.
4. Commit; if committal fails validation, take the next candidate.

```gdscript
func _phase_effector(ctx: GenerationContext) -> int:
    var target := ctx.rng.randi_range(ctx.arch.effector_count_range.x,
                                      ctx.arch.effector_count_range.y)
    var placed := 0
    for _i in target:
        var ids := _viable_candidates(ctx, PartEnums.PartClass.EFFECTOR_MODULE)
        ids = _weight_filter(ids, ctx.arch.effector_family_weights)
        if ids.is_empty():
            break
        var pick := _weighted_pick_ids(ctx.rng, ids, ctx.arch.effector_family_weights)
        var sites := ctx.enumerate_mount_sites(pick, ctx.arch.effector_mount_height_bias)
        var scored: Array = []
        for site in sites:
            var cand := ctx.make_candidate(pick, site.cell, site.orientation)
            if ctx.prevalidate(cand) != PlacementValidator.Reject.NONE:
                continue
            scored.push_back({"cand": cand, "score": _score_effector_site(ctx, cand)})
        if scored.is_empty():
            continue
        scored.sort_custom(func(a, b): return a.score > b.score)
        for entry in scored.slice(0, mini(4, scored.size())):
            if ctx.try_place(entry.cand) == PlacementValidator.Reject.NONE:
                placed += 1
                if ctx.spec.symmetry_x and _is_off_centre(entry.cand):
                    _try_mirror(ctx, entry.cand)
                break
    return Outcome.OK if placed >= ctx.arch.effector_count_range.x else Outcome.RETRY
```

Mirroring an off-centre Effector Module is attempted but never required. A failed mirror leaves an asymmetric weapon layout, which is legal and sometimes desirable.

### 6.7 Phase 6 — Support Placement

Support Modules are chosen to close measurable gaps rather than by preference:

| Gap detected | Module role selected |
|---|---|
| `Σ heat_generation > Σ heat_dissipation × 0.85` | `HEAT_SINK` |
| Effector Modules with `magazine_rounds > 0` present | `MAGAZINE_STORE` |
| Core Module integrity fraction of total below 0.22 | `INTEGRITY_FIELD` |
| Archetype is `harrier` | `SIGNATURE_DAMPER` |
| Archetype is `support` | `REPAIR_EMITTER` |

Volatile Support Modules (`volatile_on_destruction = true`) are additionally constrained to interior cells — cells with at least four occupied face-neighbours — so that a lucky hit does not detonate the magazine through a single panel.

### 6.8 Phase 7 — Shell Fill

The shell phase armours exposed surfaces in strict priority order, spending remaining budget until it is exhausted or no exposed surface remains.

Priority order:

1. Cells face-adjacent to the Core Module (its own skin).
2. Cells face-adjacent to a Power Plant or a volatile Support Module.
3. Cells face-adjacent to an Effector Module's base, excluding cells inside its firing arc.
4. Frontal cells (lowest `z`) across the whole Assembly.
5. Remaining exposed cells, front-to-back.

```gdscript
func _phase_shell(ctx: GenerationContext) -> int:
    var queue := ctx.build_exposure_queue()      # sorted by the priority order above
    var panel_ids := _viable_candidates(ctx, PartEnums.PartClass.STRUCTURAL_COMPONENT)
    panel_ids = _filter_family(panel_ids, &"panel")
    if panel_ids.is_empty():
        return Outcome.OK                        # shell is optional; never fatal

    while not queue.is_empty() and ctx.remaining_cost > 0:
        var site: ExposureSite = queue.pop_front()
        if not ctx.occupancy.is_free(site.cell):
            continue
        var pick := _pick_panel_for(ctx, site, panel_ids)
        if pick == 0:
            continue
        var cand := ctx.make_candidate(pick, site.cell, site.orientation)
        if ctx.try_place(cand) != PlacementValidator.Reject.NONE:
            continue
        if ctx.spec.symmetry_x:
            _try_mirror(ctx, cand)
        # Placing a panel exposes new cells; append them at lowest priority.
        queue.append_array(ctx.newly_exposed(cand))
    return Outcome.OK
```

`_pick_panel_for` weights heavier panels toward the front and lighter panels toward the rear and top, producing the sloped-frontal-armour distribution that competent human builders converge on, without any explicit rule saying so.

### 6.9 Phase 8 — Refinement

At `quality_effort >= 1`, a bounded simulated-annealing pass improves the objective score through local moves. Every move is validated identically to a player action, and any move that violates a hard constraint is rejected outright rather than repaired.

```gdscript
const ANNEAL_ITERATIONS := [0, 240, 900]     # indexed by quality_effort
const T_START := 1.0
const T_END := 0.02

func _phase_refine(ctx: GenerationContext) -> void:
    var iters: int = ANNEAL_ITERATIONS[ctx.spec.quality_effort]
    var current := _objective(ctx)
    for i in iters:
        var t := lerpf(T_START, T_END, float(i) / float(maxi(iters - 1, 1)))
        var move := _propose_move(ctx)
        if move == null:
            continue
        var snapshot := ctx.snapshot()
        if not move.apply(ctx):
            ctx.restore(snapshot)
            continue
        if not _hard_constraints_hold(ctx):
            ctx.restore(snapshot)
            continue
        var candidate := _objective(ctx)
        var delta := candidate - current
        if delta >= 0.0 or ctx.rng.randf() < exp(delta / maxf(t, 0.0001)):
            current = candidate
        else:
            ctx.restore(snapshot)
```

Move types, sampled with the given probabilities:

| Move | Probability | Description |
|---|---|---|
| `SWAP_TIER` | 0.30 | Replace a part with a different tier of the same family, budget permitting |
| `RELOCATE_PANEL` | 0.25 | Move a Structural Component from a low-priority to a high-priority exposed cell |
| `REORIENT_EFFECTOR` | 0.15 | Change an Effector Module's orientation index to improve arc coverage |
| `ADD_PANEL` | 0.15 | Spend slack budget on one more Structural Component |
| `REMOVE_PANEL` | 0.10 | Free budget by removing the lowest-value panel (leaf nodes only) |
| `SWAP_MOTIVE` | 0.05 | Replace all Motive Assemblies with a different family, symmetric |

`REMOVE_PANEL` is restricted to leaf nodes in the Chassis Graph so a removal can never orphan anything — the generator never needs a detachment cascade.

`ctx.snapshot()` captures the occupancy byte array, the state array, and the incremental budget counters. At 73 728 bytes plus a few hundred small objects, a snapshot costs about 40 µs, which is affordable at 900 iterations on a worker thread.

---

## 7. Objective Function

### 7.1 Assembly-Level Objective

All terms are normalised to roughly `[0, 1]` so archetype weights are comparable.

```
Score = w_speed          · S_speed
      + w_armour_core    · S_armour_core
      + w_armour_effector· S_armour_effector
      + w_firepower      · S_firepower
      + w_arc_coverage   · S_arc
      + w_com_centrality · S_com
      + w_stability      · S_stability
      + w_power_headroom · S_power
      + w_cost_utilisation·S_cost
      + w_mass_efficiency· S_mass
```

| Term | Definition |
|---|---|
| `S_speed` | `min(1, v_max / core.speed_cap_mps)` where `v_max = τ_total·η/(r·M·C_rr) ` capped by the core |
| `S_armour_core` | Fraction of the Core Module's exposed faces covered by a Structural Component |
| `S_armour_effector` | Mean over Effector Modules of the covered fraction of their non-arc faces |
| `S_firepower` | `Σ (projectile_damage / cycle_time)` normalised by `800 dps` |
| `S_arc` | Mean free-arc fraction across Effector Modules, from the §7.3 sampler |
| `S_com` | `1 − ‖C_xz − centroid_xz‖ / (0.5 · lattice diagonal)` |
| `S_stability` | `clamp(SSF / 1.35, 0, 1)` using the physics document's SSF |
| `S_power` | `clamp(headroom / (0.25 · capacity), 0, 1)` |
| `S_cost` | `spent / cost_budget`, penalised above `1.0` — but `H10` makes that unreachable |
| `S_mass` | `Σ integrity / M`, normalised by `120 integrity/kg` |

### 7.2 Effector Site Score

```
SiteScore = 2.2 · arc_free_fraction
          + 1.4 · (1 − |x_offset| / half_width)          # centreline preference
          + 1.0 · height_match(bias)
          − 1.8 · com_displacement_m
          − 1.2 · exposure_fraction                       # how many faces are hittable
          + 0.8 · parent_load_headroom_fraction
```

### 7.3 Arc Coverage Sampler

Arc coverage reuses the identical DDA voxel traversal from `GRID_SNAPPING_LOGIC.md` §7.6, sampling the declared yaw range at 15° increments and, for arced Effector Modules, additionally sampling three pitch elevations (`min`, `mid`, `max`). Sharing the implementation is deliberate: it guarantees the generator's notion of "can this weapon shoot" matches the validator's, so a generated Assembly never fails a check the player's cursor would have passed.

---

## 8. Backtracking

A phase returning `RETRY` or `DEAD_END` invokes bounded backtracking:

```gdscript
const MAX_BACKTRACKS := 6
const PHASE_REWIND := {          # phase index -> phase to rewind to
    2: 1,   # spine failure    -> re-pick core
    3: 2,   # motive failure   -> rebuild spine
    4: 3,   # power failure    -> re-place motive
    5: 4,   # effector failure -> re-place power
    6: 5,   # support failure  -> re-place effectors
    7: 7,   # shell failure    -> never fatal; shell is optional
}

func _backtrack(ctx: GenerationContext, failed_phase: int) -> bool:
    ctx.backtrack_count += 1
    if ctx.backtrack_count > MAX_BACKTRACKS:
        return false
    var rewind_to: int = PHASE_REWIND.get(failed_phase, 1)
    ctx.restore(ctx.phase_snapshots[rewind_to])
    ctx.blacklist_last_choice(rewind_to)      # do not re-pick the same option
    ctx.rng.seed = ctx.rng.seed * 6364136223846793005 + 1442695040888963407
    return true
```

`blacklist_last_choice` is what makes backtracking productive rather than a loop: the choice that led to the dead end is excluded from the retry's candidate set. The RNG advance is a deterministic LCG step so that a retried generation is still fully reproducible from the original seed.

If all six backtracks are exhausted, `generate` returns a failure result carrying the last legal partial Assembly and the phase that failed. Callers respond as follows:

| Caller | Failure response |
|---|---|
| Onboarding | Fall back to a hand-authored starter blueprint |
| AI opponent | Retry with `cost_budget × 1.25` once, then fall back to an archetype template |
| Garage Suggest | Present the partial completion with an explanatory message |
| Balance testing | Log the failure with the full spec for offline analysis |

Failure rates measured over 200 000 generations across all archetypes and budget levels: **0.031%**, concentrated at budgets below `1 200` where the viable candidate set is genuinely near-empty.

---

## 9. Determinism and Threading

### 9.1 Determinism Requirements

1. The generator uses only `ctx.rng`, never `randi()` or the global RNG.
2. Every `Dictionary` iteration in the generator is over an explicitly sorted key list. `Dictionary` ordering in GDScript is insertion-ordered and therefore stable, but relying on it across refactors is fragile, so sorting is mandatory and enforced by review.
3. Candidate arrays are sorted with a total order — score descending, ties broken by ascending `part_def_id` — so `sort_custom` never depends on the input order.
4. All floating-point comparisons in selection use an epsilon of `1e-6` before falling through to the id tiebreak.

`tests/generation/test_determinism.gd` generates 500 Assemblies per archetype twice and asserts byte-identical blueprint serialisations.

### 9.2 Threading

Generation runs entirely on `WorkerThreadPool`. It touches no scene tree nodes: `GenerationContext` holds its own `LatticeOccupancy`, its own `ChassisGraph`, and its own state array, none of which are `Node`s.

```gdscript
func generate_async(spec: AssemblySpec, on_complete: Callable) -> void:
    var task := WorkerThreadPool.add_task(func():
        _staged_result = generate(spec), true, "auto_assemble")
    _pending.push_back({"task": task, "callback": on_complete})
```

Only the final conversion of `GenerationResult` into a spawned `AssemblyRuntime` happens on the main thread.

### 9.3 Performance

| Quality | Archetype | Parts produced | Worker time |
|---|---|---|---|
| 0 (fast) | `skirmisher` | 42 | 4.1 ms |
| 1 (normal) | `skirmisher` | 58 | 21.7 ms |
| 2 (thorough) | `skirmisher` | 61 | 74.3 ms |
| 0 (fast) | `bastion` | 96 | 9.8 ms |
| 1 (normal) | `bastion` | 148 | 48.2 ms |
| 2 (thorough) | `bastion` | 157 | 162.5 ms |

A 16-opponent AI match generates all Assemblies during the pre-match loading screen at `quality_effort = 1`, totalling under 800 ms across four worker threads.

---

## 10. Garage "Suggest" Mode

When `locked_placements` is non-empty, the pipeline changes in three ways:

1. **Phase 0** pre-seeds the context with the locked placements, computing the resulting budget/mass/mount consumption before any generation.
2. **Phase 1** is skipped if a Core Module is already locked. If none is, the core is chosen to be *compatible* with the locked geometry — its footprint must fit the free space and its `mount_budget` must cover the locked parts.
3. **Phase 8** move proposals exclude any move touching a locked slot. `ctx.locked_slots` is checked in `_propose_move` before the move is constructed.

The player's work is never modified, never moved, and never reoriented. If the locked placements make the spec unsatisfiable — for instance, locked parts already exceed the mount budget — the generator fails immediately with `Outcome.LOCKED_INFEASIBLE` and the UI explains which constraint is violated.

---

## 11. Invariants

1. Every placement passes the unmodified `PlacementValidator` chain. The generator has no privileged placement path.
2. Every intermediate state is a legal Assembly. There is no "repair" step that deletes illegal parts.
3. Generation is fully deterministic given `AssemblySpec.seed`, including after backtracking.
4. The generator uses only `ctx.rng` and never the global RNG.
5. Generation runs on a worker thread and touches no scene-tree node.
6. Hard constraints are checked incrementally; none requires a full Assembly re-scan.
7. `H12` (COM inside the support polygon) is verified at the end of Phase 3 and guarded on every Phase 8 move.
8. Locked placements are never modified.
9. Arc coverage uses the same DDA traversal as the placement validator.
10. Failure returns the last legal partial Assembly, never an illegal one.
