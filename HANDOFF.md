# HANDOFF

Working notes for the next session. **Not** an architecture document — `CLAUDE.md`
and the thirteen documents in `/docs/` remain the only authority. This file
records what exists, what it cost to learn, and what to do next.

Last updated: session 3 (the placement chain: `PlacementValidator`, `BuildContext`,
`ChassisGraph`, `MateSelector`).

---

## 1. Getting a working environment

Nothing is installed by default. One command provisions everything:

```bash
tools/ci/bootstrap_env.sh          # idempotent; ~75 MB download, ~30 s
```

That puts Godot **4.7.1-stable** in `.tooling/`. `.tooling/` is gitignored in
full and holds the engine binary, the engine's `XDG_*` data, and test output, so
nothing the toolchain writes can land in a commit.

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

**23 files, 2128 checks, 0 failures.**

---

## 2. How this repository knows its tests work

Every session so far has verified the suite by **planting faults one at a time
and confirming something fails**. A test asserted only against correct code
passes just as happily with its subject commented out. The table below is the
accumulated record; rows from sessions 1–2 were re-confirmed in session 3.

| Planted fault | Caught by |
|---|---|
| global `randf()` in `src/` | `test_no_global_rng` |
| `_process` in `src/assembly/graph/` | `test_no_polling` |
| `find_child()` in `src/` | `test_no_forbidden_patterns` |
| transposed rotation matrix | `test_orientation_table` |
| dropped origin offset in `resolve` | `test_footprint_solver` |
| `out` buffer not shrunk on reuse | `test_footprint_solver` |
| definition on disk absent from the manifest | `validate_part_registry` R02 |
| duplicated manifest key | `validate_part_registry` R02 |
| collider shrunk to 60% coverage | `validate_part_registry` R08 |
| resistance above the 0.85 ceiling | `validate_part_registry` R07 |
| manifest order swapped | `test_part_registry_data` |
| four attachment nodes dropped from a `.tres` | `test_part_registry_data` |
| **occupancy check never reports a cell occupied** | `test_placement_validator` |
| **every polarity accepted** | `test_placement_validator` |
| **interpenetration margin flipped positive** | `test_placement_validator` |
| **structural load ignores the parent's subtree** | `test_placement_validator` |
| **motive clearance probes one cell, not the envelope** | `test_placement_validator` |
| **effector arc never counts a blocked sample** | `test_placement_validator` |
| **bounds check disabled** | `test_placement_validator` |
| **duplicate Core Module allowed** | `test_placement_validator` |
| **hard limits ignored (load always soft)** | `test_placement_validator` |
| **commit forgets `FLAG_STRAINED`** | `test_placement_validator` |
| **stale parent survives a rejection** | `test_placement_validator` |
| **Core Module charged against its own mount budget** | `test_placement_validator` |
| **proxy transform written before its shapes** | `test_placement_validator` |
| **`allocate_slot` stops allocating lowest-first** | `test_placement_validator` (78 failures) |
| **removal never finds an alternate parent** | `test_placement_validator` |
| **mass propagation stops at the immediate parent** | `test_chassis_graph`, `test_placement_validator` |
| **orphaning children forgets to shed their mass** | `test_chassis_graph` |
| **connectivity walks the tree, not support edges** | `test_chassis_graph` (10 failures) |
| **duplicate support edges kept** | `test_chassis_graph` |
| **depth tie-break dropped** | `test_mate_selector` |
| **weaker-joint preference inverted** | `test_mate_selector` |
| **joint rated by the stronger node** | `test_mate_selector` |
| **joint bears load when either end does** | `test_mate_selector` |
| **ledger's remove forgets the mount weight** | `test_build_budget_ledger` |
| **node adjacency tested in one direction only** | *nothing — see §5* |

Two of these were found by the tests during this session, not merely guarded
afterwards. See §3.

---

## 3. Engine facts that cost time — read before writing code

All verified against 4.7.1 in this repo, not recalled.

1. **`--import` does not catch parse errors.** It registers `class_name` globals
   by scanning source without compiling it, so a broken script imports cleanly
   and only explodes when something first loads it. `tests/arch/test_scripts_parse.gd`
   exists solely to close this hole.

2. **`--script` with a `SceneTree` subclass must not do its work in `_init()`.**
   `_init` runs before the main loop is initialised and a `quit()` issued there
   is discarded; the process then idles forever with its output still buffered.
   Do the work on the first `_process` frame instead.

3. **Autoloads are not compile-time globals in a `--script` target.** A script
   passed to `--script` is compiled *before* autoloads register, so naming
   `PartRegistry` or `EventBus` in it — or in anything it depends on — fails with
   "Identifier not found", and the failure cascades into every dependent class.
   Test files are fine, because the runner loads them after the autoloads are in
   the tree. **A throwaway probe script therefore cannot touch autoloaded
   singletons or anything that references one.** Write the probe as a temporary
   `tests/unit/test_zz_probe.gd` and run the normal suite instead; that path has
   the autoloads and costs nothing to set up.

4. **`Basis.get_column()`, `set_column()`, and `get_row()` were removed in 4.7.**
   `Basis.x`, `.y`, `.z` remain and are the **columns**.

5. **`Vector3i` components are int32.** A 64-bit sentinel assigned into one wraps
   silently. Use `±2147483647`.

6. **`const X: PackedStringArray = PackedStringArray([...])` is not a constant
   expression.** Use `const X: Array[String] = [...]`.

7. **A typed-array `const` does not give a `for` loop's variable a static type,
   and neither does `range()` or an array literal.** With `untyped_declaration=2`
   (error, as configured) every one of these is a build failure:
   `for x in [1, 2]`, `for x in range(1, 5)`, `for x in some_untyped_array`.
   Write `for x: int in ...`. Iterating an `int` (`for i in 12`) or a typed array
   is fine. This cost two round trips in session 3 alone; it is the single most
   common way a new file fails to parse here.

8. **Packed arrays pass by reference as function arguments but copy on
   assignment.** `func f(out: PackedVector3Array)` mutating `out` *is* visible to
   the caller, so doc 02 §5's zero-allocation out-parameter design works as
   written. But `var mine := shared` or `obj.field = shared` takes a copy. This
   is why `ChassisGraph` writes `children[p] = kids` back after every
   `push_back` — dropping that line loses the edit silently.

9. **`Callable.bind()` does not make two Callables compare unequal.** Use a
   distinct receiver object per handler.

10. **`ProjectSettings.get_property_list()` reports every built-in `ui_*` action**
    whether or not the project declares it. Parse the `[input]` section of
    `project.godot` to see what the project actually declares.

11. **Godot rewrites `project.godot` and drops any setting equal to the engine
    default.** `tests/arch/test_project_settings.gd` asserts *effective* values
    through `ProjectSettings`, never by grepping the text. Do not "restore" those
    lines — they will vanish again on the next save.

12. **`ResourceSaver.save` neither writes a uid nor sets `resource_path` on the
    object it wrote.** A re-save *strips* the uid an existing file carried;
    capture `ResourceLoader.get_resource_uid(path)` before the write and restore
    it after. And a sub-resource assigned from memory rather than reloaded from
    its path serialises as an *inlined copy*.

13. **`PackedFloat32Array` round-trips 0.85 as 0.85000002.** `resistance` is
    float32; compare with `is_equal_approx`.

14. **`PhysicsServer3D` works fully under `--headless`,** including
    `space_create`, static bodies, and `space_get_direct_state(...).intersect_shape`.
    A body is visible to a query in the **same frame** it is added, with no
    physics step in between — which is what makes doc 02 §7.7 usable during a
    bulk blueprint load, where many parts commit before any step occurs.

15. **A physics body must be given its transform *after* its shapes are added.**
    `body_set_state(BODY_STATE_TRANSFORM)` on a shapeless body leaves it with the
    broadphase entry it had while empty, and every subsequent query against it
    returns **nothing**. This is the worst possible failure shape for §7.7: a
    missing proxy and a legal placement are indistinguishable, so the
    interpenetration check would have silently never fired for the life of the
    project. `tests/integration/test_placement_validator.gd` caught it on first
    run because the test asserts both directions — a case that must reject and a
    neighbouring case that must not. **Assert the reject, not just the accept.**

16. **A `Shape3D` owns its server RID and frees it on destruction.** Caching the
    bare RID and letting the Resource fall out of scope leaves every entry
    dangling, and a query against a freed shape reports no hits — which again
    reads exactly like a legal placement. `BuildShapeCache` retains the
    `Shape3D` objects, not just their RIDs.

17. **Physics server RIDs are not reference counted.** A `BuildContext` dropped
    without `dispose()` leaks a space that keeps stepping for the life of the
    process. Tests collect their contexts and dispose them in `after_all`.

---

## 4. Architecture changes, cumulatively

Three amendments in three sessions. Each is recorded in the owning document.

**Session 1 — `docs/PART_DATA_SCHEMA.md` §6.2.** `PrimitiveDef` was declared as
an inner class of `ColliderProfile`. Godot 4 cannot serialise an inner-class
`Resource` into a `.tres`: it writes the element script as an empty
`[sub_resource type="GDScript"]` and on load every element fails typed-array
validation and is dropped **silently**. Since I-1 makes `ColliderProfile` the
only source of Assembly collision geometry, this would have shipped every part
with an empty collider set and no hit registration. The type is now top-level
`ColliderPrimitiveDef`, and `tests/unit/test_collider_profile_serialisation.gd`
round-trips a populated profile on every run.

**Session 2 — no document changed; code was corrected to match one.**
`AttachmentNodeDef.accepts_polarity` had `DECK` mating only with `DECK`, where
doc 02 §7.3 gives the matrix explicitly. The matrix is now a flat
`POLARITY_MATRIX` on `AttachmentNodeDef`, asserted cell by cell against the
document. `CLAUDE.md` §2 also gained `.build/`.

**Session 3 — `docs/DEPENDENCY_TREE_GRAPH.md` §2.1 and §3.1.** Three additions,
all filling gaps the document left rather than changing a decision it made:

- §2.1 gained `mass_kg`. §3.1 calls `m_mass_of(slot)` to compute the delta it
  propagates, but §2.1 declared no field to hold it — the graph could not compute
  a value its own attach path depends on. `attach` therefore takes the part's
  mass as a final argument. Storing it on the graph rather than resolving through
  `PartRegistry` also keeps `ChassisGraph` constructible in a unit test with no
  autoloads, which is how `test_chassis_graph.gd` runs.
- §3.1 now states that a `MateRecord`'s `joint_strength_n` is the **weaker** of
  the two nodes. A joint fails at whichever face yields first; rating it by the
  stronger end would let a part advertise a strength its partner cannot honour,
  and §3.2 would then pick that joint as primary parent on the strength of a
  number describing one side of it.
- §3.1 now states that `_add_edge` is idempotent per pair. A wide part meeting a
  wide part mates across several faces; that is one physical joint, and an edge
  per face would double-count it in every strain and connectivity sum.

`CLAUDE.md` §2's file listing was extended with the eight new source files.

---

## 5. Two deliberate readings of doc 02, and one redundancy

**Presentation is not on `BuildContext`.** §9.1 sketches `ctx.spawn_visual(slot)`
and `ctx.spawn_colliders(slot)`, but its very next sentence is that
`EventBus.part_attached` is what wakes the mass solver, the fusion rebuild, and
the stat panel, and that nothing polls. Meshes are therefore driven by the event
(I-4), and no presentation hook exists on the context to be left unimplemented on
the dedicated server. The **build proxies** are the exception and are created
there: they are physics, and they are what §7.7 queries.

**`_check_collider_interpenetration` is skipped without a physics space.**
`BuildContext.headless()` has none, and server-side blueprint re-validation uses
it. §12 invariant 1 permits this precisely because the query may only *reject*,
never *accept* — skipping it cannot admit a placement the integer checks refused,
and it avoids a physics space per connecting player.
`test_headless_context_skips_the_physics_query` pins both halves.

**`ResolvedNode.is_face_paired` is over-specified, knowingly.** It tests
adjacency in both directions *and* that the faces oppose, and any two of those
three conditions imply the third. Fault injection cannot make it fail by removing
one — that is the only entry in §2's table with no catcher, and it is not a test
gap. `test_two_way_adjacency_already_implies_opposing_faces` sweeps all
thirty-six face pairings to prove the redundancy is consistent. The rule is
written out because §7.3 writes it out and a reader should not have to derive it.

---

## 6. What exists now

### Environment and CI
| Path | Purpose |
|---|---|
| `tools/ci/bootstrap_env.sh` | Provisions Godot into `.tooling/` |
| `tools/ci/godot.sh` | Engine wrapper with redirected XDG paths |
| `tools/ci/run_all_checks.sh` | Reimport + suite; the command to run |
| `tools/ci/run_all_checks.gd` | Discovery-based headless test runner |

### Source
- `src/core/data/` — `SyndicateConstants`, `PartEnums`, `CollisionLayers`,
  `RenderLayers`, `PartFlags`, `PartDefinition`, `PartManifest`,
  `PartInstanceState`, `AttachmentNodeDef`, `ColliderPrimitiveDef`,
  `ColliderProfile`, `FusionProfile`, `ProxyPrimitiveDef`, `PartVisualProfile`,
  and the six class profiles.
- `src/core/math/` — `LatticeMath`, `OrientationTable` (full 24-element group).
- `src/assembly/lattice/` — `LatticeOccupancy`, `FootprintSolver`,
  `ResolvedNode`, and **new in session 3**: `PlacementCandidate`,
  `BuildBudgetLedger`, `BuildShapeCache`, `BuildContext`, `PlacementValidator`.
- `src/assembly/graph/` — **new in session 3**: `MateRecord`, `MateSelector`,
  `ChassisGraph`.
- `src/autoload/` — all eight singletons, complete, in the §4 order.
- `project.godot` — autoloads, physics/display settings, all 33 input actions.

### Data
| Path | Contents |
|---|---|
| `data/parts/registry_manifest.tres` | Two keys, in this order. **Append only.** |
| `data/parts/core/core.command.compact.t2.*` | Core Module: 60 cells (4x3x5), 94 nodes (74 neutral, 20 deck), mass 380 kg, load capacity 3600 kg, mount budget 28, power capacity 240 |
| `data/parts/str/str.panel.medium.t2.*` | Structural Component: 16 cells (4x1x4), 48 neutral nodes, mass 34 kg, load capacity 520 kg, mount weight 1 |

`tools/author_first_parts.gd` derives all of it from the documented cell
dimensions. It is committed, idempotent, and is the worked example to copy for
the next part.

### Tests
`tests/test_case.gd` (assertion base) and `tests/source_scanner.gd` (source/scene
text scanning with comment and string-literal stripping).

Arch: `test_autoload_set`, `test_input_actions`, `test_project_settings`,
`test_no_polling`, `test_no_global_rng`, `test_no_forbidden_patterns`,
`test_no_runtime_csg`, `test_visual_decoupling`, `test_scripts_parse`.

Unit: `test_lattice_math`, `test_orientation_table`, `test_part_definition_bake`,
`test_collider_profile_serialisation`, `test_lattice_occupancy`,
`test_footprint_solver`, `test_attachment_polarity`, `test_part_registry_validator`,
`test_chassis_graph`, `test_mate_selector`, `test_build_budget_ledger`.

Integration: `test_tick_ordering`, `test_part_registry_data`,
`test_placement_validator`.

---

## 7. Known gaps — deliberate, not oversights

Carried forward and still true:

- **Rule 2's reorder half is not implemented, and cannot be from data alone.**
  Absence, duplication, and both orphan directions are checked. *Order changed*
  needs a recorded baseline of shipped ids — the shape doc 13 §7 describes for
  `ColliderBaseline` — and the check becomes "the baseline is a prefix of the
  manifest". Nothing has shipped, so there is no history to protect yet.
- **Rule 13 (tier scaling) has never fired.** It needs two tiers of one
  `class.family.variant`. Several §10 rows would **fail** it as documented:
  `str.bumper.impact` t2→t4 is −22% integrity and −26% armour;
  `str.wedge.forward` t2→t3 is +8.2% integrity. Authoring those forces a choice
  between `balance_exception_note` on each and amending §12.
- **`AXLE` polarity still has no user.** Rule 11 makes a cell face carry exactly
  one node, so a face is *either* `FACE_NEUTRAL` *or* `AXLE`. Resolve when the
  first `mot.*` part is authored and record the decision in doc 01 §4.
- **No scenes, and no main scene set.** `test_no_runtime_csg` and
  `test_visual_decoupling` scan an empty set and say so in their check counts.
- **`test_degradation_table` and `test_constant_ownership` are not written.**
  Both should land with the systems they guard.
- **`cam_orbit`/`cam_pan` have keyboard/mouse bindings only**, and **seven
  actions had no binding in doc 11 §7.1**. Reconcile if §7.1 is completed.

New in session 3:

- **§7.6's muzzle expression is half a cell off the §2.1 cell-centre
  convention.** §7.6 computes `Vector3(cand.origin_cell) + (basis * muzzle) / U`,
  which is the cell's **corner**; `LatticeMath.cell_to_local` puts a cell's centre
  at `cell + 0.5`. The implementation is faithful to §7.6 as written. With a
  typical 0.6 m muzzle offset the bias can shift which cell the DDA starts in.
  Flagged rather than silently "fixed", because correcting it is a change to
  §7.6. Resolve when the first `eff.*` part is authored — which is also when the
  check first has a real user. Both current arc tests use a synthetic effector
  with a 0.125 m offset and pass either way.
- **Strain (doc 04 §4) and the detachment solver (§5) are not written.**
  `edge_strain` is allocated and kept in sync by the edge writers, so adding the
  solver does not have to rewrite them, but nothing writes a non-zero strain yet.
  Strain needs `F_recoil` and `F_impact`, which need combat systems that do not
  exist.
- **`BuildCommand` and the undo stack (doc 02 §9.3) are not written.** Undo is a
  garage-UI concern and §9.3 is self-contained; it wants the garage screen next
  to it. Everything it needs is in place — every commit and removal is already
  expressed in integer lattice terms, so undo can be exact.
- **`PlacementValidator.remove` returns the cascade list rather than acting on
  it.** §9.2 requires a player confirmation showing the affected count; returning
  the list keeps that decision with the caller. The garage must not ignore it.
- **Class limits for Effector and Motive counts are tested through the ledger,
  not through sixteen committed parts.** Committing synthetics would need them in
  the registry, which would change what every other test sees. Revisit when real
  `eff.*`/`mot.*` parts exist.

---

## 8. Suggested next steps, in dependency order

1. ~~`LatticeOccupancy` + `FootprintSolver`~~ — **done, session 1.**
2. ~~First two part definitions and the registry validator~~ — **done, session 2.**
3. ~~`PlacementValidator`, `BuildContext`, `ChassisGraph`, `MateSelector`~~ —
   **done, session 3.** All nine checks of §7, commit and removal per §9.1/§9.2,
   with re-parenting and cascade.
4. **The detachment solver and strain** (doc 04 §4–§6) — **start here.** It is the
   direct continuation: `ChassisGraph` already holds the support edges,
   `edge_strain` arrays, and the reverse-reachability traversal §5.3 is built on,
   and `test_no_polling` is already configured to police the directory. §5.5's
   cascade batching and §6's island conversion are the substance. Note §6.1 —
   debris reuses authored collider primitives, so `BuildShapeCache` is the
   precedent to follow, including the retain-the-`Shape3D` rule from §3.16 above.
5. **A first `mot.*` part.** It resolves the `AXLE` question, gives §7.5 a real
   user instead of a synthetic one, and is needed before any of doc 05 can be
   exercised.
6. **A first `eff.*` part.** Same for §7.6, and it forces the muzzle-offset
   question in §7 above.
7. **A second tier of one shipped variant**, whenever balance work starts. It is
   the cheapest way to make rule 13 non-vacuous.

---

## 9. Conventions — follow these when adding to the suite

From session 1:

- Test methods are `test_*` with no arguments; the runner sorts them, so no test
  may depend on another's ordering. Assertions record rather than halt, so one
  broken invariant does not hide the next twelve.
- Conformance-test failure messages name the file, the line, the invariant, and
  the correct alternative. A message that only says "forbidden" gets the rule
  worked around instead of followed.
- Arch tests that currently scan an empty set still call `check_true(true, ...)`
  with a description, so a vacuous pass is visible in the check count.

From session 2:

- **A validator is tested by breaking things, one at a time.** Every rule starts
  from a case that passes cleanly and plants exactly one fault.
- **Validator findings carry their rule number.** `[R08] key: message`, naming
  the invariant and the number that broke it.
- **Generated data files are derived, not typed**, and committed alongside their
  committed generator.
- **The report carries no timestamp**, so two runs over the same data are
  byte-identical.

From session 3:

- **Assert the rejection, not just the acceptance.** Every check in
  `test_placement_validator` is asserted in both directions: a case it must
  reject and a neighbouring case it must not. The interpenetration bug in §3.15
  was invisible to the accepting half and obvious to the rejecting half.
- **A fixture that cannot distinguish the rule from its fallback is not a test.**
  The depth tie-break test originally put the shallow mate on the lower slot
  index, so key 4 produced the same answer and the test passed with key 3
  deleted. Build fixtures where the key under test and the next key downstream
  disagree.
- **Prefer real parts; use synthetics where the rule needs a class or a limit
  that is not authored yet.** A synthetic candidate is never committed — commit
  resolves through `PartRegistry`, and a fixture in the registry would change
  what every other test in the suite sees. Validating a synthetic against a
  committed real neighbour works, because only the neighbour is looked up.
- **Cycle tests catch what point tests cannot.** Every structure the validator
  touches is maintained incrementally and none fails loudly; 25 commit/remove
  cycles asserting the totals return to baseline make a one-part-per-cycle leak
  obvious.
- **Dispose physics contexts in `after_all`.** See §3.17.
