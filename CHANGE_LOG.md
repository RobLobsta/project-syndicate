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
| 37 | **A limb and a rotor disc each have a chassis, and the test drive is a duel.** Doc 01 §7.1 gives `CoreModuleProfile` a `locomotion_mask` and the validator a `MOTIVE_FAMILY_MISMATCH`; `core.ambulatory.strider.t3` and `core.rotary.lifter.t3` join §10.1. The walking recipe stops borrowing a hull whose every published figure describes a machine that stands on the ground — and gains the mounts for an Energy Cell it could not fit. `MatchScreen` spawns one opponent instead of three, with the same store the player carries. Capture: the player is alive at ten seconds at 54% where it was destroyed before nine. |
| 29 | **The wheels touch the ground.** Doc 05 §16: a Motive Assembly's mesh is drawn where its contact is, not at the cell it was placed in — so suspension travel is visible, a wheel over a crest extends instead of hanging in the air, and a walking limb points at its foot along §13.7's swing arc. Twelve planted faults, one survived by design. The capture that verified it found the player flipped onto its back and destroyed in seven seconds while standing still. |
| 36 | **The rebuild lands, and the AI regression was never the AI.** The part table, both layouts and all four locomotion recipes transcribed; the reference build is **3630 kg at 132 kg/m³ on a 3.00 m wheelbase, standing on all four contacts at a 48/52 split**. One instrumented run of `AiDriver` found it: throttle 1.00 and a target held the whole time, while the hull climbed off the ground contact by contact under sustained full throttle. Doc 05 §7.4's unstable contact integration, energised by drive torque — so `drive_torque_nm` is capped at 6400 N·m until §7.4 is closed. Also: an inertia grows as the square of the extents, so every yaw and roll authority in the project fell by a factor of six. |
| 35 | **The rebuild, 89% landed.** Fixture fallout taken from **448 failing assertions across 28 files to 50 across 11**: the part table, both layouts, all four locomotion recipes, and the published-value assertions are all solved and written down. Reverted one regression short — the AI turns to face its target and then declines to close. |
| 34 | **The Crossout-scale rebuild, executed and measured, then reverted.** The reference build goes from 1107 kg at 46 kg/m³ standing on two of its four wheels to **3630 kg at 141 kg/m³ standing on all four**, with the wheelbase from 35% to 73% of the hull and the static split from 100% front to 41%. The registry validates and the proportions instrument confirms it. Reverted because the fixture fallout is 396 assertions across 28 files; `HANDOFF.md` §3.1.2 carries every number that produced the measurement. |
| 33 | **Three queue items, and the middle one beaten twice.** The control card leaves the middle of the screen and stands down on the player's first input (doc 11 §14.6). `release_part` is finally called, so a destroyed part's collider and mesh leave with it — which took doc 07 §12.2's penetration budget off corpses and turned the ambulatory mirror from an eight-session stalemate into a decision in 221 of 900 ticks. §7.4's integrator was rebuilt with both traps solved and reverted again: the shipped Assembly stands on two of its four wheels, and on that stance a correct integrator looks like a broken one. |
| 32 | **The wreck stays where it fell, and the reason a parked build never stops is now known.** Doc 05 §3.7: a body with no live parts is frozen rather than left as a one-kilogramme hull-sized collider anything can punt. Measured 2.80 m of hulk travel before, 0.00 m after. Then the physics assessment that came with it: §7.4's contact integration is **142× outside its own stability limit**, the contact reverses on ten of twelve ticks under a build standing still, and the repair was built, measured, and reverted because it moves every wheeled number in the project. `test_rest_stability` measures the defect and is asserted as it fails. |
| 31 | **You are not driven over any more.** Doc 05 §15.7.1 gains an arrival brake and a stand-off measured against the hulls rather than guessed at. The instrument came first: `worst_roll_deg` on `CombatArena.Combatant`, which is the first attitude any engagement fixture has ever recorded. Target roll on a stationary build under three converging drivers: **146.2° before, 0.3° after.** Found on the way: a stand-off shorter than the two hulls it separates, and a parked Assembly that never stops rolling. |

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

### Session 32, in more detail

Two halves, and the second one is the reason the first is the only thing that
shipped.

**The wreck.** Doc 11 §16.2 decides the hulk stays where it fell and it did not.
The mechanism was already written down and was half wrong in an instructive way:
losing the Core Module orphans every part, the islands detach, and doc 05 §3.5's
floors then describe what is left as a one-kilogramme object. What the record did
not have is that **one collider survives on it** — `AssemblyRuntime.release_part`
disables a destroyed part's shapes and *nothing in `src/` calls it*, so the
destroyed Core Module's own primitive is still there. A hull-sized collider on a
gramme of mass is a thing anything can punt over the horizon. Doc 05 §3.7 freezes
a body that has no live parts, after the islands have taken their `v + ω × r`.
2.80 m of travel before, 0.00 m after, and the fault plant fires both checks.

`release_part` having no caller is left as a finding rather than fixed: a
destroyed part that stays attached keeps its collider and its mesh, so rounds
still stop on it, and closing that moves every overpenetration measurement in
`tests/physics/`. It is `HANDOFF.md` §4's now.

**The physics assessment.** The queue's §3.10 said a parked Assembly never comes
to rest because nothing puts a rolling resistance on a free contact. The first
half is true and the second is not the cause. §7.4's contact integration is
explicit against a friction reaction of about 2.9e5 N per rad/s, which puts the
stability limit at 117 µs against a 16.7 ms tick — **a factor of 142**. It does
not diverge because §7.2's curve saturates; it limit-cycles, at ±4.7 rad/s
reversing every tick against a free-rolling 0.036.

The repair — a friction force may not reverse the slip it opposes, on both axes —
was built and measured: resting reversals 11 of 12 → 0, drift 2–3 m → 0.49 m,
and full-throttle acceleration *up* from 3.87 to 8.06 m/s, because the chatter had
been spending grip on nothing. It also halved part-throttle response, collapsed an
imposed 1 rad/s yaw to 0.057 rad/s in six ticks, and took the AI engagement from
ten rounds to one. **None of those is a defect in the repair**: the chatter was
destroying lateral grip by about 37×, and every handling constant in the project
was tuned against a machine that could not corner. That is a `balance-review` pass
with a capture, and half of it is worse than the defect. Doc 05 §7.4 carries the
diagnosis, the arithmetic, and the scheme.

### Session 31, in more detail

The queue's top item, and it named its own first step: build the instrument
before touching a constant, because otherwise the fix is unmeasurable.

- **`worst_roll_deg`, and it is the point of the session.** Every engagement
  fixture in this repository records rounds, ticks, kills and travel. None of
  them recorded **attitude**, so the two most player-visible failures of the last
  two sessions — being rammed onto your flank, and a wreck departing at 27 m/s —
  were invisible to a green suite and visible in six frames of a capture. It is
  about twenty lines on `CombatArena.Combatant`, sampled per tick for every
  combatant whether it is piloted or not, because the thing that gets rolled over
  is the one nobody is driving.

- **Three defects under one symptom, and only the first was the one expected.**

  1. **§15.7.1 had no arrival brake and needed one.** The section removed an
     arrival brake two sessions ago after measuring that it changed nothing, and
     wrote down what would bring it back: *an approach that ends fast*. That
     measurement was taken on a driver spawned facing **away** from its target,
     which spends its approach on the cosine taper and arrives at a walk. A
     driver spawned facing its target never touches the taper, holds full
     throttle for the whole run-in, and the shipped arena's nearest opponent
     spawn is 34 m — enough to arrive at **18.2 m/s**. The law is now a
     stopping-distance one, `v = sqrt(2 · a · slack)`, because the quantity that
     decides a ram is `v²/2s` and not speed.
  2. **The stand-off was shorter than the two hulls it separated.**
     `GROUND_STAND_OFF_M` was 6.0 m and had been authored against an Assembly
     length nobody had ever measured. Measured from the colliders, the reference
     build reaches 2.4 m from body origin to nose, so two of them **touch at
     4.8 m**. Six metres was nose-to-nose parking with 1.2 m of air against a
     1.2 m overshoot, and the run finished with an eight-centimetre gap. It is
     now 10.0 — contact range plus a full hull length of clear air.
  3. **A band on the closing test was added, measured, and removed.** The
     reasoning was good — a driver oscillating across a hard stand-off line
     applies throttle into a nearby hull each swing — and the measurement did not
     support it: identical fixture output with it and without, and a fault
     deleting it survives a full sweep. §15.7.1's own precedent decided it. Kept
     in the document as a thing tried, because the reasoning is the kind that
     gets re-invented.

- **The shove that looked like the ram was the target's own drift.** A parked
  1107 kg Assembly with no throttle and no brake reads 0.38 m/s at the end of a
  90-tick settle and **still 0.38 m/s after 360**, and covers two to three metres
  over an engagement while the nearest hull stays three metres clear. Nothing
  under doc 05 §7 puts a rolling resistance on a free contact. It cost an
  assertion that looked correct and measured the fixture; the honest detector is
  the gap between the hulls, which cannot be satisfied by a target that wandered
  off on its own. The drift is a real finding and is in `HANDOFF.md`.

- **A sweep found the assertion that was nearly vacuous.** Asking only that the
  hull gap stay positive passed at **eight centimetres** against the old
  stand-off, so `stand-off-inside-the-hulls` was caught by the unit test and by
  no physics file at all. The fixture now asks for a metre of clear air, which is
  what a stand-off is, rather than for the absence of the worst outcome.

Seventeen faults in the AI sweep, three survived: `aim-point-read-from-scan` and
`breakaway-never-releases` are the two standing ones, and the third was the
hysteresis, which was deleted rather than defended.

### Session 30, in more detail

The task named the fix: machine guns instead of cannon. It is right, and the
reason it is right is that recoil yaw is `impulse × lever ÷ I_yy` — rule 27 and
the mount's placement own the lever, and until this session nothing owned the
other factor.

- **A second `BALLISTIC_DIRECT` row rather than a nerf to the first.** Both
  modules ship. The autocannon still goes through a hull and still cannot be
  fired from a moving one; the repeater can be fired while driving and stops at
  what it is shooting at. That is doc 06 §12's onboarding row getting a real
  first decision instead of a strictly-better part.

- **The measurement is the deliverable**, and it is new:
  `tests/physics/test_drive_and_shoot.gd` holds one chassis under throttle with
  its mount traversed square and its trigger down, and differs between runs in
  one authored resource. 30 rounds and 2.9° against 2 rounds and 99.1°. Every
  previous measurement of this problem was a single round on a parked hull.

- **The autocannon build does not merely wander — it stops shooting.** The recoil
  turns the hull out from under the mount and doc 07 §4.3.1's fire gate then
  correctly refuses to shoot at something the module is no longer pointed at. Two
  rounds of the seventeen its cycle allows. A player reads that as a gun that has
  broken.

- **A second round type broke three joins that had agreed by accident.** Every
  module in the catalogue chambered `proj.kinetic.ap_30`, so "which round does
  this module fire", "which stores is this Assembly granted" and "which store
  does the HUD count" were the same answer and nothing checked they were. The
  fault sweep planted two of the three ways to get it wrong and **neither was
  caught**; `test_screen_flow.gd` now asserts the join.

- **`starter-ceiling-never-checked` is the general lesson.** A bound cannot
  assert anything about itself: raising the drivability ceiling past every
  published row leaves its own check green forever. The repair is a second
  assertion that the catalogue's heavy row is on the other side of it.

Six faults planted, three survived the first run, all six caught after the
repairs. The capture then found the wreck: see `HANDOFF.md` §2.

### Session 29, in more detail

One queue item, the top one: `spawn_visual` drew a Motive Assembly at its
placement cell and left it there for the whole match.

- **The offset is the travel the spring has not consumed**, not a position
  derived from the contact point. Both give the same answer under §6.1's
  authoring convention — rest length is one travel past the rolling radius, so
  the wheel's underside lands exactly on the surface — and only the first is
  bounded by construction, needs no second code path for an ungrounded contact,
  and stays honest for a row authored to a different convention. `droop_m` is one
  line and the whole of §16.1.

- **It is applied in the chassis frame, and that is the composition error the
  factory function exists to prevent.** A wheel hangs down the hull, not down
  itself, and the two are identical for anything mounted upright — which is every
  Motive Assembly in `tests/physics/`. The fixture that can see the difference is
  a synthetic sideways orientation in a unit test, and the fault sweep confirms
  that nothing else catches it.

- **A limb is now drawn as the virtual leg §13.1 says it is**: pivoted about its
  hip so its own down axis points at its foot, with §13.7's parabolic arc
  supplying that foot while it swings. `swing_height_m` had been written and
  called by nothing since session 9. This is deliberately one step short of
  §13.8's inverse kinematics, which stays doc 13's.

- **The swing target is re-derived every tick rather than frozen at lift-off.**
  Safe only because §13.7 applies no force during swing, so nothing drawn can
  reach the physics; the payoff is that the foot lands where the next touchdown
  puts it instead of jumping there. The placement law is called through one
  helper for both purposes — two derivations of one target would snap the limb on
  every plant.

- **The garage deliberately does not droop.** It has no ground, no probes and no
  contacts, so full droop is the only answer available and it would sink every
  wheel a full travel through the lattice floor. Recorded in §16.4 as a decision.

Twelve faults planted over §16, eleven caught. The survivor is the mean over a
tracked patch's road stations, which is untestable on a flat slab because every
station reports the same distance; it needs a bogie straddling a slope.

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
| `test_part_registry_data` | manifest order swapped; four attachment nodes dropped from a `.tres`; a part missing from a class bucket; a locomotion family with no shipped part; *(session 37)* a chassis authored with the wrong `locomotion_mask`, asserted as the full four-family set rather than against the constant the data uses |
| `test_placement_validator` | occupancy never reports a cell occupied; every polarity accepted; interpenetration margin flipped positive; structural load ignores the parent's subtree; motive clearance probes one cell not the envelope; effector arc never counts a blocked sample; bounds check disabled; duplicate Core Module allowed; hard limits ignored; commit forgets `FLAG_STRAINED`; stale parent survives a rejection; Core Module charged against its own mount budget; proxy transform written before its shapes; `allocate_slot` stops allocating lowest-first; removal never finds an alternate parent; *(session 27)* **a cascade announcing only the part the player named**, and the mirror of it; *(session 37)* a chassis family check that refuses too much or too little, asserted as the whole three-by-three matrix, plus the check being ordered after the budgets where it would be unreachable |
| `test_rest_stability` | *(session 32)* nothing yet, by construction: it is asserted as it fails, and what it defends is that §7.4's limit cycle stays visible until somebody repairs it |
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
| `test_held_weapon` | *(session 18)* §15.3's capsule reduced to a ball at the blade's midpoint; the capsule left standing on its own +Y; §15.4's impulse on the target never applied; the closing-speed gate refusing everything; the per-swing dedup removed; the sample count dropped back to 6; **§15.4's impulse taken from the blade's axis rather than from the edge's travel** |
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
| `test_recoil_geometry` | *(session 24)* doc 01 §14 rule 27 in both halves — the authored bore against the footprint centre and the width parity against the Core Module's — then the same quantity off the live mount, and §4.37's finding: a traversed round yaws the hull by a multiple of an on-axis one |
| `test_ai_engagement` | *(session 23)* the whole chain end to end: a scan, a target, a 180° turn, an approach, a mount converged, a round fired, a store decremented by exactly the shots, integrity taken off the target — plus §15.7.4's fire discipline and §10.2's arc penalty by value; *(session 31)* §15.7.1's arrival brake deleted, through the rounds floor |
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

Seven committed sweeps, 118 faults between them, all driven by
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

| `breakaway-never-releases` | ai | §15.7.1's standing-start demand applied at every speed, so it becomes the sustained heavy throttle that stopped the opponents ever reaching the player on real terrain. **A survivor, then briefly caught, then a survivor again** — and the round trip is the finding, not the verdict. Session 30 recorded it as caught because with no arrival brake a sustained throttle made the driver orbit its stand-off, which `test_ai_engagement`'s rounds floor is sensitive to. Session 31's arrival brake stops a driver orbiting *whatever* its throttle is doing, so the symptom the fixture was reading is gone and the rule underneath it is uncovered again. Nothing about the rule changed; a correct, unrelated change desensitised the one fixture that happened to see it, which is `LEARNED_FACTS.md` §2.1 word for word. Closes only with terrain in a fixture, or with a capture. |

The `breakaway-never-releases` row is worth reading twice by anyone about to
conclude a sweep result means a behaviour is defended. It has now been CAUGHT and
SURVIVED across three sessions without one line of the code it defends being
touched.
