# HANDOFF

Working notes for the next session. **Not** an architecture document — `CLAUDE.md`
and the thirteen documents in `/docs/` remain the only authority. This file
records what exists, what it cost to learn, and what to do next.

Last updated: session 1 (environment bootstrap + core data/math foundation).

---

## 1. Getting a working environment

Nothing is installed by default. One command provisions everything:

```bash
tools/ci/bootstrap_env.sh          # idempotent; ~75 MB download, ~30 s
```

That puts Godot **4.7.1-stable** in `.tooling/godot/`. `.tooling/` is gitignored
in full and holds the engine binary, the engine's `XDG_*` data, and test output,
so nothing the toolchain writes can land in a commit.

Run the engine only through the wrapper, never the binary directly — the wrapper
redirects `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, and `XDG_CACHE_HOME` into
`.tooling/`, and without it Godot scatters editor settings and shader caches
across `$HOME` and CI stops being reproducible:

```bash
tools/ci/godot.sh --headless --path . --version
tools/ci/run_all_checks.sh          # full suite; reimports first
```

`GODOT_VERSION` overrides the pinned version for `bootstrap_env.sh`. The engine
downloads from the GitHub releases CDN, which the agent proxy allows; the GitHub
**API** is blocked in this environment, so do not try to resolve "latest" through
`api.github.com`.

### Current suite status

**14 files, 731 checks, 0 failures.** Verified to actually fail on a planted
violation (global `randf()`, a `_process` in `src/assembly/graph/`, and a
`find_child()` each produce a located, actionable failure and exit 1).

---

## 2. Engine facts that cost time — read before writing code

These are all verified against 4.7.1 in this repo, not recalled.

1. **`--import` does not catch parse errors.** It registers `class_name` globals
   by scanning source without compiling it, so a broken script imports cleanly
   and only explodes when something first loads it. `tests/arch/test_scripts_parse.gd`
   exists solely to close this hole — it loads every `.gd` under `src/`, `tools/`,
   and `tests/` and asserts each one instantiates.

2. **`--script` with a `SceneTree` subclass must not do its work in `_init()`.**
   `_init` runs before the main loop is initialised and a `quit()` issued there
   is discarded; the process then idles forever with its output still buffered.
   Do the work on the first `_process` frame instead. Waiting one frame also
   guarantees the eight autoloads are in the tree.

3. **`Basis.get_column()`, `set_column()`, and `get_row()` were removed in 4.7.**
   `Basis.x`, `.y`, `.z` remain and are the **columns**. `OrientationTable`
   reassembles bases through the `Basis(x, y, z)` constructor.

4. **`Vector3i` components are int32.** A 64-bit sentinel assigned into one wraps
   silently — `9223372036854775807` becomes `-1`, which produced a bounds
   minimum of `(-1,-1,-1)` in `PartDefinition._bake_derived_fields`. Use
   `±2147483647`.

5. **`const X: PackedStringArray = PackedStringArray([...])` is not a constant
   expression.** Use `const X: Array[String] = [...]`. Typed `Array[Vector3i]`
   constants are fine.

6. **A typed-array `const` does not give a `for` loop's variable a static type.**
   With `untyped_declaration=2` (error, as configured) you must write
   `for name: String in CANONICAL:`.

7. **`Callable.bind()` does not make two Callables compare unequal.** Two bound
   Callables over the same object and method are equal, so binding an index
   cannot distinguish handlers. Use a distinct receiver object per handler.

8. **`PackedInt32Array` assigns by value.** Sharing one between objects hands
   each its own copy. Wrap it in a `RefCounted` when it must be shared.

9. **`ProjectSettings.get_property_list()` reports every built-in `ui_*` action**
   whether or not the project declares it. To read what the project actually
   declares, parse the `[input]` section of `project.godot`.

10. **Godot rewrites `project.godot` and drops any setting equal to the engine
    default.** `physics_ticks_per_second=60`, `stretch/scale_mode="fractional"`,
    and `renderer/rendering_method="forward_plus"` are all in force but absent
    from the file. `tests/arch/test_project_settings.gd` therefore asserts
    *effective* values through `ProjectSettings`, never by grepping the text.
    Do not "restore" those lines — they will vanish again on the next save.

---

## 3. Architecture change made this session

**`docs/PART_DATA_SCHEMA.md` §6.2 was amended, and `docs/EXTENSION_PIPELINE.md`
updated to match.**

§6.2 declared `PrimitiveDef` as an inner class of `ColliderProfile`. Godot 4
cannot serialise an inner-class `Resource` into a `.tres`: it writes the element
script as an empty `[sub_resource type="GDScript"]` with no source, and on load
every element fails typed-array validation and is dropped **silently**. A probe
saved a profile with one primitive and loaded it back with zero.

Since I-1 makes `ColliderProfile` the only source of Assembly collision geometry,
this would have shipped every part with an empty collider set and no hit
registration. The type is now top-level `ColliderPrimitiveDef`
(`src/core/data/collider_primitive_def.gd`), the document records the reasoning,
and `tests/unit/test_collider_profile_serialisation.gd` round-trips a populated
profile on every run so it cannot regress.

Nothing else in the thirteen documents was changed.

---

## 4. What exists now

### Environment and CI
| Path | Purpose |
|---|---|
| `tools/ci/bootstrap_env.sh` | Provisions Godot into `.tooling/` |
| `tools/ci/godot.sh` | Engine wrapper with redirected XDG paths |
| `tools/ci/run_all_checks.sh` | Reimport + suite; the command to run |
| `tools/ci/run_all_checks.gd` | Discovery-based headless test runner |
| `.gitignore` | Ignores `.tooling/`, `.godot/`, exports |

### Source
- `src/core/data/` — `SyndicateConstants`, `PartEnums`, `CollisionLayers`,
  `RenderLayers`, `PartFlags`, `PartDefinition`, `PartManifest`,
  `PartInstanceState`, `AttachmentNodeDef`, `ColliderPrimitiveDef`,
  `ColliderProfile`, `FusionProfile`, `ProxyPrimitiveDef`, `PartVisualProfile`,
  and the six class profiles.
- `src/core/math/` — `LatticeMath`, `OrientationTable` (full 24-element group).
- `src/autoload/` — all eight singletons, complete, in the §4 order.
- `src/net/net_channels.gd`, `src/assembly/runtime/assembly_stats.gd`.
- `project.godot` — autoloads, physics/display settings, all 33 input actions.
- `data/parts/registry_manifest.tres` — valid and **empty**; no parts exist yet.

### Tests
`tests/test_case.gd` (assertion base, dependency-free) and
`tests/source_scanner.gd` (source/scene text scanning with comment and
string-literal stripping, so a rule never fires on its own name in prose).

Conformance tests present: `test_autoload_set`, `test_input_actions`,
`test_project_settings`, `test_no_polling`, `test_no_global_rng`,
`test_no_forbidden_patterns`, `test_no_runtime_csg`, `test_visual_decoupling`,
`test_scripts_parse`.

Unit/integration: `test_lattice_math`, `test_orientation_table`,
`test_part_definition_bake`, `test_collider_profile_serialisation`,
`test_tick_ordering`.

---

## 5. Known gaps — deliberate, not oversights

- **No parts exist.** `registry_manifest.tres` is empty. `PartRegistry` handles
  that correctly (registry of size 0, `manifest_hash` over an empty list). The
  next real milestone is authoring one Core Module and one Structural Component
  end-to-end, because that is what forces `tools/validate_part_registry.gd` into
  existence.
- **No scenes, and no main scene set in `project.godot`.** `godot --path .` runs
  and does nothing. `test_no_runtime_csg` and `test_visual_decoupling` parse an
  empty scene set today and pass vacuously — they are written to bite the moment
  a `.tscn` lands, and their check counts show the scan ran.
- **`test_degradation_table` and `test_constant_ownership` from CLAUDE.md §9.2
  are not written.** The first needs `DegradationTable` (doc 08) to exist; the
  second needs a constant-ownership index that would be guesswork before there
  are more constants to own. Both should land with the systems they guard.
- **`cam_orbit` and `cam_pan` have keyboard/mouse bindings only.** Doc 11 §7.1
  assigns them the gamepad right stick and D-pad, which are two-axis inputs that
  a single Godot action cannot express. Resolving this properly means either
  splitting them into per-axis analogue actions — a change to the frozen §7.2
  action list, so a documentation change first — or handling stick camera input
  through `InputMethod`. Flagged rather than guessed at.
- **Seven actions had no binding in doc 11 §7.1** (`veh_boost`,
  `effector_cycle_group`, `cam_toggle_view`, `catalogue_prev_class`, `hud_ping`,
  `hud_scoreboard`, `net_diagnostics_toggle`). They are bound sensibly in
  `project.godot`; if doc 11 §7.1 is ever completed, reconcile against it.

---

## 6. Suggested next steps, in dependency order

1. **`LatticeOccupancy` + `FootprintSolver`** (doc 02 §3, §5). Both are fully
   specified, both are pure logic, and both are directly unit-testable against
   the `OrientationTable` that already passes.
2. **First two part definitions and `tools/validate_part_registry.gd`.** The
   validator's rules are fully written out in doc 01 §6.2 and §5.1; the
   `ColliderProfile` coverage-band check (82–118%) already has the volume maths
   it needs on `ColliderPrimitiveDef.volume_m3()` and
   `PartDefinition.occupancy_volume_m3()`.
3. **`PlacementValidator`** (doc 02) — everything in the garage, the
   auto-assembler, and server-side blueprint validation routes through it, so it
   is the highest-leverage next system.
4. **`ChassisGraph`** (doc 04), which `test_no_polling` is already configured to
   police.

---

## 7. Conventions this session established

- Test methods are `test_*` with no arguments; the runner sorts them, so no test
  may depend on another's ordering. Assertions record rather than halt, so one
  broken invariant does not hide the next twelve.
- Conformance-test failure messages name the file, the line, the invariant, and
  the correct alternative. A message that only says "forbidden" gets the rule
  worked around instead of followed.
- Arch tests that currently scan an empty set still call `check_true(true, ...)`
  with a description, so a vacuous pass is visible in the check count rather than
  indistinguishable from a real one.
