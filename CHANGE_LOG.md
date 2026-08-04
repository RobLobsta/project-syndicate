# CHANGE LOG

**What each session did, and what each test defends.** A record, not a plan and
not a rulebook. `HANDOFF.md` is the work queue; `LEARNED_FACTS.md` is what the
work taught. Nothing here is authoritative over `CLAUDE.md` or `/docs/`.

Entries are short on purpose. The full prose every session originally wrote is
in the git history of `HANDOFF.md`, and the durable half of it has been moved
into `LEARNED_FACTS.md`; what is kept here is enough to answer "when did this
change, and why" without re-reading an essay.

| § | What is in it |
|---|---|
| 1 | Sessions, in order, one entry each |
| 2 | What each test file has caught — the accumulated fault record |
| 3 | Sweep scripts: what each is for, and what still survives it |

---

### Where the old section numbers went

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

## 1. Sessions

Sessions 1–13 built the project from nothing to a simulation: the lattice, the
part schema and registry, the placement validator, the chassis graph and strain
model, the detachment solver, the assembly runtime, the mass and inertia
solvers, the debris pool, the motion layer and its four locomotion families, a
physics step inside the test suite, `ControlSystem` and the input map. They are
not itemised here; the architecture they produced is `/docs/` and the defects
they found are in `LEARNED_FACTS.md`.

| Session | What it did |
|---|---|
| 14 | Combat layer: damage resolver, effectors, projectiles. Planted 37 faults over it and ran four — the rest waited three sessions (see §3). |
| 15 | First engagements. Six duels between locomotion families; found the overpenetration grind, the first Prime Mover detonation, and three reasons an ambulatory Assembly is a poor gun platform. |
| 16 | Bounded overpenetration (doc 07 §12.2), closed the mount-on-its-stop fire gate (§4.3.1), fixed three ambulatory defects, and found the penetration budget restarting every tick. |
| 17 | Ran session 14's remaining 35 faults: 26 caught, 9 survived, 2 could no longer be planted. Four new test files closed seven of the survivals. |
| 18 | Appendages and held weapons: doc 07 §15's melee sweep lands. Four defects, only one in `src/combat/` — the query shape, the capsule's axis, a sweep parameter the engine ignores, and a fixture measuring the wrong point. |
| 19 | Audit. Named the match scene as the highest-priority next step. |
| 20 | **The game renders.** `scenes/boot/` and `scenes/match/`, a chase camera, a match HUD, the boot flow. Doc 11 §13–§15. |
| 21 | Doc 09's crater deformer: crater profile, deformation pipeline, collision streaming, `SurfaceTable`. |
| 22 | **The ground is terrain.** Dynamic Ground Arrays under the match, 15 m of relief. Fixed doc 09 §4.3 destroying the crater rim, §3.3's false volume-conservation claim, and §5's streaming order dropping an Assembly through the world. `ManifoldChecker` gates DCC operands for doc 10. |
| 23 | **Something shoots back.** `src/ai/` — context, target selector, driver. The match spawns three opponents that close, aim and fire through the same systems a player's trigger reaches. Found the recoil-yaw handling defect, a duplicated `assembly_terminated`, and that the ambulatory drift's *direction* is not reproducible. |
| 24 | **The bore is centred, and it did not fix what it was for.** Doc 01 §14 rule 27; the module is 4×4×9 and its bore is on the centre of mass. An Assembly still cannot drive and shoot — the lever is the mount's position, not the bore's offset. Also: §15.7.1's throttle floor was outside its own window; the fix for that was green on every test and broke the game on real terrain; two fixtures were resting on one lucky round from the ambulatory build. Sweeps rebuilt — 10× faster, cannot hang, baselines measured rather than declared. |
| 26 | **The game has a loop.** A menu, a garage a player builds in, a TEST DRIVE that fights three opponents with what they built, and two keys on the end card that fight again or go back. `Blueprint` carries a build across every screen boundary and is re-validated at each one. Doc 11 §4.3's inspector says what a part does. Doc 05 §3.6 stops the motion layer solving a terminated Assembly — the wreck no longer accelerates. |
| 27 | **A misclick is survivable.** Doc 02 §9.3's undo stack — `BuildCommand`, `BuildHistory`, `Ctrl+Z` and two toolbar buttons — and §9.2's confirmation before a removal that orphans something. Two defects found by checking what a docstring claimed: a cascade announced itself once, leaving the rest of its meshes floating, and `Blueprint.from_context` assumed slot order was build order, so an ordinary edit produced a build that could not reach a match. |
| 28 | **Half the clicks, and you can see what you built.** Doc 02 §10's mirror: one gesture places both flanks, as one undoable command. The shipped starter is twelve placements and comes out of eight. Found that §10's own sketch mirrors the pivot cell, which is one cell wrong on every part whose pivot is off-centre. The garage also got a fill light, a bounce and a hover wash — before them the build rendered as one dark silhouette and doc 13's class tints carried nothing. |
| 25 | **A match now ends.** Doc 11 §16: `MatchState` consumes `assembly_terminated`, an end card says which way it went, the controls come off the wreck and the camera goes to orbit. Doc 11 §14.6's control card tells a first-time player what the keys are, read live from `InputMap`. §14.3 separates "on target" from "on an enemy". Doc 05 §15.7.5 spaces converging opponents on a stand-off ladder. The capture that verified it found the wreck accelerating to 92 m/s. |

### Session 28, in more detail

Two queue items: doc 02 §10's mirroring, and the garage's legibility — which the
session-27 capture had put at the top of the player review.

- **Mirroring, and the trap in its own specification.** §10 sketches
  `mirror_x(cell)` and the garage applies it to an origin cell. An origin cell is
  a *pivot*, a pivot is not the middle of a footprint, and the mirrored part is
  additionally rotated — so that answer is one cell out on every part that ships
  with an off-centre pivot, which is all of them. The reflection is of the
  **footprint**: `PlacementCandidate.mirrored_x` seats the mirrored x extent
  against the reflection of this one's far side and carries y and z across.

  The proof is the shipped starter. It was authored flank by flank in session 26
  and its two sides carry *different* origin cells on every part off the centre
  line — 22 against 26 on the stations, (19, 22) against (28, 21) on the contacts
  — for exactly this reason. `test_mirroring.gd` demands that each of its twelve
  parts reflects onto the part standing opposite, and that building one flank
  with mirroring on reproduces the whole thing.

- **A mirrored pair is one `BuildCommand`.** The player made one gesture. Two
  commands would mean a mirrored build comes apart under Ctrl+Z one flank at a
  time, which is what mirror mode exists to stop them doing by hand. A refused
  mirror is simply not in the command's list, so undo takes back what went on.

- **The garage was unreadable and the tints were not the reason.** One sun over a
  dark procedural sky meant every face turned away from it fell to an ambient
  term sampled from that sky, so the Assembly rendered as a single silhouette and
  doc 13 §2.1's class tints carried no information at all. A fill, a bounce off
  the plate and a raised ambient fixed it; brighter tints would have washed out
  the lit faces to rescue the shaded ones. Verified by capture, before and after.

- **A hover wash**, because the inspector names a class and a build carries four
  parts of one class. It is keyed on the slot and dropped when that part leaves
  rather than when the next is hovered — the freed slot is the one the next
  placement is handed, so a highlight that outlived its part would arrive on a
  new one already lit.

Sixteen planted faults over doc 02 §9 and §10, none survived.

### Session 27, in more detail

The task was doc 02 §9.3's undo stack. Most of the value came from two things
found on the way to it, and both were found the same way: by reading a comment
that stated an invariant and asking whether the code kept it.

- **`BuildCommand` and `BuildHistory`.** A command is created by performing the
  edit, identifies a part by the **cell it sits on** rather than by its slot, and
  restores the primary tree rather than re-deriving it. The cell rule is not
  fastidiousness: `allocate_slot` hands out the lowest free slot, so two removals
  undone in the order undo has to take them come back holding each other's slots.
  Verified by hand — a slot-keyed variant fails exactly one fixture,
  `test_two_removals_undo_through_each_other_s_holes`, and nothing else in the
  suite notices. Depth 128, redo branch discarded by the next edit.

- **A cascade announced itself once.** `PlacementValidator.remove` emitted
  `part_removed` for the slot the player named and not for the parts that came
  with it, and doc 02 §9.2's sketch is where that came from. Every listener but
  the mass solver is keyed on the slot, so taking a station off the shipped
  starter left the contact it was carrying hanging in the air as a mesh with no
  part behind it. Emission is now per released part.

- **`Blueprint.from_context` assumed slot order was construction order.** Its own
  docstring said so and gave the reason — a parent's slot is lower than its
  child's — which holds until the first removal leaves a hole for a later
  placement to drop into. Remove a wheel, put something on a part placed after
  it, press TEST DRIVE: the blueprint refuses partway through and the match gets
  a build one part short, with nothing on screen having gone wrong. It now writes
  the lowest slot whose parent is already written, which is byte-identical on
  every build that has not been edited.

- **`ChassisGraph.children` said "ascending" and appended.** Both `reparent` and
  slot reuse break it, so `subtree_slots` was a function of edit history rather
  than of the tree — Invariant I-9 on the cascade order a removal reports and on
  the depth ordering the strain solver walks.

- **Doc 11 §9.1's confirmations.** A removal that orphans a dependent asks first,
  naming what rests on the part; RESET asks first, because it is the one action
  undo cannot reach. The dialog is §4.2's `ConfirmationDialog`, which was
  measured headless rather than assumed (`LEARNED_FACTS.md` §1 fact 71).

Eleven planted faults, none survived. The twelfth — a command keyed on a slot —
cannot be planted by substituting one line and was run by hand instead.

### Session 26, in more detail

The project had a beginning and an end and no second one. What it has now is a
loop, and the pieces of it are mostly boundaries rather than features.

- **`Blueprint` (doc 02 §9.4).** An ordered list of integer placements, applied
  through `PlacementValidator` and nothing else. The garage produces one, the
  match rebuilds from one, and the shell carries one across every transition.
  Re-validating inside one process looks redundant and is the point: this is the
  path a build takes from a client to a server, and a shortcut here is a hole
  there. `StarterBlueprint.skirmisher` is now the one place the shipped recipe is
  written down — it was a block of constants in `MatchScreen` and another in
  `CombatArena`, and the fixture's copy is the deliberate second one.
- **`ShellRoot` (doc 11 §15).** One screen at a time; remove, then release
  deferred. Both halves were paid for in the same afternoon: `free()` on a node
  with a worker task in flight is refused, and freeing a screen from inside a
  signal it is still emitting tears down the object whose method is running. The
  engine reports the second as an unrelated parenting error and leaves the screen
  unchanged, which is how it was found.
- **The garage (doc 11 §4, §5, §6).** Doc 02 §6's four-stage cursor-to-cell
  resolution against the build proxies in the context's own space, §8's coloured
  ghost with its validation throttled to changes of cell, the virtualised
  catalogue, and the stat panel — whose signal, `assembly_stats_ready`, had been
  declared in `EventBus` since session 4 with no producer at all.
- **Doc 05 §3.6.** The motion layer stops when slot 0 does. §3.4 had deliberately
  kept the coupling torque running on a wreck and said nothing about the
  families; they kept solving springs sized for 1107 kg against a body left on
  the engine's 1 kg floor.

- **Doc 11 §4.3, the inspector.** `rows_for` is a static over a
  `PartDefinition`, so which figures a class is described by is a rule a unit
  test can read. It fills on hover rather than on `build_pick`, because §7.1
  binds that action and `cam_orbit` to the same mouse button and the garage is
  the one screen that consumes both — found by looking at the control hint in a
  capture and reading "Middle Mouse inspect · Middle Mouse orbit".

**The wreck fix is also this session's lesson about fixtures.** The first version
of `test_wreck_settles.gd` reproduced the mass collapse faithfully — and the
planted fault survived it, because once the islands detach there are no contacts
left for the motion layer to push against and the wreck settles whether the guard
is there or not. The law needs the opposite fixture: an Assembly terminated with
its parts still attached, a full throttle demand standing, and a live control
case beside it. Two arenas, opened one after the other.

### Session 25, in more detail

The four things a player meets around a fight all landed, and the capture that
checked them found something none of them caused.

- **Doc 11 §16.** `MatchState` is `assembly_terminated`'s first consumer since the
  signal was written in session 16. The rule is one static over a sorted list of
  standing teams, which is what makes the draw and the one-team match — neither
  reachable in an arena — testable at all. `test_match_conclusion` then caught a
  real defect on its first run: one Assembly terminated twice took its team out
  twice, ending the match against a side that was still standing.
- **Doc 11 §14.6.** The control card reads every binding out of `InputMap` at the
  moment it is raised, so a rebind is on it. `hud_toggle_stats` finally has a
  consumer.
- **Doc 11 §14.3.** `target_acquired` is a second quantity beside the five reticle
  states rather than a sixth state, because `NO_AMMO` over a live target and
  `ON_TARGET` over bare hillside are both things a player has to be able to read.
- **Doc 05 §15.7.5.** The stand-off ladder spaces converging drivers by counting
  only the friends nearer the target than themselves — a strict ordering, so
  nobody negotiates and overtaking re-forms the ladder rather than oscillating it.

**And then the capture.** With the camera no longer bolted to a corpse, the corpse
turned out to be doing 92 m/s. `MotiveSystem` has no liveness guard, so a build
whose Core Module has gone keeps solving suspension and traction against contacts
it no longer has the mass to load. The end card had been claiming "the wreck stays
where it fell" in words on the screen; the string is now honest and the behaviour
is `HANDOFF.md` §3.1. It is the fourth time in this project that the only
instrument which found something was somebody looking at it.

### Session 24, in more detail

The only session so far whose headline is a **correction of the previous one**,
so the reasoning is worth keeping.

Session 23 named the shipped autocannon's half-cell muzzle offset "the
highest-value data change in the project", because it was believed to be why no
Assembly could drive and shoot at once. It was real: the module was five cells
wide against a four-cell Core Module, and the two parities can never put one
centreline on the other. Fixed — 4×4×9, bore on its own footprint centre,
lateral lever from the centre of mass measured from 0.103 m to zero, and the
build laterally symmetric for the first time. Doc 01 §14 rule 27 keeps it there.

**And the behaviour did not change.** `tests/physics/test_recoil_geometry.gd`
measures why: doc 07 §8 applies the recoil at the muzzle, and the mount sits
2.25 m forward of the centre of mass, so a traversed gun swings its line of
action out to that whole distance — 0.845 rad/s of yaw a round at 90° against
0.013 on the nose. A driver turning toward a target is firing off its nose by
definition. The arm was never the bore's offset within the mount; it is the
mount's position on the build.

Three smaller things, each recorded in `LEARNED_FACTS.md` as a rule:

- §15.7.1's `APPROACH_MIN_THROTTLE` was outside its own documented window. The
  law says the floor sits between two failures; 0.35 was on the stall side, and
  a driver spawned facing away settled at 0.2 m/s and never came round.
- Raising it to 0.80 fixed that on the flat slab every fixture stands on, stayed
  green on all 5130 checks, and **stopped the opponents ever reaching the player
  on the arena's real terrain**. Replaced with a speed-gated breakaway demand.
- An arrival brake was written for the overshoot the flat floor produced, then
  deleted once the breakaway law made it undetectable.

---

## 2. What each test file has caught

The accumulated fault record, grouped by catcher rather than by session, because
what matters is which test defends which behaviour.

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
| `test_placement_validator` | occupancy never reports a cell occupied; every polarity accepted; interpenetration margin flipped positive; structural load ignores the parent's subtree; motive clearance probes one cell not the envelope; effector arc never counts a blocked sample; bounds check disabled; duplicate Core Module allowed; hard limits ignored; commit forgets `FLAG_STRAINED`; stale parent survives a rejection; Core Module charged against its own mount budget; proxy transform written before its shapes; `allocate_slot` stops allocating lowest-first; removal never finds an alternate parent; *(session 27)* **a cascade announcing only the part the player named**, and the mirror of it |
| `test_build_history` | *(session 27)* an attach that undoes to nothing; a restored part left under whatever now mates; §9.2's re-parenting never recorded; a cascade restored child-first; a redo branch surviving an edit; the 128 depth removed; an undone command that cannot be redone — and, by hand, **a command keyed on a slot rather than on a cell** |
| `test_chassis_graph` | mass propagation stops at the immediate parent; orphaning children forgets to shed their mass; connectivity walks the tree rather than support edges; duplicate support edges kept; *(session 27)* **`children` appended rather than filed in ascending order**, which it has claimed since it was written |
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
| `test_wreck_settles` | doc 05 §3.6's liveness guard removed from `MotiveSystem.step` |
| `test_mirroring` | *(session 28)* §10's mirror reflecting the pivot cell instead of the footprint; a mirrored part keeping its orientation; the mirror plane moved half a cell onto the origin column; a mirrored pair recorded as one placement so undo takes one flank; a refused mirror committed unvalidated |
| `test_blueprint` | a blueprint that commits without validating; `copy()` returning a reference rather than an independent list; *(session 27)* **`from_context` writing ascending slot order**, which stops being a construction order at the first removal |
| `test_breakpoint` | the stat dock hidden below the expanded tier |
| `test_screen_flow` | the shell keeping the outgoing screen alive behind the incoming one; *(session 27)* the undo and redo keys reaching their handlers, and RESET editing the build before it is agreed to |
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
| `test_family_duels` | *(session 15; see the sweep record below)* the muzzle-relative recoil impulse dropped; a pitch limit that no longer clamps |
| `test_overpenetration_bounds` | a round that no longer continues past what it defeated;
the within-tick continuation removed; the same part struck twice; the penetration count
restarted every tick |
| `test_team_engagement` | *(nothing yet — planted faults reached it through the files above)* |
| `test_damage_application` | *(session 17)* §8.2's armour band multiplier dropped from `_compute_effective`; the integrity floor removed, read through the §8.4 signal that fires before destruction |
| `test_ammo_ledger` | *(session 17)* `consume` not subtracting from a finite store |
| `test_projectile_lifetime` | *(session 17)* a round that hits nothing never expiring |
| `test_debris_body_query` | *(session 17)* a pooled debris body that never joins `LAYER_DEBRIS`, so §5.3's blast query cannot see the wreck. **Not** the transform-before-shapes fault it was written for — that one survives it, and §8 item 14 records why |
| `test_aim_solver` | the yaw sign; the pitch sign; `direction_for` flipped; slew band multiplier ignored; yaw convergence not wrapped; pitch convergence wrapped; the spread cone uniform in angle; the cone basis degenerate; **the full-traverse escape hatch removed, once a mount authored `(0, 360)` existed to see it** |
| `test_band_dispatch` | the band transition never written; neither system subscribing; the motive id filter dropped; **the effector slot filter dropped** |
| `test_held_weapon` | *(session 18)* §15.3's capsule reduced to a ball at the blade's midpoint; the capsule left standing on its own +Y; §15.4's impulse on the target never applied; the closing-speed gate refusing everything; the per-swing dedup removed; the sample count dropped back to 6; **§15.4's impulse taken from the blade's axis rather than from the edge's travel** |
| `test_duel` | destruction never flagged; the destroyed event never emitted; **ammunition never consumed** |
| `test_part_visuals` | *(session 20; no sweep run against it yet — see below)* doc 13 §2.1's collider mirroring by extent, §9's spawn, I-1 over a **populated** `VisualRoot`, the mesh cache's sharing, and the `part_visual` tag suppressing every mesh while touching no collider |
| `test_chase_camera` | *(session 20; not yet swept)* doc 11 §13.4's heading rule including the degenerate hold, §13.5's frame-rate-independent lag, and the short-arc heading delta |
| `test_reticle_states` | *(session 20; not yet swept)* doc 11 §14.3's five states, their tokens by value, and §10 rule 5's shape distinction |
| `test_crater_profile` | *(session 22)* doc 09 §3.1's C0 continuity at both boundaries, the cube-root depth law, §7.1's 0.39 m rim by value, and §3.3's ejecta fraction — the last of which is what stops the amended claim being un-amended |
| `test_ground_math` | *(session 22)* §2.1's dimensions and their mutual consistency, the centred world mapping and its no-fold rule, quantisation clamping rather than wrapping, and §2.4's shared-sample counts at a seam (2), a corner (4) and the world edge (1) |
| `test_ground_deform` | *(session 22)* the bowl-and-rim shape, §9.2's reclassification, every copy of a shared sample agreeing, the erosion clamp asymptoting while still doing something on the fortieth shell, coalescing, §8.2's determinism by hash over two independently built arrays, and a replicated request reproducing an authored field exactly |
| `test_ground_terrain` | *(session 22)* the collision shape agreeing with the height data at five world positions, the field not being transposed, an Assembly settling on terrain rather than through it, collision resident only near an anchor, and a contact in a crater reading `DEFORMED` |
| `test_manifold_checker` | *(session 22)* all six cases the engine's CSG was probed on, including the two a naive index-based predicate gets wrong — a split-vertex `BoxMesh` and a `SphereMesh`'s pole fans — plus a duplicated face, which a boundary-only check passes |
| `test_ai_target_selector` | *(session 23)* doc 07 §10's four weights by value, the team filter, the range gate in both directions, the tie-break order, and §10.3's error model — reproducible at one seed, different at two, growing with range and shrinking with difficulty |
| `test_ai_driver` | *(session 23)* doc 05 §15.7.1's bearing and its flattening, the steering sign in both directions, saturation, §15.7.2's authority ceiling and the **sign of the yaw damper**, and each family's stand-off by value |
| `test_recoil_geometry` | *(session 24)* doc 01 §14 rule 27 in both halves — the authored bore against the footprint centre and the width parity against the Core Module's — then the same quantity off the live mount, and §4.37's finding: a traversed round yaws the hull by a multiple of an on-axis one |
| `test_ai_engagement` | *(session 23)* the whole chain end to end: a scan, a target, a 180° turn, an approach, a mount converged, a round fired, a store decremented by exactly the shots, integrity taken off the target — plus §15.7.4's fire discipline and §10.2's arc penalty by value |
| `test_detachment_scheduler` | …and, since session 23, that the scheduler announces **no** termination. It used to assert the opposite, which is what kept doc 04 §8.2's duplicate producer alive for seven sessions |
| `test_part_registry_validator` *(rule 27)* | *(session 24)* a bore on the pivot rather than on an even-width footprint's centre, one half a metre off it, an odd-width direct-fire module against an even-width Core Module — and both exemptions, an arced module and a melee one |
| `test_match_outcome` | *(session 25)* doc 11 §16.1's four rows, including the two nothing in an arena can stage, and §16.2's three titles, details and tokens |
| `test_match_conclusion` | *(session 25)* **one Assembly terminated twice taking its team out twice** — caught on the file's first run, before the guard existed — plus concluding twice on a mutual kill, an unregistered Assembly deciding a match, and the standing list's ordering |
| `test_input_prompt` | *(session 25)* doc 11 §14.6's binding lookup: two keys naming themselves distinctly, a modifier surviving into the glyph, the unnamed-mouse-button format branch, an undeclared action reading as unbound, §7.2's device match in both directions, and every caption being in the string table |
| *the runner itself* | `_process` returning `true`; the coroutine not awaited — both truncate the suite and both are detected by the check count, not by a failure |
| *nothing* | node adjacency tested in one direction only — see §5 |
| *nothing* | a probe claimed into two axle pairs — see §5 |
| *nothing* | anti-roll pushing both ends of an axle the same way — see §5 |
| *nothing* | a hard-coded steer lock — see §5 |

---

## 3. The sweep scripts

Five committed sweeps, 100 faults between them, all driven by
`tools/ci/sweeps/sweeplib.py`. Run them with `-j4`; a full pass over one script
is a couple of minutes.

| Script | Covers | Faults |
|---|---|---|
| `engagement_sweep.py` | the paths the engagement files rest on (sessions 15–16) | 14 |
| `garage_edit_sweep.py` | doc 02 §9's editing model and §10's mirror: the command stack, removal's announcement, `from_context`'s order, `children`'s ordering, the reflection | 16 |
| `combat_layer_sweep.py` | damage, effector and projectile layers (session 14), plus doc 07 §15 (session 18) | 45 |
| `ai_layer_sweep.py` | `src/ai/`, doc 05 §15.7, doc 07 §10, doc 01 rule 27 | 13 |
| `match_layer_sweep.py` | doc 11 §16's outcome rule, §14.3's target bracket, §14.6's binding lookup, doc 05 §15.7.5's ladder | 12 |

### What still survives, and why

| Fault | Script | Why it is kept |
|---|---|---|
| `self-immunity-zero` and `self-immunity-always-on` | engagement, combat | Doc 07 §12.3 is inert **in both directions** on the shipped builds: the nose mount emits 2.75 m ahead of the lattice origin, clear of every hull. A mechanism no engagement can distinguish from either of its extremes is carried, not tested. Closes when a module ships with its muzzle overhanging its own hull. |
| `cyclic-not-cone-clamped` | engagement | Two 14° deflections clamped per axis compose to 19.8° and the hover simply asks for less next tick — a closed loop absorbing a fault in the quantity it closes over. Closes with a unit test of `RotorSolver.thrust_direction`, where the demand is open-loop. |
| `same-part-twice-allowed` | engagement | A coverage regression, not a gap that was never filled: it was caught before the penetration budget became lifetime-scoped and is not caught after. Closes when a part ships with two collider primitives along one axis. |
| `melee-modules-emit` | combat | Four owners of one invariant, reduced to three. Each of the three enforces it alone, so no single deletion is visible. |
| `debris-transform-before-shapes` | combat | Doc 04 §6's ordering rule. **Known unverifiable by the obvious route**: the physics step a test needs in order to read a current pose is the same step that repairs the fault. Two attempts are recorded in `HANDOFF.md`; the honest position is that the rule is defended by the comment in `island_detacher.gd`. |
| `aim-point-read-from-scan` | ai | Doc 07 §10 runs selection at 2.9 Hz and aim solving every tick; collapsing them aims at where the target was up to 350 ms ago. Marginal rather than firmly untested — CAUGHT on one run and SURVIVED on the next, either side of an unrelated change. What closes it properly is an engagement in which the AI's target is *driving*. |

`breakaway-never-releases` was a deliberate standing survivor and is no longer
one: deleting the arrival brake left `test_ai_engagement`'s rounds floor
sensitive to a driver that orbits its stand-off, which sustained throttle also
produces. It is caught on the flat slab, and the terrain behaviour that made it
worth a session is still invisible to the suite — only a capture sees that.
