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

**It is a game with a loop, and the loop now forgives a mistake.** `godot --path .`
opens on a menu. The menu opens a garage, where a wheeled Assembly is standing on
the Build Lattice with a catalogue of thirteen parts beside it and its mass,
power, mounts, top speed, integrity and rollover threshold on the right. Ctrl+Z
takes back a misclick, a removal that would orphan something asks first, and
RESET asks before it throws the build away. TEST DRIVE puts that build — the one
on the screen, whatever the player has done to it — into a basin with 15 m of
relief against three opponents. They fight. A card says which way it went and
names the two keys that fight again or go back to the garage.

**What it lacks now is depth rather than shape.** One arena, one opponent recipe,
no mirroring, and a build that is hard to *see*: at the shipped tints the Core
Module, the panels and the Prime Mover are one dark mass.

**84 files, 5874 checks, 0 failures.**

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

**84 files, 5874 checks, 0 failures.**

`run_all_checks.sh` fails on any engine error printed during the suite, not only
on recorded assertion failures (`LEARNED_FACTS.md` §1 fact 34). That is why
nothing in `src/` may `push_error` on a state a test deliberately exercises — a
blueprint naming an unknown part warns instead.

**A full run is about 200 seconds** — 14 s of reimport and the rest suite. Three
files are most of it: `integration/test_screen_flow.gd` at 91 s,
`physics/test_ground_terrain.gd` at 41 s and `integration/test_ground_deform.gd`
at 30 s. The runner prints per-file timings, so check before assuming where the
cost is.

**`test_screen_flow` is now the most expensive file in the suite and it is worth
knowing why before shortening it.** It opens two real `MatchScreen`s — each a
Ground Array, primed collision streaming and four Assemblies, about 45 s — and
those are the two exits a player has: a test drive carrying the build they made,
and a rematch carrying the same one. The rematch was wired to the menu by a slip
during this session and *nothing* caught it: the suite was green, the capture
showed the end card naming the right key, and the key went to the title screen.
That is what the second arena buys. If this ever has to come down, the honest
lever is making a match cheaper to construct — the cost is doc 09's collision
prime, not the flow.

`tools/ci/run_all_checks.sh` takes two flags, both for sweeps rather than for
people: `--no-import` skips the reimport when nothing under `data/` changed, and
`--fail-fast` stops at the first failing file. There is deliberately **no way to
reorder or subset the run** — see `LEARNED_FACTS.md` §1 fact 62 for the
measurement that closed that door.

**A full sweep is about two minutes**, not the twenty it used to be. Run them
with `-j4`:

```bash
python3 tools/ci/sweeps/ai_layer_sweep.py            # all of them, 4 workers
python3 tools/ci/sweeps/garage_edit_sweep.py         # doc 02 §9: undo, removal, order
python3 tools/ci/sweeps/ai_layer_sweep.py --list     # just the fault names
python3 tools/ci/sweeps/ai_layer_sweep.py -j1 --full steer-sign-flipped
```

There are five of them and `CHANGE_LOG.md` §3 says what each covers. A sweep's
`BASELINE` is a check count and moves with the suite; update it in the same
change as anything that moves the count.

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
thing is any good to play. **Section 3's ordering comes from here.**

Captured with `LEARNED_FACTS.md` §1 fact 55's route at 1600×900: the boot flow,
and the garage on its own through `--main-scene`, which is the cheap way to look
at one screen without driving the menu.

**Building is no longer typing without a backspace.** UNDO · Ctrl+Z and REDO ·
Ctrl+Shift+Z sit in the toolbar naming their own bindings and are correctly
greyed out on open; a removal that would orphan something says how many parts
rest on it before doing anything; RESET says it cannot be undone before
discarding the build. Two things a player would have met are gone: a station
removed from the shipped starter used to leave the contact it was carrying
hanging in the air as a mesh with nothing behind it, and a build that had been
edited — anything removed and anything then placed into the hole — could hand
the match a blueprint that refused halfway through, so the test drive arrived
with a build the player had not made.

Ranked by what would most improve a first-time player's experience:

1. **You cannot see what you are building.** In the capture the Core Module, the
   panels and the Prime Mover are one dark mass, the two visible contacts are
   pale blocks, and the shape reads as a blob rather than as a machine. The
   greybox class tints (doc 13 §5) are all low-value blues and greys against a
   dark background. This is now the first thing a player meets and the cheapest
   large thing left — a lighting change and a tint spread, not new geometry.
2. **Every build is placed one part at a time down both flanks.** Doc 02 §10's
   mirroring is written and unimplemented and `build_mirror_toggle` has a binding
   and no consumer. The shipped starter is four stations and four contacts, half
   of them the mirror of the other half.
3. **The wheels are boxes, and they are drawn where the part was placed rather
   than where the suspension put them** (§3.4). In the garage they are four pale
   blocks under a hull; in the match they hang in the air on every crest.
4. **You still cannot drive and shoot at the same time** (§3.3). Unchanged, and
   the oldest thing on the list.
5. **One arena and one opponent recipe.** Every test drive is the same three
   wheeled builds at the same three spawns on the same basin. The scene is
   parameterised for none of it, and doc 06's generator is the intended answer.
6. **The garage teaches nothing about *composition* until a placement is
   refused.** The status strip names the reason and the inspector names the
   figures, and neither says that a rotor disc needs a mast under it and a second
   disc opposite it, or that supply goes on before draw.
7. **The opponents still shoot each other**, less than they did, and nothing in
   `src/combat/` knows what a team is (§3.5).
8. **A destroyed part still simply vanishes**, because `VisualDamageController`
   (doc 08 §9) is unwritten.
9. **A walking build turns 170° in five seconds while commanded straight ahead**
   (§3.7), and a player can reach that build — the garage will let them fit
   limbs.

**The bad news, plainly.** Two of the three things this session fixed were
defects a player would have hit in their first few minutes, and both had been
sitting behind a comment that asserted the opposite. Neither was found by the
suite, which was green through both of them; both were found by reading a
docstring's justification and checking whether the code kept it. That is worth
carrying forward more than the undo stack is — see `LEARNED_FACTS.md` §2's
opening lessons. And the confirmation dialog still does not highlight the parts
it is about to take, which doc 11 §9.1 asks for; the count is the honest half.

The summary: **the loop is worth going round and the garage is now safe to
experiment in.** What it is not yet is legible — a player can build, but not
easily see what they have built — and that is what the next session should take.

---

## 3. The work queue

Ordered by what is worth doing next, not by dependency. Anything not listed here
is either done or is in section 4.

### 3.1 Symmetry mirroring — the top item

Doc 02 §10 is written and unimplemented, and `build_mirror_toggle` has a binding
and no consumer. Every build a player makes by hand is placed one part at a time
down both flanks — the shipped starter is four stations and four contacts, and
half of those placements are the mirror of the other half. It is the difference
between building a machine and typing one in twice.

It is also cheaper than it was: `BuildHistory` is the place a mirrored pair goes
in as **one** command, so a mirror that half-succeeds does not leave the player
undoing twice. `BuildCommand.placements` is already a list for the cascade's
sake, so a mirrored attach is two entries in it and `undo` needs no new shape —
what it needs is for `_erase` to take them all rather than the first.

§10's rule that a refused mirror still commits the primary, with a non-blocking
notification, is the part to get right: the toast exists nowhere yet and the
status strip is where this garage puts that kind of sentence.

### 3.2 Make the build legible

The §2 capture's finding, and now the first thing a player meets. At the shipped
greybox tints the Core Module, the panels and the Prime Mover are one dark mass
against a dark background; the two visible contacts read as pale blocks stuck to
it. A player cannot tell what they have built, which undermines the inspector
that tells them what a part does.

Three levers, cheapest first, and doc 13 §5 owns the tints:

- **Spread the class tints in value, not just in hue.** They are all low-value
  blues and greys. A Prime Mover that is plainly lighter than the panel beside it
  costs one table edit.
- **Light the preview from two sides.** `GaragePreview._build_environment` has
  one key light; a fill at a different angle is what makes an edge an edge.
- **Outline the part under the pointer.** The inspector already knows which slot
  is hovered and nothing on the screen shows the player which part that is.

This is also what doc 11 §9.1's unbuilt half needs — highlighting the parts a
removal is about to take — so the per-slot tint path is worth building once.

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

**A player can now reach this and could not before**: the garage's catalogue
carries the Appendage and the edge, so a build with one is a build somebody will
make. `CombatArena` has five recipes and none carries an Appendage, so the melee
weapon landed in session 18 has never been in a fight. What it needs: a `MELEE` recipe
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
  decides that the wreck stays, which is right. What follows it is now §15's
  loop — fight again, or go back to the garage — and what is still missing is a
  `SpawnDirector`, so a match is over the moment the player's Core Module goes
  rather than putting them back in.
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
- **Doc 11 §9.1's confirmation does not highlight what it is about to take.** It
  names the count, which is the half a player acts on; highlighting wants a
  per-slot tint on the preview, and building a second one before doc 08 §9's
  `VisualDamageController` is how the two end up disagreeing. Owned by §3.2.
- **The confirmation counts dependents, and the status strip counts the
  cascade.** The two numbers differ whenever an orphan finds another parent, and
  that is deliberate: what the cascade will be is only knowable by performing the
  removal, so asking first can only name the upper bound. Doc 02 §9.2 records it.
- **Doc 02 §9.3's `REPAINT` and `REORIENT` kinds do not exist**, because no
  operation produces them — there is no tint editor and no in-place reorient.
  They arrive with those operations.
- **The compact tier has no bottom sheet.** Doc 11 §3.2 gives it one and
  §4's tree names it; below 900 logical units wide the garage hides its docks and
  a player is left with a toolbar and a 3D view. A phone cannot build.
- **`PartIconCache`, `TierPalette`, `Inventory` and `PartTooltipBuilder` do not
  exist**, and doc 11 §5.3 binds all four. The card shows the greybox class tint
  instead; the amendment is recorded in that section.
- **`GarageLayoutController` and `touch_placement_controller.gd` are not written.**
  `GarageScreen` applies the breakpoint itself, which is the same code in one
  fewer file, and doc 11 §7.3's touch model has no consumer at all.
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
- **Nothing verifies that a click actually places a part.** Doc 02 §6's integer
  half is covered by `test_cursor_to_cell`; the float half — a camera in a
  [SubViewport] projecting a ray — cannot be reached headless
  (`LEARNED_FACTS.md` §1 fact 28), so the one thing that was checked by hand and
  is checked by nothing is the ray itself.
- **The control card has no first-run flag.** Doc 11 §14.6 raises it on every
  entry to a match because there is nowhere to store "they have seen it", which
  is `SyndicateSettings` work and is waiting on there being more than one match.
- **`cam_pan` has a keyboard/mouse binding and no consumer.** `cam_orbit` found
  one in the garage; `cam_pan` is still waiting on it. Session 20 added four
  analogue `cam_look_*` actions for the match camera rather than overloading
  `cam_orbit`, which is a single action and cannot express two axes (§4.27).
- **Nothing verifies the confirmation dialog's own presentation.** The screen
  flow file asserts that RESET does not edit the build until it is agreed to and
  that agreeing works, which is the rule; whether the dialog is legible, sized,
  or dismissable by the keyboard is capture work and has not been done.
- **The suite is about 200 seconds and `test_screen_flow` is most of it**, at
  91 s for the two `MatchScreen`s it opens (§1). Inside `tests/physics/`, three of
  the four multi-Assembly files soak for hundreds of ticks by construction, and
  the two that time out — the ambulatory mirror and the five-a-side — spend their
  full budget every run on purpose. If the wall time ever becomes a problem, the
  honest levers are making a match cheaper to construct and closing §4.21 so the
  ambulatory mirror reaches a decision, not shortening any window.
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
