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

The wheeled family goes straight (zero lateral deviation over 29 m of full
throttle), corners (32° of lock holds 0.81 rad/s within 0.018, at 1.15× the
geometric radius), stops, parks, reverses, coasts to a halt in six seconds, and
tops out at **22.6 m/s** against the 24 the garage publishes.
`tests/physics/test_wheeled_drive_cycle.gd` runs that whole cycle every suite run
and `CHANGE_LOG.md` §1 has how each of those was won.

**This session: the first match waits for you, and the edge went to a fight.**

- **An opponent holds its fire while a first-time player reads the controls.**
  Doc 05 §15.7.4 gains a third gate, `AiDriver.hold_fire`, written once a tick by
  the match layer from doc 11 §14.6's card. The capture that verified the
  first-run card also showed what it cost: the opponent arrives at four seconds
  into an eleven-second dwell, so a player who did what the card is for was at
  63% integrity with a component gone. The hold is on the **trigger** and not the
  approach, and it ends the moment the player drives, steers or fires — so in
  practice it lasts exactly as long as they want it to. A card the player *asked
  for* is deliberately not a briefing, or `hud_toggle_stats` would be a key that
  switches the opposition off.
- **The energy edge has been in an engagement.** `CombatArena` gains a `MELEE`
  recipe — the wheeled layout with an Appendage on the front face, the edge in its
  hand, and an Energy Cell in the tail that is ballast rather than supply — and
  `tests/physics/test_melee_duel.gd` fights it twice. Against an unarmed opponent
  at 12 m it closes to **6.5 m** and holds: **372 energised ticks off one swing**,
  resolving on **121** of them for 323 THERMAL, and the range never re-opens.
  That closes `sustained-delivers-impulse`, a fault recorded as a survivor since
  session 42 — a frozen target absorbs sixty impulses a second and reports
  nothing.

**The bad news about the edge, plainly.** Two things.

**It cannot get to the fight.** At 30 m against a build carrying the shipped
autocannon, the melee build loses its Effector Module *and* the Appendage holding
it at **t=37** — six tenths of a second, at better than two thirds of the starting
range — and spends the remaining four seconds driving at somebody unarmed. A held
module sits three metres in front of the hull that carries it, so it is the first
thing a round meets and has none of the hull behind it. That is a build rule, not
a balance number: doc 01 §10.5's figures are not the lever.

**And "energised" is not "cutting".** The edge resolved on 121 of the 372 ticks it
was held, because the blade drifts in and out of overlap as both hulls shove each
other. Anything sizing a sustained module against a duration over-states it by
three.

**99 files, 7712 checks, 0 failures.** `briefing_and_edge_sweep.py` plants six
faults and catches five; the survivor is the four lines of `MatchScreen` joining
the card to the gate, recorded in `CHANGE_LOG.md` §3 with what would close it.

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

**99 files, 7712 checks, 0 failures**, in about 300 seconds — 14 s of reimport and
the rest suite. Three files are most of it: `integration/test_screen_flow.gd` at
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
same change as anything that moves the count. A sweep costs about a minute a
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

Captured with `LEARNED_FACTS.md` §1 fact 55's route at 1600×900 through
`--main-scene res://scenes/match/arena_basin.tscn`. The player is not driven,
which is the case that used to get run over.

**The tutorial is no longer an ambush, and the capture is an A/B.** Two runs of
the identical route, one with `user://settings.cfg` deleted and one without,
compared at the same frame — **frame 420, seven seconds in**:

| | fresh install | returning player |
|---|---|---|
| Control card | up, seven rows | down |
| Integrity | **100%** | **52%** |
| Parts | 12 / 12 | **10 / 12** |
| Event feed | empty | "Component 2 lost", "Component 3 lost" |

The opponent is in both frames and is shooting in one of them. That is the rule
working end to end, and last session's finding — 63% with a component gone at six
seconds, on the frame that was supposed to be teaching — is closed.

**What the same capture found instead: under sustained fire the screen turns
brown.** §14.4's damage flash is a full-rect `ColorRect` that accumulates
`FLASH_ALPHA_PER_PACKET = 0.06` per packet against a `FLASH_ALPHA_MAX` of 0.34
and decays proportionally at 4.5 Hz, so an autocannon firing continuously pins it
at the ceiling and holds it there. A 34% `DANGER` wash over the whole viewport is
not a flash; it recolours the sky, the ground and the player's own build for as
long as the fight lasts, and it is the difference between the two captures'
palettes. §3.11.

**A first-time player survives, can stop, park, reverse, and turn.** All four of
the questions a person asks in the first thirty seconds have answers, and the
build finishes the capture upright.

Ranked by what would most improve a first-time player's experience:

1. **The fight is two parked hulls trading fire.** The opponent arrives at about
   four seconds — but §15.7.4 gates firing on "inside its stand-off **and
   stopped**", so once it arrives neither machine moves again. The gate exists
   because firing on the move yaws the hull off its own target, which is
   measured; making the engagement dynamic means giving a driver lateral movement
   at its stand-off and re-deriving that gate. §3.1.4.
2. **The tracked family is broken and nothing had ever turned one.** It rides
   8.1° nose-up with its two forward road stations carrying no load, spikes a
   single station to 35 kN as it bottoms out, inverts in a sustained turn, and
   yaws 0.03 rad/s at full lock. It is also the constraint that stops the drive
   torque going up for everyone else. §3.1.2.
3. **The two new chassis are still unreachable in practice.** A Core Module's
   card *says* what it carries, which was half of it; the other half is a starter
   blueprint that is not a wheeled hull. §3.3.
4. **A walking Assembly cannot reverse and can barely stop.** Both are §13.5's
   placement law having no sign in it, and so is its steering. §3.1.3.
5. **A melee build cannot survive its own approach.** New this session and now
   measured rather than guessed: at 30 m the arm and the blade are gone at t=37.
   The edge itself works — it closes, holds contact, and cuts — so this is a
   build-and-encounter problem rather than a weapon one. §3.8.
6. **Sustained fire turns the whole screen brown.** New this session and found by
   looking rather than by testing: §14.4's damage flash saturates and stays
   saturated. Cheap, and it is the only thing in this list a player meets in
   their first ten seconds. §3.11.
7. **The end card is drawn over nothing.** Unchanged. The orbit camera swings to
   an empty field and the card floats on it.
8. **One arena, and one opponent recipe beyond the mirror.** Doc 06's generator
   is the answer.
9. **Nothing rewards a good build over a heavy one.** Unchanged.
10. **Nothing in `src/combat/` knows what a team is.** §3.5.
11. **A rotary Assembly has a brake and still no way to hold a hover.** §3.7.

**The bad news, plainly.** Four things.

**The engagement has no shape.** Two machines drive at each other, stop, and
shoot until one stops existing. There is no manoeuvre in it, and the reason is a
fire gate that is correct on its own terms — a hull firing on the move loses its
own aim — so this is a design problem rather than a defect. Item 1. It is now the
top item with nothing cheap above it, which is the first time that has been true.

**The edge is reachable from a fixture and still not from the game.** Session 42
landed two laws nothing could reach; this session built the recipe that reaches
them and it lives in `tests/`. A player still cannot arm an Appendage from the
garage, because no starter blueprint carries one and the catalogue is the only
other route. Closing that is §3.3's blueprint work, not §3.8's.

**A tracked build is a trap for a player who makes one.** Item 2, unchanged. It
is the only family whose problems are not documented as a family problem.

**Four of thirteen documents describe software that does not exist.** `src/net/`
holds one file against doc 12's whole authority matrix, prediction and snapshot
format; `src/vfx/fusion/`, `src/world/volumes/` and `src/assembly/autobuild/` are
empty against docs 03, 10 and 06. That is not drift — it is deliberate, and it is
recorded in §4 — but it means a third of the architecture has never been tested
against reality.

The summary: **the machine is sound and the interface around it is honest — it
drives, it says which parts fit which chassis, it stops teaching a returning
player their own controls, and it no longer shoots a first-time player who is
reading the manual — but the fight still has no manoeuvre in it, the newest
weapon cannot be built by a player, and a third of the architecture is still on
paper.**

## 3. The work queue

Ordered by what is worth doing next, not by dependency. Anything not here is
either done or is in section 4.

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

#### 3.1.2 The tracked family, and the experiment that ruled out the obvious fix

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
`CombatArena.Recipe.MELEE`'s layout is authored, validated and fought
(§3.8) — the Appendage at `(24, 5, 17)` on the Core Module's `-Z` face, the edge
at `(24, 5, 11)` in its hand — so a `StarterBlueprint.melee()` is that cell list
and nothing else. It is the only route by which a player ever holds the weapon
sessions 18, 42 and 43 built, and until it exists the honest statement is that the
edge is not in the game.

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

What is left is what the fixture found, and both are open questions rather than
tasks with an obvious shape:

1. **A held module is the first thing a round meets.** At 30 m the arm and the
   edge are both destroyed at t=37. The candidate answers, in rough order of
   honesty: armour authored in front of the arm (a Structural Component on the
   `-Z` face, which the layout has room for), an encounter where both sides have
   to close, or an Appendage tier with the integrity to survive an approach. All
   three are design decisions and none is measured.
2. **An energised edge resolves on a third of the ticks it is held**, because the
   blade drifts in and out of overlap as both hulls shove each other. Whether
   that is correct — a beam that flickers as two machines grind together — or a
   §15.3 gap worth closing with a wider capsule is not settled. Doc 07 §15.5
   records the number either way, and anything balancing `sustained_damage_s`
   against a duration has to know it.

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
  bogie straddling a slope, which no fixture has.
- **A tracked build pitches to about 20° under a full stop** and stays on its
  tracks. §7.7's proportioning is what makes that true. Whether 20° is the right
  amount of dive is a feel question and wants a scene.
- **A tracked pivot drifts a couple of metres** rather than turning about a point:
  the flanks counter-rotate correctly and their forces do not cancel exactly,
  because the two bogies sit at slightly different offsets.
- **A wheeled build wanders under full throttle with the aid off** on terrain.
  Deep wheelspin is unstable by construction — past the friction peak, more slip
  means less force — so once one flank hooks up before the other the Assembly yaws.
  That is what a burnout does. On a level slab it is now exactly straight.
- **Every yaw and roll authority fell by about six** when the reference build was
  rescaled, because an inertia grows as the square of the extents and a mass does
  not (fact 78). The authorities have not been re-derived against the new tensor.
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
