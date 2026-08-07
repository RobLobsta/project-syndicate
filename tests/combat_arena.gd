class_name CombatArena
extends RefCounted
## A match, minus the match scene: ground, the combat systems, and any number of
## Assemblies built from shipped data that drive at each other and shoot.
##
## [code]tests/physics/test_duel.gd[/code] wired one engagement by hand and is
## still the reference for what the wiring [i]is[/i]. This is the same wiring
## made reusable, because the interesting questions stopped being "does a round
## reach a Core Module" and became "what happens when the two builds move
## differently" — which needs several engagements between several kinds of
## Assembly and cannot be answered by copying four hundred lines per fight.
##
## [b]It is a fixture, not architecture.[/b] Two things here are standing in for
## systems that do not exist yet and are named so that nobody mistakes them for
## a design:
##
## [enum]
## [*] [b]The ground is a [StaticBody3D] slab.[/b] Document 09 owns Dynamic
##     Ground Arrays and nothing here pre-empts it.
## [*] [b]The command loop in [method command] is a test pilot, not
##     [code]src/ai/[/code].[/b] It reads the world and writes a [ControlInput],
##     which is exactly the contract doc 05 §6.0 gives the AI driver, and it
##     makes no decision the motion layer could not be given by a person holding
##     a key. Its target selection is per tick and deliberately naive, because an
##     engagement test measures a fight rather than a scan interval — but the
##     [i]arithmetic[/i] it drives with is [AiDriver]'s since session 23, so a
##     gain has one value in one place. [method make_autonomous] is the opt-in
##     route by which a real [AiDriver] takes over a combatant.
## [*] [b]The rotary attitude controller in [method _fly] is a stand-in for a
##     stability-augmentation layer doc 05 does not have.[/b] It is not a tactic:
##     a human flying a rotary build needs the same three loops, so it does not
##     belong in [AiDriver] (doc 05 §15.7.3). It is here because an Assembly that
##     only flies when a human is flying it cannot be put in a test at all.
## [/enum]
##
## Every fight is decided by the simulation. Nothing scripts a hit, a winner, or
## a death; the recipes differ in mass, footprint, and how they get around, and
## the outcome falls out of that.

## ===== RECIPES =========================================================

## The shipped builds these fights are fought with. A recipe is a layout, not a
## class: every one of them is an Assembly with a Core Module at slot 0, and
## what separates them is the locomotion family under it and what it carries.
enum Recipe {
	## Four wheeled contacts, a Prime Mover, one Effector Module. Roughly 1.1 t
	## and the lightest thing here that can shoot back.
	WHEELED_LIGHT,
	## The same, with an Energy Cell in the tail. Heavier, longer, and it takes
	## more rounds to put down because there is one more part to eat them.
	WHEELED_HEAVY,
	## Two tracked bogies on stations under the flanks. Skid-steered, heaviest
	## contact patch, no steering geometry to lose.
	TRACKED,
	## Four ambulatory limbs and an Effector Module on the nose. Stands tall,
	## carries its Core Module a metre and a half further off the ground than
	## anything else here, and is a far better gun platform standing still than
	## walking — see [constant AMBULATORY_STAND_OFF_M].
	##
	## It carries no Energy Cell, and that used to be forced: four limbs at four
	## mount weights apiece left two of the ground chassis's twenty-eight and a
	## cell costs three, so the ballast that would balance the nose did not fit.
	## [b]`core.ambulatory.strider.t3` offers thirty-four and it now would.[/b]
	## The recipe still declines it, and deliberately — it is the fixture every
	## gait measurement in [code]tests/physics/[/code] is taken against, and a
	## 450 kg change to the build is a change to all of them at once. What was a
	## constraint of the shipped part set is now a choice of this recipe, and doc
	## 01 §10.1 records which of the two it always was.
	AMBULATORY,
	## A pair of coaxial rotor discs on outboard stations, an Energy Cell to
	## cover their draw, and an Effector Module. It hovers, which means nothing
	## but thrust holds it up and every newton of recoil goes straight into its
	## flight path.
	ROTARY,
	## The ambulatory build with no Effector Module. Diagnostic only: it is the
	## control for every question of the form "is that the gait or is that the
	## 196 kg on the nose".
	AMBULATORY_BARE,
	## [constant Recipe.WHEELED_LIGHT] with `eff.ballistic.repeater_12.t2` on the
	## nose in place of the autocannon, which is the build the shipped starter is
	## now. It exists so that the two Effector Modules can be compared on one
	## chassis, at one mount, under one throttle — doc 01 §10.5's whole claim for
	## the row is a comparison and a single-module fixture cannot make one.
	WHEELED_REPEATER,
	## The ambulatory layout with an Appendage on each flank, an
	## `eff.melee.beam_edge.t4` in each hand, and no direct-fire module at all.
	##
	## [b]It exists because doc 07 §15's whole melee chain had never been in a
	## fight.[/b] The strike, the sustained contact of §15.5 and doc 08 §7.3's fire
	## are exercised by [code]tests/physics/test_held_weapon.gd[/code] against a
	## frozen target held at a measured distance by a frozen attacker, which
	## answers what the laws compute and nothing about whether an Assembly that
	## has to walk, turn and close can ever reach one.
	##
	## [b]It is a walker, and that is now a rule rather than a preference.[/b] Doc
	## 01 §7.1 refuses an Appendage on any chassis that does not carry the
	## ambulatory family, so this recipe could not be built on the ground chassis
	## even if it wanted to be — see
	## [method PlacementValidator._check_appendage_chassis]. It was wheeled for one
	## session and read as what it was: a car with a sword bolted to its bonnet.
	MELEE,
	## The protected utility truck: `core.utility.hauler.t2`, four 1.00 m
	## contacts, a Prime Mover mated to the nose as a bonnet, and a light module
	## on the roof.
	##
	## [b]It is the second wheeled silhouette and the reason there is a second
	## wheeled chassis.[/b] Every other recipe here has always been the same box
	## with different running gear under it; this one is as tall as it is wide
	## where [constant Recipe.WHEELED_LIGHT] is a quarter of its length in height,
	## and no arrangement of parts on the road hull produces that. Doc 01 §10.1
	## carries the reference proportions both are derived from.
	WHEELED_UTILITY,
	## Two limbs, a humanoid torso, and the first Assembly in this project that
	## balances rather than being propped up.
	##
	## [b]It exists because doc 05 §13.10 and §13.11 landed.[/b] Until they did, a
	## walking Assembly's only pitch stability was the fore-and-aft separation of
	## its feet, so two limbs side by side had a stance base of zero and fell over
	## on the first tick. A foot with an authored support polygon carries the
	## fore-aft axis on its ankle instead, and the plant target is a capture point
	## that knows which way it is being asked to go.
	##
	## The torso is `core.biped.humanoid.t3` — twice as tall as it is deep, which
	## is the humanoid reference's own proportion and which
	## [constant Recipe.AMBULATORY]'s chassis cannot be, because a quadruped's
	## stance base *is* its torso depth.
	BIPED,
}

const CORE_KEY := &"core.command.compact.t2"
## Doc 01 §7.1: a Core Module declares which locomotion families it carries, and
## the validator refuses the rest. These two recipes cannot be built on
## [constant CORE_KEY] and are not meant to be — a limb and a disc each have a
## chassis now.
const AMBULATORY_CORE_KEY := &"core.ambulatory.strider.t3"
const BIPED_CORE_KEY := &"core.biped.humanoid.t3"
const ROTARY_CORE_KEY := &"core.rotary.lifter.t3"
const UTILITY_CORE_KEY := &"core.utility.hauler.t2"
const TRACKED_CORE_KEY := &"core.tracked.hauler.t3"
const HUB_KEY := &"str.hub.axle_station.t2"
## Three cells of spar between a narrow fuselage's flank and its mast station.
## See [constant ROTARY_PYLONS].
const PYLON_KEY := &"str.outrigger.pylon.t2"
## The road car's 0.75 m contacts, sized off the reference at 0.15 of the
## vehicle's length. The 1.00 m pair below is the utility truck's, where the same
## ratio is 0.16 — the two vehicles genuinely disagree about wheel size, which is
## why there are now two pairs (doc 01 §10.3).
const WHEEL_KEY := &"mot.wheeled.light_road.t1"
const REAR_KEY := &"mot.wheeled.light_fixed.t1"
const UTILITY_WHEEL_KEY := &"mot.wheeled.allroad.t2"
const UTILITY_REAR_KEY := &"mot.wheeled.fixed_rear.t2"
const TRACK_KEY := &"mot.tracked.long_bogie.t3"
const LIMB_KEY := &"mot.limb.strider.t4"
## The two-limbed row, and doc 01 §10.3 has the derivation. A biped is in single
## support for 76% of its gait cycle, so the foot it stands on has to satisfy the
## static-stability condition on its own — `sin θ_max = foot_length / 2h`, which
## on the strider's 0.60 m foot under this build's 2.55 m centre of mass is 6.8°
## against a gait that produces eight. It landed on its face at t=390 of a
## commanded turn until this row existed.
const BIPED_LIMB_KEY := &"mot.limb.broad_foot.t4"
const ROTOR_KEY := &"mot.rotor.coaxial_mid.t3"
## The truck's bonnet, and the wheeled family's second section. §7.3's mask makes
## this row `CHASSIS_WHEELED`, which is why the three recipes that used to borrow
## it now name a mover of their own below.
const POWER_KEY := &"pmv.combustion.standard.t2"
## One Prime Mover per locomotion family, per doc 01 §7.3's mask. A tank, a mech
## and a rotorcraft shared a road car's mover until it was added, so every torque
## figure in the game was a compromise across machines that share nothing.
const TRACKED_POWER_KEY := &"pmv.turbine.tracked.t3"
const STRIDER_POWER_KEY := &"pmv.combustion.strider.t3"
const ROTARY_POWER_KEY := &"pmv.turboshaft.rotary.t3"
## The same Prime Mover laid on its side, for a hull whose roof is 1.00 m off
## its own floor. See doc 01 §10.4 — every published figure is identical.
const FLAT_POWER_KEY := &"pmv.combustion.flat.t2"
const CELL_KEY := &"cel.static.standard.t3"
const GUN_KEY := &"eff.ballistic.autocannon_30.t3"
const ROUND_KEY := &"proj.kinetic.ap_30"
## The tracked family's gun: 6.00 m, one round every three seconds, and enough
## penetration that nothing in the shipping set stops it.
const CANNON_KEY := &"eff.ballistic.rifle_long.t3"
const CANNON_ROUND_KEY := &"proj.kinetic.ap_120"
const REPEATER_KEY := &"eff.ballistic.repeater_12.t2"
const REPEATER_ROUND_KEY := &"proj.kinetic.ap_12"
const ARM_KEY := &"apx.arm.manipulator.t3"
const EDGE_KEY := &"eff.melee.beam_edge.t4"

## Callsigns, handed out in spawn order and deterministic for a given arena.
##
## A number is enough for an assertion and useless for reading a log. When
## twenty Assemblies are in one engagement and the record says slot 3 of
## assembly 14 was destroyed by assembly 7, nobody can follow it; when it says
## HALYARD lost its Prime Mover to KESTREL, the fight has a shape. They are
## diagnostics and never reach a player, so [code]tr()[/code] does not apply.
const CALLSIGNS: Array[String] = [
	"ASHFORD", "BRAMBLE", "CASTELLAN", "DRAYTON", "EMBER",
	"FENWICK", "GALLOWAY", "HALYARD", "IRONWOOD", "KESTREL",
	"LANTERN", "MARLOWE", "NIGHTJAR", "ORRERY", "PENNANT",
	"QUARRY", "REDWING", "SABLE", "TALLOW", "VESPER",
	"WARBLER", "YARROW", "ZEPHYR", "ALDER", "BIRCH",
]

## ===== LAYOUTS =========================================================
## Cell origins, per recipe. Integer lattice coordinates throughout (Invariant
## I-6); the only floats in this file are world poses and the pilot's arithmetic.
##
## [b]Every layout below is derived against its own chassis's extents, and that
## is new.[/b] Until session 44 all four authored chassis were 6x4 in section, so
## one cell list ported between families and the constants here could be shared.
## Doc 01 §10.1 records why that stopped: five reference vehicles disagree about
## the section before they disagree about anything else, and a road car, a
## protected utility truck, a tracked gun platform, a walking torso and a
## rotorcraft fuselage have no box in common. Each block states the extents it is
## placed against, because nothing else in the file can tell you.

## --- The road car -------------------------------------------------------
## `core.command.compact.t2` spans `x` 20–27, `y` 4–7 and `z` 17–30 — 2.00 m wide,
## 1.00 m tall, 3.50 m long. Its deck is `y = 8` and its underside is `y = 4`.
const GROUND_CORE := Vector3i(24, 4, 24)
## [b]The Prime Mover is behind the cabin, not on its roof, and that one move is
## most of what makes this read as a road car.[/b] `pmv.combustion.flat.t2` is the
## square row rearranged into a 2.00 x 1.00 m slab (doc 01 §10.4), mated to the
## Core Module's `+Z` face at deck level: it adds 1.50 m of length and no height
## at all. The square row on the roof added 1.00 m of height to a 1.00 m hull and
## turned the vehicle into a pickup, which is what every wheeled recipe in this
## file looked like for forty-four sessions.
const GROUND_POWER := Vector3i(24, 4, 34)
## In the tail behind the engine bay, when a recipe carries one.
const GROUND_CELL := Vector3i(24, 4, 39)
## On the rear deck, over the cabin's back half. Still at the Core Module's own
## height above the centre of mass, which is the property the long comment this
## constant used to carry was actually about: doc 07 §8 applies recoil at the
## muzzle, and what decides whether that flips an Assembly is the muzzle's height
## above the centre of mass, because the fore-aft offset is parallel to the
## recoil and contributes no moment at all.
const GROUND_GUN := Vector3i(24, 8, 29)

## Stations under the two ends of the cabin, `x` 20–21 and 26–27 so each sits
## inboard of a flank, `z` 18–19 and 28–29.
const WHEEL_HUBS: Array[Vector3i] = [
	Vector3i(21, 2, 19), Vector3i(27, 2, 19), Vector3i(21, 2, 29), Vector3i(27, 2, 29)
]
## [b]The two flanks are square with each other now, and that is the small wheel
## rather than a repair.[/b] `mot.wheeled.allroad.t2` is four cells across, so its
## local extent runs -2..1 and is off-centre by one; mirroring it therefore
## shifted its world span by a cell, which is why `WHEEL_ORIGINS` used to carry a
## one-cell offset between flanks and a comment insisting it was not an
## off-by-one. `mot.wheeled.light_road.t1` is three across, -1..1, symmetric — so
## the mirror is exact and both flanks take the same `z`.
const WHEEL_ORIGINS: Array[Vector3i] = [
	Vector3i(18, 3, 19), Vector3i(18, 3, 29), Vector3i(29, 3, 19), Vector3i(29, 3, 29)
]
## Contacts forward of this row steer; the pair behind it is fixed. An Assembly
## on which every contact steers crabs instead of turning; see CHANGE_LOG.md, session 12.
const FRONT_AXLE_Z: int = 24

## --- The utility truck --------------------------------------------------
## `core.utility.hauler.t2` spans `x` 19–28, `y` 4–9 and `z` 14–33 — 2.50 m wide,
## 1.50 m tall, 5.00 m long. Deck at `y = 10`, underside at `y = 4`.
const UTILITY_CORE := Vector3i(24, 4, 24)
## The bonnet: `pmv.combustion.standard.t2` mated to the cab's `-Z` face at hull
## level, which puts a raised block forward of the crew box exactly where the
## reference has one. The square row rather than the flat one, deliberately —
## this vehicle wants its engine to read as a separate volume.
const UTILITY_POWER := Vector3i(24, 4, 11)
## The remote weapon station, on the roof at the cab's centre.
const UTILITY_GUN := Vector3i(24, 10, 26)
## `z` 16–17 and 30–31 puts the axles 3.50 m apart under a 6.50 m machine, which
## is 54% against the reference's 61%.
const UTILITY_HUBS: Array[Vector3i] = [
	Vector3i(20, 2, 17), Vector3i(28, 2, 17), Vector3i(20, 2, 31), Vector3i(28, 2, 31)
]
## The 1.00 m contacts, and here the one-cell flank offset [b]is[/b] required:
## these are the four-cell discs whose local extent is off-centre, so the right
## flank sits one forward of the left in order that both land on the same world
## `z`. See `WHEEL_ORIGINS` for why the road car needs no such thing.
const UTILITY_WHEEL_ORIGINS: Array[Vector3i] = [
	Vector3i(17, 3, 17), Vector3i(17, 3, 31), Vector3i(30, 3, 16), Vector3i(30, 3, 30)
]

## --- The tracked gun platform -------------------------------------------
## `core.tracked.hauler.t3` spans `x` 19–28, `y` 4–8 and `z` 12–35 — 2.50 m wide,
## 1.25 m tall, 6.00 m long. Deck at `y = 9`, underside at `y = 4`.
const TRACKED_CORE := Vector3i(24, 4, 24)
## The Prime Mover on the aft deck, behind the gun's breech.
const TRACKED_POWER := Vector3i(24, 9, 33)
## [b]`eff.ballistic.rifle_long.t3` is 6.00 m of gun and it is meant to overhang.[/b]
## Placed here its breech sits at `z` 25 — mid-hull — and its muzzle reaches `z` 2,
## which is 2.50 m past a nose at `z` 12. The reference's barrel overhangs its
## glacis by about 0.55 of hull length; this is 0.42 of it, short because the
## breech cannot go further aft without leaving the deck.
const TRACKED_GUN := Vector3i(24, 9, 25)
## One station per flank at the hull's centre. A bogie distributes its own load
## across six road stations along its patch (doc 01 §10.3), so what the mount
## carries is attachment and not weight distribution.
const TRACK_HUBS: Array[Vector3i] = [Vector3i(20, 2, 24), Vector3i(28, 2, 24)]
## [b]6.00 m of track under a 6.00 m hull, which is the whole repair.[/b] Both
## bogies span `z` 12–35 exactly — the hull's own length — where
## `mot.tracked.short_bogie.t2` ran 1.90 m under hulls of 3.25 m and then 2.25 m
## and the Assembly see-sawed on it. The right flank sits one cell aft because the
## bogie's 24-cell local extent runs -12..11 and is off-centre by one, the same
## arithmetic the utility truck's wheels need.
const TRACK_ORIGINS: Array[Vector3i] = [Vector3i(17, 3, 24), Vector3i(30, 3, 23)]

## --- The walking machine ------------------------------------------------
## `core.ambulatory.strider.t3` spans `x` 21–26, `y` 14–23 and `z` 19–28 —
## 1.50 m wide, 2.50 m tall, 2.50 m long. It sits high in the lattice because a
## limb hangs below its station and the lattice floor is at `y` = 0.
##
## Doc 01 §10.1 carries the argument for the section and, more importantly, for
## why it is not the humanoid reference's section: the reference is a biped whose
## torso is 1.85 times as tall as it is deep, and doc 05 §13's virtual leg has a
## point foot, so fore-and-aft foot separation is the only pitch stability this
## family has. Torso depth and stance base are the same ten cells.
const AMBULATORY_CORE := Vector3i(24, 14, 24)
## [b]Slung under the torso between the legs, centred on the stance.[/b] It went
## on the deck for forty-four sessions and then briefly onto the tail; both are
## 620 kg on a lever the gait has to hold, and the tail version measured 25.8° of
## nose-up stoop with all four contacts unloaded. Under the belly at `z` 24 the
## mass is on the stance's own centre and 1.00 m lower than the torso base, which
## is where a walking machine's power plant belongs and is the only mount in this
## layout that contributes no pitching moment at all.
##
## The limbs are at `x` 19–21 and 26–28, so a 4-cell-wide mover at 22–25 passes
## between them; its roof at `y` 13 mates to the torso's underside at `y` 14.
const AMBULATORY_POWER := Vector3i(24, 10, 24)
## [b]The Effector Module is shoulder-mounted, and that is the part table
## deciding rather than the layout.[/b] `eff.ballistic.autocannon_30.t3` carries
## exactly one attachment node — a `FACE_MALE` on its underside (doc 01 §10.5) —
## so it mounts downward onto a deck and nowhere else. On a torso this tall the
## only deck is the roof, which puts the barrel over the shoulder line. That is
## the humanoid reference's own arrangement and it is arrived at by the
## constraint rather than chosen: a chest-mounted module would need a `-Z` node
## the part does not have.
const AMBULATORY_GUN := Vector3i(24, 24, 26)
## Station, then the limb hanging off it, four times. A station at orientation 8
## puts its AXLE faces on ±Y, so it bolts to the torso's flank through a neutral
## face and offers a downward drive station.
##
## A station at orientation 8 spans `x[px..px+1]`, `y[py..py+1]`, `z[pz-1..pz]`.
## The torso's flanks are at `x` 21 and 26, so a station outboard of the left one
## starts at 19 and one outboard of the right starts at 27.
##
## [b]The hips are at the torso's two ends — `z` 20 and 28, 2.00 m apart — and
## that separation is the family's entire pitch stability.[/b]
##
## It was 1.50 m, held there through the first pass of the rebuild on the
## reasoning that moving the stance and the height together would leave nothing to
## attribute a change in the gait to. The measurement settled it: at 1.50 m under
## a torso that had gone from 1.00 m to 2.50 m of height and a hip from 1.63 m to
## 2.24 m, the walking recipe stooped 25.8° with all four contacts unloaded and
## the melee one went past 45°. Doc 05 §13's virtual leg has a point foot, so
## there is no other term available: the base is the whole of it, and a taller
## machine on the same base is a longer lever on the same fulcrum.
##
## Two metres is what the chassis has. The stations are on its two ends and there
## is nowhere further for them to go without hanging a hip off nothing.
const AMBULATORY_LEGS: Array[Vector3i] = [
	Vector3i(19, 14, 20), Vector3i(20, 13, 20),
	Vector3i(27, 14, 20), Vector3i(27, 13, 20),
	Vector3i(19, 14, 28), Vector3i(20, 13, 28),
	Vector3i(27, 14, 28), Vector3i(27, 13, 28),
]
const HUB_AXLE_DOWN_ORIENTATION: int = 8

## --- The biped ----------------------------------------------------------
## `core.biped.humanoid.t3` spans `x` 21–26, `y` 14–23 and `z` 22–26 — 1.50 m
## wide, 2.50 m tall, 1.25 m long. Half the strider's depth, and the same height.
const BIPED_CORE := Vector3i(24, 14, 24)
## Under the torso between the legs, exactly as on the quadruped and for the same
## reason: it is the one mount in the layout that contributes no pitching moment,
## and on a machine balancing over a 0.60 m foot that matters more than it does on
## one standing on a 2.00 m base.
const BIPED_POWER := Vector3i(24, 10, 24)
## Shoulder-mounted, because `eff.ballistic.autocannon_30.t3` carries one
## attachment node and it is on its underside. See
## [constant AMBULATORY_GUN].
const BIPED_GUN := Vector3i(24, 24, 26)
## [b]Station, then the limb hanging off it — twice, and both at the same `z`.[/b]
## That is what makes it a biped and it is the line that would have been a bug
## before §13.10: two feet side by side have a fore-and-aft stance base of
## [i]zero[/i], so every newton-metre of pitch stability this machine has comes
## from the ankle torque its support polygon allows.
##
## The hips are at `z` 24, on the torso's centre, so the machine stands over its
## own feet rather than ahead of or behind them.
const BIPED_LEGS: Array[Vector3i] = [
	Vector3i(19, 14, 24), Vector3i(20, 13, 24),
	Vector3i(27, 14, 24), Vector3i(27, 13, 24),
]

## [b]The shoulder brackets the arms hang from, at the shoulder line rather than
## over the head.[/b]
##
## An Appendage mates through its own `+Y` face and through nothing else (doc 01
## §10.6 keeps every other face bare so an arm cannot be stacked into a ladder of
## brackets), so an arm that hangs beside a torso needs something directly
## [i]above[/i] it — and the torso's flank is beside it, not over it.
## `str.outrigger.pylon.t2` mated to the flank and standing entirely outboard of
## it is a 0.75 x 0.50 x 0.50 m block the arm can bolt under: a shoulder joint,
## which is what the part is for. It was `str.panel.medium.t2`, and a 4x1x4 plate
## either side of the head read as a pair of shelves.
##
## [b]`y` 21 and not 24, and that is the difference between a machine and a
## coat stand.[/b] The plates were first laid on the roof line, which is the only
## place a bracket overhanging the deck can go — and that put the shoulders
## [i]above the head[/i] and the hands at chest height. A human's shoulder line is
## about 0.82 of standing height and the fingertips about 0.45; on a torso
## spanning `y` 14–23 over feet at `y` 2.6 those are `y` 20 and `y` 12. The plate
## at 21 puts the pauldron's top at 20 and the hand at 13, which is the hip.
##
## `x` 19 and 28 put the blocks at `x` 18–20 and 27–29, exactly the columns the
## arms hang in, outboard of a torso spanning 21–26 and mating to its flanks.
const BIPED_SHOULDERS: Array[Vector3i] = [Vector3i(19, 21, 22), Vector3i(28, 21, 22)]

## [b]Two arms hanging down the flanks, hand at the hip, clear of the ground and
## clear of the legs.[/b]
##
## The arm is authored along its own `-Y` — the shoulder is the top cell and the
## hand the bottom — so orientation 0 is the hanging pose and needs no rotation at
## all. Eight cells is 2.00 m of arm on a machine standing 5.22 m, which is very
## nearly the 1.86 m a human's shoulder-to-fingertip works out at for that height,
## and hanging from `y` 20 it puts the hand at `y` 13 against hips at 13. That is
## the proportion; LEARNED_FACTS.md fact 104 records what it costs, which is that
## there is no elbow and anything held continues straight down.
##
## [b]They hang forward of the hip line and that is the only place they fit.[/b]
## `z` 20–22 against limbs at 23–25: at the height a human hand reaches, the arm
## is level with the hip housing and the thigh, and an arm sharing that column is
## refused by the occupancy before anything about the pose is considered.
const BIPED_ARMS: Array[Vector3i] = [Vector3i(19, 20, 21), Vector3i(28, 20, 21)]

## [b]Nothing in the hands, and that is what makes it read as a person.[/b]
##
## An edge mates hilt-upward under a hanging hand — the hand's GRIP face points
## down, so the blade runs down from it and there is nowhere else for it to go
## (fact 104). At the hand's old chest height that left the blades hanging beside
## the knees, which is what made the machine read as having enormously long arms;
## at the hand's *correct* height the same blade reaches within half a metre of
## the floor, which is worse.
##
## So the shipped biped stands with its hands empty and its arms at its sides, and
## the held edge is demonstrated by [constant Recipe.MELEE], whose arms run
## forward and whose blades therefore point where a sword is useful. Holding one
## on this recipe is a cell list and no new architecture — the hand is there, the
## mate is legal, and `tests/physics/test_biped_balance.gd` records what it costs
## — but it is not the pose a humanoid stands in.
const BIPED_EDGES: Array[Vector3i] = []

## [b]The backpack, and it is ballast before it is supply.[/b]
##
## Two arms and two edges are 1754 kg hung three cells forward of the hip line,
## which took the centre of mass 0.21 m ahead of the feet — inside doc 05 §13.10's
## 0.30 m ankle bound on paper and not in practice, because the spawn transient
## spends the margin the static case leaves. `cel.static.standard.t3` mated to the
## torso's `-Z`... rear face at `z` 27–31 is 450 kg at 1.25 m aft, which is very
## nearly the moment the arms put forward.
##
## It is also 460 PU of reserve against two edges that draw 145 apiece when they
## are energised, so the part that balances the machine is the part that powers
## what unbalanced it.
const BIPED_BACKPACK := Vector3i(24, 17, 29)

## [constant Recipe.MELEE]'s two Appendages and the edge in each hand, one per
## flank, derived from the ambulatory Core Module's own extents rather than
## guessed.
##
## [b]The arms are at the sides and they run forward, and only one of those two
## was a choice.[/b] An Appendage's cells extend from its shoulder along the axis
## the shoulder faces, and the module in its hand continues along that same axis —
## there is no elbow, because Invariant I-3 admits no joint between parts. So an
## arm hung off a flank at right angles is a machine in a T-pose with its blades
## pointing at the scenery, and an arm hung [i]downward[/i] beside the torso —
## which is the human pose — points its blade at the ground, where the mount's
## authored −20°/+40° of pitch can never recover it. Measured across all
## twenty-four orientations before it was written down.
##
## What is left, and what a humanoid actually reads as at a glance, is a shoulder
## at each front corner with the arm running forward alongside the torso. The
## torso spans `x` 21–26 and `z` 19–28, so a shoulder patch centred on `x` 20 or
## `x` 27 sits just outboard of a flank and mates through the corner cells of the
## torso's `-Z` face. `y = 21` is high on a torso that now runs to 23, so the
## shoulders sit above the hips at 14 and the arms swing clear of the limbs below.
const MELEE_ARMS: Array[Vector3i] = [Vector3i(20, 21, 18), Vector3i(27, 21, 18)]
## The hand is seven cells out along the arm and faces `-Z`; the edge's hilt is
## its own `+Z` face, so each blade goes in unrotated in the cell the hand points
## into and its eight cells continue forward.
const MELEE_EDGES: Array[Vector3i] = [Vector3i(20, 21, 10), Vector3i(27, 21, 10)]

## --- The rotorcraft -----------------------------------------------------
## `core.rotary.lifter.t3` spans `x` 22–25, `y` 4–9 and `z` 10–37 — 1.00 m wide,
## 1.50 m deep, 7.00 m long. Deck at `y = 10`, underside at `y = 4`.
##
## A disc's own AXLE face is its [b]underside[/b], where a wheel's and a track's
## is their `-Z` flank and a limb's is its top, so a mast needs a station under
## it exactly as a limb needs one over it. And an AXLE station's two drive faces
## are opposite each other, so a station cannot bolt on through one and offer
## the other — it attaches through a neutral flank and both drive faces stay
## free (doc 01 §4.2). That is why the stations here go on the fuselage's
## [i]sides[/i] at orientation 8, which puts their AXLE faces on ±Y, and not on
## its spine where the underside would be a drive face with nothing to drive.
##
## Two discs, not one, and that falls straight out of the geometry: a station on
## a flank carries its mast off the centreline, and a single disc there rolls the
## Assembly over. The pair is symmetric and doubles the lift.
const ROTARY_CORE := Vector3i(24, 4, 24)
## [b]The Prime Mover goes under the belly and the Energy Cell on the deck, which
## is the reverse of every other recipe here and is arithmetic rather than
## taste.[/b] A mass hung in the tail drags the solved centre of mass aft of the
## disc line, and trimming that offset out costs swashplate the Assembly then has
## none of left to fly with — measured in session 34 at 0.31 m of offset asking
## for 23° of a 14° cone, with the Assembly going over during the settle. Under
## the belly the 620 kg contributes nothing fore or aft and lowers the centre of
## mass; the lighter Energy Cell on the aft deck leaves a residual the cone can
## hold.
const ROTARY_POWER := Vector3i(24, 0, 24)
## On the aft deck, where the Prime Mover sits on every other recipe. See
## [constant ROTARY_POWER] for why the two are the other way round here.
const ROTARY_CELL := Vector3i(24, 10, 32)
## In the chin position, forward on the deck — where the reference carries its
## turret, and as far as this fuselage allows from the discs it must not foul.
const ROTARY_GUN := Vector3i(24, 10, 16)
## [b]A pylon, then the station, then the disc — and the pylon is the whole
## reason the pair reads as two rotors.[/b] §4.2 makes an AXLE station attach
## through a neutral flank so both drive faces stay free, so a mast station sits
## hard against the hull; on a 1.00 m fuselage that put the two disc centres
## 2.00 m apart under 4.00 m discs, overlapping by half a diameter. Three cells
## of `str.outrigger.pylon.t2` each side takes the separation to 3.00 m and the
## overlap to a quarter, which is about what the reference carries.
##
## The chain outboard from the fuselage's `x` 22..25: pylon 19..21, station
## 17..18, disc centred on 17.5 — and mirrored, pylon 26..28, station 29..30,
## disc centred on 29.5.
const ROTARY_PYLONS: Array[Vector3i] = [Vector3i(20, 5, 24), Vector3i(27, 5, 24)]
const ROTARY_MAST_HUBS: Array[Vector3i] = [Vector3i(17, 5, 24), Vector3i(29, 5, 24)]
const ROTARY_DISCS: Array[Vector3i] = [Vector3i(18, 7, 24), Vector3i(30, 7, 24)]

## ===== FIXTURE =========================================================

const GROUND_HALF_HEIGHT: float = 2.0
const GROUND_SPAN_M: float = 900.0
## Height a ground recipe is dropped from, above the slab surface.
const DROP_HEIGHT_M: float = 2.0
## Body-origin height the ambulatory recipe spawns at, and it is [b]below[/b] the
## slab, which is not a mistake. An Assembly's origin is its lattice origin, and
## on this build that point sits two and a half metres up inside the machine: it
## stands with its body origin at about −0.81. Spawning it at +4 was a five-metre
## drop onto its own feet, and it spent the whole settle bouncing.
##
## Just high enough that the probes cannot see the ground at spawn, so the
## Assembly falls the last few centimetres onto its springs rather than being
## placed inside them.
##
## It was −0.40 and it moved with the limb. `mot.limb.strider.t4` reaches 2.60 m
## now rather than 1.90, and the hip sits nine cells — 2.25 m — above the body
## origin, so a stance height of 0.86 × 2.60 = 2.24 m leaves the origin at about
## −0.01 m at rest where it used to sit at −0.62. Spawning at the old figure put
## the Assembly below its own standing height with its legs already through the
## floor, and it reported four unloaded contacts and a body that sank: the
## failure mode of a spawn height is not a bounce, it is a machine that never
## finds the ground at all.
const AMBULATORY_DROP_HEIGHT_M: float = 0.25

## ===== PILOT ===========================================================
## Doc 05 §6.0's [ControlInput] is the whole interface. Every gain below turns
## world state into one of its eight numbers and nothing else.
##
## [b]The ground tactic is not here any more.[/b] Doc 05 §15.7 gave it an owner:
## the steering demands, the stand-offs and the ambulatory yaw damping are
## [AiDriver]'s constants and statics, and this fixture calls them. Nothing about
## the arithmetic changed — the arena still runs its own command loop over five
## recipes and still decides its own targets per tick, because an engagement test
## measures a fight rather than a scan interval — but a gain now has one value in
## one place, and a change to how a bot drives cannot leave the two disagreeing.
##
## What is still a fixture is [method _fly]. §15.7.3 records why: holding a hover
## is a stability-augmentation layer a [b]player[/b] flying a rotary build would
## need too, and putting it in [AiDriver] would give a bot flight a person cannot
## have. Until that layer exists it lives here and is named as a stand-in.

## Degrees within an authored pitch limit that count as sitting on the stop.
const ELEVATION_STOP_EPSILON_DEG: float = 0.05
## Metres per second a rotary recipe closes at.
const ROTARY_APPROACH_MPS: float = 8.0
## Height above the slab a rotary recipe holds.
const HOVER_HEIGHT_M: float = 4.0
## Collective demand per metre of altitude error, and per metre per second of
## climb rate. The second term is the damper; without it the disc chases the
## altitude and the Assembly porpoises.
const HOVER_HEIGHT_GAIN: float = 0.55
const HOVER_CLIMB_GAIN: float = 0.45
## Horizontal acceleration demanded per metre per second of velocity error.
const CYCLIC_VELOCITY_GAIN: float = 1.2
## Ceiling on that demand. `g · tan(12°)` — inside the 14° swashplate cone, so
## the controller never asks for a tilt [RotorSolver] will clamp away underneath
## it and then integrate a demand it never met.
const CYCLIC_ACCEL_LIMIT_MPS2: float = 2.08
## Pedal demand per radian of heading error, and per radian per second of yaw.
const YAW_HEADING_GAIN: float = 0.6
const YAW_RATE_GAIN: float = 0.5

## Range [constant Recipe.MELEE] stops closing at, in metres.
##
## Zero, which is to say [b]never stop closing[/b]: doc 07 §15.5 pays per tick of
## contact, and a driver that arrives, strikes, and drifts back off the blade
## collects one strike. The thing that stops this build is its own edge running
## into the other hull.
##
## [b]It is the fixture's and not [AiDriver]'s, deliberately.[/b] Doc 05 §15.7.1's
## table is a stand-off per locomotion family, and a contact stand-off is not a
## property of how an Assembly gets around — it is a property of how far its
## Effector Module reaches. Putting a fifth row in that table would say the
## opposite. The day a driver picks its stand-off from the module it is carrying,
## this constant moves there and this comment is the reason it did.
const MELEE_STAND_OFF_M: float = 0.0

var registry: AssemblyRegistry = null
var resolver: DamageResolver = null
var projectiles: ProjectileSystem = null
var projectile_registry: ProjectileRegistry = null
var ammo: AmmoLedger = null
var combatants: Array[Combatant] = []
## Assembly id -> team, for every Assembly the arena has spawned. Doc 07 §10.1's
## roster, kept as one dictionary and handed to every [AiDriver] by reference so
## that a driver attached before its opponents exist sees them when it scans.
var roster: Dictionary = {}

## Every `part_destroyed` seen, in order, as (assembly_id, slot).
var destroyed: Array[Vector2i] = []
## Assembly ids that lost slot 0, in the order they fell. Invariant I-2 makes
## that the end of an Assembly; the match layer that should say so does not
## exist yet, so the arena reads the raw signal and calls it a kill.
var terminated: PackedInt32Array = PackedInt32Array()
## Every band transition seen, in order, as (assembly_id, slot, band after).
## Invariant I-5's five bands are only observable through this signal; a Core
## Module that went from NOMINAL to DESTROYED in one packet would satisfy every
## other assertion in a fight and would mean the band machinery never ran.
var band_events: Array[Vector3i] = []
## Rounds emitted across the whole engagement.
var shots_fired: int = 0
## assembly_id -> rounds it emitted.
var shots_by: Dictionary = {}
## Terminated assembly_id -> the id doc 04 §8.2 attributes the kill to.
var kills: Dictionary = {}
## Damage packets that landed, and assembly_id -> total integrity taken off it.
## A fight can be lost by every round missing, and shots alone cannot tell that
## apart from a fight where every round landed on armour that soaked it.
var hits_landed: int = 0
var damage_by_target: Dictionary = {}
## assembly_id -> integrity taken off it per [enum PartEnums.DamageChannel].
##
## The totals above cannot tell gunfire from a collision, and once a driver
## closes to its stand-off it is parked among wreckage and taking a little of
## the second. An assertion that means "nothing shot at it" has to say KINETIC.
var damage_by_channel: Dictionary = {}
## Ticks the last call to [method engage] actually ran for.
var ticks_engaged: int = 0
## Most rounds in flight at once during it. Sampled inside the loop, because the
## pool drains as rounds land and a count taken after the last tick says nothing
## about how full it ever got.
var peak_in_flight: int = 0
## What happened, in order, in plain words: "t=  74  KESTREL loses its Prime
## Mover to ASHFORD". Written for a human reading the run, and the only reason
## an account of one of these engagements can be checked against it.
var timeline: PackedStringArray = PackedStringArray()

var _ground: StaticBody3D = null
var _contexts: Array[BuildContext] = []
var _next_assembly_id: int = 1
var _round_id: int = -1
var _repeater_round_id: int = -1
var _cannon_round_id: int = -1
## Ticks since [method engage] opened, for stamping the timeline.
var _clock: int = 0

## Part class -> what to call it in the timeline.
const PART_CLASS_NAMES: Dictionary = {
	PartEnums.PartClass.CORE_MODULE: "its Core Module",
	PartEnums.PartClass.STRUCTURAL_COMPONENT: "a Structural Component",
	PartEnums.PartClass.MOTIVE_ASSEMBLY: "a Motive Assembly",
	PartEnums.PartClass.PRIME_MOVER: "its Prime Mover",
	PartEnums.PartClass.EFFECTOR_MODULE: "its Effector Module",
	PartEnums.PartClass.SUPPORT_MODULE: "a Support Module",
	PartEnums.PartClass.CONTROL_SURFACE: "a Control Surface",
	PartEnums.PartClass.ENERGY_CELL: "its Energy Cell",
	PartEnums.PartClass.APPENDAGE: "an Appendage",
}


## ===== SETUP ===========================================================


## Builds the slab and the four systems every Assembly in the arena shares.
func open() -> void:
	registry = AssemblyRegistry.new()
	ammo = AmmoLedger.new()
	projectile_registry = ProjectileRegistry.new()
	projectile_registry.register(load("res://data/projectiles/%s.tres" % ROUND_KEY))
	projectile_registry.register(load("res://data/projectiles/%s.tres" % REPEATER_ROUND_KEY))
	projectile_registry.register(load("res://data/projectiles/%s.tres" % CANNON_ROUND_KEY))
	projectile_registry.seal()
	_round_id = projectile_registry.id_of(ROUND_KEY)
	_repeater_round_id = projectile_registry.id_of(REPEATER_ROUND_KEY)
	_cannon_round_id = projectile_registry.id_of(CANNON_ROUND_KEY)

	_ground = StaticBody3D.new()
	_ground.name = "GroundFixture"
	_ground.collision_layer = CollisionLayers.LAYER_GROUND
	_ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SPAN_M, GROUND_HALF_HEIGHT * 2.0, GROUND_SPAN_M)
	shape.shape = box
	_ground.add_child(shape)
	EventBus.get_tree().root.add_child(_ground)
	_ground.global_position = Vector3(0.0, -GROUND_HALF_HEIGHT, 0.0)

	var world := _ground.get_world_3d()

	resolver = DamageResolver.new()
	resolver.registry = registry
	resolver.space = world.direct_space_state
	EventBus.get_tree().root.add_child(resolver)

	projectiles = ProjectileSystem.new()
	projectiles.registry = projectile_registry
	projectiles.resolver = resolver
	projectiles.space = world.direct_space_state
	EventBus.get_tree().root.add_child(projectiles)

	EventBus.part_destroyed.connect(_on_part_destroyed)
	EventBus.effector_fired.connect(_on_effector_fired)
	EventBus.part_band_changed.connect(_on_part_band_changed)
	EventBus.part_damaged.connect(_on_part_damaged)
	EventBus.assembly_terminated.connect(_on_assembly_terminated)


## Frees everything the arena put in the tree. Call from `after_all`; a leaked
## runtime stays connected to the bus and resolves the next file's fixture
## underneath it.
func close() -> void:
	if EventBus.part_destroyed.is_connected(_on_part_destroyed):
		EventBus.part_destroyed.disconnect(_on_part_destroyed)
	if EventBus.effector_fired.is_connected(_on_effector_fired):
		EventBus.effector_fired.disconnect(_on_effector_fired)
	if EventBus.part_band_changed.is_connected(_on_part_band_changed):
		EventBus.part_band_changed.disconnect(_on_part_band_changed)
	if EventBus.part_damaged.is_connected(_on_part_damaged):
		EventBus.part_damaged.disconnect(_on_part_damaged)
	if EventBus.assembly_terminated.is_connected(_on_assembly_terminated):
		EventBus.assembly_terminated.disconnect(_on_assembly_terminated)
	for c: Combatant in combatants:
		if c.runtime != null and is_instance_valid(c.runtime):
			c.runtime.free()
	combatants.clear()
	for node: Node in [projectiles, resolver, _ground] as Array[Node]:
		if node != null and is_instance_valid(node):
			node.free()
	for ctx: BuildContext in _contexts:
		ctx.dispose()
	_contexts.clear()


## Builds one Assembly of [param recipe] on [param team], facing [param yaw_rad]
## about the world up, at [param ground_xz] on the slab.
##
## [param rounds] is the store it is given; [constant AmmoLedger.UNLIMITED] is
## accepted and 0 makes an Assembly that aims, tracks, and cannot shoot — the
## asymmetry [code]test_duel.gd[/code] uses to get a decided outcome out of two
## identical builds.
func spawn(
	recipe: int, team: int, ground_xz: Vector2, yaw_rad: float, rounds: int
) -> Combatant:
	var assembly_id := _next_assembly_id
	_next_assembly_id += 1
	roster[assembly_id] = team

	var ctx := BuildContext.with_physics(assembly_id)
	_contexts.append(ctx)
	lay_out(ctx, recipe)

	var runtime := AssemblyRuntime.new()
	runtime.name = "Assembly%d" % assembly_id
	EventBus.get_tree().root.add_child(runtime)
	runtime.adopt(ctx)
	runtime.apply_mass_properties(MassSolver.compute(runtime.states, runtime.graph))
	registry.register(runtime)

	var motion := MotiveSystem.new()
	motion.runtime = runtime
	motion.input = ControlInput.new()
	motion.power = PowerSystem.new()
	motion.power.recompute(runtime.states, runtime.graph.alive)
	runtime.add_child(motion)

	var guns := EffectorSystem.new()
	guns.runtime = runtime
	guns.projectiles = projectiles
	guns.registry = projectile_registry
	guns.ammo = ammo
	# Doc 07 §15.3 resolves a melee strike by querying a space and handing the
	# packets straight to the resolver, so a melee module needs both of these and
	# direct fire needs neither. Omitting them is silent: `_sweep_edge` returns on
	# a null space, the stage machine goes on cycling, and the edge swings through
	# everything for the whole match. Session 18 found them missing here after
	# landing the sweep, which means anything written from this reference would
	# have shipped a sword that does nothing.
	guns.resolver = resolver
	# The resolver's own space rather than a second lookup, so §15.3's sweep and
	# doc 08 §5.3's blast query cannot end up asking different worlds.
	guns.space = resolver.space
	# Invariant I-9. Two Assemblies in one match must not roll their spread and
	# jam in lockstep, and the same match must replay identically.
	guns.seed_rng(assembly_id)
	runtime.add_child(guns)

	var c := Combatant.new()
	c.recipe = recipe
	c.team = team
	c.callsign = CALLSIGNS[(assembly_id - 1) % CALLSIGNS.size()]
	c.runtime = runtime
	c.motion = motion
	c.guns = guns
	c.stand_off_m = AiDriver.GROUND_STAND_OFF_M
	if recipe == Recipe.ROTARY:
		c.stand_off_m = AiDriver.ROTARY_STAND_OFF_M
	elif recipe == Recipe.AMBULATORY or recipe == Recipe.AMBULATORY_BARE:
		c.stand_off_m = AiDriver.AMBULATORY_STAND_OFF_M
	elif recipe == Recipe.MELEE:
		c.stand_off_m = MELEE_STAND_OFF_M

	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var def := runtime.definition_at(slot)
		if def == null:
			continue
		if def.part_class == PartEnums.PartClass.MOTIVE_ASSEMBLY:
			motion.register(slot, def, runtime.states[slot])
		elif def.part_class == PartEnums.PartClass.EFFECTOR_MODULE:
			guns.register(slot, def)
			c.gun_slot = slot
	motion.reassign_gait_phases()

	var height := DROP_HEIGHT_M
	if is_ambulatory(recipe):
		height = AMBULATORY_DROP_HEIGHT_M
	elif recipe == Recipe.ROTARY:
		height = HOVER_HEIGHT_M
	runtime.body.global_transform = Transform3D(
		Basis.from_euler(Vector3(0.0, yaw_rad, 0.0)),
		Vector3(ground_xz.x, height, ground_xz.y)
	)
	if recipe == Recipe.ROTARY:
		# §9's convention: set the state, do not wait for it. Spooling a disc to
		# 85 rad/s through a 2.4 s time constant is ten simulated seconds of
		# nothing happening, and the spool is [RotorSolver]'s to assert.
		for slot: int in motion.motive_slots():
			var disc := motion.disc_state(slot)
			if disc != null:
				disc.omega_rad_s = _definition(runtime, slot).motive_profile \
					.rotor_profile.nominal_rad_s

	if rounds != 0:
		# Both types, to every Assembly. A store is held per projectile type per
		# Assembly (doc 07 §13), so granting the one a recipe does not fire costs
		# a dictionary entry and saves every caller having to know which round the
		# recipe it asked for happens to chamber.
		ammo.add(assembly_id, _round_id, rounds)
		ammo.add(assembly_id, _repeater_round_id, rounds)
		ammo.add(assembly_id, _cannon_round_id, rounds)
	combatants.append(c)
	return c


## Places [param recipe]'s parts into [param ctx], and nothing else.
##
## Split out of [method spawn] so that a caller who wants the [i]cells[/i] of a
## recipe does not have to build a rigid body and a space to see them —
## `tests/unit/test_family_presets.gd` compares every shipped
## [StarterBlueprint] preset against the recipe of the same name, and that is a
## question about a cell list rather than about a machine.
func lay_out(ctx: BuildContext, recipe: int) -> void:
	match recipe:
		Recipe.WHEELED_LIGHT:
			_lay_out_wheeled(ctx, false, GUN_KEY)
		Recipe.WHEELED_HEAVY:
			_lay_out_wheeled(ctx, true, GUN_KEY)
		Recipe.WHEELED_REPEATER:
			_lay_out_wheeled(ctx, false, REPEATER_KEY)
		Recipe.WHEELED_UTILITY:
			_lay_out_utility(ctx)
		Recipe.BIPED:
			_lay_out_biped(ctx)
		Recipe.MELEE:
			_lay_out_melee(ctx)
		Recipe.TRACKED:
			_lay_out_tracked(ctx)
		Recipe.AMBULATORY:
			_lay_out_ambulatory(ctx, true)
		Recipe.AMBULATORY_BARE:
			_lay_out_ambulatory(ctx, false)
		Recipe.ROTARY:
			_lay_out_rotary(ctx)
		_:
			push_error("CombatArena: unknown recipe %d" % recipe)


## ===== RUNNING =========================================================


## Lets everything fall onto its contacts, or a rotary Assembly find its hover,
## with the triggers cold. Physics tests cost real wall time at 60 Hz, so this
## is the shortest settle that leaves nothing still moving.
func settle(ticks: int) -> void:
	for c: Combatant in combatants:
		if c.recipe == Recipe.ROTARY:
			# A hovering Assembly has to be flown even while it settles, or it
			# is a 1.2 t brick falling five metres onto the slab.
			continue
		c.motion.input.throttle = 0.0
		c.motion.input.steer = 0.0
	for i: int in ticks:
		for c: Combatant in combatants:
			if c.recipe == Recipe.ROTARY:
				_fly(c, c.runtime.body.global_position)
		await _tick()


## Runs the engagement for at most [param max_ticks], commanding every live
## combatant once per tick and stopping early when only one team is left
## standing.
##
## Returns when the fight is over. [member ticks_engaged] is how long it took.
func engage(max_ticks: int) -> void:
	ticks_engaged = 0
	peak_in_flight = 0
	_clock = 0
	for i: int in max_ticks:
		await tick_once()
		if teams_standing().size() <= 1:
			break
	stand_down()


## One commanded tick, and the whole of what [method engage] does per iteration.
##
## Public because a fixture whose subject is a [i]per-tick[/i] law cannot use
## [method engage]: doc 07 §15.5 pays per tick of contact and the stage machine
## that decides whether there is any is only readable between physics frames.
## Calling [method engage] with one tick at a time would work and would restart
## [member _clock] on every call, so the timeline every engagement here is read
## through would stamp the whole fight at t=0.
## One physics tick with nothing commanded and the inputs left exactly as the
## caller set them.
##
## [b]Neither of the other two step helpers can hold a demand across a window.[/b]
## [method settle] zeroes throttle and steer on every combatant before it steps —
## it is the "put it down and leave it alone" helper — and [method tick_once]
## overwrites them with [method command]'s decisions. A fixture measuring what a
## *given* demand does therefore needs a third, and its absence presents as two
## runs reporting byte-identical displacement for opposite throttles, which reads
## exactly like a locomotion family ignoring its own input.
func step_once() -> void:
	_clock += 1
	await _tick()


func tick_once() -> void:
	_clock += 1
	for c: Combatant in combatants:
		command(c)
	await _tick()
	ticks_engaged += 1
	peak_in_flight = maxi(peak_in_flight, projectiles.active_count())


## Drops every trigger and centres every control. [method engage] ends with this;
## a fixture running its own loop over [method tick_once] must call it, or the
## Assemblies go on driving into whatever is measured next.
func stand_down() -> void:
	for c: Combatant in combatants:
		c.guns.set_trigger(0, false)
		c.motion.input.throttle = 0.0
		c.motion.input.steer = 0.0
		c.motion.input.collective = 0.0
		c.motion.input.cyclic = Vector2.ZERO
		c.motion.input.yaw = 0.0


## One combatant's tick: pick a target, point the gun at it, hold the trigger,
## and drive.
##
## The target is the nearest live enemy, which is the whole of the tactics. A
## cleverer rule would be making claims about a target selector doc 07 §10 has
## not been written yet, and the point of these fights is the physics under the
## decision rather than the decision.
func command(c: Combatant) -> void:
	var target := nearest_enemy(c)
	c.sample_hull(target)
	if not c.arena_piloted:
		# Either an [AiDriver] is writing this Assembly's record on
		# `MatchClock.tick_started` — see [method make_autonomous] — or it is a
		# parked target with nothing driving it at all. Either way the pilot below
		# must keep its hands off it, or the two producers fight over one
		# [ControlInput] and whichever ran last wins.
		c.sample_gunnery()
		return
	if not c.is_alive():
		c.retire()
		return
	if target == null:
		c.retire()
		return

	var aim := target.runtime.part_world_position(SyndicateConstants.CORE_SLOT)
	c.guns.aim_point_world = aim
	c.guns.set_trigger(0, true)
	c.sample_gunnery()
	if c.recipe == Recipe.ROTARY:
		_fly(c, aim)
	else:
		_drive(c, aim)


## Hands [param c] over to doc 05 §15.7's [AiDriver] and takes the test pilot off
## it. Returns the driver, so a test can read what it chose.
##
## This is the one route by which [code]src/ai/[/code] gets into an engagement
## test, and it is deliberately opt-in: the five recipes' measured behaviour in
## [code]test_family_duels.gd[/code] and [code]test_team_engagement.gd[/code] is
## a record of what [method command]'s pilot does, and switching those files onto
## a driver with a 2.9 Hz scan interval would silently re-measure every one of
## them.
##
## Everything is set before [method Node.add_child], because [AiDriver] caches
## its family, stand-off, RNG seed and scan phase on entering the tree.
func make_autonomous(c: Combatant, difficulty: float) -> AiDriver:
	var driver := AiDriver.new()
	driver.name = "AiDriver"
	driver.runtime = c.runtime
	driver.input = c.motion.input
	driver.motion = c.motion
	driver.guns = c.guns
	driver.effector_slot = c.gun_slot
	driver.registry = registry
	driver.roster = roster
	driver.difficulty = difficulty
	c.arena_piloted = false
	c.runtime.add_child(driver)
	return driver


## The nearest live enemy of [param c], or null when none is left.
func nearest_enemy(c: Combatant) -> Combatant:
	var best: Combatant = null
	var best_d := INF
	var from := c.runtime.body.global_position
	for other: Combatant in combatants:
		if other.team == c.team or not other.is_alive():
			continue
		var d := from.distance_squared_to(other.runtime.body.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best


## Teams with at least one live Assembly, ascending.
func teams_standing() -> PackedInt32Array:
	var out := PackedInt32Array()
	for c: Combatant in combatants:
		if c.is_alive() and not out.has(c.team):
			out.append(c.team)
	out.sort()
	return out


## Live combatants on [param team].
func survivors(team: int) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in combatants:
		if c.team == team and c.is_alive():
			out.append(c)
	return out


## ===== PRIVATE =========================================================


func _tick() -> void:
	await (Engine.get_main_loop() as SceneTree).physics_frame


## Ground families: close on the target and, for anything that steers, turn onto
## the bearing first.
func _drive(c: Combatant, aim: Vector3) -> void:
	var body := c.runtime.body
	var flat := aim - body.global_position
	flat.y = 0.0
	var input := c.motion.input
	input.brake = 0.0
	if flat.length_squared() < SyndicateConstants.EPSILON_LINEAR:
		input.throttle = 0.0
		input.steer = 0.0
		return

	# Doc 05 §15.7.1's law, through the class that owns it. The sign convention —
	# positive steer is right, and a right turn is a negative rotation about the
	# world up — lives in [method AiDriver.steer_demand] with the assertion that
	# defends it.
	var bearing := AiDriver.bearing_to(body.global_transform.basis, flat)
	input.throttle = 1.0 if flat.length() > c.stand_off_m else 0.0
	if is_ambulatory(c.recipe):
		input.steer = AiDriver.ambulatory_steer_demand(bearing, body.angular_velocity.y)
		return
	input.steer = AiDriver.steer_demand(bearing)


## The rotary family, and the one piece of this fixture that is a controller
## rather than a stand-in for a key.
##
## An Assembly held up by thrust alone cannot be driven by a throttle and a
## steer: the disc is not attached to anything, so a demand has to be resolved
## into a [i]world-space thrust direction[/i] and then back out into the swash
## angles that produce it from whatever attitude the body happens to be in. That
## last step is what makes it stable — the cyclic demand carries the body's own
## tilt in it, so a gust, a recoil impulse, or a shot-off part is corrected by
## the same arithmetic that holds the hover.
##
## Three loops, all through [ControlInput] and none of them applying a force:
## collective on altitude, cyclic on horizontal velocity, pedal on heading.
## Flies [param c] toward [param aim] with the autopilot below, for a test that
## needs a rotary build moving and does not want the whole command loop.
##
## Public because a rotary Assembly cannot hold a hover on its own — doc 05
## §15.7.3's augmentation layer does not exist — so any fixture that wants one in
## the air has to borrow this, and two copies of a three-loop autopilot is two
## things to keep true.
func fly_toward(c: Combatant, aim: Vector3) -> void:
	_fly(c, aim)


## Holds [param c]'s altitude and [b]nothing else[/b]: throttle and collective,
## with the cyclic and the pedals left alone.
##
## The one loop a fixture measuring doc 05 §12.8's arrest must keep, and the two
## it must not. §12.8 adds into `input.cyclic`, so an autopilot writing that field
## would be measuring itself; the collective is orthogonal to it and without it the
## Assembly is a brick.
func hold_altitude(c: Combatant) -> void:
	var body := c.runtime.body
	c.motion.input.throttle = 1.0
	c.motion.input.collective = clampf(
		(HOVER_HEIGHT_M - body.global_position.y) * HOVER_HEIGHT_GAIN
		- body.linear_velocity.y * HOVER_CLIMB_GAIN,
		-1.0,
		1.0
	)


func _fly(c: Combatant, aim: Vector3) -> void:
	var body := c.runtime.body
	var input := c.motion.input
	# A disc only turns under throttle (doc 05 §12.2), so the rotary family flies
	# with the throttle open and modulates lift with the collective.
	input.throttle = 1.0

	var velocity := body.linear_velocity
	var altitude_error := (HOVER_HEIGHT_M - body.global_position.y)
	# [b]Plus the collective that hovers, which is what stops a proportional loop
	# sitting below the height it was asked for.[/b] A P controller's output has to
	# be non-zero at equilibrium, so it settles wherever `error x gain` equals the
	# demand that holds the machine up — measured, 1.28 m under a 4.00 m target,
	# every time, on both combatants. That reads as "the rotary family cannot reach
	# its hover height" and is a fixture with droop.
	#
	# Fed forward rather than integrated: the disturbance here is the Assembly's own
	# weight, which is known exactly and does not change between structural events,
	# and an integrator would be a second piece of state to get wrong on a fixture
	# that already stands in for a system doc 05 does not have (`HANDOFF.md` §3.7).
	input.collective = clampf(
		_hover_collective(c)
		+ altitude_error * HOVER_HEIGHT_GAIN
		- velocity.y * HOVER_CLIMB_GAIN,
		-1.0,
		1.0
	)

	# Station-keeping rather than a one-way approach, and the module's 8° of
	# depression is the whole reason. A rotary Assembly that only ever closes
	# ends up directly over a ground target with its gun on the stop, unable to
	# point at the thing underneath it — so it backs off as readily as it closes.
	var flat := Vector3(aim.x - body.global_position.x, 0.0, aim.z - body.global_position.z)
	var wanted := Vector3.ZERO
	if flat.length() > SyndicateConstants.EPSILON_LINEAR:
		wanted = flat.normalized() * clampf(
			flat.length() - c.stand_off_m, -ROTARY_APPROACH_MPS, ROTARY_APPROACH_MPS
		)
	var accel := (wanted - Vector3(velocity.x, 0.0, velocity.z)) * CYCLIC_VELOCITY_GAIN
	accel = accel.limit_length(CYCLIC_ACCEL_LIMIT_MPS2)
	input.cyclic = _cyclic_for(c, Vector3(accel.x, SyndicateConstants.GRAVITY_MPS2, accel.z))

	if flat.length_squared() > SyndicateConstants.EPSILON_LINEAR:
		var forward := -body.global_transform.basis.z
		forward.y = 0.0
		var bearing := forward.normalized().signed_angle_to(flat.normalized(), Vector3.UP)
		input.yaw = clampf(
			bearing * YAW_HEADING_GAIN - body.angular_velocity.y * YAW_RATE_GAIN, -1.0, 1.0
		)


## The normalised collective that holds [param c] in the hover, in [0, 1].
##
## Thrust is linear in collective pitch (doc 05 §12.3) and the profile quotes its
## coefficient at the maximum, so the fraction of full collective that produces
## the Assembly's own weight is simply weight over what every disc makes at the
## stop. Ground effect is deliberately excluded — it would make the feed-forward
## height-dependent, and the proportional term above is what handles the
## difference.
func _hover_collective(c: Combatant) -> float:
	var peak := 0.0
	for slot: int in c.motion.motive_slots():
		if c.motion.family_of(slot) != PartEnums.LocomotionMode.ROTARY:
			continue
		var rotor := _definition(c.runtime, slot).motive_profile.rotor_profile
		if rotor == null:
			continue
		peak += RotorSolver.base_thrust_n(
			rotor, rotor.nominal_rad_s, rotor.collective_limit_deg.y
		)
	if peak <= 0.0:
		return 0.0
	return clampf(
		c.runtime.body.mass * SyndicateConstants.GRAVITY_MPS2 / peak, 0.0, 1.0
	)


## The normalised cyclic demand that points this Assembly's disc along
## [param thrust_world].
##
## [method RotorSolver.thrust_direction] tilts the disc's rest-frame up about
## `+X` by the first swash angle and about `+Z` by the second, then carries the
## result through the part's placement orientation and the chassis basis. This
## inverts that composition exactly, which is why the controller can ask for a
## world direction and get a demand that produces it rather than one that
## approaches it.
func _cyclic_for(c: Combatant, thrust_world: Vector3) -> Vector2:
	var slots := c.motion.motive_slots()
	if slots.is_empty():
		return Vector2.ZERO
	var slot := slots[0]
	var st: PartInstanceState = c.runtime.states[slot]
	var rotor := _definition(c.runtime, slot).motive_profile.rotor_profile
	if st == null or rotor == null:
		return Vector2.ZERO

	var body_dir := c.runtime.body.global_transform.basis.inverse() * thrust_world.normalized()
	var rest := (OrientationTable.basis_for(st.orientation_index).inverse() * body_dir).normalized()
	# `up.rotated(RIGHT, a).rotated(BACK, b)` is `(-cos a·sin b, cos a·cos b, sin a)`.
	var pitch := asin(clampf(rest.z, -1.0, 1.0))
	var roll := atan2(-rest.x, rest.y)
	var limit := maxf(rotor.cyclic_limit_deg, SyndicateConstants.EPSILON_LINEAR)
	return Vector2(rad_to_deg(pitch), rad_to_deg(roll)).limit_length(limit) / limit


func _on_part_destroyed(assembly_id: int, slot: int, _cause: int) -> void:
	destroyed.append(Vector2i(assembly_id, slot))
	if slot == SyndicateConstants.CORE_SLOT:
		terminated.append(assembly_id)
	else:
		_log("%s loses %s" % [name_of(assembly_id), _part_name(assembly_id, slot)])


## Doc 04 §8.2's match-level event, now that [DamageResolver] produces one.
## Reading this rather than re-deriving Invariant I-2 from a slot-0
## `part_destroyed` is the point of the signal existing.
func _on_assembly_terminated(assembly_id: int, killer_id: int) -> void:
	kills[assembly_id] = killer_id
	if killer_id == 0 or killer_id == assembly_id:
		_log("%s is destroyed" % name_of(assembly_id))
	else:
		_log("%s is destroyed by %s" % [name_of(assembly_id), name_of(killer_id)])


func _log(text: String) -> void:
	timeline.append("t=%4d  %s" % [_clock, text])


## The callsign of an Assembly id, or the raw id if the arena never spawned it.
func name_of(assembly_id: int) -> String:
	for c: Combatant in combatants:
		if c.assembly_id() == assembly_id:
			return c.callsign
	return "#%d" % assembly_id


## A readable name for what just came off, from the part class rather than the
## part key: "its Prime Mover" reads and "pmv.combustion.standard.t2" does not.
func _part_name(assembly_id: int, slot: int) -> String:
	for c: Combatant in combatants:
		if c.assembly_id() != assembly_id:
			continue
		var def := c.runtime.definition_at(slot)
		if def == null:
			return "a part"
		return PART_CLASS_NAMES.get(def.part_class, "a part")
	return "a part"


func _on_effector_fired(assembly_id: int, _slot: int, _tick: int) -> void:
	shots_fired += 1
	if not shots_by.has(assembly_id):
		_log("%s opens fire" % name_of(assembly_id))
	shots_by[assembly_id] = int(shots_by.get(assembly_id, 0)) + 1


func _on_part_band_changed(assembly_id: int, slot: int, _before: int, after: int) -> void:
	band_events.append(Vector3i(assembly_id, slot, after))
	# Only the Core Module's, and only the band that means it is nearly over.
	# Invariant I-5's five bands on every part of twenty Assemblies is a wall of
	# text; "ASHFORD's Core Module is CRITICAL" is the thing a reader wants.
	if slot == SyndicateConstants.CORE_SLOT and after == PartEnums.IntegrityBand.CRITICAL:
		_log("%s's Core Module is CRITICAL" % name_of(assembly_id))


func _on_part_damaged(assembly_id: int, _slot: int, amount: float, channel: int) -> void:
	hits_landed += 1
	damage_by_target[assembly_id] = float(damage_by_target.get(assembly_id, 0.0)) + amount
	if not damage_by_channel.has(assembly_id):
		damage_by_channel[assembly_id] = PackedFloat32Array()
		damage_by_channel[assembly_id].resize(PartEnums.DAMAGE_CHANNEL_COUNT)
	var per: PackedFloat32Array = damage_by_channel[assembly_id]
	per[channel] += amount
	damage_by_channel[assembly_id] = per


## Integrity taken off [param assembly_id] through [param channel], or 0.0.
func damage_through(assembly_id: int, channel: PartEnums.DamageChannel) -> float:
	if not damage_by_channel.has(assembly_id):
		return 0.0
	var per: PackedFloat32Array = damage_by_channel[assembly_id]
	return per[channel]


## Bands [param slot] of [param assembly_id] was observed in, in order.
func bands_seen(assembly_id: int, slot: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for e: Vector3i in band_events:
		if e.x == assembly_id and e.y == slot:
			out.append(e.z)
	return out


## The yaw about the world up that points an Assembly's `-Z` — which doc 07 §7.2
## fixes as forward, and which is where every barrel here points — from
## [param from] at [param to].
static func yaw_towards(from: Vector2, to: Vector2) -> float:
	var d := (to - from).normalized()
	return atan2(-d.x, -d.y)


static func _definition(runtime: AssemblyRuntime, slot: int) -> PartDefinition:
	return runtime.definition_at(slot)


## ===== LAYOUTS =========================================================


static func _place(ctx: BuildContext, key: StringName, cell: Vector3i, orientation: int) -> void:
	var def := PartRegistry.definition_by_key(key)
	var candidate := PlacementCandidate.create(def, cell, orientation)
	var reject := PlacementValidator.validate(ctx, candidate)
	if reject != PlacementValidator.Reject.NONE:
		push_error(
			"CombatArena: '%s' at %s rejected (%d): %s"
			% [key, cell, reject, PlacementValidator.REJECT_KEYS[reject]]
		)
		return
	PlacementValidator.commit(ctx, candidate)


## The wheeled layout, with [param gun_key] on the nose. Parameterised rather
## than duplicated: the mount cell, the stations and the contacts are the whole
## of what makes a recoil comparison a comparison, so a second copy of this
## function is a second chance for the two builds to differ in something nobody
## meant them to differ in.
func _lay_out_wheeled(ctx: BuildContext, with_cell: bool, gun_key: StringName) -> void:
	_place(ctx, CORE_KEY, GROUND_CORE, 0)
	_place(ctx, FLAT_POWER_KEY, GROUND_POWER, 0)
	_place(ctx, gun_key, GROUND_GUN, 0)
	if with_cell:
		_place(ctx, CELL_KEY, GROUND_CELL, 0)
	for cell: Vector3i in WHEEL_HUBS:
		_place(ctx, HUB_KEY, cell, 0)
	for cell: Vector3i in WHEEL_ORIGINS:
		var key := WHEEL_KEY if cell.z < FRONT_AXLE_Z else REAR_KEY
		var inboard := Vector3.RIGHT if cell.x < GROUND_CORE.x else Vector3.LEFT
		_place(ctx, key, cell, drive_face_orientation(inboard))


## [constant Recipe.MELEE]: the ambulatory running gear with an Appendage on each
## flank and an edge in each hand.
##
## The arms before the edges, because an edge's only attachment node is a GRIP
## hilt (doc 01 §4.3) and there is nothing for it to mate with until the hand
## exists. That is the same order a player has to build in and the same order the
## validator enforces, which is the point of routing this through it.
##
## It carries no Energy Cell. The four limbs and two arms come to 31 of the
## ambulatory chassis's 34 mounts, and the two edges draw 40 PU against 710
## available — supply is not what is scarce here, mounts are.
func _lay_out_melee(ctx: BuildContext) -> void:
	_lay_out_ambulatory(ctx, false)
	for cell: Vector3i in MELEE_ARMS:
		_place(ctx, ARM_KEY, cell, shoulder_orientation())
	for cell: Vector3i in MELEE_EDGES:
		_place(ctx, EDGE_KEY, cell, 0)


## [constant Recipe.TRACKED], on its own chassis at last.
##
## It was built on `core.command.compact.t2` — the road hull — for the life of the
## project, which is how a 1.90 m track patch ended up under a 3.25 m vehicle. It
## now carries `core.tracked.hauler.t3` and `mot.tracked.long_bogie.t3`, so the
## contact base is exactly the length of the hull above it, and
## `eff.ballistic.rifle_long.t3`, whose barrel is the reason anybody would build
## one.
func _lay_out_tracked(ctx: BuildContext) -> void:
	_place(ctx, TRACKED_CORE_KEY, TRACKED_CORE, 0)
	_place(ctx, TRACKED_POWER_KEY, TRACKED_POWER, 0)
	_place(ctx, CANNON_KEY, TRACKED_GUN, 0)
	for cell: Vector3i in TRACK_HUBS:
		_place(ctx, HUB_KEY, cell, 0)
	for cell: Vector3i in TRACK_ORIGINS:
		var inboard := Vector3.RIGHT if cell.x < TRACKED_CORE.x else Vector3.LEFT
		_place(ctx, TRACK_KEY, cell, drive_face_orientation(inboard))


## [constant Recipe.WHEELED_UTILITY]: the protected utility truck.
##
## The same four-contact construction as the road car on a hull half again as
## tall, with the 1.00 m contacts rather than the 0.75 m ones and the Prime Mover
## mated to the nose as a bonnet rather than to the tail as an engine bay. Those
## three differences are the whole vehicle, and none of them is a line of code —
## which is the argument for the part table carrying two wheel sizes and two
## Prime Mover sections.
func _lay_out_utility(ctx: BuildContext) -> void:
	_place(ctx, UTILITY_CORE_KEY, UTILITY_CORE, 0)
	_place(ctx, POWER_KEY, UTILITY_POWER, 0)
	_place(ctx, REPEATER_KEY, UTILITY_GUN, 0)
	for cell: Vector3i in UTILITY_HUBS:
		_place(ctx, HUB_KEY, cell, 0)
	for cell: Vector3i in UTILITY_WHEEL_ORIGINS:
		var key := UTILITY_WHEEL_KEY if cell.z < FRONT_AXLE_Z else UTILITY_REAR_KEY
		var inboard := Vector3.RIGHT if cell.x < UTILITY_CORE.x else Vector3.LEFT
		_place(ctx, key, cell, drive_face_orientation(inboard))


func _lay_out_ambulatory(ctx: BuildContext, armed: bool) -> void:
	_place(ctx, AMBULATORY_CORE_KEY, AMBULATORY_CORE, 0)
	_place(ctx, STRIDER_POWER_KEY, AMBULATORY_POWER, 0)
	if armed:
		_place(ctx, GUN_KEY, AMBULATORY_GUN, 0)
	for i: int in AMBULATORY_LEGS.size() / 2:
		_place(ctx, HUB_KEY, AMBULATORY_LEGS[i * 2], HUB_AXLE_DOWN_ORIENTATION)
		_place(ctx, LIMB_KEY, AMBULATORY_LEGS[i * 2 + 1], 0)


## [constant Recipe.BIPED]: two limbs on a humanoid torso.
##
## Structurally the ambulatory layout with half the limbs and a shallower torso.
## What makes it stand is not in this function at all — it is
## [constant BIPED_LIMB_KEY]'s authored `foot_length_m`, which doc 05 §13.10 turns
## into a bounded ankle torque, and §13.11's capture point deciding where the next
## step goes. Neither existed before session 44 and the recipe would have been a
## machine lying on its face.
##
## [b]And it is a different limb from the quadruped's.[/b] Sharing
## [constant LIMB_KEY] made the recipe a machine that walks in a straight line and
## falls on its face the moment it is asked to turn, because a foot sized for four
## limbs is 6.8° of recoverable tilt on two.
func _lay_out_biped(ctx: BuildContext) -> void:
	_place(ctx, BIPED_CORE_KEY, BIPED_CORE, 0)
	_place(ctx, STRIDER_POWER_KEY, BIPED_POWER, 0)
	_place(ctx, GUN_KEY, BIPED_GUN, 0)
	for i: int in BIPED_LEGS.size() / 2:
		_place(ctx, HUB_KEY, BIPED_LEGS[i * 2], HUB_AXLE_DOWN_ORIENTATION)
		_place(ctx, BIPED_LIMB_KEY, BIPED_LEGS[i * 2 + 1], 0)
	# Bracket, then arm, then edge — the order the validator forces and the order
	# a player has to build in. An arm has nothing to mate to until the plate over
	# it exists, and an edge's only node is a GRIP hilt with nothing to hold it.
	_place(ctx, CELL_KEY, BIPED_BACKPACK, 0)
	for cell: Vector3i in BIPED_SHOULDERS:
		_place(ctx, PYLON_KEY, cell, 0)
	for cell: Vector3i in BIPED_ARMS:
		_place(ctx, ARM_KEY, cell, 0)
	for cell: Vector3i in BIPED_EDGES:
		_place(ctx, EDGE_KEY, cell, hilt_up_orientation())


func _lay_out_rotary(ctx: BuildContext) -> void:
	# Supply before draw. §7.4's power budget is checked against what the context
	# holds at the moment of the placement, so the second disc is refused if the
	# Energy Cell that covers it has not been bolted on yet — the same rule a
	# player meets in the garage, and the same order they have to build in.
	_place(ctx, ROTARY_CORE_KEY, ROTARY_CORE, 0)
	_place(ctx, ROTARY_POWER_KEY, ROTARY_POWER, 0)
	_place(ctx, CELL_KEY, ROTARY_CELL, 0)
	# Pylon before station before disc. Each mates to the one before it, which is
	# the order a player has to build in and the order the validator enforces.
	for cell: Vector3i in ROTARY_PYLONS:
		_place(ctx, PYLON_KEY, cell, 0)
	for cell: Vector3i in ROTARY_MAST_HUBS:
		_place(ctx, HUB_KEY, cell, HUB_AXLE_DOWN_ORIENTATION)
	for cell: Vector3i in ROTARY_DISCS:
		_place(ctx, ROTOR_KEY, cell, 0)
	_place(ctx, GUN_KEY, ROTARY_GUN, 0)


## The orientation carrying a part's own `-Z` drive face onto [param face],
## upright. Derived from the 24-orientation group rather than written down:
## which index does it is a property of [OrientationTable], and the integer does
## not survive a change to the table (LEARNED_FACTS.md §3, and watch fact 39).
static func drive_face_orientation(face: Vector3) -> int:
	return OrientationTable.upright_facing(face)


## The orientation that turns an Appendage's shoulder — its own `+Y` — onto the
## Assembly's rear, so the arm reaches forward off a `-Z` face and the hand at its
## far end points the way the hull is going.
##
## Roll about the shoulder axis is not specified and does not need to be: the arm
## is square in section and the Effector Module in its hand carries its own frame,
## which is why this goes through [method OrientationTable.first_carrying] rather
## than through [method OrientationTable.upright_facing].
## True for every recipe built on the ambulatory chassis, which is the question
## the spawn height and the steering law both actually ask.
##
## Written as one predicate rather than as a list repeated at each call site,
## because [constant Recipe.MELEE] joining the walking recipes is exactly the
## change that leaves one of two such lists behind — and the one that gets missed
## is the spawn height, where the symptom is a five-metre drop onto its own feet
## rather than an error.
static func is_ambulatory(recipe: int) -> bool:
	return (
		recipe == Recipe.AMBULATORY
		or recipe == Recipe.AMBULATORY_BARE
		or recipe == Recipe.MELEE
		or recipe == Recipe.BIPED
	)


static func shoulder_orientation() -> int:
	return OrientationTable.first_carrying(Vector3.UP, Vector3.BACK)


## The orientation that stands a held Effector Module's hilt up, so the blade
## hangs below the hand rather than reaching out of it.
##
## An edge is authored along `-Z` with its GRIP node on `+Z` (doc 01 §10.5), and
## an Appendage's hand faces the way the arm runs. A hanging arm's hand therefore
## points down, and the only mate is an edge whose `+Z` has been carried onto
## `+Y`. Derived rather than written down, for the reason
## [method drive_face_orientation] gives.
static func hilt_up_orientation() -> int:
	return OrientationTable.first_carrying(Vector3.BACK, Vector3.UP)


## ===== COMBATANT =======================================================


## One Assembly in the arena, with the two systems that drive it and the record
## of what it did.
class Combatant:
	extends RefCounted

	var recipe: int = Recipe.WHEELED_LIGHT
	var team: int = 0
	var runtime: AssemblyRuntime = null
	var motion: MotiveSystem = null
	var guns: EffectorSystem = null
	var gun_slot: int = SyndicateConstants.INVALID_SLOT
	## False once something else owns this Assembly's [ControlInput] — an
	## [AiDriver] via [method CombatArena.make_autonomous], or nothing at all for
	## a parked target. [method CombatArena.command] then leaves it alone.
	var arena_piloted: bool = true
	## What the timeline calls this Assembly.
	var callsign: String = "?"
	## Metres from its target this Assembly stops closing at.
	var stand_off_m: float = 0.0
	## Ticks this Assembly was commanded for, and how many of them its mount
	## spent converged and pinned against an elevation stop.
	##
	## The two are not exclusive, and that is the point of recording both. Doc 07
	## §4.3 tests convergence against the [i]clamped[/i] target angles, so a mount
	## asked for more depression than it has reads as on target while it sits on
	## its stop pointing over the enemy — and §7.1's gate opens on exactly that
	## flag. An Assembly can therefore hold a perfect firing solution, fire, and
	## miss by a hull height, for as long as the geometry stays outside its arc.
	var ticks_commanded: int = 0
	var ticks_on_target: int = 0
	var ticks_on_elevation_stop: int = 0
	## Steepest nose-down attitude the hull reached, in degrees.
	var worst_nose_down_deg: float = 0.0
	## Furthest the hull ever rolled about its own longitudinal axis, in degrees.
	##
	## [b]Nothing in this suite measured attitude in roll until session 31, and
	## that is why a fixture can be green through the worst thing a player
	## sees.[/b] Every engagement file records rounds, ticks, kills and travel; an
	## Assembly that ends the fight on its side moves none of them, so being
	## rammed over — which is what the shipped match's first five seconds
	## actually were — was invisible to 6143 checks and visible in six frames of
	## a capture.
	##
	## Absolute, and it reads the full circle rather than the tilt of one axis:
	## [code]asin(right.y)[/code] answers 90° for a hull on its side and
	## [b]0°[/b] for one upside down, which is the one reading that must not be
	## mistaken for upright. See [method roll_deg].
	var worst_roll_deg: float = 0.0
	## Fastest the hull was ever travelling, in m/s. Recorded next to the roll
	## because the two together separate "it was pushed over" from "it drove
	## itself over": a build put on its side by something that hit it is slow
	## when it happens, and one that rolled itself is not.
	var peak_speed_mps: float = 0.0
	## Nearest any enemy ever came, body origin to body origin, in metres.
	##
	## The companion an attitude assertion cannot do without. "Nobody rolled
	## over" is satisfied in full by three drivers that never arrived — which is
	## a documented failure of doc 05 §15.7.1's throttle law, not a success — so
	## a fixture asserting the first has to assert this one alongside it.
	var closest_enemy_m: float = INF

	## One tick of gunnery telemetry. Called by [method CombatArena.command].
	func sample_gunnery() -> void:
		ticks_commanded += 1
		var hp := guns.hardpoint(gun_slot)
		if hp == null:
			return
		if hp.on_target:
			ticks_on_target += 1
		var def := runtime.definition_at(gun_slot)
		if def != null:
			var limits := def.effector_profile.pitch_limit_deg
			var pitch := rad_to_deg(hp.pitch_target_rad)
			if (
				absf(pitch - limits.x) < ELEVATION_STOP_EPSILON_DEG
				or absf(pitch - limits.y) < ELEVATION_STOP_EPSILON_DEG
			):
				ticks_on_elevation_stop += 1

	## One tick of hull telemetry: attitude, speed, and how close
	## [param nearest] — the nearest live enemy, or null when none is left — got.
	##
	## Called by [method CombatArena.command] for [b]every[/b] combatant, piloted
	## or not, and that is the point of it being separate from
	## [method sample_gunnery]. A parked target is exactly the thing that gets
	## rolled over, and the gunnery counter both returns early on a build with no
	## mount and is skipped entirely on one that is dead.
	func sample_hull(nearest: Combatant) -> void:
		var basis := runtime.body.global_transform.basis
		var nose := -basis.z
		worst_nose_down_deg = maxf(
			worst_nose_down_deg, rad_to_deg(asin(clampf(-nose.y, -1.0, 1.0)))
		)
		worst_roll_deg = maxf(worst_roll_deg, absf(roll_deg()))
		peak_speed_mps = maxf(peak_speed_mps, runtime.body.linear_velocity.length())
		if nearest != null:
			closest_enemy_m = minf(
				closest_enemy_m,
				runtime.body.global_position.distance_to(nearest.runtime.body.global_position)
			)

	## Half the hull's length along its own forward axis, in metres.
	##
	## Measured from the [b]colliders[/b], because Invariant I-1 makes those the
	## physical footprint and it is the footprint that decides where two
	## Assemblies touch. Every one of them is an authored primitive hanging
	## directly off the [ChassisBodyRef] — nested shapes do not register at all
	## (LEARNED_FACTS.md §1 fact 22) — so walking the body's own children is the
	## whole set.
	##
	## It exists because doc 05 §15.7.5 states an Assembly's length as a premise
	## and nothing had ever measured one. A stand-off shorter than two of these
	## added together is not a stand-off; it is a range at which the two builds
	## are already touching, and no approach law can rescue it.
	func hull_half_length_m() -> float:
		var reach := 0.0
		for child: Node in runtime.body.get_children():
			var shape_node := child as CollisionShape3D
			if shape_node == null or shape_node.shape == null:
				continue
			var box := shape_node.shape.get_debug_mesh().get_aabb()
			for corner: int in 8:
				reach = maxf(
					reach, absf((shape_node.transform * box.get_endpoint(corner)).z)
				)
		return reach

	## The hull's present roll about its own forward axis, in degrees, signed and
	## over the full circle: 0 upright, ±90 on a flank, ±180 inverted.
	##
	## [code]atan2(-x.y, y.y)[/code] rather than the angle between the hull's up
	## and the world up, because that one conflates roll with pitch and
	## [member worst_nose_down_deg] already owns the other axis.
	func roll_deg() -> float:
		var basis := runtime.body.global_transform.basis
		return rad_to_deg(atan2(-basis.x.y, basis.y.y))

	## Invariant I-2: the Core Module is the root and losing it ends the
	## Assembly. Read from the part rather than from a flag the arena keeps, so
	## that nothing here can disagree with [DamageResolver].
	func is_alive() -> bool:
		var core: PartInstanceState = runtime.states[SyndicateConstants.CORE_SLOT]
		return core != null and not core.has_flag(PartFlags.FLAG_DESTROYED)

	## Drops the trigger and the controls. A wreck stops shooting; what else it
	## does is the match layer's decision and there is not one yet (§8 item 12a).
	func retire() -> void:
		guns.set_trigger(0, false)
		motion.input.throttle = 0.0
		motion.input.steer = 0.0
		motion.input.collective = 0.0
		motion.input.cyclic = Vector2.ZERO
		motion.input.yaw = 0.0

	func assembly_id() -> int:
		return runtime.assembly_id

	func core_integrity() -> float:
		return runtime.states[SyndicateConstants.CORE_SLOT].integrity

	## Live parts still on the Assembly, Core Module included.
	func parts_remaining() -> int:
		var n := 0
		for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
			var st: PartInstanceState = runtime.states[slot]
			if st != null and not st.has_flag(PartFlags.FLAG_DESTROYED):
				n += 1
		return n
