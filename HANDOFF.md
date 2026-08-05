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

These three files were one `HANDOFF.md` until session 24, and comments in `src/`,
`tests/` and `tools/` still cite its sections. **The mapping lives in
`LEARNED_FACTS.md` §0 and only there** — it was copied into all three files and
three copies of a lookup table is three things to keep true.

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

**And it looks like a vehicle now.** The Crossout-scale rebuild landed: the
reference build is **3630 kg at 132 kg/m³ on a 3.00 m wheelbase, standing on all
four of its contacts at a 48/52 split**, where it used to be 1107 kg at 46 kg/m³
— a fifth of balsa — on a 1.50 m wheelbase standing on two. The Effector Module
is a third of the hull's length rather than half of it, and it sits on the roof
instead of hanging a metre past the front axle.

**What it lacks now is depth rather than shape** — one arena, one opponent
recipe, and nothing yet that rewards a good build over a heavy one — **and the
ground physics under it is less sound than a green suite suggests, and is now the
cap on four other things.** Doc 05 §7.4's contact integration is 142 times
outside its own stability limit; it holds down the drive torque, the service
brake, §7.6's traction control and the machine's ability to stand still. §2 and
§3.1 have it.

**91 files, 6844 checks, 0 failures.**

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

**91 files, 6844 checks, 0 failures.**

`run_all_checks.sh` fails on any engine error printed during the suite, not only
on recorded assertion failures (`LEARNED_FACTS.md` §1 fact 34). That is why
nothing in `src/` may `push_error` on a state a test deliberately exercises — a
blueprint naming an unknown part warns instead.

**A full run is about 215 seconds** — 14 s of reimport and the rest suite. Three
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

**It looks like a vehicle.** This session's, and it is the whole point of the
rebuild. The frame at one second is a four-wheeled machine with a cabin and a
small module on its roof, on a wheelbase that reaches the ends of its hull —
where the same frame used to be a gun with a car attached, at a fifth of balsa's
density, standing on two of its four wheels. Nothing in the repository could see
that and one frame answers it (`LEARNED_FACTS.md` §1 fact 75).

**You can see the fight now.** Session 33's, and the capture holds: the controls
card is in the upper left, the centre of the screen is clear, and all three
opponents are visible on approach at five seconds.

**And a destroyed part is gone, legibly.** At seven seconds the readout is
`PARTS 11/12`, the tail of the hull is visibly missing, and `POWER` drops from
`26 / 410` to `26 / 150` because what left was the Energy Cell. A player can read
what they lost off the panel without being told.

Ranked by what would most improve a first-time player's experience:

1. **The machine never sits still, and it is worse than it was.** The capture's
   own speed readout reads **2.4 m/s with nobody touching a key**, against 0.8
   before the rebuild — the chatter scales with the load. §3.1 has the cause, the
   repair, and the three other things it is holding down.
2. **A first-time player is destroyed in nine seconds.** 100% at three, 90% at
   five, 46% at seven, Core Module gone before ten. The previous capture on the
   identical route had the player **alive at ten seconds at 64%**. The Assembly
   carries 2.9 times the Core Module integrity it used to and dies sooner, which
   most likely means a bigger machine is simply a bigger target — but nothing has
   measured that, and *the opening engagement is now less survivable than the one
   session 31 was written to fix*. Measure it before tuning anything.
3. **You cannot ask the machine to slow down, and the brake is being cancelled
   underneath.** `S` is one key meaning both "brake" and "reverse", the handbrake
   is bound to Space and read by nothing — and §7.4's limit cycle reverses the
   brake torque's sign on most ticks, so even the AI's planned stop arrives at
   hull contact. **§3.3**, and its second half is §3.1's.
4. **The end card is drawn over nothing.** At nine seconds the shot is good: the
   wreck in the middle of the frame with three opponents standing over it. A
   second later the orbit camera has swung to an empty blue field and the card is
   floating on it. §4 has the mechanism; what is missing is a decision about
   where the camera stands.
5. **One arena and one opponent recipe.** Every test drive is the same three
   builds at the same three spawns on the same basin. Doc 06's generator is the
   intended answer.
6. **Nothing rewards a good build over a heavy one** — except which Effector
   Module you fit, and that trade got *smaller* this session: the autocannon can
   now be fired from a moving hull, which is one fewer axis of decision rather
   than one more. §4 records the measurement.
7. **The garage teaches nothing about *composition* until a placement is
   refused.** The inspector names figures; nothing says a rotor disc needs a mast
   under it and a second disc opposite it, or that supply goes on before draw.
8. **The opponents still shoot each other**, and nothing in `src/combat/` knows
   what a team is (§3.4).
9. **A walking build turns 51° on the spot while standing still** (§3.1.2), and
   the garage will let a player fit limbs.

**The bad news, plainly.** Three things.

**The ground physics is wrong, it has always been wrong, and it is now the cap on
four other things.** Doc 05 §7.4 integrates the contact's spin explicitly against
a friction reaction of about 2.9e5 N per rad/s — stable below 117 microseconds
against a 16.7 ms tick. It does not diverge, because the Pacejka curve saturates;
it limit-cycles, measured on the rebuilt build at 8 reversals in 12 ticks peaking
at 5.9 rad/s against a free-rolling 1.2. **No aggregate any fixture recorded
moved**, which is how it survived thirty-two sessions of a green suite. What
session 36 added is the bill: it holds `drive_torque_nm` down to a third of what
the contacts could take, it leaves doc 05 §7.6's traction control with no
reachable fixture on the shipped part set, it cancels the service brake by
reversing its sign every other tick, and it is why a parked machine drifts at
2.4 m/s. §3.1.

**The opening engagement got harder and nobody decided that it should.** The
player is destroyed at nine seconds on the same route that used to leave it alive
at ten with 64% integrity, and it is carrying nearly three times the Core Module
integrity it was. That is a balance consequence of a geometry change, which is
exactly the kind of thing that ships without anybody noticing, and it is item 2
above. **Measure why before tuning anything** — a bigger target is the obvious
explanation and it is not the measured one.

**And the rebuild cost the walking family its one good state.** A standing
ambulatory Assembly used to hold a heading to a fraction of a degree
indefinitely; it now turns 51° in five seconds. Half of that was a layout error
worth one cell and is fixed; the rest is doc 05 §13's missing heading authority,
which §4.21 has always named. §3.1.2.

The summary: **the machine looks right now, and the physics under it is the same
physics it always was — which is the thing standing between this and being good
to play.** One defect, diagnosed twice, is holding down the drive, the brake, the
aids and the stillness of a parked hull.

## 3. The work queue

Ordered by what is worth doing next, not by dependency. Anything not listed here
is either done or is in section 4.

### 3.1 Close §7.4's contact integration — it is now the cap on four other things

**Read doc 05 §7.4's open-defect block before acting. The diagnosis, the
arithmetic, the working scheme, and the measured cost of landing it are in it,
and re-deriving them costs a session — it has now cost two.**

The short version. The contact's angular rate is integrated explicitly against a
friction reaction of about 2.9e5 N per rad/s, which is stable below 117 µs
against a 16.7 ms tick — a factor of 142. It saturates rather than diverging, so
it presents as a limit cycle: measured on the rebuilt build at 8 reversals in 12
ticks, peaking at 5.9 rad/s against a free-rolling 1.2.
`tests/physics/test_rest_stability.gd` measures it and is **asserted as it
fails**, so closing this turns that file red and the fix there is to re-measure
and re-assert, never to loosen.

**Session 32 built the repair twice and reverted it twice.** The scheme that
works is in §7.4: step the **slip velocity** rather than the rate, take it
implicitly, reconstruct `ω = (v_long + u) / r` afterwards, and cap any friction
force that would reverse the slip it opposes. Both traps are paid for and written
down in §7.4 and in `LEARNED_FACTS.md` facts 73 and 74 — damping `ω` rather than
the slip is worse than the defect, and the implicit factor must use the chord
rather than the tangent at zero.

**What changed in session 36 is that §7.4 stopped being one item and became the
cap on four.** The rebuild put all four contacts on the ground, which was the
thing blocking the repair; what it revealed is how much else this defect is
holding down:

- **`drive_torque_nm` is capped at 6400 N·m by the instability, not by grip.** At
  10 200 the chatter is energised by the drive and pumps the suspension until the
  Assembly leaves the ground under sustained full throttle — measured, and it is
  what made the AI look like it was refusing to fight. The contacts would hold
  1.05 g; the authored figure is 0.36.
- **Doc 05 §7.6's traction control has no reachable fixture**, because at 6400
  N·m the Prime Mover no longer out-torques the contacts. `test_ground_assembly`
  supplies its own over-torqued mover through the Assembly's `PowerSystem` and
  says so; that is a fixture standing in for a shipped build that cannot exist
  yet.
- **The service brake is being defeated by it.** §7.2's brake torque opposes the
  contact's spin through `-signf(contact_omega)`, and that sign reverses on most
  ticks. `tests/physics/test_ram_attitude.gd` measures the consequence: a driver
  plans a 6 m/s² stop and arrives at hull contact anyway.
- **A parked Assembly drifts at 2.4 m/s in the shipped match**, which is three
  times what it was, because the chatter scales with the load.

Closing it should let the drive torque go back up, give §7.6 a shipped fixture,
make the brake work, and stop the machine shivering. **It is the highest-value
item in the project and it is no longer blocked by anything.**

#### 3.1.1 What the rebuild left behind

The Crossout-scale rebuild is **landed and green**. The reference build:

| | before | after |
|---|---|---|
| Mass | 1107 kg | **3630 kg** |
| Density | 46 kg/m³ | **132 kg/m³** (a passenger car is 115) |
| Wheelbase | 1.50 m — 35% of hull | **3.00 m — 75%** |
| Contacts loaded | **2 of 4** | **4 of 4** |
| Static split | **100% front** | **48% front** |

Three consequences are still open and none of them is large:

- **The rollover threshold is 0.97 g**, a laden truck rather than a car, because
  the Prime Mover and the Effector Module share a deck four cells above the
  belly. `test_the_starter_is_stable_and_a_tall_build_is_not` asserts it above
  0.90 and says why. A player meets it in a hard turn.
- **Doc 01 §10's unshipped rows are on the old scale.** Fourteen parts were
  rescaled; every other row in that document was not, and authoring one means
  rescaling it rather than transcribing it. §10's opening now says so.
- **The ambulatory family got worse and the rotary family had to be re-laid.**
  §3.1.2.

#### 3.1.2 The walking family regressed, and it is a heading problem

**A standing ambulatory Assembly no longer holds a heading.** It used to hold to
a fraction of a degree indefinitely — that was `test_ambulatory_drift`'s control,
the half that worked — and on the 5148 kg chassis it turns about fifty degrees in
five seconds with nothing asking it to. The file asserts it as it behaves, as a
magnitude and never as a sign, and says what has to happen for the check to go
red again.

Two things are known about it and both are worth having before starting:

- **A cell of layout was most of it.** The limbs hung one cell forward of the
  stations they mate to, so the four feet came down about a mean of `z` 23 under
  a hull centred at 24. Squaring them onto their stations took the standing drift
  from 152° to 51°. **What is left is not a layout error** — the stance is
  symmetric in both axes now — and it is doc 05 §13's, which §4.21 has always
  said.
- **It is the same inertia collapse as everything else.** `LEARNED_FACTS.md`
  fact 78: the Core Module's tensor grew 24× against a mass factor of 4.7, so
  every yaw authority in the project fell by about six. The gait's disturbance
  did not fall with it.

The rotary family needed a re-lay and now works: the Prime Mover goes **under the
belly** and the Energy Cell on the aft deck, which is the reverse of every other
recipe. In the tail the 620 kg mover put the centre of mass 0.31 m behind the
disc line, which asks for 23° of a 14° swashplate cone, and the Assembly went
over during the settle. `CombatArena.ROTARY_POWER` carries the arithmetic.

### 3.2 Give the control card a first-run flag

The placement and the dwell are **done** (session 32): the card sits in the upper
left, out of the band the opponents approach through, and stands down on the
player's first throttle, steer, or fire rather than on an eleven-second clock.
Doc 11 §14.6 owns both and records why the centred version was wrong.

What is left is the half that was always waiting on something else: the card is
raised unconditionally on every entry to a match, because there is nowhere to
store "they have seen it". That is `SyndicateSettings` work and it wants there to
be more than one match first. It costs a returning player a corner panel that
leaves on their first input, which is cheap enough that this is now a small item
rather than a player-review one.

### 3.3 A player cannot brake — the mechanism exists and no input reaches it

**Read the first line before acting on this one: the brakes are not missing.**
The chain is complete and correct for the wheeled and tracked families, and
session 31's arrival brake is proof it works — it is the only thing that stopped
a driver arriving at 18 m/s. `veh_brake` → `ControlInput.brake` →
`brake_torque_nm × demand` in `MotiveSystem._apply_traction` → opposed to the
contact's spin in `TractionSolver.integrate_contact` → the contact slips and
doc 05 §7.2's longitudinal force retards the hull. There is even a zero-crossing
guard whose docstring names the symptom it prevents: "a vehicle that will not
quite come to rest."

**What is missing is any way for a person to ask for it.** Three things, and the
third is the one that is simply absent rather than conflated.

1. **`S` is one key meaning two opposite things.** `ControlSystem.sample` builds
   `drive := axis(ACTION_BRAKE, ACTION_THROTTLE)` and writes it to
   `input.throttle`, *and separately* writes
   `input.brake = get_action_strength(ACTION_BRAKE)`. So one press of `S`
   demands full braking and full **reverse drive torque** in the same tick. A
   player who wants to shed thirty metres a second and hold position has no
   input that says so; they have one that says "stop, then go backwards".
2. **A stop is a moment, not a state — and it is worse than that.**
   `brake_sign := -signf(contact_omega)`, and `signf(0.0)` is `0.0`, so at
   exactly rest the brake torque vanishes and the reverse drive torque from the
   same key is all that is left. Whether *that* matters is a design question
   about a combined brake/reverse axis, which is a real convention and not
   obviously wrong.

   **What is not a design question is that the sign reverses on most ticks.**
   §7.4's limit cycle flips `contact_omega` eight times in twelve, so the brake
   torque flips with it and the Assembly decelerates at a fraction of what it is
   being asked for. Measured through the AI, which is the only thing in the
   project that plans a stop: `AiDriver` plans 6 m/s² from a 14 m stand-off, and
   `tests/physics/test_ram_attitude.gd` records it arriving at hull contact
   anyway. **So the brake is not merely unreachable from the keyboard; it is
   being cancelled underneath.** That half is §3.1's.
3. **`veh_handbrake` is bound to Space, sampled into `ControlInput.handbrake`,
   and read by nothing** — the natural answer to (2), already listed in §4 and
   still unwritten. Doc 05 does not define what a handbrake does to a contact,
   which is the actual blocker.

**And there is no braking at all for two of the four families.** `input.brake` is
read in exactly one place, `_apply_traction`, which only `GROUND` and `TRACKED`
reach. An ambulatory build and a rotary one have no deceleration control of any
kind — not conflated, not weak: absent. The rotary case is partly §3.7's, since
nothing flies one anyway; the ambulatory case is not, because a player can build
and drive one today.

The cheapest honest first step is a decision rather than code: doc 05 §15.1 owns
the input→`ControlInput` mapping and §7 owns what a contact does with it, and
neither says whether "decelerate" is a demand distinct from "reverse". Nothing
here should be invented in `ControlSystem` without that section saying so.

### 3.4 Decide whether friendly fire exists

§15.7.5's ladder fixed the *geometry* — three drivers converging on one target no
longer stand in each other's line — and deliberately did not touch the rule.
Nothing in `src/combat/` knows what a team is: `DamagePacket` names a source
Assembly and `DamageResolver` never asks whose side it is on, so a round that
reaches a friend does full damage.

That is doc 08's question and it is a real one, not an oversight. The roster
already exists on `AiContext` and the match layer owns it; what does not exist is
a decision about whether the resolver should be told.

### 3.5 Sweep the bounds nobody reaches

Invariant I-12 lists eighteen bounds and the suite demonstrably reaches almost
none of them. Deleting each in turn and watching for green is a cheap way to find
out which are load-bearing — and it is now genuinely cheap, at a couple of
minutes a sweep. The fixture that closes one has to be built to *exceed* it and
then to assert that it exceeds it. Likeliest to be untested: chain-reaction depth
3, collapse cascades, melee sweep segments, and the two debris caps.

### 3.6 Fight with the edge

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

### 3.6.1 Design note — an ambulatory faction that eats wreckage

Recorded rather than queued, because it is a direction and not a task.

The idea: make walking Assemblies a **separate faction** with their own build
rules — Crossout's Ravagers as the reference — rather than one more locomotion
family a player bolts onto the same hull. And let them **absorb nearby wreckage**,
taking a fallen part onto their own chassis as armour or as a weapon.

Three things in the repository already point that way, which is why it is worth
writing down now rather than later:

- **The parts are already there to absorb.** Doc 04 §6 turns a severed island
  into a `DebrisBodyRef` that keeps its authored `ColliderProfile` primitives and
  its `PartInstanceState` — integrity, band, tint and all. An absorbed part would
  be a `PlacementValidator` commit against the absorber's `BuildContext` from a
  record that already exists, not a new kind of object.
- **Absorption is a structural event, which is the shape Invariant I-4 wants.**
  It is an attach, a mass recompute, and a graph edge — the same path the garage
  uses. Nothing needs to poll.
- **The ambulatory family's open defect is a faction-shaped problem.** §4.21's
  yaw drift and §4.16's one-number steering are both "a walker is not a car with
  legs", and a faction that never shares a chassis with a wheeled build is free to
  answer them in doc 05 §13 without regard for §7.6.

What it would need before it is a task: a decision in doc 06 about whether an
archetype can be faction-locked, a rule in doc 02 for where an absorbed part is
allowed to land (the lattice is integer and the wreck is not aligned to it), and
a cap — Invariant I-12 has a bound for everything else that can be triggered
repeatedly, and "parts absorbed per match" would need one.

### 3.7 A stability-augmentation layer, and the rotary family

`CombatArena._fly` is three loops through `ControlInput` and is still the only
thing in the repository that can hold a hover. A **player** flying a rotary build
needs the same loops, so it is not a tactic and does not go in `AiDriver`. It
wants a layer between both `ControlInput` producers and the motion layer, which
doc 05 does not have. An `AiDriver` handed a rotary Assembly aims and fires but
does not fly.

### 3.8 §15.5's sustained contact, and `DotScheduler`

Two small, self-contained pieces of doc 07 and doc 08. `eff.melee.beam_edge.t4`
authors sustained contact, `MeleeSolver.sustained_channel_damage` is written and
unit-tested, and nothing calls it — one line clears the target set per swing
instead of per tick. `DotScheduler` (doc 08 §7.3) is about sixty lines and is the
difference between thermal damage that resolves correctly when submitted and
thermal damage that actually burns.

### 3.9 The rest of document 10

Comparable in size to what document 09 cost, in dependency order: the CSG bake
(doc 10 §3.1–§3.2), fragment decomposition (§3.3), support graph and collapse
(§3.5, §5), runtime slicing (§6), fragment bodies (§7), and the `StructureArchetype`
generator. `ManifoldChecker` — the blocking gate that makes DCC authoring
survivable — is built and tested. Worth knowing before starting: a Voronoi cell
is an intersection of half-spaces, so for a *convex* Section this is repeated
plane slicing and needs no CSG at all.

### 3.10 Smaller, and worth doing when passing

- **A destroyed part still leaves no visible trace.** `release_part` now takes
  its collider and its mesh out of the simulation the moment it dies (session
  32), which is right and is only half of doc 08 §9: what a player sees is a part
  blinking out rather than a hull that looks damaged. `VisualDamageController` is
  the other half and is unwritten.
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
  exist in a test.** Owned by §3.7.
- **The ambulatory gait drifts in yaw and no steering demand can null it.**
  §4.21, measured at 170° over five seconds, and now the family's limiting
  defect. It wants a heading term in doc 05 §13, which §13.8 currently forbids
  by omission.
- **An ambulatory Assembly still cannot be asked to turn and travel
  independently** (§4.16). Less painful than it was — the one steering number
  now turns the right way — but still one number doing two jobs.
- **`handbrake` and `boost` have producers and no consumers**, and
  `ControlInput.brake` reaches only `_apply_traction`, so two of the four
  families have no deceleration control at all. §3.3 has the whole of this,
  including why inventing a handbrake here would be worse than the gap.
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
  That is what a burnout does, and it is why traction control exists. How much of
  the measured wander is this and how much is §3.1's limit cycle is not known.
- **`drive_torque_nm` is a third of what the contacts could hold**, and the cap
  is doc 05 §7.4's instability rather than grip: at 10 200 N·m sustained full
  throttle pumps the suspension until the Assembly leaves the ground. §3.1.
- **Doc 05 §7.6's traction control has no reachable fixture on the shipped part
  set**, for the same reason. `test_ground_assembly` supplies its own
  over-torqued Prime Mover through the Assembly's `PowerSystem` and asserts that
  it crossed the bound before asserting anything about the aid.
- **Every yaw and roll authority in the project fell by about six** when the
  reference build was rescaled, because an inertia grows as the square of the
  extents and a mass does not (`LEARNED_FACTS.md` fact 78). §7.6's corrective
  brake now takes 2% off an imposed spin where it took 60%, and the steering is
  slower to match. It is asserted as a strict reduction, and the authority itself
  is a doc 05 §7.6 balance question nobody has taken.

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
- **`eff.ballistic.autocannon_30.t3` can now be fired from a moving hull, and
  that is a shrunken trade rather than a fixed defect.** It was 99.1° of heading
  drift and two rounds of a possible seventeen; on the rebuilt chassis the same
  module at the same mount under the same throttle reads under ten degrees and
  fifteen rounds. Nothing about the module changed — 1450 N·s met three times the
  yaw inertia through a shorter lever. `eff.ballistic.repeater_12.t2` is still
  three times better and doc 01 §10.5's trade survives as a multiple, but one of
  the two axes a player chooses between just got flatter. What is *not* settled
  is the recoil scale §10.5's four legacy direct-fire rows are on — 1450 N·s for
  a 30 mm round is about 3.6× real, the repeater is authored at a realistic 26,
  and rescaling the legacy rows onto one basis is a `balance-review` change that
  moves every engagement in `tests/physics/` at once.
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
- **No engagement has ever been fought at contact range.** Owned by §3.6.
- **A second projectile type exists and only one join is asserted.** Until this
  session every module in the catalogue chambered `proj.kinetic.ap_30`, so "which
  round does this module fire", "which stores is this Assembly granted" and
  "which store does the HUD count" were one answer by accident. A fault sweep
  planted two of the three ways to get that wrong and **neither was caught**;
  `test_screen_flow.gd` now asserts it for the player's own module. The
  equivalent for an AI opponent, and for a build carrying two modules that
  chamber different rounds, is still unasserted.
- **§15.5's sustained contact is not implemented.** The edge authors it, the
  solver computes it, and nothing calls it. Owned by §3.8.
- **A melee strike can never ricochet**, because its packet's normal is derived
  from its own direction. Not a defect — the query reports no surface normal —
  but see §5 before assuming doc 08 §4's angle gate means anything here.
- **`DotScheduler` is not written** (doc 08 §7.3), so thermal and corrosive
  packets resolve correctly when submitted and nothing submits them over time.
  Owned by §3.8.
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
  converging on one target and deliberately not the rule. Owned by §3.4.
- **A destroyed Assembly is never removed and never respawns.** Doc 11 §16.2
  decides that the wreck stays, which is right, and doc 05 §3.7 now makes it
  actually stay rather than being punted over the horizon. What follows it is
  §15's loop — fight again, or go back to the garage — and what is still missing
  is a `SpawnDirector`, so a match is over the moment the player's Core Module
  goes rather than putting them back in.
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
  91 s for the two `MatchScreen`s it opens. §1 has the breakdown and the honest
  levers; the ambulatory mirror is no longer one of them, because it reaches a
  decision now.
- **§12.3's self-immunity window is inert in both directions.** Setting it to
  zero and pinning it permanently on both leave the suite green, because no
  shipped recipe mounts a module whose muzzle overhangs its own hull. It is
  carried, not tested.
- **Four files assert a defect as it stands, and every one of them says so at the
  constant.** `tests/physics/test_rest_stability.gd` asserts §7.4's limit cycle;
  `tests/physics/test_ambulatory_drift.gd` asserts the walking family's yaw drift
  *and*, since session 36, the standing one; `tests/physics/test_ram_attitude.gd`
  asserts that a driver arrives at bare contact rather than with clear air; and
  `test_team_engagement`'s five-a-side asserts that it runs to the timeout. Each
  goes red when the thing it records is repaired, and the fix in every case is to
  re-measure and re-assert, never to loosen.

  Two came back the other way this session and are worth knowing as precedent.
  `test_build_proportions` was written with two of its three assertions asserted
  as failures and the rebuild closed both, so it now asserts the correct state and
  keeps only the two proportions that are still off. `test_drive_and_shoot`'s two
  defect assertions **inverted** — the autocannon build holds its heading now —
  and were re-framed rather than re-numbered, which the rebuild plan had predicted
  would be needed.

  Where a tick count was the thing asserted, it was **deleted** rather than moved:
  a tick count in a multi-Assembly file measures the suite and not the fight
  (`LEARNED_FACTS.md` §1 fact 54), and re-asserting a new one hands the same trap
  to whoever adds the next file.

---
