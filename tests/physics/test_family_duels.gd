extends TestCase
## Three engagements between shipped Assemblies of different locomotion
## families, fought to a decision on real ground with real rounds.
##
## [code]test_duel.gd[/code] proved the chain works: a validated build, a
## solved aim, a swept round, a resolved packet, a band transition, a destroyed
## Core Module. It proved it with [b]one[/b] pairing — two identical wheeled
## builds, one of them frozen and the other unarmed — because a first end-to-end
## test should have exactly one variable in it.
##
## This file removes both simplifications and adds the one thing that pairing
## could not show: [b]what the locomotion family does to the fight[/b]. Nothing
## is frozen, both sides are armed, and each engagement puts two Assemblies that
## move in genuinely different ways in front of each other:
##
## [enum]
## [*] An ambulatory Assembly against a rotary one — a 1.6 t machine that walks
##     at 1.5 m/s against a 1.5 t machine that hovers at four metres and holds
##     station by thrust vectoring.
## [*] Two ambulatory Assemblies, which is the same build twice and therefore
##     the fixture that has nowhere to hide: whoever wins, wins on gunnery.
## [*] Two rotary Assemblies, where every newton of recoil goes straight into
##     the flight path because nothing is holding either of them up but thrust.
## [/enum]
##
## [b]The fixture is [CombatArena], and its tactics are a test pilot.[/b] They
## read the world and write a [ControlInput] — the same eight numbers doc 05
## §6.0 gives the AI driver — and they decide nothing about who wins. Every hit,
## every band transition and every death here is the simulation's.
##
## [b]The recoil measurement is the point of the last two methods.[/b] Handoff
## §4.11 recorded that the shipped chassis cannot carry the shipped autocannon:
## on the roof mount, one round is 3.6 rad/s of pitch and the Assembly never
## fires a second aimed shot. That measurement was taken with the muzzle two
## metres above the centre of mass. The recipes here mount the module on the
## nose instead, and the two methods below measure what that changes and what it
## does not — because the answer turns out to be "everything" and "nothing",
## respectively, and both halves are worth writing down.

## Metres apart the two combatants start. Outside the ground families'
## stand-off, so closing is part of every engagement, and just inside the rotary
## one, so a rotary Assembly opens by backing off rather than by charging.
const SEPARATION_M: float = 24.0

## Ticks to fall onto the contacts, or to find a hover, with the triggers cold.
const SETTLE_TICKS: int = 180
## Ticks an engagement is given. Fifteen seconds. Two frozen Assemblies ten
## metres apart settle it in fourteen rounds — about two seconds — and
## everything past that is the cost of hitting a moving target with an aiming
## tolerance and a bloom cone. This is the timeout; a fight that reaches it is a
## finding rather than a pass.
const ENGAGE_TICKS: int = 900

## Ticks the recoil measurement runs for. Long enough for one round to leave and
## for the impulse to be integrated, short enough that the second round of a
## 0.14 s cycle has not yet fired.
const RECOIL_TICKS: int = 12
## Ticks the mount is given to arrive on a fixed aim point before the trigger is
## touched. A 65°/s traverse needs most of three seconds to come round from the
## back, and the settle leaves it wherever the arena's default aim point put it.
const AIM_SETTLE_TICKS: int = 260
## Range the level aim point is placed at. Far enough that the pitch it demands
## is indistinguishable from zero.
const AIM_RANGE_M: float = 300.0

## Pitch rate, in rad/s, that the roof-mounted module of handoff §4.11 imparted
## with a single round. Written out by value rather than derived, because it is
## the number this build is being compared against and a derivation would move
## with the thing under test.
const ROOF_MOUNT_PITCH_RAD_S: float = 3.6

## Fraction of `impulse / mass` the rearward push must still reach with the
## contacts loaded and resisting for the tick the round leaves in.
const REARWARD_FLOOR_FRACTION: float = 0.75
## Slack on the ceiling, for the float32 round trip through the physics server.
const EPSILON_MPS: float = 0.01

## Reciprocal of the share of a fight an Assembly's mount has to be converged for
## before it counts as having been in the fight at all. Twenty is 5%: measured,
## the ambulatory build manages one tick in a hundred and eighty, and an
## Assembly that could actually bring its gun to bear would be an order of
## magnitude past this rather than just over it.
const ON_TARGET_SHARE_DIVISOR: int = 20

var _fought: bool = false
var _ambulatory_v_rotary: Duel = null
var _ambulatory_mirror: Duel = null
var _rotary_mirror: Duel = null
var _recoil: Recoil = null
## The engagement currently running, so a failure part-way through still tears
## its arena down. Every fight closes its own the moment its record is taken.
var _open: CombatArena = null


func after_all() -> void:
	if _open != null:
		_open.close()
		_open = null


## ===== THE FIGHTS ======================================================


func test_a_walking_assembly_and_a_hovering_one_fight_to_a_decision() -> void:
	await _run_all()
	var d := _ambulatory_v_rotary

	check_true(d.b_shots > 0, "the rotary Assembly fired: %d rounds" % d.b_shots)
	# [b]The ambulatory Assembly fires nothing, and this is asserted as it
	# behaves rather than repaired.[/b] It used to land one round in the window,
	# and the session that centred the shipped module's bore took even that away —
	# not by touching this family but by making every shooter more accurate, which
	# shortened the fight from 207 ticks to 180 and killed the walker before its
	# mount arrived. One round was never a capability; it was noise, and two
	# separate fixtures were resting on it (see the note on the shooter recipe in
	# `test_overpenetration_bounds.gd`).
	#
	# The mount is the thing to watch, not the round count: if it never converges
	# the trigger can never open, so the assertion is on `a_on_target_ticks` and
	# names the number. When §4.21's drift or §4.22's depression is closed this
	# starts failing, which is the point — a finding left in prose gets
	# re-litigated and one left in a test does not.
	check_true(
		d.a_on_target_ticks * ON_TARGET_SHARE_DIVISOR < d.ticks,
		(
			"and the ambulatory Assembly's mount was converged for %d of %d ticks, so "
			% [d.a_on_target_ticks, d.ticks]
		)
		+ "it fired %d rounds" % d.a_shots
	)
	check_true(d.terminated.size() >= 1, "and one of them lost its Core Module")
	check_eq(
		d.killer_of_loser,
		d.survivor,
		"with `assembly_terminated` crediting the survivor: %s" % d.survivor
	)
	check_true(
		d.ticks < ENGAGE_TICKS,
		"the fight was decided by damage, not by the timeout: %d ticks" % d.ticks
	)
	# The rotary Assembly is still flying when the shooting starts, and that is
	# not a detail: a hover is an active equilibrium, and an Assembly that had
	# quietly fallen out of the sky during the settle would still satisfy every
	# assertion about rounds and bands above it.
	check_true(
		d.b_settled_height_m > 3.0,
		"the rotary Assembly was airborne when the engagement opened: %.2f m"
		% d.b_settled_height_m
	)
	check_true(
		d.a_settled_upright > 0.99,
		"and the ambulatory one was on its feet: up · UP = %.3f" % d.a_settled_upright
	)


func test_two_walking_assemblies_trade_fire_without_settling_it() -> void:
	# The mirror match, and the one engagement of the five that still does not
	# reach a decision. Both builds are the same part list at the same mass with
	# the same tactics, and fifteen seconds of mutual fire is not enough.
	#
	# What changed since the last session is [i]why[/i], and the reason is now one
	# thing instead of three. The elevation stop no longer dominates: the fire
	# gate refuses to open on a clamped solution (doc 07 §4.3.1), the hull no
	# longer walks twenty degrees nose-down, and a standing Assembly holds itself
	# level indefinitely. What is left is the drift measured in
	# [code]tests/physics/test_ambulatory_drift.gd[/code] — a gait that turns
	# 170° in five seconds with the steering demand held at zero, which no
	# steering demand can null, and which an aiming mount that converges at half a
	# degree cannot track through.
	#
	# Asserted as it behaves. A finding in prose gets re-litigated; one in a test
	# does not, and this one will fail the day doc 05 §13 grows a heading term.
	await _run_all()
	var d := _ambulatory_mirror

	check_true(d.a_shots > 0 and d.b_shots > 0, "both squared up and both opened fire")
	check_true(d.hits_landed > 0, "and rounds landed: %d packets resolved" % d.hits_landed)
	check_true(
		d.terminated.size() < 2,
		"but it does not resolve into a clear win: %d Core Modules lost" % d.terminated.size()
	)
	check_true(
		d.ticks > ENGAGE_TICKS / 2,
		"and it takes most of the window or all of it: %d of %d ticks"
		% [d.ticks, ENGAGE_TICKS]
	)
	# The elevation stop is no longer the story, and the number is the evidence.
	# It was a clear majority of the engagement before doc 07 §4.3.1; a fifth is
	# a hull that bobs, not a hull that cannot bear.
	check_true(
		d.a_stop_ticks * 2 < d.commanded_ticks,
		(
			"the mount was pinned against an elevation stop on %d of %d ticks, no longer most"
			% [d.a_stop_ticks, d.commanded_ticks]
		)
	)


func test_two_hovering_assemblies_fight_to_a_decision() -> void:
	await _run_all()
	var d := _rotary_mirror

	check_true(d.a_shots > 0 and d.b_shots > 0, "both rotary Assemblies engaged")
	check_true(d.terminated.size() > 0, "and at least one Core Module was lost")
	check_eq(
		d.killer_of_loser,
		d.survivor,
		"with `assembly_terminated` crediting the survivor: %s" % d.survivor
	)
	check_true(
		d.ticks < ENGAGE_TICKS, "inside the engagement window: %d ticks" % d.ticks
	)
	# Two Assemblies held up by nothing but thrust, firing 1450 N·s at each other
	# on a 0.14 s cycle. That they are both still airborne at the decision is the
	# assertion the nose mount exists to make true.
	check_true(
		d.a_settled_height_m > 3.0 and d.b_settled_height_m > 3.0,
		"both were flying when the engagement opened: %.2f m / %.2f m"
		% [d.a_settled_height_m, d.b_settled_height_m]
	)


func test_the_loser_degraded_through_the_bands_before_it_died() -> void:
	# Invariant I-5 observed on a real part rather than asserted against a table,
	# and asserted on the ambulatory pairing because it is the one whose loser is
	# known in advance from a completed run rather than decided by the roll.
	await _run_all()
	var d := _ambulatory_v_rotary
	check_true(d.terminated.size() > 0, "somebody died")
	if d.terminated.is_empty():
		return
	var bands := d.loser_core_bands
	check_true(
		bands.size() >= 3,
		"and its Core Module passed through the intermediate bands on the way: %s" % [bands]
	)
	if bands.is_empty():
		return
	check_eq(
		bands[bands.size() - 1],
		PartEnums.IntegrityBand.DESTROYED,
		"ending at DESTROYED"
	)


func test_a_round_never_strikes_the_assembly_that_fired_it() -> void:
	# §12.3's self-exclusion, asserted where the answer is unambiguous: one
	# Assembly alone on the slab, firing down an empty line, with nothing in the
	# world that a round could legitimately hit. Any damage packet at all is a
	# round that struck its own muzzle.
	#
	# This is the assertion a nose mount needs and a roof mount does not. The
	# module here emits from 2.75 m ahead of the lattice origin, on the
	# centreline, at the height of the Core Module — a line that passes through
	# where the hull would be if the offset composition of
	# [method EffectorSystem.muzzle_world_transform] were wrong by one step. Every
	# other assertion in this file would survive that; this one would not.
	await _run_all()
	check_true(_recoil.shots > 0, "the lone Assembly fired: %d rounds" % _recoil.shots)
	check_eq(_recoil.self_damage, 0, "and nothing on it was damaged by its own round")


func test_the_rounds_fired_resolved_and_did_not_leak() -> void:
	# §12's pool is bounded and every round has a life. A sweep that never
	# expired a miss would fill 2048 slots and start recycling live rounds, which
	# presents as shots vanishing in mid-air much later and is close to
	# undiagnosable after the fact.
	#
	# The second check is the one that matters more, and it is the rejection half
	# of every assertion above: an engagement in which rounds left the muzzle and
	# nothing was ever struck would satisfy "both fired" and would mean the sweep
	# never resolved anything.
	await _run_all()
	for d: Duel in [_ambulatory_v_rotary, _ambulatory_mirror, _rotary_mirror] as Array[Duel]:
		check_true(
			d.in_flight_at_end < ProjectileSystem.POOL_SIZE,
			"%s: the pool did not fill: %d in flight" % [d.name, d.in_flight_at_end]
		)
		check_true(
			d.hits_landed > 0,
			"%s: and %d rounds resolved against something" % [d.name, d.hits_landed]
		)


## ===== RECOIL ==========================================================


func test_a_nose_mounted_module_does_not_backflip_its_own_assembly() -> void:
	# Handoff §4.11, measured again with the module moved. The impulse is
	# unchanged and so is the mass; the only thing that differs is where the
	# muzzle sits relative to the centre of mass, and the moment arm is what the
	# whole finding was about.
	await _run_all()
	check_true(
		_recoil.pitch_rate_rad_s < ROOF_MOUNT_PITCH_RAD_S * 0.25,
		(
			"one round pitches the Assembly at %.3f rad/s, against %.1f from the roof mount"
			% [_recoil.pitch_rate_rad_s, ROOF_MOUNT_PITCH_RAD_S]
		)
	)
	check_true(
		_recoil.muzzle_above_com_m < 0.4,
		"because the muzzle is %.3f m off the centre of mass rather than two"
		% _recoil.muzzle_above_com_m
	)
	# The rejection half. A test that only ever asserts the pitch is small passes
	# just as happily against a build whose Effector Module never fired.
	check_eq(_recoil.shots, 1, "and it was measured across exactly one round")


func test_the_rearward_push_of_a_round_is_undiminished_by_moving_the_muzzle() -> void:
	# The other half of §4.11, and the half the nose mount does [i]not[/i] fix.
	# Recoil is an impulse: moving the muzzle changes the moment it applies and
	# cannot change the momentum. 1450 N·s into an 1100 kg Assembly is 1.3 m/s
	# whatever the module is bolted to, and a build holding this trigger at the
	# heat-limited rate takes about a third of a g of continuous rearward
	# acceleration for as long as it holds it.
	#
	# Bracketed rather than equated, and the bracket is the physics: the impulse
	# lands inside a tick during which four loaded contacts are also resisting
	# it, so the observed change is the ideal figure less whatever the tyres took.
	# An equality here would be asserting that the Assembly is in free flight.
	await _run_all()
	var ideal := _recoil.recoil_impulse_ns / _recoil.mass_kg
	check_true(
		_recoil.rearward_mps > ideal * REARWARD_FLOOR_FRACTION,
		(
			"one round pushes the Assembly back at %.3f m/s, against %.3f ideal"
			% [_recoil.rearward_mps, ideal]
		)
	)
	check_true(
		_recoil.rearward_mps <= ideal + EPSILON_MPS,
		"and never more than the impulse it carries: %.3f m/s" % _recoil.rearward_mps
	)


## ===== FIXTURES ========================================================


## Runs all three engagements and the recoil measurement, exactly once, however
## many test methods ask for them.
##
## A fight is destructive and cannot be repeated — an Assembly whose Core Module
## has gone cannot be put back — so each one runs here and leaves a record
## behind. That is what lets eight test methods each assert one thing about the
## same three runs, instead of three methods asserting eight things apiece and
## reporting only the first failure in each.
func _run_all() -> void:
	if _fought:
		return
	_fought = true
	_ambulatory_v_rotary = await _duel(
		"ambulatory against rotary", CombatArena.Recipe.AMBULATORY, CombatArena.Recipe.ROTARY
	)
	_ambulatory_mirror = await _duel(
		"ambulatory against ambulatory",
		CombatArena.Recipe.AMBULATORY,
		CombatArena.Recipe.AMBULATORY
	)
	_rotary_mirror = await _duel(
		"rotary against rotary", CombatArena.Recipe.ROTARY, CombatArena.Recipe.ROTARY
	)
	_recoil = await _measure_recoil()


## Opens a fresh arena, and it is the [i]only[/i] one open.
##
## Every arena builds its slab and its Assemblies in the same world at the same
## coordinates, because they all hang off the one [SceneTree] the autoloads live
## in. Two open at once put the second engagement inside the first one's
## wreckage — rounds strike a hull that belongs to a fight that finished, the
## bus delivers one arena's damage into the other's counters, and every number
## either of them records is a mixture. Each fight therefore takes its record
## and tears its arena down before the next one is built.
func _open_arena() -> CombatArena:
	assert(_open == null, "an arena is already open")
	_open = CombatArena.new()
	_open.open()
	return _open


func _close_arena() -> void:
	if _open != null:
		_open.close()
		_open = null


## One engagement, from two recipes to a record of what happened.
func _duel(name: String, recipe_a: int, recipe_b: int) -> Duel:
	var arena := _open_arena()

	var at := Vector2(0.0, SEPARATION_M * 0.5)
	var bt := Vector2(0.0, -SEPARATION_M * 0.5)
	var a := arena.spawn(recipe_a, 0, at, CombatArena.yaw_towards(at, bt), AmmoLedger.UNLIMITED)
	var b := arena.spawn(recipe_b, 1, bt, CombatArena.yaw_towards(bt, at), AmmoLedger.UNLIMITED)

	await arena.settle(SETTLE_TICKS)

	var d := Duel.new()
	d.name = name
	# Recorded when the fixture is built, not when a test happens to ask. The
	# runner sorts methods, and by the time an alphabetically later one runs
	# these two have driven several metres and one of them is wreckage.
	d.a_settled_height_m = a.runtime.body.global_position.y
	d.b_settled_height_m = b.runtime.body.global_position.y
	d.a_settled_upright = a.runtime.body.global_transform.basis.y.dot(Vector3.UP)
	d.b_settled_upright = b.runtime.body.global_transform.basis.y.dot(Vector3.UP)
	var a_start := a.runtime.body.global_position
	var b_start := b.runtime.body.global_position

	await arena.engage(ENGAGE_TICKS)

	d.ticks = arena.ticks_engaged
	d.a_shots = int(arena.shots_by.get(a.assembly_id(), 0))
	d.b_shots = int(arena.shots_by.get(b.assembly_id(), 0))
	d.terminated = arena.terminated.duplicate()
	d.parts_destroyed = arena.destroyed.size()
	d.in_flight_at_end = arena.projectiles.active_count()
	d.hits_landed = arena.hits_landed
	d.a_travelled_m = a_start.distance_to(a.runtime.body.global_position)
	d.b_travelled_m = b_start.distance_to(b.runtime.body.global_position)
	d.a_on_target_ticks = a.ticks_on_target
	d.a_stop_ticks = a.ticks_on_elevation_stop
	d.b_stop_ticks = b.ticks_on_elevation_stop
	d.commanded_ticks = a.ticks_commanded
	d.a_worst_nose_down_deg = a.worst_nose_down_deg
	d.timeline = arena.timeline.duplicate()
	if not d.terminated.is_empty():
		# Only from `assembly_terminated`. `name_of` answers "#7" for an id it
		# has never seen, so defaulting the lookup and naming the result would
		# make the attribution assertions below unfailable — which is exactly
		# what a fault sweep found them to be before this guard existed.
		if arena.kills.has(d.terminated[0]):
			d.killer_of_loser = arena.name_of(int(arena.kills[d.terminated[0]]))
		# The other side of a two-Assembly fight, named independently of who
		# the signal says did it, so the two can be compared.
		var loser_id := d.terminated[0]
		d.survivor = arena.name_of(b.assembly_id() if loser_id == a.assembly_id()
				else a.assembly_id())
		d.loser_core_bands = arena.bands_seen(loser_id, SyndicateConstants.CORE_SLOT)
	print("  --- %s: %d ticks, %d + %d rounds, %d hits" % [name, d.ticks, d.a_shots, d.b_shots, d.hits_landed])
	for line: String in d.timeline:
		print("      " + line)
	_close_arena()
	return d


## Fires exactly one round from a settled Assembly and measures what it did to
## the body it is bolted to.
##
## Everything here exists to isolate the impulse. The Assembly is settled first
## so it fires from the pose a real build would be in; the target is placed dead
## ahead and level so the mount is not elevated and the recoil is along the
## chassis; and the trigger is released after one round, because a second round
## inside the measurement window would make this an average rather than an
## impulse.
func _measure_recoil() -> Recoil:
	var arena := _open_arena()
	var shooter := arena.spawn(
		CombatArena.Recipe.WHEELED_LIGHT, 0, Vector2.ZERO, 0.0, AmmoLedger.UNLIMITED
	)
	await arena.settle(SETTLE_TICKS)

	var body := shooter.runtime.body
	var def := shooter.runtime.definition_at(shooter.gun_slot)
	var hp := shooter.guns.hardpoint(shooter.gun_slot)
	var r := Recoil.new()
	r.mass_kg = shooter.runtime.mass_properties.total_mass
	r.recoil_impulse_ns = def.effector_profile.recoil_impulse_ns
	r.muzzle_above_com_m = absf(
		(
			body.global_transform.inverse() * EffectorSystem.muzzle_world_transform(
				shooter.runtime, shooter.runtime.states[shooter.gun_slot], def, 0, 0.0, 0.0
			).origin
		).y
		- shooter.runtime.mass_properties.com_local.y
	)

	# Level and dead ahead, with the trigger cold, until the mount has actually
	# arrived. A mount still slewing fires along a different line than the one
	# the impulse is being predicted for, and the settle leaves it pointed
	# wherever the arena's default aim point put it.
	for i: int in AIM_SETTLE_TICKS:
		shooter.guns.aim_point_world = _level_aim(shooter)
		await physics_frames(1)
		if hp.on_target:
			break

	var before_omega := body.angular_velocity
	var before_v := body.linear_velocity
	shooter.guns.set_trigger(0, true)
	for i: int in RECOIL_TICKS:
		shooter.guns.aim_point_world = _level_aim(shooter)
		await physics_frames(1)
		if hp.shots_fired > 0:
			# One round, not an average. The cycle is 0.14 s — eight ticks — so
			# releasing here leaves the measurement window clear of the next one.
			shooter.guns.set_trigger(0, false)
			break
	await physics_frames(1)

	r.shots = hp.shots_fired
	# Nothing else is on this slab, so any packet at all came off its own muzzle.
	r.self_damage = arena.hits_landed
	r.pitch_rate_rad_s = absf((body.angular_velocity - before_omega).x)
	# Along the chassis's own backward axis. The Assembly is on its suspension
	# with its contacts loaded, so the tyres take a share of this inside the tick
	# the impulse lands in; the assertion brackets it rather than equating it.
	r.rearward_mps = (body.linear_velocity - before_v).dot(body.global_transform.basis.z)
	print(
		"  recoil: %d round, %.3f rad/s pitch, %.3f m/s rearward, muzzle %.3f m above the COM"
		% [r.shots, r.pitch_rate_rad_s, r.rearward_mps, r.muzzle_above_com_m]
	)
	_close_arena()
	return r


## An aim point straight down the chassis centreline at the muzzle's own height,
## so the mount sits at zero yaw and zero pitch and the recoil is a pure
## rearward impulse along the hull.
func _level_aim(shooter: CombatArena.Combatant) -> Vector3:
	var body := shooter.runtime.body
	var muzzle := EffectorSystem.muzzle_world_transform(
		shooter.runtime,
		shooter.runtime.states[shooter.gun_slot],
		shooter.runtime.definition_at(shooter.gun_slot),
		0,
		0.0,
		0.0
	)
	var forward := -body.global_transform.basis.z
	forward.y = 0.0
	return muzzle.origin + forward.normalized() * AIM_RANGE_M


## ===== RECORDS =========================================================


## What one engagement did, captured while the Assemblies were still standing.
class Duel:
	extends RefCounted

	var name: String = ""
	var ticks: int = 0
	var a_shots: int = 0
	var b_shots: int = 0
	var parts_destroyed: int = 0
	var terminated: PackedInt32Array = PackedInt32Array()
	var loser_core_bands: PackedInt32Array = PackedInt32Array()
	var in_flight_at_end: int = 0
	var hits_landed: int = 0
	var a_settled_height_m: float = 0.0
	var b_settled_height_m: float = 0.0
	var a_settled_upright: float = 0.0
	var b_settled_upright: float = 0.0
	var a_travelled_m: float = 0.0
	var b_travelled_m: float = 0.0
	var a_on_target_ticks: int = 0
	var a_stop_ticks: int = 0
	var b_stop_ticks: int = 0
	var commanded_ticks: int = 0
	var a_worst_nose_down_deg: float = 0.0
	var timeline: PackedStringArray = PackedStringArray()
	## Whoever doc 04 §8.2's `assembly_terminated` named as the killer, and
	## empty if the signal never arrived.
	var killer_of_loser: String = ""
	## The combatant that was still alive, derived from the roster rather than
	## from the signal, so the two can be checked against each other.
	var survivor: String = ""


## What one round did to the Assembly that fired it.
class Recoil:
	extends RefCounted

	var shots: int = 0
	var mass_kg: float = 0.0
	var recoil_impulse_ns: float = 0.0
	var muzzle_above_com_m: float = 0.0
	var pitch_rate_rad_s: float = 0.0
	var rearward_mps: float = 0.0
	var self_damage: int = 0
