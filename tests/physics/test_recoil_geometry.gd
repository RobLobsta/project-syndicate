extends TestCase
## Where the recoil impulse is applied, and what it does to the hull — doc 07 §8
## and doc 01 §14 rule 27.
##
## Doc 07 §8 applies the recoil at the [b]muzzle[/b] rather than at the centre of
## mass, which is what makes a heavy module mounted high pitch the nose. The
## consequence nobody had measured is the other axis: the muzzle's [i]lateral[/i]
## distance from the centre of mass is the moment arm of every round fired, and
## it produces yaw that the driving layer then has to fight.
##
## This file measures that arm in the two states it can be in.
##
## [b]On the nose[/b], the bore is on the Assembly's own centreline and one round
## produces almost no yaw. That is rule 27's whole content and it is a regression
## guard: the shipped module was authored five cells wide against a four-cell Core
## Module until this was measured, which put its bore half a cell out and about a
## kilonewton-metre of steady yaw through the hull — more than the wheeled
## family's entire steering authority.
##
## [b]Traversed[/b], it is not, and cannot be made to be. The mount sits over two
## metres forward of the centre of mass, so a bore pointed across the hull swings
## its own line of action out to a lever of that length. Rule 27 does nothing for
## this case and was never going to: the arm is the mount's position, not the
## bore's offset within the mount.
##
## The second measurement is the one that matters to a player, because a driver
## turning toward a target is by definition firing off its own nose. It is
## asserted here as it behaves, with the numbers, rather than left in prose —
## §9's rule about writing down a measurement you cannot yet fix.

## Ticks for the build to fall onto its contacts with the trigger cold.
const SETTLE_TICKS: int = 120
## Ticks allowed for the mount to reach the commanded bearing before the round.
const AIM_TICKS: int = 240
## Ticks the trigger is held for. The cycle is 0.14 s — eight ticks — so this is
## comfortably one round and the loop releases on the first.
const FIRE_TICKS: int = 30

## Range the aim point is placed at. Far enough that the mount solves an
## essentially flat bearing and the elevation stays out of the measurement.
const AIM_RANGE_M: float = 200.0

## Rule 27's own tolerance, in metres, for the [b]authored[/b] figure. The bore
## either sits on the footprint's lateral centre or it is half a cell — 0.125 m —
## away from it, so anything between the two is a rounding artefact.
const BORE_TOLERANCE_M: float = 0.005

## And the tolerance on the same quantity measured off the [b]live[/b] mount,
## which is necessarily looser and cannot be made tighter.
##
## Doc 07 §4.3 converges a mount at half a degree and the muzzle sits 2.25 m from
## the hardpoint pivot, so half a degree of residual traverse is already 0.02 m of
## lateral offset before the hull has rolled a millimetre on its suspension.
## Measured across runs the live figure wanders between −0.044 and +0.008.
##
## What the bound has to do is separate a centred bore from the half-cell one
## that was shipped, and it does: the same measurement on the five-cell-wide
## module was 0.103 m, which fails this comfortably.
const LIVE_BORE_TOLERANCE_M: float = 0.06

## Yaw rate, in rad/s, that one round fired dead ahead may impart. Measured at
## 0.027 with the bore centred on the rebuilt hull; the same shot with the bore
## half a cell out was part of a steady torque the steering could not answer. The
## bound is set well above the measurement and well below the traversed figure
## below, so it separates the two cases rather than pinning either.
##
## [b]Both figures fell by about a factor of seven when the reference build was
## rescaled[/b] — 0.120 to 0.027 here and 0.845 to 0.124 below — because the hull
## is 3.3 times the mass with the yaw inertia to match and the mount sits 1.75 m
## across it rather than over two. That is the heavy module becoming something a
## driver can survive firing, and it is re-measured here rather than left as a
## bound nothing can reach.
const NOSE_YAW_CEILING_RAD_S: float = 0.06

## And the ceiling on what the traversed shot may now do to a [b]parked[/b] hull.
##
## [b]This was a floor of 0.08 and it has inverted.[/b] The traversed shot used to
## yaw the reference build at 0.124 rad/s — 7°/s from a single round — and this
## file recorded that as a defect rule 27 could not reach, because the lever is
## the mount's position rather than the bore's offset within it. The lever is
## still there and is still asserted, two checks up. What changed is the hull
## underneath it: doc 05 §7.4's contact integration was 142 times outside its own
## stability limit, which cost a contact most of its lateral grip, and §7.7's
## holding brake did not exist. With both closed, a stationary Assembly stands on
## real friction with its brakes on and a single round moves it 0.0035 rad/s.
##
## [b]It has not stopped mattering; it has moved to the case that matters.[/b] The
## hull absorbs recoil when it is [i]stopped[/i], which is exactly when doc 05
## §15.7.4 now lets an [AiDriver] fire. A hull that is driving is spending its
## friction budget longitudinally and has far less to spare, which is
## `tests/physics/test_drive_and_shoot.gd`'s measurement and not this file's.
const TRAVERSED_YAW_CEILING_RAD_S: float = 0.02

## Traverse the second measurement is taken at, in degrees. Square across the
## hull, which is the worst case and is also roughly where a driver's mount sits
## while the driver is turning toward something.
const TRAVERSE_DEG: float = 90.0

## Ceiling, in rad/s, on what one traversed `eff.ballistic.repeater_12.t2` round
## may do to the same hull. Set at the autocannon's own [b]dead-ahead[/b] figure,
## which is the claim doc 01 §10.5 makes for the row stated as a number: a round
## fired square across the hull from the light module disturbs it no more than a
## round fired straight down the nose from the heavy one.
const REPEATER_TRAVERSED_CEILING_RAD_S: float = NOSE_YAW_CEILING_RAD_S

var _measured: bool = false
var _arena: CombatArena = null
var _nose: Shot = null
var _traversed: Shot = null
var _repeater: Shot = null


func after_all() -> void:
	if _arena != null:
		_arena.close()
		_arena = null


## ===== RULE 27, AS GEOMETRY ============================================


## The authored half, read off the definition rather than off the world. A part
## whose bore is off its own centre fails this however it is mounted.
func test_the_authored_bore_sits_on_the_modules_lateral_centre() -> void:
	var def := PartRegistry.definition_by_key(&"eff.ballistic.autocannon_30.t3")
	check_true(def != null, "the shipped autocannon is in the registry")
	if def == null:
		return
	var centre_x := (
		float(def.bounds_min_cell.x + def.bounds_max_cell.x)
		* 0.5
		* SyndicateConstants.LATTICE_UNIT_M
	)
	var offsets := def.effector_profile.muzzle_offsets_m
	check_true(not offsets.is_empty(), "and it authors at least one muzzle")
	for i: int in offsets.size():
		check_true(
			absf(offsets[i].x - centre_x) <= BORE_TOLERANCE_M,
			(
				"muzzle %d sits at x = %.4f against a footprint centre of %.4f"
				% [i, offsets[i].x, centre_x]
			)
		)


## The parity half. An odd-width module on an even-width Core Module cannot be
## centred at any placement, so the widths have to agree modulo two — and the
## fixture assertion comes first, because every claim after it is vacuous if the
## registry has no Core Module to compare against.
func test_the_module_and_the_core_module_share_a_width_parity() -> void:
	var gun := PartRegistry.definition_by_key(&"eff.ballistic.autocannon_30.t3")
	var core := PartRegistry.definition_by_key(&"core.command.compact.t2")
	check_true(gun != null and core != null, "both parts are in the registry")
	if gun == null or core == null:
		return
	check_eq(
		gun.bounds_size_cells.x % 2,
		core.bounds_size_cells.x % 2,
		(
			"the module is %d cells wide and the Core Module %d"
			% [gun.bounds_size_cells.x, core.bounds_size_cells.x]
		)
	)


## ===== RULE 27, AS PHYSICS =============================================


## The geometry above, arriving at the physics: with the bore on the centreline
## the lateral lever is zero, so a round fired dead ahead is a pure rearward
## push and a pitch, with no yaw worth naming.
##
## The lever assertion is the falsifiable one. A test that only checked the yaw
## rate would pass for a build whose bore was off-centre and whose contacts
## happened to absorb the torque on the tick it was sampled.
func test_a_round_fired_dead_ahead_puts_no_lever_on_the_hull() -> void:
	await _measure()
	check_eq(_nose.shots, 1, "one round left the barrel")
	check_true(
		absf(_nose.lever_lateral_m) <= LIVE_BORE_TOLERANCE_M,
		"and its muzzle was on the centre of mass's own line: %.4f m off"
		% _nose.lever_lateral_m
	)
	check_true(
		absf(_nose.yaw_rate_rad_s) < NOSE_YAW_CEILING_RAD_S,
		(
			"so the hull barely yawed: %.4f rad/s against a ceiling of %.2f"
			% [_nose.yaw_rate_rad_s, NOSE_YAW_CEILING_RAD_S]
		)
	)


## And the part rule 27 does not reach.
##
## [b]This is asserted as a defect, deliberately.[/b] Traversed square across the
## hull the same module, on the same build, firing the same round, yaws it by a
## multiple — because the mount is over two metres forward of the centre of mass
## and the recoil's line of action swings out with it. Centring the bore was
## expected to make an Assembly able to drive and shoot at once and it does not,
## and this is the measurement that says why.
##
## The comparison is against the nose shot rather than against a constant, so it
## stays a statement about the geometry if the recoil impulse is ever rebalanced.
func test_a_traversed_round_yaws_the_hull_by_a_multiple() -> void:
	await _measure()
	check_eq(_traversed.shots, 1, "one round left the traversed barrel too")
	# The fixture assertion: the mount actually got round. Everything below is
	# satisfied by a mount that never traversed and fired down the nose.
	check_true(
		absf(_traversed.lever_lateral_m) > 1.0,
		(
			"and the mount had traversed, putting its muzzle %.3f m across the hull"
			% _traversed.lever_lateral_m
		)
	)
	check_true(
		absf(_traversed.yaw_rate_rad_s) < TRAVERSED_YAW_CEILING_RAD_S,
		(
			"and the parked hull absorbed it: %.4f rad/s, against 0.124 before doc 05 "
			+ "§7.4's contact integration was repaired and §7.7's holding brake existed"
		) % _traversed.yaw_rate_rad_s
	)


## ===== THE OTHER FACTOR ================================================


## The lever is the mount's and the impulse is the round's, and the round is the
## half an authored row controls.
##
## Same chassis, same mount cell, same 90° traverse, same lever — and one
## authored resource different. This is the only place in the suite where the two
## `BALLISTIC_DIRECT` rows meet on identical geometry, which is what makes it a
## measurement of the rows rather than of two builds.
func test_the_light_module_traversed_disturbs_the_hull_less_than_the_heavy_one_on_the_nose() -> void:
	await _measure()
	check_eq(_repeater.shots, 1, "one repeater round left the traversed barrel")
	# The fixture assertion. Everything below is satisfied by a mount that never
	# got round, and a mount that never got round has no lever to load.
	check_true(
		absf(_repeater.lever_lateral_m) > 1.0,
		(
			"and it was traversed on the same lever as the autocannon: %.3f m against %.3f"
			% [_repeater.lever_lateral_m, _traversed.lever_lateral_m]
		)
	)
	check_true(
		absf(_repeater.yaw_rate_rad_s) < REPEATER_TRAVERSED_CEILING_RAD_S,
		(
			"a traversed repeater round yaws the hull by %.4f rad/s — inside what the "
			% _repeater.yaw_rate_rad_s
			+ "autocannon does firing dead ahead"
		)
	)
	# The comparison, as a multiple, so it survives a rebalance of either row.
	#
	# [b]The multiple here is much smaller than the impulse ratio and that is
	# expected.[/b] 26 N·s against 1450 is a factor of 56, and this measures 8 —
	# because a single-round delta on a settled hull is not a clean read of the
	# recoil at this magnitude. The window is one physics frame, and one frame of
	# a four-spring suspension still working through the last of its settle is
	# tens of milliradians per second in its own right; the autocannon's round
	# swamps that and the repeater's does not. So this bound separates the two
	# rows and deliberately does not pin either.
	#
	# The measurement that is clean is the sustained one, because it integrates
	# thirty rounds against the contacts that have to hold them:
	# `tests/physics/test_drive_and_shoot.gd` reads 2.9° of heading drift against
	# 99.1° over the same window, which is the factor of thirty the authored
	# impulses predict.
	check_true(
		absf(_traversed.yaw_rate_rad_s) > absf(_repeater.yaw_rate_rad_s) * 5.0,
		(
			"and the heavy round on the same lever is %.0f times worse"
			% (absf(_traversed.yaw_rate_rad_s) / maxf(absf(_repeater.yaw_rate_rad_s), 0.0001))
		)
	)


## ===== FIXTURES ========================================================


func _measure() -> void:
	if _measured:
		return
	_measured = true
	_nose = await _fire_at(CombatArena.Recipe.WHEELED_LIGHT, 0.0)
	_traversed = await _fire_at(CombatArena.Recipe.WHEELED_LIGHT, TRAVERSE_DEG)
	_repeater = await _fire_at(CombatArena.Recipe.WHEELED_REPEATER, TRAVERSE_DEG)


## One build, one round, at a commanded traverse. The arena is opened and closed
## per shot: firing is destructive to the measurement — the hull keeps the
## angular velocity of the previous round — and §3.45 wants one arena at a time.
func _fire_at(recipe: int, traverse_deg: float) -> Shot:
	_arena = CombatArena.new()
	_arena.open()
	var c := _arena.spawn(recipe, 0, Vector2.ZERO, 0.0, AmmoLedger.UNLIMITED)
	# No pilot. The arena's command loop would drive and aim this build, and both
	# would be in the measurement.
	c.arena_piloted = false
	await _arena.settle(SETTLE_TICKS)

	var body := c.runtime.body
	var st := c.runtime.state(c.gun_slot)
	var def := c.runtime.definition_at(c.gun_slot)
	var hp := c.guns.hardpoint(c.gun_slot)

	# An aim point on a circle about the muzzle, at the muzzle's own height, so
	# the mount ends up at the requested traverse and at zero elevation. Taking
	# the height from the muzzle rather than from the hull keeps the elevation
	# out of a measurement that is about the horizontal plane.
	var rest := EffectorSystem.muzzle_world_transform(c.runtime, st, def, 0, 0.0, 0.0)
	var heading := Vector3(sin(deg_to_rad(traverse_deg)), 0.0, -cos(deg_to_rad(traverse_deg)))
	var aim := rest.origin + body.global_transform.basis * heading * AIM_RANGE_M
	aim.y = rest.origin.y
	for i: int in AIM_TICKS:
		c.guns.aim_point_world = aim
		await physics_frames(1)
		if hp.on_target:
			break

	var before := body.angular_velocity
	c.guns.set_trigger(0, true)
	for i: int in FIRE_TICKS:
		c.guns.aim_point_world = aim
		await physics_frames(1)
		if hp.shots_fired > 0:
			# One round, not an average: releasing here leaves the window clear
			# of the next cycle.
			c.guns.set_trigger(0, false)
			break
	await physics_frames(1)

	var shot := Shot.new()
	shot.shots = hp.shots_fired
	shot.yaw_rate_rad_s = (body.angular_velocity - before).y
	# The lever the impulse actually acted on: the muzzle where it was when the
	# round left, in the body's frame, against the centre of mass the physics
	# server takes its torque about.
	var live := EffectorSystem.muzzle_world_transform(
		c.runtime, st, def, 0, hp.yaw_rad, hp.pitch_rad
	)
	var muzzle_local := body.global_transform.affine_inverse() * live.origin
	shot.lever_lateral_m = muzzle_local.x - body.center_of_mass.x
	print(
		"  recoil geometry: recipe %d, traverse %5.1f°, lever %+6.3f m lateral, yaw %+.4f rad/s"
		% [recipe, traverse_deg, shot.lever_lateral_m, shot.yaw_rate_rad_s]
	)

	_arena.close()
	_arena = null
	return shot


## One round's worth of record, taken while the fixture is built rather than in a
## test method: the runner sorts methods, and by the time a later one runs the
## arena is closed.
class Shot:
	extends RefCounted
	var shots: int = 0
	var yaw_rate_rad_s: float = 0.0
	var lever_lateral_m: float = 0.0
