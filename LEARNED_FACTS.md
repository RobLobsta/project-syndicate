# LEARNED FACTS

**What this project has learned the hard way.** Engine behaviour that cost
somebody an afternoon, testing rules that were paid for in defects that shipped,
and readings of the architecture that were decided once and should not be
re-litigated.

`CLAUDE.md` and the thirteen documents in `/docs/` remain the only authority.
This file has none: it records what is *true about working here*, not what the
software must do. `HANDOFF.md` carries the work queue; `CHANGE_LOG.md` carries
what each session did.

**Read sections 1 and 2 before writing code, and section 3 before writing a
test.** Nothing in here is ordered by importance — it is ordered so that a thing
can be found again.

| § | What is in it |
|---|---|
| 0 | Where the old `HANDOFF.md` section numbers went — the one copy |
| 1 | Engine facts, verified against Godot 4.7.1 in this repository |
| 2 | What the fault sweeps taught, and what uncaught faults taught |
| 3 | Conventions for adding to the suite |
| 4 | Deliberate readings of the architecture, and the redundancies kept on purpose |

---

## 0. Where the old section numbers went

These three files were one `HANDOFF.md` until session 24. Older comments in
`src/`, `tests/` and `tools/` refer to its sections, and so does some text kept
verbatim here. The mapping:

| Old | Now |
|---|---|
| handoff §1 (environment) | `HANDOFF.md` §1 |
| handoff §2, §2.1 (test record, lessons) | `LEARNED_FACTS.md` §2, and the per-test table in `CHANGE_LOG.md` §2 |
| handoff §2.0 (sweep records) | `CHANGE_LOG.md` §3 |
| handoff §3.NN (engine facts) | `LEARNED_FACTS.md` §1 — **the item numbers are unchanged**, so §3.55 is fact 55 |
| handoff §4.NN (findings) | `CHANGE_LOG.md` §1 |
| handoff §5 (deliberate readings) | `LEARNED_FACTS.md` §4 |
| handoff §6 (what exists) | deleted; the source tree is the answer |
| handoff §6.5 (player review) | `HANDOFF.md` §2 |
| handoff §7 (known gaps) | `HANDOFF.md` §4 |
| handoff §8 (next steps) | `HANDOFF.md` §3 |
| handoff §9 (conventions) | `LEARNED_FACTS.md` §3 |

A bare `§N.M` in prose that is *not* in that table is a reference to one of the
thirteen documents in `/docs/`, named just before it.


---

## 1. Engine facts that cost time — read before writing code

All verified against 4.7.1 in this repo, not recalled. They are numbered for
cross-reference and the numbers are stable; nothing here is in priority order.

**Two numbers are used twice** — there are two facts 62 and two 63, adjacent in
each case. That is a defect and it is deliberately not being repaired: `src/`,
`tests/` and `tools/` cite these numbers in comments, and renumbering to tidy the
list would silently point every one of them at a different fact. Read a citation
with its subject, which is always named. (The horizontal rule that used to split
the section between the two pairs is gone — it read as a section boundary and
there is only one section here.)

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
   `tests/**/test_zz_probe.gd` and run the normal suite instead.

4. **`Basis.get_column()`, `set_column()`, and `get_row()` were removed in 4.7.**
   `Basis.x`, `.y`, `.z` remain and are the **columns**, so `b.x.x` is element
   (0,0). For a symmetric tensor the column/row distinction does not matter,
   which is exactly why a fault that reads a row instead of a diagonal survives
   any test that only checks symmetry.

5. **`Vector3i` components are int32.** A 64-bit sentinel assigned into one wraps
   silently. Use `±2147483647`.

6. **No `Packed*Array` constructor is a constant expression.**
   `const X: PackedInt32Array = PackedInt32Array([...])` fails with "Assigned
   value for constant isn't a constant expression". Use `const X: Array[int]`, or
   a `static func` returning the packed array. `Vector3i(...)` and `Vector2(...)`
   **are** constant expressions, including as `Dictionary` keys.

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
   `push_back` — dropping that line loses the edit silently. Not true of a plain
   `Array`, which is why `AssemblyRegistry.ids()` does need its `duplicate()`.

10. **`Callable.bind()` does not make two Callables compare unequal.** Use a
    distinct receiver object per handler.

11. **A `TestCase` is a `RefCounted` and has no `get_tree()`.** To put a `Node`
    under test into a real tree, go through an autoload:
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
    resource set, not from content.** Reruns of the *same* code are byte-stable,
    but any change to the surrounding authoring code churns every id. **Diff
    generated data with the `[sub_resource]` and `SubResource(` lines filtered
    out before concluding anything changed.** Session 10's data change was 776
    lines of diff and 69 lines of content; the filter is what showed that.

16. **`PackedFloat32Array` round-trips 0.85 as 0.85000002.** `resistance` is
    float32; compare with `is_equal_approx`. The same bites `Vector2`, which is
    also float32: a friction-circle magnitude computed in doubles and returned
    through a `Vector2` disagrees at about 1e-7 relative, so `check_approx` on one
    needs a tolerance nearer `1e-3` than `1e-5`.

17. **A float accumulated from `PHYSICS_DT` never lands on a round threshold.**
    27 additions of `1.0/60.0` compare `< 0.45`, so a bare `>=` against a dwell
    constant silently grants one extra tick. Compare against
    `THRESHOLD - EPSILON_LINEAR` — or store a **tick** and compare integers.

18. **`PhysicsServer3D` works fully under `--headless`,** including
    `space_create`, static bodies, and `space_get_direct_state(...).intersect_shape`.
    A body is visible to a query in the **same frame** it is added, with no
    physics step in between.

19. **A physics body must be given its transform *after* its shapes are added.**
    `body_set_state(BODY_STATE_TRANSFORM)` on a shapeless body leaves it with the
    broadphase entry it had while empty, and every subsequent query against it
    returns **nothing**. **Assert the reject, not just the accept.**

    **Qualified in session 17: "every subsequent query" means every query before
    the next physics step.** A step rebuilds the entry from the body's current
    shapes and pose, so the damage is confined to the frame it happened in. That
    is why the ordering rule is real and why no test in `tests/physics/` can
    catch a violation of it — the `await physics_frames` those tests need in
    order to read a current pose (§3.28) is the same step that repairs it.
    Measured both ways round; see §8 item 14 before writing a third fixture for
    this.

20. **A `Shape3D` owns its server RID and frees it on destruction.** Caching the
    bare RID and letting the Resource fall out of scope leaves every entry
    dangling, and a query against a freed shape reports no hits.

21. **Physics server RIDs are not reference counted.** A `BuildContext` dropped
    without `dispose()` leaks a space that keeps stepping for the life of the
    process. Tests collect their contexts and dispose them in `after_all`.

22. **A `CollisionShape3D` registers only as a *direct* child of a
    `CollisionObject3D`.** Nested under an intervening `Node3D` it is silently
    inert: no runtime error, no warning, and `body_get_shape_count` simply does
    not count it. This is why doc 05 §2's `ColliderRoot` had to go. A
    `ShapeCast3D` is **not** a shape owner and works anywhere in the tree, which
    is why `MotiveProbes` survived the same amendment.

23. **A body's shape indices are assignment order, and disabling preserves them
    while removal renumbers.** `PhysicsServer3D.body_is_shape_disabled` does
    **not** exist in 4.7; assert through the node or through the shape count.

24. **`RigidBody3D.mass = 0.0` is refused** by `ERR_FAIL_COND(p_mass <= 0)`,
    leaving whatever the body already had. `inertia = Vector3.ZERO` is *accepted*
    and means "derive it from the collision shapes" — the exact physics/visual
    coupling I-1 forbids. Floor both.

25. **`WorkerThreadPool.add_task` + `wait_for_task_completion` work under
    `--headless`**, including within a single `_process` frame.

26. **A test method that never awaits still runs entirely inside one
    `_process` callback,** so emitting `MatchClock.tick_started` by hand is
    deterministic and no physics frame interleaves into it. That is still true
    and is what every `tests/unit/` and `tests/integration/` file relies on;
    §3.36 is the opt-in exception.

27. **Two `class_name` scripts may call each other's statics.** `MassSolver` and
    `InertiaSolver` reference each other, as do `RotorDiscState` and
    `RotorSolver`. A cycle is only a problem for `extends` and for constant
    folding.

28. **~~The main world's `direct_space_state` answers nothing in this suite.~~
    Corrected in session 10: it answers, against a stale pose.** A body added to
    `get_tree().root` is registered in the space *immediately* and both
    `intersect_ray` and `intersect_shape` find it in the same frame. What it does
    **not** have is the transform you gave it after `add_child` — the broadphase
    keeps the pose the body was added with until a physics tick flushes it.
    `tests/physics/test_physics_frame.gd` asserts both halves.

    The distinction is not academic, and getting it wrong cost two sessions. "The
    space is empty" says *build your own space with `space_create`*. "The pose is
    stale" says *step once*, which is four lines. It is also the same fact as
    §3.19, seen from the other side. `SubViewport.world_3d` really is null
    headless even with `own_world_3d = true`.

29. **`RigidBody3D.linear_velocity` and `angular_velocity` round-trip through the
    server with no physics step**, so a test can set a chassis velocity and
    assert exactly what a severed island inherited from it — or impose a spin
    mid-test and watch a controller trim it.

30. **A member's initialiser may call a static function; a `const` may not.**
    `var _freeze_after_ticks: int = MatchClockService.ticks_for_seconds(4.0)` is
    legal and runs once per instance.

31. **`VisibleOnScreenNotifier3D.is_on_screen()` is always false headless, but
    its signals are drivable.** A class that *caches* the flag from
    `screen_entered`/`screen_exited` is testable where one that polls is not.
    The notifier's `aabb` is in its own local space.

32. **A `VisualInstance3D` under a `PhysicsBody3D` is not automatically an I-1
    violation.** The invariant is about geometry and about visual transforms
    driving physics. Doc 04 §6.2 records the reasoning.

33. **A `Callable` bound to a `Node`'s method survives being reassigned around.**
    `scheduler.island_sink = pool.on_island_severed` is the whole production
    wiring between doc 04 §5 and §6.

34. **The test runner does not fail on a GDScript runtime error, and the shell
    wrapper does.** `run_all_checks.gd` counts recorded assertion failures and
    nothing else. A null dereference, a failed `assert()`, or a call on a freed
    object prints to stderr, aborts the *method* it happened in, and lets the
    runner continue. `tools/ci/run_all_checks.sh` tees the run and fails on any
    `SCRIPT ERROR`/`ERROR` line. Two consequences: a planted fault that "passes"
    may have crashed rather than been tolerated, so read the log; and **an
    `assert()` is not a testable guard here** — it does not fail a check, it only
    prints, though the wrapper does then fail the run.

35. **`Vector2.limit_length` is the cone clamp, and `clampf` per component is
    not.** Two 14° deflections clamped independently compose to about 19.8° of
    resultant tilt; the same input through `limit_length` composes to 13.92°. The
    0.08° shortfall is the cost of composing two orthogonal rotations and is
    correct — a test asserting exactly 14° there is asserting something false.

36. **The suite can step physics, and three things had to be true at once.**
    `await physics_frames(n)` on a `TestCase` suspends a test until the engine has
    ticked. Making that work needed:
    - **`_process` must return `false`.** A `SceneTree` script's `_process`
      returning `true` *quits the main loop*. With a suspended run that meant the
      suite printed the handful of checks that had completed before the first
      suspension and **exited zero** — a silent partial pass, the worst possible
      failure mode for a test runner. The run ends at `quit()` inside `_run`.
    - **The runner must await the call.** A suspended GDScript call returns a
      `GDScriptFunctionState`, not its declared type. `GDScriptFunctionState` is
      not exposed to script and cannot be named, so the runner tests
      `pending is Object` and awaits `Signal(pending, &"completed")`.
    - **`_done` still guards re-entry**, because `_process` now fires on every
      frame the run needs rather than once.

    Both of the first two, planted as faults, are caught only by the **check
    count** — the suite reports `PASS` on every file it reached and exits zero.
    The sweep script compares against a baseline count for exactly this reason.

37. **Godot applies no gyroscopic term.** A free `RigidBody3D` with three
    distinct principal moments, spun about its intermediate axis, holds its
    angular velocity constant to seven significant figures for five simulated
    seconds. The server integrates `I_diag ω̇ = τ` and nothing else. This
    contradicts doc 05 §3.4's original premise; see §4.

38. **Damping is a project default and it is not zero.** A `RigidBody3D` used to
    assert `Δv = F·dt/m` needs `linear_damp_mode = DAMP_MODE_REPLACE` with
    `linear_damp = 0.0`, and the same for angular. Measuring **from rest** is
    better still: the damping term is proportional to the current velocity, so
    from zero it contributes nothing and the equality is exact rather than
    approximate. `test_motive_force_application` matches to 1e-4.

39. **`Vector3.FORWARD` is `(0, 0, -1)` and `Vector3.BACK` is `(0, 0, +1)`.**
    Using the wrong one when searching the orientation group for the index that
    carries a part's `-Z` drive face onto the Assembly's `+X` silently returns
    orientation 0, and every placement then fails with a mating rejection that
    looks like a data problem.

40. **`Input.action_press` and `action_release` work under `--headless` and are
    exact.** `Input.action_press(action, 0.4)` makes `get_action_strength` return
    0.4 with no deadzone remapping — the deadzone declared on the action applies
    to device events, not to a programmatic press. This is what lets
    `tests/unit/test_control_system.gd` drive the real input map rather than
    construct `InputEvent`s, and it means an input mapping is unit-testable with
    no window, no device, and no scene. Release everything at the **top** of each
    test: the runner sorts the methods, and a test that fails part-way through
    would otherwise leave a key held for the next one.

41. **`RigidBody3D.freeze = true` makes a clean static test platform**, and it
    keeps its collision shapes, its transform, and its visibility to every query.
    A frozen body still gets hit by a swept ray and still resolves damage; what it
    stops doing is responding to impulses. That is what `tests/physics/test_duel.gd`
    uses to take §4.11's recoil out of a test whose subject is everything
    downstream of the muzzle. **Freeze after the settle, not before** — a body
    frozen in mid-air never finds its suspension and fires from a pose no real
    build would be in.

42. **A test method's name decides when it runs, and `before_all` is the only
    place a pre-condition can be measured.** The runner sorts methods, so
    `test_the_two_assemblies_are_built_and_separate` runs *after*
    `test_they_close_shoot_and_one_of_them_wins` — by which time one of them has
    driven several metres and the separation it was asserting is gone. A property
    of the fixture is recorded when the fixture is built, not when a test happens
    to ask.

43. **A destructive fixture needs a run-once guard, not a per-test rebuild.** The
    duel cannot be repeated: an Assembly whose Core Module has gone cannot be put
    back. `_fight()` runs on the first call and returns immediately after, which
    is what lets five test methods each assert one thing about the same run
    instead of one method asserting five things and reporting only the first
    failure.

44. **This suite is not bit-reproducible run to run once several bodies are in
    one space.** Two consecutive runs of `tests/physics/test_family_duels.gd`
    gave 23 and 25 rounds from the same Assembly, and the five-a-side gave 222
    rounds and three kills on one run and 375 and two on the next. Nothing
    stochastic differs — every generator is seeded (Invariant I-9) — so the
    divergence is float ordering inside the physics server across many contacts.
    **Assert a range, a direction, or a pigeonhole in a multi-Assembly test, and
    never an exact count.** A single Assembly on a slab still reproduces exactly,
    which is why every unit and integration test is unaffected.

45. **Every `CombatArena` builds its slab and its Assemblies at the same world
    coordinates, because they all hang off the one [SceneTree] the autoloads live
    in.** Two arenas open at once put the second engagement inside the first
    one's wreckage: rounds strike hulls belonging to a finished fight, and the
    bus delivers one arena's `part_damaged` into the other's counters. Every
    number either of them records is then a mixture. Open exactly one at a time
    and close it before the next — `test_family_duels._open_arena` asserts it.

46. **`RigidBody3D.freeze = true` on a hovering Assembly is not the same
    simplification as freezing a wheeled one.** A frozen wheeled build keeps the
    pose its suspension settled into; a frozen rotary one keeps whatever pose the
    autopilot happened to be holding, and the two Assemblies stop pushing each
    other around. Session 15's overpenetration grind reproduces with both
    Assemblies live and **stops** reproducing the moment either is frozen, which
    cost most of an hour before it was noticed.

47. **A physics fixture with a small margin is a fixture that fails somewhere
    else.** `tests/physics/test_duel.gd` needed 9.5° of depression against an
    authored 8°, and passed alone while failing inside the suite — the two ran
    the same code and differed only in how much simulation had happened before
    them. §3.44's float ordering is enough to move a frozen hull's attitude by a
    degree or two, and a fixture with two degrees of margin flips on it. **When a
    test passes in isolation and fails in the suite, look for the margin before
    you look for the contamination**; both are real here and they present
    identically.

48. **A leaked arena is invisible until it eats something.** Session 16's drift
    file left four Assemblies standing at the origin because it closed its arena
    in `after_all` rather than as soon as it had its measurement. The next file
    along built its engagement inside them, and every round the shooter fired
    stopped on a hull belonging to a fight that had finished — reported as "the
    shooter fired and nothing came apart", which reads as a damage bug and is
    not one. Close an arena the moment its record is taken; leave `after_all` as
    the guard for a run that failed part-way through (§3.45).

49. **`wrapf(x, -PI, PI)` is half-open and `clamp_yaw` uses it for a full-circle
    mount.** A bearing of exactly `+PI` comes back as `-PI`, so an equality test
    between the clamped and unclamped yaw fails for a target dead astern and
    only for a target dead astern. Everything else in `(-PI, PI)` round-trips to
    within 1e-9. It is a one-value hole and it is the kind that surfaces once a
    year in a bug report nobody can reproduce.

50. **Headless Godot still paces its main loop against the wall clock, and
    `Engine.time_scale` will not fix it.** This is the single most expensive
    engine fact in the file, because it silently cost every session before this
    one a factor of twelve on every suite run and every fault sweep.

    Measured on 4.7.1 in this repo, with a probe that does nothing but
    `await physics_frame`:

    | Configuration | 600 bare frames | Effective rate |
    |---|---|---|
    | default headless | 9876 ms | 60.8 fps |
    | `Engine.time_scale = 20` | 10003 ms | 60.0 fps |
    | `--fixed-fps 60` | 4 ms | 152 000 fps |
    | `--fixed-fps 60 --disable-render-loop` | 3 ms | 184 000 fps |

    So `tests/physics/` was never compute-bound. Its wall time was tick count
    divided by sixty — a 900-tick engagement cost fifteen real seconds no matter
    how little work was in it.

    **`Engine.time_scale` is the trap.** It is the obvious answer and it is wrong
    twice: it produced *no* speedup at all, and the delta handed to
    `_physics_process` went from 0.016667 s to **0.333333 s**. It scales the
    delta, not the frame count. At that step a 940 m/s round advances 313 m per
    tick, every spring in doc 05 integrates to nonsense, and Invariant I-9's
    determinism is gone. Anything that changes `delta` is disqualified here on
    principle, not just on measurement.

    **`--fixed-fps 60` is the right lever precisely because it changes nothing
    the simulation can observe.** It disables real-time synchronisation and lets
    the loop advance as fast as the CPU allows; the physics step stays exactly
    1/60. Verified rather than assumed: a full real-time run and a full
    `--fixed-fps` run produce 4342 checks each and byte-identical engagement
    output — same 207 / 900 / 291 tick duels, same 684-tick brawl, same kill
    order, same pool peak. `tools/ci/run_all_checks.sh` passes it, so the sweeps
    inherit it.

    `--disable-render-loop` adds nothing worth having on top of it in headless.

51. **`intersect_shape` ignores `PhysicsShapeQueryParameters3D.motion`, and so
    does `collide_shape`.** Only `cast_motion` honours it, and it answers with a
    pair of fractions along the motion rather than with the set of bodies it
    passed through — so it cannot serve any query whose purpose is the target
    set. Measured three ways on 4.7.1: a sphere parked 3 m from a hull with
    `motion` carrying it onto the hull reports **zero** hits from
    `intersect_shape` and **zero** contacts from `collide_shape`, while
    `cast_motion` on the identical parameters returns `[0.768, 0.773]` — it
    plainly knows the hull is there and the other two plainly do not ask.

    This cost doc 07 §15.3 four sessions. The section specified a swept query,
    the implementation wrote one, and the sweep silently degenerated to a static
    test at the segment's start — which is survivable — while everyone reading
    the code believed the volume between two samples was covered, which is not.
    **A parameter that the engine accepts and ignores is worse than one it
    rejects**, and the only defence is to measure the query rather than to read
    the field name.

52. **A `CapsuleShape3D` runs along its own local +Y, and `height` is its total
    extent including the caps.** A capsule meant to lie along a -Z convention —
    doc 07 §7.2's muzzle axis, which §15.2's edge shares — needs a quarter turn
    about X in front of it. Without the turn it stands vertically, which on a
    melee edge puts a 2.4 m blade through the wielder's own hull and out of the
    top, and the query is not empty, it is *wrong*. Measured: a capsule offset
    1.0 m along +Y from a hull hits it and one offset 1.0 m along +X does not;
    after `Basis(Vector3.RIGHT, PI * 0.5)` the +Z offset hits and +X still does
    not.

53. **`free()` on a node with a `WorkerThreadPool` task in flight is *refused*,
    and the node survives.** A task executing one of the node's own methods holds
    a call on it, so `Object::free` reports "Object is locked and can't be freed"
    and returns. The node stays in the tree, connected to the bus, holding every
    space and body the file built.

    **`_exit_tree` is not the escape hatch, because `free()` never reaches it.**
    `MassRecomputeScheduler._exit_tree` has joined its task since it was written;
    the lock check happens first. `remove_child` *does* reach it, so the teardown
    order that works is remove, then free.

    Session 18 saw this **once in nine identical runs**: twelve leaked
    `GodotBody3D`/`GodotArea3D`/`GodotSpace3D` RIDs out of
    `tests/integration/test_mass_recompute.gd`, and then
    `test_ground_assembly` — which builds at the origin — settling its Assembly
    on top of the wreckage and reporting **22 failures** about suspension travel,
    load distribution, braking and steering. Every one of them read as a
    locomotion regression and none of them was.

    Two things to carry from it. **An intermittent leak presents as a physics
    defect in an unrelated file**, which is §3.48 again with a worse disguise,
    because the leaking file passes. And **the wrapper is what caught it**
    (§3.34): the leak prints an engine error and records no failure, so the
    `.gd` runner alone would have reported a green partial and moved on.

54. **A tick count in a multi-Assembly physics test measures the *suite*, not
    the fight.** Session 20's largest finding and the one most likely to waste
    somebody's afternoon, because it presents as a combat regression caused by a
    change that cannot possibly have caused one.

    Adding `tests/integration/test_part_visuals.gd` — which spawns eight
    two-part Assemblies, asserts things about their meshes, and frees them all
    before any physics test starts — took `test_team_engagement`'s twenty-a-side
    brawl from running out its 1200-tick window to finishing in **316**.
    Reproducibly: three runs in a row, same number. Then reproduced again from a
    **control file that did nothing but spawn those eight Assemblies and free
    them**, with no meshes, no `SubsystemGate` toggle, and no debris body.

    It is not a leak. It was bisected against a clean worktree at the previous
    commit, group by group — the orientation refactor, `project.godot`, the
    runtime's visual spawn, `src/ui/`, and finally the test file — and every
    group but the last left the brawl passing. The mechanism is JULES.md §6.6's,
    applied one level further out than anyone had applied it: once twenty rigid
    bodies share a space, the solver's float ordering depends on the allocation
    history of the **whole process**, so any earlier file that creates and
    destroys bodies shifts the outcome of a later engagement.

    **So a tick count is not a property of the engagement.** `e.ticks >
    ENGAGE_TICKS / 2` was not measuring the fight; it was measuring what the
    suite happened to allocate before it. Re-asserting the new number would have
    moved the fragility to whoever added the next file. The bound is now
    `BRAWL_MIN_TICKS`, twice the documented 91-tick pre-bound figure, with the
    whole story in a comment at the constant.

    The general rule, and it applies to every file in `tests/physics/` that
    fights more than one Assembly: **assert directions, ranges, and orderings.
    Never a count, a duration, or an exact value.** §9's conventions already said
    this; what was missing was the knowledge that "an unrelated file was added"
    is one of the things that moves the number.

    **Session 23 found the sharper version: a *direction* can move too.**
    `test_ambulatory_drift` compared the sign of a counter-steered walker's
    heading against a neutral one's, and adding one engagement file flipped the
    neutral case from +169.6° to −76.1° while leaving both **commanded** runs
    byte-identical. Only the uncommanded walker moved, because it is the one with
    no demand to dominate its accumulated asymmetry. So the rule extends: a
    quantity with no commanded input driving it is noise with a magnitude, and a
    comparison *against* such a quantity is a comparison against the suite. §4.36
    has the repair, which was to compare the two commanded runs with each other.

55. **Godot's Movie Maker mode is how you look at this game from a headless
    box.** `xvfb-run -a -s "-screen 0 1600x900x24" tools/ci/godot.sh --path .
    --rendering-driver opengl3 --resolution 1600x900 --write-movie <dir>/f.png
    --quit-after 240` renders a numbered PNG per frame through Mesa's llvmpipe
    and exits on its own. It is slow — about 7% of real time, so 240 frames cost
    a minute — and it is the only way anybody has actually *seen* this project.

    Two details. `--write-movie` with a `.png` extension writes a sequence
    rather than needing ffmpeg, and the frames are the engine's own, so what you
    read is what a player would see. And Movie Maker pins the frame rate, so a
    capture is deterministic in a way an interactive session is not — which
    makes it usable for a before/after on a camera or a HUD change.

56. **`PhysicsDirectSpaceState3D.cast_motion` answers `[1, 1]` for a clear path
    and `[0, 0]` when the shape starts already overlapping.** Both are ordinary
    answers and neither is an error, so a caller that treats "safe fraction 0" as
    a failure will behave differently from one that treats it as "you are inside
    something". The chase camera treats it as the latter and clamps to a minimum
    distance, because the alternative is `look_at` with a zero-length direction,
    which is an engine error every frame rather than a bad picture.

57. **CSG evaluates fully under `--headless`, but `bake_static_mesh()` answers
    `null` on the frame the tree is built.** Both halves matter for doc 10's
    bake, and the second half is what wastes the afternoon: a bake script that
    constructs a `CSGCombiner3D`, adds it to the tree, and bakes in the same
    function gets `null` from every case — primitives, imported meshes,
    intersections, everything — and reads exactly like "CSG does not work
    headless". It does. Evaluation is deferred to the server, and the tree
    answers on the **next** `_process` frame. Measured across every case in this
    session's probes: **first correct answer at frame 2, never later.**

    So the bake is a frame-counter script in the §3.2 shape — build on frame 1,
    bake on frame 2 — and **not** an `await process_frame` inside `_process`,
    which does not let the server run and returns `null` just like frame 1 does.
    Extraction once evaluated is free: a re-bake of an already-evaluated
    25-operand tree measured **0.001 ms**, because the boolean result is cached
    and `bake_static_mesh` only copies it out.

58. **A non-manifold CSG operand is silently discarded, not rejected.** The
    single most expensive fact in this section for anyone landing doc 10, and it
    is the exact opposite of what the document assumes.

    Godot 4.4 replaced the CSG implementation with the Manifold library, and
    Manifold's contract is that operands are watertight. A non-manifold one does
    not raise, does not warn, and does not fail the bake — it **contributes
    nothing and the tree bakes cleanly without it**. Measured three ways: an
    open two-triangle sheet unioned with a 1 m box bakes to exactly the box; a
    box with one face deleted bakes to nothing at all; and a 9 408-triangle
    cylinder whose seam vertices differ by the `2.4e-16` between `sin(0)` and
    `sin(TAU)` bakes to nothing, taking its twelve window cuts down with it.

    **The failure mode is therefore a missing wall in an otherwise perfect
    building, with a green build log.** Doc 10 §3.1 says non-manifold geometry
    "is reported as a build error, not silently accepted"; that is a statement
    about a `ManifoldChecker` the repository has to write, not about anything the
    engine does. And the check has to run on the **input operands**, not on the
    bake output, because a dropped operand leaves output that is impeccably
    manifold and simply missing a storey.

59. **The manifold test must weld by position first; index-based edge counting
    produces false alarms on Godot's own primitives.** The obvious validator —
    count how many triangles use each index pair, demand exactly two — reports
    Godot's `BoxMesh` as having **24 boundary edges**, because a box's 8 corners
    are 24 vertices once split for UVs and normals. The engine bakes that box
    perfectly. Manifold welds by position internally, so the validator must too.

    Quantise each position to a grid, weld, then count edge uses: `boundary`
    (used once — a hole) and `excess` (used three or more — a fin or a duplicate
    face) must both be zero. Degenerate triangles are *not* disqualifying —
    `SphereMesh` ships 128 of them at its poles and bakes fine — so they are
    worth reporting and wrong to reject on. At a `1/4096 m` quantum this
    predicate agreed with the engine on **six of six** cases: `BoxMesh`,
    `SphereMesh`, a welded grid box, the float-seam cylinder, the open sheet, and
    the holed box.

60. **`CSGMesh3D` takes an arbitrary `ArrayMesh` as a first-class operand,
    including under `OPERATION_INTERSECTION`.** A 3 m imported solid minus a
    cylinder bakes correctly; the same solid intersected with a box cell returns
    exactly the half, which is doc 10 §3.2's `CsgBakeUtil.intersect_with_box`
    working on imported geometry rather than on a CSG primitive tree. A
    6 912-triangle operand with twelve subtractions bakes in the same single
    frame as a bare `CSGBox3D`.

    This is what makes a DCC-authored Static Volume viable: **doc 10 §2.1's
    "permitted but discouraged" reading of `CSGMesh3D` is a performance
    judgement from before the Manifold rewrite, and the measurement no longer
    supports it.** Whether to amend it is §8 item 18.

    One trap alongside it: `CSGShape3D.bake_collision_shape()` returns a
    `ConcavePolygonShape3D`, which Invariant I-1 forbids on anything dynamic. It
    is usable as an editor reference and for nothing else; doc 10 §3.4 already
    generates Section colliders from partition geometry and is right to.

61. **`HeightMapShape3D` stores `map_data[z * width + x]`, sample zero at the
    shape's negative corner, one unit per sample, centred on the shape origin.**
    There is no sample-spacing property — `map_width`, `map_depth` and `map_data`
    are the whole API in 4.7.1 — so doc 09's 0.5 m spacing is a scale on the
    shape node, and the Y component must stay 1 or heights stop being metres.
    Verified by raying a field of `h = 0.1·x_index + 0.01·z_index`: `x=-64,z=-64`
    answers 0.0 and `x=+64,z=+64` answers 14.08, exactly as that layout predicts.
    A 129-sample field at 0.5 scale spans 64 m, confirmed by a hit at 31 m and a
    miss at 33 m.

    Costs are comfortable: building a 129×129 `PackedFloat32Array` is 0.565 ms
    and assigning it to `map_data` is 0.065 ms, against doc 09 §11's 1.40 ms
    budget for the pair.

62. **A shape reachable only through a physics RID is freed when the last
    reference drops, and the body then silently stops colliding.**
    `PhysicsServer3D.body_add_shape(body, shape.get_rid())` keeps the RID and not
    the resource. A `HeightMapShape3D` held in a local variable is destroyed when
    the function returns, and every subsequent query against that body answers
    nothing — which reads exactly like §3.19's transform-before-shapes fault and
    is a different bug. This cost a probe run: rays that should have hit a ramp
    at `y=64` all missed, while a second body built inside the querying function
    worked perfectly. `GroundChunk` holds `collision_shape` for this reason.

63. **Godot 4 exposes no `RWLock` to GDScript.** `Mutex`, `Semaphore`, `Thread`
    and `WorkerThreadPool` are the entire threading surface. Doc 09 §8.1 rule 3
    specified an `RWLock`; the document is amended and `GroundArray.lock` is a
    plain mutex. At this access pattern — writes only inside a deformation solve,
    readers a handful of sample lookups per contact per tick — serialising two
    readers costs less than a GDScript-level reader-writer lock would.

62. **The suite's file order is an input to every measurement in
    `tests/physics/`.** Not the tick counts alone — fact 54 already says that —
    but the measured *quantities*. Hoisting one physics file to the front of the
    run leaves the check count identical at 5130 and moves
    `test_family_duels`' single-round recoil measurement from 1.069 m/s to 0.916
    and its pitch from 0.012 rad/s to 0.119, which is enough to fail an assertion
    that passes in discovery order.

    The consequence is a tool that does not exist: **there is no way to reorder
    or subset a run, and there deliberately never will be.** A sweep that skipped
    ahead to the file expected to catch its fault would manufacture failures and
    report them as faults being caught. Truncating a run is safe, because it
    cannot change anything that already ran; reordering is not. `--fail-fast`
    exists and `--first` was built, measured, and deleted.

63. **A planted fault can wedge the suite, and `subprocess.run` with no timeout
    turns that into a sweep that never returns.** Fact 2 is the mechanism: a
    `SceneTree` script that never reaches `quit()` idles forever with its output
    buffered, and a fault that leaves the runner awaiting a coroutine which never
    resumes does exactly that. `sweeplib.py` starts each run in its own session
    and kills it by **process group** on a timeout — killing the shell alone
    leaves the engine running, because `run_all_checks.sh` pipes it through
    `tee`. A timeout is reported as `CAUGHT-HUNG`, which is a true verdict: a
    fault that wedges the suite has certainly been noticed.

64. **A hard-coded baseline in a sweep script rots silently, and rots in the
    direction of reporting success.** All three sweeps carried a check count with
    a comment telling the next person to update it. Two were stale by hundreds of
    checks — at which point `checks != BASELINE` is true for every fault and the
    sweep reports `CAUGHT` for all of them, including the ones nothing noticed.
    A number that must be maintained by hand to stay honest, in a file run once a
    session, does not stay honest. It is now measured from a clean run and only
    when some fault records no failures at all, which is the only case it
    decides; a declared value is kept and checked against the measured one, so a
    stale constant prints a warning instead of inverting the result.

65. **A 4.7 MB project copy is a cheaper way to parallelise than anything
    clever.** The suite is single-threaded and CPU-bound, so several faults can be
    swept at once by giving each worker a `cp -a` of the project under `/tmp` and
    pointing it at the original checkout's engine binary through
    `SYNDICATE_GODOT_DIR`. Each worker runs the identical full suite in the
    identical order, so unlike every other accelerant that was tried this one
    changes no measurement at all. A full sweep went from about twenty minutes to
    two.

66. **`DisplayServer.keyboard_get_keycode_from_physical` is unimplemented
    headless, and it reports that by pushing an engine error rather than by
    returning a fallback.** "Not supported by this display server" once per call,
    which the suite wrapper fails the whole run on (fact 34) — so a HUD label
    that resolves a key glyph turns every green run red. The physical keycode is
    the right fallback, because it is the US layout that doc 11 §7.1's table is
    written against. `InputPrompt._layout_keycode` branches on
    `DisplayServer.get_name() == "headless"`, which is the same guard
    `InputMethodService._set_method` already needed for `Input.mouse_mode`.

    The general shape is worth more than the call: **a `DisplayServer` method
    that is meaningful only with a window may be a hard error headless rather
    than a no-op**, and the suite is the only place that difference is visible.

67. **A freed object passed into a typed parameter is a type error before the
    function body runs, so an `is_instance_valid` guard inside it can never
    fire.** "The Object-derived class of argument 1 (previously freed) is not a
    subclass of the expected argument class" — the check happens at the call
    boundary. Iterating an `Array[Node]` that holds a freed entry fails the same
    way, for the same reason.

    So a teardown helper cannot be written as "call it on everything and let it
    sort out what is already gone". The pattern that works is for the helper to
    **drop its own handle**: `_release` erases the entry before freeing, and
    `after_all` drains what is left, which is by construction still live.

68. **A GDScript lambda captures by value, so a closure that writes to a local
    outside it writes to its own copy.** A test that passed
    `func(i, k): seen = k` as a callback and then asserted on `seen` asserted on
    the value `seen` started with, in a run where the callback had fired
    correctly every time. It presents as "the callback was never called", which
    is the one explanation it rules out. Use a small `RefCounted` recorder, or an
    `Array`/`Dictionary` — those are reference types, and a closure writing
    *into* one is visible outside it.

69. **`Object.free()` on a node that is currently emitting a signal you are
    handling tears down the object whose method is running,** and the engine
    reports it as `Condition "p_child->data.parent != this" is true` — a
    parenting error naming neither the node nor the signal. The screen simply
    does not change.

    Every transition in `ShellRoot` arrives this way, because a screen is left by
    pressing something on it. `remove_child` and then `queue_free()` is the
    pattern, and both halves matter: removal is immediate and runs `_exit_tree`,
    which is where a screen joins its worker tasks and disposes its contexts
    (fact 53 is why that has to happen before anything is freed), and deletion
    lands at the end of the frame by which time the emission has returned. The
    removal is what makes the deferral safe rather than merely later — a node out
    of the tree can do nothing further whether it has been deleted yet or not.

70. **`Input.mouse_mode` is a hard error headless rather than a no-op**, which is
    fact 66's general shape applied to the property every screen wants to set. A
    screen that assigned it directly could not be constructed in a test at all,
    because the suite wrapper fails a run on any engine error (fact 34). The
    guard belongs in one place — `InputMethod.set_mouse_mode` and
    `InputMethod.mouse_mode` — which that autoload already needed for its own
    use, and two owners of one branch is how one of them drifts.

71. **A `ConfirmationDialog` works fully under `--headless`, and that is not
    obvious given facts 66 and 70.** A `Window` subclass sounds exactly like the
    kind of node that needs a display server, and the two facts above establish
    that a `DisplayServer` method meaningful only with a window is a hard error
    headless rather than a no-op — which the suite wrapper fails a run on. So the
    tempting move is to build a `Control` panel standing in for doc 11 §4.2's
    `ConfirmDialog` and record an amendment.

    Measured instead: `root.gui_embed_subwindows` is true, `popup_centered`
    reports `visible = true`, `get_ok_button()` answers, and `hide()` reports
    `visible = false`, with no engine error at any step. The dialog is an
    embedded subwindow drawn by the viewport, so no platform window is involved.
    A screen that raises one is constructible in a test.

    The general shape, and it is the counterweight to facts 66 and 70 rather
    than a contradiction of them: **whether a node needs the display server is a
    question about what it draws with, not about what it inherits from.** Probe
    it — a `--script` `SceneTree` that touches no autoload is four lines
    (fact 3).

72. **A tyre friction model is stiff enough to be unstable at a 60 Hz tick, and
    it hides that by saturating rather than diverging.** Measured in session 32
    on doc 05 §7.4's contact integration, and it is the most expensive thing in
    this file for anyone touching the motion layer.

    The friction reaction opposing a contact's spin is a very steep function of
    that spin near the rolling condition. Differentiating §7.2's curve through
    §7.1's two divisions:

    ```
    dF/dω = μ·N · f'(0) / κ_peak · r / max(|v_long|, V_REF)
    f'(0) = C·B / sin(C·atan(B)) = 12.415
    ```

    At the shipped all-road figures — `I_c = 8.5 kg·m²`, `r = 0.5 m`, `μ = 1.05`,
    5 kN of load — that is `2.9e5 N per rad/s`, giving `dω̇/dω ≈ −1.7e4 s⁻¹`.
    Explicit Euler is stable below `2/1.7e4` = **117 µs**. The tick is 16.7 ms.
    **The step is 142× outside its own stability limit**, and the lateral axis is
    worse, because §7.1 floors its denominator at `V_REF` and a hull creeping
    sideways at 0.05 m/s already draws most of a friction budget.

    **It does not blow up, and that is why nobody found it for thirty-one
    sessions.** The Pacejka form saturates past its peak, so the excursion is
    bounded and the contact settles into a limit cycle: measured at ±4.7 rad/s
    reversing every single tick under a build standing still, against a
    free-rolling 0.036 rad/s.

    Three things to carry from it. **An unstable step in a saturating model
    presents as noise, not as a crash** — look for it wherever a force is a steep
    function of the state it is integrated against. **The chatter was destroying
    lateral grip by about 37×**: a combined slip of ±20 puts `sy/s` near zero, so
    every handling constant in this project was tuned against a machine that
    could not corner. And **stabilising it is not a damping term** — see fact 73,
    which is the part that cost the second session.

73. **Stabilising a stiff contact: the two ways to do it wrong, both measured.**
    Fact 72 is the defect; this is the repair, and it is recorded separately
    because both wrong turns look correct on paper and each costs most of a day.

    **Wrong turn one: damp the rate.** Take `I_c ω̇ = τ − r·F(ω)` implicitly in
    `ω`, so the stiffness lands in the denominator as `I_c + dt·r·k`. It is
    unconditionally stable, it kills the limit cycle exactly as intended, and it
    is wrong, because the fictitious inertia that damps the residual also resists
    a contact **genuinely spinning up with an accelerating hull**. Measured: full
    throttle reached **0.20 m/s**. The cure is to step the quantity the friction
    actually depends on — the slip velocity `u = ω·r − v_long` — and reconstruct
    `ω = (v_long + u)/r` afterwards. The contact then follows the hull for free
    instead of having to be integrated into following it.

    **Wrong turn two: use the tangent at zero as the stiffness.** It is the
    natural choice and the reasoning is sound as far as it goes: §7.2's curve is
    steepest at the origin, so that slope bounds every other slope, and an
    implicit step is stable for any bound at or above the true one. What the
    reasoning omits is the cost of overestimating. Measured on the shipped build,
    the tangent over-damps by a factor of **317**, so a contact knocked to a slip
    of −0.05 m/s takes forty ticks to recover and drags several kilonewtons the
    whole time — and the Assembly does not accelerate at all. The chord
    `|F| / |u|` is the average slope actually traversed, is never above the
    tangent, collapses to the right small number past the peak, and costs one
    division of two quantities already in hand.

    The general shape, and it is worth more than the contact: **an implicit
    factor is a statement about how fast the state may move, so an overestimate
    is not conservative — it is a brake you did not intend to fit.** Bound it by
    what the system actually did over the step, not by the worst it could ever do.

74. **The reference build is nose-heavy enough to stand on its front axle, and has
    been for the life of the project.** With the shipped starter settled on level
    ground, the two **rear** contacts report zero normal load, permanently.
    Nothing noticed, because fact 72's chatter produced enough force anyway — and
    it is what makes fact 73's repair look broken, since a correct integrator on a
    two-wheeled stance gives 0.09 m/s under full throttle and a porpoising hull.

    The cause is arithmetic, not mystery. Against a 1.50 m wheelbase the centre of
    mass sits 0.40 m aft of the front axle, which is a **73/27** static split —
    940 kg on the front pair and 342 kg on the rear — and
    `eff.ballistic.autocannon_30.t3`'s own centre is a further **1.12 m forward of
    the front axle**. A 2.25 m gun cantilevered a metre past the front wheels of a
    vehicle whose wheelbase is 1.50 m is the whole finding, and it is also why a
    braking or rammed opponent pitches onto its barrel.

    **Two traps around it.** The right-hand wheel cells are authored one cell
    forward of the left — `(28, 3, 21)` against `(19, 3, 22)` — which looks
    exactly like doc 02 §10's old mirror off-by-one and is not: squaring them up
    fails `test_the_shipped_starter_is_its_own_mirror` immediately, because the
    mirror is correct and the wheel's pivot is off-centre, so cells that are
    symmetric are metres that are not. And the whole Assembly is **39 kg/m³** of
    its bounding box — a fifth of balsa — so every figure doc 05 §6.4 retunes
    against `rated_load_kg` is being asked about loads the build never reaches.

75. **A part table can be internally consistent and still be the wrong shape, and
    only a picture shows it.** Measured after a capture prompted the question
    "why is the gun bigger than the vehicle": at `LATTICE_UNIT_M = 0.25`, the Core
    Module is 5 cells long and the autocannon is 9, so the weapon is **50% of the
    reference build's length and the cabin 28%**. Every validator passes, every
    mass is plausible in isolation, and the silhouette is a gun with a car
    attached.

    The lesson is the general one and it is cheap to act on: **the registry has no
    check that compares one part against another**, so proportion is the one
    property of the part table that no test can see and that a single frame of
    capture answers immediately. Ratios worth watching, all derivable from
    `occupancy_cells` and `mass_kg` with no engine at all: weapon length against
    hull length, cabin against hull, wheel diameter against ride height, and mass
    against bounding-box volume.

76. **`author_appendage_parts.gd` must be re-run after `author_locomotion_parts.gd`,
    and the failure is silent.** The appendage script *re-authors* an existing
    part: it loads `eff.melee.beam_edge.t4` and replaces its attachment nodes
    with a single `GRIP` hilt on `+Z`, so the edge can be held and cannot be
    welded to a roof. `author_locomotion_parts.gd` writes the same key from
    scratch with a `FACE_MALE` node on `-Y`. Run the locomotion script alone and
    the edge quietly goes back to being a deck mount — no error, no warning, and
    the registry validates either way.

    The symptom is a held-weapon fixture that can bolt a sword to a Structural
    Component, which reads as a polarity bug in the validator. **The authoring
    order is `first` → `combat` → `locomotion` → `appendage` → `chassis`**, and
    the general shape is worth more than the order: a generator that reads a file
    another generator writes is order-dependent, and nothing in `tools/` declared
    that. `author_chassis_parts.gd` reads nothing and is safe anywhere, which is
    why it is last rather than because it has to be.

    **Session 44 walked into it twice, and the second time is the interesting
    one.** The first was landing the vehicle remodel; the second was a single
    follow-up re-run of `author_locomotion_parts.gd` to give a limb its foot,
    with this fact already written down, already read that session, and already
    cited in the file being edited. It still cost a full suite run, surfacing as
    `polarity_mismatch` on a melee blade three hundred lines into a log.

    **So the repair is `tools/author_all_parts.sh` and not another sentence
    here.** A fact that has to be remembered at the moment of acting is a fact
    that will be forgotten, and the thing to do with a known-order pipeline is to
    write the order down somewhere the computer reads it. Re-author through the
    script; the individual `--script` invocations remain for debugging one
    generator.

77. **A driver that has a target, is pointed at it, and is demanding full
    throttle is not a tactics defect — read the contacts, not the law.** Session
    36's largest finding, and it had been recorded as an AI regression through
    two previous sessions.

    `test_ai_engagement` showed an attacker turning to face its target perfectly
    and then never closing: 44.2 m to 45.4 m, zero rounds. `approach_throttle`
    returns 1.0 at that bearing, `arrival_brake` returns 0.0, and the same build
    drives at 16 m/s elsewhere — so every reading of it was "something between
    having a target and moving is not firing".

    Twenty lines of instrumentation inside `CombatArena.engage` — throttle, brake,
    steer, target id, closure, speed, range, bearing, **body height, grounded
    contact count and the four normal forces**, every fifteen ticks — answered it
    on the first run. The driver was faultless the whole way. The hull climbed
    from 0.93 m to 1.63 m while its contacts unloaded to zero one at a time, then
    landed on a 32 kN spike and stopped dead with no probe touching anything. It
    had not declined to fight; it had taken off.

    Two things to carry. **The three fields that answered it were the three
    nobody prints** — height, grounded count, and per-contact normal force — and
    every field that *was* being printed said the system was working. And the
    cause was fact 72's contact instability being *energised by drive torque*, so
    an unstable integrator does not only add noise: it pumps.

78. **An inertia grows as the square of the extents, so scaling a part table by
    mass is not scaling it uniformly.** `core.command.compact.t2` went from
    4×3×5 cells at 380 kg to 6×4×13 at 1800 — mass ×4.7 — and its box tensor
    about `Y` went from 81 to 1922 kg·m², which is **×24**.

    Every rotational authority in the project is a torque over that inertia, so
    all of them fell by about a factor of six at once, and three unrelated
    fixtures measured the same collapse from three directions: doc 05 §7.6's
    corrective yaw brake took 2% off an imposed spin where it took 60%, the
    rotary autopilot could no longer hold a hover, and doc 01 §10.5's autocannon
    stopped being able to spin its own hull — which is the one that went the
    right way, and which inverted both of `test_drive_and_shoot`'s
    asserted-as-a-defect methods.

    So when a mass moves, the things to re-derive are not only the forces that
    hold it up. **Anything that turns it has to be re-derived against the square
    of the size, not against the mass**, and a fixture window sized for the old
    inertia measures nothing on the new one.

79. **Only two fields on a `CoreModuleProfile` are read by the simulation, and
    the four a balance change would reach for first are not among them.**
    `mount_budget` and `power_capacity_pu` reach `BuildBudgetLedger` and decide
    what may be placed. `speed_cap_mps` reaches `MotiveSystem._speed_cap_mps`,
    which for the ambulatory family is then floored by
    `GaitSolver.top_speed_mps` — 2.42 m/s on the shipped limb — so a chassis cap
    anywhere above that is inert. `mass_tolerance_kg` and `control_authority`
    are read by `AssemblyStatPanel` and `PartInspector` and by nothing else at
    all; `operator_seat_offset_m` and `respawn_integrity_fraction` are read by
    nothing.

    Worth knowing in both directions. Authoring a new chassis is cheap, because
    most of its published figures cannot destabilise anything. And a session that
    tries to *tune* a family through its chassis figures will change a number on
    a card and nothing else — the levers that move an Assembly are on the Motive
    Assembly, the Prime Mover, and doc 05's constants.

    What a new Core Module *does* move, and it moves it hard, is the mass and the
    inertia — fact 78. `core.ambulatory.strider.t3` is 450 kg lighter and four
    cells shorter than the chassis the walking recipe used to borrow, and every
    number in `test_ambulatory_drift` changed: uncommanded yaw drift 140° → 92°,
    standing drift 51° → 18°, standing lean 0.999 → 0.989 of upright.

80. **A physics fixture in `tests/physics/` can be byte-reproducible even with
    four Assemblies in the space, and checking is four minutes.** Fact 44 says a
    multi-Assembly test is not reproducible run to run, and fact 54 says a tick
    count measures the suite. Both are true and neither means *give up on the
    number*: `test_ambulatory_drift` spawns four Assemblies into one arena and
    reported `neutral -92.2°, hard over +24.6°, counter +19.9°, standing -18.10°`
    identically on two consecutive full runs.

    The distinction is what varies. Those four Assemblies are built by one file,
    in one order, with an identical allocation history in front of them, and
    nothing else is in the space. A brawl in `test_team_engagement` is twenty
    bodies interacting, which is where the float ordering bites.

    So before deciding a surprising physics result is noise, **run the suite
    twice and compare**. If the number repeats it is attributable, and a
    regression can be reasoned about rather than shrugged at. If it does not, the
    assertion was always wrong and fact 54 tells you what to write instead.

81. **A speed readout in the shipped match is not a measurement of anything, and
    three sessions read one as a physics defect.** `HANDOFF.md` carried "a parked
    Assembly drifts at 2.4 m/s" from session 32 to session 37, sourced from the
    HUD in a capture. It is wrong, and the way it is wrong is worth carrying.

    The arena is a **basin**. The player spawn sits on a 1.78° grade — measured
    off `GroundSource.basin(20260803, 15.0)` — and the shipped build has no
    parking brake, because `veh_handbrake` is bound to Space and read by nothing.
    Put that build on that terrain with no opponent, no fire and no input and it
    rolls 9.4 m out at 2.7 m/s, stops, and rolls **back** to within 2.7 m of
    where it started. A vehicle in neutral on a slope. Mostly correct physics.

    On a **flat slab**, where gravity contributes nothing,
    `tests/physics/test_rest_stability.gd` measures the real defect at
    **0.196 m/s and 1.307 m over 360 ticks** — an order of magnitude smaller.

    Three things to carry. **Measure a rest defect on flat ground**; a bowl adds
    a term an order of magnitude larger than the one being looked for. **A HUD
    number in a capture has a scene behind it** — the same frame that read
    2.4 m/s also read 100% integrity, which is what ruled out an impact, and
    checking that took one contact sheet of twenty-one frames. And **a number
    quoted from a still frame propagates**: it was restated in four places
    before anybody put the build on the terrain alone.

82. **The chatter is why nothing corners, and traction control is neither the
    cause nor the cure.** `TractionSolver.combined_forces` puts both slips on one
    friction circle — `sx = kappa/KAPPA_PEAK`, `sy = tan_alpha/ALPHA_PEAK_TAN`,
    `s = hypot(sx, sy)` — and returns the lateral component as `f_max · sy/s`.
    So a large *longitudinal* slip crowds the lateral force out of the budget,
    whatever the lateral slip is.

    Against the measured chatter peak of 6.242 rad/s (fact 72's mechanism,
    `test_rest_stability`'s number): a contact in a 6 m/s corner with 1 m/s of
    lateral slip keeps **0.264** of the lateral share a clean rolling contact
    would have — a 3.8× loss — and a parked contact keeps 0.013 against a
    free-rolling 0.348, a 26× loss.

    **Doc 05 §7.6's traction control cannot be involved in either direction.**
    Its slip limiter scales `τ_drive`, so with no throttle there is nothing to
    scale; its yaw loop is gated at `MIN_YAW_CONTROL_SPEED_MPS` = 1.5 m/s and off
    below it; and §7.6 is `GROUND`-only, so it is not in the ambulatory or rotary
    path at all. A session that goes looking for a handling defect in the *aid*
    is looking one layer too high — the aid rides on top of §7.4's integrator and
    inherits everything it does.

    **Closed in session 38, and the last paragraph turned out to be the important
    one.** With the integrator repaired the lateral grip came back in full, and
    the aid it "cannot be involved" with immediately became a *net negative*: the
    contacts alone now trim three quarters of an imposed spin, and §7.6's yaw loop
    leaves more than no aid at all. Fact 86 has it. The arithmetic above is kept
    because it is the derivation of why a friction circle behaves this way, and
    because the same crowding is what makes a *driving* contact corner worse than
    a coasting one — which is correct behaviour and is now reachable.

83. **Three ways an explicit contact solve injects energy, all found in one
    session, all with the same signature.** Fact 72 named the first and facts 73
    and 74 recorded the repair; landing it turned up two more of the same shape,
    and the shape is worth more than any of the three.

    **The signature is a per-tick sign alternation.** Not a divergence — a
    saturating model bounds it — so it presents as noise, as a hull that shivers,
    as a build that never quite stops. Anywhere a quantity flips sign on every
    single tick, something is being stepped explicitly past its stability limit.

    - **Fact 72's:** the contact's rate against §7.2's friction. Closed by
      stepping the slip velocity implicitly with a chord factor.
    - **A deadbeat stick cap, one axis out and one layer up.** "The force that
      lands the slip exactly on zero" is exact only if the mass resisting that
      slip is exact, and for a contact a metre below the centre of mass it is
      not: part of what the force moves is the hull's **rotation**, and a share
      mass taken from the normal load accounts only for its translation.
      Measured on the reference build standing still, the roll rate alternated
      between −0.22 and +0.21 rad/s on every tick and the hull crept at
      0.05 m/s. **Under-relax any deadbeat correction whose effective mass you
      cannot compute exactly** — half tolerates a 2× overestimate and converges
      geometrically instead of ringing.
    - **A feed-forward that is wrong.** Reconstructing `ω` against the hull's
      *predicted* end-of-tick speed makes the held case exact and makes the free
      case a positive feedback loop: each tick credits the hull with an
      acceleration it did not have, the slip is over-read, the force grows. A
      parked build wound its contacts to 13 rad/s and drove itself backwards at
      4 m/s with the throttle at zero. **A prediction inside a force loop is an
      energy source unless it is exact.** The case it was written for — a contact
      the brake is holding — has an exact answer that needs no prediction at all:
      it does not rotate.

84. **A contact frame borrowed from the chassis basis is indistinguishable from a
    correct one until the hull is not level, and then it is a positive feedback
    loop.** Doc 05 §7.1 specifies an orthonormal frame *in the contact plane*;
    the implementation took `-basis.z` and `basis.x` unprojected for the life of
    the project. A hull pitched nose-down has a `-Z` that points into the ground,
    so the "longitudinal" friction retarding it acquires a large downward
    component, which pitches it further, which tilts the frame further.

    It survived every measurement in the suite because fact 72's unstable step
    never produced enough force for the loop to close. The tick the brake started
    working, a tracked build braking from 4.8 m/s pitched past ninety degrees and
    finished balanced on its nose.

    The general shape: **a repair that makes a force real will find every place
    that force was being applied in the wrong direction.** Three of this session's
    four regressions were pre-existing defects that had been invisible for want of
    a force large enough to expose them.

85. **A part with several contacts must divide its rotating inertia among them,
    and getting that wrong is invisible until the figure is used for something
    else.** A tracked bogie has four road stations and one run of track;
    `MotiveSystem` credited each station with the whole part's `mass_kg`, counting
    it four times. That was harmless while the figure only scaled `ω̇` — every
    station was equally wrong and the flanks still balanced — and stopped being
    harmless the moment the same figure sized a mobility term. Over-stated inertia
    is under-stated mobility is a stick cap that throttles a tracked patch to a
    few hundred newtons: measured, the shipped bogie could not reach 2 m/s under
    full throttle, and 2.5× the drive torque hid it.

86. **An electronic aid tuned against a broken physics becomes a defect when the
    physics is fixed, and it will not announce itself.** Doc 05 §7.6's yaw loop
    modulates one flank's brakes. `MAX_BRAKE_FRACTION = 0.55` of the shipped
    Motive Assembly's authored brake is 4565 N·m against the 4672 N·m that locks
    its patch — so the aid was locking the flank it was biasing, which was
    survivable while a locked patch had no lateral grip to lose and is not now
    that it has. With §7.4 closed the **contacts alone** take three quarters of an
    imposed 1 rad/s off in six ticks, and the aid leaves more spin than no aid at
    all.

    Two things to carry. **A brake bias that locks the patch has stopped being a
    bias**, which is a rule and not a number. And when a foundational solver is
    repaired, **every gain tuned above it is now untuned** — the aids, the AI's
    stand-offs, the authored torques — and the ones that read as "still fine" are
    the ones nobody measured.

87. **The cap on drive torque is the hull's own stability, not the integrator.**
    `HANDOFF.md` carried "`drive_torque_nm` is a third of what the contacts could
    hold, and the cap is §7.4's instability" for two sessions. §7.4 is closed and
    the figure still cannot move far: at 16000 N·m the reference build takes off
    under sustained full throttle, and at 9600 it progressively unloads two
    contacts over five hundred ticks in a sustained turn and finishes on its back.
    Its static stability factor is 0.97 g and its contacts can make 1.05, so it
    can trip itself over — which also means retuning the contacts *down* is a real
    lever and was measured to work (0.78 stops it tipping and costs nothing else).
    Neither change is landed; both are recorded with their numbers in
    `CHANGE_LOG.md` §1.

    **Amended in session 39: the 9600 N·m half of this is void.** It was a roll
    failure, and it was measured with fact 88's anti-roll amplifier in place. The
    16000 N·m figure is a pitch failure and is unaffected. Anything else in this
    file or in `HANDOFF.md` that concludes something from a *roll* measured before
    session 39 is on the same footing.

88. **A restoring term applied in the wrong direction is not a weak spring, it is
    a divergence — and a unit test over its magnitude cannot see which way round
    it went.** Doc 05 §6.5's anti-roll couple was applied inverted for the life of
    the project: the loaded side was pushed further down rather than lifted.

    It survived thirty-eight sessions because of what it needs to show itself.
    On a level slab both sides compress equally, the term is exactly zero, and
    every straight-line, braking and standing measurement in the suite is
    untouched. It only bites under a roll disturbance, and then it bites
    catastrophically: once the inside contact leaves the ground there is no spring
    on that side left to oppose the couple, so the roll grows geometrically.
    Measured on the reference build at full lock from **3.3 m/s** — a walking
    pace — successive samples read `−1.1°, −2.9°, −4.6°, −7.3°, −11.5°, −18.3°,
    −28.3°, −41.9°, −57.3°, −72.6°` and it finished inverted. Corrected, the same
    manoeuvre settles at −1.3° with all four contacts loaded.

    Three things to carry.

    **A magnitude test is half a test for anything that is applied as a vector.**
    `tests/unit/test_suspension_solver.gd` asserted `k · r · (x_left − x_right)`
    exactly and correctly, and the direction the caller applies it in was asserted
    nowhere. §3's "assert the sign, in every direction it can point" already said
    this; what was missing was noticing that the sign in question lived one layer
    up from the function that was tested.

    **A suite can be comprehensive along every axis it happens to exercise.**
    Four physics files drive an Assembly and not one of them turned it at speed —
    straight-line, braking-in-a-line, and a quarter throttle. The defect was in
    the one manoeuvre nobody had written a fixture for, which is the general
    reason `test_wheeled_drive_cycle` runs a *sequence* rather than a question.

    **It explains a player-visible symptom three reviews called undiagnosed.** The
    capture kept ending with the player's parked hull on its side under fire, and
    "a parked hull taking fire" is exactly "a hull being given roll disturbances".

89. **Two controls that mean the same thing to the driver can cancel each other in
    the code, and the loser is whichever is read from the raw record.** Doc 05
    §15.5 releases the service brake demand as the hull stops going forwards, so
    one key can be a brake and a reverse gear. §7.7's holding brake engaged on a
    record demanding "neither drive nor brake" — read off `input.brake` directly.

    Put those together and a driver *holding the brake* at rest has an effective
    service demand of zero (§15.5 released it) and is refused the holding brake
    (§7.7 sees the key held). Holding the brake was strictly worse than holding
    nothing: a parked build absorbing twenty rounds of its own recoil travelled
    **10.49 m** with the key held against 1.15 m with it released.

    The rule that falls out: **a gate on an input should test the demand that
    actually reaches the physics, not the record it came from**, wherever
    something upstream is allowed to modify that demand.

90. **A binding table is data and needs a conformance test like any other.** Doc
    11 §7.1 published the right trigger against `veh_throttle` *and*
    `effector_fire_primary`, the left against `veh_brake` and
    `effector_fire_secondary`, and D-pad right against `veh_roll_right` and
    `cam_toggle_view` — three collisions inside one screen, in a table whose own
    prose says bindings collide only across contexts. `test_input_actions.gd`
    checked that every action existed, was prefixed, was bound, and matched any
    device. It never compared two rows.

    The check is eight lines: key each gamepad event by the physical control it
    occupies — button index, or axis plus the sign of its value so the two ends of
    a stick are two slots — and assert no two actions in one context claim the
    same key. The context lists are hand-maintained, so they need their own check
    against the canonical action list in both directions, or an action added to
    neither is silently exempt.

91. **`InputEvent.as_text()` is unusable on a control card, and the three gamepad
    families print different things on the same button.** Godot answers
    `"Joypad Button 0 (Bottom Action, Sony Cross, Xbox A, Nintendo B)"` — correct,
    exhaustive, and forty-eight characters wrong for a row that has to read `A`.
    And the enumeration is not academic: a Switch pad's bottom button is printed
    **B** and an Xbox pad's is printed **A**, so one naming tells half of the
    players to press the wrong one.

    Godot's controller database already resolves a DualShock, a Switch Pro and an
    8BitDo to the same logical button indices, so **one binding set is genuinely
    correct for all of them** and only the glyph varies. Match on
    `Input.get_joy_name` rather than on a vendor id: an 8BitDo reports as an Xbox
    pad in X-input mode and as a Nintendo one in Switch mode, with correct indices
    either way, so the name is the thing that already knows.

92. **An event-driven input handler cannot read a stick.** A stick held at
    deflection emits no further `InputEvent`s, so a handler that orbits on
    `InputEventMouseMotion` sits perfectly still for a player who is holding the
    right stick over. The garage had no camera control on a controller at all for
    this reason, while doc 11 §7.1 published "Right Stick" against `cam_orbit`.

    Anything continuous and analogue has to be **polled** — `_process` plus
    `Input.get_action_strength` — and anything discrete should stay event-driven.
    A single action also cannot express two axes, which is why doc 11 §13.6 added
    four analogue `cam_look_*` actions rather than reusing `cam_orbit`.

93. **A retarding term scaled by `1 − throttle` cancels the drive at a quarter
    throttle, and the arithmetic is one line.** Doc 05 §7.8's driveline drag —
    engine braking — is naturally written as "a fraction of the mover's capacity,
    fading as the throttle opens". Written that way the net torque at throttle `t`
    is `τ·t − 0.35·τ·(1 − t)`, which is **negative below `t = 0.26`**: a demand to
    accelerate retards the Assembly.

    It failed the suite in three places on its first run and every one of them
    read as something else. A quarter throttle moved the reference build at
    0.89 m/s where it had moved it at 3.8 (`test_ground_assembly`), a negative
    throttle stopped backing it out, and doc 05 §15.7.1's `APPROACH_MIN_THROTTLE`
    of 0.35 left an `AiDriver` unable to turn onto a bearing behind it — an AI
    failure caused by a friction constant.

    The repair is to release the term by a *fifth* of the throttle rather than
    across the whole range, so it models lifting off and is absent from any demand
    the game actually issues. The general shape: **when a new term opposes an
    existing one, plot their sum over the whole input range before believing
    either.** The property to assert is not "the term is right" but "net output is
    monotonic in the demand, and positive by the smallest throttle anything
    commands".

94. **The cheapest way to make a pointer-driven interface work on a gamepad is to
    give the gamepad a pointer.** The garage was unplayable on a pad for exactly
    one reason: every placement runs
    `GarageScreen._place_at(_preview_pointer())`, and that pointer was the mouse.

    The obvious design is a lattice cursor — a cell the player moves with the
    stick. It needs its own snapping, its own bounds test, its own mating rules
    and its own idea of which face a part attaches through, which is doc 02 §6's
    whole chain written a second time. The substitution instead is one line:
    `_preview_pointer()` returns a virtual cursor in the viewport's coordinates
    when `InputMethod` reports a pad, and the ghost, the inspector wash, the
    mirror, the validator and the commit are all untouched. A pad cannot then
    place something a mouse could not, which is the property CLAUDE.md §10 rule 9
    exists to protect.

    One thing it does need that a mouse does not: **something drawn where the
    cursor is.** The ghost shows where a *part* would go and there is no ghost
    until the player has armed one, so a pad with an empty catalogue selection has
    no feedback at all.

95. **A shared part is a shared constraint, and measuring one recipe is not
    measuring the part.** `drive_torque_nm` was re-measured on the wheeled
    reference build after two defects that had capped it were closed: at
    **16 000 N·m** it neither takes off nor rolls over. Raised to 9600 on that
    evidence, it broke the suite — because `CombatArena.Recipe.TRACKED` carries the
    same Prime Mover and is a far less stable machine.

    The tracked recipe turned out to be the real cap and to be defective
    independently of the torque: at the shipped 6400 it already rides **8.1°
    nose-up with its two forward road stations carrying nothing**, spikes a single
    station to 35 kN as it bottoms out, and inverts in a sustained turn. It also
    barely steers — full lock at 6 m/s yaws it 0.03 rad/s — because
    `TrackProfile.pivot_taper_mps` has faded the differential to a third by then
    and `lateral_grip_ratio` of 1.35 gives the patch more lateral grip than
    longitudinal.

    Two things to carry. **Re-measuring a cap means re-measuring it on every
    recipe that shares the part**, not on the one the defect was found with. And
    when a re-measurement says a figure could move, the honest outcome is
    sometimes that it stays where it is with the *reason* corrected — which is a
    better answer than the void one it replaced.

96. **A retardation at zero input and none at any positive input cannot both hold
    continuously — pick where the discontinuity goes.** Doc 05 §7.8's driveline
    drag is full at a shut throttle and must never oppose an open one, and those
    two requirements are incompatible for any continuous function: the drag has a
    positive value at `t = 0` and must be under `τ_capacity · t` for every `t > 0`.

    Three ways out, and only one is defensible. A **coasting band** where a small
    throttle still retards is what a real driveline does and reads as a control
    that cannot be trusted. A **dead band** where a small throttle does nothing
    reads as a control with slack in it. **Capping the drag at the drive it is
    opposing** puts the step at the instant the throttle leaves zero, which is
    where a driver already expects one — lifting off gives engine braking, touching
    the pedal takes it away — and it is worth 1.23 m/s² on the reference build.

    The general rule: when two requirements are provably incompatible, the design
    question is not which to abandon but **where the incompatibility is least
    visible**, and that is a question about the player rather than about the maths.

97. **Splitting a family apart does not fix the family, and this one is a worked
    example of a plausible structural change that measures worse.** Doc 01 §7.1's
    `CHASSIS_GROUND` carried `GROUND` and `TRACKED` together; the tracked recipe
    rode 4.7° nose-up on a 1.42 m base under a 3.25 m hull and inverted in a turn,
    and giving tracked its own nine-cell chassis is the obvious repair.

    Measured: the rest pitch goes 4.7° → **1.6°** and the front-to-rear load spread
    3.2× → **1.45×**, and the dynamics do not move at all. It still inverts, still
    yaws 0.03 rad/s at full lock, and it *loses* the ability to brake without going
    over — because nine cells cannot carry a six-cell Prime Mover and a nine-cell
    Effector Module without one of them overhanging that same short base.

    So the shipped `core.command.compact.t2` keeps `CHASSIS_GROUND_TRANSITIONAL`,
    named to say it is a holding position, and `core.tracked.hauler.t3` ships
    beside it unused. **The finding is that the family needs a contact base longer
    than its hull, and the part set cannot express one**:
    `mot.tracked.short_bogie.t2` runs eight cells and two per flank fit on no
    chassis in the registry. A static-stance improvement that leaves the dynamics
    alone is evidence that the model, not the layout, is where the defect lives.

98. **The Ground Array is 4096 m square and the ceiling is memory and float32,
    not the chunk grid.** Chunks are allocated sparsely, so span costs nothing
    until something drives on it. What bounds it:

    | Span | Samples/edge | Heights + surface, fully explored | float32 ULP at the corner |
    |---|---|---|---|
    | 2048 m | 4097 | 34 + 17 MB | 0.12 mm |
    | 4096 m | 8193 | 134 + 67 MB | 0.24 mm |
    | 8192 m | 16385 | 537 + 269 MB | 0.49 mm |
    | 16384 m | 32769 | 2148 + 1074 MB | 0.98 mm |

    **4 km is the comfortable ceiling and 8 km is where paging and a
    `precision=double` build stop being optional.** For scale, the reference build's
    governed top speed is 22.6 m/s, so crossing 4096 m takes three minutes — and a
    match currently uses about thirty metres of it, which is the limit that actually
    bites.

    One trap when the span changes: **the world-origin sample index moves with it**
    (`WORLD_CHUNKS.x · 128 / 2`), and two fixtures state it by value. A third,
    `test_ground_terrain`, searches for a pair of probes that differ in height and
    found 0.9 m of relief at 2048 m and 0.23 at 4096 — the noise field is sampled by
    index, so every fixture standing on a particular patch of terrain stands on a
    different one afterwards.

99. **Thermal damage and thermal heat come off the same `raw_amount`, so
    catching fire has an integrity floor — and most of the part table is under
    it.** Doc 08 §7.1 deals `raw · (1 − resist) · (1 − absorption)` and deposits
    `raw · 0.55`, so a part cannot reach `THERMAL_IGNITION_HU` unless it can
    survive

    ```
    480 / 0.55 · (1 − resist_THERMAL) · (1 − armour_absorption)
    ```

    points of thermal damage first. That is 542 on `core.command.compact.t2` and
    614 on `str.panel.medium.t2`, whose whole integrity is 380. **Five of the
    seventeen shipped parts can ignite** — the four Core Modules and the tracked
    bogie, with the limb and the rotor disc inside 10% — and the other twelve are
    destroyed by the fire they would have caught.

    The second half of the same arithmetic is the one that surprises: **heat is
    `raw · 0.55` per packet and the interval does not scale it.** §7.1's
    `maxf(interval_s, 1.0)` is 1.0 for every interval this game produces, and a
    per-tick instalment's `raw_amount` already carries the tick — so the rate is
    right, and a single 480-raw thermal strike is worth **264 HU**, which means
    two swings of the shipped edge light a Core Module with no sustained contact
    at all. A fixture measuring sustained contact has to discount the strikes
    that got it there.

    The consequence for anything reading `DamagePacket.interval_s`: it reaches
    §7.2's corrosive decay and nothing else. Setting it is still correct — a melee
    mix with a `CORROSIVE` share is authorable — and it is a planted fault that
    survives, because no shipped part takes that branch.

100. **When a new per-tick law reports exactly one event, suspect the geometry
    before the law.** Session 42's sustained-contact fixture reported "the edge
    resolved on 1 of the 1 ticks it was held", which is precisely what a missing
    per-tick clear of the victim set looks like — and the law was correct. §15.4's
    strike impulse had shoved the target off the blade on the first tick, so every
    tick after it swept clear air.

    The tell was that the one packet it did see was the wrong *size*: 0.29 where
    the contact rate asks for 2.64, which is a doc 08 §7.3 burn instalment and not
    a melee packet at all. **Check the magnitude of the event you did get before
    concluding anything about the ones you did not** — a fixture that had only
    counted events would have been reported as a defect in the code under test.

    The repair is the standard one and it is in §3's conventions now: freeze the
    target for a phase whose subject is not motion.

101. **A `Node` constructed inside an assertion expression is never freed, and
    the leak report names nothing.** `check_false(SettingsService.new().flag, …)`
    reads perfectly and costs four leaked `ObjectDB` instances and one resource
    still in use at exit — the service, its `ConfigFile`, and what they hold.
    Godot prints the counts at shutdown with no class, no file and no line, and
    `run_all_checks.sh` fails the run on it (fact 34) after every check has
    passed, so the summary line says `0 failures` and the run is red.

    There is no bisecting it from the message. The answer is always the same
    question: **which file did this session add, and what does it build that it
    does not free?**

102. **A frozen fixture cannot assert a rule about not applying a force, and the
    honest replacement is rarely the obvious quantity.** Fact 100's repair —
    freeze the target for a phase whose subject is not motion — is right, and it
    costs exactly one thing: the phase can no longer see anything the code does
    *to* motion. Doc 07 §15.5's "an instalment carries no impulse" was
    unassertable for that reason, and the planted fault that deletes it survived
    the sweep that found it.

    `tests/physics/test_melee_duel.gd` closes it with a live target, and the way
    it closes it is the part worth carrying. The tempting assertion is the
    target's **speed**: an impulse throws things, so bound how fast the target may
    go. Measured, that is 2.76 m/s under correct behaviour against 7.68 under the
    fault — because a melee build *rams*, so the target is already moving at a
    good fraction of the attacker's approach speed and the two numbers are three
    times apart with a two-Assembly fight's noise between them (fact 44).

    What separated them by two orders of magnitude, on that recipe, was **whether
    contact once made is ever lost**: the range re-opened 0.03 m correct and
    5.15 m faulted. The general shape: **when a fault adds energy to a system that
    is also being driven, the driven quantity is contaminated and the one to
    assert is what the energy destroys.**

    **And then the recipe changed, and the two instruments swapped over.** Doc 01
    §7.1 made an Appendage ambulatory equipment, so the melee build became a
    walker — which leans on what it cuts far more gently and whose contact
    flickers as it steps. The speed bound became the clean one (0.03 m/s correct
    against 4.00 faulted) and the re-opening stopped discriminating, because the
    fault now costs contact rather than distance. Same law, same planted fault,
    opposite instruments.

    So the durable lesson is not which quantity to assert. It is that **an
    assertion chosen against one fixture is a property of that fixture**, and a
    sweep re-run after the fixture changes is the only thing that says so. This
    one went CAUGHT → SURVIVED → CAUGHT across a single session without the code
    under test being touched. `test_melee_duel` now asserts both quantities, which
    is the cheap insurance.

103. **A hold a player can grant themselves is not a hold.** Doc 11 §14.6's
    control card holds the opponent's fire while a first-time player reads it,
    and the first implementation keyed that on "the card is visible" — which is
    also true of the card `hud_toggle_stats` raises, at any time, for eleven
    seconds, as often as the player presses it. The same key would have been a
    cease-fire button.

    The repair is two entry points that present identically and differ in one
    flag: `ControlCard.raise_first_run()` sets the briefing and `raise()` clears
    it. Worth generalising, because this project keeps adding rules of the form
    "while X is on screen, the simulation does Y": **a grant conditioned on a
    piece of interface has to be conditioned on why that interface is up, not on
    whether it is** — and the test that catches it is the one that raises it the
    other way.


104. **There is no elbow, so a held module always continues along its arm's
    axis** — and that decides what a limbed Assembly can be shaped like far more
    than any art decision will.

    An Appendage's cells run from its shoulder along the axis the shoulder faces,
    and Invariant I-3 admits no joint between parts, so the module in its hand
    carries straight on in the same direction. Measured across all twenty-four
    orientations against every shipped chassis: an arm hung off a flank at right
    angles is a T-pose with its weapon pointing at the scenery, and an arm hung
    downward beside the torso — the human rest pose — points its weapon at the
    ground, where doc 01 §10.5's authored −20°/+40° of mount pitch can never
    recover it.

    **So the pose that looks right and the pose that works are different poses**,
    and this is the trade every humanoid layout in this project runs into. A
    shoulder at a front corner with the arm running forward alongside the hull is
    the only arrangement that is both mounted at the sides and able to aim; it is
    what `CombatArena.MELEE_ARMS` uses and it reads as a quadruped reaching
    forward rather than as a person. The genuinely humanoid alternative — the Core
    Module stood on end (orientation 20 carries `BACK` onto `UP`, giving a 6×9×4
    torso), two limbs under it, shoulder brackets of `str.panel.medium.t2` on each
    flank and arms hanging from their undersides — builds and validates, and its
    blades point at the floor.

    Two things to carry beyond the arms. **The Core Module may be placed rotated
    and nothing forbids it**, which is a whole axis of silhouette nobody had used:
    a chassis authored as a vehicle cabin becomes a torso for free. And a part set
    with no bent members cannot express a bent pose, so a body plan that needs one
    is a request for a *part*, not for a layout.
105. **A cylinder inscribed in a square is 78.5% of it at every radius, which is
    outside doc 01 §6.2's collider coverage band — so a round part needs its
    occupancy corners cut before a `CYLINDER` collider will validate.**

    `π/4 = 0.7854`, and §6.2 wants 82%–118%. The four-cell wheels get away with a
    cylinder because `PartAuthoring.disc_cells` takes their four corners off,
    which drops the occupancy to 75% of the box and puts the ratio at 105%. At
    **three** cells the same corner-cut leaves a plus of five cells — 55.6% of the
    box — and the identical cylinder is then **141%** of it.

    So a three-cell disc has no cell list a cylinder fits: the box is 78.5% and
    the plus is 141%, with nothing in between. `mot.wheeled.light_road.t1` and
    `mot.wheeled.light_fixed.t1` therefore carry a `BOX` collider over a box
    occupancy, which is exactly 100%.

    The general shape is worth more than the two parts: **a helper that produces a
    "round" footprint is only round at the sizes it was written for**, and the
    coverage rule is the thing that notices. Doc 05 §6.1 shape-casts suspension
    from the probe rather than from the collider, so what a wheel's collider
    decides is ramming and hit registration, not ride — which is why a box is
    survivable here and would not be if the collider were the contact.

106. **A validation limit whose stated reason does not match its value binds on
    something nobody wrote down.** Doc 01 §14 rule 5 capped a part at
    `Vector3i(16, 16, 16)` and gave the reason "a part larger than this would not
    fit the lattice with room to mate on both sides". The lattice is
    `Vector3i(48, 32, 48)`, so that reason is true of a number three times larger.

    What 16 cells actually did was cap every part at **4.00 m**, and nothing
    noticed for forty-four sessions because every chassis in the registry was
    2.25 m long. Session 44's five reference vehicles broke it four times in one
    afternoon — a 7.00 m fuselage, a 6.00 m hull, a 6.00 m bogie and a 6.00 m gun.

    The repair was to derive the figure from `LATTICE_EXTENT` rather than to raise
    it: two thirds per axis, `Vector3i(32, 21, 32)`. **Per axis matters and a
    scalar could not say it** — the lattice is 48 on X and 32 on Y, so a run that
    is legal along X is illegal along Y, and the test that asserted one scalar
    against all three axes was asserting one of them and saying nothing about the
    other two.

107. **A recipe cell list is a property of the chassis's section, and sharing a
    section is what let five vehicles become one vehicle.** Until session 44 all
    four authored Core Modules were 6x4 in section and differed only in length, on
    the reading that a shared section keeps every flank and deck mount cell the
    same across families — so one cell list ported everywhere and
    `tests/integration/test_placement_validator.gd` could probe all three chassis
    with one candidate.

    That reading is defensible and it cost the thing no validator can see: **every
    Assembly was the same box with different running gear underneath**, which is
    invisible to 8000 checks and obvious in one frame of capture (fact 75 again,
    one level up). Reversing it is not free — every layout is now derived against
    its own chassis's extents, and a fixture that probes several chassis needs a
    cell per chassis or two of its three cases reject on `CELL_OCCUPIED` and read
    exactly like the rule under test working.

108. **A mass scaled against the hull makes the Assembly out of air, because the
    bounding box grows faster than the hull does.** `core.command.compact.t2` was
    taken from 1800 kg to 1450 during session 44's rebuild on sound reasoning —
    the reference road car masses 1500 kg over 11.2 m³ of envelope — and every
    validator passed. `tests/physics/test_build_proportions.gd` then measured the
    finished Assembly at **93 kg/m³** of its own bounding box, under the 100 that
    file calls the line between a vehicle and balsa.

    The box a wheeled build occupies counts the contacts standing proud of the
    flanks and the Effector Module standing on the deck; the hull counts neither.
    So the hull's density and the Assembly's are different questions, and only the
    second one is about whether the machine looks like a machine. The mass went
    back to 1800.

109. **A walking Assembly's pitch stability is its stance base and nothing else, so
    torso depth and stability are the same number.** Doc 05 §13's virtual leg is
    one spring-damper force along the hip-to-foot line with a **point foot**:
    there is no ankle, no foot length and no balance controller, and
    `GaitSolver.stance_axial_force_n` returns one scalar along one line.

    This is the constraint that makes a humanoid reference undeliverable as data.
    The reference torso is 1.85 times as tall as it is deep and its legs are half
    its height; reproducing either needs a torso with almost no fore-and-aft
    depth, and every cell of depth removed is a cell of stance base removed.
    Measured on the way through: a 2.50 m torso on a 2.24 m hip over the family's
    1.50 m stance stooped **25.8°** with all four contacts unloaded, and widening
    the stance to the torso's own ends — 2.00 m — brought it to **0.6°**. Nothing
    else changed.

    **A biped is doc 05 §13 architecture, not a part table.** It needs a foot with
    a length and an ankle torque, or a balance controller modulating stance force
    fore and aft. Until one exists, the answer to "why is the walking machine not
    the reference's proportion" is this fact.


---

## 2. What fault injection taught

Every session verifies the suite by **planting faults one at a time and
confirming something fails**. A test asserted only against correct code passes
just as happily with its subject commented out. About 500 faults have been
planted across seventeen working sessions; the table below is the accumulated
record, grouped by catcher rather than by session, because what matters to the
next session is which test defends which behaviour. The engagement and
combat-layer sweeps of sessions 15 to 18 are broken out in §2.0, because between
them they produced fifteen survivals and the survivals are the interesting part.

The lessons worth carrying, consolidated across seventeen sessions rather than
listed per session:

- **A test that reads the same constant the source does asserts nothing.** The
  probe-radius check imported `AssemblyRuntime.PROBE_RADIUS_RATIO`, so a probe
  five times too large moved the expectation with it. A published constant is
  asserted against its document once, **by value**, and
  `tests/unit/test_traction_control.gd` is the pattern: the §7.6 table written
  out by hand at the top of the file, and everything else asserted against those.
- **Pick the assertion that the wrong sign cannot satisfy.** A flipped coupling
  torque tumbles the Assembly and leaves the energy roughly alone; only
  world-frame angular momentum tells the two apart. Same shape of question for
  the steering sign and session 9's traction sign. Session 15's version is a
  pigeonhole: two tick counts drawn from the same window that sum to more than
  the window prove the two states overlapped, which no single count can.
- **A count is not a pairing, and a fixture can hide even the fixed test.**
  `axle_pair_count() == 2` passes whether four probes were matched across the
  Assembly or down one flank.
- **A fixture that cannot distinguish the rule from its inverse is not a test.**
  Session 5's shape-transform test used a part at orientation 0, under which the
  two composition orders differ by an addition that commutes. Session 9's was a
  four-limb gait phase test asserting only "the offsets are all different", which
  passes against an ordering with the right side *not* reversed. Session 10's
  `test_inertia_coupling` spins the Assembly about its **intermediate** principal
  axis, because a spin about the largest or the smallest is stable and would sit
  still for a correct correction and a broken one alike. Session 13's was the yaw
  controller measured over a third of a second, by which time the contacts' own
  lateral grip has taken the whole spin.
- **Isolate the loop you are testing from the loop you are not.** §7.6 has two
  and both are gated on the same authority; comparing aid-on against aid-off
  under throttle compares two Assemblies at *different speeds*. Releasing the
  throttle first turned an unmeasurable effect into a factor of two and a half.
- **A comment that states an invariant is the best place in the repository to
  look for a defect.** Session 27's two player-visible findings were both found
  this way and neither was found by the suite, which was green through both.
  `Blueprint.from_context` said it could read slots in ascending order *because*
  a parent's slot is lower than its child's; that reason is true of a build which
  has only ever grown and false at the first removal, and the consequence was a
  test drive arriving with a build the player had not made.
  `ChassisGraph.children` said "ascending, by construction because slots are
  allocated lowest-first and appended in allocation order", and both halves of
  that reason fail under ordinary editing. The tell in each case is a docstring
  that argues rather than describes: **a justification is a claim about code
  somewhere else, and nothing checks it.** Read the reason, find the code it is
  about, and ask what breaks it.
- **Sweeps confirm; integration finds.** Not one of §4's findings came from a
  fault sweep. Every one came from the first test that assembled the real pieces
  and asked for a real behaviour — and the largest of them, session 15's
  overpenetration grind, came from the first test that asked two *different*
  kinds of Assembly to fight each other.
- **An unfinished sweep is not a sweep, and an unaffordable one is worse.**
  Session 12 ran five of thirteen planted faults and deferred eight; session 13
  ran them and **five of the eight survived**, including the entire §7.6 yaw loop
  being disconnected from the contacts, after four green sessions. Session 14
  then planted 37 over the combat layer and ran four, because nobody had done the
  arithmetic: the suite had grown a duel that steps 700 ticks, and 37 × 6 minutes
  is three and a half hours. Session 15 planted six and ran six. **Cost the sweep
  before writing it** — §2's opening paragraph has the current per-fault figure.
- **A new subsystem written with its sweep in mind is cheap to defend.** Session
  13's fourteen faults over `ControlSystem` and the reverse path were **all
  caught first time**. The difference from §4.8 is not luck: the tests were
  written against the *document's* table of mappings and each one asserts a
  direction rather than a value, so there was nothing for a sign flip to hide
  behind.

### 2.1 What the sweeps taught

**A closed loop hides the thing it closes over.** Session 15's two survivals were
both of this shape: an autopilot that corrects an error every tick absorbs a
fault in the quantity it is correcting, and an emission geometry with margin to
spare absorbs a fault in the guard that protects the margin. The assertion has to
be made where the loop is *open*.

**A bound is only tested by geometry that exceeds it.** Session 16's new lesson,
and a different failure from the closed-loop one. Nothing was correcting for the
penetration budget; the fixtures simply never asked for a fifth part. Every
bound in Invariant I-12's table should be read with the question "does anything
in the suite reach this?", and the answer for most of them today is no. The
fixture that closes one has to be built to exceed it and then has to *assert that
it exceeds it* — `test_overpenetration_bounds` checks that six parts are on the
line before it checks that four were struck, because every assertion after that
is unfalsifiable if the line is short.

**Ask how many files failed, not whether any did — and re-run the sweep after
the fix.** `same-part-twice-allowed` was caught by exactly one assertion in one
file: the ten-a-side brawl finishing 700 ticks early. After §4.24 made the
penetration budget lifetime-scoped, the same fault **stopped being caught at
all**, because a round that double-taps one part now still stops at four parts
and the brawl finishes on schedule. Nothing about the rule changed; the fix
shrank the fault's blast radius until the one fixture sensitive to it went quiet.

**Bounding a rule's consequences is not testing the rule**, and a sweep run only
before a change will not tell you that. One failure in one file means one
fixture happens to be sensitive, not that the rule is covered — and a sensitive
fixture is exactly the kind that a later, unrelated, correct change desensitises.
§12.2.1 is now recorded as untested; see §5.

Session 31 watched that happen live and in the other direction too.
`breakaway-never-releases` was recorded as a standing survivor in session 24,
recorded as **caught** in session 30 — because with no arrival brake a sustained
throttle made the driver orbit its stand-off, which one rounds-floor assertion is
sensitive to — and is a survivor again in session 31, because the arrival brake
stops a driver orbiting whatever its throttle is doing. Three verdicts, no change
to the rule or to its code. **A sweep verdict is a statement about the fixtures,
not about the rule**, and a fault whose verdict moves under unrelated work was
never covered in the first place.

**Run the sweep with `--full` before believing a CAUGHT.** Fail-fast stops at the
first failing file, so a fault caught by a unit test reports CAUGHT and tells you
nothing about whether the fixture built to defend the behaviour saw it. Session
31 planted three faults against a new law: all three reported CAUGHT under
fail-fast at 871 checks, all three from the same unit test. Under `--full`, one
of them turned out to be caught by nothing else at all — the physics fixture's
assertion was passing by eight centimetres. **Ask which files failed, and the
cheap way to be unable to ask is fail-fast.**

**Two of session 15's six faults were planted against loops rather than against
laws.** Of session 16's twelve, one was — and it was kept knowingly.

**A unit test over statics does not cover the code that calls them, and it is
the calling that the document is usually about.** Session 17's largest finding,
and it accounts for four of its nine survivals. `test_damage_resolver.gd` is a
good file: it asserts §4's curve, §5's falloff, §6's impulse and §8's bands
against figures written out by hand from the document. Every one of those is a
`static func` taking floats. The rules that survived deletion were all in the
*instance* path — which armour figure is handed to the curve, whether the
subtraction is floored, whether the store is decremented — and none of them is
reachable from a static. **Ask of each pure-function test: what chooses the
arguments, and is that choice a rule too?**

**A sentinel is a branch, and the fixtures may only ever take one side of it.**
Both ammunition faults survived because every engagement spawns
`AmmoLedger.UNLIMITED` and `consume` returns on the sentinel before reaching the
line that does the work. The suite exercised the ledger constantly and executed
that line never. Same shape as the bound nothing reached, one level down: not
"no fixture is large enough" but "every fixture takes the early return".

**A committed sweep script rots, silently, in the direction of testing less.**
Two of session 14's faults no longer apply to code session 16 rewrote, and the
script says `PATCH-MISS` and carries on. Read the misses as carefully as the
survivals — a fault that cannot be planted is a defence that has been removed
without anybody deciding to remove it.

**A slot is reused, so anything keyed on one has to be dropped when its part
leaves rather than when the next arrives.** `BuildContext.allocate_slot` hands
out the lowest free slot, so the slot a removal frees is the slot the next
placement is given. The garage's hover wash is keyed on a slot and clears itself
in `part_removed` for this reason; a highlight that waited for the next hover
would arrive on a new part already lit. The same shape bit `BuildCommand`, which
is why a command names a cell instead — and the two answers are different because
a wash is presentation that can be dropped and a command is a record that cannot.

**A signal keyed on a slot must be emitted per slot.** Session 27's, and it
generalises past the one signal: `part_removed` announced the part the player
named and not the cascade that went with it, because doc 02 §9.2's sketch emits
once at the end of a function that removes one part. Every listener that
*recomputes from the context* — the mass solver, the stat panel — was right
anyway, which is what kept it alive: the listeners that were wrong are the ones
holding per-slot state, and in a headless suite there is exactly one of those and
it draws meshes. **Ask of every signal carrying an id: does a caller ever do this
to more than one at a time?**

**A layout that is one cell out presents as a physics defect, and the arithmetic
that finds it is a mean.** Session 36's, and it cost two fixtures before it was
seen. The ambulatory recipe hung its limbs one cell forward of the stations they
mate to, so the four feet came down about a mean of `z` 23 under a hull whose
centre of mass is at 24; a *standing* walker then yawed 152° in five seconds and
read as doc 05 §13's known gait drift getting worse. Squaring the limbs onto their
stations cut it to 51. The rotary recipe put its Prime Mover in the tail, 0.31 m
behind the disc line, which asks for `atan(0.31 / 0.72)` = 23° of a 14° swashplate
cone — the Assembly tumbled during the settle and read as the autopilot failing.

Both were found by computing a **mass-weighted mean position and comparing it to
the thing that has to be under it** — the feet, the disc line — which is five
minutes of arithmetic against a part list and needs no engine at all. Do it before
believing a solver is at fault, because a layout is data and a solver is not.

**A fixture's ground is not the game's ground.** Session 24's, and it is the
first lesson here that no test can enforce. Every fixture in `tests/physics/`
stands on a flat `StaticBody3D` slab and the match runs on fifteen metres of
relief, so a locomotion or tactics law can be measurably better on the slab and
measurably worse in the game. It happened: a throttle constant that improved
every number in the suite stopped the opponents ever reaching the player. For
anything in doc 05 §13 or §15.7, run the capture.

**A quantity nothing has ever measured is a defect nothing can ever catch, and
the tell is that the fixtures all record the same four things.** Session 31's,
and it is the generalisation of the two sessions before it. Every engagement file
in `tests/physics/` recorded rounds, ticks, kills and travel; none recorded
**attitude**. So a build ending the fight on its roof moved no number, and the
worst thing a player could experience was invisible to six thousand checks while
being obvious in six frames of a capture. The instrument was twenty lines.

**A limit cycle averages to zero, so every aggregate is blind to it. Sample the
sign, not the mean.** Session 32's, and it is the sharp version of the lesson
above rather than a repeat of it. §7.4's contact spin was reversing on ten of
every twelve ticks, at a hundred and thirty times the rate the hull's own speed
could account for, and **no quantity any fixture recorded moved at all**: the mean
force was right, the mean position was right, the speed was a couple of tenths,
and six thousand checks were green. The instrument that saw it in twenty lines was
a count of *sign changes* in a per-tick sample.

So the question to ask of an oscillating suspect is not "what is it doing" — the
answer is "nothing, on average, which is the point" — but "how often does it
change direction, and is that rate physical". The same shape applies to anything
integrated per tick: a per-tick alternation is invisible to every statistic that
does not preserve order.

Before adding an assertion to an engagement fixture, read what the record class
already holds and ask what a player would notice that is **not on the list**. The
answer is usually a physical state rather than a count — attitude, contact,
displacement, whether anything is still upright — because counts are what a
system under test naturally emits and states are what a person actually sees.

**Measure the geometry before choosing a constant that is a distance.** Same
session, and it is the finding that no approach law could have rescued.
`GROUND_STAND_OFF_M` was 6.0 m, and doc 05 §15.7.5's spacing step of 4.5 m was
justified in the document as "a little over an Assembly's own length". Nobody had
ever measured an Assembly. Taken off the colliders — Invariant I-1 makes those
the physical footprint — the reference build reaches 2.4 m from body origin to
nose, so two of them **touch at 4.8 m** and both constants were authored inside
the hulls they were meant to separate. A stand-off shorter than the two things it
stands off is not a tuning problem.

**A parked Assembly does not stop, and any fixture that treats "it moved" as
evidence is measuring that.** A wheeled build with no throttle and no brake reads
0.38 m/s at the end of a 90-tick settle and **still 0.38 m/s after 360** — the
drift does not decay, because nothing under doc 05 §7 puts a rolling resistance
on a free contact. It cost an assertion that looked airtight: a stationary
1107 kg hull ending three metres from its spawn reads as unarguable proof
something rammed it, and was the fixture's own baseline. The detector that
survives is the **gap between the colliders**, which a target that wandered off
on its own cannot satisfy.

**A behaviour added without an assertion is not there yet.** `no-arrival-brake`
survived its first run because the brake was added and nothing was written to
notice it. The suite was green with the behaviour and green without it, which is
the definition of untested — and it is easy to miss precisely because the
behaviour is *visibly* working when you add it.

**And read a `CAUGHT` whose blast radius does not match its subject.** Session
23's arc-cost fault anchored on three lines that appear twice in one file, landed
in the wrong function, and reported `CAUGHT` with nineteen failures across five
files that have nothing to do with what it was defending. A sweep that only
greps its own output for `SURVIVED` records that as a success. The tell was in
the output the whole time: a fault on target selection had broken
overpenetration, the duel, and the brawl.

### 2.2 What the uncaught faults taught

The question to ask first is never "how do I test this" — it is **"is this code
dead?"** Across sessions 4 to 7 that question deleted a depth sort, a duplicate
batch clear, a redundant island guard and three redundant state resets, and it
saved a mass floor by finding the one state that reaches it. Reaching for
"document the redundancy" before "delete it" is how untested code accumulates.

- **A fixture that cannot distinguish the rule from its inverse is not a test.**
  Session 5's shape-transform test used a part at orientation 0, under which the
  two composition orders differ by an addition that commutes. Session 9's was a
  four-limb gait phase test asserting only "the offsets are all different", which
  passes against an ordering with the right side *not* reversed. Session 10's was
  caught while writing: `test_inertia_coupling` spins the Assembly about its
  **intermediate** principal axis, because a spin about the largest or the
  smallest is stable and would sit still for a correct correction and a broken
  one alike. Session 13's was the yaw controller measured over a third of a
  second, by which time the contacts' own lateral grip has taken the whole spin
  and the aid has nothing left to show for itself.
- **Isolate the loop you are testing from the loop you are not.** §7.6 has two,
  and both are gated on the same authority. Comparing aid-on against aid-off
  under throttle compares two Assemblies at *different speeds*, because the slip
  limiter held one of them back. Releasing the throttle before the measurement
  removes the limiter from the comparison entirely and leaves the corrective
  brake as the only difference — which turned an unmeasurable effect into a
  factor of two and a half.
- **The most valuable test is the first one that tries the whole thing.** Every
  large finding here has come from a test that assembled the real pieces and
  asked for a real behaviour. Session 9's traction sign came from the first test
  that asserted a driven contact accelerates its Assembly; all of session 10's
  findings from the first test that put a build on ground and drove it.
- **Two owners of one invariant is worse than either alone.** Nine found so far.
- **Six pieces of dead code were deleted rather than tested** (session 9). All
  were guards whose condition the surrounding arithmetic already produced. Every
  one read as prudence.
- **A redundant check can hide a genuinely needed one.** `DetachmentScheduler`
  drops an Assembly's pending work when it leaves the match, and the resolve path
  separately guards against a null graph. They cover different cases, so the
  answer was a test for the first rather than a deletion of it.
- **When a fault survives, check whether it crashed rather than whether it was
  tolerated.** Those look identical in a green run and only one of them means the
  test is missing. §3.34 is why, and the shell wrapper is what closed it.
- **An assertion that passes for a state the test was written to exclude is not
  an assertion.** Found twice, in two different disguises, and it is the single
  most productive question to ask of an existing green test.
  `test_locomotion_behaviour` asserted since session 9 that a walker "stands on
  its feet rather than on its shins", by checking
  `contact.distance_m < leg_length_m`. Session 15 measured that a *stationary*
  ambulatory Assembly rests on its thigh colliders with the stance spring doing
  nothing, and the check passes in exactly that state (§4.15); the fixed version
  compares against the **rest** length, not the full extension. Session 16's was
  subtler and only a fault sweep found it: two duels asserted
  `check_ne(killer_of_loser, "")` over a value produced by
  `arena.name_of(kills.get(loser, 0))`, and `name_of` answers `"#0"` for an id it
  has never seen — so deleting doc 04 §8.2's `assembly_terminated` emission
  entirely left the suite green. **A `check_ne` against `""` is a smell.** It
  passes for every string a formatter can produce, including the ones that mean
  "nothing was found", and the fix is almost always to name what the value should
  have been and use `check_eq`.

---

---

## 3. Conventions — follow these when adding to the suite

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
  `BuildContext`, in `after_all`. Release every held input action at the **top**
  of each test that presses one.

### Engagement tests
- **Use `CombatArena`.** It builds the ground, the four shared combat systems and
  any number of Assemblies from five recipes, and it drives them. A fourth duel
  written by hand is four hundred lines that will disagree with the other three.
- **One arena at a time** (§3.45). Take the record, then close it.
- **Record a property of the fixture when the fixture is built**, never in a test
  method. The runner sorts methods, and by the time an alphabetically later one
  runs the Assemblies have moved and one of them is wreckage. `Duel` and
  `Engagement` exist for exactly this.
- **Run each fight once and let every method assert one thing about the record.**
  A fight is destructive and cannot be repeated. `_run_all()` guards it, which is
  what lets eight methods report eight failures instead of one method reporting
  the first of eight.
- **Assert ranges, directions and pigeonholes, never exact counts** (§3.44).
- **Assert the honest outcome.** Two of session 15's six engagements do not reach
  a decision. Both are asserted as they behave, with the three measurements that
  explain why, because a finding left in prose gets re-litigated and one left in
  a test does not.

### Physics tests
- **`await physics_frames(n)` is the only way to observe a force**, and it costs
  real wall time at 60 Hz. Prefer the fewest ticks that make the claim. A test
  that soaks for ten seconds to show a trend is usually one that has not found
  the derived number it should be asserting — and a soak can actively destroy a
  measurement, as §4.8's yaw window did.
- **Measure from rest wherever an equality is wanted.** Damping is proportional
  to the current velocity, so from zero it contributes nothing and `Δv = F·dt/m`
  is exact rather than approximate (§3.38).
- **Freeze a body whose motion is not the subject of the phase.** A fixture that
  measures a hundred ticks of anything against a target needs the target to still
  be there on tick a hundred, and an impulse delivered on tick one is enough to
  take it out of reach. `test_held_weapon` measures §15.4's impulse on a live
  target and then freezes it for §15.5's contact phase; fact 100 is what the
  unfrozen version reported, and it read as a defect in the law rather than in
  the fixture.
- **A frozen phase cannot assert a rule about *not* applying a force**, so a
  law of that shape needs a second fixture with the body live — and the quantity
  to assert there is usually not the one the force acts on. Fact 102.
- **Free everything a test builds, including what it builds inside an
  assertion.** A `Node` constructed as an argument — `check_false(Thing.new().x,
  …)` — is leaked, and the engine's report at exit names no class and no file
  (fact 101). Build it into a local, assert, free it.
- **Set state directly instead of waiting for it.** `RotorDiscState.omega_rad_s`
  assigned is deterministic and instant; spooling to it is neither. The same goes
  for an imposed spin (§3.29): a yaw provoked by wheelspin is real but is not
  reproducible tick-for-tick between two runs, and the comparison is the
  assertion.
- **Remove every loop but the one under test from a comparison.** Two aids on one
  authority means comparing the authority on against off compares both. §4.8 is
  what that costs and how it was fixed.
- **Build the ground out of a `StaticBody3D` slab and name it a fixture.**
  Document 09 owns Dynamic Ground Arrays.
- **A physics test that plants no fault is not finished.**
- **Never `git add -A` while a sweep is running, and never kill one mid-fault.**
  A sweep writes a fault, runs, and restores in a `finally`. Session 14 did both
  of the things that break that: it committed during a sweep, capturing a planted
  fault into a commit, and then killed the sweep between the write and the
  restore. The fault — §4.2's ricochet angle gate replaced by `if false` — went
  in as a one-line change to a file the commit had no business touching, and the
  only reason it was noticed within the hour is that
  `test_a_square_hit_never_ricochets_however_weak` had been written twenty minutes
  earlier and started failing. Stage explicit paths, or wait.
- **A sweep gets slower as the suite grows.** Session 13's cost about 2.5 minutes
  a fault; session 14's, with the duel in the suite, costs nearer six. Thirty-odd
  faults is then most of an afternoon of wall time. Plant fewer and better ones,
  scope them to the code that changed, and start the sweep before writing the
  documentation rather than after.

### What to assert
- **Assert the rejection, not just the acceptance.** Every check in
  `test_placement_validator` is asserted in both directions.
- **Ask what chooses the arguments.** A unit test over a `static func` asserts
  the formula and says nothing about the caller that picks its inputs — and the
  document is usually about both. Four of session 17's nine survivals lived in
  that gap: §4's damage curve was tested exactly, and *which armour figure is
  handed to it* was tested nowhere. When a pure function is covered, the next
  question is which call site fills each parameter and whether that is a rule.
- **Assert an equality against a count, not a decrease.** `test_duel` now asserts
  the store equals `LOADED_ROUNDS - shots`, not that it went down: a store that
  merely fell is satisfied by a module that double-charges every round.
- **Assert a derived number, not that it moved.** Every strain, mass, inertia,
  suspension, traction, rotor, gait and track test fixes an input and asserts the
  exact value, written out as arithmetic against the published tables — never
  derived by calling the code under test with different arguments.
- **Assert the sign, in every direction it can point.** Session 9's traction sign
  defect survived a test that asserted the friction *magnitude* was right.
- **Assert a composition where two conventions meet.** §15.4's cyclic inversion
  is invisible to a test of either the mapping or the solver alone; the assertion
  that catches it is "a forward pitch demand points the thrust vector at −Z".
- **Assert the surviving structure, not just the return value.** A solver that
  severs too much and one that severs too little both return an island list.
- **Assert through the layer that consumes the result.** `test_assembly_runtime`
  counts shapes on the *physics server*, not `CollisionShape3D` children.
- **Go through the signals in an event-driven test.** `test_detachment_scheduler`
  never calls `_resolve_assembly`; it emits `part_destroyed` and then
  `tick_resolved`.
- **Cycle tests catch what point tests cannot.** Every structure these systems
  maintain is incremental and none fails loudly.
- **Write down a measurement you cannot yet fix.** §4.2 and §4.3 are asserted as
  they behave today, with the assertion's own comment saying what should replace
  it. A finding left in prose gets re-litigated; a finding left in a test does
  not.

### Fixtures
- **Prefer real parts; use synthetics where the rule needs a class, a limit, or a
  pose that is not authored yet.** `tests/physics/` is entirely real parts.
- **Derive an orientation index, never write one down.** Which of the 24 carries
  a part's drive face onto a given Assembly axis is a property of
  `OrientationTable`. Searching for it with a stated predicate survives a change
  to the table; the integer `3` does not. Watch `Vector3.FORWARD` (§3.39).
- **Drive a subsystem through the signal its real producer raises.**
- **A fixture that cannot distinguish the rule from its fallback is not a test.**
- **A fixture built by hand can be wrong in a way that hides the rule.** If a
  test passes for a reason you cannot state in one sentence, the fixture is wrong.

### Instrumenting
- **Put the measurement in the assertion message, always.** Half of session 36's
  re-measurements needed a full suite run purely to learn what the number now
  was, because the message said "a quarter throttle moves it forward at a real
  speed" and not what speed. A run is three and a half minutes; a `%.2f` is free.
- **When a system looks like it is not acting, print the state it acts on rather
  than the command it was given.** Fact 77 is the worked example: every field
  describing the *demand* said the system was working, and the three fields
  nobody prints — body height, grounded contact count, per-contact normal force —
  answered it immediately.

### After writing
- **Plant faults against laws, not against loops.** §2.0's two survivals are both
  faults planted inside something that corrects itself: a closed-loop autopilot
  absorbs an error in the quantity it is closing over, and a geometry with margin
  absorbs a fault in the guard protecting the margin. Ask, before writing a
  fault, *what would have to be true for nothing to notice this* — and if the
  answer is "the loop compensates", plant it somewhere the loop is open.
- **Plant faults, one at a time, and confirm something fails.** Not optional, and
  where most real defects here have been found. A scripted sweep is worth the ten
  minutes it takes to write — and **finish it in the session that starts it**
  (§2, last lesson).
- **Compare the check count, not just the exit code.** Two of session 10's faults
  truncate the suite into a green partial pass and are invisible to anything else
  (§3.36). For the same reason, do not add or delete a test file while a sweep is
  running.
- **When a planted fault is not caught, first ask whether the code is dead.**
- **Two owners of one invariant is worse than either alone.**
- **Two checks that look alike may cover different cases.** Before deleting the
  one whose removal changed nothing, write down the input each would catch.

---

## 4. Deliberate readings, and the redundancies

**The camera went into doc 11 rather than into a fourteenth document.** It had
no owner at all, and the two candidates each had a real claim: it is a `Node3D`
following a rigid body, which sounds like doc 05, and it decides what the player
sees, which sounds like doc 11. It went to doc 11 because of what it *consumes*
— the `cam_*` half of §7.1's input map, `InputMethod`, the theme, and §14's
reticle geometry — and because doc 07 §3 already required "a camera ray cast
against the world" without saying whose job it was. Every one of those is doc
11's. None is doc 05's, which keeps the Assembly's motion while doc 11 now keeps
the observer.

A fourteenth document was rejected deliberately. CLAUDE.md is built around
thirteen and names them in three separate tables; a fourteenth is a change to the
project's shape, and "the camera" is not a subsystem of that size. Doc 11's title
line was widened instead.

**`spawn_visual` reads `visual_profile` and `attach_part` reads
`collider_profile`, and they share no line.** That is Invariant I-1's whole
content stated as code structure rather than as a prohibition: the two functions
can be read side by side and there is no point at which one influences the other.
It would have been shorter to build both from one loop over one primitive list —
and doc 13 §2.1 keeps `ProxyPrimitiveDef` and `ColliderPrimitiveDef` as separate
types precisely so that an art edit can never move a hitbox. Merging the builders
would put back exactly the coupling the type split exists to prevent.

**Recoil yaw has two factors and an authored row owns one of them.** It is
`impulse × lever ÷ I_yy` per round, and `impulse ÷ cycle × lever` sustained. Doc
01 §14 rule 27 and the build's mount placement own the lever, and four sessions
were spent on that half — centring the bore, then measuring that centring it
changed nothing, because a mount two metres forward of the centre of mass swings
its own line of action out to two metres the moment it traverses. The other
factor is the round, and it is the half a `.tres` file can change. Doc 01 §10.5's
`eff.ballistic.repeater_12.t2` is that half: 26 N·s against 1450 is 2.9° of
heading drift against 99.1° over the same throttled, traversed, trigger-held
window. **When a quantity is a product and one factor is geometry, look at the
other factor before concluding the geometry is the problem.**

The sharper half of the same finding: **the heavy module does not merely wander,
it stops firing.** Its recoil turns the hull out from under the mount, and doc 07
§4.3.1's fire gate then correctly declines to shoot at something the module is no
longer pointed at — two rounds of a possible seventeen. Every measurement before
this one was a single round on a parked hull, which cannot see a feedback loop
between the hull's attitude and the gate. **A defect that only appears when two
loops run in the same window needs a fixture that runs both.**

**A second instance of anything reveals the joins that agreed by accident.** For
the whole life of the project every Effector Module chambered
`proj.kinetic.ap_30`, so "which round does this module fire", "which stores is
this Assembly granted at spawn" and "which store does the HUD count" were one
answer and nothing checked they were three. Adding one more projectile type made
two of the three wrong in ways a fault sweep caught and nothing else did — a
player whose module draws a round the ledger never stocked cannot fire for the
whole match and is told they are out of ammunition on the first frame. **Before
adding the second of a kind, ask which lookups have never been distinguishable.**

**A bound cannot assert anything about itself.** A test that pins a threshold —
"the starter's module recoils at no more than N" — is green forever if somebody
raises N past every value that exists, and no other test can see it. The repair
is a second assertion in the same test that something known is on the *other*
side of the bound. Found by planting exactly that fault and watching it survive.

**Presentation following the simulation is the direction Invariant I-1 permits,
and it is easy to read the invariant as forbidding it.** Moving a mesh to where a
probe says its wheel is, or pointing a limb at the foot the gait planted, is the
simulation deciding and the picture obeying. What I-1 forbids is the reverse: a
collider derived from a mesh, a visual transform a physics query can see, or a
footprint that changes with damage state or LOD. The collider stays exactly where
the part was placed in every one of these cases, which is the invariant's actual
content — *a part's physical footprint is fixed from placement to destruction*.
Doc 05 §16 is the worked version; the test that keeps it honest is that an
Assembly with the `part_visual` tag off simulates identically, which the
dedicated server relies on anyway.

The same reading settles where such a write goes. Doc 05 §6.0 rule 1 says a
locomotion family contributes `apply_force` and `apply_torque` and nothing else,
so §16's pass runs **after** the family dispatch rather than inside any solver —
the rule stays literally true, and the presentation branch is a second question
asked of the `_family` array rather than a fifth thing a family does.

**A destroyed part's mesh is hidden, and that is presentation following the
simulation rather than decorating it.** Every shipped part's greybox *is* its
collider (doc 13 §2.1's mirroring), so a mesh left behind by a disabled shape is
geometry a player can see and cannot hit — which reads as a round passing through
armour rather than as a part being gone. `release_part`, `restore_part` and
`detach_colliders_to` therefore all move the visual with the shapes. It is also
the wrong long-term answer for a *player*, who should see a wreck; that is doc 08
§9's `VisualDamageController` and is recorded in §6.5.

**Presentation is not on `BuildContext`.** Meshes are driven by
`EventBus.part_attached` (I-4). The **build proxies** are the exception and are
created there: they are physics, and they are what doc 02 §7.7 queries.

**`_check_collider_interpenetration` is skipped without a physics space.**
`BuildContext.headless()` has none, and server-side blueprint re-validation uses
it. Doc 02 §12 invariant 1 permits this precisely because the query may only
*reject*, never *accept*.

**`ProjectileSystem._already_struck` is unreachable against the shipped part
set, and is kept anyway.** All twelve `ColliderProfile`s carry exactly one
convex primitive; the sweep queries with `hit_from_inside = false` starting two
centimetres past each impact; a straight ray therefore cannot report the same
`(assembly_id, slot)` twice. Doc 07 §12.2.1 mandates the rule, Invariant I-1
permits three primitives per part, and the guard costs a scan of at most four
int32s — so this is a guard against geometry that has not been authored yet
rather than dead code, and deleting it would be trading 32 KB and four
comparisons for a defect that reappears with the first two-primitive part.

What is *not* acceptable is calling it tested. §2.0 records how it went: the
`same-part-twice-allowed` fault was caught by one assertion in one file, and
§4.24's lifetime-scoped budget — a correct, unrelated change — desensitised that
fixture and left the rule uncovered. `test_overpenetration_bounds` asserts it
against the round's own strike record and says in the comment that the assertion
cannot currently fail. **The condition that closes this is a part with two
collider primitives along one axis**, not a cleverer fixture.

**~~"A melee module does not emit a projectile" has four owners.~~ Reduced to
three, session 18.** Session 17 deleted `can_fire`'s `if profile.is_melee():
return false` and nothing anywhere changed, and recorded the redundancy as the
worst in this file — while declining to act on it, because the guard's subject is
doc 07 §15's melee sweep and that was the next thing anybody would wire up. That
happened, so the guard is gone. What settled it was not the count but the
**reachability**: §7.1's emission loop now hands a melee module to `_step_melee`
and `continue`s, so the guard sat below the only `continue` that could reach it
and was dead from the one caller `can_fire` has. The remaining owners are all
still true and are no longer arguable about — `register` never resolves a
projectile id for a melee module, `eff.melee.beam_edge.t4` authors
`projectile_key = &""`, and `can_fire` terminates on `_projectile_id[slot] >= 0`
— but the legibility argument the deleted guard existed for is now served at the
call site, which is a better place for it than inside a function the call never
makes.

**A melee packet's incoming direction cannot be tested, because its normal is
derived from it.** `_resolve_melee_hit` writes `impact_normal_world = -direction`
and `incoming_direction = direction` out of one local, so doc 08 §4's ricochet
test — the angle between them — is `cos = 1` for every value either could take.
A fault on that local survives everything and did (§2.0). This is not
carelessness: `intersect_shape` reports no surface normal, and neither does
`collide_shape`, so there is nothing else available to write there. **The
consequence to know is that a melee strike can never ricochet**, which is
probably right for an edge and is undecided rather than decided. If it ever needs
to be, the normal has to come from somewhere the query does not currently
provide. The impulse direction is a *different* quantity out of the same travel
vector and is tested, which is why the fault had to be re-planted there.

**`ResolvedNode.is_face_paired` is over-specified, knowingly.** It tests
adjacency in both directions *and* that the faces oppose, and any two imply the
third. Fault injection cannot make it fail by removing one — not a test gap.

**`IslandDetacher` writes the debris body's transform after its shapes, and
nothing proves it must — and session 17 established that nothing in
`tests/physics/` can.** This entry used to say the test was cheap and obvious: a
shape query at the island's centre of mass, with the transform written before the
shapes as the fault that must fail it. That test now exists
(`test_debris_body_query.gd`) and the fault survives it, both as an extra early
write and as the only write. §3.28 requires a stepped frame before the space
answers with a current pose, and the step repairs the very broadphase entry
§3.19's rule protects. The rule is still believed — §3.19 is a real measurement —
but it is defended by the comment in `island_detacher.gd` rather than by a test,
and §8 item 14 records the two attempts so the next session does not make a
third.

**`MotiveSystem._gather_contacts` is covered end to end** by
`test_ground_assembly` through four real probes on real ground. It should stay
thin anyway — every derived quantity belongs in a static solver a unit test can
call directly.

**`MotiveSystem.register` guards the part class and nothing else.** It used to
also guard a null `motive_profile`, and fault injection showed the two were
indistinguishable. Validator rule 6 rejects a Motive Assembly with a null payload
at build time. Removing the class guard is caught only because the shell wrapper
fails on the resulting null dereference (§3.34).

**Three faults remain uncaught, all for stated reasons.** A hard-coded steer lock
of 32 degrees is indistinguishable from reading `max_steer_angle_deg`, because
`mot.wheeled.allroad.t2` is the only shipped row with a non-zero lock and its
lock is 32; the fixed rear row cannot expose it either, since its
`steer_rate_deg_s` is zero and the angle never leaves the stop. A second steered
row with a different lock makes it visible and costs nothing else. The second is
the `taken[j]` guard in `_rebuild_axle_pairs`, which stops one probe being
claimed by two pairs: it is live — three probes where one is a candidate for two
others reaches it — and the shipped four-disc fixture cannot produce that
arrangement. The third is the *sign* of the anti-roll force, which cannot be
observed at all until §4.2's suspension settles on real springs; a bar that
pushes both ends the same way makes a settled build roll further rather than
less, so that one becomes testable for free.

**`MotiveContact.probe` holds a node reference, and that is the layering it
wants.** The alternative was `MotiveSystem` resolving `probe_s%03d_%d` through
`get_node_or_null` every tick — a string build and a `NodePath` construction
inside the tick loop, for a node that cannot move relative to the chassis. The
binding happens once, at registration, which fixes the ordering the §6 wiring
already had: `adopt` builds the geometry, then Motive Assemblies register.

**A probe is not collision geometry.** `ShapeCast3D` under `ChassisBody` is a
query, not a shape owner (§3.22), so `MotiveProbes` does not touch I-1. It lives
*inside* the body so its sweep follows the chassis: suspension travel is along
the chassis's own down, not world down.

**`MotiveSystem` declares `_physics_process` and is on the `test_no_polling`
allowlist.** It is a force integrator, not a reactor to structural events, and
doc 05 §9's dynamic amplification factor is explicitly per-tick work. `step(dt)`
is the whole tick and `_physics_process` does nothing but call it — which is what
lets a unit test drive the identical path with synthetic contacts *and* lets a
physics test let the engine drive it and assert what the body did.

**`ControlSystem` does not.** It reacts to `MatchClock.tick_started`, which the
clock emits at `process_physics_priority = -1000` — before every other
`_physics_process` in the tree. That is not a stylistic preference: sampling in
its own `_physics_process` would put the input one tick ahead of or behind the
motion layer depending on where the match scene added the node, which presents
as one frame of input lag on some builds and not others. The signal makes the
ordering a property of the clock. It is also why `ControlSystem` needs no
allowlist entry and no `SubsystemGate` tag: it declares no per-frame callback,
and the dedicated server simply never constructs one.

**`ControlSystem` does no smoothing.** A keyboard produces a step from 0 to 1 and
it stays a step. `MotiveSystem` already rate-limits the steer *angle* from the
part's authored `steer_rate_deg_s`, and a ramp in the input layer would be a
second owner of that behaviour and would make the authored number mean less than
it says. Same reasoning for the deadzone: the action's own deadzone in
`project.godot` is the only one in the chain.

**One axis feeds several families and nothing branches on locomotion mode.**
`throttle` is also `collective`, and `steer` is also `yaw`. A build may carry
more than one family at once — a walker with a lift rotor is a legal Assembly —
so a mode switch would have to pick a winner. Each family reads the fields it
uses and ignores the rest, which is the same discipline doc 05 §6.0 rule 1 asks
of the force side.

**`DamageResolver` and `ProjectileRegistry` are objects, not autoloads.** Doc 08
§3.1 writes `AssemblyRegistry.get(aid)` and its own amendment records why that
became `registry.get_runtime(aid)` on an ordinary `RefCounted`: CLAUDE.md §4
freezes the autoload list at eight and a `static var` holding the same dictionary
is that global with less of the visibility that makes an autoload reviewable. The
resolver needs the registry, so it is one too. The match scene owns both and
hands them out.

**Band transitions reach the caching systems as a signal, not as a direct call.**
Doc 08 §8.4 writes `assembly.motive_system.on_band_changed(slot, after)`, which
would need the resolver to hold a reference to every per-Assembly system in the
match. That is the same shape it declined for the registry. `MotiveSystem` and
`EffectorSystem` subscribe to `EventBus.part_band_changed` and filter on their
own assembly id. **This was missing until session 14 closed it**, and while it was
missing the multipliers were written once at registration and never again — a
Motive Assembly could be shot to pieces and keep full traction, and an Effector
Module could never jam.

**Blast occlusion walks parts, not lattice cells.** Doc 08 §5.2 walks the
occupancy lattice with the §7.6 DDA. The occupancy array belongs to the
`BuildContext` the Assembly was adopted from and does not survive into the match,
and the question being asked is "how much metal is in the way" — a part is the
unit metal comes in. A part-level walk gives the same answer at the resolution
that matters and needs no structure the match does not already have.

**Non-kinetic damage meets armour on a curve, not a threshold.** §4's penetration
ratio needs a penetration figure and blast, impact and thermal have none. They go
through `armour / (armour + ARMOUR_HALF_ABSORPTION)`, which never reaches 1.0 —
so a heavily armoured part is resistant to fire and never immune to it. The
half-absorption point is one armour rating and the constant is owned by the
resolver, because doc 08 specifies the channels and leaves this join open.

**A projectile is an index, not a node.** Doc 07 §12.1. `ProjectileSystem` holds
flat arrays and one loop; the pool recycles the *oldest* round on exhaustion
rather than dropping the newest, because a dropped shot is one a player fired
that silently never existed. The victim is chosen by a ring cursor so it is O(1)
and deterministic — a server and a predicting client must recycle the same slot
or their pools diverge for the rest of the match.

**Hit detection is a swept ray and can never be a point test.** At 940 m/s a
round covers 15.7 m in a tick. This is the one place in the combat layer where
the obvious implementation is not merely slower but silently wrong, and the
symptom is rounds passing through everything and landing in the terrain behind.

**Ammunition is held per projectile type per Assembly, not per module.** Two
autocannon firing the same round draw from one store, which is what makes
carrying a second one a trade against the Support Modules that hold the rounds
rather than a free doubling of output.

**The coupling torque runs before the input guard.** It is a property of the
Assembly's mass distribution, not of what it is being asked to do; a wreck
tumbling with nobody at the controls is exactly where it is most visible.

**Anti-roll runs after the families.** It differentiates the compressions they
wrote *this* tick; running it first would couple the previous tick's roll into
this one.

**A rotor and a wheel share `DegradationTable.MOTIVE_TRACTION`.** A disc at
`IMPAIRED` loses 40% of its thrust exactly as a wheel loses 40% of its grip.
Splitting the table would be a balance liability, and Invariant I-5 wants one
table.

**`LimbState.hip_local` is cached at registration rather than resolved per
call.** A part does not move relative to the chassis. Caching it is what lets
`reassign_gait_phases` run without reaching back into the Assembly.

**`MotiveAssemblyProfile.contact_radius_m` keeps its meaning across all four
families** — rolling radius, hub radius, foot radius. Doc 02 §7.5's clearance
check and doc 05 §6.1's probe geometry both read it, and neither should have to
know which family it is looking at. §4.2 above is what happens when a *second*
authored length has to agree with it and does not.

**An AXLE station's two drive faces are opposite each other.** So a station
cannot bolt on through one and offer the other: it attaches through a neutral
face and both drive faces stay free. A station under a Core Module's corner
carries a Motive Assembly outboard on either side; a station carrying a mast
upward must itself attach sideways. Recorded in doc 01 §4.2 because it is not
visible in the parameter table and it is the first thing that bites when
composing a build by hand.

**Nothing simulated may read `DebrisPool.retired_count`.** It is the one number
in the debris system that legitimately differs between the server and a client.
`simulated_count` is the one they agree on.

**`DetachmentScheduler` drops pending work for an unregistered Assembly, and the
resolve path separately guards against a null graph.** These look like the same
check and are not: the first covers an Assembly that left the match with a
destruction already queued, the second an id that was never registered at all.

**The rotary autopilot stayed in the fixture, and that is the decision §5 has
been deferring since session 15.** The question was always "what belongs in
`AiDriver` and what belongs in a stability-augmentation layer doc 05 does not
have". The answer is a test rather than a taste: **would a human flying this
build need the same loop?** Holding a hover is three closed loops that resolve a
demand into a world-space thrust direction and invert §12.3 back into swash
angles, and a person with a keyboard needs every one of them — so putting it in
`AiDriver` would give a bot flight a player cannot have, which is exactly what
doc 05 §15.7's contract forbids. Closing on a bearing and stopping at a stand-off
fails the same test in the other direction: a player does that with two keys.

So the augmentation layer is real, it is unwritten, it sits between *both*
producers and the motion layer, and `AiDriver` asked to drive a rotary Assembly
aims, fires, and writes a neutral motion record rather than a wrong one. Doc 05
§15.7.3 records it; `CombatArena._fly` remains the only implementation and still
names itself a fixture.

**The AI layer is the first system in the project that knows what a team is, and
it holds the roster as data.** Nothing in `src/combat/` asks whose side a packet
came from — friendly fire is decided by which hull the ray reaches first — and
the temptation was to put a team field on `DamagePacket` or on `AssemblyRuntime`
while passing. `AiContext` carries an `assembly_id -> team` dictionary the match
layer owns instead, so the resolver's ignorance stays a deliberate property
rather than something the next system to want teams has to unpick. An Assembly
the roster does not name is skipped rather than defaulted onto a side: a
candidate whose team is a guess is one an AI may shoot at because nobody said not
to.

**`EffectorSystem.reaches` exists so that §10.2's arc cost cannot disagree with
§7.1's fire gate.** The selector needs to know whether a candidate is reachable
*before* committing the mount to slewing at it, and the obvious implementation —
a bearing comparison against the authored yaw limits — is wrong in the same way
doc 07 §4.2 was wrong before session 14: it ignores the chassis basis and the
part's placement orientation. So the question is asked of the mount, through the
identical decomposition `_solve_aim` runs, factored into `_rest_direction`. A
driver whose arc test disagreed with its fire gate would pick targets it then
declined to shoot at.

**`CombatArena` is a fixture, and its tactics are a test pilot.** They read the
world and write a `ControlInput` — the same eight numbers doc 05 §6.0 gives the
AI driver — and they decide nothing about who wins. The rotary attitude
controller in `_fly` is the one place that goes further than a person holding a
key, and it is there because an Assembly that only flies when a human is flying
it cannot be put in a test at all. When `src/ai/` is written, the tactics here
are the reference for the contract and **not** for the content.

**The rotary autopilot resolves a demand into a world-space thrust direction and
then back out into swash angles.** That last step is what makes it stable: the
cyclic demand carries the body's own tilt in it, so a gust, a recoil impulse, or
a shot-off part is corrected by the same arithmetic that holds the hover.
`_cyclic_for` inverts `RotorSolver.thrust_direction` exactly, which is why the
controller can ask for a direction and get a demand that produces it rather than
one that approaches it.

**Every recipe puts its Effector Module on the nose at the Core Module's own
height.** §4.14 is the arithmetic. It is the one deliberate departure from
`test_duel.gd`'s build and it is what makes an engagement last long enough to be
an engagement.

**A disc's own AXLE face is its underside**, where a wheel's and a track's is
their `-Z` flank and a limb's is its top. So a mast needs a station under it
exactly as a limb needs one over it — and doc 01 §4.2's rule that a station
cannot bolt on through a drive face means the station goes on the Core Module's
*flank* at orientation 8, not on its roof. That in turn forces a **pair** of
discs: a station on a flank carries its mast three quarters of a metre off the
centreline and a single disc there rolls the Assembly over.

**§7.4's power budget is checked against what the context holds at the moment of
the placement.** The second rotor disc is refused if the Energy Cell that covers
its draw has not been bolted on yet. That is the same rule a player meets in the
garage and the same order they have to build in; it is not a validator quirk, and
a layout function has to place supply before draw.

**`match_concluded` is a signal on `MatchState`, not an entry in `EventBus`.**
Doc 04 §8's list is the project's cross-system contract, and every addition to it
permanently widens what any class in the project may listen to. This one has a
single producer and a single consumer, both inside the match layer, and the
`MatchScreen` that owns the object is the only thing that ever connects. The bar
CLAUDE.md §4 sets for an autoload is the bar this applies to a global signal: a
concept that two systems share belongs on the bus, and a concept one system tells
its own owner about does not. `DamageResolver` and `ProjectileRegistry` being
objects rather than autoloads is the same judgement one level down.

**The mouse stays captured when a match ends, and releasing it was tried first.**
It reads as the obvious courtesy — the player is finished, give them their cursor
back — and it makes the end of the match worse, because doc 11 §13.6 reads mouse
motion for the camera look, so a released mouse is an orbit camera that cannot
orbit. The end card names the binding that releases it instead, which is §14.6's
answer for every other control nobody can guess.

**The wreck stays where it fell.** Doc 11 §16.2 records it as a decision rather
than as work not yet done: an Assembly that despawned on losing its Core Module
would take the debris, the craters and the hulk with it, and the orbit camera
§16.2 hands the player would then be circling an empty basin. It also costs
nothing — the runtime is already inert once slot 0 is destroyed — which is the
part that makes "leave it" the cheap answer as well as the right one.

**A build command names a cell, not a slot, and that is the whole of doc 02
§9.3's exactness claim.** `BuildContext.allocate_slot` hands out the lowest free
slot, so a part restored after two removals lands in whichever hole is lowest
rather than in the one it came out of — undo two removals in the order undo has
to take them and the parts come back holding each other's slots. The build is
right and every command still on the stack that named a slot points at the wrong
part. A cell does not move, and the pivot cell is inside the part's own footprint
by construction, so `LatticeOccupancy.slot_at` always answers with whoever holds
it now. Invariant I-6 says placement is integer arithmetic over the lattice; this
is the same statement about identity.

It is caught by exactly one fixture —
`test_two_removals_undo_through_each_other_s_holes`, and only because that
fixture goes on to *redo*, which is the sole operation that has to find a part it
did not just put there. The slot-keyed variant was run against the whole suite by
hand and nothing else noticed.

**A pivot is not the middle of a footprint, and every transform of a placement
has to deal with that separately.** Doc 02 §10 mirrors a cell; mirroring a
*placement* is a different operation, because the origin cell is the part's pivot
and an authored footprint need not be centred on its own pivot — the shipped
station is two cells wide and pivots at the high-x end. The mirrored part is also
rotated, which moves the pivot within the footprint again, so the correction is
not a constant. The rule that works is: **transform the footprint's bounding box,
then solve for the origin that seats the transformed part in it.** Anything that
transforms the origin directly is right for symmetric parts and one cell out for
everything else, which is the worst available failure — it looks like a physics
problem, because the build comes out asymmetric and drives crooked.

`FootprintSolver.origin_for_seated_footprint` already existed for the
auto-assembler and answers the same shape of question. If a third caller ever
needs it, that is the function to widen rather than to copy.

**The shipped starter is the repository's only hand-mirrored build, and that
makes it a test fixture rather than only a fixture.** It was authored flank by
flank, so its two sides carry different origin cells wherever the pivot is
off-centre — which is exactly the ground truth a mirror implementation needs and
exactly what nobody would think to write down as an expectation. Any future
hand-authored symmetric build is worth the same treatment; there is currently no
second one.

**A blueprint is re-validated at every screen boundary, in one process, and that
is not redundancy.** The garage produces one, the shell carries it, the match
rebuilds it, and each crossing runs the identical `PlacementValidator` chain. It
would be cheaper to hand the match the `BuildContext` the garage already holds —
and doing so would make the garage-to-match path different from the
client-to-server path doc 12 §4.3 specifies, which is the one path that has to be
right. The redundancy is the rehearsal.

**The opponents are not built from the player's build.** A test run against three
copies of whatever the player just made is a different game every time and
measures nothing; a player who has fitted a rotor disc would be fighting three
things that fly. Doc 06's generator is what eventually varies them, from an
archetype and a seed.

**The garage is the only way into a match.** The menu could offer "fight" beside
"build" and it does not, because a player who has never seen the build screen
does not know the game has one — and the build screen is the game.

**`build_cancel` means two things in a match, decided by whether it is over.**
During the match it releases the mouse; after the conclusion it leaves for the
garage. That is not overloading for want of a key: doc 11 §16.2 keeps the mouse
captured at the conclusion so the orbit camera can be orbited, which means the
exits have to be keys, and the mouse-release meaning has nothing left to do on a
screen the player is leaving.

**`drive_torque_nm` is capped by doc 05 §7.4's stability, not by grip, and that
is a deliberate reading rather than a balance choice.** The reference build's
contacts can hold about 1.05 g; the authored total is 6400 N·m, which is 0.36 g.
The gap is not caution about wheelies — it is measured: at 10 200 N·m sustained
full throttle from a standing start pumps §7.4's limit cycle until the Assembly
leaves the ground and stops being drivable at all, and at 3200 the machine crawls.
6400 is the largest figure that was measured to be stable.

Two consequences are worth stating rather than rediscovering. The shipped Prime
Mover **no longer out-torques the shipped contacts**, so doc 05 §7.6's traction
control has no reachable fixture on the shipped part set and
`test_ground_assembly` supplies its own over-torqued mover through the Assembly's
own `PowerSystem` — which is a fixture parameter and not a data edit, because
Invariant I-11 is about `PartDefinition` and the power budget is per-Assembly
runtime state recomputed on every structural event. And the number goes **up**
when §3.1 is closed; it is not a balance decision anybody made about how fast a
vehicle should be.

**`tests/physics/` builds its ground out of a `StaticBody3D` slab and says so.**
Document 09 owns Dynamic Ground Arrays and nothing in a test may pre-empt it. The
slab is a fixture, on `LAYER_GROUND`, and is named as one in both files that
build one.

---
