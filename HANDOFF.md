# HANDOFF

Working notes for the next session. **Not** an architecture document — `CLAUDE.md`
and the thirteen documents in `/docs/` remain the only authority. This file
records what exists, what it cost to learn, and what to do next.

Last updated: session 6 (island conversion to debris: doc 04 §6).

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

**31 files, 2641 checks, 0 failures.**

---

## 2. How this repository knows its tests work

Every session verifies the suite by **planting faults one at a time and
confirming something fails**. A test asserted only against correct code passes
just as happily with its subject commented out. Roughly 170 faults have been
planted across six sessions; the table below is the accumulated record, grouped
by catcher rather than by session, because what matters to the next session is
which test defends which behaviour.

| Test | Faults it has caught |
|---|---|
| `test_no_global_rng` | global `randf()` in `src/` |
| `test_no_polling` | `_process` in `src/assembly/graph/` |
| `test_no_forbidden_patterns` | `find_child()` in `src/` |
| `test_orientation_table` | transposed rotation matrix |
| `test_footprint_solver` | dropped origin offset in `resolve`; `out` buffer not shrunk on reuse |
| `validate_part_registry` | definition on disk absent from the manifest (R02); duplicated manifest key (R02); collider shrunk to 60% coverage (R08); resistance above the 0.85 ceiling (R07) |
| `test_part_registry_data` | manifest order swapped; four attachment nodes dropped from a `.tres` |
| `test_placement_validator` | occupancy never reports a cell occupied; every polarity accepted; interpenetration margin flipped positive; structural load ignores the parent's subtree; motive clearance probes one cell not the envelope; effector arc never counts a blocked sample; bounds check disabled; duplicate Core Module allowed; hard limits ignored; commit forgets `FLAG_STRAINED`; stale parent survives a rejection; Core Module charged against its own mount budget; proxy transform written before its shapes; `allocate_slot` stops allocating lowest-first; removal never finds an alternate parent |
| `test_chassis_graph` | mass propagation stops at the immediate parent; orphaning children forgets to shed their mass; connectivity walks the tree rather than support edges; duplicate support edges kept |
| `test_mate_selector` | depth tie-break dropped; weaker-joint preference inverted; joint rated by the stronger node; joint bears load when either end does; load-bearing key dropped from the ordering; re-parent ignores core reachability |
| `test_build_budget_ledger` | ledger's remove forgets the mount weight |
| `test_chassis_strain` | strain charges the part alone not its subtree; dynamic factor never applied; deposits not summed over the subtree; peak deposit replaced by the latest; candidate set only grows; dwell keyed on the ordered pair; dwell fires without waiting out the window |
| `test_detachment_solver` | connectivity walks the tree in the solver; survivors never re-parented; seeds collected after removal; terminal component cap ignored; islands returned in traversal order |
| `test_detachment_scheduler` | batching removed; pending cleared at the end rather than swapped first; assembly ids resolved in hash order; core loss falls through to the normal solver; unsupported orphan treated as a removed part; failed joint severs without checking other routes; core partitioned with the survivors; mass never announced dirty; island sink never called |
| `test_mass_solver` | parallel-axis term dropped; part tensor never rotated; box tensor uses half extents as full; authored half-extent override ignored; `zero()` returns the identity basis; `diagonal_of` reads a row; island tensor taken about the assembly origin; detached parts still counted; dead graph slots still counted; centre of mass divided by part count; tensor accumulated about the lattice origin; orientation dropped from the part centre of mass; snapshot omits the orientation; mass floor removed; inertia floor removed |
| `test_assembly_runtime` | shapes parented under an intermediate node; shape transform ignores the part pose; shape transform composed in the wrong order; release removes the shape instead of disabling it; visual root parented under the body; decoupling walk does not recurse; adopt leaves the build proxies alive; shape map grows zero-filled |
| `test_mass_recompute` | apply happens after the launch; dirty list admits duplicates; dirty list appended rather than ordered; events for unregistered assemblies queued; dirty list not cleared after capture; consumed batch never cleared; terminated assembly's result applied anyway |
| `test_island_detachment` | `ω × r` term dropped; lever arm not rotated into world space; angular velocity not inherited; island centre of mass not mass-weighted; debris centre of mass left at the Assembly origin; island inertia taken about the Assembly origin; body transform composed the other way round; `FLAG_DETACHED` never set; reaper never scheduled; slot list never recorded; `island_detached` never emitted; mass counted per part rather than summed; total mass zeroed; mass properties never applied; hull shape left enabled after its island leaves; collider not rebased onto the island centre of mass; collider rebased with the wrong sign; minimum-parts guard removed |
| `test_debris_pool` | exhaustion recycles the newest body; released body keeps its geometry; parked body still occupies a layer; acquired body not put back into the solver; acquired body keeps the last deadline; debris masked against debris; released body never rejoins the free list; damping left at the engine default; expiry comparison strictly greater; unscheduled bodies reaped; waking does not reset the sleep accumulator; freeze fires on the first sleeping tick; freeze never fires; freeze mode not static; lifetime measured in seconds not ticks; shape reset does not rewind the cursor; shape reset does not disable; reused node left disabled; reused node keeps the old transform; a new node built on every adopt |
| *nothing* | node adjacency tested in one direction only — see §5 |
| *nothing* | debris body given its transform before its shapes — see §5 |

### 2.1 What the last two sessions learned from a fault that was *not* caught

The question to ask first is never "how do I test this" — it is **"is this code
dead?"** Across sessions 4, 5 and 6 that question deleted a depth sort, a
duplicate batch clear, a redundant island guard and a redundant timer reset, and
it saved a mass floor by finding the one state that reaches it. Reaching for
"document the redundancy" before "delete it" is how untested code accumulates.

The three patterns worth repeating:

- **A fixture that cannot distinguish the rule from its inverse is not a test.**
  Session 5's shape-transform test used a part at orientation 0, under which the
  two composition orders differ by an addition that commutes. Session 6 walked
  into the same trap twice in one file: the velocity-inheritance test first used
  an angular velocity *parallel* to the lever arm, so `ω × r` was zero and the
  term being dropped and the term being correct produced the same number; and
  the world pose first rotated about the Y axis, which is the axis the island
  sits on, so a lever arm that was never rotated into world space looked
  identical to one that was. Build fixtures where the rule under test and the
  thing it would fall back to disagree.
- **Two owners of one invariant is worse than either alone.** Session 6 found
  three: `IslandDetacher` tested its minimum-island size against both its
  argument and its result, `DebrisPool` cleared a body's deadline both on the
  way out and on the way back in, and it cleared the sleep accumulator in a
  place the reaper already covers. The first two collapsed to one owner each and
  are now caught; the third was genuinely dead and was deleted (§5).
- **Some things this harness cannot assert at all.** See §3.28: a query against
  the main world's physics space returns nothing in the suite, so nothing can be
  asserted about a debris body by *hitting* it. That is why the transform-after-
  shapes ordering has no catcher.

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
   the autoloads and costs nothing to set up. In particular
   `godot.sh --check-only --script src/...` reports a bogus "Identifier not
   found: EventBus" for any file that emits a signal — that is not a real error,
   and the suite is the only meaningful check.

4. **`Basis.get_column()`, `set_column()`, and `get_row()` were removed in 4.7.**
   `Basis.x`, `.y`, `.z` remain and are the **columns**, so `b.x.x` is element
   (0,0). For a symmetric tensor the column/row distinction does not matter,
   which is exactly why a fault that reads a row instead of a diagonal survives
   any test that only checks symmetry.

5. **`Vector3i` components are int32.** A 64-bit sentinel assigned into one wraps
   silently. Use `±2147483647`.

6. **`const X: PackedStringArray = PackedStringArray([...])` is not a constant
   expression.** Use `const X: Array[String] = [...]`.

7. **A typed-array `const` does not give a `for` loop's variable a static type,
   and neither does `range()` or an array literal.** With `untyped_declaration=2`
   (error, as configured) every one of these is a build failure:
   `for x in [1, 2]`, `for x in range(1, 5)`, `for x in some_untyped_array`.
   Write `for x: int in ...`. Iterating an `int` (`for i in 12`) or a typed array
   (including every `Packed*Array`) is fine. This is still the single most common
   way a new file fails to parse here.

8. **A `for` loop's iterator name occupies the whole enclosing function scope.**
   `for i in live:` with `var i := edge_index(...)` inside the body is
   "There is already a for loop iterator named i declared in this scope", even
   though the two never coexist logically.

9. **Packed arrays pass by reference as function arguments but copy on
   assignment.** `func f(out: PackedVector3Array)` mutating `out` *is* visible to
   the caller, so doc 02 §5's zero-allocation out-parameter design works as
   written. But `var mine := shared` or `obj.field = shared` takes a copy. This
   is why `ChassisGraph` writes `children[p] = kids` back after every
   `push_back` — dropping that line loses the edit silently.

10. **`Callable.bind()` does not make two Callables compare unequal.** Use a
    distinct receiver object per handler.

11. **A `TestCase` is a `RefCounted` and has no `get_tree()`.** To put a `Node`
    under test into a real tree — which `DetachmentScheduler`,
    `MassRecomputeScheduler`, `AssemblyRuntime` and `DebrisPool` all need — go
    through an autoload: `EventBus.get_tree().root.add_child(node)`. Free it in
    the same file's `after_all`; a leaked node stays connected to the bus and
    resolves the next test's fixture underneath it.

12. **`ProjectSettings.get_property_list()` reports every built-in `ui_*` action**
    whether or not the project declares it. Parse the `[input]` section of
    `project.godot` to see what the project actually declares.

13. **Godot rewrites `project.godot` and drops any setting equal to the engine
    default.** `tests/arch/test_project_settings.gd` asserts *effective* values
    through `ProjectSettings`, never by grepping the text. Do not "restore" those
    lines — they will vanish again on the next save.

14. **`ResourceSaver.save` neither writes a uid nor sets `resource_path` on the
    object it wrote.** A re-save *strips* the uid an existing file carried;
    capture `ResourceLoader.get_resource_uid(path)` before the write and restore
    it after. And a sub-resource assigned from memory rather than reloaded from
    its path serialises as an *inlined copy*.

15. **`PackedFloat32Array` round-trips 0.85 as 0.85000002.** `resistance` is
    float32; compare with `is_equal_approx`.

16. **A float accumulated from `PHYSICS_DT` never lands on a round threshold.**
    27 additions of `1.0/60.0` compare `< 0.45`, so a bare `>=` against a dwell
    constant silently grants one extra tick. Compare against
    `THRESHOLD - EPSILON_LINEAR` — or, where the deadline is set once rather than
    accumulated, store a **tick** and compare integers (§3.27).

17. **`PhysicsServer3D` works fully under `--headless`,** including
    `space_create`, static bodies, and `space_get_direct_state(...).intersect_shape`.
    A body is visible to a query in the **same frame** it is added, with no
    physics step in between — which is what makes doc 02 §7.7 usable during a
    bulk blueprint load, where many parts commit before any step occurs. **This
    holds only for a space you created yourself; see §3.28 for the main world.**

18. **A physics body must be given its transform *after* its shapes are added.**
    `body_set_state(BODY_STATE_TRANSFORM)` on a shapeless body leaves it with the
    broadphase entry it had while empty, and every subsequent query against it
    returns **nothing** — a missing proxy and a legal placement become
    indistinguishable. **Assert the reject, not just the accept.**

19. **A `Shape3D` owns its server RID and frees it on destruction.** Caching the
    bare RID and letting the Resource fall out of scope leaves every entry
    dangling, and a query against a freed shape reports no hits — which again
    reads exactly like a legal placement. `BuildShapeCache` retains the
    `Shape3D` objects, not just their RIDs. The same resource may be registered
    on two bodies at once, which is how a debris body shares the Assembly's
    authored primitives rather than rebuilding them.

20. **Physics server RIDs are not reference counted.** A `BuildContext` dropped
    without `dispose()` leaks a space that keeps stepping for the life of the
    process. Tests collect their contexts and dispose them in `after_all`.

21. **A `CollisionShape3D` registers only as a *direct* child of a
    `CollisionObject3D`.** Nested under an intervening `Node3D` it is silently
    inert: no runtime error, no warning, and `body_get_shape_count` simply does
    not count it. This is why doc 05 §2's `ColliderRoot` had to go — under it
    an Assembly would have carried no collision geometry at all, and presented
    as a damage bug rather than a tree bug. Verified with a probe, not assumed.

22. **A body's shape indices are assignment order, and disabling preserves them
    while removal renumbers.** `CollisionShape3D.disabled = true` keeps the shape
    on the body (`body_get_shape_count` is unchanged) and keeps every later index
    where it was. `PhysicsServer3D.body_is_shape_disabled` does **not** exist in
    4.7; assert through the node or through the shape count. This is why a
    detaching island's colliders are *re-registered* on the debris body rather
    than moved to it (doc 04 §6, amendment 3).

23. **`RigidBody3D.mass = 0.0` is refused** by `ERR_FAIL_COND(p_mass <= 0)`,
    leaving whatever the body already had, and prints an engine error.
    `inertia = Vector3.ZERO` is *accepted* and means "derive it from the collision
    shapes" — which is the exact physics/visual coupling I-1 forbids. Floor both.

24. **`WorkerThreadPool.add_task` + `wait_for_task_completion` work under
    `--headless`**, including within a single `_process` frame, so a scheduler
    that joins on a tick boundary is synchronously testable with no `await`.

25. **The suite never has a physics frame interleaved into it.** The runner does
    all its work inside one `_process` callback, so emitting
    `MatchClock.tick_started` by hand is deterministic and cannot race the
    clock's own emission. `Engine.get_physics_interpolation_fraction()` returns a
    real value headless. The same fact is what makes §3.28 bite.

26. **Two `class_name` scripts may call each other's statics.** `MassSolver` and
    `InertiaSolver` reference each other and neither the parser nor the loader
    objects; a cycle is only a problem for `extends` and for constant folding.

27. **A property with only `get:`/`set:` and no backing variable is legal**, and
    is the right way to stop two objects holding two copies of one id.
    `AssemblyRuntime.assembly_id` reads and writes `body.assembly_id` directly.

28. **The main world's `direct_space_state` answers nothing in this suite.** A
    `StaticBody3D` or `RigidBody3D` added to `get_tree().root` with a live
    `CollisionShape3D` — confirmed present on the server by
    `body_get_shape_count` — is invisible to
    `get_world_3d().direct_space_state.intersect_shape` and to `intersect_ray`
    until a physics step has run, and the runner never lets one run (§3.25). No
    error is printed: the query simply returns an empty result, which reads
    exactly like a correct "nothing there". A space made with
    `PhysicsServer3D.space_create` answers immediately (§3.17), which is why
    `BuildContext`'s interpenetration query works and a debris body cannot be
    asserted by hitting it. `SubViewport.world_3d` is null headless even with
    `own_world_3d = true`, so isolating a node body in its own space is not
    available either.

29. **`RigidBody3D.linear_velocity` and `angular_velocity` round-trip through the
    server with no physics step**, so a test can set a chassis velocity and
    assert exactly what a severed island inherited from it.

30. **A member's initialiser may call a static function; a `const` may not.**
    `var _freeze_after_ticks: int = MatchClockService.ticks_for_seconds(4.0)` is
    legal and runs once per instance. This is the way to keep a duration in
    seconds where the document states it and still compare integers.

---

## 4. Architecture changes, cumulatively

Every amendment is recorded in the owning document, in the change that
introduced it. This section is the index, not the record.

**Session 1 — doc 01 §6.2.** `PrimitiveDef` was an inner class of
`ColliderProfile`. Godot 4 cannot serialise an inner-class `Resource` into a
`.tres`: every element fails typed-array validation on load and is dropped
**silently**, which would have shipped every part with an empty collider set and
no hit registration. The type is now top-level `ColliderPrimitiveDef`.

**Session 2 — no document changed; code was corrected to match one.**
`AttachmentNodeDef.accepts_polarity` contradicted doc 02 §7.3's matrix. The
matrix is now a flat `POLARITY_MATRIX`, asserted cell by cell. `CLAUDE.md` §2
gained `.build/`.

**Session 3 — doc 04 §2.1 and §3.1.** §2.1 gained `mass_kg`, which §3.1 read but
never declared. §3.1 now states that a `MateRecord`'s `joint_strength_n` is the
**weaker** of the two nodes and that `_add_edge` is idempotent per pair.

**Session 4 — doc 01 §3; doc 04 §2.1, §3.3, §4.1, §4.2, §5.3, §5.5, §7.2, §8.2;
doc 07 §8; doc 08 §6.2.** Gap-filling except two corrections: the dwell key is
canonical over the *unordered* pair (as written, one physical joint got two
timers), and the dwell comparison carries an epsilon (see §3.16). `GRAVITY_MPS2`
was written as a literal in four documents and owned by none; it is now
`SyndicateConstants`'. §4.1's recoil deposit now decays, where doc 07 deposited
it without ever clearing it. `CLAUDE.md` §6 gained the terminal debris cap.

**Session 5 — doc 05 §2, §3.3, §4.3; doc 04 §6; doc 08 §5.4; `CLAUDE.md` §5.1.**

- **Doc 05 §2, amendment: `ColliderRoot` is removed.** See §3.21 above. Shape
  indices are now stated to be fixed at spawn, and a part leaving the simulation
  has its shapes *disabled*, because removing one renumbers the map doc 08 §5.4
  reads and turns one destroyed panel into mis-attributed hits across the
  Assembly.
- **Doc 05 §3.3: the accumulation moves to `InertiaSolver`.** `CLAUDE.md` §2
  already named a file for it, and doc 04 §6 needs the identical arithmetic over
  an island's slots. The *sum* stays in `MassSolver`, which already holds each
  part's centre from the pass that produced `C`.
- **Doc 05 §4.3, three amendments.** The scheduler runs on
  `MatchClock.tick_started` rather than a raw `_physics_process` (§11 invariant 4
  wants the start of a tick, and callback order is scene-tree construction
  order); it joins its task on the next tick rather than polling
  `is_task_completed` (fixed one-tick latency beats variable); and the worker
  reads a snapshot captured on the main thread rather than the live `ChassisGraph`
  and state array, which would otherwise race the tick that scheduled it.
- **Doc 04 §6: `island_inertia` takes the state array,** not the whole
  `AssemblyRuntime`. It reads nothing else, and the mass layer stays independent
  of the runtime layer.
- **Doc 08 §5.4, amendment: the shape map grows filled with `INVALID_SLOT`.** The
  document's zero-filling `resize` makes every unassigned index report a hit on
  slot 0 — the Core Module, and the one part whose loss ends the match.
- **`CLAUDE.md` §5.1 gained `MASK_ASSEMBLY_HULL`.** The table carried a mask for
  everything except the chassis body itself.

**Session 6 — doc 04 §6 and §6.2; `CLAUDE.md` §2.** Nine amendments, all recorded
in the document. The six on §6:

1. **`DebrisPool` and `DebrisReaper` are instances, passed in.** §6 called them
   as globals; `CLAUDE.md` §4 freezes the autoload list at eight. The pool is an
   ordinary `Node` and constructs the reaper, because a reaper pointed at no pool
   is not a meaningful object.
2. **The graph writes belong to §5.3.** §6's `graph.alive[slot] = 0` is already
   done by `remove_node` before an island is ever announced. `IslandDetacher`
   asserts it instead of repeating it.
3. **Colliders are re-registered, not moved.** See §3.22. The island's `Shape3D`
   resources are registered on the debris body and the Assembly's copies
   disabled where they stand.
4. **`detach_visual_to` is absent** until doc 13 §9 spawns meshes at all.
5. **Mass properties go through `MassSolver.apply_mass_properties`**, so the
   zero-mass and zero-inertia floors of doc 05 §3.5 have one owner rather than
   two (see §3.23 for what a second owner would eventually get wrong).
6. **`DEBRIS_MIN_PARTS_FOR_BODY` is tested against the parts that resolved,**
   not against the argument. With the minimum at one, testing both would leave
   neither load-bearing.

And three on §6.2: **both deadlines are tick counts** rather than accumulated
seconds (§3.16 again, but here the problem can be removed instead of tolerated —
the tick a body disappears on is replicated); **shape nodes are reused, never
freed** (freeing means removing nodes from a body inside a physics callback, and
`queue_free` would let the recycling path hand out a body still carrying the last
island's geometry); and **the 0.25 s recycle fade is not implemented**, because
it is presentation and debris has no meshes to fade.

`CLAUDE.md` §2 gained the three debris files under `src/assembly/runtime/`.

---

## 5. Deliberate readings, and the redundancies

**Presentation is not on `BuildContext`.** Doc 02 §9.1 sketches
`ctx.spawn_visual(slot)`, but its next sentence is that `EventBus.part_attached`
wakes the mass solver, the fusion rebuild, and the stat panel. Meshes are driven
by the event (I-4). The **build proxies** are the exception and are created
there: they are physics, and they are what §7.7 queries.

**`_check_collider_interpenetration` is skipped without a physics space.**
`BuildContext.headless()` has none, and server-side blueprint re-validation uses
it. Doc 02 §12 invariant 1 permits this precisely because the query may only
*reject*, never *accept*.

**`ResolvedNode.is_face_paired` is over-specified, knowingly.** It tests
adjacency in both directions *and* that the faces oppose, and any two imply the
third. Fault injection cannot make it fail by removing one — one of the two
entries in §2's table with no catcher, and not a test gap.
`test_two_way_adjacency_already_implies_opposing_faces` sweeps all thirty-six
face pairings to prove the redundancy is consistent.

**`IslandDetacher` writes the debris body's transform after its shapes, and
nothing proves it must.** §3.18 recorded the failure that rule exists for, and
§3.28 is why it cannot be re-observed here: the only assertion that would
distinguish the two orderings is a query against the body, and the main world's
space answers nothing in this harness. The ordering costs nothing, matches the
rule everywhere else in the project, and is the second of §2's two uncaught
faults. If a future session gains a physics step inside the suite, the test to
write is *a shape query at the island's centre of mass finds the debris body* —
which would also pin the point of `MASK_ASSEMBLY_HULL` including `LAYER_DEBRIS`.

**`MateSelector.choose_support_parent`'s core-reachability filter is nearly
unreachable, and is kept anyway.** The one arrangement in which it changes an
answer is a component floating entirely, where it returns "no parent" instead of
a parent inside the debris. The alternative is an unguarded function that goes
wrong silently the first time a future caller asks about a disconnected part.

**A depth sort in the solver's `_sever` was deleted rather than documented.**
Fault injection reversed it and nothing failed, because `remove_node` lifts a
slot's children off it before detaching, so removal order cannot matter.
Deleting beat keeping fifteen untested lines with an excuse.

**One of the scheduler's two batch-clears was deleted for the same reason.** The
surviving clear now carries an `assert` in the launch path stating that the batch
must already be empty, so the invariant is named where it is relied on rather
than re-established.

**`DebrisPool` does not clear `asleep_since_tick` when a body is parked**, and
that is the third redundancy deletion. `acquire` sets `sleeping = false`, and the
reaper's next sweep — which always lands before the body could have fallen asleep
again, since debris is spawned in `tick_resolved` and swept at the following
`tick_started` — resets the accumulator itself. The clear on the way out was
therefore unreachable, and `acquire` carries a comment naming what it relies on.
The deadline is a different matter: it is cleared in exactly one place, and
removing it is caught.

**`AssemblyRuntime` spawns colliders but not meshes.** Doc 13 §9's `spawn_visual`
branches on `PartVisualProfile.Stage` into `ProxyMeshCache`, `GreyboxMaterial`,
and `BlockoutMaterial`, none of which exist and all of which doc 13 owns.
Inventing them here would pre-empt the asset pipeline (CLAUDE.md §10 rule 13).
`VisualRoot` exists, is a sibling of the body, is driven by the interpolator, and
is walked by `visual_decoupling_violations()`; meshes land with doc 13, and the
visual half of detachment lands with them.

**The mass floor is nearly dead and is kept for one reachable case.** Doc 04 §7.2
turns every part into debris when the Core Module dies, so a solve can find
nothing live while the body still holds 414 kg; without the floor Godot refuses
the write and the wreck keeps reporting the old mass.

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
  `ResolvedNode`, `PlacementCandidate`, `BuildBudgetLedger`, `BuildShapeCache`,
  `BuildContext`, `PlacementValidator`.
- `src/assembly/graph/` — `MateRecord`, `MateSelector`, `ChassisGraph`,
  `DetachmentSolver`, `DetachmentScheduler`, and **new in session 6**:
  `IslandDetacher`.
- `src/assembly/mass/` — `MassSolver` (with `MassProperties` and `MassInput`),
  `InertiaSolver`, `MassRecomputeScheduler`.
- `src/assembly/runtime/` — `AssemblyStats`, `AssemblyRuntime`, `ChassisBodyRef`,
  `AssemblyInterpolator`, and **new in session 6**: `DebrisBodyRef`,
  `DebrisPool`, `DebrisReaper`.
- `src/autoload/` — all eight singletons, complete, in the §4 order.
- `project.godot` — autoloads, physics/display settings, all 33 input actions.

`ChassisGraph` covers doc 04 §2, §3, and §4 in full. `DetachmentSolver` and
`DetachmentScheduler` cover §5 and §7.2. `IslandDetacher`, `DebrisPool` and
`DebrisReaper` cover §6 and §6.2. `AssemblyRuntime` and the mass classes cover
doc 05 §1–§4 and §10.2.

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
`test_chassis_graph`, `test_mate_selector`, `test_build_budget_ledger`,
`test_chassis_strain`, `test_detachment_solver`, `test_mass_solver`.

Integration: `test_tick_ordering`, `test_part_registry_data`,
`test_placement_validator`, `test_detachment_scheduler`, `test_assembly_runtime`,
`test_mass_recompute`, `test_island_detachment`, `test_debris_pool`.

---

## 7. Known gaps — deliberate, not oversights

### Data and the registry
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
- **Class limits for Effector and Motive counts are tested through the ledger,
  not through sixteen committed parts.** Revisit when real `eff.*`/`mot.*` parts
  exist.
- **Only two definitions ship, and they are the only source of mass variety.**
  `test_island_detachment` needs two parts of very different mass to separate a
  mass-weighted centre from a plain mean, and reaches for the Core Module's
  definition at a non-core slot to get it. A third `str.*` part of a different
  mass would let that fixture stop being odd.

### The lattice and the garage
- **`BuildCommand` and the undo stack (doc 02 §9.3) are not written.** Undo is a
  garage-UI concern and §9.3 is self-contained; it wants the garage screen next
  to it. Everything it needs is in place — every commit and removal is already
  expressed in integer lattice terms, so undo can be exact.
- **`PlacementValidator.remove` returns the cascade list rather than acting on
  it.** §9.2 requires a player confirmation showing the affected count. The
  garage must not ignore it.
- **§7.6's muzzle expression is half a cell off the §2.1 cell-centre
  convention.** §7.6 computes `Vector3(cand.origin_cell) + (basis * muzzle) / U`,
  which is the cell's **corner**; `LatticeMath.cell_to_local` puts a cell's centre
  at `cell + 0.5`. The implementation is faithful to §7.6 as written. Correcting
  it is a change to §7.6, so it is flagged rather than silently fixed. Resolve
  when the first `eff.*` part is authored.

### The graph and strain
- **Nothing calls `recompute_strain` or `evaluate_strain` yet.** Both are complete
  and tested; their triggers are a recoil discharge (doc 07 §8) and an impact
  deposit (doc 08 §6.2), neither of which exists. `update_dynamic_factor` waits on
  doc 05 §9's 10 Hz call, which waits on the motion system. The producer APIs are
  in place and named as those documents name them: `deposit_recoil_force`,
  `deposit_impact_force`, `decay_deposits`.
- **Strain is attributed to the primary-tree edge only.** §2's table lists "load
  sharing" as a use of support edges, but §4.1 gives exactly one formula and it
  is `F_edge(s → parent)`. A wide panel bridged across two spars currently loads
  only the one §3.2 picked. Spreading it is a change to §4.1.
- **§4.3's strain feedback is not implemented.** Stress decals above 0.70 and the
  metal-groan cue above 0.90 are presentation and want the skirting system.
  `joint_strain_changed` already carries everything they need.
- **`assembly_terminated` reports `killer_id = 0`.** Attribution needs the damage
  layer; doc 04 §8.2 records 0 as "unattributed".

### Debris (new in session 6)
- **Nothing wires `DetachmentScheduler.island_sink` in production.** The sink
  takes an assembly id, and turning that into the `AssemblyRuntime` that owns it
  is exactly what `AssemblyRegistry` is for — see below. `test_island_detachment`
  stands in for the match scene with a two-field object; that object is what the
  match scene will be, once there is one.
- **`DebrisPool`'s owner does not exist.** It is a `Node` that expects to be a
  child of the match scene, and there are no scenes (see below).
- **Debris takes no damage and is not replicated.** §6 spawns the body and emits
  `island_detached`; doc 12's snapshot of it and doc 08's treatment of a debris
  hit are both unwritten. `DebrisBodyRef.slots` and `source_assembly_id` exist
  for exactly those two consumers.
- **No visual half.** `detach_visual_to` and §6.2's 0.25 s recycle fade both need
  meshes; see §4 and §5.
- **`AssemblyRuntime.release_part` and `restore_part` still have no production
  caller.** Their callers are doc 08 §9's `_destroy_part` and §11's repair path.
  `detach_colliders_to` now has one.

### The runtime and mass
- **There is still no `AssemblyRegistry`.** `CLAUDE.md` §2 lists
  `src/assembly/runtime/assembly_registry.gd`, doc 08 §5.3 and doc 12 §7 both
  call `AssemblyRegistry.get(aid)`, and the debris sink above needs the same
  lookup. Two schedulers keep their own `assembly_id ->` map
  (`DetachmentScheduler._graphs`, `MassRecomputeScheduler._targets`); when the
  registry lands, `register` and `unregister` on both are the four calls to move.
  It is **not** an autoload — §4's list of eight is frozen — so its ownership
  needs deciding, most likely by the match scene.
- **Doc 05 §3.4's coupling torque is not implemented.** `MassProperties`
  carries `inertia_full` precisely so it can be, and `test_mass_solver` pins the
  off-diagonal terms it consumes, but applying it is per-tick work that belongs
  to the motion system.
- **Doc 05 §5.1's stability metrics are not implemented.** They need
  `ConvexHull2D` (listed in `CLAUDE.md` §2, not written) and a Motive contact
  set. `AssemblyStats.rollover_lateral_g` is the field waiting for them.
- **`consumable_mass_step` has a consumer and no emitter.** Doc 05 §4.2's 8 kg
  quantisation belongs to the ammunition ledger (doc 07 §9), which does not exist.
- **`MotiveProbes` is an empty container.** Doc 05 §6 fills it, and needs a
  `mot.*` part to fill it with.

### Testing and scenes
- **No scenes, and no main scene set.** `test_no_runtime_csg` and
  `test_visual_decoupling` scan an empty set and say so in their check counts.
  `AssemblyRuntime` builds its tree in `_init` rather than from
  `scenes/prefabs/assembly_runtime.tscn`, and `DebrisPool` builds its ninety-six
  bodies the same way, which keeps those two scans honest.
- **`tests/physics/` and `tests/generation/` are still empty.** The runner walks
  them and finds nothing. The first real occupant of `tests/physics/` is doc 05
  §3.4's tumbling test, which needs the coupling torque.
- **Nothing in the suite can assert a physics query against a world-space body.**
  See §3.28 and §5. This is the one harness limitation that has cost a real
  assertion.
- **`test_degradation_table` and `test_constant_ownership` are not written.**
  Both should land with the systems they guard.
- **`cam_orbit`/`cam_pan` have keyboard/mouse bindings only**, and **seven
  actions had no binding in doc 11 §7.1**. Reconcile if §7.1 is completed.

---

## 8. Suggested next steps, in dependency order

1. ~~`LatticeOccupancy` + `FootprintSolver`~~ — **done, session 1.**
2. ~~First two part definitions and the registry validator~~ — **done, session 2.**
3. ~~`PlacementValidator`, `BuildContext`, `ChassisGraph`, `MateSelector`~~ —
   **done, session 3.**
4. ~~Strain (doc 04 §4) and the detachment solver (§5)~~ — **done, session 4.**
5. ~~`AssemblyRuntime` and the mass solver (doc 05 §1–§4)~~ — **done, session 5.**
6. ~~Island conversion to debris (doc 04 §6)~~ — **done, session 6.**

7. **`AssemblyRegistry` — start here.** It is small, and it is now blocking five
   call sites across three documents (§7 above), including the one seam that
   stops the debris system from being wired the way a match will wire it.
   Deciding its owner is most of the work; doc 12 §7, doc 08 §5.3 and doc 04 §6
   all assume a global reachable by id, and `CLAUDE.md` §4 says it cannot be an
   autoload. Landing it means moving four `register`/`unregister` calls off the
   two schedulers, and `test_detachment_scheduler` currently registers a bare
   `ChassisGraph` with no runtime behind it — deciding whether the registry holds
   runtimes or something narrower is the real design question.

8. **A first `mot.*` part.** It resolves the `AXLE` question, gives doc 02 §7.5 a
   real user instead of a synthetic one, and is the prerequisite for anything in
   doc 05 §6–§7.

9. **Doc 05 §6–§9: suspension, traction, aerodynamics, and κ.** The largest
   remaining block, and the one that makes an Assembly move. It needs step 8, and
   it is what finally gives `ChassisGraph.update_dynamic_factor` its caller.
   §3.4's coupling torque belongs with it, and brings the first
   `tests/physics/` occupant. It is also the first thing that would let a physics
   step run inside a test, which would in turn make §5's uncaught fault testable.

10. **A first `eff.*` part**, which forces the muzzle-offset question in §7 above
    and gives `deposit_recoil_force` its first caller.

11. **A third `str.*` part at a different mass**, whenever balance work starts.
    It also removes the one odd fixture in `test_island_detachment` (§7).

12. **A second tier of one shipped variant.** The cheapest way to make rule 13
    non-vacuous.

---

## 9. Conventions — follow these when adding to the suite

### Structure
- Test methods are `test_*` with no arguments; the runner sorts them, so no test
  may depend on another's ordering. Assertions record rather than halt, so one
  broken invariant does not hide the next twelve.
- Conformance-test failure messages name the file, the line, the invariant, and
  the correct alternative. A message that only says "forbidden" gets the rule
  worked around instead of followed.
- Arch tests that currently scan an empty set still call `check_true(true, ...)`
  with a description, so a vacuous pass is visible in the check count.
- Validator findings carry their rule number: `[R08] key: message`.
- Generated data files are derived, not typed, and are committed alongside their
  committed generator. The report carries no timestamp, so two runs over the same
  data are byte-identical.
- Free every `Node` a test puts in the tree, and `dispose()` every
  `BuildContext`, in `after_all`.

### What to assert
- **Assert the rejection, not just the acceptance.** Every check in
  `test_placement_validator` is asserted in both directions. The interpenetration
  bug in §3.18 was invisible to the accepting half and obvious to the rejecting
  half, and the velocity-inheritance test in `test_island_detachment` asserts
  both that the tangential term is present and that the answer is *not* the plain
  chassis velocity.
- **Assert a derived number, not that it moved.** A test asserting "heavier means
  more strain" passes against a model that omits κ entirely. Every strain, mass
  and inertia test fixes an input and asserts the exact value, written out as
  arithmetic against the published tables — never derived by calling the code
  under test with different arguments.
- **Assert the surviving structure, not just the return value.** A solver that
  severs too much and one that severs too little both return an island list.
- **Assert through the layer that consumes the result.** `test_assembly_runtime`
  and `test_island_detachment` count shapes on the *physics server*, not
  `CollisionShape3D` children, because counting children passes against the
  `ColliderRoot` under which not one shape was registered.
- **Go through the signals in an event-driven test.** `test_detachment_scheduler`
  never calls `_resolve_assembly`; it emits `part_destroyed` and then
  `tick_resolved`. `test_mass_recompute` never calls the solver.
  `test_island_detachment` never calls `IslandDetacher.detach` except in the two
  tests whose subject is the function's own guards. A test that called the
  subject directly would pass with the batching — the entire reason those classes
  exist — removed.
- **Cycle tests catch what point tests cannot.** Every structure these systems
  maintain is incremental and none fails loudly; twelve commit/remove cycles
  asserting the totals return to baseline make a one-per-cycle leak obvious. The
  debris pool is the same shape: acquire and release the whole budget and assert
  it comes back whole.

### Fixtures
- **Prefer real parts; use synthetics where the rule needs a class, a limit, or a
  pose that is not authored yet.** A synthetic candidate is never committed —
  commit resolves through `PartRegistry`, and a fixture in the registry would
  change what every other test in the suite sees.
- **A fixture that cannot distinguish the rule from its fallback is not a test.**
  Four examples, all found by fault injection: the depth tie-break test put the
  shallow mate on the lower slot index, so the next key down produced the same
  answer; the shape-transform test used an unrotated part, under which the two
  composition orders are identical; the island-velocity test used an angular
  velocity parallel to the lever arm, so `ω × r` was zero; and its world pose
  rotated about the axis the island sat on, so an unrotated lever arm looked
  correct. Build fixtures where the rule under test and the thing it would fall
  back to disagree.
- **A fixture built by hand can be wrong in a way that hides the rule.** Two
  re-parenting tests initially severed the edge under test before running the
  solver, so both asserted `INVALID` against a code path that never ran. If a
  test passes for a reason you cannot state in one sentence, the fixture is
  wrong.

### After writing
- **Plant faults, one at a time, and confirm something fails.** This is not
  optional and it is where most real defects in this repository have been found.
  A scripted sweep — patch, run, revert, report — is worth the ten minutes it
  takes to write; session 6's was forty faults in one pass.
- **When a planted fault is not caught, first ask whether the code is dead.**
  Across sessions 4, 5 and 6 that question deleted a depth sort, a duplicate
  clear, a redundant guard and a redundant timer reset, and it saved a mass floor
  by finding the one state that reaches it. Reaching for "document the
  redundancy" before "delete it" is how untested code accumulates.
- **Two owners of one invariant is worse than either alone.** If two places both
  enforce something, neither is load-bearing and either can be deleted silently.
  Pick one, and put an `assert` or a comment at the other naming what it relies
  on.
