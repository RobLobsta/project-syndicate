# HANDOFF

**The work queue.** What to do next, in the order it is worth doing.

`CLAUDE.md` and the thirteen documents in `/docs/` are the only authority. This
file has none — it is a plan, and it is the one file in the repository that is
allowed to be wrong about the future.

Two companions, and neither is optional reading:

- **`LEARNED_FACTS.md`** — engine behaviour that cost somebody an afternoon,
  testing rules paid for in shipped defects, and readings of the architecture
  decided once. **Read §1 before writing code and §3 before writing a test.**
- **`CHANGE_LOG.md`** — what each session did and what each test defends. Read
  it when you need to know when something changed and why.

There is also a `JULES.md` at the repository root: the operating charter for a
read-only review agent (Google Jules). It grants no authority and nothing here
depends on it.

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

## Where this stands

**It is a game with a beginning and an end, and no second one.** `godot --path .`
opens on a basin with 15 m of relief, tells you which keys do what, and puts
three opponents on you. They shoot you to pieces in about a minute, a card says
so, and the camera lets go of the wreck. The fighting works and is still the best
thing in the project. What it now lacks is the thing immediately after the
ending: **there is no way to play again except to relaunch.**

**76 files, 5258 checks, 0 failures.**

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

**76 files, 5258 checks, 0 failures.**

`run_all_checks.sh` fails on any engine error printed during the suite, not only
on recorded assertion failures (`LEARNED_FACTS.md` §1 fact 34).

**A full run is about 95 seconds** — 14 s of reimport and 78 s of suite. Two
files are most of it: `integration/test_ground_deform.gd` at 30 s and
`physics/test_ground_terrain.gd` at 27 s. The runner prints per-file timings, so
check before assuming where the cost is.

`tools/ci/run_all_checks.sh` takes two flags, both for sweeps rather than for
people: `--no-import` skips the reimport when nothing under `data/` changed, and
`--fail-fast` stops at the first failing file. There is deliberately **no way to
reorder or subset the run** — see `LEARNED_FACTS.md` §1 fact 62 for the
measurement that closed that door.

**A full sweep is about two minutes**, not the twenty it used to be. Run them
with `-j4`:

```bash
python3 tools/ci/sweeps/ai_layer_sweep.py            # all of them, 4 workers
python3 tools/ci/sweeps/match_layer_sweep.py         # doc 11 §16, §14.3, §14.6
python3 tools/ci/sweeps/ai_layer_sweep.py --list     # just the fault names
python3 tools/ci/sweeps/ai_layer_sweep.py -j1 --full steer-sign-flipped
```

Workers run in throwaway copies of the project under `/tmp`, so `-j2` and above
cannot leave a planted fault in your checkout. `-j1` still patches in place, and
the old rules apply to it: do not `git add -A` while it runs, and check
`git status` after. A run that wedges is killed at 420 s and reported as
`CAUGHT-HUNG` rather than hanging the sweep, which it used to do.

Still true regardless of speed: build a fixture once in `before_all` and reset it
per test; four tests that each spawn an Assembly spawn them on top of each other.
See `LEARNED_FACTS.md` §1 facts 36 and 44 before adding to `tests/physics/`.

---

## 2. The player-experience review (CLAUDE.md §10 rule 17)

Recorded every session, because a green suite says nothing about whether the
thing is any good to play. **Section 3's ordering comes from here**, and in
session 24 this was the only instrument that caught a change which had improved
every measurement in the suite and stopped the game being a game.

**It is still a fight, and it is still the best thing here.** `godot --path .`
opens on a basin with 15 m of relief: a wheeled Assembly under a sky, three
opponents standing off at 34 to 46 m, a chase camera behind you, a HUD reading
integrity, power, ammunition and part count — and now a card, up for eleven
seconds, that says `W / S`, `A / D`, `Mouse`, `Left Mouse`, `C`, `Wheel Up /
Wheel Down`, `Escape`, and that `Tab` shows it again. Every one of those strings
is read out of `InputMap` at the moment the card is raised, so a rebind is on it.

Captured with `LEARNED_FACTS.md` §1 fact 55's route, 900 frames, no player input
at all. The card is legible from frame 1. By frame 340 the three are at contact
range, the player is at 51% with a component gone and the feed saying so, and the
target bracket is lighting on a hull. Somewhere in the last third — frame 615 on
one capture and 520 on the next, which is `LEARNED_FACTS.md` §1 fact 44 and not a
defect — the Core Module goes, the end card comes up in `danger` reading CORE
MODULE DESTROYED, the reticle goes with it, the controls come off the wreck and
the camera goes to orbit.

**And then the wreck flies away at ninety metres a second**, which is the
session's largest finding and the one nobody could have seen before, because
until this session the camera was bolted to a corpse and nobody was looking at
what the corpse did next.

Ranked by what would most improve a first-time player's experience:

1. **A destroyed Assembly's remains accelerate instead of settling.** Measured off
   the capture: 17.3 m/s at the conclusion, 18.1 m/s ten frames later, **92.0 m/s
   at frame 670** — the hulk crossing the basin and climbing. `MotiveSystem.step`
   has no liveness guard, so a build whose Core Module has gone keeps solving
   suspension and traction against contacts it no longer has the mass to load.
   This is now the last thing a player sees, every time. Owned by §3.1.
2. **There is no way to play again.** The match ends properly now and then stops
   being a game: no restart, no menu, no return to anything, because §15's screen
   flow has exactly one scene in it. A player who loses in a minute must quit the
   process and relaunch. A direct consequence of finishing the previous session's
   top item — the ending exposed the absence of everything after it.
3. **You still cannot drive and shoot at the same time** (§3.3). Unchanged and
   still a design question with real answers: the recoil is applied at a mount
   2.25 m forward of the centre of mass, so a traversed gun yaws the hull at
   48°/s a round and a player who holds the trigger while turning will spin.
4. **The control card covers the screen for the whole approach.** Eleven seconds
   is the right length to read it and most of the time the fight takes, so on the
   capture it is up from the spawn to first contact. It was centred over the
   player's own Assembly until the capture showed it; it now sits in the upper two
   fifths. Whether it should also shorten, or dismiss on the first command input,
   wants a second look with somebody actually playing.
5. **The vehicle is small in frame**, about a sixth of the screen height, and the
   fight now happens at six metres. Still worth an A/B.
6. **Nothing renders a wheel at its contact point** (§3.4). The greybox contacts
   are drawn where the part was placed, not where the suspension put them, so on
   15 m of rolling terrain the wheels hang in the air on every crest.
7. **The opponents still shoot each other**, though less. §15.7.5's ladder spaces
   three converging drivers at 6 m, 10.5 m and 15 m instead of stacking them, so
   they are no longer in each other's line for the whole engagement — but nothing
   in `src/combat/` knows what a team is and a round that reaches a friend still
   does full damage (§3.5).
8. **A destroyed part simply vanishes**, because `VisualDamageController`
   (doc 08 §9) is unwritten. More noticeable now that the camera is pointed at the
   wreck on purpose.
9. **A walking build turns 170° in five seconds while commanded straight ahead**,
   and **the edge has still never been in a fight** (§3.7). A player cannot reach
   either; the match scene spawns wheeled builds only.

The honest summary: **the game now has a shape — you are told how to play, you
fight, and you are told how it ended — and it stops dead at the end of it.**
Everything the previous four sessions said was missing around the fight is there.
What replaced it is smaller and sharper: a player who has just been shown a
result has nothing to press.

---

## 3. The work queue

Ordered by what is worth doing next, not by dependency. Anything not listed here
is either done or is in section 4.

### 3.1 A wreck must not accelerate — the top item

Measured off this session's capture: at the moment the player's Core Module is
destroyed the body is doing 17.3 m/s, and fifty frames later it is doing **92.0
m/s**, climbing and crossing the basin. It is now the last thing a player sees,
every time, and doc 11 §16.2's end card was briefly claiming the opposite in
words on the screen.

`MotiveSystem.step` has no liveness guard. Invariant I-2 makes an Assembly over
when slot 0 goes; the motion layer never hears about it and keeps solving
suspension and traction, against contacts belonging to a build that has just shed
most of its mass to the debris pool. Small residual forces on a small residual
mass are a large acceleration.

**Do not fix this by guessing.** Doc 05 §3.4 deliberately keeps the coupling
torque running on a wreck, and says why — a tumbling hulk is where an asymmetric
tensor is most visible — so "stop everything on termination" contradicts a
documented decision. The question the document does not answer is whether the
*families* should keep running, and that is the section to amend.

Two things to have in hand first: the measurement above, repeated with
`test_family_duels`' losers rather than only the player's build, and the mass the
body is left holding once its islands have detached. `MassSolver.MASS_FLOOR_KG`
is 0.001 kg and `LEARNED_FACTS.md` §1 fact 24 records that the engine refuses a
zero mass outright, so a body sitting near that floor with an ordinary suspension
force still on it is the likely mechanism — **likely, and not yet confirmed.**

### 3.2 A way to play again

The match concludes, the card says which way it went, and then nothing. Doc 11
§16.3 records the gap deliberately: a restart needs a screen flow §15 does not
have, because `scenes/boot/main.tscn` picks one scene and instantiates it.

The smallest honest version is a **restart binding on the end card** that frees
the match scene and instantiates a fresh one — which is a real test of whether
the teardown in `MatchScreen._exit_tree` is complete, and `LEARNED_FACTS.md` §1
facts 45, 48 and 53 all say it is the kind of thing that goes wrong quietly. The
larger version is §15's missing menu and `SpawnDirector`, and it is the one that
eventually has to exist.

Do the small one first and find out what leaks.

### 3.3 Decide what a build does about recoil at a traversed mount

Unchanged from session 24, and now the oldest thing on the list. The recoil is
applied at the muzzle and the mount sits 2.25 m forward of the centre of mass, so
a traversed gun yaws the hull at 48°/s a round.

Three candidates, and they are genuinely different games:

- **Mount position.** A gun over the centre of mass rather than on the nose.
  Costs the pitch behaviour the nose mount was chosen for, and makes where a
  player puts a gun a real trade. Cheapest to try: a cell coordinate in
  `CombatArena` and `MatchScreen`.
- **A smaller recoil impulse.** 1450 N·s is roughly three times a real 30 mm
  round's momentum. Probed at 500 N·s: the driver fires more and still cannot
  turn, so this alone does not close it. `balance-review`, and it moves every
  engagement at once.
- **Live with it and make it legible.** A player who understands that shooting
  sideways spins them has a tactic; one who does not has a bug. Doc 11 work.

`tests/physics/test_recoil_geometry.gd` reports the lever and the yaw per round
and is the instrument. Measure before choosing.

### 3.4 Make the wheels follow their contacts

`spawn_visual` draws a Motive Assembly at the cell it was placed in, not at its
probe hit point, so suspension travel is invisible and a limb does not bend. On
15 m of relief the wheels hang in the air on every crest. This is the cheapest
large improvement to how the game *looks* that is available; doc 05 does not
cover it and should. `AssemblyRuntime.visual_of(slot)` is the hook and the
contact's `point_world` is the answer.

### 3.5 Decide whether friendly fire exists

§15.7.5's ladder fixed the *geometry* — three drivers converging on one target no
longer stand in each other's line — and deliberately did not touch the rule.
Nothing in `src/combat/` knows what a team is: `DamagePacket` names a source
Assembly and `DamageResolver` never asks whose side it is on, so a round that
reaches a friend does full damage.

That is doc 08's question and it is a real one, not an oversight. The roster
already exists on `AiContext` and the match layer owns it; what does not exist is
a decision about whether the resolver should be told.

### 3.6 Sweep the bounds nobody reaches

Invariant I-12 lists eighteen bounds and the suite demonstrably reaches almost
none of them. Deleting each in turn and watching for green is a cheap way to find
out which are load-bearing — and it is now genuinely cheap, at a couple of
minutes a sweep. The fixture that closes one has to be built to *exceed* it and
then to assert that it exceeds it. Likeliest to be untested: chain-reaction depth
3, collapse cascades, melee sweep segments, and the two debris caps.

### 3.7 Fight with the edge

`CombatArena` has five recipes and none carries an Appendage, so the melee weapon
landed in session 18 has never been in a fight. What it needs: a `MELEE` recipe
(the wheeled layout with `apx.arm.manipulator.t3` and `eff.melee.beam_edge.t4` in
place of the autocannon), a stand-off of roughly zero, and one duel against
`WHEELED_LIGHT`. Expect the edge to **lose** on the first run and treat that as a
measurement: 640 damage a swing has to survive a 26 m approach into 120 damage a
round at seven a second, and §15.4's own impulse shoves the target 7 m/s clear of
a second swing.

### 3.8 A stability-augmentation layer, and the rotary family

`CombatArena._fly` is three loops through `ControlInput` and is still the only
thing in the repository that can hold a hover. A **player** flying a rotary build
needs the same loops, so it is not a tactic and does not go in `AiDriver`. It
wants a layer between both `ControlInput` producers and the motion layer, which
doc 05 does not have. An `AiDriver` handed a rotary Assembly aims and fires but
does not fly.

### 3.9 §15.5's sustained contact, and `DotScheduler`

Two small, self-contained pieces of doc 07 and doc 08. `eff.melee.beam_edge.t4`
authors sustained contact, `MeleeSolver.sustained_channel_damage` is written and
unit-tested, and nothing calls it — one line clears the target set per swing
instead of per tick. `DotScheduler` (doc 08 §7.3) is about sixty lines and is the
difference between thermal damage that resolves correctly when submitted and
thermal damage that actually burns.

### 3.10 The rest of document 10

Comparable in size to what document 09 cost, in dependency order: the CSG bake
(doc 10 §3.1–§3.2), fragment decomposition (§3.3), support graph and collapse
(§3.5, §5), runtime slicing (§6), fragment bodies (§7), and the `StructureArchetype`
generator. `ManifoldChecker` — the blocking gate that makes DCC authoring
survivable — is built and tested. Worth knowing before starting: a Voronoi cell
is an intersection of half-spaces, so for a *convex* Section this is repeated
plane slicing and needs no CSG at all.

### 3.11 Smaller, and worth doing when passing

- **The camera can still end up inside the wreckage.** `LEARNED_FACTS.md` §1 fact
  56's `cast_motion` clamp does its job against ground and Static Volumes, and
  debris is not in the mask. At contact range the player finishes inside a pile of
  debris bodies, and the orbit camera §16.2 now hands them is orbiting the inside
  of a box. Adding `LAYER_DEBRIS` to §13.7's mask is one constant.
- **A second steered wheeled row.** Makes one of the three surviving uncaught
  faults visible, gives rule 13 a second tier, and gives the garage a real choice
  on the front axle.
- **A second tier of the rotor family.** The cheapest way to make rule 13
  non-vacuous. `mot.rotor.main_single.t3` is worth authoring for its failure mode
  alone: `torque_reaction_ratio = 1.0` and no yaw authority, so a build carrying
  one alone spins under its own reaction torque and cannot stop.
- **Widen the authored depression, or decide not to.** 8° is a turret ring on
  flat ground and nothing in this game is on flat ground for long. Measured,
  reverted, recorded in doc 01 §10.5; it is a `balance-review` decision.
- **Ruts have never been seen.** Everything is implemented and tested, but the
  arena's baseline surface is `COMPACTED`, which is not ruttable. The slope rule
  produces `LOOSE` on the hillsides, so this may already work and simply not have
  been looked at. **Go and look before changing anything.**
- **`tests/generation/` is empty** and `test_constant_ownership` is not written.
- **CLAUDE.md §8's prohibited terms are enforced in `src/` and nowhere else**,
  and `tests/` has drifted — `_build_walker`, `GUN_KEY`, `_guns_a`. Either
  `test_no_forbidden_patterns` should scan `tests/` too or §8 should say it does
  not; right now the rule is binding and unenforced.

---

## 4. Known gaps — deliberate, not oversights

Things that are missing on purpose, or that are understood and not yet worth
fixing. None of these is a surprise waiting to be found.

### The motion layer
- **`MotiveSystem.step` has no liveness guard, and a wreck accelerates.** Measured
  at 17.3 m/s rising to 92.0 m/s over fifty frames after the Core Module went.
  Invariant I-2 ends the Assembly and the motion layer never hears about it. Doc
  05 §3.4 deliberately keeps the coupling torque running on a wreck and does not
  say whether the families should keep running; that is the section to amend.
  Owned by §3.1.
- **There is no stability-augmentation layer, and a rotary Assembly needs one to
  exist in a test.** Owned by §3.8.
- **The ambulatory gait drifts in yaw and no steering demand can null it.**
  §4.21, measured at 170° over five seconds, and now the family's limiting
  defect. It wants a heading term in doc 05 §13, which §13.8 currently forbids
  by omission.
- **An ambulatory Assembly still cannot be asked to turn and travel
  independently** (§4.16). Less painful than it was — the one steering number
  now turns the right way — but still one number doing two jobs.
- **`handbrake` and `boost` have producers and no consumers.** `ControlSystem`
  writes both — `AiDriver` writes neither, deliberately: a driver that used a
  handbrake nothing implements would be writing a field for a behaviour that does
  not exist. Nothing in `src/motion/` reads either. Doc 05 does not define what
  a handbrake does to a contact and inventing it here would be worse than the
  gap.
- **Nothing consumes `AeroSolver`, and no `ctl.*` part is authored**, so drag,
  downforce, and Control Surfaces have never acted on a moving Assembly. It is
  complete and matches doc 05 §8; what it needs is a per-part pressure-centre
  pass in `MotiveSystem` and a part to hang it on.
- **`_static_load_n` returns `rated_load_kg · g` rather than the distributed
  static load doc 05 §6.4 specifies,** and `SuspensionSolver.retune` is called
  per contact per tick rather than on mass recompute. Neither is wrong
  numerically — `retune` is pure and its inputs are constant between structural
  events — but §6.4 says "fires on mass recompute only" and the code does not.
- **The visual wheel does not follow the contact**, and since the terrain landed
  it is visible rather than theoretical. Owned by §3.4.
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

### Combat
- **An Assembly cannot drive and fire at the same time.** The muzzle offset that
  was blamed for it is closed and the behaviour is unchanged; the lever is the
  mount's position, not the bore's. Owned by §3.3.
- **Only direct fire is implemented.** Doc 07 §5.3's arced solve, §5.4's guided
  ordnance, §10's AI target acquisition and §11's prediction are not written. A
  module of a kind that needs one aims correctly and declines to fire, which is
  the failure mode to prefer.
- **No engagement has ever been fought at contact range.** Owned by §3.7.
- **§15.5's sustained contact is not implemented.** The edge authors it, the
  solver computes it, and nothing calls it. Owned by §3.9.
- **A melee strike can never ricochet**, because its packet's normal is derived
  from its own direction. Not a defect — the query reports no surface normal —
  but see §5 before assuming doc 08 §4's angle gate means anything here.
- **`DotScheduler` is not written** (doc 08 §7.3), so thermal and corrosive
  packets resolve correctly when submitted and nothing submits them over time.
  Owned by §3.9.
- **`VisualDamageController` is not written** (doc 08 §9) and neither is §10's
  repair path. Repair is the more interesting of the two: it must route through
  `DamageResolver` so that a band transition upward fires the same signal as one
  downward, and nothing else may write integrity.
- **The shipped weapon's lethality was the overpenetration bug.** §4.13's last
  paragraph. With rounds stopping at the first part they defeat, nothing in the
  shipped set kills anything. The bound at four parts is what keeps the fights
  decidable, and moving it is a balance change that has to be measured as one.
- **8° of depression is a real constraint and widening it is not free.** §4.22.
  Measured, reverted, recorded in doc 01 §10.5; the decision is open.
- **Nothing in `src/combat/` knows what a team is, and two things now do.**
  `DamagePacket` carries a source Assembly and the resolver never asks whose side
  it is on, so friendly fire is decided by whichever hull the ray reaches first.
  The roster lives on `AiContext` and on `MatchState`, both owned by the match
  layer. Doc 05 §15.7.5's ladder answers the *geometry* of several drivers
  converging on one target and deliberately not the rule. Owned by §3.5.
- **A destroyed Assembly is never removed and never respawns.** Doc 11 §16.2
  decides that the wreck stays, which is right, and §16.3 records that nothing
  follows it: no restart, no menu, no `SpawnDirector`. Owned by §3.2.
- **`killer_id` arrives on `assembly_terminated` and nothing reads it.** Doc 04
  §8.2's second consumer — scoring — is unwritten, and `MatchState` deliberately
  does not guess at one.
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
- **Two Effector Modules exist, one per resolution path.** Doc 02 §7.6's
  muzzle-offset half-cell discrepancy is still unresolved and still flagged
  rather than silently fixed; the autocannon authors its muzzle half a cell past
  its last occupied cell, which is a choice made in the generator and commented
  there.
- **§4.11 is an open balance question, not a defect.** The shipped chassis cannot
  fire the shipped autocannon without flipping. Either a heavier hull or a
  lighter gun; someone has to pick.

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

### Testing and scenes
- **`tests/generation/` is empty.** The runner walks it and finds nothing.
- **`test_constant_ownership` is not written.**
- **CLAUDE.md §8's prohibited terms are enforced in `src/` and nowhere else, and
  `tests/` has drifted.** §8 bans `walker` outright and bans `gun` in
  identifiers; `tests/physics/test_locomotion_behaviour.gd` has `_build_walker`,
  `WALKER_CORE` and `WALKER_SPAWN`, and `tests/physics/test_duel.gd` has
  `GUN_KEY` and `_guns_a`. Session 15's files use the locomotion vocabulary
  throughout (`AMBULATORY_*`, `_ambulatory_mirror`, `_rotary_mirror`) and kept
  `GUN_KEY` only where `test_duel.gd` had already established it. Either
  `test_no_forbidden_patterns` should scan `tests/` too, or §8 should say it
  does not — right now the rule is binding and unenforced, which is the worst of
  both.
- **`run_all_checks.gd` still tolerates a runtime error on its own.** The shell
  wrapper catches it (`LEARNED_FACTS.md` §1 fact 34). Worth knowing before running the `.gd` directly.
- **The camera can still be buried in debris.** §13.7's `cast_motion` clamp masks
  ground and Static Volumes and not `LAYER_DEBRIS`, so a player who finishes
  inside a pile of wreckage is handed an orbit camera orbiting the inside of a
  box. One constant; owned by §3.11.
- **The control card has no first-run flag.** Doc 11 §14.6 raises it on every
  entry to a match because there is nowhere to store "they have seen it", which
  is `SyndicateSettings` work and is waiting on there being more than one match.
- **`cam_orbit` and `cam_pan` have keyboard/mouse bindings only and no consumer.**
  Session 20 added four analogue `cam_look_*` actions for the match camera rather
  than overloading `cam_orbit`, which is a single action and cannot express two
  axes (§4.27). `cam_orbit` and `cam_pan` are now waiting on the garage, which is
  where doc 11 §7.1 always intended them.
- **The suite is about 40 seconds and `tests/physics/` is most of it.** Three of
  the four multi-Assembly files soak for hundreds of ticks by construction, and
  the two that time out — the ambulatory mirror and the five-a-side — spend their
  full budget every run on purpose. It was 4 min 15 s until `LEARNED_FACTS.md` §1 fact 50; if the wall
  time ever becomes a problem again, the honest lever is closing §4.21 so the
  ambulatory mirror reaches a decision, not shortening its window.
- **§12.3's self-immunity window is inert in both directions.** Setting it to
  zero and pinning it permanently on both leave the suite green, because no
  shipped recipe mounts a module whose muzzle overhangs its own hull. It is
  carried, not tested.
- **Two engagements are asserted as they fail.** `test_family_duels`'s ambulatory
  mirror and `test_team_engagement`'s five-a-side both assert that they run to
  the timeout. Those assertions are correct today and are *supposed* to break:
  when §4.13 or §4.15 is closed, both files fail, and the fix is to re-measure
  and re-assert rather than to loosen them.

  **But re-measure with `LEARNED_FACTS.md` §1 fact 54 in hand.** The brawl in that same file asserted its
  tick count against half the window, and session 20 discovered that the number
  moves when an unrelated integration file spawns and frees Assemblies — 1200
  down to 316, reproducibly, with no change to the combat layer. A tick count in
  a multi-Assembly file is a measurement of the suite. The brawl's bound is now a
  floor on the reversal from 91 ticks rather than a description of the fight, and
  the other two assertions of this shape should be read with the same suspicion
  before anybody re-measures them.

---
