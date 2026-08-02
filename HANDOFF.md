# HANDOFF

Working notes for the next session. **Not** an architecture document — `CLAUDE.md`
and the thirteen documents in `/docs/` remain the only authority. This file
records what exists, what it cost to learn, and what to do next.

Last updated: session 13 (session 12's fault sweep finished, and `ControlSystem`).

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

**48 files, 3683 checks, 0 failures.**

`run_all_checks.sh` fails on any engine error printed during the suite, not only
on recorded assertion failures (§3.34). A run takes about 100 s, because
`tests/physics/` waits on real ticks at 60 Hz — see §3.36 before adding to it.
Build a fixture once in `before_all` and reset it per test; four tests that each
spawn an Assembly spawn them on top of each other.

**A full fault sweep costs about two and a half minutes per fault**, because
each one reimports and re-runs everything. Budget for it: a fourteen-fault sweep
is thirty-five minutes of wall time and it is still the cheapest defect-finding
in this repository. Run it in the background and do documentation work while it
goes, but do **not** add or remove a test file while a sweep is running — the
sweep compares check counts against a baseline and a new file reads as every
remaining fault being caught.

---

## 2. How this repository knows its tests work

Every session verifies the suite by **planting faults one at a time and
confirming something fails**. A test asserted only against correct code passes
just as happily with its subject commented out. About 430 faults have been
planted across thirteen working sessions; the table below is the accumulated
record, grouped by catcher rather than by session, because what matters to the
next session is which test defends which behaviour.

The lessons worth carrying:

- **A test that reads the same constant the source does asserts nothing.** The
  probe-radius check imported `AssemblyRuntime.PROBE_RADIUS_RATIO`, so a probe
  five times too large moved the expectation with it. A published constant is
  asserted against its document once, **by value**, and
  `tests/unit/test_traction_control.gd` is the pattern: the §7.6 table written
  out by hand at the top of the file, and everything else asserted against those.
- **Pick the assertion that the wrong sign cannot satisfy.** A flipped coupling
  torque tumbles the Assembly and leaves the energy roughly alone; only
  world-frame angular momentum tells the two apart. Same shape of question for
  the steering sign and session 9's traction sign.
- **A count is not a pairing, and a fixture can hide even the fixed test.**
  `axle_pair_count() == 2` passes whether four probes were matched across the
  Assembly or down one flank.
- **Sweeps confirm; integration finds.** Not one of §4's findings came from a
  fault sweep. Every one came from the first test that assembled the real pieces
  and asked for a real behaviour.
- **An unfinished sweep is not a sweep.** Session 12 ran five of thirteen
  planted faults and deferred eight. Session 13 ran them: **five of the eight
  survived**, including the entire §7.6 yaw loop being disconnected from the
  contacts. Four green sessions had passed over it. Finish the sweep in the
  session that plants it.
- **A new subsystem written with its sweep in mind is cheap to defend.** Session
  13's fourteen faults over `ControlSystem` and the reverse path were **all
  caught first time** — no gap to close afterwards. The difference from §4.8 is
  not luck: the tests were written against the *document's* table of mappings and
  each one asserts a direction rather than a value, so there was nothing for a
  sign flip to hide behind.

| Test | Faults it has caught |
|---|---|
| `test_no_global_rng` | global `randf()` in `src/` |
| `test_no_polling` | `_process` in `src/assembly/graph/`; an unlisted per-frame callback in `src/` |
| `test_no_forbidden_patterns` | `find_child()` in `src/` |
| `test_orientation_table` | transposed rotation matrix |
| `test_footprint_solver` | dropped origin offset in `resolve`; `out` buffer not shrunk on reuse |
| `test_input_actions` | an action deleted from `project.godot` |
| `test_part_registry_validator` | definition on disk absent from the manifest (R02); duplicated manifest key (R02); collider shrunk to 60% coverage (R08); resistance above the 0.85 ceiling (R07); and every rule 17–24 check: rotor thrust vs rated load, rotor zero-fields, malformed disc geometry, inverted collective limits, melee mix sum, melee mix length, melee emission fields, melee bounds, AXLE keying, an AXLE node on a class that may not carry one, family payload missing, family payload on a kind that takes none, two payloads at once, limb suspension fields, limb gait bounds, cadence ceiling below its floor, an over-long step, track steer angle, track station bounds, malformed track parameters, the shared non-zero helper neutered, rule 23 never firing, **a torqueless Prime Mover accepted, and a supply-less Energy Cell accepted** |
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
| `test_traction_control` | the launch floor dropped from the allowance; **the corrective brake's ceiling removed**; the slip cut turned into a subtraction; the deadband stepped over rather than subtracted; the grip clamp dropped; the bicycle model's sign; authority not applied to the brake demand |
| `test_rotor_solver` | spool as an Euler step; spool-up and spool-down swapped; power fraction not applied; power fraction unclamped above one; thrust linear in tip speed; collective clamped at zero rather than signed; ground effect never fading; translational lift unbounded; vortex ring with no forward escape; vortex ring onset removed; degradation dropped from thrust; cyclic clamped per axis rather than on the cone; thrust direction ignoring orientation; shaft torque dropping the radius term; collective unclamped; cyclic step not rate limited |
| `test_gait_solver` | **right side not reversed**; phase offsets not spread; sides not partitioned; fore-aft tie not broken on slot; standing deadband removed; cadence unclamped; clock not wrapping; neutral point using a whole stance; velocity-error correction dropped; step length unclamped; leg reach unclamped; frozen gait still stepping; turn command ignored; stance spring allowed to pull; foot force uncapped; stance damper dropped; foot μ ignoring the band; friction cone never limiting; an upward-pulling foot still transmitting; swing arc not a parabola |
| `test_track_solver` | stations not centred on the patch; stations all at the pivot; authority not tapering; taper ignoring speed magnitude; steer command unclamped; internal loss charged after the split; bias not differentiating the sides; slew resistance uncapped; slew resistance not opposing; slew ignoring patch length; slew ignoring normal load; the centreline counting as right; station load divided by count |
| `test_melee_solver` | cycle multiplier ignored; swing arc not centred; edge not offset along its reach; sample count unbounded; samples not reaching the end of the swing; channel mix ignored; the mix sum hard-coded to one; sustained flag ignored; closing-speed gate inverted; the terminal swing-progress assignment removed; reaction not opposing the strike; energised draw always charged; `begin` not clearing the target set; target budget not enforced |
| `test_motive_system` | slot list not sorted; duplicate registration appending; the class guard removed (caught only since §3.34); a tracked part given one contact; a rotary part given a contact; station index never advancing; a band change writing only traction; unregister leaving the slot; unregister not re-phasing the gait; unregister leaving the disc state; the hip not resolved from the placement; contacts never bound to their probes; any two probes pairing regardless of side; a probe taken into two pairs; pairs never built at registration |
| `test_control_system` | **the whole record left unsampled** (the clock connection dropped); the axis helper's halves swapped; steer inverted; the brake action no longer producing a reverse demand; the brake field dropped; collective decoupled from the drive axis; yaw decoupled from the steer axis; §15.4's pitch inversion undone; §15.4's roll inversion undone; the two tilt axes transposed; the aid authority left unbounded; the held buttons never read |
| `test_locomotion_families` | a locomotion family mis-mapped in `LOCOMOTION_OF_MOTIVE_KIND`; `ENERGY_MELEE` not recognised as melee; a family payload keyed on the wrong kind; rotor max thrust dropping the density; stance rest length as the whole leg; stance duration ignoring duty factor; melee mix sum hard-coded to one |
| `test_physics_frame` | `physics_frames` waiting for nothing |
| `test_ground_assembly` | steering turning the wrong way; the steer angle snapping instead of rate limiting; the contact frame never steered; probe sphere far larger than the contact; every probe sweeping from the Assembly origin; probe reach too short to reach the ground; probes masked to hulls instead of ground; probes parented outside `MotiveProbes`; no part getting a probe at all; contacts never bound to their probes; any two probes pairing regardless of side; axle pair ends swapped; pairs never built at registration; the slip limiter never cutting; the limiter ignoring its authority; the yaw target pointing the wrong way; the corrective brake applied to the flank that adds to the spin; **the corrective brake never reaching the contacts**; **both flanks braked instead of one**; drive torque clamped to forward only |
| `test_motive_force_application` | a disc given a ground probe |
| `test_inertia_coupling` | coupling torque unclamped; identically zero; applied in the body frame; angular velocity never rotated into the body frame; never applied at all; evaluated at the tick boundary rather than the midpoint; **sign flipped** |
| `test_locomotion_behaviour` | both track flanks driven alike; flanks swapped; the steer command never reaching the mixer; every bogie counted as one flank; a limb's probe sized from suspension it has none of; a limb sweeping from the Assembly origin |
| *the runner itself* | `_process` returning `true`; the coroutine not awaited — both truncate the suite and both are detected by the check count, not by a failure |
| *nothing* | node adjacency tested in one direction only — see §5 |
| *nothing* | a probe claimed into two axle pairs — see §5 |
| *nothing* | anti-roll pushing both ends of an axle the same way — see §5 |
| *nothing* | a hard-coded steer lock — see §5 |

### 2.1 What the uncaught faults taught

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

---

## 4. What the physics tests found, and what was decided

Everything here came out of `tests/physics/` — the first tests in the project's
history to build an Assembly, put it on ground, and ask it to move. None of it
came from a fault sweep. Every one of these subsystems had exact unit tests over
synthetic inputs, and every one of them was inert.

### 4.1 Fixed — no Motive Assembly could be attached to anything

All four `mot.*` parts carried `accepts_classes = [MOTIVE_ASSEMBLY]` on their
**own** drive face. That is the AXLE *station's* restriction; doc 01 §4.2 puts it
on the station alone. `PlacementValidator._check_mating` tests `accepts_class` in
**both** directions, so every Motive Assembly in the registry rejected the only
class §4.2 lets it mount on. Nothing with locomotion could be built at all, and
rule 18 checked only the station's half of the pair. Fixed in the authoring tool,
with rule 18 extended to both halves.

### 4.2 Decided — a ground contact's rest length must reach past its radius

`suspension_rest_length_m` was 0.32 m on both ground rows against a 0.50 m
`contact_radius_m`. §6.1 puts the probe at the part's centre of mass and §6.2
reads compression as `rest − distance`; a part standing on its own collider puts
that distance at one radius. Measured: zero compression, zero normal force, and a
full-throttle displacement of **0.000 m**.

**Decision: `rest = contact_radius + travel_limit`**, so 0.74 m on both rows.
That places full droop exactly one travel above the surface and makes the part's
own collider the bump stop, so two authored numbers determine the third and there
is no third number to get wrong. §14 rule 23 enforces the hard half — rest
strictly greater than radius — rather than the convention, because a shorter
travel is a legitimate tuning choice and an inert spring is not.

### 4.3 Decided — the coupling torque was correcting for a term nothing applies

Doc 05 §3.4 derived `τ = ω × (I_diag ω) − ω × (I_full ω)` on the premise that the
server integrates the diagonal gyroscopic term. §3.37 is the measurement: it
integrates `I_diag ω̇ = τ` and no gyroscopic term at all.

**Decision: `τ = − ω × (I_full ω)`, evaluated at the midpoint.** The diagonal
half was cancelling something nothing produced. The midpoint matters separately:
the continuous torque does no work, but sampling it at the tick boundary added
**16%** of the rotational energy over five seconds, which §11 invariant 10
forbids outright. Stepping ω half a tick along `ω̇ = I_diag⁻¹ τ` and re-evaluating
costs one cross product and turns that into a **3% loss**. A correction that
bleeds energy cannot destabilise an Assembly; one that adds it spins a wreck up
out of nothing, so the test bounds the gain tightly and the loss loosely.

The assertion that catches a sign error is **world-frame angular momentum**, not
energy and not the tumble: both signs tumble and both leave the energy roughly
alone, and only the correct one conserves `L = R · I_full · ω`.

### 4.4 Fixed — steering was authored but never implemented

`max_steer_angle_deg` and `steer_rate_deg_s` were on every wheeled row and
`DegradationTable.MOTIVE_STEER` was cached per slot, and nothing read any of
them. `MotiveSystem` now carries a rate-limited steer angle per slot and rotates
that slot's contact frame about the contact normal before the friction solve, so
the lateral force stays a genuine slip-angle force (doc 05 §7.0).

Two things fell out of it. **The sign was wrong first time** — a positive
rotation about the surface normal carries the forward axis *left*, and positive
steer is right on every input device — and the test asserts the direction of the
yaw, which is the only assertion that catches it. And **an Assembly on which
every wheel steers does not turn, it crabs**: four patches pointing the same way
translate the hull sideways with its nose still forward. `mot.wheeled.fixed_rear.t2`
was published in doc 01 §10.3 and never authored; it is now shipped, and the
difference between it and the steered row is one authored number.

### 4.5 Fixed — a track's differential drive was never wired

`TrackSolver.drive_bias` and `side_torques` were written, unit-tested to the
newton, and **never called**. `MotiveSystem._solve_tracked` drove both flanks
from the same undifferentiated share, so a tracked Assembly rolled forward and
could not turn.

Wiring it exposed that §14.2's own formula could not produce the behaviour its
prose described. `τ_left = τ_share · (1 + bias)` with `bias` bounded at 1 never
drives a flank backwards — at full lock it gives one track everything and the
other exactly zero, a pivot about the *stopped track* — and because the whole
expression scaled with the throttle, a stopped tracked Assembly received nothing
on either flank and could not turn under any input. **Decision: throttle and
steer are additive terms**, `τ = τ_share · clamp(throttle ± bias, −1, 1)`, which
is the standard skid-steer mixer and what the prose asked for.

The unit test that covered this was named `test_a_full_bias_counter_rotates_the_sides`
and asserted that the inner track **stops**. A test whose name contradicts its
assertion is worth more attention than a test that fails.

### 4.6 Fixed — a limb's probe had zero length, and its collider was its leg

Two separate faults, both of which made a walker stand perfectly still.

- §14 rule 21 requires every `suspension_*` field on an ambulatory row to be zero
  — a leg is a spring-loaded inverted pendulum, not a strut — and the probe
  constructor sized its sweep from exactly those fields. A zero-length cast finds
  nothing, the contact never grounds, the foot is never planted, and the gait
  clock runs happily. An ambulatory probe now sweeps `leg_length_m` from the hip.
- The limb's occupancy spanned the **fully extended** leg, so `single_box_collider`
  baked a 2.0 m collider around a machine whose stance height is 1.63 m. The
  Assembly rested on its own shins with 0.23 m of travel it could not reach.
  **Decision: a limb occupies its hip and thigh, not its leg** — exactly as
  `mot.rotor.*` occupies its mast and not its 2.6 m disc.

### 4.7 The power classes split, and traction control (session 12)

**`POWER_PLANT` became `PRIME_MOVER` and `ENERGY_CELL`.** §10.4 already published
two rows with a `0` in the torque column, which is a class distinction written as
a magic value: nothing stopped a cell being authored with torque, nothing told
the garage that the two parts answer different questions, and one name covered
two unrelated jobs. The split puts it in the type system and §14 rule 24 keeps it
there.

**A part key was renamed, which rule 12 forbids.** `pwr.combustion.standard.t2`
is now `pmv.combustion.standard.t2`, in place at the same manifest index, so
every other `part_def_id` is unchanged. Rule 12's stated reason is that ids are
serialised into save data and network packets — and nothing has shipped to a
player, so there is no history to protect. **This is the last cheap moment for a
rename of this kind.**

**Traction control** (doc 05 §7.6) is two loops that both act *through the
contacts*: a slip limiter that scales drive torque, and a yaw controller that
brakes one flank. Neither applies a force of its own, and that is the design
rather than an implementation detail — a yaw controller calling `apply_torque`
would turn an Assembly just as briskly on ice, on a slope, or with two wheels in
the air. It carries an authority in `[0, 1]` on `ControlInput`, so the aid is a
dial rather than a switch and a burnout is what you get at zero.

**A slip ratio is meaningless at a standstill.** §7.1 divides by
`max(|v|, 0.8)`, so any rotation reads as enormous slip and the first limiter
throttled a stopped Assembly to a crawl. Flooring the road speed at 5 m/s makes
the law a slip *velocity* below that and a slip *ratio* above it — launch control
and traction control in one `maxf` rather than two modes.

### 4.8 Found — §7.6's yaw loop was never connected to anything (session 13)

Session 12's sweep was left five-eighths unrun. Running it found that **replacing
the corrective brake with a hard zero changed nothing**: the whole yaw
controller — the bicycle model, the grip clamp, the deadband, the flank choice —
was solved every tick and thrown away, and the suite was green. So was braking
*both* flanks, which is a slower Assembly and no yaw moment at all.

Nothing was wrong with the code. The controller was wired correctly the whole
time. What was missing was any test that could tell, because every §7.6 test in
the file either called a static directly or measured a straight-line launch —
and the slip limiter alone holds a straight-line launch.

The test that tells is in §2.1's second lesson: **impose a spin on a coasting
Assembly.** Coasting removes the slip limiter from the comparison, so the
corrective brake becomes the only difference between authority 0 and authority
1, and both runs start at the same speed. Measured over a tenth of a second: an
imposed 1.0 rad/s spin decays to **0.30 rad/s unmanaged and 0.12 managed**. Over
a third of a second both are under 0.1 and the test is worthless — the contacts'
own lateral grip is a strong yaw damper and it swamps the aid quickly.

Rule 24, added the same session, had no test at all. Both halves are covered now.

### 4.9 What the four families do now, measured

| Family | Behaviour | Where |
|---|---|---|
| Wheeled | drives, reverses, brakes, steers to a rate-limited lock, holds a heading | `test_ground_assembly.gd` |
| Wheeled | full throttle spins the patches past the grip peak — a burnout — and transfers load off the front axle to a third of its resting weight | same |
| Wheeled | traction control holds the launch, keeps the heading, and trims an imposed spin two and a half times faster than the tyres alone | same |
| Tracked | drives straight on both flanks, pivots on the spot at zero throttle, resists an imposed slew without reversing it | `test_locomotion_behaviour.gd` |
| Ambulatory | stands on four feet with the stance spring loaded, walks forward at about 1.5 m/s, limbs spread evenly around the cycle | same |
| Rotary | thrust reaches the body at `F·dt/m`, exact to 1e-4, at the disc's own offset | `test_motive_force_application.gd` |

Both the burnout and the load transfer are emergent. Nothing scripts either: the
tractive force is applied at the contact and the centre of mass is most of a
metre above it, so the couple pitches the nose up under power and dives it under
braking, from the same rigid body and the same offset forces.

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
third. Fault injection cannot make it fail by removing one — not a test gap.

**`IslandDetacher` writes the debris body's transform after its shapes, and
nothing proves it must — but now something could.** §3.19 recorded the failure
that rule exists for, and §3.28 used to be the reason it could not be
re-observed. §3.28 was wrong, and `tests/physics/` can now step the engine, so
the test to write is *a shape query at the island's centre of mass finds the
debris body*, with the transform written before the shapes as the fault that must
fail it. It is the cheapest remaining item in §8.

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

**`tests/physics/` builds its ground out of a `StaticBody3D` slab and says so.**
Document 09 owns Dynamic Ground Arrays and nothing in a test may pre-empt it. The
slab is a fixture, on `LAYER_GROUND`, and is named as one in both files that
build one.

---

## 6. What exists now

### Environment and CI
| Path | Purpose |
|---|---|
| `tools/ci/bootstrap_env.sh` | Provisions Godot into `.tooling/` |
| `tools/ci/godot.sh` | Engine wrapper with redirected XDG paths |
| `tools/ci/run_all_checks.sh` | Reimport + suite; the command to run |
| `tools/ci/run_all_checks.gd` | Discovery-based headless runner; awaits suspended tests (§3.36) |

### Source
- `src/core/data/` — `SyndicateConstants`, `PartEnums`, `CollisionLayers`,
  `RenderLayers`, `PartFlags`, `PartDefinition`, `PartManifest`,
  `PartInstanceState`, `AttachmentNodeDef`, `ColliderPrimitiveDef`,
  `ColliderProfile`, `FusionProfile`, `ProxyPrimitiveDef`, `PartVisualProfile`,
  the class profiles including `PrimeMoverProfile` and `EnergyCellProfile`,
  `RotorProfile`, `LimbProfile`, `TrackProfile`, `MeleeProfile`.
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
- `src/motion/` — `MotiveContact`, `SuspensionSolver`, `TractionSolver`,
  `TractionControl`, `RotorSolver`, `RotorDiscState`, `GaitSolver`, `LimbState`,
  `TrackSolver`, `AeroSolver`, `PowerSystem`, `ControlInput`,
  **`ControlSystem` (new)**, `MotiveSystem`.
- `src/combat/damage/` — `DegradationTable`.
- `src/combat/effectors/` — `MeleeSolver`, `MeleeStrikeState`.
- `src/autoload/` — all eight singletons, complete, in the §4 order.
- `project.godot` — autoloads, physics/display settings, all **37** input actions.

`ChassisGraph` covers doc 04 §2–§4 in full; `DetachmentSolver` and
`DetachmentScheduler` cover §5 and §7.2; `IslandDetacher`, `DebrisPool` and
`DebrisReaper` cover §6 and §6.2. `AssemblyRuntime` and the mass classes cover
doc 05 §1–§4 and §10.2. The `src/motion/` set covers doc 05 §6–§9, §12–§14, and
**§15 as of this session**. `MeleeSolver` covers doc 07 §15.

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

# then, per Assembly — and the order matters: adopt() builds the probes that
# MotiveSystem.register() binds its contacts to.
#   runtime.adopt(ctx); registry.register(runtime)
#   runtime.apply_mass_properties(MassSolver.compute(runtime.states, runtime.graph))
#   var motion := MotiveSystem.new()
#   motion.runtime = runtime
#   motion.power = PowerSystem.new()
#   motion.power.recompute(runtime.states, runtime.graph.alive)
#   motion.input = ControlInput.new()
#   runtime.add_child(motion)
#   for each Motive Assembly slot: motion.register(slot, def, runtime.states[slot])
#   motion.reassign_gait_phases()
#
# and, on the client, for the one Assembly the player is driving:
#   var controls := ControlSystem.new()
#   controls.input = motion.input        # must be set before it enters the tree
#   runtime.add_child(controls)
```

### Data
Eleven definitions, in manifest order. **Append only** — `part_def_id` is the
manifest index and is serialised.

| `part_key` | Class / kind | Notes |
|---|---|---|
| `core.command.compact.t2` | Core Module | 60 cells, 94 nodes, 380 kg, 240 PU, 28 mounts |
| `str.panel.medium.t2` | Structural | 16 cells, 48 neutral nodes, 34 kg |
| `str.hub.axle_station.t2` | Structural | 8 cells; the only part carrying `AXLE` nodes (±X, keyed to Motive) |
| `mot.wheeled.allroad.t2` | `WHEELED_STEERED` | 24 cells, disc footprint, 0.50 m radius, 0.74 m rest, 32° lock |
| `mot.tracked.short_bogie.t2` | `TRACKED_SEGMENT` | 96 cells, 4 road stations, 1.90 m patch, 0.74 m rest |
| `mot.rotor.coaxial_mid.t3` | `ROTOR_DISC` | 96 cells, 2.6 m disc, lifts 2600 kg, draws 150 PU |
| `mot.limb.strider.t4` | `AMBULATORY_LIMB` | 45 cells (hip and thigh; the 1.90 m leg is reach, not occupancy), 0.62 duty factor |
| `pmv.combustion.standard.t2` | Prime Mover | 60 cells, 3200 N·m, supplies 150 PU |
| `eff.melee.beam_edge.t4` | `ENERGY_MELEE` | 72 cells, 2.4 m reach, 75% thermal mix |
| `mot.wheeled.fixed_rear.t2` | `WHEELED_FIXED` | 24 cells, zero steer lock — the rear axle a steering build needs |
| `cel.static.standard.t3` | Energy Cell | 48 cells, 260 PU, no torque, 900 PU·s reserve |

`tools/part_authoring.gd` holds the shared derivations; `tools/author_first_parts.gd`
and `tools/author_locomotion_parts.gd` are the two committed generators. Both are
idempotent (with the caveat in §3.15).

### Tests
`tests/test_case.gd` (assertions, and `physics_frames`) and `tests/source_scanner.gd`.

Arch: `test_autoload_set`, `test_input_actions`, `test_project_settings`,
`test_no_polling`, `test_no_global_rng`, `test_no_forbidden_patterns`,
`test_no_runtime_csg`, `test_visual_decoupling`, `test_scripts_parse`.

Unit: `test_assembly_registry`, `test_lattice_math`, `test_orientation_table`,
`test_part_definition_bake`, `test_collider_profile_serialisation`,
`test_lattice_occupancy`, `test_footprint_solver`, `test_attachment_polarity`,
`test_part_registry_validator`, `test_chassis_graph`, `test_mate_selector`,
`test_build_budget_ledger`, `test_chassis_strain`, `test_detachment_solver`,
`test_mass_solver`, `test_degradation_table`, `test_suspension_solver`,
`test_traction_solver`, **`test_traction_control`**, `test_rotor_solver`,
`test_gait_solver`, `test_track_solver`, `test_melee_solver`,
**`test_control_system`**.

Integration: `test_tick_ordering`, `test_part_registry_data`,
`test_placement_validator`, `test_detachment_scheduler`, `test_assembly_runtime`,
`test_mass_recompute`, `test_island_detachment`, `test_debris_pool`,
`test_motive_system`.

Physics: `test_locomotion_families`, `test_physics_frame`, `test_ground_assembly`,
`test_motive_force_application`, `test_inertia_coupling`,
`test_locomotion_behaviour`.

`tests/generation/` is still empty.

---

## 7. Known gaps — deliberate, not oversights

### The motion layer
- **Nothing drives an Assembly except a test.** `ControlSystem` produces the
  intent and every family consumes it, but no scene constructs one, so the whole
  chain from a key to a wheel exists and has never been run by a person. That is
  §8's item 12, not a defect.
- **`handbrake` and `boost` have producers and no consumers.** `ControlSystem`
  writes both; nothing in `src/motion/` reads either. Doc 05 does not define what
  a handbrake does to a contact and inventing it here would be worse than the
  gap.
- **Nothing consumes `AeroSolver`, and no `ctl.*` part is authored**, so drag,
  downforce, and Control Surfaces have never acted on a moving Assembly. It is
  complete and matches doc 05 §8; what it needs is a per-part pressure-centre
  pass in `MotiveSystem` and a part to hang it on.
- **`_surface_multiplier` returns 1.0 unconditionally.** The Ground Array of
  document 09 answers it. Routed through one named function so landing that
  document is a single edit.
- **`PowerSystem.recompute` has no production caller.** It is wired on structural
  and band-change events, and `DamageResolver` does not exist. The physics tests
  call it directly at spawn.
- **`_static_load_n` returns `rated_load_kg · g` rather than the distributed
  static load doc 05 §6.4 specifies,** and `SuspensionSolver.retune` is called
  per contact per tick rather than on mass recompute. Neither is wrong
  numerically — `retune` is pure and its inputs are constant between structural
  events — but §6.4 says "fires on mass recompute only" and the code does not.
- **The visual wheel does not follow the contact.** Nothing renders a Motive
  Assembly at its probe hit point, so a lightly loaded Assembly will draw its
  wheels wherever the part was placed, and a walker's legs will not bend at all.
  Doc 05 does not cover this and should — it is the one part of the motion layer
  with no owner.
- **A tracked pivot drifts a couple of metres** rather than turning about a
  point. The flanks counter-rotate correctly but their forces do not cancel
  exactly, because the two bogies sit at slightly different offsets. Whether that
  is worth correcting is a feel question and wants a scene to answer it.
- **The wheeled build wanders under full throttle with the aid off.** Deep
  wheelspin is unstable by construction — past the friction peak, more slip means
  less force — so once one flank hooks up before the other the Assembly yaws.
  That is what a burnout does, and it is why traction control exists.

### Power
- **An Energy Cell's reserve does nothing yet.** `capacity_pu_s` and
  `recharge_pu_s` are authored and read by nobody; `PowerSystem` uses the
  sustained figures alone. The reserve is what should cover a transient overdraw
  — a salvo and a rotor spool in the same tick — and it belongs with doc 08's
  brownout handling, which is unwritten.
- **Nothing reads `PrimeMoverProfile.torque_curve`, `peak_angular_rpm`, or
  `throttle_response_s`.** Drive torque is a flat figure scaled by the throttle,
  so a Prime Mover has no power band and no lag. That is doc 05 §7.5 work.

### Melee
- **`MeleeSolver` computes everything except the query.** The swept-capsule
  `intersect_shape` belongs to the effector system, which owns the space and does
  not exist. `EffectorSystem`, `HardpointState`, `AimSolver`, and `AmmoLedger` are
  all doc 07 and all unwritten.
- **Nothing consumes `channel_mix`.** `DamageResolver` (doc 08 §5) is where the
  packets go, and it is unwritten.

### Data and the registry
- **Rule 13 (tier scaling) has still never fired.** It needs two tiers of one
  `class.family.variant`. The rotor family is the cheapest place to make it
  non-vacuous: doc 01 §10.3 publishes `mot.rotor.coaxial_heavy.t4` and
  `mot.rotor.main_single.t3` alongside the shipped mid disc.
- **`mot.rotor.main_single.t3` is the interesting one to author next.** It has
  `torque_reaction_ratio = 1.0` and no yaw authority, so a build carrying one
  alone spins under its own reaction torque and cannot stop. Session 10 saw the
  shape of that failure by accident: a *coaxial* disc mounted well off the centre
  of mass tumbled to 131 rad/s of yaw in ten seconds. Both are legal builds and
  both are the teaching.
- **Rule 2's reorder half is not implemented, and cannot be from data alone.** It
  needs a recorded baseline of shipped ids.
- **Only one Effector Module exists and it is melee.** The ballistic path has no
  authored user. Doc 02 §7.6's muzzle-offset half-cell discrepancy is unresolved
  and still flagged rather than silently fixed.

### The lattice and the garage
- **`BuildCommand` and the undo stack (doc 02 §9.3) are not written.**
- **`PlacementValidator.remove` returns the cascade list rather than acting on
  it.** §9.2 requires a player confirmation showing the affected count.
- **Doc 02 §7.5's ground-clearance check has still never rejected anything.** A
  Motive Assembly now goes through the validator, but no test places one where
  the clearance check should refuse it.
- **The aid authority has no control.** `ControlSystem.aid_authority` defaults to
  full and the settings screen that should write it is doc 11 work.

### The graph and strain
- **`update_dynamic_factor` has a caller and a moving body**, but nothing asserts
  the factor it produces. `recompute_strain` and `evaluate_strain` are still
  waiting on a recoil discharge and an impact deposit.
- **Strain is attributed to the primary-tree edge only.** A wide panel bridged
  across two spars loads only the one doc 04 §3.2 picked. Spreading it is a change
  to §4.1.
- **`assembly_terminated` reports `killer_id = 0`.** Attribution needs the damage
  layer.

### Testing and scenes
- **No scenes, and no main scene set.** What a scene still gates is the camera
  the debris visibility mechanism has never met, and anything a human is meant to
  look at.
- **`tests/generation/` is empty.** The runner walks it and finds nothing.
- **`test_constant_ownership` is not written.**
- **`run_all_checks.gd` still tolerates a runtime error on its own.** The shell
  wrapper catches it (§3.34). Worth knowing before running the `.gd` directly.
- **`cam_orbit`/`cam_pan` have keyboard/mouse bindings only**, and several
  actions had no binding in doc 11 §7.1.

---

## 8. Suggested next steps, in dependency order

1–10. ~~Lattice, parts, validator, graph, strain, detachment, runtime, mass,
   debris, registry, the motion layer, four locomotion families, a physics step
   inside the suite~~ — **done, sessions 1–10.**

11. ~~`ControlSystem`, and the input map into it~~ — **done, session 13.** Doc 05
    §15 owns the mapping, doc 11 §7.1 gained four tilt actions for the rotary
    family's cyclic, and `tests/unit/test_control_system.gd` drives the real
    input map with `Input.action_press` (§3.40).

12. **The match scene.** Now the single largest thing between this project and a
    person driving something, and every other item below is easier once it
    exists. The wiring is written out in §6 in full, including the client-only
    `ControlSystem`. What it gates: a camera, the debris visibility mechanism
    that has never met one, the visual wheel that does not yet follow its
    contact, and every feel question in §7 that a test cannot answer.

13. **The debris body shape query.** §5's uncaught fault, and cheap: a shape
    query at a severed island's centre of mass must find the debris body, and
    writing the body's transform before its shapes must fail it.

14. **A second steered wheeled row.** Makes one of §5's three surviving faults
    visible, gives rule 13 a second tier to check, and gives the garage a real
    choice on the front axle.

15. **`DamageResolver` and doc 08.** The missing consumer for `channel_mix`, for
    `PowerSystem.recompute`, for `MotiveSystem.on_band_changed`, and for
    `assembly_terminated`'s killer attribution. Four systems waiting on one
    document.

16. **`EffectorSystem` and doc 07 §7.** The melee sweep query needs it, and it is
    what gives `deposit_recoil_force` its first caller.

17. **A second tier of the rotor family.** The cheapest way to make rule 13
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
  `BuildContext`, in `after_all`. Release every held input action at the **top**
  of each test that presses one.

### Physics tests
- **`await physics_frames(n)` is the only way to observe a force**, and it costs
  real wall time at 60 Hz. Prefer the fewest ticks that make the claim. A test
  that soaks for ten seconds to show a trend is usually one that has not found
  the derived number it should be asserting — and a soak can actively destroy a
  measurement, as §4.8's yaw window did.
- **Measure from rest wherever an equality is wanted.** Damping is proportional
  to the current velocity, so from zero it contributes nothing and `Δv = F·dt/m`
  is exact rather than approximate (§3.38).
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

### What to assert
- **Assert the rejection, not just the acceptance.** Every check in
  `test_placement_validator` is asserted in both directions.
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

### After writing
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
