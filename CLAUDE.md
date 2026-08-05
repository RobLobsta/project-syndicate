# CLAUDE.md — Project Syndicate Source of Truth

**This file is binding.** It is the highest-authority document in the repository for any AI or human contributor generating code, data, or assets. Read it in full before writing anything.

Project Syndicate is a 3D multiplayer vehicle-assembly combat game built in **Godot 4** with **GDScript**. Players construct combat vehicles from individual modules in a garage and fight in matches featuring localised structural destruction, deformable ground, and demolishable structures.

---

## 0. The Prime Directive

> **The thirteen documents in `/docs/` are the architecture. No code, data, scene, or asset may contradict them.**

If a task appears to require violating a documented rule, the correct action is to **stop and raise the conflict**, not to implement a workaround, a special case, or a "temporary" exception. Every shortcut in a system like this becomes permanent technical debt within two sprints.

If a document is silent on something, follow the closest documented precedent and the conventions in this file. If genuinely novel architecture is required, it must be added to the relevant document in `/docs/` **in the same change** that introduces it.

---

## 1. The Thirteen Documents

| # | Document | Authoritative for |
|---|---|---|
| 01 | [`docs/PART_DATA_SCHEMA.md`](docs/PART_DATA_SCHEMA.md) | `PartDefinition`, `PartRegistry`, all enums, all constants, mass/integrity tables, resistance matrix, serialisation |
| 02 | [`docs/GRID_SNAPPING_LOGIC.md`](docs/GRID_SNAPPING_LOGIC.md) | Build Lattice, coordinate frames, 24-orientation group, occupancy, `PlacementValidator`, undo model |
| 03 | [`docs/PART_FUSION_SHADER.md`](docs/PART_FUSION_SHADER.md) | Occupancy SDF, fusion shader, vertex displacement, smart skirting, fusion LOD |
| 04 | [`docs/DEPENDENCY_TREE_GRAPH.md`](docs/DEPENDENCY_TREE_GRAPH.md) | `ChassisGraph`, support edges, strain, detachment solver, debris islands, `EventBus` contract |
| 05 | [`docs/DYNAMIC_MASS_PHYSICS.md`](docs/DYNAMIC_MASS_PHYSICS.md) | Single-rigid-body model, mass/COM/inertia, suspension, traction, aerodynamics, stutter elimination |
| 06 | [`docs/AUTO_ASSEMBLE_ALGORITHM.md`](docs/AUTO_ASSEMBLE_ALGORITHM.md) | Archetypes, constraint model, 8-phase generation pipeline, objective function, backtracking |
| 07 | [`docs/WEAPON_TARGETING_LOGIC.md`](docs/WEAPON_TARGETING_LOGIC.md) | Hardpoints, aim solving, ballistic lead, arc solving, emission loop, projectile pool |
| 08 | [`docs/COMPONENT_HEALTH_DAMAGE.md`](docs/COMPONENT_HEALTH_DAMAGE.md) | Damage packets, all five channels, `DegradationTable`, band transitions, visual damage states, repair |
| 09 | [`docs/TERRAIN_CRATER_DEFORMER.md`](docs/TERRAIN_CRATER_DEFORMER.md) | Ground Arrays, crater profile, deformation pipeline, collision streaming, `SurfaceTable` |
| 10 | [`docs/PROCEDURAL_STRUCTURE_SLICING.md`](docs/PROCEDURAL_STRUCTURE_SLICING.md) | Static Volumes, CSG bake, fracture decomposition, support graph, runtime convex slicing |
| 11 | [`docs/RESPONSIVE_GARAGE_UI.md`](docs/RESPONSIVE_GARAGE_UI.md) | Scaling, breakpoints, container hierarchy, virtualised catalogue, input abstraction, theme, **match camera, match HUD, boot flow, match outcome** |
| 12 | [`docs/HEADLESS_NETWORK_SYNC.md`](docs/HEADLESS_NETWORK_SYNC.md) | Authority matrix, channels, snapshot format, prediction, lag compensation, headless server |
| 13 | [`docs/EXTENSION_PIPELINE.md`](docs/EXTENSION_PIPELINE.md) | Asset maturity stages, naming, DCC export contract, import config, validation, promotion workflow |

### 1.1 Which Document Owns Which Constant

When a value appears in more than one place, exactly one document **owns** it and the others **reference** it. Never duplicate a constant.

| Constant / table | Owner |
|---|---|
| `SyndicateConstants` (lattice, limits, cadence, bands) | 01 |
| All `PartEnums` values | 01 |
| Per-part mass, integrity, armour, resistance | 01 |
| `OrientationTable`, `LatticeMath` | 02 |
| `PlacementValidator.Reject` codes | 02 |
| Fusion shader uniforms and defaults | 03 |
| `EventBus` signal list and priority groups | 04 |
| Suspension, traction, Pacejka, aero constants | 05 |
| Rotor thrust, tilt, spool, and shaft-power constants | 05 |
| Gait phase, cadence, foot placement, and stance constants | 05 |
| Road station, differential drive, and slew constants | 05 |
| Input action → `ControlInput` mapping | 05 |
| AI stand-off, steer saturation, gait yaw damping | 05 |
| AI stand-off ladder (ally spacing) | 05 |
| AI scan cadence, target score weights, difficulty error | 07 |
| Archetype weights and budget ratios | 06 |
| Effector timing, spread, recoil, jam constants | 07 |
| Melee reach, arc, sweep, and reaction constants | 07 |
| `DegradationTable` (every band multiplier) | 08 |
| Damage channel formulas and thresholds | 08 |
| `CraterProfile`, `SurfaceTable` (incl. traction multipliers) | 09 |
| Static Volume materials, fracture budgets | 10 |
| Breakpoints, colour tokens, **input map actions** | 11 |
| Screen flow, the shell, and what survives a transition | 11 |
| Blueprint format and the placement-sequence rule | 02 |
| Camera framing, lag rates, aim-ray constants | 11 |
| Reticle states, HUD flash and feed constants | 11 |
| Match outcome rule, end card and control card constants | 11 |
| Protocol version, channel layout, quantisation bits | 12 |
| Triangle budgets, socket names, atlas layout | 13 |
| Proxy mesh resolution, greybox class tints | 13 |

---

## 2. Directory Structure

This layout is normative. Do not create top-level directories not listed here without updating this file.

```
project-syndicate/
├── CLAUDE.md                       ← this file
├── HANDOFF.md                      ← the work queue; see Section 10 rule 1
├── LEARNED_FACTS.md                ← engine facts, testing rules, settled readings
├── CHANGE_LOG.md                   ← what each session did, and what each test defends
├── JULES.md                        ← read-only review charter for an external
│                                     analyst agent. Claude ignores it.
├── README.md                       ← user-facing overview
├── project.godot
├── export_presets.cfg
│
├── docs/                           ← the thirteen architecture documents
│   ├── PART_DATA_SCHEMA.md
│   ├── GRID_SNAPPING_LOGIC.md
│   ├── PART_FUSION_SHADER.md
│   ├── DEPENDENCY_TREE_GRAPH.md
│   ├── DYNAMIC_MASS_PHYSICS.md
│   ├── AUTO_ASSEMBLE_ALGORITHM.md
│   ├── WEAPON_TARGETING_LOGIC.md
│   ├── COMPONENT_HEALTH_DAMAGE.md
│   ├── TERRAIN_CRATER_DEFORMER.md
│   ├── PROCEDURAL_STRUCTURE_SLICING.md
│   ├── RESPONSIVE_GARAGE_UI.md
│   ├── HEADLESS_NETWORK_SYNC.md
│   └── EXTENSION_PIPELINE.md
│
├── src/                            ← ALL GDScript
│   ├── autoload/                   ← singletons; see Section 4
│   │   ├── part_registry.gd
│   │   ├── event_bus.gd
│   │   ├── match_clock.gd
│   │   ├── net_authority.gd
│   │   ├── ui_scale_service.gd
│   │   ├── input_method_service.gd
│   │   ├── subsystem_gate.gd
│   │   └── settings_service.gd
│   │
│   ├── core/
│   │   ├── data/                   ← syndicate_constants.gd, part_enums.gd,
│   │   │                             part_definition.gd, *_profile.gd,
│   │   │                             part_instance_state.gd, part_flags.gd
│   │   ├── math/                   ← lattice_math.gd, orientation_table.gd,
│   │   │                             convex_hull_2d.gd, convex_hull_util.gd,
│   │   │                             bit_writer.gd, bit_reader.gd
│   │   ├── collections/            ← ring_buffer.gd, object_pool.gd
│   │   └── util/                   ← mesh_util.gd, geometry helpers, hashing,
│   │                                 proxy_mesh_builder.gd, proxy_mesh_cache.gd,
│   │                                 greybox_material.gd, part_mesh_factory.gd
│   │
│   ├── assembly/
│   │   ├── lattice/                ← lattice_occupancy.gd, footprint_solver.gd,
│   │   │                             resolved_node.gd, placement_candidate.gd,
│   │   │                             placement_validator.gd, build_context.gd,
│   │   │                             build_budget_ledger.gd, build_shape_cache.gd,
│   │   │                             build_command.gd, build_history.gd,
│   │   │                             blueprint.gd, starter_blueprint.gd
│   │   ├── graph/                  ← chassis_graph.gd, detachment_solver.gd,
│   │   │                             detachment_scheduler.gd, island_detacher.gd,
│   │   │                             mate_selector.gd, mate_record.gd
│   │   ├── mass/                   ← mass_solver.gd, inertia_solver.gd,
│   │   │                             mass_recompute_scheduler.gd
│   │   ├── runtime/                ← assembly_runtime.gd, chassis_body_ref.gd,
│   │   │                             assembly_interpolator.gd, assembly_registry.gd,
│   │   │                             debris_body_ref.gd, debris_pool.gd,
│   │   │                             debris_reaper.gd, assembly_stats.gd,
│   │   │                             assembly_stat_solver.gd
│   │   └── autobuild/              ← auto_assembler.gd, generation_context.gd,
│   │                                 archetype_profile.gd, objective.gd
│   │
│   ├── motion/                     ← motive_system.gd, motive_contact.gd,
│   │                                 suspension_solver.gd, traction_solver.gd,
│   │                                 rotor_solver.gd, rotor_disc_state.gd,
│   │                                 gait_solver.gd, limb_state.gd,
│   │                                 track_solver.gd, track_station.gd,
│   │                                 aero_solver.gd, power_system.gd,
│   │                                 control_input.gd, control_system.gd
│   │
│   ├── combat/
│   │   ├── damage/                 ← damage_resolver.gd, damage_packet.gd,
│   │   │                             degradation_table.gd, dot_scheduler.gd,
│   │   │                             visual_damage_controller.gd
│   │   ├── effectors/              ← effector_system.gd, hardpoint_state.gd,
│   │   │                             aim_solver.gd, firing_group_binding.gd,
│   │   │                             ammo_ledger.gd, melee_solver.gd,
│   │   │                             melee_strike_state.gd
│   │   └── projectiles/            ← projectile_system.gd, projectile_registry.gd,
│   │                                 guided_projectile_controller.gd
│   │
│   ├── world/
│   │   ├── ground/                 ← ground_array.gd, ground_chunk.gd,
│   │   │                             ground_deform_system.gd, crater_profile.gd,
│   │   │                             ground_collision_streamer.gd, surface_table.gd
│   │   ├── volumes/                ← static_volume_runtime.gd, support_graph.gd,
│   │   │                             structure_collapse_solver.gd, convex_slicer.gd,
│   │   │                             fragment_pool.gd
│   │   └── match/                  ← match_state.gd, spawn_director.gd, scoring.gd
│   │
│   ├── net/                        ← net_client.gd, net_server.gd, snapshot_encoder.gd,
│   │                                 snapshot_decoder.gd, prediction_system.gd,
│   │                                 rewind_scope.gd, interest_manager.gd,
│   │                                 quat_codec.gd, blueprint_codec.gd
│   │
│   ├── ui/
│   │   ├── boot/                   ← main_boot.gd, shell_root.gd, main_menu.gd
│   │   ├── garage/                 ← garage_screen.gd, garage_preview.gd,
│   │   │                             catalogue_presenter.gd, part_card.gd,
│   │   │                             part_inspector.gd,
│   │   │                             assembly_stat_panel.gd, touch_placement_controller.gd
│   │   ├── match/                  ← match_screen.gd, chase_camera.gd, hud_frame.gd
│   │   ├── hud/                    ← match_hud.gd, reticle.gd, damage_indicator.gd,
│   │   │                             control_card.gd, match_end_card.gd
│   │   └── common/                 ← meter_row.gd, stat_row.gd, toast_stack.gd,
│   │                                 input_prompt.gd, ui_tokens.gd, breakpoint.gd
│   │
│   ├── vfx/
│   │   ├── fusion/                 ← occupancy_sdf_baker.gd, skirting_builder.gd,
│   │   │                             skirt_run_collector.gd, fusion_instance_writer.gd
│   │   ├── shaders/                ← *.gdshader
│   │   └── particles/              ← vfx_pool.gd, spark_vfx.gd, rubble_vfx.gd
│   │
│   └── ai/                         ← ai_context.gd, ai_target_selector.gd, ai_driver.gd
│
├── scenes/
│   ├── boot/                       ← main.tscn, main_menu.tscn
│   ├── garage/                     ← garage_screen.tscn
│   ├── match/                      ← arena_*.tscn, match_hud.tscn
│   ├── net/                        ← dedicated_server.tscn
│   └── prefabs/                    ← assembly_runtime.tscn, debris_body.tscn
│
├── data/                           ← .tres resources; NO logic
│   ├── parts/                      ← <class>/<dotted_key>.tres + .visual/.collider/.fusion
│   ├── projectiles/
│   ├── archetypes/
│   ├── materials/
│   ├── ui/                         ← syndicate_theme.tres, high_contrast_theme.tres
│   └── tables/                     ← balance CSVs consumed by tools
│
├── assets/                         ← imported art; see docs/EXTENSION_PIPELINE.md §3
├── art_src/                        ← DCC sources; NEVER exported
│
├── addons/
│   └── syndicate_pipeline/         ← import plugin, editor tools
│
├── tools/                          ← @tool / EditorScript utilities and CI checks
│   ├── validate_part_registry.gd
│   ├── validate_part_visuals.gd
│   ├── bake_static_volumes.gd
│   ├── bake_part_blockout.gd
│   ├── promote_part_stage.gd
│   └── ci/
│
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── physics/
│   ├── generation/
│   └── arch/                       ← architectural conformance tests; see Section 9
│
└── .build/                         ← generated tool output; gitignored, never committed
```

`.build/` is the only directory here that is not authored. It holds
`part_registry_report.md` (`docs/PART_DATA_SCHEMA.md` §14) and the promotion
contact sheets of `docs/EXTENSION_PIPELINE.md` §8. It is regenerated by the
validators on every run; nothing may read it at runtime.

---

## 3. GDScript Style Rules

### 3.1 File and Symbol Naming

| Kind | Convention | Example |
|---|---|---|
| Script file | `snake_case.gd` | `chassis_graph.gd` |
| Shader file | `snake_case.gdshader` | `part_fusion.gdshader` |
| Scene file | `snake_case.tscn` | `garage_screen.tscn` |
| Resource file | `snake_case.tres` / `dotted.key.tres` for parts | `syndicate_theme.tres`, `str.panel.medium.t2.tres` |
| Class name | `PascalCase` via `class_name` | `class_name ChassisGraph` |
| Node in a scene | `PascalCase` | `CatalogueDock`, `ChassisBody` |
| Runtime-generated node | `snake_case` with index | `part_s014`, `shape_s014_p0` |
| Function | `snake_case` | `resolve_blast()` |
| Private function | `_snake_case` | `_compute_effective()` |
| Variable | `snake_case` | `integrity_band` |
| Private variable | `_snake_case` | `_visit_stamp` |
| Constant | `SCREAMING_SNAKE_CASE` | `MAX_CHAIN_DEPTH` |
| Enum type | `PascalCase` | `enum IntegrityBand` |
| Enum member | `SCREAMING_SNAKE_CASE` | `IMPAIRED` |
| Signal | `snake_case`, **past tense** | `part_destroyed`, `assembly_structure_changed` |
| `StringName` literal | `&"snake_case"` | `&"skirmisher"` |
| Autoload singleton | `PascalCase` | `PartRegistry`, `EventBus` |

### 3.2 Mandatory Practices

1. **Static typing everywhere.** Every variable, parameter, and return value is typed. `var x := 5` (inferred) is acceptable; bare `var x = 5` is not.
2. **Typed collections** where the element type is known: `Array[PartDefinition]`, `PackedInt32Array`, `PackedByteArray`.
3. **Packed arrays over `Array`** for numeric and byte data. `Array[int]` in a hot path is a defect.
4. `class_name` on every script that is instantiated by type or used as a type annotation.
5. **Documentation comments** (`##`) on every `class_name`, every public function, and every exported property. Regular `#` comments explain *why*, never *what*.
6. `@export` properties are grouped with `## ===== SECTION =====` banner comments in resources with more than eight properties.
7. `assert()` for invariants that indicate a programming error. Never for input validation — validate and return an error instead.
8. `push_error` / `push_warning` for recoverable problems, always with enough context to identify the offending resource by key or path.
9. **No magic numbers.** Every literal outside `0`, `1`, `-1`, `0.0`, `1.0`, and `0.5` is a named `const` in the owning class.
10. Prefer `is_zero_approx` / `is_equal_approx` over `==` on floats.
11. `@onready` only for node references. Never for computed values.

### 3.3 Forbidden Patterns

| Forbidden | Why | Use instead |
|---|---|---|
| `get_node()` with a hard-coded path in gameplay code | Fragile against scene edits | `@export` node reference or `@onready var x := $Path` |
| `find_child()` / `find_children()` at runtime | O(n) tree walk | Cached reference set at spawn |
| `Node.get_tree().call_group()` in a hot path | Reflection cost | Direct `EventBus` signal |
| String-keyed `Dictionary` in a per-tick loop | Hashing cost | Flat array indexed by slot |
| `preload()` of a large scene inside a function | Load stall | Module-level `const` preload or `ResourceLoader` async |
| `Object.call()` / `callv()` with a string method name | Unverifiable | `Callable` |
| `yield` / `await` inside `_physics_process` | Breaks determinism | Scheduler + event |
| Global `randi()` / `randf()` in gameplay | Breaks determinism and network sync | A seeded `RandomNumberGenerator` owned by the system |
| `_process` or `_physics_process` on a class that only reacts to events | Wasted CPU; violates the event-driven mandate | Connect to `EventBus` |
| Mutating a `PartDefinition` at runtime | It is shared and immutable by contract | Per-instance state on `PartInstanceState` |
| `ConcavePolygonShape3D` on anything dynamic | Performance and stability | Primitives or convex hulls |
| Any `CSGShape3D` in an exported scene | Runtime CSG cost | Bake to `ArrayMesh` offline |

### 3.4 Formatting

- Indentation: **tabs**, one per level (Godot default).
- Maximum line length: **100 characters**. Break long expressions at operators with the continuation indented one level.
- Two blank lines between top-level function definitions; one blank line between logical blocks inside a function.
- Declaration order in a script: `@tool` → `class_name` → `extends` → `## docstring` → signals → enums → constants → `@export` vars → public vars → private vars → `@onready` vars → `_init` → `_ready` → Godot callbacks → public methods → private methods → inner classes.

---

## 4. Autoload Singletons

Exactly these eight, registered in this order (order matters — later ones may depend on earlier ones):

| Order | Name | Script | Responsibility |
|---|---|---|---|
| 1 | `SyndicateSettings` | `src/autoload/settings_service.gd` | User settings, quality tiers, key rebinds |
| 2 | `SubsystemGate` | `src/autoload/subsystem_gate.gd` | Enables/disables subsystems by feature tag (headless) |
| 3 | `PartRegistry` | `src/autoload/part_registry.gd` | Immutable part definition registry |
| 4 | `EventBus` | `src/autoload/event_bus.gd` | All cross-system signals |
| 5 | `MatchClock` | `src/autoload/match_clock.gd` | Authoritative tick counter and tick phases |
| 6 | `NetAuthority` | `src/autoload/net_authority.gd` | Server/client role, peer identity, prediction flags |
| 7 | `UiScale` | `src/autoload/ui_scale_service.gd` | Logical size, DPI, content scale |
| 8 | `InputMethod` | `src/autoload/input_method_service.gd` | Active input device detection |

**No new autoloads may be added without updating this table and `docs/`.** An autoload is a global; each one added is a permanent increase in coupling. The bar is deliberately high.

---

## 5. Collision Layers and Render Layers

### 5.1 Physics Layers

Defined once in `src/core/data/collision_layers.gd`. Layer numbers are frozen.

| Bit | Layer | Occupied by |
|---|---|---|
| 1 | `LAYER_ASSEMBLY_HULL` | `ChassisBody` collision shapes |
| 2 | `LAYER_ASSEMBLY_MOTIVE` | Reserved for motive-specific volumes |
| 3 | `LAYER_GROUND` | Streamed Ground Array chunk collision |
| 4 | `LAYER_STATIC_VOLUME` | Static Volume section bodies |
| 5 | `LAYER_PROJECTILE` | Reserved (projectiles are raycast, not bodies) |
| 6 | `LAYER_DEBRIS` | Detached islands, Static Volume fragments |
| 7 | `LAYER_TRIGGER_VOLUME` | Capture zones, kill volumes, spawn areas |
| 8 | `LAYER_BUILD_GHOST` | Garage-only build proxies |
| 9 | `LAYER_BUILD_FLOOR` | Garage-only ground plane |
| 10 | `LAYER_AIM_TRACE` | Aim raycast targets (hull + ground + volumes) |

Common masks:

```gdscript
const MASK_ASSEMBLY_HULL     := (1 << 0) | (1 << 2) | (1 << 3) | (1 << 5)
const MASK_GROUND            := 1 << 2                      # LAYER_GROUND
const MASK_STATIC_VOLUME     := 1 << 3
const MASK_DEBRIS            := (1 << 2) | (1 << 3)         # ground + volumes only
const MASK_PROJECTILE_TARGET := (1 << 0) | (1 << 2) | (1 << 3) | (1 << 5)
const MASK_BLAST_QUERY       := (1 << 0) | (1 << 3) | (1 << 5)
const MASK_AIM_TRACE         := (1 << 0) | (1 << 2) | (1 << 3)
const MASK_BUILD_GHOST       := 1 << 7
```

Note `MASK_DEBRIS` excludes `LAYER_DEBRIS` — debris never collides with debris. `MASK_ASSEMBLY_HULL` *includes* its own layer, because Assemblies ram each other, and includes `LAYER_DEBRIS` so a wreck left in the road is an obstacle rather than a decoration.

### 5.2 Render Layers

| Bit | Layer | Contents |
|---|---|---|
| 1 | `LAYER_WORLD` | Ground, Static Volumes, skybox-adjacent geometry |
| 2 | `LAYER_ASSEMBLY_VISUAL` | All Assembly part meshes, skirting, decals |
| 3 | `LAYER_DEBRIS_VISUAL` | Detached islands and fragments |
| 4 | `LAYER_VFX` | Particles, tracers, beams |
| 5 | `LAYER_GARAGE_ONLY` | Lattice grid, ghost preview, build gizmos |
| 20 | `LAYER_ICON_RENDER` | Isolated layer for the part-icon `SubViewport` |

---

## 6. Core System Invariants

These are absolute. A change that violates one is a change to the architecture and requires updating `/docs/`, not a code comment explaining the exception.

### I-1 — Decoupled Collision Architecture
Physics geometry and visual geometry are separate, independently authored assets, and **the simulation reads only the physics geometry**.

- Every collider on an Assembly is an authored `ColliderProfile` primitive: `BoxShape3D`, `CylinderShape3D`, `CapsuleShape3D`, or `SphereShape3D`. Maximum three per part.
- No collision shape is ever generated from a visual mesh at runtime. `ConcavePolygonShape3D` is forbidden on anything dynamic.
- Every node under `VisualRoot` has `collision_layer = 0` and `collision_mask = 0`, and is never a child of a `PhysicsBody3D`.
- Colliders do not change with damage state, visual LOD, hardpoint rotation, animation, or fusion displacement. A part's physical footprint is fixed from placement to destruction.
- Static Volumes and their fragments obey the same rule: convex hulls or primitives only, generated from partition geometry, never from rendered meshes.

### I-2 — The Core Module Is The Root
- Every Assembly has exactly one Core Module, at slot `0`.
- Slot `0` is the `ChassisGraph` primary-tree root and has `parent_slot == INVALID_SLOT`.
- The Core Module owns the single `RigidBody3D`.
- Losing the Core Module terminates the Assembly.

### I-3 — One Rigid Body Per Assembly
- An Assembly is one `RigidBody3D`. There are **no joints between parts**. Ever.
- Structural failure is a discrete topological event in the Chassis Graph, never a physics constraint.
- Suspension travel is modelled per Motive Assembly by shape casts; the chassis itself is rigid.
- This holds for every locomotion family. An ambulatory limb is a **virtual leg** — one spring-damper force along the hip-to-foot line — and its visible articulation is inverse kinematics under `VisualRoot`. A rotor disc is a thrust vector. Neither is a joint, neither is a body, and `docs/DYNAMIC_MASS_PHYSICS.md` §13.1 records why a jointed leg is not merely forbidden but unnecessary.

### I-4 — Event-Driven Structural Evaluation
- Connectivity, mass properties, fusion SDF, skirting, strain, and functional degradation are recomputed **only** in response to discrete events.
- `ChassisGraph` and `DetachmentSolver` declare no `_process` and no `_physics_process`. This is enforced by `tests/arch/test_no_polling.gd`.
- Detachment is batched to once per tick per Assembly, in deterministic order.
- A match with no destruction costs zero graph CPU time.

### I-5 — Component-Level Functional Degradation
- Every part degrades through five bands: `NOMINAL`, `STRESSED`, `IMPAIRED`, `CRITICAL`, `DESTROYED`, at 75%, 50%, 30%, and 0% of maximum integrity.
- All multipliers come from `DegradationTable` (owner: doc 08). No subsystem defines its own thresholds or curves.
- Multipliers are written into cached flat arrays at band transitions. **No hot loop ever reads integrity or computes a band.**
- Reference behaviours: a Motive Assembly below 50% integrity has traction multiplier `0.60` and sparks; an Effector Module below 30% has an `0.18` per-shot jam chance.

### I-6 — Integer-Only Placement
- Placement decisions are integer arithmetic over the lattice. Floats appear only when converting a pointer ray to a candidate cell, and are quantised immediately.
- `orientation_index ∈ [0, 24)`; the index-to-basis mapping is frozen and serialised.
- The single physics query in the validation chain runs last and may only reject, never accept.
- The occupancy array is the sole authority on overlap. There is no separate broadphase for building.

### I-7 — Seamless Metal Fusion Is Presentation Only
- Fusion SDF, vertex displacement, and skirting meshes are visual. They never produce, modify, or are read by collision.
- Fusion quality settings have zero effect on hit registration, damage, mass, or any simulated quantity.
- SDF bakes and skirt rebuilds run on `WorkerThreadPool`; only texture upload and mesh assignment touch the main thread.

### I-8 — Server Authority
- The server is authoritative for transforms, integrity, bands, topology, damaging projectiles, ground deformation, and structure failure.
- Clients predict only their own Assembly, and never predict jams or destruction.
- Clients report intent to fire, never what they hit.
- `integrity_band` is replicated explicitly; clients never derive it from quantised integrity.
- Blueprints from clients are re-validated server-side through the same `PlacementValidator` the garage uses.

### I-9 — Determinism Where It Is Claimed
Systems documented as deterministic must be bit-reproducible: ground deformation, auto-assembly generation, fracture layout, spread rolls, and detachment ordering.

- Use a seeded `RandomNumberGenerator` owned by the system. Never the global RNG.
- Iterate sorted key lists, never raw `Dictionary` key order.
- Sort with a total order; break ties on a stable integer id.

### I-10 — No Runtime CSG
- No `CSGShape3D` node exists in any scene loaded during a match. CI enforces this by parsing exported scenes.
- CSG is confined to editor authoring and offline bakes. Runtime geometry change uses convex plane slicing on already-convex hulls.

### I-11 — Data Is Immutable At Runtime
- `PartDefinition` and every profile resource are read-only after `PartRegistry._ready()`.
- All mutable per-part state lives in `PartInstanceState`.
- Per-instance modifiers (corrosive resistance decay, tint) are stored on the instance, never written back to shared data.

### I-12 — Bounded Work
Every system that can be triggered repeatedly has an explicit bound:

| System | Bound |
|---|---|
| Damage chain reactions | depth 3 |
| Projectile penetrations | 4 per round |
| Projectile sweep segments | 8 per round per tick |
| Terminal debris components | 8 per Assembly |
| Collapse cascades | 6 ticks per trigger |
| Fragment slicing | 3 slices per fragment |
| Melee targets | `max_targets_per_swing`, ≤ 8 |
| Melee sweep segments | `swing_samples`, ≤ 16 |
| Auto-assemble backtracking | 6 attempts |
| Ground deform commit | 1.5 ms/frame |
| Slice commit | 0.8 ms/frame |
| Debris bodies | 96 pooled |
| Fragments | 320 global, 64 per volume |
| Projectiles | 2048 pooled |
| Fused Assemblies | 24 |
| Skirt vertices | 24 000 per Assembly |

---

## 7. Input Map Standard

Action names are normative. The full table with per-device bindings is in `docs/RESPONSIVE_GARAGE_UI.md` §7.1. Adding an action requires updating both that table and `project.godot`.

### 7.1 Naming Rules

- Prefix by domain: `veh_`, `effector_`, `build_`, `cam_`, `catalogue_`, `hud_`, `net_`.
- `snake_case`, verb-first where an action, noun-first where a mode.
- Godot's built-in `ui_*` actions are used for menu navigation and are never rebound.

### 7.2 Canonical Action List

```
veh_throttle            veh_brake              veh_steer_left
veh_steer_right         veh_handbrake          veh_boost
veh_pitch_forward       veh_pitch_back         veh_roll_left
veh_roll_right

effector_fire_primary   effector_fire_secondary effector_fire_tertiary
effector_cycle_group

build_place             build_remove           build_pick
build_rotate_yaw        build_rotate_pitch     build_rotate_roll
build_mirror_toggle     build_undo             build_redo
build_cancel            build_cursor_left      build_cursor_right
build_cursor_up         build_cursor_down

cam_orbit               cam_pan                cam_zoom_in
cam_zoom_out            cam_focus_selection    cam_toggle_view
cam_look_left           cam_look_right         cam_look_up
cam_look_down

catalogue_search        catalogue_next_class   catalogue_prev_class

hud_toggle_stats        hud_ping               hud_scoreboard

net_diagnostics_toggle
```

### 7.3 Rules

1. Never read a raw key or button in gameplay code. Always `Input.is_action_*` or an `InputEvent.is_action*` test.
2. Analogue actions (`veh_throttle`, `veh_steer_*`) use `Input.get_action_strength` so triggers and sticks work without a special case.
3. Rebinds are stored in `SyndicateSettings` and applied through `InputMap` at startup. Never hard-code a rebind.
4. UI-tier adaptation is driven by `InputMethod`, which is orthogonal to the layout breakpoint.

---

## 8. Terminology

Generic engineering nomenclature is mandatory across code, data, comments, commit messages, and user-facing strings. The full table is in `docs/PART_DATA_SCHEMA.md` §2. Summary of the required terms:

**Core Module** · **Structural Component** · **Motive Assembly** · **Prime Mover** · **Energy Cell** · **Effector Module** · **Support Module** · **Control Surface** · **Appendage** · **Dynamic Ground Array** · **Static Volume** · **Assembly** · **Build Lattice** · **Attachment Node** · **Chassis Graph** · **Integrity** (not "health" in identifiers) · **Effector** (not "weapon" in identifiers)

Prohibited in identifiers, resource names, and localisation keys: *cabin, cockpit, armor plate, wheel, engine, weapon, gun, cannon, terrain, building, vehicle, car, health bar*.

**Power Plant** was the term for the torque source and was retired in favour of
**Prime Mover** and **Energy Cell**. It named one class doing two unrelated jobs
— making shaft torque and supplying power — and it read as a fixed installation
rather than as something bolted into a vehicle. *Prime Mover* is the standard
engineering term for a machine that converts energy into motion and covers a
piston, a turbine, and a reaction drive without favouring any of them; *engine*
stays prohibited above for the same reason *wheel* and *cannon* do. The split is
`docs/PART_DATA_SCHEMA.md` §7.3 and §7.7.

`hardpoint` is permitted **only** for the two-DOF rotational mount internal to an Effector Module.

`arm`, `hand`, `grip`, and `shoulder` are permitted as **mechanism** vocabulary on the Appendage class — `apx.arm.manipulator.t3`, `AppendageProfile.grip_rating_n`, the `hand` attachment node — in exactly the way `rotor`, `limb` and `foot` already are. What stays prohibited is using them as a substitute for the class: the class is always `APPENDAGE`, never "the arms". A weapon carried in one is a **held Effector Module**, never a "weapon" in an identifier.

`rotor`, `disc`, `limb`, `foot`, `hip`, `stance`, `swing`, and `gait` are permitted as **family and mechanism** vocabulary — `mot.rotor.*`, `LimbState.foot_world`, `GaitSolver` — in exactly the way `wheeled` and `tracked` already are in `mot.wheeled.*` and `MotiveKind.WHEELED_STEERED`. What stays prohibited is using any of them as a **substitute for the class**: the class is always `MOTIVE_ASSEMBLY`, never "the legs" or "the rotors". `helicopter`, `mech`, `walker`, and `aircraft` are prohibited outright — an Assembly is an Assembly regardless of how it gets around, and that is the point of §I-3's last bullet.

---

## 9. Testing Requirements

### 9.1 Required Test Categories

| Directory | Purpose | Must exist for |
|---|---|---|
| `tests/unit/` | Pure function correctness | Every math utility, codec, and table |
| `tests/integration/` | Cross-system behaviour | Tick ordering, damage→detach→mass chain, ground determinism |
| `tests/physics/` | Simulation correctness | Inertia coupling, suspension settling, traction curves |
| `tests/generation/` | Auto-assemble | Determinism, legality, archetype conformance |
| `tests/arch/` | Architectural conformance | See below |

### 9.2 Architectural Conformance Tests

These parse the source tree and fail the build on violation. They are the automated enforcement of Section 6.

| Test | Enforces |
|---|---|
| `test_no_polling.gd` | No `_process`/`_physics_process` in `src/assembly/graph/` |
| `test_visual_decoupling.gd` | No `CollisionShape3D` under any `VisualRoot`; no mesh-derived shapes |
| `test_no_runtime_csg.gd` | No `CSGShape3D` in exported scenes |
| `test_no_global_rng.gd` | No `randi()`/`randf()`/`randomize()` in `src/` outside `tests/` |
| `test_degradation_table.gd` | `DegradationTable` arrays are length 5, monotonic in the correct direction, terminate at 0 |
| `test_constant_ownership.gd` | No constant defined in more than one file |
| `test_autoload_set.gd` | Autoload list matches Section 4 exactly |
| `test_input_actions.gd` | `project.godot` action set matches Section 7.2 exactly |
| `test_no_forbidden_patterns.gd` | The Section 3.3 forbidden list |
| `test_doc_indexes.gd` | Every document in `/docs/` carries a current index of its own top-level sections |

### 9.3 Coverage Expectations

New systems ship with unit tests for their pure logic and at least one integration test exercising their event contract. A change to any value in a table owned by a document (Section 1.1) requires updating that document in the same change.

---

## 10. Rules For Generated Code

Any AI session producing code for this repository must obey the following. These are not stylistic preferences; they exist because this architecture's performance and correctness properties are structural and are easily destroyed by a plausible-looking shortcut.

1. **The Session Lifecycle Contract.** Every AI session works this loop, in this order, and none of the four steps is optional.

   - **Initialisation.** Read `HANDOFF.md` before taking any other action — before reading source, before running the suite, before answering. It is the work queue: what to do next, in the order it is worth doing, plus the standing player-experience review that sets that order. Then read **`LEARNED_FACTS.md` §1 before writing any code and §3 before writing any test**. A session that skips these re-derives them at full price and usually re-derives them wrong.
   - **Execution.** Do the work, under every rule in this file and every document in Section 1. Consult `CHANGE_LOG.md` when you need to know when something changed and why.
   - **Consolidation.** Before reporting, update all three files so they describe the repository as it now stands, and **consolidate; do not append**:
     - `HANDOFF.md` — a queue. A step that has been taken leaves it. If it only ever grows, it has failed. Keep it short enough to read in full.
     - `LEARNED_FACTS.md` — durable knowledge only. A fact belongs here when it would cost the next session time to rediscover, and it is written once rather than re-stated per session. Prune anything the code now enforces.
     - `CHANGE_LOG.md` — one short entry per session, and the per-test fault record. Compress older entries as they stop mattering; the git history holds the long version.
   - **Reporting.** The final message to the user is a plain-language description of what was built and what comes next. Not a diff summary, not a list of file paths, and not the commit message again.

   These three files are the only memory that survives a context window. Treat a stale or inflated one as a defect of the same order as a stale document under Section 1, because the next session's first hour is spent believing it. **Splitting them further, or merging them back, is a change to this section** — the division is by *lifetime*: a queue that empties, knowledge that accumulates, and a record that compresses.

2. **Read the relevant `/docs/` document before writing code that touches its subsystem.** Do not infer the design from surrounding code alone.

3. **Never introduce a per-frame poll of structural state.** If you find yourself writing a loop over parts inside `_process` or `_physics_process` that reads integrity, connectivity, or attachment, stop. The correct implementation is an `EventBus` connection plus a cached array.

4. **Never generate collision from a mesh.** No `create_trimesh_collision()`, no `create_convex_collision()`, no `-col` import suffix, no `CollisionShape3D` parented under a visual node. Colliders come from `ColliderProfile` and nowhere else.

5. **Never add a joint between Assembly parts.** If a task seems to require flex, the answer is a Chassis Graph event or a visual-only effect.

6. **Never duplicate a constant.** Look it up in the Section 1.1 ownership table and import it.

7. **Never use the global RNG in gameplay code.** Every stochastic system owns a seeded generator.

8. **Never write a literal user-facing string.** Use a `tr()` key.

9. **Never bypass `PlacementValidator`.** The garage, the auto-assembler, blueprint loading, and server-side blueprint validation all use the identical chain.

10. **Never write `PartInstanceState.integrity` outside `DamageResolver`.** Repair routes through the same band-transition path.

11. **Never add an autoload** without updating Section 4 and the architecture documents.

12. **Never add a top-level directory** not listed in Section 2.

13. **When adding a new part**, add it to `registry_manifest.tres` by appending only. Never reorder, never remove — `part_def_id` values are serialised in save data and network packets.

14. **A normative formula that produces a vector must state the direction it is applied in.** A magnitude is half a specification. Doc 05 §6.5 published `F_arb = k_arb · (x_left − x_right)` and said nothing about which way the pair is pushed; the implementation applied it inverted for the life of the project, turning the anti-roll bar into a roll *amplifier* that put builds on their roofs from a walking pace, and the unit test over the formula passed the whole time because it asserted the number. Any document giving a force, a torque, an impulse or an offset must say what the positive sense means in world or body terms, and the test for it must assert that sense and not only the magnitude.

15. **When a task conflicts with a document**, raise the conflict rather than implementing around it. Then, if the architecture genuinely must change, update the document and the conformance tests in the same change.

16. **Match the surrounding code.** Comment density, naming, and idiom should be indistinguishable from the files around the change.

17. **Do not stub.** Code committed to this repository is complete. `TODO`, `FIXME`, `implement later`, and `pass  # placeholder` are not acceptable in `src/`. If the full implementation is not yet possible, do not commit the partial one.

18. **Play the game before you call the work done.** Before wrapping anything up, review the repository as it now stands and answer one question: **would a customer get the best possible experience from this game in this state?** Not "do the tests pass", not "is the architecture sound" — whether the thing is any good to play.

    This rule is a deliberate counterweight. Every other rule in this file pushes toward internal correctness, and a project can satisfy all of them while being unplayable: no scene, no camera, a vehicle that flips on its first shot, a locomotion family that cannot hold a heading. Those findings are invisible to a green suite, and a green suite is exactly what makes them easy to stop noticing.

    Ask at least:

    - Can a person start it, see something, and press a key that does something?
    - Of the things that *are* reachable, which is the most broken or the least satisfying, and why?
    - Which single change would most improve a first-time player's experience?
    - Does anything shipped feel unfinished, unfair, or confusing in a way a player would notice before a developer would?

    **What this turns up drives the work.** It is not a report filed and forgotten: it should shape what the current session does with its remaining time and what the next session is told to do first. Findings belong in `HANDOFF.md` alongside the technical ones, and a plain-language summary of the assessment — **including the bad news** — is mandatory in the final message to the user, every session, whether or not the session's task was player-facing.

---

## 11. Build and Run

```bash
# Editor
godot --editor --path .

# Client
godot --path .

# Headless dedicated server
godot --headless --path . --main-scene res://scenes/net/dedicated_server.tscn \
      -- --port=27015 --max-players=16 --map=arena_basin --tickrate=60

# Full validation suite (run before any commit touching src/ or data/).
# Use the wrapper, not the runner: it reimports first, and it fails on engine
# errors the runner's exit code cannot see.
tools/ci/run_all_checks.sh                       # ~24 s

# The runner directly, when you want the raw output. --fixed-fps is not optional
# for anything that touches tests/physics/: headless Godot paces its main loop
# against the wall clock, so without it a 900-tick engagement costs 15 real
# seconds and the suite costs five minutes instead of seventeen seconds. It
# changes pacing only — the physics delta stays 1/60 — so Invariant I-9 holds and
# results are byte-identical either way.
#
# Never substitute Engine.time_scale. It scales delta rather than the frame
# count: measured on 4.7.1 it yields no speedup at all and hands
# _physics_process a 0.333 s step.
godot --headless --path . --fixed-fps 60 --script tools/ci/run_all_checks.gd

# Individual validators
godot --headless --path . --script tools/validate_part_registry.gd
godot --headless --path . --script tools/validate_part_visuals.gd

# Static Volume bake
godot --headless --path . --script tools/bake_static_volumes.gd

# Regenerate the section index at the top of each of the thirteen documents.
# Run it after adding or renaming a top-level section; tests/arch/test_doc_indexes.gd
# fails the build when one is stale, because a hand-maintained list of contents
# rots in the direction of looking complete.
python3 tools/ci/doc_index.py
```

Key `project.godot` settings that must not be changed without an architecture review:

```
[physics]
common/physics_ticks_per_second=60
common/physics_jitter_fix=0.0            # see docs/DYNAMIC_MASS_PHYSICS.md §10.1
3d/solver/solver_iterations=12

[display]
window/stretch/mode="canvas_items"       # see docs/RESPONSIVE_GARAGE_UI.md §2.1
window/stretch/aspect="expand"
```

---

## 12. Change Protocol

| Change type | Required |
|---|---|
| New part | Manifest append + `.tres` set + validator pass. No code. |
| Balance value change | Update the owning document's table in the same commit. `balance-review` label. |
| New subsystem | Architecture document section added or amended first, then code, then conformance test. |
| Collider change | `balance-review` label; collider baseline hash update; explicit justification. |
| Art promotion | Visual files + one `.visual.tres` only. Nothing else in the diff. |
| Invariant change | Update Section 6 here, update the owning document, update `tests/arch/`, and flag it prominently in review. |

---

*Project Syndicate — Principal Systems Architecture. Every rule in this file exists because its absence produced a specific, diagnosable failure in a system of this shape.*
