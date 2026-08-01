# HANDOFF

Working notes for the next session. **Not** an architecture document — `CLAUDE.md`
and the thirteen documents in `/docs/` remain the only authority. This file
records what exists, what it cost to learn, and what to do next.

Last updated: session 2 (first two part definitions, registry validator, polarity fix).

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

**19 files, 1673 checks, 0 failures.** Verified to actually fail on planted
faults, not merely to pass:

| Planted fault | Caught by |
|---|---|
| global `randf()` in `src/` | `test_no_global_rng` |
| `_process` in `src/assembly/graph/` | `test_no_polling` (both tests) |
| `find_child()` in `src/` | `test_no_forbidden_patterns` |
| transposed rotation matrix | `test_orientation_table` (32 failures) |
| dropped origin offset in `resolve` | `test_footprint_solver` (30 failures) |
| `out` buffer not shrunk on reuse | `test_footprint_solver` |
| definition on disk absent from the manifest | `validate_part_registry` R02 |
| duplicated manifest key | `validate_part_registry` R02 |
| manifest naming a definition that does not exist | `validate_part_registry` R02 |
| collider shrunk to 60% coverage | `validate_part_registry` R08 |
| resistance above the 0.85 ceiling | `validate_part_registry` R07 |
| manifest order swapped | `test_part_registry_data` (5 failures) |
| four attachment nodes dropped from a `.tres` | `test_part_registry_data` (2 failures) |

Each reports file, line, and the invariant, and the runner exits 1.

Note the last two rows. **The validator does not catch a dropped attachment
node and cannot** — §14 has no rule about how many nodes a part should have, so
there is nothing for it to compare against. Only the integration test, which
knows a 4×1×4 solid box exposes 48 cell faces, sees it. That is the division of
labour to preserve when adding parts: the validator checks what the schema can
decide, the integration test checks what the data is supposed to say.

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

6a. **Packed arrays pass by reference as function arguments but copy on
   assignment.** `func f(out: PackedVector3Array)` mutating `out` *is* visible
   to the caller, so doc 02 §5's zero-allocation out-parameter design works as
   written. But `var mine := shared` or `obj.field = shared` takes a copy. The
   two behaviours look identical at the call site and differ completely, so be
   explicit about which one a piece of code relies on.

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

11. **`ResourceSaver.save` neither writes a uid nor sets `resource_path` on the
    object it wrote.** Two consequences, both silent. A re-save *strips* the uid
    an existing file already carried, breaking every `uid://` reference to it —
    capture `ResourceLoader.get_resource_uid(path)` before the write and put it
    back with `ResourceSaver.set_uid(path, uid)` after, minting a
    `ResourceUID.create_id()` only when there was none. And a sub-resource
    assigned from memory rather than reloaded from its path serialises as an
    *inlined copy*: `def.collider_profile = collider` wrote the whole profile
    into the definition and left the `.collider.tres` file dead, which would
    have let a definition's collider diverge from the file doc 13 §7 hashes for
    the balance-review gate. `tools/author_first_parts.gd` reloads each side-car
    through `CACHE_MODE_REPLACE` for exactly this reason.

12. **`PackedFloat32Array` round-trips 0.85 as 0.85000002.** An inclusive
    ceiling tested with a bare `>` rejects the exact value the balance tables
    are written to. `resistance` is float32; compare with `is_equal_approx`.
    `tests/unit/test_part_registry_validator.gd` caught this on the first run.

---

## 3. Architecture changed once, in session 1

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

## 3a. Code corrected against the documents, in session 2

No document changed. One piece of session-1 code contradicted one, and was
fixed to match rather than the other way round.

**`AttachmentNodeDef.accepts_polarity` had `DECK` mating only with `DECK`.**
`docs/GRID_SNAPPING_LOGIC.md` §7.3 gives the matrix explicitly: `DECK` accepts
`FACE_MALE` and `FACE_NEUTRAL`, refuses `FACE_FEMALE`, and refuses another
`DECK` — two decks facing each other describe no physical joint. `FACE_MALE`
and `FACE_NEUTRAL` accept `DECK` in return, which the old code also omitted.

This surfaced while authoring the Core Module's upward face. Under the old rule
that face would have refused every part in the game, and the failure would have
looked like a data problem rather than a code one. The matrix is now a flat
`POLARITY_MATRIX` lookup on `AttachmentNodeDef`, asserted cell by cell against
the document by `tests/unit/test_attachment_polarity.gd`, which also asserts the
symmetry §7.3 claims the matrix has by construction.

When `PlacementValidator` lands, its `polarity_compatible` must call this one.
§7.3 sketches a second copy of the table on the validator; a second copy is how
the first one went wrong.

**`CLAUDE.md` §2 gained `.build/`.** Doc 01 §14 and doc 13 §8 both require tool
output there, and §2 forbade top-level directories it did not list. It is
declared as generated output and gitignored.

---

## 4. What exists now

### Environment and CI
| Path | Purpose |
|---|---|
| `tools/ci/bootstrap_env.sh` | Provisions Godot into `.tooling/` |
| `tools/ci/godot.sh` | Engine wrapper with redirected XDG paths |
| `tools/ci/run_all_checks.sh` | Reimport + suite; the command to run |
| `tools/ci/run_all_checks.gd` | Discovery-based headless test runner |
| `.gitignore` | Ignores `.tooling/`, `.godot/`, `.build/`, exports |

### Source
- `src/core/data/` — `SyndicateConstants`, `PartEnums`, `CollisionLayers`,
  `RenderLayers`, `PartFlags`, `PartDefinition`, `PartManifest`,
  `PartInstanceState`, `AttachmentNodeDef`, `ColliderPrimitiveDef`,
  `ColliderProfile`, `FusionProfile`, `ProxyPrimitiveDef`, `PartVisualProfile`,
  and the six class profiles.
- `src/core/math/` — `LatticeMath`, `OrientationTable` (full 24-element group).
- `src/assembly/lattice/` — `LatticeOccupancy` (dense byte-per-cell overlap
  authority), `FootprintSolver`, `ResolvedNode`.
- `src/autoload/` — all eight singletons, complete, in the §4 order.
- `src/net/net_channels.gd`, `src/assembly/runtime/assembly_stats.gd`.
- `project.godot` — autoloads, physics/display settings, all 33 input actions.

### Data
| Path | Contents |
|---|---|
| `data/parts/registry_manifest.tres` | Two keys, in this order. **Append only.** |
| `data/parts/core/core.command.compact.t2.*` | Core Module: definition + visual/collider/fusion |
| `data/parts/str/str.panel.medium.t2.*` | Structural Component, same four files |

Both are straight from doc 01 §10.1, §10.2 and §11. Two values §10 does not
publish were chosen and are commented where they are set:
`load_capacity_kg = 3600` on the Core Module (it carries structurally what
§10.1's `mass_tolerance_kg` says it tolerates dynamically), and the Tier-2
`build_cost` baselines, 900 and 60, which §12 will scale every other tier of
those two variants from.

Both ship at `STAGE_PROXY` with **empty** `proxy_primitives`, so doc 13 §2.1
mirrors the `ColliderProfile` and the greybox renders exactly what it collides
as. Each is one solid box under a single `BOX` primitive at 100% of the §6.2
coverage band, with one attachment node per exposed cell face — 94 on the Core
Module, 48 on the panel.

Per-cell node coverage is not padding. Doc 02 §6.4 disambiguates between
"several nodes sharing the required face", and doc 06 enumerates mount cells as
"every free cell adjacent to an occupied cell with an upward-facing node". A
part with one node per face would only ever snap at its own centre.

`tools/author_first_parts.gd` derives all of it — cells, nodes, collider
extents, centre of mass — from the documented cell dimensions. It is committed,
idempotent, and is the worked example to copy for the next part. Hand-typing 94
node records is a transcription error waiting to happen.

### Tools
| Path | Purpose |
|---|---|
| `tools/part_registry_validator.gd` | `PartRegistryValidator`: the 16 rules of doc 01 §14 |
| `tools/validate_part_registry.gd` | CI entry point; writes `.build/part_registry_report.md` |
| `tools/author_first_parts.gd` | Derives and writes the two parts and the manifest append |

The rules live in the `RefCounted` class and the `SceneTree` script is a thin
shell, because CLAUDE.md §11 fixes the `--script` path and a script cannot be
both. Findings carry their rule number (`[R08] str.panel.medium.t2: ...`), which
is what the unit tests assert on.

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
`test_lattice_occupancy`, `test_footprint_solver`, `test_attachment_polarity`,
`test_part_registry_validator`, `test_tick_ordering`,
`test_part_registry_data`.

The last two are a deliberate pair. `test_part_registry_validator` plants one
fault at a time in a synthetic definition and asserts the rule that should catch
it does — a validator asserted only against valid data passes just as happily
with its checks commented out. `test_part_registry_data` then runs the real
validator over the real `data/parts/` and re-asserts every published number from
§10 after the round trip through `.tres`.

---

## 5. Known gaps — deliberate, not oversights

- **Rule 2's reorder half is not implemented, and cannot be from data alone.**
  §14 rule 2 is "`part_key` is absent from `registry_manifest.tres`, or the
  manifest order changed". Absence, duplication, a manifest entry with no file,
  and a file with no manifest entry are all checked and all verified to fail.
  *Order changed* is only meaningful against a prior, and the validator has
  none. Nothing has shipped yet, so there is no history to protect and the gap
  costs nothing today. Before the first release it needs a recorded baseline of
  shipped ids — the same shape as the `ColliderBaseline` doc 13 §7 describes —
  and the check becomes "the baseline is a prefix of the manifest". Faking it
  now, against a baseline the validator itself writes, would assert nothing.
- **No motive parts, so `AXLE` polarity has no user yet — and there is a
  decision waiting there.** Rule 11 makes a cell face carry exactly one node, so
  a face is *either* `FACE_NEUTRAL` *or* `AXLE`, never both, and `AXLE` mates
  only with `AXLE`. Every face on both shipped parts is neutral (bar the Core
  Module's deck). So either Motive Assemblies mate through `FACE_MALE`/
  `FACE_NEUTRAL` and `AXLE` is reserved for dedicated axle-mount structural
  parts, or chassis parts must give up specific faces to `AXLE`. Doc 01 §4 says
  only "motive assemblies only". Flagged rather than guessed at; resolve it when
  the first `mot.*` part is authored, and record the decision in doc 01 §4.
- **Rule 13 (tier scaling) has never fired.** It needs two tiers of one
  `class.family.variant` and there is one tier of two variants. The check is
  written and grouped correctly; it is simply vacuous. Worth knowing before
  trusting it: several §10 rows would **fail** it as documented —
  `str.bumper.impact` t2→t4 is −22% on integrity and −26% on armour, and
  `str.wedge.forward` t2→t3 is +8.2% on integrity. Authoring those parts will
  force a choice between `balance_exception_note` on each and amending §12.
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

1. ~~`LatticeOccupancy` + `FootprintSolver`~~ — **done in session 1.**
   `LatticeOccupancy` stores per-slot cell lists in a flat array indexed by slot
   rather than the dictionary sketched in doc 02 §3. The public interface is
   unchanged; a flat array drops the hashing and makes `slots_in_use()`
   ascending by construction, which I-9 needs. Not an architecture change, so
   doc 02 was left alone.
2. ~~First two part definitions and `tools/validate_part_registry.gd`~~ —
   **done in session 2.**
3. **`PlacementValidator`** (doc 02 §7) — **start here.** Everything in the
   garage, the auto-assembler, and server-side blueprint validation routes
   through it, so it is the highest-leverage next system, and it now has real
   parts to validate against instead of fixtures. The pieces it composes exist:
   `FootprintSolver.all_in_bounds` and `LatticeOccupancy.is_footprint_free` are
   deliberately separate because the two rejections carry different `Reject`
   codes, and `ResolvedNode.opposes` holds the mating rule and now reads the
   corrected polarity matrix. Two cautions: §7.3 sketches a second copy of
   `_POLARITY_MATRIX` on the validator — call `AttachmentNodeDef` instead — and
   §7.4's budget checks need `mount_weight` summed against
   `core_profile.mount_budget`, which the Core Module deliberately sets to 0 for
   itself.
4. **`ChassisGraph`** (doc 04), which `test_no_polling` is already configured to
   police.
5. **A second tier of one of the two shipped variants**, whenever balance work
   starts. It is the cheapest way to make rule 13 non-vacuous, and it will
   immediately expose whether §12's scaling model survives contact with §10's
   own tables (see §5 above — twice, it does not).

---

## 7. Conventions — follow these when adding to the suite

Established in session 1:

- Test methods are `test_*` with no arguments; the runner sorts them, so no test
  may depend on another's ordering. Assertions record rather than halt, so one
  broken invariant does not hide the next twelve.
- Conformance-test failure messages name the file, the line, the invariant, and
  the correct alternative. A message that only says "forbidden" gets the rule
  worked around instead of followed.
- Arch tests that currently scan an empty set still call `check_true(true, ...)`
  with a description, so a vacuous pass is visible in the check count rather than
  indistinguishable from a real one.

Added in session 2:

- **A validator is tested by breaking things, one at a time.** Every rule in
  `test_part_registry_validator` starts from a definition that passes cleanly and
  plants exactly one fault. The fixture is synthetic rather than the shipped
  panel: a fixture that loads real data fails for reasons a fault test cannot
  distinguish from the fault it planted.
- **Validator findings carry their rule number.** `[R08] key: message`, and the
  message names the invariant and the number that broke it — "collider covers
  60.0% of the 0.2500 m³ occupancy; §6.2 requires 82%–118%", not "invalid
  collider".
- **Generated data files are derived, not typed.** Committed alongside a
  committed generator, so the derivation is reviewable next to the data.
- **The report carries no timestamp**, so two runs over the same data are
  byte-identical and it diffs as cleanly as the data it describes.
