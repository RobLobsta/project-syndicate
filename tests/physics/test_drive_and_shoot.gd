extends TestCase
## Can an Assembly drive and shoot at the same time? Doc 01 §10.5 and doc 07 §8.
##
## [b]The answer changed with the rebuild, and this file is where it says so.[/b]
## Both of its "asserted as a defect" methods inverted: the autocannon build used
## to spin 99° in two and a half seconds and fire two rounds of seventeen, and on
## the 3630 kg chassis it holds its heading to under ten and fires fifteen. The
## trade doc 01 §10.5 authored `eff.ballistic.repeater_12.t2` for survives as a
## multiple rather than as the difference between a working gun and a useless one.
##
## [b]The oldest open question in the project and the first file to ask it.[/b]
## Every other measurement of the recoil problem has been a single round on a
## stationary hull — `test_recoil_geometry.gd` fires one and reports the yaw it
## imparts — and a player never fires one round at a standstill. They hold the
## trigger down with a target off the nose while the machine is moving, which is
## a sustained torque against four contacts rather than an impulse against a
## parked mass, and nothing had ever put those two loops in the same window.
##
## The measurement is an A/B on one chassis. Both runs use the identical wheeled
## layout at the identical mount cell under the identical throttle, traversed to
## the identical bearing, and differ in one authored resource: which Effector
## Module is bolted to the nose. That is the only way the claim doc 01 §10.5
## makes for `eff.ballistic.repeater_12.t2` can be tested at all — it is a claim
## about a comparison, and a fixture carrying one module cannot make one.
##
## [b]What is asserted is the difference, never a heading in degrees.[/b]
## `LEARNED_FACTS.md` §1 fact 54: a quantity measured off a multi-Assembly
## engagement is a measurement of the suite. This file runs one Assembly at a
## time on a flat slab, which fact 44 says does reproduce — but the honest bound
## is still the ratio, because the absolute drift depends on the contacts'
## lateral grip and doc 09's surface table, and neither is this file's subject.

## Ticks for the build to fall onto its contacts with the trigger cold.
const SETTLE_TICKS: int = 120

## Ticks allowed for the mount to reach the commanded bearing before the run
## begins. Generous: the two modules slew at different authored rates (65°/s and
## 95°/s), and a run that started before the slower one arrived would be
## comparing a traversed module against a traversing one.
const AIM_TICKS: int = 240

## Ticks the throttle and the trigger are held together. Two and a half seconds:
## long enough that the repeater fires thirty rounds and the autocannon seventeen,
## short enough that neither build reaches the edge of the slab.
const RUN_TICKS: int = 150

## Throttle held through the run. The same figure `test_ground_assembly.gd`
## drives its straight-line tests at — enough to move cleanly, well below the
## wheelspin threshold, so what is measured is the recoil and not a burnout.
const THROTTLE: float = 0.25

## Traverse the mount is held at through the run, in degrees. Square across the
## hull, which is the worst case and is also roughly where a driver's mount sits
## while the driver is turning toward something.
const TRAVERSE_DEG: float = 90.0

## Range the aim point is placed at. Far enough that the mount solves an
## essentially flat bearing and the elevation stays out of the measurement.
const AIM_RANGE_M: float = 200.0

## Heading drift, in degrees, inside which a build is "driving where it was
## pointed" for this file's purposes.
##
## Ten degrees over two and a half seconds is four degrees a second, which is a
## machine a player is steering rather than one being steered by its own gun.
## The figure is a judgement and is stated here so that it is one number in one
## place; the assertions that matter are the ratios below it.
const HELD_HEADING_DEG: float = 10.0

## Distance, in metres, a run must cover to count as having driven at all.
## Everything about heading is vacuous on a build that never moved.
##
## [b]A validity guard and not a measurement, and it has to be read as one.[/b]
## The autocannon build is the marginal case this whole file is about — doc 01
## §10.5's 1450 N·s throws it hard enough that it barely drives while firing — so
## its travel is exactly the kind of quantity LEARNED_FACTS.md §1 fact 44 warns
## about, and it has been seen anywhere between 0.77 m and 4.42 m across changes
## made elsewhere in the project with nothing touching this fixture. The floor is
## therefore set where "it moved" and "it never moved" genuinely part company,
## which is well under a metre; the repeater covers two and a half.
const MIN_TRAVEL_M: float = 0.5

## Separation the lethality duel is fought at, in metres. The same 24 m
## `test_family_duels.gd` uses, so the two files' engagements are comparable.
const DUEL_SEPARATION_M: float = 24.0
const DUEL_SETTLE_TICKS: int = 180
## Fifteen seconds. `test_family_duels.gd`'s window, for the same reason.
const DUEL_TICKS: int = 900

var _measured: bool = false
var _fought: bool = false
var _arena: CombatArena = null
var _repeater: Run = null
var _autocannon: Run = null
var _duel_ticks: int = 0
var _duel_parts_destroyed: int = 0
var _duel_terminated: PackedInt32Array = PackedInt32Array()


func after_all() -> void:
	if _arena != null:
		_arena.close()
		_arena = null


## ===== THE QUESTION ====================================================


func test_both_runs_actually_drove_and_actually_fired() -> void:
	# The fixture assertion, and it comes first because every claim below it is
	# satisfied by a build that sat still with a cold trigger. A module that
	# overheated, ran dry, or never reached its bearing would make this file
	# report a beautifully held heading and mean nothing by it.
	await _measure()
	for run: Run in [_repeater, _autocannon] as Array[Run]:
		check_true(
			run.travelled_m > MIN_TRAVEL_M,
			"%s drove: %.2f m" % [run.label, run.travelled_m]
		)
		check_true(run.shots > 0, "%s fired at least once: %d rounds" % [run.label, run.shots])
		check_true(
			absf(run.lever_lateral_m) > 1.0,
			(
				"%s had its mount traversed across the hull: %.2f m of lever"
				% [run.label, run.lever_lateral_m]
			)
		)


func test_the_repeater_fires_the_burst_its_cycle_allows() -> void:
	# Against the authored cycle rather than a recorded number, so the assertion
	# is "the module ran at its rated cadence" and not "it fired about thirty
	# times last Tuesday". Two thirds of the theoretical count is generous slack
	# for the ticks the trigger spends inside a cycle.
	await _measure()
	var allowed := _rounds_in_window(&"eff.ballistic.repeater_12.t2")
	check_true(
		float(_repeater.shots) > float(allowed) * 0.66,
		(
			"%d rounds against the %d its 0.075 s cycle allows in the window"
			% [_repeater.shots, allowed]
		)
	)


## [b]This test used to assert the opposite, and the rebuild is what inverted
## it.[/b]
##
## The recoil did not merely turn the hull — it turned the hull out from under the
## mount, and doc 07 §4.3.1's fire gate then correctly refused to shoot at
## something the module was no longer pointed at. On the 1107 kg chassis the build
## spent the engagement spinning with its trigger held and its barrel cold: two
## rounds of the seventeen its cycle allows, which a player reads as a gun that
## has stopped working.
##
## On the 3630 kg chassis the same module at the same mount under the same
## throttle gets fifteen of seventeen away. Nothing about the module changed;
## 1450 N·s met three times the yaw inertia through a shorter lever, and the gate
## stopped closing. The trade doc 01 §10.5 authored the repeater for is still
## real — [method test_the_difference_is_the_module_and_it_is_large] measures it —
## but it is now a matter of degree rather than of possibility.
func test_the_autocannon_build_now_gets_most_of_its_rounds_away() -> void:
	await _measure()
	var allowed := _rounds_in_window(&"eff.ballistic.autocannon_30.t3")
	check_true(allowed > 8, "the window is long enough to matter: %d rounds allowed" % allowed)
	check_true(
		float(_autocannon.shots) > float(allowed) * 0.5,
		(
			"it managed %d of the %d rounds its cycle allows, where the same module on "
			% [_autocannon.shots, allowed]
			+ "the old chassis managed two"
		)
	)


func test_a_repeater_build_holds_its_heading_while_firing() -> void:
	# The claim doc 01 §10.5 makes for the row, arriving at a player.
	await _measure()
	check_true(
		_repeater.heading_drift_deg < HELD_HEADING_DEG,
		(
			"%.1f deg of drift over %d rounds under throttle"
			% [_repeater.heading_drift_deg, _repeater.shots]
		)
	)


## The other half, and it inverted with the one above. It was 99.1° of heading
## drift over two and a half seconds — an Assembly being steered by its own gun —
## and it is now under ten, which is a machine a player is steering.
##
## [b]This assertion is supposed to break.[/b] If §10.5's four legacy direct-fire
## rows are ever rescaled off their 3× recoil basis, or the reference build is
## rescaled again, this file fails, and the fix is to re-measure and re-assert
## rather than to loosen it.
func test_the_autocannon_build_is_no_longer_steered_by_its_own_gun() -> void:
	await _measure()
	check_true(
		_autocannon.heading_drift_deg < HELD_HEADING_DEG,
		(
			"the autocannon build held its heading: %.1f deg over %d rounds"
			% [_autocannon.heading_drift_deg, _autocannon.shots]
		)
	)


func test_the_difference_is_the_module_and_it_is_large() -> void:
	# The comparison, which is the only part of this file that is a statement
	# about the two rows rather than about this slab and this throttle. Asserted
	# as a multiple so it survives a change to the contacts, the surface table or
	# the throttle — all three move both runs together.
	await _measure()
	var ratio := _autocannon.heading_drift_deg / maxf(_repeater.heading_drift_deg, 0.01)
	check_true(
		ratio > 3.0,
		(
			"one authored resource is worth %.1fx the heading: %.1f deg against %.1f"
			% [ratio, _autocannon.heading_drift_deg, _repeater.heading_drift_deg]
		)
	)


func test_the_repeater_puts_more_rounds_out_for_less_disturbance() -> void:
	# The trade, stated in the direction that makes it a trade rather than a
	# nerf. If the drivable module were also the one that fires less, doc 01
	# §10.5's row would be a strictly worse part and no player would fit it.
	await _measure()
	check_true(
		_repeater.shots > _autocannon.shots,
		(
			"the faster cycle reached the ground: %d rounds against %d in the same window"
			% [_repeater.shots, _autocannon.shots]
		)
	)


## ===== AND IS IT STILL LETHAL ==========================================
## The risk the row carries, measured rather than argued.
##
## `HANDOFF.md` §4 records that the shipped set's lethality is the four-part
## overpenetration bound doing the work: with rounds stopping at the first thing
## they defeat, nothing in the catalogue kills anything. `proj.kinetic.ap_12`
## carries half `ap_30`'s penetration, so "the drivable module cannot finish a
## fight" is the obvious way this change could be a bad one, and a green suite
## full of unit tests would not say a word about it.


func test_a_repeater_build_can_still_decide_a_fight() -> void:
	await _fight()
	check_true(
		not _duel_terminated.is_empty(),
		(
			"the engagement reached a decision in %d of its %d ticks"
			% [_duel_ticks, DUEL_TICKS]
		)
	)


func test_the_lighter_round_still_takes_parts_off_a_hull() -> void:
	# The intermediate quantity, and the one that tells a timeout apart from a
	# stalemate. A duel that runs out its window having destroyed nothing is a
	# round that cannot penetrate; one that runs out having destroyed a dozen
	# parts is two builds that are simply tough.
	await _fight()
	check_true(
		_duel_parts_destroyed > 0,
		"%d parts came off across the engagement" % _duel_parts_destroyed
	)


## ===== FIXTURES ========================================================


## Rounds [param key]'s authored cycle time allows inside the run window.
##
## Read off the definition rather than written down, so a rebalance of either
## row moves the expectation with it. The window is what the fixture holds the
## trigger for and the cycle is what the part authors; nothing here is a
## measurement of what happened.
func _rounds_in_window(key: StringName) -> int:
	var def := PartRegistry.definition_by_key(key)
	if def == null or def.effector_profile == null:
		return 0
	var window_s := float(RUN_TICKS) * SyndicateConstants.PHYSICS_DT
	return int(window_s / maxf(def.effector_profile.cycle_time_s, 0.001))


## One engagement between the two rows, run once. The record is taken while the
## arena is open and every method above asserts one thing about it.
func _fight() -> void:
	if _fought:
		return
	_fought = true
	_arena = CombatArena.new()
	_arena.open()
	var at := Vector2(0.0, DUEL_SEPARATION_M * 0.5)
	var bt := Vector2(0.0, -DUEL_SEPARATION_M * 0.5)
	_arena.spawn(
		CombatArena.Recipe.WHEELED_REPEATER,
		0,
		at,
		CombatArena.yaw_towards(at, bt),
		AmmoLedger.UNLIMITED
	)
	_arena.spawn(
		CombatArena.Recipe.WHEELED_LIGHT,
		1,
		bt,
		CombatArena.yaw_towards(bt, at),
		AmmoLedger.UNLIMITED
	)
	await _arena.settle(DUEL_SETTLE_TICKS)
	await _arena.engage(DUEL_TICKS)

	_duel_ticks = _arena.ticks_engaged
	_duel_parts_destroyed = _arena.destroyed.size()
	_duel_terminated = _arena.terminated.duplicate()
	# Which one lost is the balance datum and is deliberately printed rather than
	# asserted. `LEARNED_FACTS.md` §1 fact 44: a multi-Assembly engagement is not
	# bit-reproducible run to run, so pinning a winner would pin noise. What the
	# assertions above claim is that the fight *resolves*, which is the property
	# the lighter round could plausibly have cost.
	var loser := "nobody"
	if not _duel_terminated.is_empty():
		loser = "%s (recipe %d)" % [
			_arena.name_of(_duel_terminated[0]),
			_recipe_of(_duel_terminated[0])
		]
	print(
		"  drive and shoot: repeater vs autocannon — %d ticks, %d parts off, %s lost"
		% [_duel_ticks, _duel_parts_destroyed, loser]
	)
	# Closed the moment the record is taken (`LEARNED_FACTS.md` §1 fact 48): a
	# leaked arena leaves four hulls at the origin and the next file along builds
	# its engagement inside them.
	_arena.close()
	_arena = null


## The recipe [param assembly_id] was built from, or -1. Diagnostics only.
func _recipe_of(assembly_id: int) -> int:
	for c: CombatArena.Combatant in _arena.combatants:
		if c.assembly_id() == assembly_id:
			return c.recipe
	return -1


func _measure() -> void:
	if _measured:
		return
	_measured = true
	# One arena at a time (`LEARNED_FACTS.md` §1 fact 45), and closed the moment
	# its record is taken (fact 48). Two builds standing at one origin would
	# shoot each other and both records would be a mixture.
	_repeater = await _run(CombatArena.Recipe.WHEELED_REPEATER, "repeater_12")
	_autocannon = await _run(CombatArena.Recipe.WHEELED_LIGHT, "autocannon_30")


## One build, driven straight with its mount traversed square and its trigger
## held down for [constant RUN_TICKS].
func _run(recipe: int, label: String) -> Run:
	_arena = CombatArena.new()
	_arena.open()
	var c := _arena.spawn(recipe, 0, Vector2.ZERO, 0.0, AmmoLedger.UNLIMITED)
	# No pilot. The arena's command loop would steer this build toward a target
	# and its steering would be in the measurement — which is exactly the thing
	# being measured, arriving from the wrong end.
	c.arena_piloted = false
	await _arena.settle(SETTLE_TICKS)

	var body := c.runtime.body
	var st := c.runtime.state(c.gun_slot)
	var def := c.runtime.definition_at(c.gun_slot)
	var hp := c.guns.hardpoint(c.gun_slot)

	# An aim point square across the hull at the muzzle's own height, so the
	# mount ends up at the requested traverse with the elevation out of the
	# measurement. Taken in the world and then held fixed: an aim point that
	# tracked the hull would rotate with it and the mount would stay traversed by
	# construction, which is a different and easier question.
	var rest := EffectorSystem.muzzle_world_transform(c.runtime, st, def, 0, 0.0, 0.0)
	var heading := Vector3(sin(deg_to_rad(TRAVERSE_DEG)), 0.0, -cos(deg_to_rad(TRAVERSE_DEG)))
	var aim := rest.origin + body.global_transform.basis * heading * AIM_RANGE_M
	aim.y = rest.origin.y
	for i: int in AIM_TICKS:
		c.guns.aim_point_world = aim
		await physics_frames(1)
		if hp.on_target:
			break

	var forward_at_start := -body.global_transform.basis.z
	var position_at_start := body.global_position
	c.motion.input.throttle = THROTTLE
	c.guns.set_trigger(0, true)
	for i: int in RUN_TICKS:
		# Re-aimed every tick at the same world point, so the mount stays where it
		# was put as the hull turns under it. A mount left un-commanded would
		# drift back toward its rest bearing and quietly reduce the lever this
		# file exists to load.
		c.guns.aim_point_world = aim
		await physics_frames(1)
	c.guns.set_trigger(0, false)
	c.motion.input.throttle = 0.0

	var run := Run.new()
	run.label = label
	run.shots = hp.shots_fired
	run.travelled_m = position_at_start.distance_to(body.global_position)
	run.heading_drift_deg = rad_to_deg(
		absf(forward_at_start.signed_angle_to(-body.global_transform.basis.z, Vector3.UP))
	)
	var live := EffectorSystem.muzzle_world_transform(
		c.runtime, st, def, 0, hp.yaw_rad, hp.pitch_rad
	)
	var muzzle_local := body.global_transform.affine_inverse() * live.origin
	run.lever_lateral_m = muzzle_local.x - body.center_of_mass.x
	print(
		"  drive and shoot: %-14s %3d rounds, %5.2f m travelled, %6.1f deg of drift"
		% [run.label, run.shots, run.travelled_m, run.heading_drift_deg]
	)

	_arena.close()
	_arena = null
	return run


## One run's record, taken while the arena is open rather than in a test method:
## the runner sorts methods, and by the time a later one runs the arena is closed.
class Run:
	extends RefCounted
	var label: String = ""
	var shots: int = 0
	var travelled_m: float = 0.0
	var heading_drift_deg: float = 0.0
	var lever_lateral_m: float = 0.0
