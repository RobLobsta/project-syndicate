# HANDOFF

**The work queue.** What to do next, in the order it is worth doing.

`CLAUDE.md` and the thirteen documents in `/docs/` are the only authority. This
file has none — it is a plan, and it is the one file in the repository that is
allowed to be wrong about the future.

Two companions, neither optional:

- **`LEARNED_FACTS.md`** — engine behaviour that cost somebody an afternoon,
  testing rules paid for in shipped defects, and readings of the architecture
  decided once. **Read §1 before writing code and §3 before writing a test.**
- **`CHANGE_LOG.md`** — what each session did and what each test defends.

Older comments in `src/`, `tests/` and `tools/` cite section numbers from the
single `HANDOFF.md` these three files were split out of in session 24. **The
mapping is in `LEARNED_FACTS.md` §0 and only there.** A bare `§N.M` anywhere else
refers to whichever document in `/docs/` was named just before it.

---

## Where this stands

**It is a game with a loop, and the machine under it drives.** `godot --path .`
opens on a menu. The menu opens a garage where a wheeled Assembly stands on the
Build Lattice with fifteen parts beside it and its mass, power, mounts, top
speed, integrity and rollover threshold on the right. **M** mirrors, **Ctrl+Z**
takes back a misclick, a removal that would orphan something asks first. TEST
DRIVE puts that build into a basin against one opponent built from the player's
own blueprint, thirty metres away, carrying the same six hundred rounds. They
fight. A card says which way it went. All of it is playable on a keyboard or on a
controller, and a build can be made with either.

The wheeled family goes straight, corners, stops, parks, reverses and coasts to a
halt; `tests/physics/test_wheeled_drive_cycle.gd` runs that whole cycle every
suite run and still passes after the session-44 rebuild. **The figures that used
to be quoted here — 29 m of zero lateral deviation, 0.81 rad/s at 32° of lock,
22.6 m/s of top speed — were measured on a hull that has since changed shape and
gained 54% of its yaw inertia, and have not been re-taken.** §3.0.

**This session: five vehicles, remodelled against five photographs.**

The part table had been rescaled twice for *density* and never once for *shape*,
so every Assembly in the game was the same 6x4 box with different running gear
underneath. Doc 01 §10.1 now derives each chassis from a reference image, and no
two are the same section any more:

| | Section (W x H) | Length | The ratio that forced it |
|---|---|---|---|
| Road car | 2.00 x 1.00 m | 3.50 m | height is a quarter of length |
| Utility truck | 2.50 x 1.50 m | 5.00 m | height **equals** width |
| Tracked platform | 2.50 x 1.25 m | 6.00 m | as long as the track under it |
| Walking torso | 1.50 x 2.50 m | 2.50 m | taller than it is long |
| Rotorcraft | 1.00 x 1.50 m | 7.00 m | ten times longer than it is wide |

Six new parts carry them: a 6.00 m gun, a bogie as long as its hull, a 0.75 m
steered/fixed contact pair, a Prime Mover that lies down, and the utility chassis.

**The tracked family stands level for the first time.** 12 of 12 road stations
loaded at **1.4°** of pitch, against 8.1° nose-up with two carrying nothing — and
`HANDOFF.md` §3.1.2's three items are done: a bogie longer than the hull,
`pivot_taper_mps` 9.0 → 16.0, and `lateral_grip_ratio` 1.35 → **0.85**.

**The walker is a walking machine.** 5.00 m tall against 2.63, on a torso that is
taller than it is long rather than a box lying on its side, standing at 0.6° after
two measurements got the mass off its levers (`LEARNED_FACTS.md` fact 109).

**The bad news, plainly. Three things, and the third is the one that matters.**

**The remodel is not finished.** The suite went from green to **27 failures across
12 files**, and almost all of them are assertions that quote a geometry which has
moved — a mass, a wheelbase, a tick count, a hover margin. They are re-measurements
rather than defects, but *until they are re-measured nobody knows which*, and a
suite this red cannot tell a regression from an expectation. **§3.0 is the whole
of the next session's work and nothing else should start before it.**

**The walker is not the reference's proportion and cannot be.** The humanoid
reference is a biped whose torso is 1.85 times as tall as it is deep. Doc 05 §13's
virtual leg has a **point foot**, so fore-and-aft foot separation is the only pitch
stability the family has, and torso depth and stance base are the same number. This
is architecture, not data. §3.1.3.

**A wheeled build is 3.00 m wide over a 2.00 m body.** The contacts stand proud of
the flanks because a hub mounts inboard and its wheel hangs outboard, and the
lattice has no way to recess a contact into a hull. The reference car is 0.42 of
its length in width and this is 0.60. Nothing is wrong; the construction cannot
express a wheel arch. §3.11.

---

---

## 1. Getting a working environment

Nothing is installed by default. One command provisions everything:

```bash
tools/ci/bootstrap_env.sh          # idempotent; ~75 MB download, ~30 s
```

That puts Godot **4.7.1-stable** in `.tooling/`, which is gitignored in full and
holds the binary, the engine's `XDG_*` data and test output. Run the engine only
through the wrapper — without it Godot scatters editor settings and shader caches
across `$HOME` and CI stops being reproducible:

```bash
tools/ci/godot.sh --headless --path . --version
tools/ci/run_all_checks.sh          # full suite; reimports first
```

`GODOT_VERSION` overrides the pinned version for `bootstrap_env.sh`. The engine
downloads from the GitHub releases CDN, which the agent proxy allows; the GitHub
**API** is blocked, so do not try to resolve "latest" through `api.github.com`.

### The suite

**100 files, 8069 checks, and 27 failures** as of session 44, in about 300
seconds — 14 s of reimport and the rest suite. It was green at 100 files and 7760 checks; §3.0 is the work that gets it back and is the next session's whole
job. Three files are most of it: `integration/test_screen_flow.gd` at
82 s, `physics/test_ground_terrain.gd` at 41 s and `integration/test_ground_deform.gd`
at 30 s. The runner prints per-file timings; check before assuming where the cost
is.

`run_all_checks.sh` fails on any engine error printed during the suite, not only
on recorded assertion failures (`LEARNED_FACTS.md` §1 fact 34). That is why
nothing in `src/` may `push_error` on a state a test deliberately exercises.

`test_screen_flow` is the most expensive file and is worth keeping. It opens two
real `MatchScreen`s — each a Ground Array, primed collision streaming and four
Assemblies — and those are the two exits a player has: a test drive carrying the
build they made, and a rematch carrying the same one. The rematch was once wired
to the menu by a slip and *nothing* caught it. If this has to come down, the
honest lever is making a match cheaper to construct, not shortening the flow.

Two flags, both for sweeps rather than for people: `--no-import` skips the
reimport when nothing under `data/` changed, and `--fail-fast` stops at the first
failing file. There is deliberately **no way to reorder or subset a run** —
`LEARNED_FACTS.md` §1 fact 62 has the measurement that closed that door.

### The sweeps

```bash
python3 tools/ci/sweeps/drive_cycle_sweep.py         # doc 05 §6.5/§7.7/§15.5, doc 11 §7
python3 tools/ci/sweeps/burn_and_hold_sweep.py       # doc 07 §15.5, doc 08 §7.1/§7.3
python3 tools/ci/sweeps/briefing_and_edge_sweep.py   # doc 05 §15.7.4, doc 11 §14.6, doc 07 §15
python3 tools/ci/sweeps/ai_layer_sweep.py --list     # just the fault names
python3 tools/ci/sweeps/ai_layer_sweep.py -j1 --full steer-sign-flipped
```

Ten of them; `CHANGE_LOG.md` §3 says what each covers and what still survives.
A sweep's `BASELINE` is a check count and moves with the suite; update it in the
same change as anything that moves the count. **Every one of them is currently
stale**, because session 44 moved the count and left the suite red — a sweep run
against a failing baseline reports `CAUGHT` for every fault including the ones
nothing noticed (fact 64). Do not run a sweep until §3.0 is done. A sweep costs about a minute a
fault at `-j4` — a fault caught by a unit test costs seconds and one caught only
by a physics file costs a full run, so plant against the cheap files where the
law allows it.

Workers run in throwaway copies under `/tmp`, so `-j2` and above cannot leave a
planted fault in your checkout. `-j1` still patches in place: do not `git add -A`
while it runs, and check `git status` after. A run that wedges is killed at 420 s
and reported as `CAUGHT-HUNG`.

Still true regardless of speed: build a fixture once in `before_all` and reset it
per test; four tests that each spawn an Assembly spawn them on top of each other.
See `LEARNED_FACTS.md` §1 facts 36 and 44 before adding to `tests/physics/`.

---

## 2. The player-experience review (CLAUDE.md §10 rule 18)

Recorded every session, because a green suite says nothing about whether the
thing is any good to play. **Section 3's ordering comes from here.**

**Not captured this session, and that is a gap worth naming.** The rule asks
whether a customer would get the best possible experience from the game as it
stands, and the honest answer is that **the machine was taken apart and is not
back together yet**. What follows is read off the suite's own instrumentation and
off the geometry, not off a frame.

**What a player would now see, and it is the point of the whole session.** Five
vehicles that are five *different shapes* rather than one box with different
running gear underneath:

| | Overall (L × W × H) | Reads as |
|---|---|---|
| Road car | 5.00 × 3.00 × 2.00 m | long, low, small wheels |
| Utility truck | 6.50 × 3.50 × 2.75 m | tall slab-sided cab, bonnet, big wheels |
| Tracked platform | 8.50 × 4.00 × 3.00 m | 6 m of hull, 6 m of track, 6 m of gun |
| Walking machine | 2.75 × 2.50 × 5.00 m | upright torso on long legs |
| Rotorcraft | 7.00 × 3.00 × 3.50 m | slender fuselage, twin discs on outriggers |

The tracked one is the biggest single gain a player would feel: it stood 8.1°
nose-up on two dead road stations and now sits level on twelve, and it carries a
gun that reaches 2.50 m past its own nose instead of a 1.75 m autocannon.

**The bad news, plainly. Three things.**

**The suite is red and that is the state the game is in.** 27 failures across 12
files. Nothing observed so far is a system that stopped working — they are
assertions quoting geometry that moved — but a red suite cannot tell a regression
from an expectation, so **the honest statement is that nobody currently knows
whether this build plays as well as the last one.** §3.0.

**A wheeled build is 3.00 m wide over a 2.00 m body**, because a hub mounts
inboard and its wheel hangs outboard and the lattice cannot recess a contact into
a hull. The reference car is 0.42 of its length in width; this is 0.60. It is the
one proportion in the set that the construction, rather than the data, refuses.

**The walker is a walking machine and still not the reference.** It is 5.00 m tall
with an upright torso, which is the change; it has four legs where the reference
has two, and its torso is as deep as it is tall where the reference's is half
that. Both are doc 05 §13's point foot (fact 109), both are architecture, and a
player who knows what the reference is will notice immediately.

Ranked by what would most improve a first-time player's experience:

1. **Finish the re-measurement.** §3.0. Nothing below can be trusted until the
   suite can tell a regression from a moved expectation.
2. **The fight is two parked hulls trading fire.** Unchanged from last session,
   and now the top *design* item. §3.1.4.
3. **A walking Assembly cannot reverse well and can barely stop** — though it now
   reverses 5.16 m where it managed 0.01, which is the first movement on this in
   five sessions. §3.1.3.
4. **The two new chassis are still unreachable in practice**, and there are now
   five silhouettes a player cannot choose between. §3.3 is the same task and
   worth more than it was.
5. **Sustained fire turns the whole screen brown.** Unchanged, cheap, and the only
   thing in this list a player meets in their first ten seconds. §3.11.
6. **The end card is drawn over nothing.** Unchanged.
7. **One arena, and one opponent recipe beyond the mirror.** Doc 06's generator.
8. **Nothing rewards a good build over a heavy one.** Unchanged.
9. **Nothing in `src/combat/` knows what a team is.** §3.5.
10. **A rotary Assembly has a brake and still no way to hold a hover.** §3.7.

The summary: **the game now contains five machines a person could tell apart in a
single frame, which it has never done before, and the price was a suite that has
to be re-measured before anyone can say what else the change did.**

## 3. The work queue

Ordered by what is worth doing next, not by dependency. Anything not here is
either done or is in section 4.

### 3.0 Re-measure the suite against the rebuilt geometry

**Do this before anything else.** Session 44 moved every chassis section, four
masses, a limb reach, a disc radius and a track patch, and the suite is carrying
**27 failures across 12 files** as a result. Every one seen so far is an assertion
quoting a number the rebuild moved, not a system that stopped working — but that is
a claim about a set nobody has finished walking, and the ones that are *not*
re-measurements are hiding in the same list.

The rule is `LEARNED_FACTS.md` §3's and it has not changed: **re-measure and
re-assert; never loosen.** Where a file asserts a defect as it stands, the
measurement moves and the complaint stays.

**Every remaining failure is in `tests/physics/`.** Everything in `tests/unit/`,
`tests/integration/` and `tests/arch/` is green, which is worth knowing: the data,
the registry, the placement chain, the mass solver and the screen flow all agree
with the rebuilt geometry. What is left is what the simulation *does* with it.

**Two are not obviously re-measurements and are the first things to look at.**

- **`test_inertia_coupling` loses 6.4% of its angular momentum** over a five-second
  torque-free soak, against a 5% tolerance — 32 443 before, 34 505 after. The
  fixture's tensor changed shape, so this may be an integrator accuracy question
  rather than a broken sign, but it is the file whose whole purpose is catching a
  flipped `−ω × (I ω)` and it should not be loosened without understanding which.
- **`test_ground_assembly`'s §7.6 yaw aid is now the *worse* of the two options** —
  0.692 rad/s left with the aid against 0.693 without, on an imposed 1.0. That is
  the comparison §3.1.4 already disputed the generality of, measured on a hull
  whose yaw inertia moved; re-derive `YAW_GAIN_NM_PER_RAD_S` against the new
  tensor rather than re-asserting the number.

**The rest are re-measurements, and some moved the right way.**

- **`test_melee_duel`** — the melee walker closes 12.0 m to 11.0 and no longer
  reaches. It is 6.75 m long now with the arms and blades out front, and it stoops
  12.8° rather than the 29.6° it did. §3.8.
- **`test_family_duels`, `test_team_engagement`, `test_ai_engagement`** —
  engagement outcomes, hover margins and stand-off distances against builds whose
  mass and inertia all moved. Read fact 44 before asserting any count.
- **`test_ambulatory_drift`, `test_braking_and_reverse`** — the walking family's
  numbers moved a long way and some moved the *right* way: **a walker now reverses
  5.16 m where it managed 0.01**, and a tracked build reverses at all. Both files
  assert defects as they stand, so both go red when the defect closes; re-measure
  and re-frame rather than deleting, and `test_rest_stability` is the precedent.
- **`test_recoil_geometry`, `test_drive_and_shoot`** — a hull whose `I_zz` grew
  54% on an unchanged mass, and everything downstream of it.

### 3.1 The motion layer

#### 3.1.1 The drive torque, and why it did not move

`pmv.combustion.standard.t2` still authors **6400 N·m**, and the reason has
changed twice. It was capped there because 10 200 pumped the suspension until the
Assembly took off (§7.4, closed session 38) and because 9600 rolled it over in a
sustained turn (§6.5, closed session 39). **Both measurements were void and both
were re-taken.** On the wheeled reference build with §7.8's governor in place, a
600-tick full-throttle run and a 600-tick full-lock turn at **16 000 N·m** finish
on all four contacts with 2.8° of roll and not one airborne tick:

| N·m | straight-line top | airborne ticks | worst roll in a full-lock turn |
|---|---|---|---|
| 6400 | 15.65 m/s | 0 | 2.5° |
| 9600 | 20.85 m/s | 0 | 2.4° |
| 13 000 | 23.20 m/s | 0 | 2.4° |
| 16 000 | 23.40 m/s | 0 | 2.8° |

**The figure stayed at 6400 because the binding constraint is now the tracked
recipe.** §3.1.2. Raised to 9600 the suite fails in three places, all of them
tracked: it cannot stop without pitching past vertical and cannot reverse at all.
The torque goes up when a tracked build stands level.

#### 3.1.2 The tracked family — done, and what it unblocks

**Closed in session 44.** All three items this section listed are shipped:

1. **A longer bogie.** `mot.tracked.long_bogie.t3` runs 6.00 m with 5.60 m of
   patch and six road stations, under a 6.00 m `core.tracked.hauler.t3`.
2. **`pivot_taper_mps` re-derived**, 9.0 → 16.0. At 9.0 the differential was down
   to a third by 6 m/s, which is why full lock yawed a tracked build 0.03 rad/s.
3. **`lateral_grip_ratio` questioned and answered**, 1.35 → **0.85**. A machine
   that steers by breaking its patch loose sideways should not grip harder
   sideways than it drives forward, and the longer the patch the more wrong it is.

Measured at rest: **12 of 12 road stations loaded at 1.4° of pitch**, against 8.1°
nose-up with the two forward stations carrying nothing. **The inversion in a
sustained turn has not been re-measured** and this section said it should not be
chased until the three above were settled — they now are, so that measurement is
the next thing this family wants, along with whether §3.1.1's drive torque can
finally come off 6400 N·m.

#### 3.1.2a The old tracked section, kept for its measurements

**It has its own chassis now and that did not fix it.** `core.tracked.hauler.t3`
ships — nine cells rather than the command core's thirteen, `CHASSIS_TRACKED`,
1700 kg, a 14 m/s cap that §7.8's governor now enforces — and the shipped recipe
is **not on it**, because migrating measures worse:

| Migrated to the nine-cell chassis | before | after |
|---|---|---|
| Rest pitch | 4.7° nose-up | **1.6°** |
| Front-to-rear load spread | 3.2× | **1.45×** |
| Inverts in a sustained turn | yes | **yes** |
| Yaw at full lock, 6 m/s | 0.030 rad/s | 0.035 rad/s |
| Brakes without going over | yes | **no** |

`core.command.compact.t2` therefore keeps `CHASSIS_GROUND_TRANSITIONAL`, named so
that nobody mistakes it for a design.

**What the family actually needs is a contact base longer than its hull, and the
part set cannot express one.** `mot.tracked.short_bogie.t2` runs **eight cells** —
1.90 m — so one per flank is the design and two do not fit on any chassis in the
registry. A nine-cell hull is 2.25 m over a 1.43 m base and still cannot carry a
six-cell Prime Mover and a nine-cell Effector Module without one of them
overhanging it.

Three things to do, in order:

1. **Author a longer bogie**, or a `t3` with more road stations, so a flank can
   carry a patch as long as the hull. That is the one change that makes the rest
   tractable.
2. **Re-derive §14.2's `pivot_taper_mps`.** At 9.0 the differential is down to a
   third by 6 m/s, which is why full lock yaws the build 0.03 rad/s — it cannot
   turn at any speed a player drives at.
3. **Question `lateral_grip_ratio = 1.35`.** A patch with *more* lateral grip than
   longitudinal is the wrong way round for a machine that steers by breaking the
   patch loose, and it is the other half of why it will not turn.

The inversion is downstream of all three and should be re-measured once they are
settled rather than chased on its own.

#### 3.1.3 The ambulatory family needs a sign in its placement law

Three defects, one cause, and the family now has a chassis and a mirror opponent,
so a player will meet all three.

- **A steering demand does not steer it.** Doc 05 §13.8: uncommanded −92.2°, full
  left +24.6°, full right +19.9°. A demand moves the heading a hundred and twelve
  degrees and its direction accounts for under five.
- **It cannot reverse.** Asserted as it stands in
  `tests/physics/test_braking_and_reverse.gd`: 0.01 m over three seconds against a
  wheeled build's 7.67.
- **It brakes at half strength.** §13.9 freezes the gait with every foot planted,
  which is the strongest state the model has, and it sheds 1.45 m/s to 0.65 in
  five seconds.

All three are `turn_command` and the travel demand reaching only the *correction*
term of §13.5's placement law. The repair is a term carrying the sign of the
demand into the cadence and the swing, which is new architecture in doc 05 §13
rather than a solver fix.

**Session 44 moved two of the three and added a fourth.** The family's chassis and
limb were rebuilt against a humanoid reference — a 2.50 m torso on a 2.60 m reach,
standing 5.00 m — and the reverse went from 0.01 m over three seconds to **5.16 m**,
which is the first movement on any of these in five sessions. It is a side effect
of geometry rather than a repair of §13.5, and re-measuring the other two against
the new build is part of §3.0.

**And the fourth: a biped is not expressible.** Doc 05 §13's virtual leg is one
spring-damper force along the hip-to-foot line with a **point foot**, so
fore-and-aft foot separation is the family's only pitch stability and torso depth
is the same number as stance base (fact 109). The humanoid reference's torso is
1.85 times as tall as it is deep and its legs are half its height; neither is
reachable while a foot has no length. What it needs is a **foot with an extent and
an ankle torque**, or a balance controller modulating stance force fore and aft —
either is a doc 05 §13 section, and either would also give §13.9's braking
something to push against. Measured on the way in: the rebuilt torso over the old
1.50 m stance stooped 25.8° with every contact unloaded; widening the stance to
2.00 m brought it to 0.6° with nothing else changed.

#### 3.1.4 The engagement has no manoeuvre in it

**The top item in the review.** The opponent now arrives at about four seconds
rather than eleven — the spawn came in to 30 m — and then both machines stand
still and trade fire until one of them stops existing.

§15.7.4 gates firing on "inside its stand-off **and stopped**", and the gate is
correct on its own terms: doc 01 §10.5's recoil yaws a firing hull off its own
target, which is measured in `test_drive_and_shoot`. So a dynamic engagement is
not a matter of deleting the gate. What it wants is either a driver that keeps
lateral station while firing — circling at its stand-off rather than parking —
with the gate re-derived against *lateral* rather than *any* motion, or a mount
that can hold a bearing through a hull that is moving, which is doc 07 §11's
prediction and is unwritten.

**And the approach is still slow.** A ground driver crosses the arena's fifteen
metres of relief at about two metres a second against a build that does 9.3 on the
flat. Nothing has measured why on terrain, because `CombatArena` builds a slab and
the basin exists only in `MatchScreen`. Instrument it the way fact 77 says —
throttle, brake, steer, speed, **grounded contact count and the four normal
forces**, every fifteen ticks — on the basin. Two candidates and neither has been
compared with the other: §15.7.1's `APPROACH_MIN_THROTTLE` taper, and §7.6's
corrective brake retarding a flank the whole way across a slope.

**§7.6's own verdict is condition-dependent and only one condition is measured.**
`test_ground_assembly` asserts that the aid leaves *more* of an imposed spin than
no aid at all, and that still passes. Probed at 7.8 m/s under full throttle with
an imposed 1 rad/s, the aid is a clear gain: 4.5° of residual heading error
against 12.1° with it off. Re-derive `YAW_GAIN_NM_PER_RAD_S` against both before
touching it.

### 3.2 What is left of the controller

**The match and the garage are both playable on a pad now.** Doc 11 §7.3's
placement is done — a virtual cursor on the left stick, the crosshair that shows
where it is, and the camera on the right stick — and
`tests/integration/test_pad_build.gd` places a part from the stick alone. What is
left is navigation rather than placement:

1. **The catalogue does not take focus.** Godot's `ui_*` actions traverse
   `Control` focus for free and are bound to the pad by default; nothing in
   `CataloguePresenter` accepts focus, so a player on a pad cannot choose which
   part to arm without a mouse. That is the one remaining hard stop.
2. **`cam_pan` has a keyboard binding, no gamepad binding and no consumer.** With
   the cursor it is not needed; either give it one or take it out of §7.2's list.
3. **Touch is specified and unbuilt.** `touch_placement_controller.gd` does not
   exist and the compact tier has no bottom sheet, so a phone still cannot build.

### 3.3 The chassis are still unreachable, and so is the edge

Doc 01 §7.1's family lock shipped with the parts and no way for a player to meet
them. **The inspector half is done** — a Core Module's card now names the
families it carries, so a refused limb has a reason a player can read. Two steps
left:

1. **A second and a third `StarterBlueprint`.** An `ambulatory()` and a `rotary()`
   beside `skirmisher()` would give the garage something to open on other than a
   wheeled hull. **Read `LEARNED_FACTS.md` fact 76 first** — the arena's layouts
   are the reference, not a copy to make a third of.
2. **Let the opponent be one of them.** `MatchScreen` spawns the shipped starter;
   spawning a walking or flying opponent is one constant, and it is the only way a
   player sees a family they are not already driving. A rotary opponent is blocked
   on §3.7; an ambulatory one is not, it just walks badly (§3.1.3).

**And a `melee()` beside them, which is now cheap.**
`CombatArena.Recipe.MELEE`'s layout is authored, validated and fought (§3.8) —
the ambulatory hull, an Appendage at `(20, 17, 19)` and `(27, 17, 19)`, an edge at
`(20, 17, 13)` and `(27, 17, 13)` — so a `StarterBlueprint.melee()` is that cell
list and nothing else. It is the only route by which a player ever holds the
weapon sessions 18, 42 and 43 built, and until it exists the honest statement is
that the edge is not in the game.

**And session 44 made this the most valuable item in the file that is not §3.0.**
There are now **five distinct silhouettes** in the registry — a road car, a
utility truck, a tracked gun platform, a walking machine and a rotorcraft — and a
player can reach exactly one of them. Everything else in the part table is
reachable only through a catalogue with no chassis to root it on. The blueprints
are cheap now, because `tests/combat_arena.gd` carries all five layouts as
validated cell lists; what is missing is still the chooser.

**None of the four is reachable without a way to choose one.** All four blueprints
would be dead code the moment they are written: `skirmisher()` has three callers
and nothing in the interface offers an alternative. The blueprints and the chooser
are one task, not two, and the chooser is the half that is doc 11 work — a row of
build presets on the main menu, or a "new build" control in the garage.

### 3.4 Two controls with a producer and no consumer

- **`veh_boost`.** The only field left on `ControlInput` in that state now that
  `handbrake` has one. Doc 05 does not define what a boost does, which is the
  blocker and is a smaller decision than the handbrake was.
- **`ControlSystem.aid_authority`** defaults to full and the settings screen that
  should write it is doc 11 work — and §3.1.4 makes it more interesting than it
  was, because a player who could switch the aid off might be faster.

### 3.5 Decide whether friendly fire exists

§15.7.5's ladder fixed the *geometry* — three drivers converging on one target no
longer stand in each other's line — and deliberately did not touch the rule.
Nothing in `src/combat/` knows what a team is: `DamagePacket` names a source
Assembly and `DamageResolver` never asks whose side it is on.

The shipped match no longer demonstrates it, because there is one opponent with
nobody to hit but the player. `tests/physics/test_team_engagement.gd` still fights
five a side and doc 06's generator will put several opponents back. The roster
exists on `AiContext` and the match layer owns it; what does not exist is a
decision about whether the resolver should be told.

### 3.6 Sweep the bounds nobody reaches

Invariant I-12 lists eighteen bounds and the suite demonstrably reaches almost
none. Deleting each in turn and watching for green is a cheap way to find which
are load-bearing, and at a couple of minutes a sweep it is genuinely cheap. The
fixture that closes one has to be built to *exceed* it and then assert that it
does. Likeliest untested: chain-reaction depth 3, collapse cascades, melee sweep
segments, and the two debris caps.

### 3.7 A stability-augmentation layer, and the rotary family

`CombatArena._fly` is three loops through `ControlInput` and is the only thing in
the repository that can hold a hover. A **player** flying a rotary build needs the
same loops, so it is not a tactic and does not go in `AiDriver`. It wants a layer
between both `ControlInput` producers and the motion layer, which doc 05 does not
have. An `AiDriver` handed a rotary Assembly aims and fires but does not fly.

### 3.8 The edge has been to a fight; now it needs to survive one

**Done, and it answered both questions it was written to answer.**
`CombatArena.Recipe.MELEE` and `tests/physics/test_melee_duel.gd` ship: a driver
**can** hold contact (372 energised ticks off one swing, resolving on 121), and
§15.4's impulse **cannot** knock a target out of reach (0.03 m of re-opening).
The second of those closed a fault recorded as a survivor since session 42.

**Every figure in this section was measured before session 44 and none has been
re-taken.** The recipe is on a torso two and a half times taller than the one it
was measured on, with arms a third longer and blades reaching further ahead of a
machine that is now 6.75 m nose to tail. It stoops 12.8° where it stooped 29.6°,
which is better, and it closes 12.0 m to 11.0 and no longer reaches, which is
worse. Re-measuring it is part of §3.0 and the numbers below are stale until then.

What is left is what the fixture found, and both are open questions rather than
tasks with an obvious shape:

1. **The walker cannot reach a fight**, which is §3.1.3 rather than doc 07 §15:
   it loses ground over thirty metres under fire. Nothing about the melee build
   improves until a walking Assembly can hold a heading.
2. **An energised edge resolves on one tick in fifteen**, because the blade drifts
   in and out of overlap and a walker never quite stands still. Whether that is
   correct — a beam that flickers as two machines grind together — or a §15.3 gap
   worth closing with a wider capsule is not settled. Doc 07 §15.5 records the
   number either way, and anything balancing `sustained_damage_s` against a
   duration has to know it.
3. **Two arms are 1434 kg and the walker stoops 29.6° under them.** The wheeled
   version of this recipe used an Energy Cell in the tail as ballast; the
   ambulatory chassis has three mounts spare and doc 01 §7.1 will not let the arms
   move elsewhere. Candidates: a lighter Appendage tier, a shorter blade, or a
   chassis authored with the mounts for a counterweight. All data, none measured.
4. **A held module is the first thing a round meets.** Measured on the wheeled
   version before the rule moved it: the arm and edge were destroyed at t=37. It
   is no longer what kills this build — the walker dies with its arms intact,
   because it never brings them anywhere — but it is still true and still argues
   for armour in front of the arms.

The other thing this turned up: **`CombatArena` builds no `DotScheduler`**, so no
engagement in the suite can set anything on fire. Doc 08 §7.3 is exercised only by
`test_held_weapon`, which builds its own. Adding one to the arena is four lines
and would move every engagement measurement in the suite at once, so it wants a
session that expects to re-measure.

### 3.9 The rest of document 10

Comparable in size to what document 09 cost, in dependency order: the CSG bake
(§3.1–§3.2), fragment decomposition (§3.3), support graph and collapse (§3.5, §5),
runtime slicing (§6), fragment bodies (§7), and the `StructureArchetype`
generator. `ManifoldChecker` — the gate that makes DCC authoring survivable — is
built and tested. Worth knowing first: a Voronoi cell is an intersection of
half-spaces, so for a *convex* Section this is repeated plane slicing and needs no
CSG at all.

### 3.10 Design note — an ambulatory faction that eats wreckage

Recorded rather than queued, because it is a direction and not a task.

Make walking Assemblies a **separate faction** with their own build rules —
Crossout's Ravagers as the reference — rather than one more locomotion family
bolted onto the same hull, and let them **absorb nearby wreckage** as armour or as
a weapon. Three things already point that way:

- **The parts are there to absorb.** Doc 04 §6 turns a severed island into a
  `DebrisBodyRef` that keeps its authored colliders and its `PartInstanceState`.
  An absorbed part is a `PlacementValidator` commit against the absorber's
  `BuildContext`, not a new kind of object.
- **Absorption is a structural event**, which is the shape Invariant I-4 wants: an
  attach, a mass recompute, and a graph edge.
- **The family's open defect is faction-shaped.** §3.1.3 is "a walker is not a car
  with legs", and a faction that never shares a chassis with a wheeled build is
  free to answer it in doc 05 §13 without regard for §7.6.

Before it is a task it needs: a decision in doc 06 about whether an archetype can
be faction-locked, a rule in doc 02 for where an absorbed part may land (the
lattice is integer and a wreck is not aligned to it), and a cap under I-12.

### 3.11 Smaller, and worth doing when passing

- **A wheeled build is 3.00 m wide over a 2.00 m body, and the lattice cannot
  express a wheel arch.** A hub mounts inboard of a flank and its contact hangs
  outboard, so every wheeled Assembly is `hull_width + 2 × tyre_width` across. The
  reference road car is 0.42 of its length in width and the shipped one is 0.60.
  Closing it needs one of: an occupancy that can carry a hole, so a contact can
  sit inside the hull's envelope; a station that mounts through the hull's
  *underside* and reaches outboard; or a hull authored narrow with the body
  filled out by Structural Components either side of the contacts. The third is
  buildable today and is the only one that needs no new architecture — it is a
  blueprint, not a part.

- **The greybox now reads, and the next stage is articulation.** Doc 13 §2.1's
  family proxies ship: a rotor is a mast, a hub and its authored blades out to
  `disc_radius_m`; a limb is hip, thigh, shin and foot; a track is two runs and
  its authored road wheels; a module is a breech and a barrel to its muzzle. What
  is still missing is **movement within a part** — a limb is drawn as a leg and
  swings as one rigid piece, because doc 05 §13.1 leaves the inverse-kinematics
  chain unspecified. A two-segment IK knee under `VisualRoot` is the next thing
  worth doing and needs no invariant change: I-3 is about physics bodies and a
  visual chain is not one.
- **§14.4's damage flash saturates and stays saturated.** `FLASH_ALPHA_PER_PACKET`
  is 0.06 against a `FLASH_ALPHA_MAX` of 0.34 and the decay is proportional at
  4.5 Hz, so any module firing faster than about ten rounds a second pins it — and
  the shipped autocannon does. The capture shows a 34% `DANGER` wash over the
  entire viewport for the whole engagement: the sky, the ground and the player's
  own build all change colour, which is a state readout drawn as an atmosphere.
  Three candidates and the first is probably right: **an edge vignette rather than
  a full-rect fill**, so the periphery reddens and the world does not; a decay
  that outruns the shipped cadence; or a per-hit pulse with no accumulator, which
  loses the "how hard am I being hit" reading the accumulator is there for. Doc 11
  §14.4 owns the constants and the shape.
- **A destroyed part leaves no visible trace.** `release_part` takes its collider
  and mesh out the moment it dies, which is half of doc 08 §9.
  `VisualDamageController` is the other half and is unwritten — and it now has a
  second thing worth drawing: §9's table gives `FLAG_OVERHEATED` a heat shimmer,
  and as of this session that flag means a part is on fire for about ten seconds
  rather than meaning nothing at all.
- **Steering could be speed-sensitive.** Full lock at 9 m/s asks for a 4.8 m
  radius, which needs 1.7 g; the contacts make 0.78, so the corner washes out to
  2.5× the geometric radius. That is correct physics and it is also why fast
  cornering feels vague. Tapering the authored lock with speed is the standard
  answer and doc 05 §7.1 has no term for it. `balance-review`.
- **Doc 05 §15.7.5's ladder step is under one hull length.** 4.5 m against a
  reference build measuring 4.8 m nose to tail. The document says so and the
  constant is knowingly left alone — it moves every engagement measurement at
  once.
- **A second steered wheeled row**, and **a second tier of the rotor family**.
  Both make doc 01 §14 rule 13 non-vacuous. `mot.rotor.main_single.t3` is worth
  authoring for its failure mode alone: `torque_reaction_ratio = 1.0` and no yaw
  authority, so a build carrying one alone spins under its own reaction torque.
- **Rescale §10.5's four legacy direct-fire rows, or decide not to.** 1450 N·s for
  a 30 mm round is about 3.6× real momentum and `eff.ballistic.repeater_12.t2` is
  authored at a realistic 26, so the table is on two bases. `balance-review`.
- **Widen the authored depression, or decide not to.** 8° is a turret ring on flat
  ground and nothing here is on flat ground for long. Measured, reverted, recorded
  in doc 01 §10.5.
- **Ruts have never been seen.** Everything is implemented and tested, but the
  arena's baseline surface is `COMPACTED`, which is not ruttable. The slope rule
  produces `LOOSE` on the hillsides, so this may already work. **Go and look
  before changing anything.**
- **`tests/generation/` is empty** and `test_constant_ownership` is not written.
- **CLAUDE.md §8's prohibited terms are enforced in `src/` and nowhere else.**
  `tests/` has drifted — `_build_walker`, `GUN_KEY`, `_guns_a`. Either
  `test_no_forbidden_patterns` should scan `tests/` too or §8 should say it does
  not; right now the rule is binding and unenforced.

---

## 4. Known gaps — deliberate, not oversights

Things missing on purpose, or understood and not yet worth fixing. The long
reasoning for each lives at its constant or in the owning document; what is here
is enough to recognise one and not be surprised.

### Motion
- **No stability-augmentation layer**, so a rotary Assembly needs `CombatArena._fly`
  to exist in a test at all. §3.7.
- **The ambulatory steering demand is a disturbance with a sign attached, not a
  heading authority**, and one number does two jobs. Doc 05 §13.8. §3.1.3.
- **`boost` has a producer and no consumer.** §3.4.
- **`AeroSolver` has no consumer and no `ctl.*` part is authored**, so drag,
  downforce and Control Surfaces have never acted on a moving Assembly. Doc 05 §7.8's driveline
  drag is the retardation a player feels; aerodynamics is still the one that
  should scale with speed.
- **`_static_load_n` returns `rated_load_kg · g`** rather than doc 05 §6.4's
  distributed static load, and `SuspensionSolver.retune` runs per contact per tick
  rather than on mass recompute. Neither is wrong numerically — `retune` is pure
  and its inputs are constant between structural events — but §6.4 says otherwise.
- **A tracked patch is drawn at the mean of its road stations and nothing asserts
  the mean** (doc 05 §16.1). Every station on a flat slab reports the same
  distance, so the mean and the first station are one number; it closes with a
  bogie straddling a slope, which no fixture has. **Worth more since session 44**:
  `mot.tracked.long_bogie.t3` runs six stations over 5.60 m, so the difference
  between the mean and the first station is now a real distance on any relief.
- **A tracked build pitched to about 20° under a full stop** and stayed on its
  tracks. Measured on the short bogie under a 2.25 m hull; the family now runs
  5.60 m of patch under a 6.00 m hull and this has not been re-taken. Whether the
  dive is the right amount is a feel question and wants a scene either way.
- **A tracked pivot drifts a couple of metres** rather than turning about a point:
  the flanks counter-rotate correctly and their forces do not cancel exactly,
  because the two bogies sit at slightly different offsets. Also measured on the
  short bogie, and `differential_authority` went 1.00 → 0.85 with the long one.
- **A wheeled build wanders under full throttle with the aid off** on terrain.
  Deep wheelspin is unstable by construction — past the friction peak, more slip
  means less force — so once one flank hooks up before the other the Assembly yaws.
  That is what a burnout does. On a level slab it is now exactly straight.
- **Every yaw and roll authority fell by about six** when the reference build was
  rescaled, because an inertia grows as the square of the extents and a mass does
  not (fact 78). The authorities have not been re-derived against the new tensor —
  and session 44 moved it again: the road hull kept its 1800 kg, changed shape,
  and its `I_zz` went **up** by 54%.
- **Doc 05 §7.6's traction control has no reachable fixture on the shipped part
  set**, because the shipped Prime Mover cannot out-torque the contacts.
  `test_ground_assembly` supplies its own over-torqued mover and says so.

### Power
- **An Energy Cell's reserve does nothing.** `capacity_pu_s` and `recharge_pu_s`
  are authored and read by nobody; `PowerSystem` uses the sustained figures alone.
  The reserve belongs with doc 08's brownout handling, which is unwritten.
- **Nothing reads `PrimeMoverProfile.torque_curve`, `peak_angular_rpm` or
  `throttle_response_s`**, so a Prime Mover has no power band and no lag. §7.8's driveline drag is the
  first consumer of any of it and reads only `drive_torque_nm`.

### Combat
- **Only direct fire is implemented.** Doc 07 §5.3's arced solve, §5.4's guided
  ordnance, §10's AI target acquisition and §11's prediction are not written. A
  module of a kind that needs one aims correctly and declines to fire, which is
  the failure mode to prefer.
- **No engagement in the suite can set anything on fire**, because `CombatArena`
  builds no `DotScheduler`. Doc 08 §7.3 is exercised only by `test_held_weapon`,
  which builds its own. §3.8.
- **A held Effector Module is destroyed before it can be used**, against anything
  that shoots down the approach. Measured, not assumed: `test_melee_duel` loses
  the arm and the edge at t=37 from 30 m. §3.8.
- **A held edge's `energised_draw_pu` reaches nothing.** §15.5 routes its
  consequence through `FLAG_POWER_STARVED`, which nothing in `src/` sets, so
  wiring the draw today would move a HUD number and change no behaviour. It goes
  in with doc 08's brownout handling.
- **A held edge resolves on only about a third of the ticks it is energised**,
  because the blade drifts in and out of overlap as two hulls grind together.
  Recorded in doc 07 §15.5 and unresolved as a question: correct, or a §15.3 gap.
- **Only five shipped parts can catch fire.** Damage and heat come off the same
  raw amount, so ignition needs ~540 points of thermal damage survived first
  (fact 99). Arithmetic rather than a defect, and a part table that wanted a
  burning wheel would raise that part's thermal resistance.
- **A part below the ignition point never cools**, because doc 08 §7.1's cooling
  rides on the fire. A part that has been warmed and left alone is closer to
  catching next time, which is the more interesting reading and is recorded as
  the chosen one.
- **`VisualDamageController` is not written** and neither is doc 08 §10's repair
  path. Repair is the more interesting of the two: it must route through
  `DamageResolver` so a band transition upward fires the same signal as one
  downward.
- **A melee strike can never ricochet**, because its packet's normal is derived
  from its own direction — the query reports no surface normal.
- **Nothing in `src/combat/` knows what a team is.** §3.5.
- **A destroyed Assembly is never removed and never respawns.** Doc 11 §16.2
  decides the wreck stays, which is right; what is missing is a `SpawnDirector`,
  so a match is over the moment the player's Core Module goes.
- **`killer_id` arrives on `assembly_terminated` and nothing reads it.** Doc 04
  §8.2's second consumer — scoring — is unwritten.
- **Attitude is measured in roll and pitch only.** A hull spinning on the spot is
  upright in both, and nothing samples attitude on a *wreck* after termination.
- **Doc 02 §7.6's muzzle-offset half-cell discrepancy is unresolved** and flagged
  rather than silently fixed.
- **§12.3's self-immunity window is inert in both directions**, because no shipped
  recipe mounts a module whose muzzle overhangs its own hull. Carried, not tested.
  `CombatArena.Recipe.MELEE` finally mounts one that does — the blade reaches 5.1 m
  forward of the body origin — but doc 07 §15's sweep excludes the wielder's own
  body outright rather than through §12.3's window, so it does not reach the rule.

### The lattice and the garage
- **A controller cannot place a part.** §3.2.
- **Doc 11 §9.1's confirmation does not highlight what it is about to take.** It
  names the count, which is the half a player acts on. `GaragePreview.highlight_slot`
  exists for the hover wash; what the dialog needs is that wash in `danger` over a
  *set* of slots.
- **Doc 02 §10's mirror ghost previews against the build as it stands**, not as it
  will be once the primary commits, so a mirrored placement whose legality depends
  on its own other half shows red and commits green. The honest fix is a
  `BuildContext` that can speculate, and nothing else wants one.
- **Removal is not mirrored, deliberately.** Doc 02 §10.2: §9.2's cascade already
  takes parts the player did not point at.
- **The confirmation counts dependents and the status strip counts the cascade**,
  and the two differ whenever an orphan finds another parent. Doc 02 §9.2.
- **Doc 02 §9.3's `REPAINT` and `REORIENT` kinds do not exist**, because no
  operation produces them.
- **The compact tier has no bottom sheet.** Below 900 logical units wide the
  garage hides its docks and a player is left with a toolbar and a 3D view. A
  phone cannot build.
- **`PartIconCache`, `TierPalette`, `Inventory` and `PartTooltipBuilder` do not
  exist**, and doc 11 §5.3 binds all four. The card shows the greybox class tint.
- **`GarageLayoutController` and `touch_placement_controller.gd` are not written.**
  `GarageScreen` applies the breakpoint itself.
- **Doc 02 §7.5's ground-clearance check has never rejected anything.**

### The graph and strain
- **`update_dynamic_factor` has a caller and a moving body**, but nothing asserts
  the factor it produces. `recompute_strain` and `evaluate_strain` are waiting on
  a recoil discharge and an impact deposit.
- **Strain is attributed to the primary-tree edge only.** A wide panel bridged
  across two spars loads only the one doc 04 §3.2 picked.

### Testing and scenes
- **`run_all_checks.gd` tolerates a runtime error on its own**; the shell wrapper
  catches it (fact 34). Worth knowing before running the `.gd` directly.
- **Nothing verifies that a click actually places a part.** Doc 02 §6's integer
  half is covered by `test_cursor_to_cell`; the float half — a camera in a
  `SubViewport` projecting a ray — cannot be reached headless (fact 28).
- **The orbit camera at the conclusion ends up inside the wreck.** Fact 56 is the
  mechanism; what doc 11 §16.2 never settled is where the camera stands when the
  thing it is orbiting is directly under it.
- **Nothing verifies the confirmation dialog's own presentation** — legibility,
  sizing, keyboard dismissal. That is capture work.
- **Four files assert a defect as it stands, and each says so at the constant.**
  `test_ambulatory_drift` (the walking family's yaw drift and its two steering
  demands landing within five degrees of each other), `test_braking_and_reverse`
  (that the same family cannot reverse and brakes at half strength),
  `test_ground_assembly` (that §7.6's yaw loop leaves more spin than no aid at
  all — see §3.1.4, which now disputes the generality of it), and
  `test_team_engagement`'s five-a-side running to its timeout. Each goes red when
  the thing it records is repaired, and the fix is to re-measure and re-assert,
  never to loosen.

  **`test_rest_stability` came off that list in session 38 and is the precedent.**
  It was written asserted-as-it-failed against §7.4's limit cycle, the section
  said closing the defect would turn it red, and that is what happened; it now
  carries the before/after table rather than the complaint.
  `test_recoil_geometry`'s traversed-yaw claim inverted in the same session and
  was re-framed rather than deleted. Where a **tick count** was the thing
  asserted it was deleted rather than moved — a tick count in a multi-Assembly
  file measures the suite and not the fight (fact 54).
