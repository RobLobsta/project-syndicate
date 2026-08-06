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

These three files were one `HANDOFF.md` until session 24, and comments in `src/`,
`tests/` and `tools/` still cite its sections. **The mapping lives in
`LEARNED_FACTS.md` §0 and only there** — it was copied into all three files and
three copies of a lookup table is three things to keep true.

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
| 43 | **The first match waits for you, and the edge finally goes to a fight.** Doc 05 §15.7.4 gains a third gate — `AiDriver.hold_fire`, written by the match layer — so an opponent holds its fire while doc 11 §14.6's first-run card is up; a player reading it was taking a third of their machine doing so. A card the player *asked for* is deliberately not a briefing, or `hud_toggle_stats` would be a key that switches the opposition off. `CombatArena` gains a **`MELEE` recipe** and `tests/physics/test_melee_duel.gd` puts doc 07 §15 in an engagement for the first time: it closes to **6.5 m**, holds contact for **372 energised ticks off one swing**, resolves on 121 of them, and **the range never re-opens** — which closes `sustained-delivers-impulse`, a fault recorded as a survivor since session 42. Two findings: an energised edge resolves on only a third of the ticks it is held, and a held module sits three metres in front of the hull, so at 30 m against a gunner the arm and the blade are both gone by **t=37**. |
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
| 30 | **You can drive and shoot.** Doc 01 §10.5 gains `eff.ballistic.repeater_12.t2` — 26 N·s against the autocannon's 1450, at twice the cadence for two thirds of the throughput and half the penetration — and the shipped starter carries it. Measured: 2.9° of heading drift against 99.1° over the same throttled, traversed, trigger-held window. The autocannon build also stops being able to fire at all, because its own recoil takes the mount off the target. |
| 42 | **The edge burns.** Doc 07 §15.5's sustained contact and doc 08 §7.3's `DotScheduler` land together: a held edge cuts on **93 consecutive ticks** at the authored 340 damage/s, deposits heat as it goes, and 3.4 s of it takes a Core Module past `THERMAL_IGNITION_HU` — after which §7.3's list burns it with nothing touching it. §7.1 gains the cooling term that makes its own hysteresis band reachable (`THERMAL_COOLING_HU_S = 18.0`, charged to the burning part). Also: a Core Module's card now names the families its chassis carries (doc 11 §4.3), and §14.6's control card is a **first-run** card. Two findings on the way: catching fire has an integrity floor that twelve of seventeen shipped parts are under, and a discrete thermal packet is worth a full second of heat, so two swings ignite a hull on their own. |
| 41 | **Documents say whether they are built; the throttle stops braking; tracked gets a chassis that does not fix it.** Every one of the thirteen carries a generated **BUILT / PARTIAL / PLANNED** banner checked against a witness path in `src/`, so a reader can tell doc 09 from doc 10 without opening `src/`. §7.8's driveline drag is capped at the drive it opposes, so **no positive throttle ever retards** — the first sliver releases engine braking instead. CLAUDE.md gains rule 14: a normative formula producing a vector must state its direction, which is the rule §6.5's inverted anti-roll couple broke for the life of the project. `CHASSIS_GROUND` splits into `CHASSIS_WHEELED` and `CHASSIS_TRACKED` and `core.tracked.hauler.t3` ships — and the shipped recipe stays on the command core, because migrating it takes the rest pitch from 4.7° to 1.6° and *loses* the ability to brake without going over. The Ground Array doubles to **4096 m**. |
| 40 | **The bad news, closed.** Doc 05 gains **§7.8**: a driveline drag that takes a released Assembly from 0.14 m/s² of rolling resistance to **2.19**, and a speed-cap governor that makes `speed_cap_mps` a speed the build reaches and holds (**22.56 m/s** against a published 24, where it used to sail through to 25). Doc 11 §7.3's **pad placement** lands as one substitution — `_preview_pointer()` returns a virtual cursor when a pad is in use — so a controller builds through the identical chain a mouse does; `test_pad_build.gd` places a part from the stick alone. The opponent spawn came in to 30 m, so the fight starts at four seconds rather than eleven. And `drive_torque_nm` was **re-measured and left alone**: the wheeled build tolerates 16 000 N·m, and the binding constraint turned out to be the tracked recipe, which rides 8.1° nose-up on two of its eight road stations, spikes one to 35 kN, inverts in a turn, and barely steers. |
| 39 | **The machine handles.** Doc 05 §6.5's anti-roll couple had been applied inverted for the life of the project — a roll *amplifier*, so any disturbance diverged and the reference build went from −1.1° to inverted in a second and a half at full lock from **3.3 m/s**. Corrected, the same manoeuvre settles at −1.3° with all four contacts loaded, and it is what has been putting parked hulls on their sides in every capture since session 31. `tests/physics/test_wheeled_drive_cycle.gd` runs the whole cycle a person performs on a smooth slab and is the first fixture in the project to turn an Assembly at speed. Also: §7.7's holding brake read the raw record while §15.5 had already released the demand, so holding the brake was **strictly worse than holding nothing** (10.49 m of recoil travel against 1.15). And doc 11 §7.1's binding table published three gamepad collisions inside the match; it is rebuilt per context, enforced by `test_input_actions`, given PlayStation/Nintendo/generic glyphs, and the garage camera now orbits on the right stick. |
| 38 | **The contact integrator is closed, and everything downstream of it came back.** Doc 05 §7.4 stepped through the slip velocity with a chord-implicit factor and an under-relaxed stick cap: a parked build goes from 0.196 m/s and 1.307 m of wander to **0.000 and 0.000**, and its contacts from seven sign reversals in twelve ticks to none. On top of it, §7.7's holding brake and brake proportioning, §15.5's brake release, §12.8's rotary arrest, §13.9's ambulatory stop, and §15.7.4's second gate — an `AiDriver` now fires from a **stop**. Three defects fell out on the way: the contact frame was never projected into the contact plane (a nose-down hull's "longitudinal" friction pitched it further, and a tracked build somersaulted), a tracked bogie credited each of its four road stations with the whole part's inertia, and §7.6's yaw loop was locking the flank it was biasing. The match drives a **mirror of the player's build** at sixty metres. |
| 37 | **A limb and a rotor disc each have a chassis, and the test drive is a duel.** Doc 01 §7.1 gives `CoreModuleProfile` a `locomotion_mask` and the validator a `MOTIVE_FAMILY_MISMATCH`; `core.ambulatory.strider.t3` and `core.rotary.lifter.t3` join §10.1. The walking recipe stops borrowing a hull whose every published figure describes a machine that stands on the ground — and gains the mounts for an Energy Cell it could not fit. `MatchScreen` spawns one opponent instead of three, with the same store the player carries. Capture: the player is alive at ten seconds at 54% where it was destroyed before nine. |
| 29 | **The wheels touch the ground.** Doc 05 §16: a Motive Assembly's mesh is drawn where its contact is, not at the cell it was placed in — so suspension travel is visible, a wheel over a crest extends instead of hanging in the air, and a walking limb points at its foot along §13.7's swing arc. Twelve planted faults, one survived by design. The capture that verified it found the player flipped onto its back and destroyed in seven seconds while standing still. |
| 36 | **The rebuild lands, and the AI regression was never the AI.** The part table, both layouts and all four locomotion recipes transcribed; the reference build is **3630 kg at 132 kg/m³ on a 3.00 m wheelbase, standing on all four contacts at a 48/52 split**. One instrumented run of `AiDriver` found it: throttle 1.00 and a target held the whole time, while the hull climbed off the ground contact by contact under sustained full throttle. Doc 05 §7.4's unstable contact integration, energised by drive torque — so `drive_torque_nm` is capped at 6400 N·m until §7.4 is closed. Also: an inertia grows as the square of the extents, so every yaw and roll authority in the project fell by a factor of six. |
| 35 | **The rebuild, 89% landed.** Fixture fallout taken from **448 failing assertions across 28 files to 50 across 11**: the part table, both layouts, all four locomotion recipes, and the published-value assertions are all solved and written down. Reverted one regression short — the AI turns to face its target and then declines to close. |
| 34 | **The Crossout-scale rebuild, executed and measured, then reverted.** The reference build goes from 1107 kg at 46 kg/m³ standing on two of its four wheels to **3630 kg at 141 kg/m³ standing on all four**, with the wheelbase from 35% to 73% of the hull and the static split from 100% front to 41%. The registry validates and the proportions instrument confirms it. Reverted because the fixture fallout is 396 assertions across 28 files; `HANDOFF.md` §3.1.2 carries every number that produced the measurement. |
| 33 | **Three queue items, and the middle one beaten twice.** The control card leaves the middle of the screen and stands down on the player's first input (doc 11 §14.6). `release_part` is finally called, so a destroyed part's collider and mesh leave with it — which took doc 07 §12.2's penetration budget off corpses and turned the ambulatory mirror from an eight-session stalemate into a decision in 221 of 900 ticks. §7.4's integrator was rebuilt with both traps solved and reverted again: the shipped Assembly stands on two of its four wheels, and on that stance a correct integrator looks like a broken one. |
| 32 | **The wreck stays where it fell, and the reason a parked build never stops is now known.** Doc 05 §3.7: a body with no live parts is frozen rather than left as a one-kilogramme hull-sized collider anything can punt. Measured 2.80 m of hulk travel before, 0.00 m after. Then the physics assessment that came with it: §7.4's contact integration is **142× outside its own stability limit**, the contact reverses on ten of twelve ticks under a build standing still, and the repair was built, measured, and reverted because it moves every wheeled number in the project. `test_rest_stability` measures the defect and is asserted as it fails. |
| 31 | **You are not driven over any more.** Doc 05 §15.7.1 gains an arrival brake and a stand-off measured against the hulls rather than guessed at. The instrument came first: `worst_roll_deg` on `CombatArena.Combatant`, which is the first attitude any engagement fixture has ever recorded. Target roll on a stationary build under three converging drivers: **146.2° before, 0.3° after.** Found on the way: a stand-off shorter than the two hulls it separates, and a parked Assembly that never stops rolling. |

### Session 43, in more detail

**The briefing hold.** Doc 11 §14.6's card was raised once, on a player's first
match, and session 42's own capture showed what that bought: the opponent arrives
at four seconds into an eleven-second dwell, so at six seconds the player is at
63% integrity with a component gone, stationary, still reading. `AiDriver` gains
`hold_fire`; `MatchScreen` writes it onto every driver once a tick from
`MatchHud.briefing_is_up()`. It holds the **trigger** and not the approach — an
opponent that crosses the basin and waits reads as an opponent, and one that sits
at its spawn reads as a match that has not started.

`ControlCard.raise_first_run()` and `raise()` present identically and differ in
one flag, because a hold keyed on "the card is visible" is eleven seconds of an
opponent that will not shoot back, on demand, for as long as a player cares to
hold `hud_toggle_stats`.

**The edge in a fight.** `CombatArena.Recipe.MELEE` is the wheeled layout with
`apx.arm.manipulator.t3` on the Core Module's `-Z` face and
`eff.melee.beam_edge.t4` in its hand, plus an Energy Cell in the tail that is
**ballast rather than supply** — the arm and the blade are 717 kg on the front of a
build fact 74 already calls nose-heavy. `tests/physics/test_melee_duel.gd` runs
two phases against one arena each:

| | contact (12 m, unarmed target) | duel (30 m, armed) |
|---|---|---|
| Closed to | 6.5 m | 22.4 m |
| Swings started | 1 | 1 |
| Energised ticks | 372 | 0 |
| Ticks that resolved | 121 | 0 |
| THERMAL delivered | 323 | 0 |
| Range re-opened after first cut | 0.03 m | — |
| Outcome | held to the window | Effector Module and Appendage gone at **t=37**, destroyed at t=297 |

Three things came out of it. **Contact is held** — 121 resolves off one swing is
§15.5 and nothing else, since a discrete swing costs 58 ticks. **An energised edge
is not a resolving edge**: it cut on a third of the ticks it was held, because the
blade drifts in and out of overlap as both hulls shove each other, so anything
sizing a sustained module against a duration has to count resolves. And **a held
module is the first thing a round meets**, which is a build rule rather than a
balance number: doc 01 §10.5's figures are not the lever, armour in front of the
arm or an opponent that also has to close is.

**A recorded survivor closed.** `sustained-delivers-impulse` — §15.4's per-swing
impulse applied on every tick — survived `burn_and_hold_sweep.py` because
`test_held_weapon` freezes its target. It is caught here, but *not* by the
assertion that was tempting: the target's peak speed is 2.76 m/s correct against
7.68 faulted, which is inside the noise of a two-Assembly fight, because a melee
build rams. What separates them cleanly is whether contact, once made, is ever
lost: **0.03 m of re-opening against 5.15**.

**Also:** `OrientationTable.first_carrying` — two fixtures needed to hang an arm
off a hull and the answer is a property of the group; `CombatArena.tick_once` and
`stand_down`, so a fixture whose subject is a per-tick law can sample between
physics frames without restarting the timeline's clock; and `PART_CLASS_NAMES`
gained its Appendage row, which was reading "a part" in every timeline.

### Session 42, in more detail

**Neither half of the energy edge was worth anything alone.** `eff.melee.beam_edge.t4`
has authored `sustained = true` and `sustained_damage_s = 340` since session 18;
`MeleeSolver.sustained_channel_damage` was written and unit-tested with no caller,
and `FLAG_OVERHEATED` was set by the resolver and read by nobody. So the edge was a
short-ranged autocannon with a thermal mix, and thermal damage was a resistance row.
The two shipped together: contact deposits heat, heat ignites, and §7.3's list is
what makes ignition mean anything.

**§15.5's rule is one line and it is not the stage machine.** Holding the stage at
the end of the arc is the visible half; the half that decides whether anything
happens is clearing `struck_this_swing` per tick rather than per swing, because
§15.3 deduplicates a target for the whole swing. Get the stage right and the
clearing wrong and the edge resolves exactly once and then nothing — which is
indistinguishable from a correct implementation to any assertion about damage
*arriving*. `test_held_weapon` counts the ticks that resolved for that reason.

**The instalment says what it covers.** `interval_s` on a sustained packet is the
tick, so doc 08 §7.1's heat is a rate rather than sixty full-second deposits a
second. And a held edge delivers **no impulse**: §15.4's is the momentum of a
blade swung through a hull, once per swing.

**§7.1's hysteresis band had no way to be reached.** The section ends a fire when
heat drops under 320 and never said what makes it drop. Cooling every part in the
match on a timer is the poll I-4 exists to forbid, so the cooling rides on the
burning part's own entry: a part that is alight sheds heat, a part that is merely
warm does not, and the band is reachable exactly where it is observable. Net of
the 2.2 HU/s the fire's own packets deposit, an ignited part burns for about ten
seconds and forty points of integrity.

**Two findings, both arithmetic and both recorded in doc 08 §7.1.** Damage and
heat come off the same `raw_amount`, so a part must survive ~540 points of thermal
damage before it can ignite at all — five of seventeen shipped parts clear that
bar. And a packet with no interval is read as a full second's deposit, so **two
strikes of the shipped edge ignite a Core Module** with no contact at all. Fact 99.

**The fixture reported the law as broken and was wrong.** The sustained phase read
"resolved on 1 of the 1 ticks it was held", which is exactly what a missing
per-tick clear looks like; §15.4's impulse had shoved the target off the blade on
the first tick. The tell was the *size* of the one packet it did see — 0.29 where
contact asks for 2.64, which is a burn instalment and not a melee packet. Fact 100.

**The sweep found a third owner of a rule and deleted it.** `fire-ignites-every-packet`
survived its first run because the resolver tested "is this the transition" and
the scheduler tested "is this part already in the list" — two owners of one
invariant, so the scheduler's own de-duplication was unreachable and the fault
that removed it was caught by nothing, including the test written to assert it.
The resolver now offers **every** packet that leaves a part alight and
`DotScheduler.ignite` is the one owner. Eight of eleven faults caught; the two
kept survivors are in §3.

**And two one-line interface rules that a later change could delete unnoticed.**
A Core Module's card names what it carries, because doc 01 §7.1's family lock
shipped with the parts and no way for a player to meet it. §14.6's control card is
raised on a first run only, recorded in a `seen` section that is deliberately not
a preference. Both are planted as faults in `burn_and_hold_sweep.py`.

### Session 41, in more detail

**The status banners are generated and witnessed rather than written.**
`tools/ci/doc_index.py` renders a BUILT / PARTIAL / PLANNED line into each of the
thirteen headers from one table, and `tests/arch/test_doc_indexes.gd` checks the
claim against a source path: a PLANNED document must have *no* implementation, so
the day somebody writes `src/net/net_server.gd` the banner fails rather than
quietly becoming a lie. Four documents are PLANNED — 03, 06, 10 and 12 — and five
are PARTIAL.

**The throttle stops being a brake, and the incompatibility is real.** A
retardation that is full at zero throttle and absent at any positive one cannot be
continuous. Capping the drag at the drive it opposes puts the step where a driver
already expects one — lifting off gives engine braking, touching the pedal takes it
away — and turns the old coasting band into a dead one. Fact 96.

**The tracked split was done, measured, and deliberately not shipped.**
`core.tracked.hauler.t3` exists and validates; the shipped recipe stays on
`core.command.compact.t2` through a mask named `CHASSIS_GROUND_TRANSITIONAL`,
because migrating it improves the static stance (4.7° → 1.6° of rest pitch, 3.2× →
1.45× load spread) and makes the dynamics worse. Fact 97 has why, and the answer
is that the family needs a contact base longer than its hull — which the part set
cannot express, since `mot.tracked.short_bogie.t2` runs eight cells and two per
flank fit on no chassis in the registry.

**The world doubled and three fixtures moved with it.** 4096 m square, sparse
chunks, 134 MB of height if fully explored, 0.24 mm of float32 error at the far
corner. The trap is that the world-origin sample index moves with the span and the
noise field is sampled by index, so every fixture standing on a particular patch of
terrain stands on a different one afterwards — `test_ground_terrain` found 0.9 m of
relief at its spawn before and 0.23 after.

### Session 40, in more detail

**Two of the five bad-news items were one missing model.** Between rolling
resistance at 0.14 m/s² and §7.7's holding brake at 1.5 m/s there was nothing at
all, so releasing the controls did almost nothing; and `speed_cap_mps` reached the
ambulatory path and no other, while the garage published it as a projected top
speed. Doc 05 §7.8 is both terms, and both act through §7.2's friction solve as a
resisting torque, so neither can exceed grip.

**The obvious form of the drag is wrong and the arithmetic is one line.** Scaled
by `1 − |throttle|` the drag cancels the drive at `t = 0.26`, so a demand to
accelerate retards the Assembly. It failed the suite in three places on its first
run and none of them looked like a friction constant: a quarter throttle moved the
reference build at 0.89 m/s where it had moved it at 3.8, reverse stopped working,
and §15.7.1's `APPROACH_MIN_THROTTLE` of 0.35 left an `AiDriver` unable to turn
onto a bearing behind it. `LEARNED_FACTS.md` fact 93.

**The pad cursor is a substitution rather than a feature.** The garage was
unplayable on a controller because `_preview_pointer()` was the mouse. A lattice
cursor — the obvious design — needs its own snapping, bounds and mating rules,
which is doc 02 §6's chain written twice; a virtual pointer needs none of that and
guarantees a pad cannot place something a mouse could not. Fact 94.

**The drive torque was re-measured, and the answer was that it stays.** Both
figures that had capped it at 6400 were void — one closed in session 38, one in
39 — and the wheeled build now tolerates 16 000 N·m with 2.8° of roll and no
airborne tick. Raised to 9600 it broke the suite in three places, all tracked,
because `CombatArena.Recipe.TRACKED` shares the Prime Mover. Measuring one recipe
is not measuring the part (fact 95), and the tracked recipe turns out to be
defective on its own: 8.1° of permanent nose-up with its forward road stations
unloaded, a 35 kN spike as it bottoms out, and 0.03 rad/s of yaw at full lock.

**A second finding of the same shape as session 39's.** The anti-roll couple was
invisible because nothing turned an Assembly at speed; the tracked recipe's
attitude is invisible because nothing turns a *tracked* Assembly at all. Both are
manoeuvres with no fixture rather than fixtures that got an answer wrong.

**The suite's shape, measured rather than assumed.** 7532 checks across 95 files:
3555 unit, 2105 integration, 1210 architectural, and **539 physics across 23
files**. Every claim this project makes about how a machine behaves rests on that
last seven per cent.

### Session 39, in more detail

**The defect was found by writing the fixture nobody had written.** Four physics
files drive an Assembly — straight, braking in a line, and at a quarter throttle —
and not one of them turned it at speed. `test_wheeled_drive_cycle.gd` runs the
sequence instead of a question: accelerate from rest, brake to a stop, hold full
lock, reverse under lock, shoot, shoot with the brake held. The corner failed on
the first run, from a walking pace, with the hull inverted and all four contacts
in the air.

**Reading the contacts is what named it** (`LEARNED_FACTS.md` fact 77, again).
Every quantity describing the demand said the Assembly was cornering correctly;
the normal loads said the two inside contacts had unloaded to zero at 2.9° of
roll, and the roll then grew geometrically. That signature — a restoring term
producing a divergence — is a sign error, and `_apply_anti_roll` applied
`SuspensionSolver.anti_roll_force` downward on the more compressed side.

**Two things kept it invisible for thirty-eight sessions.** On a level slab both
sides compress equally and the term is exactly zero, so every straight-line and
braking measurement in the suite is untouched by it. And the unit test asserted
`k · r · (x_left − x_right)` exactly and correctly — the *magnitude* — while the
direction the caller applies it in was asserted nowhere. Fact 88 has the general
shape.

**Three measurements this project has been carrying are now suspect.** Anything
concluded from a *roll* before this session was measured against an amplifier.
The 9600 N·m drive-torque cap is the named casualty (`HANDOFF.md` §3.1.1); the
16000 N·m one is a pitch failure and stands.

**§7.7 and §15.5 were fighting over one key.** §15.5 releases the service demand
as the hull stops going forwards so that one key can brake and reverse; §7.7
engaged its holding brake on a record demanding "neither drive nor brake", read
straight off `input.brake`. A driver holding the brake at rest therefore had
neither — measured at 10.49 m of recoil travel against 1.15 m with the key
released. §7.7 now reads the released demand, and `ControlInput.is_coasting()`
went with it, because the question it answered can no longer be asked of the raw
record.

**The input map was wrong as published, not merely as implemented.** Doc 11 §7.1
bound the right trigger to both `veh_throttle` and `effector_fire_primary`, the
left to both `veh_brake` and `effector_fire_secondary`, and D-pad right to both
`veh_roll_right` and `cam_toggle_view` — three collisions inside one screen, in a
table whose own prose forbids exactly that. Three more were in the garage half.
`test_input_actions` now keys every gamepad event by the physical control it
occupies and compares rows within a context; the context lists are checked
against the canonical action list in both directions so an action in neither is
not silently exempt.

**One binding set really does cover PS4, Switch and 8BitDo**, because Godot's
controller database resolves all three to the same logical indices. What varies
is the marking, so `InputPrompt` grew a three-family glyph table — a Switch pad's
bottom button is printed `B` where an Xbox pad's is `A`, and the engine's own
`as_text()` answers with a forty-eight-character enumeration of all of them.

**A stick cannot be read by an event handler**, which is why the garage had no
camera control on a controller at all: `handle_camera_input` orbits on
`InputEventMouseMotion`, and a stick held over emits nothing. `GaragePreview`
polls the four analogue `cam_look_*` actions in `_process`.

**Twelve of thirteen planted faults were caught.** `drive_cycle_sweep.py`;
`garage-stick-orbit-removed` is the survivor and is honest — nothing tests the
garage camera, and closing it needs a fixture that can drive a `SubViewport`
camera, which fact 28 says is not reachable headless.

### Session 38, in more detail

**The repair is three parts and each has a wrong turn recorded against it.** Doc
05 §7.4 has the arithmetic. What is worth carrying here is the shape of the two
things that were *not* in the plan.

**A deadbeat stick cap produced a second limit cycle, one axis out.** The scheme
called for the force that lands the slip exactly on zero. That is exact only if
the mass resisting the slip is exact, and for a contact a metre below the centre
of mass it is not — part of what the force moves is the hull's rotation. The
overestimate reversed what it was correcting: the roll rate alternated between
−0.22 and +0.21 rad/s on every single tick, with the hull creeping at 0.05 m/s.
`STICK_RELAXATION = 0.5` closed it and the drift went to zero.

**A feed-forward that is wrong injects energy.** Reconstructing `ω` against the
hull's *predicted* end-of-tick speed made the held case exact and made the free
case a positive feedback loop: a parked build wound its contacts to 13 rad/s and
drove itself backwards at 4 m/s with the throttle at zero. A held contact simply
does not rotate, and saying so outright is both exact and cheaper.

**Two data changes were built, measured, and reverted**, and the measurement is
worth more than the change. Retuning the wheeled contacts from μ 1.05 to 0.78 —
so that they cannot out-grip the hull's own 0.97 g rollover threshold — stopped a
build tipping itself over on landing and cost nothing else. Raising
`drive_torque_nm` from 6400 to 16000 and then 9600 put the reference build back
in the air: at 9600 it progressively unloaded two contacts over five hundred
ticks in a sustained turn and finished on its back. **The cap on drive torque is
no longer §7.4; it is the hull's own stability.** Both are `HANDOFF.md` §3.1.1.

### Session 37, in more detail

**The chassis split is one bit test and a lot of consequence.** `locomotion_mask`
carries one bit per `LocomotionMode`; `PlacementValidator._check_motive_family`
runs between the class limits and the budgets and refuses a Motive Assembly the
committed Core Module does not declare. It is deliberately one-directional — a
Core Module is always slot 0 and always first, so a chassis cannot arrive under a
family — and the mask is a mask rather than a single family because `GROUND` and
`TRACKED` are separate solver families for the shape of their contact sets, not
because a tracked machine is built on a different hull.

Both new chassis keep the command core's 6×4 section and are shorter along `Z`
(nine cells, not thirteen). That is what made the change affordable: every mount
cell that hangs off a flank or sits on a deck is the same cell on all three, so
the arena's ambulatory and rotary layouts moved by nothing at all.

**Three of four ambulatory numbers improved and the fourth said something worse.**
`test_ambulatory_drift` on the strider chassis: uncommanded drift 140.4° → 92.2°,
countered 156.1° → 19.9°, standing 51.2° → 18.1°. But both commanded runs now
land within 4.7° of each other, from a neutral case 112° away — so a steering
demand moves the heading a long way and its *sign* accounts for almost none of
it. That is a sharper statement of doc 05 §13.8's missing heading term than the
file has ever been able to make, and §13.8 now records the measurement. The
file's assertion was re-framed rather than loosened: it asserted that the demand
could not null the drift, which stopped being true.

**A correction, verified rather than inherited.** `HANDOFF.md` had carried "a
parked Assembly drifts at 2.4 m/s" since session 32, sourced from a HUD readout
in a capture. Checked three ways this session: a twenty-one frame contact sheet
shows the speed climbing 0.9 → 2.6 m/s over four and a half seconds *at 100%
integrity*, so it is not an impact; the basin's grade at the player spawn is
1.78°; and the shipped build put on that terrain with no opponent and no input
rolls 9.4 m out and back to within 2.7 m of where it started. It is a vehicle in
neutral in a bowl with no parking brake. The real rest defect is
`test_rest_stability`'s flat-slab **0.196 m/s and 1.307 m over 360 ticks**.
`LEARNED_FACTS.md` facts 81 and 82 carry it, along with the arithmetic showing
that the same chatter costs a cornering contact 3.8× of its lateral grip — and
that doc 05 §7.6's traction control is neither the cause nor the cure, since its
limiter scales drive torque and its yaw loop is off below 1.5 m/s.

**The three-on-one test drive was never argued for.** It was what the scene
happened to be built with while nothing in it could kill anybody, and once
`src/ai/` landed it meant three copies of the player's own blueprint firing seven
rounds a second at one hull. Doc 11 §15.5 carries the three arguments for a duel;
the store asymmetry that existed to cover it went with it, so both sides now
carry 600 rounds and the only remaining handicap is the AI's aim-point offset.

### Session 36, in more detail

**The transcription was arithmetic, exactly as §3.1.2 promised.** 379 failing
assertions across 28 files on the first full run, down to zero over twelve runs,
and the three rules covered what they said they would.

**The blocker was not the AI, and one instrumented run said so in twenty lines.**
`CombatArena.engage` printed `input.throttle`, the target id, the closure term,
the hull height, the grounded contact count and the four normal forces every
fifteen ticks. The driver was faultless throughout — throttle 1.00, brake 0.00,
target held, bearing 0.4° — and the *hull* was the thing failing: body height
climbing 0.93 → 1.63 m, contacts unloading one at a time to zero, then a 32 kN
landing and a dead stop with no probe touching anything. It was not declining to
fight; it had taken off. **A driver that has a target, is pointed at it, and is
demanding full throttle is not a tactics problem — read the contacts, not the
law.**

The cause is doc 05 §7.4's known 142×-unstable contact integration, energised by
drive torque: at 10 200 N·m sustained full throttle pumps the suspension until
the Assembly leaves the ground. Measured three ways — 10 200 breaks it, 6400 does
not, 3200 is too slow to drive — so `drive_torque_nm` is **6400 N·m**, which is a
cap set by an integration defect rather than by grip and goes up when §3.1 is
closed. It costs §7.6's traction control its only reachable fixture: the shipped
Prime Mover no longer out-torques the shipped contacts, so the two aid tests
supply their own over-torqued mover through the Assembly's `PowerSystem` and
assert that they crossed the bound before asserting anything about the aid.

**Three findings the rebuild produced that nobody was looking for.**

*An inertia grows as the square of the extents, and every authority is a torque
over an inertia.* `core.command.compact.t2`'s box tensor went from 81 to
1922 kg·m² about `Y` — 24× against a mass factor of 4.7 — so yaw and roll
authority fell by about six. Three fixtures measured the same collapse from
different directions: §7.6's corrective brake takes 2% off an imposed spin where
it took 60%, the rotary autopilot could not hold a hover and tumbled during the
settle, and `eff.ballistic.autocannon_30.t3` **stopped being able to spin its own
hull** — `test_drive_and_shoot`'s two defect assertions inverted, from 99° and
two rounds of seventeen to under ten degrees and fifteen.

*A stand-off is a stopping distance plus a clearance, and both terms belong to
the build.* At three times the mass the driver arrived at its ten-metre mark
still carrying enough speed to run through it into hull contact.
`ARRIVAL_DECEL_MPS2` 4.0 → 6.0 and `GROUND_STAND_OFF_M` 10.0 → 14.0, both
re-derived rather than nudged.

*Two recipes were one cell out and it presented as a physics defect.* The
ambulatory limbs hung one cell forward of their stations, putting the four feet
about a mean of `z` 23 under a hull centred at 24 — a standing walker yawed 152°
in five seconds. Squaring them cut it to 51. And the rotary recipe put its
620 kg Prime Mover in the tail, 0.31 m behind the disc line, which asks for 23°
of a 14° swashplate cone; the Assembly went over during the settle. Prime Mover
under the belly, Energy Cell on the aft deck, and it hovers and fights.

### Session 35, in more detail

The second pass at §3.1.2, and it got most of the way. 448 → 350 → 182 → 144 →
110 → 84 → 54 → **50**, over ten full suite runs.

**Three rules covered about four hundred of the assertions**, and finding them is
what cost the time. `Vector3i(24, 7, 24)` turns out to be a shared idiom meaning
"on the Core Module's deck" across fifteen test files, so the deck moving from
y=6 to y=7 is one replacement — followed immediately by bumping everything that
was *already* stacked at y=8, because the blanket replacement collides them. The
flanks moved from x 22..25 to x 21..26, so flank mounts go from x=20/26 to
x=19/27. And published values are asserted by value throughout, so masses, cell
counts, face counts, tensors and capacities all move together.

**Two things had to be discovered rather than derived.** A station at orientation
8 spans `x[px..px+1]`, `y[py..py+1]`, `z[pz-1..pz]` — probing the orientation
table turned the ambulatory and rotary re-lay from guesswork into arithmetic and
fixed both recipes in one pass. And scaling mass without scaling the force models
breaks two families outright: the rotor could no longer lift (hover margin 0.77
against a required 1.15) and the limb's stance spring sagged 0.186 m, so
`thrust_coefficient`, `stance_stiffness_n_m` and their ratings scale with the
hull. Doc 01 §14 rule 19 checks the rotor pair against each other and refuses a
disc that cannot lift its rating, which caught it immediately.

**What stopped it is not a threshold.** `test_ai_engagement`'s attacker turns to
face its target perfectly — 179.9° to 0.4° — and then does not close, 44.2 m to
45.4 m, firing nothing. The throttle law says full ahead at that bearing and the
arrival brake says zero, and the same build drives at 16 m/s under power
elsewhere, so it is not the law. A game whose opponents do not drive at you is
worse than one with a small vehicle, so it was reverted rather than shipped.
`HANDOFF.md` §3.1.2 has every number, both layouts, the three fixture rules, the
per-file exceptions, and the one instrumented run that would close it.

### Session 34, in more detail

The rebuild was run rather than proposed, which is the only reason §3.1.2 is worth
anything: the uncertain half — does this design actually put four wheels on the
ground, and does the registry accept it — is answered, and what is left is
mechanical.

The cabin goes from 4×3×5 cells to **6×4×13** and the autocannon comes *down*
from 9 cells to 7, which is the whole silhouette problem: the weapon was 50% of
the vehicle's length and the cabin 28%. With the cabin spanning thirteen cells the
gun tucks onto the roof instead of hanging 1.12 m past the front axle, and the
hubs reach the ends of the hull for a 2.75 m wheelbase.

Two traps were paid for on the way. `validate_part_registry` refused a 3-cell-wide
repeater under doc 01 §14 rule 27 — an odd-width module cannot centre on an
even-width hull and Invariant I-6 leaves no half-cell to correct with. And raising
mass without the geometry was measured as worthless: on the old layout it moves
the split from 73/27 to 70/30, because a 1.50 m wheelbase turns a centimetre of
centre-of-mass shift into 0.7 points.

**On the sources.** Every Crossout domain — `crossout.net`, both Fandom wikis,
`crossoutdb.com`, `steamcommunity.com`, `forum.crossout.net`, `en.namu.wiki` — is
refused at the CONNECT by this environment's network policy, and the search quota
was spent establishing it. Four figures survived and two are load-bearing: a
medium cabin's tonnage of ≈5,300 kg, which is now `mass_tolerance_kg` directly,
and a medium wheel at 110 kg, which said the wheels were nearly right and
everything else three to five times too light. The rest of the scale is derived
from those two and from real-vehicle bounding-box density.

### Session 33, in more detail

**The control card.** Doc 11 §14.6 centred it on the reasoning that the middle of
the screen is what a player looks at. The first capture of a real match falsified
that: the opponents close from ahead, so the middle is exactly where a first-time
player must be looking, and an opponent sat directly behind the panel at seven
seconds with the card still up at ten. It moves to the upper left — the only
quarter of the interface with nothing in it — and the eleven-second dwell becomes
a ceiling rather than a duration, collapsing to the fade the moment the player
drives, steers, or fires. Camera, zoom, and mouse release deliberately do not
count: those are the rows a player is least likely to find alone.

**`release_part`.** Doc 08 §5.4 has always said a part taken out of the
simulation has its shapes disabled. The method was written, documented,
unit-tested, and called by nothing in `src/`, so a destroyed part that stayed
attached kept its collider and its mesh — rounds went on stopping in armour that
no longer existed. The consequence was larger than expected and is the session's
best result: **the ambulatory mirror duel now reaches a decision.** It had been
asserted as it failed for eight sessions on the explicit understanding that it
was supposed to break the day something upstream was closed. Re-measured rather
than loosened, and its tick count deleted rather than moved — a tick count in a
multi-Assembly file measures the suite, not the fight, so what is asserted now is
the outcome.

**§7.4, second attempt, second revert.** Both remaining traps were solved and are
recorded in the document and in `LEARNED_FACTS.md` §1 facts 73 and 74. Step the
slip rather than the rate, because damping `ω` resists a contact genuinely
spinning up with an accelerating hull and takes full throttle to 0.20 m/s. Take
the implicit factor from the chord and never the tangent at zero, because the
tangent over-damps a lagging contact by **317×**. With both right the scheme
measures well in isolation — 6.06 m/s² at full throttle, and a build set rolling
at 0.4 m/s finally comes to rest.

It still does not work in the game, and the reason is not in the integrator:
**two of the shipped build's four contacts carry no normal load at all.** The
hull has been standing on two wheels for the life of the project and §7.4's
chatter was producing enough force to hide it. The obvious cause — the
right-hand wheel cells authored one cell forward of the left — is not the cause:
squaring them up fails `test_the_shipped_starter_is_its_own_mirror`, because doc
02 §10's mirror is right and the wheel's pivot is off-centre. `HANDOFF.md` §3.1.1
owns it and it blocks §3.1.

**Documentation.** The section-number mapping table was in all three memory files;
it is now in `LEARNED_FACTS.md` §0 and pointed at from the other two. Doc 05 §3.4
and §7.2 both led with superseded text — §7.2's code block still carried the
inverted longitudinal sign four sessions after the prose was corrected, so a
reader following the code implemented the bug — and both now state the correct
physics first with a short record of what changed underneath.

### Sessions 24–32, in more detail

**Deleted, and this line is the record that they were.** Each of those sessions
had a forty-line account here; the table above carries what it did, the durable
half is in `LEARNED_FACTS.md`, the architecture it produced is in `/docs/`, and
the long version is in this file's git history. Nine sections of prose that
nothing referenced was the largest block of text in the three memory files, and
CLAUDE.md §10 rule 1 says to compress older entries as they stop mattering.

The rule that fell out of doing it: **an entry earns its detail section while a
later session might still need to re-derive the reasoning.** Once the reasoning
has been either written into a document, promoted to a fact, or superseded, the
prose here is a third copy.


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
| `test_part_registry_data` | manifest order swapped; four attachment nodes dropped from a `.tres`; a part missing from a class bucket; a locomotion family with no shipped part; *(session 37)* a chassis authored with the wrong `locomotion_mask`, asserted as the full four-family set rather than against the constant the data uses |
| `test_placement_validator` | occupancy never reports a cell occupied; every polarity accepted; interpenetration margin flipped positive; structural load ignores the parent's subtree; motive clearance probes one cell not the envelope; effector arc never counts a blocked sample; bounds check disabled; duplicate Core Module allowed; hard limits ignored; commit forgets `FLAG_STRAINED`; stale parent survives a rejection; Core Module charged against its own mount budget; proxy transform written before its shapes; `allocate_slot` stops allocating lowest-first; removal never finds an alternate parent; *(session 27)* **a cascade announcing only the part the player named**, and the mirror of it; *(session 37)* a chassis family check that refuses too much or too little, asserted as the whole three-by-three matrix, plus the check being ordered after the budgets where it would be unreachable |
| `test_rest_stability` | *(session 32, re-asserted 38)* written asserted-as-it-failed and turned round when §7.4 closed. It now defends the repair from both sides: zero contact-rate sign reversals in twelve ticks, a peak under a hundredth of a rad/s, and a build that comes to a **complete** stop with no input. The sign history is still the instrument — a hull that is stationary on average moves no speed assertion at all |
| `test_part_inspector` | *(session 42)* doc 11 §4.3's chassis row dropped from a Core Module's card, so the one figure that decides what a player may bolt on is unreadable again |
| `test_control_card` | *(session 33)* the card moved back to the centre of the screen; the stand-down removed, so the dwell runs its full eleven seconds through the opening engagement; an action added to or dropped from the stand-down list |
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
| `test_wreck_settles` | doc 05 §3.6's liveness guard removed from `MotiveSystem.step`; *(session 32)* §3.7's freeze removed — the hulk drifts 2.80 m under the end card instead of staying put, and reports itself still simulated |
| `test_mirroring` | *(session 28)* §10's mirror reflecting the pivot cell instead of the footprint; a mirrored part keeping its orientation; the mirror plane moved half a cell onto the origin column; a mirrored pair recorded as one placement so undo takes one flank; a refused mirror committed unvalidated |
| `test_blueprint` | *(session 30)* **the shipped starter re-armed with a module its own chassis cannot fire while moving**, and the drivability ceiling raised past every published row so its own check could never fail; a blueprint that commits without validating; `copy()` returning a reference rather than an independent list; *(session 27)* **`from_context` writing ascending slot order**, which stops being a construction order at the first removal |
| `test_breakpoint` | the stat dock hidden below the expanded tier |
| `test_screen_flow` | *(session 30)* **the player stocked with a round their own module does not chamber**, the second round type never registered, and §14.1's counter reading the other store — three faults, none of which anything else in the suite noticed; the shell keeping the outgoing screen alive behind the incoming one; *(session 27)* the undo and redo keys reaching their handlers, and RESET editing the build before it is agreed to |
| `test_degradation_table` | a band multiplier changed off its documented value; a table that does not terminate at zero; a table that is not monotonic; a table of the wrong length; the out-of-range clamp removed; a table missing from `all_tables()` |
| `test_suspension_solver` | compression not clamped to travel; an ungrounded probe still compressing; rebound damped like compression; force allowed to pull; bottom-out clamp removed; settle scale always applied; damp multiplier ignored; retune scale unclamped; damper not derived from corner mass; axle pairing ignoring longitudinal distance; axle pairing accepting the same side; anti-roll ignoring the difference; *(session 29)* **§16.1's droop returning the travel consumed instead of the travel left**, full droop returned whatever the probe found, and an ungrounded contact drawn in its placed cell |
| `test_traction_solver` | slip ratio dividing by raw speed; slip angle using a signed denominator; Pacejka curve unnormalised; load sensitivity unclamped; band multiplier dropped from μ; **longitudinal sign flipped**; lateral grip ratio applied after the solve; zero-slip guard removed; brake zero-crossing guard removed; the guard catching negative drive too; ground reaction term dropped; contact inertia using full mass; torque split evenly rather than by load; rolling resistance ignoring the band |
| `test_traction_control` | the launch floor dropped from the allowance; **the corrective brake's ceiling removed**; the slip cut turned into a subtraction; the deadband stepped over rather than subtracted; the grip clamp dropped; the bicycle model's sign; authority not applied to the brake demand |
| `test_rotor_solver` | spool as an Euler step; spool-up and spool-down swapped; power fraction not applied; power fraction unclamped above one; thrust linear in tip speed; collective clamped at zero rather than signed; ground effect never fading; translational lift unbounded; vortex ring with no forward escape; vortex ring onset removed; degradation dropped from thrust; cyclic clamped per axis rather than on the cone; thrust direction ignoring orientation; shaft torque dropping the radius term; collective unclamped; cyclic step not rate limited |
| `test_gait_solver` | **right side not reversed**; phase offsets not spread; sides not partitioned; fore-aft tie not broken on slot; standing deadband removed; cadence unclamped; clock not wrapping; neutral point using a whole stance; velocity-error correction dropped; step length unclamped; leg reach unclamped; frozen gait still stepping; turn command ignored; stance spring allowed to pull; foot force uncapped; stance damper dropped; foot μ ignoring the band; friction cone never limiting; an upward-pulling foot still transmitting; swing arc not a parabola; *(session 29)* the swing arc flattened onto the ground, and swing progress measured from the top of the cycle rather than from lift-off |
| `test_track_solver` | stations not centred on the patch; stations all at the pivot; authority not tapering; taper ignoring speed magnitude; steer command unclamped; internal loss charged after the split; bias not differentiating the sides; slew resistance uncapped; slew resistance not opposing; slew ignoring patch length; slew ignoring normal load; the centreline counting as right; station load divided by count |
| `test_melee_solver` | cycle multiplier ignored; swing arc not centred; edge not offset along its reach; sample count unbounded; samples not reaching the end of the swing; channel mix ignored; the mix sum hard-coded to one; sustained flag ignored; closing-speed gate inverted; the terminal swing-progress assignment removed; reaction not opposing the strike; energised draw always charged; `begin` not clearing the target set; target budget not enforced |
| `test_motive_system` | slot list not sorted; duplicate registration appending; the class guard removed (caught only since §3.34); a tracked part given one contact; a rotary part given a contact; station index never advancing; a band change writing only traction; unregister leaving the slot; unregister not re-phasing the gait; unregister leaving the disc state; the hip not resolved from the placement; contacts never bound to their probes; any two probes pairing regardless of side; a probe taken into two pairs; pairs never built at registration |
| `test_control_system` | **the whole record left unsampled** (the clock connection dropped); the axis helper's halves swapped; steer inverted; the brake action no longer producing a reverse demand; the brake field dropped; collective decoupled from the drive axis; yaw decoupled from the steer axis; §15.4's pitch inversion undone; §15.4's roll inversion undone; the two tilt axes transposed; the aid authority left unbounded; the held buttons never read |
| `test_locomotion_families` | a locomotion family mis-mapped in `LOCOMOTION_OF_MOTIVE_KIND`; `ENERGY_MELEE` not recognised as melee; a family payload keyed on the wrong kind; rotor max thrust dropping the density; stance rest length as the whole leg; stance duration ignoring duty factor; melee mix sum hard-coded to one |
| `test_physics_frame` | `physics_frames` waiting for nothing |
| `test_ground_assembly` | steering turning the wrong way; the steer angle snapping instead of rate limiting; the contact frame never steered; probe sphere far larger than the contact; every probe sweeping from the Assembly origin; probe reach too short to reach the ground; probes masked to hulls instead of ground; probes parented outside `MotiveProbes`; no part getting a probe at all; contacts never bound to their probes; any two probes pairing regardless of side; axle pair ends swapped; pairs never built at registration; the slip limiter never cutting; the limiter ignoring its authority; the yaw target pointing the wrong way; the corrective brake applied to the flank that adds to the spin; **the corrective brake never reaching the contacts**; **both flanks braked instead of one**; drive torque clamped to forward only; *(session 29)* §16's visual pass dropped from the tick |
| `test_motive_force_application` | a disc given a ground probe |
| `test_inertia_coupling` | coupling torque unclamped; identically zero; applied in the body frame; angular velocity never rotated into the body frame; never applied at all; evaluated at the tick boundary rather than the midpoint; **sign flipped** |
| `test_locomotion_behaviour` | both track flanks driven alike; flanks swapped; the steer command never reaching the mixer; every bogie counted as one flank; a limb's probe sized from suspension it has none of; a limb sweeping from the Assembly origin; *(session 29)* **a planted foot drawn at the last swing sample instead of at the point it is standing on** |
| `test_family_duels` | *(session 15; see the sweep record below)* the muzzle-relative recoil impulse dropped; a pitch limit that no longer clamps; *(session 33)* `release_part` not called, so rounds go on stopping in destroyed armour and the ambulatory mirror grinds out 900 of 900 ticks with neither Core Module lost |
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
| `test_held_weapon` | *(session 18)* §15.3's capsule reduced to a ball at the blade's midpoint; the capsule left standing on its own +Y; §15.4's impulse on the target never applied; the closing-speed gate refusing everything; the per-swing dedup removed; the sample count dropped back to 6; **§15.4's impulse taken from the blade's axis rather than from the edge's travel**; *(session 42)* §15.5's stage hold removed; **the per-tick clear of the victim set removed**, which is the fault no assertion about damage arriving can see; a held edge charging strike damage per tick; the instalment not declaring its interval; and, through the fire it starts, §7.3's list never told a part ignited |
| `test_dot_scheduler` | *(session 42)* doc 08 §7.1's ignition never announced to §7.3; one entry per packet instead of one per burning part; the 10 Hz cadence gate removed; the cooling term zeroed, so the hysteresis band is unreachable and a part that catches fire burns to nothing |
| `test_first_run_card` | *(session 42)* doc 11 §14.6's first-run flag consulted by nobody — the card back to being raised over every match a player ever plays; *(session 43)* doc 05 §15.7.4's briefing gate deleted from `AiDriver`, so the opponent shoots a first-time player who is reading; and a card the player raised counting as a briefing, which makes `hud_toggle_stats` a key that switches the opposition off |
| `test_melee_duel` | *(session 43)* the melee recipe holding at the ground family's twenty-metre stand-off, so an edge with 2.4 m of reach parks seventeen short; the orientation group answering "identity" when asked to carry an Appendage's shoulder onto a hull face; and **§15.4's per-swing impulse applied on every tick of contact** — a fault `test_held_weapon` cannot see, because it freezes the target that would be thrown |
| `test_duel` | destruction never flagged; the destroyed event never emitted; **ammunition never consumed** |
| `test_part_mesh_pose` | *(session 29)* the §16.1 droop lifting the part instead of lowering it; the droop composed in the part's own frame rather than the chassis's — **which nothing in `tests/physics/` can see, because a Motive Assembly is only ever mounted upright there**; a limb never turned toward its foot; a limb turned about its mesh origin instead of about its hip |
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
| `test_recoil_geometry` | *(session 24, re-asserted 38)* doc 01 §14 rule 27 in both halves — the authored bore against the footprint centre and the width parity against the Core Module's — then the same quantity off the live mount. The traversed-yaw claim **inverted** in session 38: the lever is still there and still asserted, and a parked hull standing on real friction with §7.7's brakes on now absorbs the round, 0.0035 rad/s against 0.124 |
| `test_ai_engagement` | *(session 23)* the whole chain end to end: a scan, a target, a 180° turn, an approach, a mount converged, a round fired, a store decremented by exactly the shots, integrity taken off the target — plus §15.7.4's fire discipline and §10.2's arc penalty by value; *(session 31)* §15.7.1's arrival brake deleted, through the rounds floor |
| `test_braking_and_reverse` | *(session 38)* the file that would have caught every one of the session's own regressions: a rotary arrest with §15.4's sign inverted (the disc accelerated the hull and flipped it), a tracked build that pitched past vertical under an unproportioned brake, and a gait that could not be asked to stop because the brake demand and the travel demand fought each other. It also records two things as they stand — an ambulatory build sheds only half its speed, and cannot reverse at all |
| `test_ram_attitude` | *(session 31)* §15.7.1's arrival brake deleted — the target inverted at 180° of roll, the driver at 173°, and the two hulls interpenetrating by 2.36 m; the stand-off put back inside the hulls, once the gap assertion asked for clear air rather than for bare non-contact. **The first fixture in the project that measures whether anything ended up on its roof** |
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

Ten committed sweeps, 153 faults between them, all driven by
`tools/ci/sweeps/sweeplib.py`. Run them with `-j4`; a full pass over one script
is a couple of minutes.

| Script | Covers | Faults |
|---|---|---|
| `engagement_sweep.py` | the paths the engagement files rest on (sessions 15–16) | 14 |
| `garage_edit_sweep.py` | doc 02 §9's editing model and §10's mirror: the command stack, removal's announcement, `from_context`'s order, `children`'s ordering, the reflection | 16 |
| `combat_layer_sweep.py` | damage, effector and projectile layers (session 14), plus doc 07 §15 (session 18) | 45 |
| `ai_layer_sweep.py` | `src/ai/`, doc 05 §15.7, doc 07 §10, doc 01 rule 27 | 13 |
| `match_layer_sweep.py` | doc 11 §16's outcome rule, §14.3's target bracket, §14.6's binding lookup, doc 05 §15.7.5's ladder | 12 |
| `contact_visual_sweep.py` | doc 05 §16: the droop, the frame it is applied in, the limb's pivot, the swing arc | 12 |
| `effector_choice_sweep.py` | doc 01 §10.5's second direct-fire row: the starter's module, the comparison fixture, the second round type's wiring | 6 |
| `drive_cycle_sweep.py` | doc 05 §6.5's anti-roll sign, §7.7's holding brake and proportioning, §7.8's driveline drag and governor, §15.5's release, §7.1's steering, and doc 11 §7's binding table, glyphs and pad cursor | 18 |
| `burn_and_hold_sweep.py` | doc 07 §15.5's sustained contact — the stage hold, the per-tick clear, the rate, the interval, the impulse — doc 08 §7.1's ignition and cooling and §7.3's cadence, plus doc 11 §4.3's chassis row and §14.6's first-run flag | 11 |
| `briefing_and_edge_sweep.py` | doc 05 §15.7.4's briefing gate and doc 11 §14.6's briefing/legend distinction, the melee recipe's stand-off, the orientation group's shoulder answer, and §15.4's impulse against the fixture that now catches it | 6 |

### What still survives, and why

| Fault | Script | Why it is kept |
|---|---|---|
| `self-immunity-zero` and `self-immunity-always-on` | engagement, combat | Doc 07 §12.3 is inert **in both directions** on the shipped builds: the nose mount emits 2.75 m ahead of the lattice origin, clear of every hull. A mechanism no engagement can distinguish from either of its extremes is carried, not tested. Closes when a module ships with its muzzle overhanging its own hull. |
| `cyclic-not-cone-clamped` | engagement | Two 14° deflections clamped per axis compose to 19.8° and the hover simply asks for less next tick — a closed loop absorbing a fault in the quantity it closes over. Closes with a unit test of `RotorSolver.thrust_direction`, where the demand is open-loop. |
| `same-part-twice-allowed` | engagement | A coverage regression, not a gap that was never filled: it was caught before the penetration budget became lifetime-scoped and is not caught after. Closes when a part ships with two collider primitives along one axis. |
| `melee-modules-emit` | combat | Four owners of one invariant, reduced to three. Each of the three enforces it alone, so no single deletion is visible. |
| `debris-transform-before-shapes` | combat | Doc 04 §6's ordering rule. **Known unverifiable by the obvious route**: the physics step a test needs in order to read a current pose is the same step that repairs the fault. Two attempts are recorded in `HANDOFF.md`; the honest position is that the rule is defended by the comment in `island_detacher.gd`. |
| `tracked-mean-is-its-first-station` | contact visual | Doc 05 §16.1 draws a tracked patch at the mean of its road stations, and on a flat slab every station reports the same distance — so the mean and the first are one number. Planted knowingly, in the same change as the code. Closes with a bogie straddling a slope, which no fixture in `tests/physics/` has. |
| `aim-point-read-from-scan` | ai | Doc 07 §10 runs selection at 2.9 Hz and aim solving every tick; collapsing them aims at where the target was up to 350 ms ago. Marginal rather than firmly untested — CAUGHT on one run and SURVIVED on the next, either side of an unrelated change. What closes it properly is an engagement in which the AI's target is *driving*. |

| `sustained-no-interval` | burn and hold | *(session 42)* `DamagePacket.interval_s` on a §15.5 instalment reaches doc 08 §7.2's corrosive decay and nothing else — §7.1's heat is `raw · 0.55` per packet and its `maxf(interval_s, 1.0)` is 1.0 for every interval this game produces. The line is right and no shipped melee mix authors a corrosive share, which is the ammunition sentinel's shape exactly. Closes with a corrosive edge, or with a resolver test that submits one. |
| `briefing-never-held` | briefing and edge | *(session 43)* The four lines of `MatchScreen` that join doc 11 §14.6's card to doc 05 §15.7.4's gate. Both ends are asserted — the gate on a real `AiDriver`, the briefing on a real `MatchHud` — and the join is reached only by `test_screen_flow`, which builds two real matches and does not control `SyndicateSettings.control_card_seen`. Closes when that file takes over the settings save/restore `test_first_run_card` already does, or when a match is cheap enough to build a third time. |
| `breakaway-never-releases` | ai | §15.7.1's standing-start demand applied at every speed, so it becomes the sustained heavy throttle that stopped the opponents ever reaching the player on real terrain. **A survivor, then briefly caught, then a survivor again** — and the round trip is the finding, not the verdict. Session 30 recorded it as caught because with no arrival brake a sustained throttle made the driver orbit its stand-off, which `test_ai_engagement`'s rounds floor is sensitive to. Session 31's arrival brake stops a driver orbiting *whatever* its throttle is doing, so the symptom the fixture was reading is gone and the rule underneath it is uncovered again. Nothing about the rule changed; a correct, unrelated change desensitised the one fixture that happened to see it, which is `LEARNED_FACTS.md` §2.1 word for word. Closes only with terrain in a fixture, or with a capture. |

The `breakaway-never-releases` row is worth reading twice by anyone about to
conclude a sweep result means a behaviour is defended. It has now been CAUGHT and
SURVIVED across three sessions without one line of the code it defends being
touched.
