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

**It is a game with a loop, the loop forgives a mistake, the garage builds the
way a player expects it to, the machine drives on the ground rather than over it,
and the fight is now something you are in rather than something that happens to
you.** `godot --path .` opens on a menu. The menu opens a garage, where a
wheeled Assembly is standing on the Build Lattice with a catalogue of thirteen
parts beside it and its mass, power, mounts, top speed, integrity and rollover
threshold on the right. The part under the pointer lights up and the inspector
says what it is. **M** mirrors placements onto the other flank, so a symmetric
build is half the clicks; **Ctrl+Z** takes back a misclick, including both halves
of a mirrored pair at once. A removal that would orphan something asks first, and
RESET asks before it throws the build away. TEST DRIVE puts that build into a
basin with 15 m of relief against three opponents. They fight. A card says which
way it went and names the two keys that fight again or go back to the garage.

**And you can now drive and shoot at the same time**, which is the oldest thing
that was ever wrong with it. The shipped starter carries
`eff.ballistic.repeater_12.t2` — a light, fast module at 26 N·s a round where the
autocannon is 1450 — and the autocannon is still in the catalogue for a build
that means to stand still and punch through hulls.

**And the opponents stop in front of you instead of on top of you.** They used to
close to a six-metre stand-off between two hulls that touch at 4.8 m, arrive at
18 m/s, and drive a stationary player onto its roof at five seconds. Doc 05
§15.7.1 has an arrival brake and a stand-off measured against the colliders, and
the same capture now shows the player upright at ten seconds, at 41% integrity,
trading fire with something that has stopped and is shooting back.

**What it lacks now is depth rather than shape.** One arena, one opponent recipe,
and nothing yet that rewards a good build over a heavy one.

**88 files, 6165 checks, 0 failures.**

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

**88 files, 6165 checks, 0 failures.**

`run_all_checks.sh` fails on any engine error printed during the suite, not only
on recorded assertion failures (`LEARNED_FACTS.md` §1 fact 34). That is why
nothing in `src/` may `push_error` on a state a test deliberately exercises — a
blueprint naming an unknown part warns instead.

**A full run is about 210 seconds** — 14 s of reimport and the rest suite. Three
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

There are seven of them and `CHANGE_LOG.md` §3 says what each covers. A sweep's
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

Captured with `LEARNED_FACTS.md` §1 fact 55's route at 1600×900, 600 frames
through `--main-scene res://scenes/match/arena_basin.tscn` — the cheap way to
look at a fight without driving the menu and the garage first, since
`MatchScreen` falls back to the shipped starter when no blueprint arrives. The
player is not driven, which is the exact case that used to get run over.

**You survive the opening.** The whole of the last session's top finding, gone.
Where the previous capture had an 1107 kg hull on its flank at five seconds and
destroyed at seven, the same scene now reads: **upright and 100% at five seconds,
upright and 86% at seven, upright and 41% at ten**, standing in a firefight with
an opponent that has stopped ten metres away and is shooting back. Three defects
were under that one symptom and §3's history has them; the short version is that
the drivers arrived at 18 m/s at a stand-off six metres long between two hulls
that touch at 4.8 m.

**You can drive and shoot at the same time**, from the session before: doc 01
§10.5's `eff.ballistic.repeater_12.t2` at 26 N·s against the autocannon's 1450,
measured at 2.9° of heading drift and 30 rounds against 99.1° and 2. **And the
wheels are on the ground**, from the one before that.

Ranked by what would most improve a first-time player's experience:

1. **A destroyed Assembly's wreck is launched over the horizon.** Now the top
   item. Doc 11 §16.2 says the wreck stays where it fell and it does not: losing
   the Core Module orphans every part, the islands detach, and doc 05 §3.5's mass
   floor leaves a 1 kg body that the next thing to touch it punts away. Measured
   climbing past 27 m/s under the end card, which is free fall from wherever it
   was kicked to. **§3.1 owns it and it is cheap.**
2. **The controls card sits in the middle of the screen for the whole first
   fight.** `ControlCard.DWELL_S` is 11 s and the opening engagement is decided
   inside that, so a first-time player reads the fight through a legend. It is
   centred, opaque, and covers exactly the band of screen the opponents approach
   through — all three of them are behind it in the frames that matter. Doc 11
   §14.6 raises it on every entry because there is nowhere to store "they have
   seen it"; the placement and the dwell are separable from that and cheaper.
   **§3.2.**
3. **One arena and one opponent recipe.** Every test drive is the same three
   wheeled builds at the same three spawns on the same basin. Doc 06's generator
   is the intended answer.
4. **Nothing rewards a good build over a heavy one** — except which Effector
   Module you fit, which is now a real decision because the two published
   direct-fire rows are good at different things. One axis out of the six the
   stat panel names.
5. **The garage teaches nothing about *composition* until a placement is
   refused.** The inspector names figures; nothing says a rotor disc needs a mast
   under it and a second disc opposite it, or that supply goes on before draw.
6. **The opponents still shoot each other**, and nothing in `src/combat/` knows
   what a team is (§3.3).
7. **A destroyed part still simply vanishes**, because `VisualDamageController`
   (doc 08 §9) is unwritten.
8. **A walking build turns 170° in five seconds while commanded straight ahead**
   (§3.6), and the garage will let a player fit limbs.

**The bad news, plainly.** Four things.

**The suite could not see the ram, and the reason generalises.** Every engagement
fixture in this repository records rounds, ticks, kills and travel. Not one of
them recorded **attitude**, so a build ending the fight on its roof moved no
number and six thousand checks were green through it. That is fixed for roll — the
instrument is twenty lines and `tests/physics/test_ram_attitude.gd` is what it is
for — but the shape of the mistake is not: the fixtures record what the systems
emit, and a player watches what the machine *does*. Ask of any new engagement
assertion what physical state is missing from the record class, not what count.

**Two of the three constants involved were authored against geometry nobody had
measured.** `GROUND_STAND_OFF_M` at 6.0 m, and doc 05 §15.7.5's 4.5 m ladder
step justified in the document as "a little over an Assembly's own length" — the
reference build is 4.8 m long, so the stand-off was inside the hulls and the step
is still under one. The stand-off is fixed. **The step is knowingly left wrong**,
because moving it moves every engagement measurement in `tests/physics/` at once
and it is not what was driving over the player. It is a `balance-review` decision
and it is open (§3.9).

**A parked Assembly never comes to rest.** Found while building the fixture, and
not fixed: a wheeled build with no throttle and no brake reads 0.38 m/s at the
end of a 90-tick settle and still 0.38 m/s after 360, and covers two to three
metres over an engagement. Nothing under doc 05 §7 puts a rolling resistance on a
free contact. A player who lets go of the keys on level ground drifts, which is
small but is the kind of thing that reads as the vehicle being broken (§3.9).

**And the drivable module still loses a straight duel.** Repeater against
autocannon at 24 m, both stationary and trading: the repeater build's Core Module
goes in 89 ticks. That is the trade working as designed, but nobody has checked
whether the trade is *fun*, and the only build in the game that fights with it is
the one every opponent also carries.

The summary: **the first fight is now a fight.** You are not decided by your own
gun and you are not decided by being rammed. What decides it next is that you
cannot see it past the controls card, and that whatever you kill leaves the map.

---

## 3. The work queue

Ordered by what is worth doing next, not by dependency. Anything not listed here
is either done or is in section 4.

### 3.1 Keep the wreck where it fell — the top item

Doc 11 §16.2 decides that a destroyed Assembly's hulk stays put, and the capture
shows it climbing past 27 m/s under the end card — free fall, from wherever the
last thing to touch it kicked it.

The mechanism is understood and the fix is a decision rather than an
investigation: losing the Core Module orphans every part, the islands detach, and
doc 05 §3.5's mass floor leaves the chassis at **one kilogramme**. Anything that
touches a 1 kg body with a hull-sized collider sends it over the horizon.
`tests/physics/test_wreck_settles.gd` already prints `1.000 kg` and passes,
because nothing in its fixture ever touches the wreck.

Two candidate readings, and doc 04 owns the choice: a terminated Assembly's parts
should not detach at all — the hulk is one dead object — or the floor should be
the surviving parts' mass rather than a constant. The first is closer to what
§16.2 describes and is the cheaper of the two.

### 3.2 Get the controls card out of the fight

Second on the player review and cheap. `ControlCard.DWELL_S` is 11 s and the
opening engagement is decided inside that window, so a first-time player watches
their first fight through an opaque legend sitting in the middle of the screen —
across exactly the band the three opponents approach through.

Doc 11 §14.6 raises it on every entry because there is nowhere to store "they
have seen it", and that half is `SyndicateSettings` work waiting on there being
more than one match. **The placement and the dwell are separable from it and are
not waiting on anything**: a card in a corner, or one that stands down on the
first throttle input rather than on a timer, costs nothing and does not need a
settings key. §14.6 owns the constants and would need amending in the same
change.

Verify by capture rather than by test — this is a question about what is legible,
and `LEARNED_FACTS.md` §1 fact 55 is the route.

### 3.3 Decide whether friendly fire exists

§15.7.5's ladder fixed the *geometry* — three drivers converging on one target no
longer stand in each other's line — and deliberately did not touch the rule.
Nothing in `src/combat/` knows what a team is: `DamagePacket` names a source
Assembly and `DamageResolver` never asks whose side it is on, so a round that
reaches a friend does full damage.

That is doc 08's question and it is a real one, not an oversight. The roster
already exists on `AiContext` and the match layer owns it; what does not exist is
a decision about whether the resolver should be told.

### 3.4 Sweep the bounds nobody reaches

Invariant I-12 lists eighteen bounds and the suite demonstrably reaches almost
none of them. Deleting each in turn and watching for green is a cheap way to find
out which are load-bearing — and it is now genuinely cheap, at a couple of
minutes a sweep. The fixture that closes one has to be built to *exceed* it and
then to assert that it exceeds it. Likeliest to be untested: chain-reaction depth
3, collapse cascades, melee sweep segments, and the two debris caps.

### 3.5 Fight with the edge

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

### 3.6 A stability-augmentation layer, and the rotary family

`CombatArena._fly` is three loops through `ControlInput` and is still the only
thing in the repository that can hold a hover. A **player** flying a rotary build
needs the same loops, so it is not a tactic and does not go in `AiDriver`. It
wants a layer between both `ControlInput` producers and the motion layer, which
doc 05 does not have. An `AiDriver` handed a rotary Assembly aims and fires but
does not fly.

### 3.7 §15.5's sustained contact, and `DotScheduler`

Two small, self-contained pieces of doc 07 and doc 08. `eff.melee.beam_edge.t4`
authors sustained contact, `MeleeSolver.sustained_channel_damage` is written and
unit-tested, and nothing calls it — one line clears the target set per swing
instead of per tick. `DotScheduler` (doc 08 §7.3) is about sixty lines and is the
difference between thermal damage that resolves correctly when submitted and
thermal damage that actually burns.

### 3.8 The rest of document 10

Comparable in size to what document 09 cost, in dependency order: the CSG bake
(doc 10 §3.1–§3.2), fragment decomposition (§3.3), support graph and collapse
(§3.5, §5), runtime slicing (§6), fragment bodies (§7), and the `StructureArchetype`
generator. `ManifoldChecker` — the blocking gate that makes DCC authoring
survivable — is built and tested. Worth knowing before starting: a Voronoi cell
is an intersection of half-spaces, so for a *convex* Section this is repeated
plane slicing and needs no CSG at all.

### 3.9 Smaller, and worth doing when passing

- **A parked Assembly never comes to rest.** Session 31, found while building the
  ram fixture and deliberately not fixed in it. A wheeled build with no throttle
  and no brake reads 0.38 m/s at the end of a 90-tick settle and **still
  0.38 m/s after 360** — the drift does not decay, because nothing in doc 05 §7
  puts a rolling resistance on a free contact. `TractionSolver` has a rolling
  resistance term and it is charged against a *driven* contact; what a coasting
  one gets is nothing. Two to three metres of wander over an engagement, and a
  player who lets go of the keys on level ground drifts. Whoever takes it should
  know it cost an assertion first: "a stationary 1107 kg hull ended three metres
  from its spawn" reads as unarguable proof of a ram and was the fixture's own
  baseline.
- **Doc 05 §15.7.5's ladder step is under one hull length.** §15.7.5 justifies
  4.5 m as "a little over an Assembly's own length"; the reference build measures
  4.8 m from nose to tail, so a friend one rung out is still partly in the line.
  The document is amended to say so and the constant is knowingly left alone —
  it is `balance-review` and it moves every engagement measurement in
  `tests/physics/` at once. `CombatArena.Combatant.hull_half_length_m` is the
  measurement, if a decision wants remaking against it.
- **A second steered wheeled row.** Makes one of the three surviving uncaught
  faults visible, gives rule 13 a second tier, and gives the garage a real choice
  on the front axle.
- **A second tier of the rotor family.** The cheapest way to make rule 13
  non-vacuous. `mot.rotor.main_single.t3` is worth authoring for its failure mode
  alone: `torque_reaction_ratio = 1.0` and no yaw authority, so a build carrying
  one alone spins under its own reaction torque and cannot stop.
- **Rescale §10.5's four legacy direct-fire rows, or decide not to.** 1450 N·s
  for a 30 mm round is about 3.6× real momentum, and `eff.ballistic.repeater_12.t2`
  is authored at a realistic 26 for a 12 mm one, so the table is currently on two
  bases. `balance-review`, and it moves every engagement measurement in
  `tests/physics/` at once — which is why it was not bundled with the row that
  needed to exist.
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
  exist in a test.** Owned by §3.6.
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
- **A tracked patch is drawn at the mean of its road stations, and nothing
  asserts the mean.** Doc 05 §16.1. Every station on a flat slab reports the same
  distance, so the mean and the first station are one number and the fault sweep
  says so: `tracked-mean-is-its-first-station` is a knowing survivor. It closes
  with a bogie straddling a slope, which no fixture has.
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
- **`eff.ballistic.autocannon_30.t3` still cannot be fired from a moving hull,
  and that is now a property of one row rather than of the game.** Measured at
  99.1° of heading drift and two rounds of a possible seventeen over two and a
  half seconds; `eff.ballistic.repeater_12.t2` on the identical chassis and mount
  reads 2.9° and thirty. Both ship, the starter carries the light one, and doc 01
  §10.5 records the trade. What is *not* settled is the recoil scale §10.5's four
  legacy direct-fire rows are on — 1450 N·s for a 30 mm round is about 3.6× real,
  the repeater is authored at a realistic 26, and rescaling the legacy rows onto
  one basis is a `balance-review` change that moves every engagement in
  `tests/physics/` at once.
- **Attitude is measured now, in roll only.**
  `CombatArena.Combatant.worst_roll_deg` and `worst_nose_down_deg` are sampled
  per tick for every combatant, and `tests/physics/test_ram_attitude.gd` asserts
  them. What is still unmeasured is **yaw rate** — a hull spinning on the spot is
  upright in both of the recorded axes — and nothing samples attitude on a
  *wreck* after termination, which is what §3.1 would want.
- **Only direct fire is implemented.** Doc 07 §5.3's arced solve, §5.4's guided
  ordnance, §10's AI target acquisition and §11's prediction are not written. A
  module of a kind that needs one aims correctly and declines to fire, which is
  the failure mode to prefer.
- **No engagement has ever been fought at contact range.** Owned by §3.5.
- **A second projectile type exists and only one join is asserted.** Until this
  session every module in the catalogue chambered `proj.kinetic.ap_30`, so "which
  round does this module fire", "which stores is this Assembly granted" and
  "which store does the HUD count" were one answer by accident. A fault sweep
  planted two of the three ways to get that wrong and **neither was caught**;
  `test_screen_flow.gd` now asserts it for the player's own module. The
  equivalent for an AI opponent, and for a build carrying two modules that
  chamber different rounds, is still unasserted.
- **§15.5's sustained contact is not implemented.** The edge authors it, the
  solver computes it, and nothing calls it. Owned by §3.7.
- **A melee strike can never ricochet**, because its packet's normal is derived
  from its own direction. Not a defect — the query reports no surface normal —
  but see §5 before assuming doc 08 §4's angle gate means anything here.
- **`DotScheduler` is not written** (doc 08 §7.3), so thermal and corrosive
  packets resolve correctly when submitted and nothing submits them over time.
  Owned by §3.7.
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
  converging on one target and deliberately not the rule. Owned by §3.3.
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
  names the count, which is the half a player acts on. This got cheaper rather
  than done: `GaragePreview.highlight_slot` now exists for the hover wash, and
  what the dialog needs is that wash in `danger` over a *set* of slots rather
  than one. A `highlight_slots(PackedByteArray, Color)` and a call from
  `_remove_at` is the whole of it.
- **Doc 02 §10's mirror ghost previews against the build as it stands**, not as
  it will be once the primary commits — so a mirrored placement whose legality
  depends on its own other half shows red and commits green. Validating against a
  hypothetical commit would mean running the whole chain twice per pointer move
  to answer a question the click answers a frame later; the honest fix is a
  `BuildContext` that can speculate, and nothing else wants one yet.
- **Removal is not mirrored, deliberately.** Doc 02 §10.2 records the reasoning:
  §9.2's cascade already takes parts the player did not point at, and crossing
  the build to take one more would be two surprises in one click.
- **The toolbar is six controls wide at the expanded tier** and the compact tier
  has nowhere to put them. MIRROR, UNDO and REDO each carry their binding in the
  caption, which is what makes them discoverable and what makes them wide.
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
- **The orbit camera at the conclusion ends up inside the wreck.** Doc 11 §16.2
  hands the player an orbit camera over the hulk, and the capture shows the end
  card fading in over a close-up of hull plating that makes it barely legible.
  `LEARNED_FACTS.md` §1 fact 56 is the mechanism — `cast_motion` answers `[0, 0]`
  for a shape that starts already overlapping, and the camera clamps to a minimum
  distance rather than doing something better with that answer. What §16.2 never
  settled is where the camera stands when the thing it is orbiting is directly
  under it.
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
- **The suite is about 210 seconds and `test_screen_flow` is most of it**, at
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
