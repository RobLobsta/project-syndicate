# HANDOFF

Working notes for the next session. **Not** an architecture document — `CLAUDE.md`
and the thirteen documents in `/docs/` remain the only authority. This file
records what exists, what it cost to learn, and what to do next.

Last updated: session 9 (the motion layer, and four locomotion families).

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

**41 files, 3359 checks, 0 failures.**

`run_all_checks.sh` now **fails on any engine error printed during the suite**,
not only on recorded assertion failures. See §3.34 for why — it closes a hole
that made a whole class of fault invisible.

---

## 2. How this repository knows its tests work

Every session verifies the suite by **planting faults one at a time and
confirming something fails**. A test asserted only against correct code passes
just as happily with its subject commented out. Roughly 365 faults have been
planted across eight sessions; the table below is the accumulated record, grouped
by catcher rather than by session, because what matters to the next session is
which test defends which behaviour.

Session 9 planted **142** across three passes. The first found 14 survivors, and
the way they resolved is the useful part: **six were dead code and were deleted**,
one was two owners of one invariant and was consolidated, two were genuine test
gaps, four were a whole validator rule set with no fault coverage at all, and one
turned out to be invisible to the harness rather than untested — which is how
§3.34 got found.

| Test | Faults it has caught |
|---|---|
| `test_no_global_rng` | global `randf()` in `src/` |
| `test_no_polling` | `_process` in `src/assembly/graph/`; an unlisted per-frame callback in `src/` |
| `test_no_forbidden_patterns` | `find_child()` in `src/` |
| `test_orientation_table` | transposed rotation matrix |
| `test_footprint_solver` | dropped origin offset in `resolve`; `out` buffer not shrunk on reuse |
| `test_part_registry_validator` | definition on disk absent from the manifest (R02); duplicated manifest key (R02); collider shrunk to 60% coverage (R08); resistance above the 0.85 ceiling (R07); and every rule 17–22 check: rotor thrust vs rated load, rotor zero-fields, malformed disc geometry, inverted collective limits, melee mix sum, melee mix length, melee emission fields, melee bounds, AXLE keying, an AXLE node on a class that may not carry one, family payload missing, family payload on a kind that takes none, two payloads at once, limb suspension fields, limb gait bounds, cadence ceiling below its floor, an over-long step, track steer angle, track station bounds, malformed track parameters, and the shared non-zero helper neutered |
| `test_part_registry_data` | manifest order swapped; four attachment nodes dropped from a `.tres`; a part missing from a class bucket; a locomotion family with no shipped part |
| `test_placement_validator` | occupancy never reports a cell occupied; every polarity accepted; interpenetration margin flipped positive; structural load ignores the parent's subtree; motive clearance probes one cell not the envelope; effector arc never counts a blocked sample; bounds check disabled; duplicate Core Module allowed; hard limits ignored; commit forgets `FLAG_STRAINED`; stale parent survives a rejection; Core Module charged against its own mount budget; proxy transform written before its shapes; `allocate_slot` stops allocating lowest-first; removal never finds an alternate parent |
| `test_chassis_graph` | mass propagation stops at the immediate parent; orphaning children forgets to shed their mass; connectivity walks the tree rather than support edges; duplicate support edges kept |
| `test_mate_selector` | depth tie-break dropped; weaker-joint preference inverted; joint rated by the stronger node; joint bears load when either end does; load-bearing key dropped from the ordering; re-parent ignores core reachability |
| `test_build_budget_ledger` | ledger's remove forgets the mount weight |
| `test_chassis_strain` | strain charges the part alone not its subtree; dynamic factor never applied; deposits not summed over the subtree; peak deposit replaced by the latest; candidate set only grows; dwell keyed on the ordered pair; dwell fires without waiting out the window |
| `test_detachment_solver` | connectivity walks the tree in the solver; survivors never re-parented; seeds collected after removal; terminal component cap ignored; islands returned in traversal order |
| `test_detachment_scheduler` | pending work kept for a departed Assembly; batching removed; pending cleared at the end rather than swapped first; assembly ids resolved in hash order; core loss falls through to the normal solver; unsupported orphan treated as a removed part; failed joint severs without checking other routes; core partitioned with the survivors; mass never announced dirty; island sink never called |
| `test_mass_solver` | parallel-axis term dropped; part tensor never rotated; box tensor uses half extents as full; authored half-extent override ignored; `zero()` returns the identity basis; `diagonal_of` reads a row; island tensor taken about the assembly origin; detached parts still counted; dead graph slots still counted; centre of mass divided by part count; tensor accumulated about the lattice origin; orientation dropped from the part centre of mass; snapshot omits the orientation; mass floor removed; inertia floor removed |
| `test_assembly_runtime` | shapes parented under an intermediate node; shape transform ignores the part pose; shape transform composed in the wrong order; release removes the shape instead of disabling it; visual root parented under the body; decoupling walk does not recurse; adopt leaves the build proxies alive; shape map grows zero-filled |
| `test_mass_recompute` | registration ignored; unregistered assemblies queued; queued work kept for a departed Assembly; apply happens after the launch; dirty list admits duplicates; dirty list appended rather than ordered; events for unregistered assemblies queued; dirty list not cleared after capture; consumed batch never cleared; terminated assembly's result applied anyway |
| `test_island_detachment` | island sink resolves nothing; `ω × r` term dropped; lever arm not rotated into world space; angular velocity not inherited; island centre of mass not mass-weighted; debris centre of mass left at the Assembly origin; island inertia taken about the Assembly origin; body transform composed the other way round; `FLAG_DETACHED` never set; reaper never scheduled; slot list never recorded; `island_detached` never emitted; mass counted per part rather than summed; total mass zeroed; mass properties never applied; hull shape left enabled after its island leaves; collider not rebased onto the island centre of mass; collider rebased with the wrong sign; minimum-parts guard removed |
| `test_debris_pool` | 45 faults across exhaustion order, retirement, linger, visibility dwell, shape reuse, and bounds — see session 7's record in git history for the full list |
| `test_assembly_registry` | ids appended rather than ordered; `ids()` returns the live array; unregister leaves the id behind; departure announced after the entry is dropped; arrival never announced; departure never announced; an unknown id announced anyway; `graph_of` does not read the runtime |
| `test_degradation_table` | a band multiplier changed off its documented value; a table that does not terminate at zero; a table that is not monotonic; a table of the wrong length; the out-of-range clamp removed; a table missing from `all_tables()` |
| `test_suspension_solver` | compression not clamped to travel; an ungrounded probe still compressing; rebound damped like compression; force allowed to pull; bottom-out clamp removed; settle scale always applied; damp multiplier ignored; retune scale unclamped; damper not derived from corner mass; axle pairing ignoring longitudinal distance; axle pairing accepting the same side; anti-roll ignoring the difference |
| `test_traction_solver` | slip ratio dividing by raw speed; slip angle using a signed denominator; Pacejka curve unnormalised; load sensitivity unclamped; band multiplier dropped from μ; **longitudinal sign flipped**; lateral grip ratio applied after the solve; zero-slip guard removed; brake zero-crossing guard removed; the guard catching negative drive too; ground reaction term dropped; contact inertia using full mass; torque split evenly rather than by load; rolling resistance ignoring the band |
| `test_rotor_solver` | spool as an Euler step; spool-up and spool-down swapped; power fraction not applied; power fraction unclamped above one; thrust linear in tip speed; collective clamped at zero rather than signed; ground effect never fading; translational lift unbounded; vortex ring with no forward escape; vortex ring onset removed; degradation dropped from thrust; cyclic clamped per axis rather than on the cone; thrust direction ignoring orientation; shaft torque dropping the radius term; collective unclamped; cyclic step not rate limited |
| `test_gait_solver` | **right side not reversed**; phase offsets not spread; sides not partitioned; fore-aft tie not broken on slot; standing deadband removed; cadence unclamped; clock not wrapping; neutral point using a whole stance; velocity-error correction dropped; step length unclamped; leg reach unclamped; frozen gait still stepping; turn command ignored; stance spring allowed to pull; foot force uncapped; stance damper dropped; foot μ ignoring the band; friction cone never limiting; an upward-pulling foot still transmitting; swing arc not a parabola |
| `test_track_solver` | stations not centred on the patch; stations all at the pivot; authority not tapering; taper ignoring speed magnitude; steer command unclamped; internal loss charged after the split; bias not differentiating the sides; slew resistance uncapped; slew resistance not opposing; slew ignoring patch length; slew ignoring normal load; the centreline counting as right; station load divided by count |
| `test_melee_solver` | cycle multiplier ignored; swing arc not centred; edge not offset along its reach; sample count unbounded; samples not reaching the end of the swing; channel mix ignored; the mix sum hard-coded to one; sustained flag ignored; closing-speed gate inverted; the terminal swing-progress assignment removed; reaction not opposing the strike; energised draw always charged; `begin` not clearing the target set; target budget not enforced |
| `test_motive_system` | slot list not sorted; duplicate registration appending; the class guard removed (caught only since §3.34); a tracked part given one contact; a rotary part given a contact; station index never advancing; a band change writing only traction; unregister leaving the slot; unregister not re-phasing the gait; unregister leaving the disc state; the hip not resolved from the placement |
| `test_locomotion_families` | a locomotion family mis-mapped in `LOCOMOTION_OF_MOTIVE_KIND`; `ENERGY_MELEE` not recognised as melee; a family payload keyed on the wrong kind; rotor max thrust dropping the density; stance rest length as the whole leg; stance duration ignoring duty factor; melee mix sum hard-coded to one |
| *nothing* | node adjacency tested in one direction only — see §5 |
| *nothing* | debris body given its transform before its shapes — see §5 |

### 2.1 What five sessions learned from faults that were *not* caught

The question to ask first is never "how do I test this" — it is **"is this code
dead?"** Across sessions 4 to 7 that question deleted a depth sort, a duplicate
batch clear, a redundant island guard and three redundant state resets, and it
saved a mass floor by finding the one state that reaches it. Reaching for
"document the redundancy" before "delete it" is how untested code accumulates.

The patterns worth repeating:

- **A fixture that cannot distinguish the rule from its inverse is not a test.**
  Session 5's shape-transform test used a part at orientation 0, under which the
  two composition orders differ by an addition that commutes. Session 6 walked
  into the same trap twice in one file. Session 9's version of the trap was the
  gait: a four-limb phase test that only asserted "the offsets are all different"
  would pass against an ordering with the right side *not* reversed, which is the
  one thing the rule exists to do. The test that works asserts *which* pair is
  adjacent in phase. Build fixtures where the rule under test and the thing it
  would fall back to disagree.
- **Two owners of one invariant is worse than either alone.** Nine found so far,
  three of them in session 9. One was in the tests rather than the source: a new
  `test_registry_publishes_every_shipped_part` walked the whole manifest and
  asserted the key-to-id map, which the existing `test_part_ids_follow_manifest_order`
  already did for two of the nine parts; the old test was narrowed to the reverse
  direction and the reserved id rather than left to duplicate it. The other two
  were in `MotiveSystem.register`, which guarded both the part class and the null
  profile — indistinguishable, because both return without registering — and in
  `MeleeSolver.advance`, which clamped swing progress on the assignment *and*
  pinned it to 1.0 in the branch below.
- **Six pieces of dead code were deleted rather than tested.** All six were
  guards whose condition the surrounding arithmetic already produced: a slew
  early-out for a stationary hull (`signf(0.0)` is `0.0`), an airborne-track
  early-out (a zero load makes a zero magnitude), a `READY` early-out in a match
  statement with no `READY` arm, a zero-travel guard before
  `Vector3.normalized()` (which returns zero for zero), a `duplicate()` on a
  returned `Packed*Array` (which copies on assignment anyway — §3.9), and a lower
  clamp on a quantity that only ever rises from zero. Every one of them read as
  prudence. Reaching for "document the redundancy" before "delete it" is how
  untested code accumulates.
- **A redundant check can hide a genuinely needed one.** `DetachmentScheduler`
  drops an Assembly's pending work when it leaves the match, and the resolve path
  separately guards against a null graph. They cover different cases, so the
  answer was a test for the first rather than a deletion of it.
- **Some things this harness cannot assert at all — and one it turned out it
  could, once the harness was fixed.** See §3.28: a query against the main
  world's physics space returns nothing in the suite. That is why the motion
  layer is built as pure static solvers with a thin gathering step (§5), and why
  `MotiveSystem`'s force application has no direct test. The *second* limitation
  found this session was fixable: a fault whose only symptom was a crash passed
  the suite silently, because the runner counts assertion failures and a runtime
  error merely aborts the method it happened in. That is now caught by the shell
  wrapper (§3.34). **When a fault survives, check whether it crashed rather than
  whether it was tolerated** — those look identical in a green run, and only one
  of them means the test is missing.

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
   `tests/unit/test_zz_probe.gd` and run the normal suite instead.

4. **`Basis.get_column()`, `set_column()`, and `get_row()` were removed in 4.7.**
   `Basis.x`, `.y`, `.z` remain and are the **columns**, so `b.x.x` is element
   (0,0). For a symmetric tensor the column/row distinction does not matter,
   which is exactly why a fault that reads a row instead of a diagonal survives
   any test that only checks symmetry.

5. **`Vector3i` components are int32.** A 64-bit sentinel assigned into one wraps
   silently. Use `±2147483647`.

6. **No `Packed*Array` constructor is a constant expression.** The rule was
   recorded for `PackedStringArray` in session 2 and is general:
   `const X: PackedInt32Array = PackedInt32Array([...])` fails with "Assigned
   value for constant isn't a constant expression" exactly the same way. Use
   `const X: Array[int] = [...]`, or a `static func` returning the packed array
   where a packed one is what the field needs. `Vector3i(...)` and `Vector2(...)`
   **are** constant expressions, including as `Dictionary` keys, which is why the
   face-polarity maps in the authoring tools are `const` and the class filters
   are functions.

7. **A typed-array `const` does not give a `for` loop's variable a static type,
   and neither does `range()` or an array literal.** With `untyped_declaration=2`
   (error, as configured) every one of these is a build failure:
   `for x in [1, 2]`, `for x in range(1, 5)`, `for x in some_untyped_array`.
   Write `for x: int in ...`. Iterating an `int` (`for i in 12`) or a typed array
   (including every `Packed*Array`) is fine. This is still the single most common
   way a new file fails to parse here.

8. **A `for` loop's iterator name occupies the whole enclosing function scope.**
   `for i in live:` with `var i := edge_index(...)` inside the body is
   "There is already a for loop iterator named i declared in this scope".

9. **Packed arrays pass by reference as function arguments but copy on
   assignment.** `func f(out: PackedVector3Array)` mutating `out` *is* visible to
   the caller. But `var mine := shared` or `obj.field = shared` takes a copy.
   This is why `ChassisGraph` writes `children[p] = kids` back after every
   `push_back` — dropping that line loses the edit silently.

10. **`Callable.bind()` does not make two Callables compare unequal.** Use a
    distinct receiver object per handler.

11. **A `TestCase` is a `RefCounted` and has no `get_tree()`.** To put a `Node`
    under test into a real tree — which `DetachmentScheduler`,
    `MassRecomputeScheduler`, `AssemblyRuntime`, `DebrisPool` and `MotiveSystem`
    all need — go through an autoload:
    `EventBus.get_tree().root.add_child(node)`. Free it in the same file's
    `after_all`; a leaked node stays connected to the bus and resolves the next
    test's fixture underneath it.

12. **`ProjectSettings.get_property_list()` reports every built-in `ui_*` action**
    whether or not the project declares it. Parse the `[input]` section of
    `project.godot` to see what the project actually declares.

13. **Godot rewrites `project.godot` and drops any setting equal to the engine
    default.** `tests/arch/test_project_settings.gd` asserts *effective* values
    through `ProjectSettings`, never by grepping the text.

14. **`ResourceSaver.save` neither writes a uid nor sets `resource_path` on the
    object it wrote.** A re-save *strips* the uid an existing file carried;
    capture `ResourceLoader.get_resource_uid(path)` before the write and restore
    it after. And a sub-resource assigned from memory rather than reloaded from
    its path serialises as an *inlined copy*.

15. **`ResourceSaver` regenerates `[sub_resource]` ids from the file's external
    resource set, not from content.** Session 9 refactored the authoring
    derivations into `PartAuthoring` without changing a single authored value,
    and every `.tres` still came back with different `Resource_xxxxx` ids. Reruns
    of the *same* code are byte-stable, so the tools are still idempotent — but
    "re-running rewrites the same bytes" is only true while the surrounding code
    is unchanged. Diff generated data with the `[sub_resource]` and `SubResource(`
    lines filtered out before concluding anything changed.

16. **`PackedFloat32Array` round-trips 0.85 as 0.85000002.** `resistance` is
    float32; compare with `is_equal_approx`. The same bites `Vector2`, which is
    also float32: a friction-circle magnitude computed in doubles and returned
    through a `Vector2` disagrees with the double at about 1e-7 relative, so
    `check_approx` on one needs a tolerance nearer `1e-3` than `1e-5`.

17. **A float accumulated from `PHYSICS_DT` never lands on a round threshold.**
    27 additions of `1.0/60.0` compare `< 0.45`, so a bare `>=` against a dwell
    constant silently grants one extra tick. Compare against
    `THRESHOLD - EPSILON_LINEAR` — or, where the deadline is set once rather than
    accumulated, store a **tick** and compare integers.

18. **`PhysicsServer3D` works fully under `--headless`,** including
    `space_create`, static bodies, and `space_get_direct_state(...).intersect_shape`.
    A body is visible to a query in the **same frame** it is added, with no
    physics step in between. **This holds only for a space you created yourself;
    see §3.28 for the main world.**

19. **A physics body must be given its transform *after* its shapes are added.**
    `body_set_state(BODY_STATE_TRANSFORM)` on a shapeless body leaves it with the
    broadphase entry it had while empty, and every subsequent query against it
    returns **nothing**. **Assert the reject, not just the accept.**

20. **A `Shape3D` owns its server RID and frees it on destruction.** Caching the
    bare RID and letting the Resource fall out of scope leaves every entry
    dangling, and a query against a freed shape reports no hits.

21. **Physics server RIDs are not reference counted.** A `BuildContext` dropped
    without `dispose()` leaks a space that keeps stepping for the life of the
    process. Tests collect their contexts and dispose them in `after_all`.

22. **A `CollisionShape3D` registers only as a *direct* child of a
    `CollisionObject3D`.** Nested under an intervening `Node3D` it is silently
    inert: no runtime error, no warning, and `body_get_shape_count` simply does
    not count it. This is why doc 05 §2's `ColliderRoot` had to go.

23. **A body's shape indices are assignment order, and disabling preserves them
    while removal renumbers.** `PhysicsServer3D.body_is_shape_disabled` does
    **not** exist in 4.7; assert through the node or through the shape count.

24. **`RigidBody3D.mass = 0.0` is refused** by `ERR_FAIL_COND(p_mass <= 0)`,
    leaving whatever the body already had. `inertia = Vector3.ZERO` is *accepted*
    and means "derive it from the collision shapes" — the exact physics/visual
    coupling I-1 forbids. Floor both.

25. **`WorkerThreadPool.add_task` + `wait_for_task_completion` work under
    `--headless`**, including within a single `_process` frame.

26. **The suite never has a physics frame interleaved into it.** The runner does
    all its work inside one `_process` callback, so emitting
    `MatchClock.tick_started` by hand is deterministic. The same fact is what
    makes §3.28 bite.

27. **Two `class_name` scripts may call each other's statics.** `MassSolver` and
    `InertiaSolver` reference each other, as do `RotorDiscState` and
    `RotorSolver`; neither the parser nor the loader objects. A cycle is only a
    problem for `extends` and for constant folding.

28. **The main world's `direct_space_state` answers nothing in this suite.** A
    `StaticBody3D` or `RigidBody3D` added to `get_tree().root` with a live
    `CollisionShape3D` is invisible to `intersect_shape` and to `intersect_ray`
    until a physics step has run, and the runner never lets one run. No error is
    printed: the query returns empty, which reads exactly like a correct
    "nothing there". A space made with `PhysicsServer3D.space_create` answers
    immediately. `SubViewport.world_3d` is null headless even with
    `own_world_3d = true`.

29. **`RigidBody3D.linear_velocity` and `angular_velocity` round-trip through the
    server with no physics step**, so a test can set a chassis velocity and
    assert exactly what a severed island inherited from it.

30. **A member's initialiser may call a static function; a `const` may not.**
    `var _freeze_after_ticks: int = MatchClockService.ticks_for_seconds(4.0)` is
    legal and runs once per instance.

31. **`VisibleOnScreenNotifier3D.is_on_screen()` is always false headless, but
    its signals are drivable.** A class that *caches* the flag from
    `screen_entered`/`screen_exited` is testable where one that polls is not.
    Cheaper too. The notifier's `aabb` is in its own local space.

32. **A `VisualInstance3D` under a `PhysicsBody3D` is not automatically an I-1
    violation.** The invariant is about geometry and about visual transforms
    driving physics. Doc 04 §6.2 records the reasoning; do not extend it to
    meshes without the same argument.

33. **A `Callable` bound to a `Node`'s method survives being reassigned around.**
    `scheduler.island_sink = pool.on_island_severed` is the whole production
    wiring between doc 04 §5 and §6.

34. **The test runner does not fail on a GDScript runtime error, and now the
    shell wrapper does.** `run_all_checks.gd` counts recorded assertion failures
    and nothing else. A null dereference, a failed `assert()`, or a call on a
    freed object prints to stderr, aborts the *method* it happened in, and lets
    the runner continue — so the test reports zero failures and the file passes.
    **Any fault whose only symptom is a crash is therefore invisible to fault
    injection.** Session 9 hit this with a class guard in `MotiveSystem.register`
    whose removal caused a null dereference and changed nothing the suite could
    see. `tools/ci/run_all_checks.sh` now tees the run and fails on any
    `SCRIPT ERROR`/`ERROR` line, which caught it immediately. Two consequences
    for the next session: a planted fault that "passes" may have crashed rather
    than been tolerated, so read the log; and **an `assert()` is not a testable
    guard here** — it does not fail a check, it only prints.

35. **`Vector2.limit_length` is the cone clamp, and `clampf` per component is
    not.** Two 14° deflections clamped independently compose to about 19.8° of
    resultant tilt; the same input through `limit_length` composes to 13.92°.
    The 0.08° shortfall against the nominal limit is the cost of composing two
    orthogonal rotations and is correct — a test asserting exactly 14° there is
    asserting something false.

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
matrix is now a flat `POLARITY_MATRIX`, asserted cell by cell.

**Session 3 — doc 04 §2.1 and §3.1.** §2.1 gained `mass_kg`. §3.1 now states that
a `MateRecord`'s `joint_strength_n` is the **weaker** of the two nodes and that
`_add_edge` is idempotent per pair.

**Session 4 — doc 01 §3; doc 04 §2.1, §3.3, §4.1, §4.2, §5.3, §5.5, §7.2, §8.2;
doc 07 §8; doc 08 §6.2.** Gap-filling except two corrections: the dwell key is
canonical over the *unordered* pair, and the dwell comparison carries an epsilon.
`GRAVITY_MPS2` was written as a literal in four documents and owned by none.

**Session 5 — doc 05 §2, §3.3, §4.3; doc 04 §6; doc 08 §5.4; `CLAUDE.md` §5.1.**
`ColliderRoot` removed (§3.22 above). The inertia accumulation moved to
`InertiaSolver`. The mass scheduler runs on `MatchClock.tick_started`, joins on
the next tick, and reads a snapshot rather than the live graph. The shape map
grows filled with `INVALID_SLOT` rather than zero.

**Session 6 — doc 04 §6 and §6.2; `CLAUDE.md` §2.** `DebrisPool` and
`DebrisReaper` are instances rather than globals; colliders are re-registered on
the debris body rather than moved; mass properties go through
`MassSolver.apply_mass_properties`; both debris deadlines are tick counts; shape
nodes are reused, never freed.

**Session 7 — doc 04 §6 and §6.2; doc 08 §5.1; doc 12 §7.2 and §9.2.**
`AssemblyRegistry` is an object, not a global. A wreck's lifetime ends in two
events — deterministic retirement, then a presentation-only linger. Doc 12 §9.2
gained `debris_visibility`, the first tag whose absence changes behaviour.

**Session 9 — doc 01 §3, §4, §7.2, §7.4, §10, §11, §14; doc 05 §6, §7.2, §7.4,
§11, §12, §13, §14; doc 06 §3; doc 07 §14, §15; `CLAUDE.md` §1.1, §2, §6, §8.**
The largest amendment set so far, because it added three locomotion families and
a weapon class. The ones that are corrections rather than additions:

- **Doc 05 §7.2: the longitudinal friction sign was wrong.** The section wrote
  both friction components as negative. With `κ = (ω·r − v_long)` from §7.1, a
  driven contact has *positive* κ, so a negative `F_long` pushed the Assembly
  backwards — pressing the accelerator would have decelerated it. §7.4's own
  `− F_long · r` retarding term only balances against the positive sign, so the
  two sections disagreed and §7.4 was right. The asymmetry between the two signs
  is real and now stated: κ is already the negative of the patch's slip velocity
  and `tan α` is not. **Found by the first test that asserted a driven contact
  accelerates the Assembly it is attached to**, which is exactly the kind of
  claim the fixture rules in §9 are about.
- **Doc 05 §7.4: `wheel_omega`, `m_wheel`, and `_integrate_wheel` renamed.**
  `CLAUDE.md` §8 prohibits *wheel* in identifiers and §7.1's own contact frame
  already used neutral vocabulary. The conflict was invisible while nothing
  implemented the section.
- **Doc 01 §4.2: `AXLE` resolved as a keyed connector.** The open question from
  session 2 is closed. A Motive Assembly's drive face is `AXLE` and nothing else;
  it mates only to a Structural Component offering an `AXLE` station whose nodes
  restrict `accepts_classes` to `MOTIVE_ASSEMBLY`. One station
  (`str.hub.axle_station.t2`) serves all four families, because the
  24-orientation group points its drive axis anywhere — which is the strongest
  evidence available that the four families really are one class.

And the additions, each with its own document section rather than a flag on an
existing one:

- **`LocomotionMode` and `LOCOMOTION_OF_MOTIVE_KIND` (doc 01 §4.1).** Family
  selection is one array index. No subsystem outside `MotiveSystem` branches on
  `MotiveKind`, and a fifth family is an append rather than a new branch in every
  consumer.
- **Doc 05 §6.0, the five rules every family meets.** Forces and torques on
  `ChassisBody` only; cached band multipliers, never integrity; no state the mass
  solver owns; deterministic; bounded and slot-indexed. Rule 1 is the load-bearing
  one — it is what lets a rotorcraft take blast damage, shed a panel, re-solve its
  mass and keep flying with no code in the damage or mass layers aware that rotors
  exist.
- **Doc 05 §12, rotor lift and tilt.** Momentum-theory thrust, signed collective,
  ground effect, translational lift, vortex ring state with a forward-flight
  escape, cone-limited cyclic, reaction torque, and shaft power. The shipping
  coefficients are *solved* from `T_max = rated_load × g` rather than chosen, and
  §14 rule 19 checks it.
- **Doc 05 §13, ambulatory locomotion.** Spring-loaded inverted pendulum with
  Raibert foot placement. §13.1 records why Invariant I-3 does not merely forbid
  a jointed leg but makes one unnecessary: a leg contributes exactly one force at
  the hip, and the internal articulation reaches the body only through it.
- **Doc 05 §14, tracked locomotion.** Road stations, differential drive with a
  speed taper, and slew resistance proportional to patch length times normal load.
  Its own family rather than a flag on the ground one, because routing it through
  `GROUND` puts three `if kind == TRACKED_SEGMENT` branches inside hot loops.
- **Doc 07 §15, melee effectors.** Swept-capsule resolution, a stage machine in
  place of a cycle timer, `channel_mix` doing the balance work so `KINETIC_MELEE`
  and `ENERGY_MELEE` need no second code path, and server-only authority that is
  stricter than the ballistic path.
- **Doc 01 §3 gained `AIR_DENSITY_KG_M3`**, for the same reason it gained
  `GRAVITY_MPS2`: §8's dynamic pressure and §12's momentum theory must not be able
  to disagree about the atmosphere.
- **Doc 06 §3 gained `locomotion_modes` and two archetypes**, `rotorcraft` and
  `strider`, each with a hard constraint checked in Phase 3 rather than deferred
  to the objective, because a build that fails either does not function.

---

## 5. Deliberate readings, and the redundancies

**Presentation is not on `BuildContext`.** Meshes are driven by
`EventBus.part_attached` (I-4). The **build proxies** are the exception and are
created there: they are physics, and they are what doc 02 §7.7 queries.

**`_check_collider_interpenetration` is skipped without a physics space.**
`BuildContext.headless()` has none, and server-side blueprint re-validation uses
it. Doc 02 §12 invariant 1 permits this precisely because the query may only
*reject*, never *accept*.

**`ResolvedNode.is_face_paired` is over-specified, knowingly.** It tests
adjacency in both directions *and* that the faces oppose, and any two imply the
third. Fault injection cannot make it fail by removing one — one of the two
entries in §2's table with no catcher, and not a test gap.

**`IslandDetacher` writes the debris body's transform after its shapes, and
nothing proves it must.** §3.19 recorded the failure that rule exists for, and
§3.28 is why it cannot be re-observed here. The second of §2's two uncaught
faults. If a future session gains a physics step inside the suite, the test to
write is *a shape query at the island's centre of mass finds the debris body*.

**`MotiveSystem._gather_contacts` has no test, and that is the same limitation.**
Everything the motion layer derives is in a pure static solver a test reaches
directly; the gathering step is a loop over already-built `ShapeCast3D` nodes
copying four fields, and §3.28 makes it unobservable here. It is kept as thin as
it can possibly be for exactly that reason — every line in it is a line nothing
defends. The same physics step that would test the debris body would test this.

**`MotiveSystem.register` guards the part class and nothing else.** It used to
also guard a null `motive_profile`, and fault injection showed the two were
indistinguishable — both return without registering. Validator rule 6 rejects a
Motive Assembly with a null payload at build time, so the class test is the only
guard that ever fires on real data, and the comment there names what it relies
on. Removing it is caught only because the shell wrapper now fails on the
resulting null dereference (§3.34); before that fix it was invisible.

**`MotiveSystem` declares `_physics_process` and is on the `test_no_polling`
allowlist.** It is a force integrator, not a reactor to structural events, and
doc 05 §9's dynamic amplification factor is explicitly per-tick work. `step(dt)`
is the whole tick and `_physics_process` does nothing but call it — which is not
decoration, it is what lets a test drive the identical path the engine uses.

**A rotor and a wheel share `DegradationTable.MOTIVE_TRACTION`.** A disc at
`IMPAIRED` loses 40% of its thrust exactly as a wheel loses 40% of its grip.
Splitting the table so the four families could drift apart would be a balance
liability, not a modelling gain, and Invariant I-5 wants one table.

**`LimbState.hip_local` is cached at registration rather than resolved per
call.** A part does not move relative to the chassis, so the hip is fixed from
placement to destruction. Caching it is not only cheaper — it is what lets
`reassign_gait_phases` run without reaching back into the Assembly for a
definition it was already handed, which is how the first version of it silently
did nothing in a test with no runtime wired.

**`MotiveAssemblyProfile.contact_radius_m` keeps its meaning across all four
families** — rolling radius, hub radius, foot radius. Doc 02 §7.5's ground
clearance check and doc 05 §6.1's probe geometry both read it, and neither should
have to know which family it is looking at.

**`str.aperture.port.t2` is `TRANSPARENT` and was briefly not.** An edit to the
§10.2 table adjacent to it changed the occlusion column by accident and it was
reverted in the same session. Nothing depends on it yet; it is noted only because
the row is easy to clip when appending to that table.

**Nothing simulated may read `DebrisPool.retired_count`.** It is the one number
in the debris system that legitimately differs between the server and a client.
`simulated_count` is the one they agree on.

**`DetachmentScheduler` drops pending work for an unregistered Assembly, and the
resolve path separately guards against a null graph.** These look like the same
check and are not: the first covers an Assembly that left the match with a
destruction already queued, the second an id that was never registered at all.

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
  the six class profiles, and **new in session 9**: `RotorProfile`,
  `LimbProfile`, `TrackProfile`, `MeleeProfile`.
- `src/core/math/` — `LatticeMath`, `OrientationTable` (full 24-element group).
- `src/assembly/lattice/` — `LatticeOccupancy`, `FootprintSolver`,
  `ResolvedNode`, `PlacementCandidate`, `BuildBudgetLedger`, `BuildShapeCache`,
  `BuildContext`, `PlacementValidator`.
- `src/assembly/graph/` — `MateRecord`, `MateSelector`, `ChassisGraph`,
  `DetachmentSolver`, `DetachmentScheduler`, `IslandDetacher`.
- `src/assembly/mass/` — `MassSolver`, `InertiaSolver`, `MassRecomputeScheduler`.
- `src/assembly/runtime/` — `AssemblyStats`, `AssemblyRuntime`, `ChassisBodyRef`,
  `AssemblyInterpolator`, `DebrisBodyRef`, `DebrisPool`, `DebrisReaper`,
  `AssemblyRegistry`.
- `src/motion/` — **all new in session 9**: `MotiveContact`, `SuspensionSolver`,
  `TractionSolver`, `RotorSolver`, `RotorDiscState`, `GaitSolver`, `LimbState`,
  `TrackSolver`, `AeroSolver`, `PowerSystem`, `ControlInput`, `MotiveSystem`.
- `src/combat/damage/` — **new**: `DegradationTable`.
- `src/combat/effectors/` — **new**: `MeleeSolver`, `MeleeStrikeState`.
- `src/autoload/` — all eight singletons, complete, in the §4 order.
- `project.godot` — autoloads, physics/display settings, all 33 input actions.

`ChassisGraph` covers doc 04 §2–§4 in full; `DetachmentSolver` and
`DetachmentScheduler` cover §5 and §7.2; `IslandDetacher`, `DebrisPool` and
`DebrisReaper` cover §6 and §6.2. `AssemblyRuntime` and the mass classes cover
doc 05 §1–§4 and §10.2. **The `src/motion/` set covers doc 05 §6–§9 and §12–§14**,
and `MeleeSolver` covers doc 07 §15.

**The wiring the match scene will do**, in full:

```gdscript
var registry := AssemblyRegistry.new()

var detachment := DetachmentScheduler.new()
detachment.registry = registry

var mass := MassRecomputeScheduler.new()
mass.registry = registry

var debris := DebrisPool.new()
debris.registry = registry
detachment.island_sink = debris.on_island_severed

add_child(detachment); add_child(mass); add_child(debris)

# then, per Assembly:
#   runtime.adopt(ctx); registry.register(runtime)
#   var motion := MotiveSystem.new()
#   motion.runtime = runtime
#   motion.power = PowerSystem.new()
#   motion.input = ControlInput.new()
#   runtime.add_child(motion)
#   for each Motive Assembly slot: motion.register(slot, def, runtime.states[slot])
#   motion.reassign_gait_phases()
```

### Data
Nine definitions, in manifest order. **Append only.**

| `part_key` | Class / kind | Notes |
|---|---|---|
| `core.command.compact.t2` | Core Module | 60 cells, 94 nodes, 380 kg, 240 PU, 28 mounts |
| `str.panel.medium.t2` | Structural | 16 cells, 48 neutral nodes, 34 kg |
| `str.hub.axle_station.t2` | Structural | 8 cells; the only part carrying `AXLE` nodes (±X, keyed to Motive) |
| `mot.wheeled.allroad.t2` | `WHEELED_STEERED` | 24 cells, authored as a **disc** so a cylinder collider meets §6.2 coverage |
| `mot.tracked.short_bogie.t2` | `TRACKED_SEGMENT` | 96 cells, 4 road stations, 1.90 m patch |
| `mot.rotor.coaxial_mid.t3` | `ROTOR_DISC` | 96 cells, 2.6 m disc, lifts 2600 kg, draws 150 PU |
| `mot.limb.strider.t4` | `AMBULATORY_LIMB` | 72 cells, 1.90 m leg, 0.62 duty factor |
| `pwr.combustion.standard.t2` | Power Plant | 60 cells, 3200 N·m, supplies 150 PU |
| `eff.melee.beam_edge.t4` | `ENERGY_MELEE` | 72 cells, 2.4 m reach, 75% thermal mix |

`tools/part_authoring.gd` holds the shared derivations; `tools/author_first_parts.gd`
and `tools/author_locomotion_parts.gd` are the two committed generators. Both are
idempotent (with the caveat in §3.15).

### Tests
`tests/test_case.gd` (assertion base) and `tests/source_scanner.gd`.

Arch: `test_autoload_set`, `test_input_actions`, `test_project_settings`,
`test_no_polling`, `test_no_global_rng`, `test_no_forbidden_patterns`,
`test_no_runtime_csg`, `test_visual_decoupling`, `test_scripts_parse`.

Unit: `test_assembly_registry`, `test_lattice_math`, `test_orientation_table`,
`test_part_definition_bake`, `test_collider_profile_serialisation`,
`test_lattice_occupancy`, `test_footprint_solver`, `test_attachment_polarity`,
`test_part_registry_validator`, `test_chassis_graph`, `test_mate_selector`,
`test_build_budget_ledger`, `test_chassis_strain`, `test_detachment_solver`,
`test_mass_solver`, and **new**: `test_degradation_table`,
`test_suspension_solver`, `test_traction_solver`, `test_rotor_solver`,
`test_gait_solver`, `test_track_solver`, `test_melee_solver`.

Integration: `test_tick_ordering`, `test_part_registry_data`,
`test_placement_validator`, `test_detachment_scheduler`, `test_assembly_runtime`,
`test_mass_recompute`, `test_island_detachment`, `test_debris_pool`, and
**new**: `test_motive_system`.

Physics: **new**, and the directory's first occupant —
`test_locomotion_families`, which asserts against the shipped definitions rather
than synthetics.

`tests/generation/` is still empty.

---

## 7. Known gaps — deliberate, not oversights

### The motion layer
- **`MotiveSystem` has never applied a force.** Every solver it calls is asserted
  exactly, and the dispatch and bookkeeping are tested, but the force application
  itself needs a physics step the suite cannot run (§3.28, §5). This is the
  largest single untested surface in the project and it is one scene away from
  being testable.
- **Probes are never built.** `_probe_for` looks up `probe_s%03d_%d` under
  `MotiveProbes` and nothing creates those nodes yet. Doc 05 §6.1 specifies the
  geometry; the constructor belongs with `AssemblyRuntime.adopt`, and writing it
  before there is a scene to see it in would be writing it blind.
- **`_surface_multiplier` returns 1.0 unconditionally.** The Ground Array of
  document 09 answers it. Routed through one named function so landing that
  document is a single edit rather than a search for every place a surface was
  assumed.
- **`AeroSolver` has no caller.** It is complete and matches doc 05 §8, but
  Control Surfaces need a per-part pressure-centre pass in `MotiveSystem` and no
  `ctl.*` part is authored.
- **`ControlSystem` is not written.** `ControlInput` is the record every family
  reads; the mapping from the §7.2 input actions into one is a garage/HUD concern
  and wants `src/ui/`.
- **`PowerSystem.recompute` has no caller**, for the same reason
  `MassRecomputeScheduler` had none for two sessions: it is wired on structural
  and band-change events, and `DamageResolver` does not exist.
- **Anti-roll is implemented and unused.** `SuspensionSolver.anti_roll_force` and
  `is_axle_pair` are tested; pairing probes at spawn belongs with the probe
  constructor above.
- **The coupling torque of doc 05 §3.4 is still not applied.** `MassProperties`
  carries `inertia_full` precisely so it can be. It belongs in `MotiveSystem.step`
  and brings `tests/physics/`'s second occupant.

### Melee
- **`MeleeSolver` computes everything except the query.** The swept-capsule
  `intersect_shape` belongs to the effector system, which owns the space and does
  not exist. `EffectorSystem`, `HardpointState`, `AimSolver`, and `AmmoLedger` are
  all doc 07 and all unwritten.
- **Nothing consumes `channel_mix`.** `DamageResolver` (doc 08 §5) is where the
  packets go, and it is unwritten.

### Data and the registry
- **Rule 13 (tier scaling) has still never fired.** It needs two tiers of one
  `class.family.variant` and the nine shipped parts have no such pair. The rotor
  family is now the cheapest place to make it non-vacuous: doc 01 §10.3 publishes
  `mot.rotor.coaxial_heavy.t4` and `mot.rotor.main_single.t3` alongside the
  shipped mid disc.
- **`mot.rotor.main_single.t3` is the interesting one to author next.** It has
  `torque_reaction_ratio = 1.0` and no yaw authority, so a build carrying one
  alone spins under its own reaction torque and cannot stop. That is legal, and
  it is the first part whose *failure mode* is the teaching.
- **Rule 2's reorder half is not implemented, and cannot be from data alone.** It
  needs a recorded baseline of shipped ids. Nine parts have now shipped in this
  branch but nothing has shipped to a player, so there is still no history to
  protect.
- **Only one Effector Module exists and it is melee.** The ballistic path — arc
  solving, spread, recoil deposit, the projectile pool — has no authored user.
  Doc 02 §7.6's muzzle-offset half-cell discrepancy is still unresolved and is
  still flagged rather than silently fixed.

### The lattice and the garage
- **`BuildCommand` and the undo stack (doc 02 §9.3) are not written.** Everything
  it needs is in place — every commit and removal is already expressed in integer
  lattice terms, so undo can be exact.
- **`PlacementValidator.remove` returns the cascade list rather than acting on
  it.** §9.2 requires a player confirmation showing the affected count.
- **Nothing has ever placed a Motive Assembly through the validator.** Doc 02
  §7.5's ground-clearance check now has real parts to reject, and the `AXLE`
  keying of §4.2 has never been exercised by a placement. `test_placement_validator`
  uses synthetic candidates throughout and should gain a real one.

### The graph and strain
- **`update_dynamic_factor` finally has a caller** — `MotiveSystem._update_kappa`
  — but nothing has run it against a moving body. `recompute_strain` and
  `evaluate_strain` are still waiting on a recoil discharge and an impact deposit.
- **Strain is attributed to the primary-tree edge only.** A wide panel bridged
  across two spars loads only the one doc 04 §3.2 picked. Spreading it is a change
  to §4.1.
- **`assembly_terminated` reports `killer_id = 0`.** Attribution needs the damage
  layer.

### Testing and scenes
- **No scenes, and no main scene set.** This is now the single biggest blocker.
  It gates the probe constructor, the force application test, the camera the
  debris visibility mechanism has never met, and the coupling torque.
- **`tests/generation/` is empty.** The runner walks it and finds nothing.
- **`test_constant_ownership` is not written.** `test_degradation_table` landed
  this session; the ownership scan should land with whatever next duplicates a
  constant.
- **`run_all_checks.gd` itself still tolerates a runtime error.** The shell
  wrapper catches it (§3.34), which is enough for CI, but a test run through the
  engine directly still reports a false pass. Moving the scan into the runner
  would want a way to observe engine errors from GDScript, which 4.7 does not
  offer cleanly — the wrapper is the pragmatic place for it and the limitation is
  worth knowing before someone runs the `.gd` on its own and trusts the result.
- **`cam_orbit`/`cam_pan` have keyboard/mouse bindings only**, and seven actions
  had no binding in doc 11 §7.1.

---

## 8. Suggested next steps, in dependency order

1. ~~`LatticeOccupancy` + `FootprintSolver`~~ — **done, session 1.**
2. ~~First two part definitions and the registry validator~~ — **done, session 2.**
3. ~~`PlacementValidator`, `BuildContext`, `ChassisGraph`, `MateSelector`~~ —
   **done, session 3.**
4. ~~Strain and the detachment solver~~ — **done, session 4.**
5. ~~`AssemblyRuntime` and the mass solver~~ — **done, session 5.**
6. ~~Island conversion to debris~~ — **done, session 6.**
7. ~~`AssemblyRegistry` and visibility-aware debris retirement~~ — **done, session 7.**
8. ~~A first `mot.*` part~~ — **done, session 9**, and it became seven parts across
   four locomotion families.
9. ~~Doc 05 §6–§9: suspension, traction, aerodynamics, and κ~~ — **done,
   session 9**, plus §12–§14 for the rotary, ambulatory, and tracked families.

10. **The match scene — start here.** It is now the blocker for four separate
    things, all of them listed in §7: the suspension probe constructor, the first
    real force application, the camera the debris visibility mechanism has never
    seen, and doc 05 §3.4's coupling torque with its tumbling test. Everything it
    needs to hold is written and the wiring is in §6. Nothing else in the project
    unblocks as much per hour.

11. **The probe constructor and one real placement.** Building the `ShapeCast3D`
    set in `AssemblyRuntime.adopt` per doc 05 §6.1, and pushing one Motive
    Assembly through `PlacementValidator` so §7.5's clearance check and §4.2's
    `AXLE` keying are exercised by a placement rather than by a unit test.

12. **`DamageResolver` and doc 08.** It is the missing consumer for `channel_mix`,
    for `PowerSystem.recompute`, for `MotiveSystem.on_band_changed`, and for
    `assembly_terminated`'s killer attribution. Four systems are waiting on one
    document.

13. **`EffectorSystem` and doc 07 §7.** The melee sweep query needs it, and it is
    what gives `deposit_recoil_force` its first caller.

14. **A second tier of the rotor family.** The cheapest way to make rule 13
    non-vacuous, and `mot.rotor.main_single.t3` is worth authoring for its failure
    mode alone.

---

## 9. Conventions — follow these when adding to the suite

### Structure
- Test methods are `test_*` with no arguments; the runner sorts them, so no test
  may depend on another's ordering. Assertions record rather than halt.
- Conformance-test failure messages name the file, the line, the invariant, and
  the correct alternative. A message that only says "forbidden" gets the rule
  worked around instead of followed.
- Arch tests that currently scan an empty set still call `check_true(true, ...)`
  with a description, so a vacuous pass is visible in the check count.
- Validator findings carry their rule number: `[R08] key: message`.
- Generated data files are derived, not typed, and are committed alongside their
  committed generator.
- Free every `Node` a test puts in the tree, and `dispose()` every
  `BuildContext`, in `after_all`.

### What to assert
- **Assert the rejection, not just the acceptance.** Every check in
  `test_placement_validator` is asserted in both directions.
- **Assert a derived number, not that it moved.** A test asserting "heavier means
  more strain" passes against a model that omits κ entirely. Every strain, mass,
  inertia, suspension, traction, rotor, gait and track test fixes an input and
  asserts the exact value, written out as arithmetic against the published
  tables — never derived by calling the code under test with different arguments.
- **Assert the sign, in every direction it can point.** Session 9's traction sign
  defect survived a test that asserted the friction *magnitude* was right. The
  test that caught it asserts that a driven contact pushes forward, a dragging one
  pushes back, and a sideways-sliding one is pushed the other way — three
  directions, one convention.
- **Assert the surviving structure, not just the return value.** A solver that
  severs too much and one that severs too little both return an island list.
- **Assert through the layer that consumes the result.** `test_assembly_runtime`
  counts shapes on the *physics server*, not `CollisionShape3D` children.
- **Go through the signals in an event-driven test.** `test_detachment_scheduler`
  never calls `_resolve_assembly`; it emits `part_destroyed` and then
  `tick_resolved`.
- **Cycle tests catch what point tests cannot.** Every structure these systems
  maintain is incremental and none fails loudly.

### Fixtures
- **Prefer real parts; use synthetics where the rule needs a class, a limit, or a
  pose that is not authored yet.** With nine parts shipping, far more is
  reachable with real data than was. `tests/physics/test_locomotion_families.gd`
  is the pattern: it asserts against `PartRegistry` and nothing else.
- **Drive a subsystem through the signal its real producer raises.**
- **A fixture that cannot distinguish the rule from its fallback is not a test.**
  Five examples now, all found by fault injection: the depth tie-break test put
  the shallow mate on the lower slot index; the shape-transform test used an
  unrotated part; the island-velocity test used an angular velocity parallel to
  the lever arm; its world pose rotated about the axis the island sat on; and the
  gait phase test would have passed with the right side unreversed if it had only
  asserted that the offsets differ.
- **A fixture built by hand can be wrong in a way that hides the rule.** If a
  test passes for a reason you cannot state in one sentence, the fixture is wrong.

### After writing
- **Plant faults, one at a time, and confirm something fails.** This is not
  optional and it is where most real defects in this repository have been found —
  including, this session, a sign error in a normative document. A scripted sweep
  is worth the ten minutes it takes to write; session 9's was 130 faults in one
  pass.
- **When a planted fault is not caught, first ask whether the code is dead.**
- **Two owners of one invariant is worse than either alone.** If two places both
  enforce something, neither is load-bearing and either can be deleted silently.
  This applies to tests as much as to source.
- **Two checks that look alike may cover different cases.** Before deleting the
  one whose removal changed nothing, write down the input each would catch.
