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
way a player expects it to, and — as of this session — the machine underneath it
obeys the controls.** `godot --path .` opens on a menu. The menu opens a garage,
where a wheeled Assembly stands on the Build Lattice with a catalogue of fifteen
parts beside it and its mass, power, mounts, top speed, integrity and rollover
threshold on the right. **M** mirrors placements, **Ctrl+Z** takes back a
misclick, a removal that would orphan something asks first. TEST DRIVE puts that
build into a basin with 15 m of relief against **one opponent built from the
player's own blueprint**, sixty metres away, carrying the same six hundred
rounds. They fight. A card says which way it went.

**Doc 05 §7.4 is closed, and it was the cap on everything below it.** The
contact's angular state is stepped through the *slip velocity* with a chord
implicit factor and an under-relaxed stick cap, and rolling resistance is finally
in the balance. On the reference build, one Assembly on a slab:

| | before | after |
|---|---|---|
| Contact rate reversals in 12 ticks standing still | 7 of 11 | **0** |
| Peak contact rate standing still | 5.9 rad/s | **under 0.001** |
| Speed six seconds after the settle, no input | 0.196 m/s | **0.000** |
| Distance wandered over the same window | 1.307 m | **0.000** |
| Stopping distance from 6.3 m/s under full brake | never stopped | **4.31 m** |

**And with it, four things a player asks for in the first thirty seconds.** A
service brake that works (§7.4's limit cycle had been reversing its sign on eight
ticks in twelve). A **parking brake** — §7.7, engaged on a record demanding
neither drive nor brake, and `veh_handbrake` finally has the consumer it has been
waiting for since it was bound. **Reverse**, on §15.5's released brake demand.
And deceleration for the two families that had none at all: §13.9 stops a walking
Assembly by freezing its gait with every foot planted, §12.8 arrests a rotary one
by tilting the disc against its own velocity.

**The opponent is a mirror of what you built, it stops, and only then does it
shoot.** §15.7.4's fire gate was "inside its stand-off"; it is now "inside its
stand-off **and stopped**", which could not be written while the brake did not
work. `MatchScreen` spawns the player's own blueprint at sixty metres instead of
the shipped starter at thirty-four.

**Three pre-existing defects fell out of making the forces real**, and that is the
session's most useful lesson (`LEARNED_FACTS.md` fact 84): a repair that makes a
force real finds every place that force was being applied wrongly. The contact
frame was never projected into the contact plane, so a nose-down hull's
"longitudinal" friction pitched it further — a tracked build somersaulted the
first time its brake worked. A tracked bogie credited each of its four road
stations with the whole part's inertia. And §7.6's yaw loop was locking the flank
it was biasing.

**What it lacks now is depth rather than shape** — one arena, one opponent recipe
beyond the mirror, and nothing yet that rewards a good build over a heavy one —
**and the constraint that has replaced §7.4 is the hull's own stability.** §3.1.1.

**92 files, 6975 checks, 0 failures.**

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

**92 files, 6975 checks, 0 failures.**

`run_all_checks.sh` fails on any engine error printed during the suite, not only
on recorded assertion failures (`LEARNED_FACTS.md` §1 fact 34). That is why
nothing in `src/` may `push_error` on a state a test deliberately exercises — a
blueprint naming an unknown part warns instead.

**A full run is about 220 seconds** — 14 s of reimport and the rest suite. Three
files are most of it: `integration/test_screen_flow.gd` at 82 s,
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

Captured with `LEARNED_FACTS.md` §1 fact 55's route at 1600×900, 900 frames
through `--main-scene res://scenes/match/arena_basin.tscn`. The player is not
driven, which is the exact case that used to get run over.

**The machine sits still now, and that is this session's whole headline.** The
readout reads **0.1 m/s at one second and 0.1 m/s at fifteen**, with the hull in
the identical position in both frames. The previous capture read 0.9 climbing to
2.6 with nobody touching a key, and three sessions in a row wrote that down as a
defect they could not close. It is closed: §7.4's contact integration plus §7.7's
holding brake, measured at 0.000 m/s and 0.000 m of wander over six seconds on
flat ground.

**A first-time player survives, and can now stop, park and reverse.** The other
three questions a person asks in the first thirty seconds all have answers where
none of them did: `S` sheds 6.3 m/s in 4.3 m, letting go parks it, and holding
`S` at rest backs it out.

**It looks like a vehicle** (session 36's rebuild) and **you can see the fight**
(session 33's card placement); both hold in this capture.

Ranked by what would most improve a first-time player's experience:

**The opponent stops in front of you and shoots from there.** The final capture:
the opponent is a speck on the horizon at one second, closes across the basin,
**stops at its stand-off around eleven seconds**, and opens fire from there. At
fifteen seconds it is still standing off — plainly separated from the player in
the frame — and the player is at 52% integrity with eleven of twelve parts. Two
things had to be right for that: §15.7.4's second gate, and a stand-off widened
from fourteen metres to twenty because fourteen was derived on a flat slab and
the arena is a basin. Both intermediate attempts are recorded at their constants.

Ranked by what would most improve a first-time player's experience:

1. **The player's hull ends up on its side, and nothing drove it there.** The
   capture's last four seconds show the build rolled over, stationary, being shot
   at. It is not being driven — this is a parked hull taking fire — so what put it
   there is either the opponent's approach making contact before the stand-off
   widened, or the incoming rounds. **It is the most visible unexplained thing in
   the capture and it is not diagnosed.** Instrument it the way fact 77 says
   before theorising: attitude and per-contact normal force, every fifteen ticks,
   on the basin.
2. **The opponent takes eleven seconds to arrive.** A ground driver averages about
   **two metres a second** across the arena's fifteen metres of relief, against a
   build that does 6.3 on the flat. Sixty metres was tried for the spawn and the
   capture rejected it outright — no shots at all by fifteen seconds — so the spawn
   is at forty-two, which hides the problem rather than fixing it. §3.1.4.
3. **The two new chassis are unreachable in practice** — unchanged from last
   session, and the mirror opponent makes it *sharper*: a player who builds a
   walking Assembly now fights a walking Assembly, so the family finally has a
   fight of its own the moment anybody knows it exists. §3.2 is the cheapest half.
4. **A walking Assembly cannot reverse and can barely stop.** §13.9 gave it the
   strongest brake the family's model can produce and it sheds only half its speed
   in five seconds; a negative throttle moves it 0.01 m against a wheeled build's
   7.67. Both are §13.5's placement law having no sign in it. §3.1.2.
5. **The end card is drawn over nothing.** Unchanged. At the conclusion the orbit
   camera swings to an empty field and the card floats on it. §4 has the
   mechanism; what is missing is a decision about where the camera stands.
6. **One arena, and now one opponent *recipe* rather than one opponent build.**
   The mirror is a real improvement and it is not variety: every test drive is
   still the same basin and the same spawn. Doc 06's generator is the answer.
7. **Nothing rewards a good build over a heavy one.** Unchanged — except that
   with a mirror opponent the comparison is at last honest, because both sides
   carry the same handicap.
8. **The garage teaches nothing about *composition* until a placement is
   refused.** Unchanged.
9. **Nothing in `src/combat/` still knows what a team is.** §3.4.
10. **A rotary Assembly has a brake now and still no way to hold a hover**, so
   §12.8 is a control a player can use and cannot yet use *well*. §3.7.

**The bad news, plainly.** Five things.

**The player's build finishes the capture on its side and nothing explains it.**
Item 1 above. It is a parked hull under fire and it should not end up there; it is
undiagnosed and it is the first thing to instrument next session.

**The fight starts late.** Eleven seconds of watching a speck approach, on a
driver that crosses terrain at two metres a second against a build that does six
on the flat. Moving the spawn in only hides it. §3.1.4.

**`drive_torque_nm` did not come back, and the reason changed.** Two sessions of
`HANDOFF.md` said the 6400 N·m figure was capped by §7.4's instability. §7.4 is
closed and the figure still cannot move far: at 16000 the reference build takes
off under sustained full throttle and at 9600 it unloads two contacts over five
hundred ticks in a sustained turn and finishes on its back. **The cap is now the
hull's own stability** — a 0.97 g rollover threshold against contacts that make
1.05 — and that is a build and balance problem rather than a solver one. §3.1.1.

**§7.6's traction control got worse rather than better, and it is measured.**
With real lateral grip the contacts trim three quarters of an imposed spin on
their own, and the aid's brake bias leaves *more* spin than no aid at all —
0.35 rad/s against 0.26. Halving its ceiling moved that by a thousandth. Every
gain tuned above §7.4 is now untuned, and this is the one that was measured.
§3.1.3.

**An ambulatory Assembly still cannot be driven properly.** It cannot reverse, it
brakes at half strength, and doc 05 §13.8's measurement stands: a steering demand
moves its heading by a hundred and twelve degrees and its *sign* accounts for
under five of them. Three separate defects, one cause, and it is the family a
player is most likely to build next now that it has a chassis. §3.1.2.

The summary: **the ground under the game is sound for the first time — it stops,
it parks, it reverses, it corners — and what that exposed is that everything
tuned on top of it was tuned against a defect.**

## 3. The work queue

Ordered by what is worth doing next, not by dependency. Anything not listed here
is either done or is in section 4.

### 3.1 What closing §7.4 left behind

**Doc 05 §7.4 is closed.** The section carries the scheme, the two wrong turns,
the two extra energy sources found landing it, and the before/after table.
`LEARNED_FACTS.md` facts 83–87 carry the general shapes. Nothing below is that
work; all of it is work the repair *revealed*.

#### 3.1.1 The drive torque, and the hull that cannot take it

`pmv.combustion.standard.t2` still authors **6400 N·m** — 0.36 g against contacts
that hold 1.05 — and the cap is no longer the integrator.

Measured this session and reverted, both with the numbers in `CHANGE_LOG.md` §1:

- **16000 N·m**: sustained full throttle unloads the front pair and the Assembly
  leaves the ground. Fact 77's take-off, arriving from a different direction.
- **9600 N·m**: the reference build progressively unloads two contacts over five
  hundred ticks in a sustained turn and finishes on its back.
- **Retuning the contacts from μ 1.05 → 0.78** (and `fixed_rear` 1.09 → 0.80,
  the tracked bogie 1.34 → 0.95) is **landed**, under the rule *a contact may not
  out-grip the hull's own rollover threshold*. It stops a build tipping itself over
  on the spawn drop and costs nothing measurable. Doc 01 §10.3 carries it; every
  unshipped row in that table is still on the old basis.

The static stability factor of the reference build is **0.97 g**. Anything that
raises the drive torque has to be paired with either lower contacts or a lower
centre of mass, and the Prime Mover and the Effector Module sharing a deck four
cells above the belly is where that height comes from.

#### 3.1.2 The ambulatory family needs a sign in its placement law

**Three defects, one cause, and the family now has a chassis and a mirror
opponent, so a player will meet all three.**

- **A steering demand does not steer it.** Doc 05 §13.8: uncommanded −92.2°, full
  left +24.6°, full right +19.9°. A demand moves the heading a hundred and twelve
  degrees and its direction accounts for under five.
- **It cannot reverse.** New this session, and asserted as it stands in
  `tests/physics/test_braking_and_reverse.gd`: a negative throttle moves it 0.01 m
  over three seconds against a wheeled build's 7.67.
- **It brakes at half strength.** §13.9 freezes the gait with every foot planted,
  which is the strongest state the model has, and it sheds 1.45 m/s to 0.65 in
  five seconds.

All three are `turn_command` and the travel demand reaching only the *correction*
term of §13.5's placement law. The repair is a term that carries the sign of the
demand into the cadence and the swing, which is new architecture in doc 05 §13
rather than a solver fix.

#### 3.1.3 §7.6's aids are untuned, and the yaw loop is a net negative

Measured: the contacts alone take three quarters of an imposed 1 rad/s off in six
ticks, and the aid leaves 0.35 rad/s where no aid leaves 0.26.
`MAX_BRAKE_FRACTION` came down from 0.55 to 0.25 this session — 0.55 was locking
the patch the aid was biasing — and it moved the measurement by a thousandth, so
the mechanism is the friction circle rather than the ceiling.

`tests/physics/test_ground_assembly.gd` asserts the measurement with the reasoning
at the constant. What it needs is a re-derivation of `YAW_GAIN_NM_PER_RAD_S` and
of whether a brake bias is the right actuator at all now that a braked patch has
real lateral grip to lose. The slip limiter is untouched by any of this and is
still doing its job.

#### 3.1.4 A ground driver crosses terrain at two metres a second

**The most player-visible thing left.** On flat ground the reference build does
6.3 m/s inside four seconds; across the arena's fifteen metres of relief an
`AiDriver` averages about two, which is why the spawn distance had to come back
from sixty metres to forty-two.

Three things are known and none of them has been measured against the others:

- §15.7.1's `APPROACH_MIN_THROTTLE` taper deliberately does not drive hard on
  slopes, and the section records that raising it broke the match.
- §7.6's corrective brake now genuinely retards a flank, and a driver holding a
  steering demand across a slope is holding a yaw error the whole way. §3.1.3.
- `drive_torque_nm` is 0.36 g. §3.1.1.

Instrument it the way fact 77 says: throttle, brake, steer, speed, **grounded
contact count and the four normal forces**, every fifteen ticks, on the basin
rather than on a slab.

### 3.2 Make the two new chassis reachable, and give the control card a first-run flag

**The chassis half is the player-facing one and it is small.** Doc 01 §7.1's
family lock shipped with the parts and without any way for a player to meet them:
the catalogue lists them, the validator enforces them, and nothing in the game
says the option exists. Three cheap steps, in order of value:

1. **A second and a third `StarterBlueprint`.** The class already holds the one
   hand-authored recipe every screen falls back to; an `ambulatory()` and a
   `rotary()` alongside `skirmisher()` would give the garage something to open on
   other than a wheeled hull, and `tests/combat_arena.gd` has both layouts
   already proven. **Read `LEARNED_FACTS.md` fact 76 first** — the arena's
   layouts are the reference, not a copy to make a third of.
2. **Let the opponent be one of them.** `MatchScreen` spawns the shipped starter;
   spawning a walking or a flying opponent instead is one constant, and it is the
   only way a player sees a family they are not already driving.
3. **Say so in the inspector.** A Core Module's card names its mounts and its
   speed cap and does not name the one figure that decides what can be bolted to
   it. `PartInspector._append_core` is where a chassis-family row goes.

Step 2 has a real blocker worth knowing: a rotary opponent needs §3.7's
stability-augmentation layer, because `AiDriver` aims and fires but does not fly.
An ambulatory opponent does not — it walks, badly, and §3.1.2 is why.

**The control card's first-run flag** is the older half of this item and is
unchanged. The placement and the dwell are done (session 32): the card sits in
the upper left and stands down on the player's first throttle, steer, or fire.
What is left is that it is raised unconditionally on every entry to a match,
because there is nowhere to store "they have seen it". That is
`SyndicateSettings` work.

### 3.3 What is left of braking, and it is small

**This item was "a player cannot brake" for two sessions and the chain is now
complete.** `veh_brake` → `ControlInput.brake` → §15.5's release → the contact's
resisting torque; `veh_handbrake` → §7.7's holding brake, which is also engaged
automatically on a record demanding neither drive nor brake; §13.9 for the
walking family and §12.8 for the rotary one. `tests/physics/test_braking_and_reverse.gd`
measures all of it.

Three residuals, all small and all recorded at their constants:

1. **A walking Assembly brakes at about half strength and cannot reverse.**
   §3.1.2, and it is the same defect as its steering.
2. **`veh_boost` still has a producer and no consumer.** The only field on
   `ControlInput` left in that state now that `handbrake` has one. Doc 05 does not
   define what a boost does, which is the blocker and is a smaller decision than
   the handbrake was.
3. **The aid authority has no control.** `ControlSystem.aid_authority` defaults to
   full and the settings screen that should write it is doc 11 work — and §3.1.3
   makes that more interesting than it was, because the aid is currently a net
   negative and a player who could switch it off would be faster.

### 3.4 Decide whether friendly fire exists

§15.7.5's ladder fixed the *geometry* — three drivers converging on one target no
longer stand in each other's line — and deliberately did not touch the rule.
Nothing in `src/combat/` knows what a team is: `DamagePacket` names a source
Assembly and `DamageResolver` never asks whose side it is on, so a round that
reaches a friend does full damage.

**The shipped match no longer demonstrates it**, because there is one opponent
and it has nobody to hit but the player. That makes this cheaper to ignore and no
less unresolved: `tests/physics/test_team_engagement.gd` still fights five a side
and doc 06's generator will put several opponents back.

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
- **The two family chassis are `t3` baselines with no family behind them**, so
  doc 01 §14 rule 13's tier scaling has nothing to compare either against — the
  same vacuum the rotor family is in. A `core.ambulatory.strider.t4` would make
  the rule non-vacuous in a second place.
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
- **The ambulatory steering demand is a disturbance with a sign attached, not a
  heading authority.** Doc 05 §13.8 now carries the measurement: full left ends
  at +24.6° and full right at +19.9° from an uncommanded −92.2°, so the demand
  moves the heading a hundred and twelve degrees and its direction accounts for
  under five of them. `turn_command` rotates the plant offset and nothing else.
  §3.1.2 has the repair, and it is the family's limiting defect.
- **An ambulatory Assembly still cannot be asked to turn and travel
  independently** (§4.16). One number doing two jobs, and the above is what that
  costs.
- **`boost` has a producer and no consumer.** `handbrake` gained one this
  session — doc 05 §7.7's holding brake — and `ControlInput.brake` now reaches all
  four families through §7.7, §12.8 and §13.9. Doc 05 does not define what a boost
  does, which is the blocker. §3.3.
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
- **A tracked build pitches to about 20° under a full-strength stop**, recovers,
  and stays on its tracks. §7.7's proportioning is what makes that true; without it
  it went past vertical. Whether 20° is the right amount of dive is a feel question
  and wants a scene to answer it.
- **A tracked pivot drifts a couple of metres** rather than turning about a
  point. The flanks counter-rotate correctly but their forces do not cancel
  exactly, because the two bogies sit at slightly different offsets. Whether that
  is worth correcting is a feel question and wants a scene to answer it.
- **The wheeled build wanders under full throttle with the aid off.** Deep
  wheelspin is unstable by construction — past the friction peak, more slip means
  less force — so once one flank hooks up before the other the Assembly yaws. That
  is what a burnout does. §7.4's limit cycle is no longer part of the answer, so
  what is left is the real thing.
- **`drive_torque_nm` is a third of what the contacts could hold, and the cap is
  no longer §7.4.** It is the hull's own 0.97 g rollover threshold against contacts
  that make 1.05: measured this session, 16000 N·m takes the build off the ground
  under sustained throttle and 9600 rolls it over in a sustained turn. §3.1.1.
- **Doc 05 §7.6's traction control has no reachable fixture on the shipped part
  set**, for the same reason — the shipped Prime Mover cannot out-torque the
  contacts. `test_ground_assembly` supplies its own over-torqued mover through the
  Assembly's `PowerSystem` and says so. Its **yaw loop** is a separate and worse
  problem: it is now a net negative and §3.1.3 owns it.
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
- **Five files assert a defect as it stands, and every one of them says so at the
  constant.** `tests/physics/test_ambulatory_drift.gd` asserts the walking
  family's yaw drift, the standing one, and that the two opposite steering demands
  land within five degrees of each other; `tests/physics/test_braking_and_reverse.gd`
  asserts that the same family cannot reverse at all and brakes at half strength;
  `tests/physics/test_ground_assembly.gd` asserts that §7.6's yaw loop leaves more
  spin than no aid at all; `tests/physics/test_ram_attitude.gd` asserts that a
  driver arrives at bare contact rather than with clear air; and
  `test_team_engagement`'s five-a-side asserts that it runs to the timeout. Each
  goes red when the thing it records is repaired, and the fix in every case is to
  re-measure and re-assert, never to loosen.

  **`test_rest_stability` came off that list in session 38 and is the precedent
  worth having.** It was written asserted-as-it-failed against §7.4's limit cycle,
  with the section it came from saying that closing the defect would turn the file
  red and that the fix was to re-measure. That is exactly what happened, and the
  file now carries the before/after table rather than the complaint.
  `test_recoil_geometry`'s traversed-yaw claim **inverted** in the same session —
  a parked hull absorbs the round now — and was re-framed rather than deleted.

  Two came back the other way in session 36 and are worth knowing as precedent.
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
