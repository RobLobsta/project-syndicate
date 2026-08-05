extends TestCase
## The whole drive cycle a person performs in their first thirty seconds, on
## perfectly smooth ground, measured rather than watched.
##
## Accelerate from a standstill to whatever the build will do, hold full lock,
## stop, back out while turning, shoot, and shoot with the brake held. Six phases,
## one Assembly, one slab, every record taken while the arena is open.
##
## [b]Why a sixth file in [code]tests/physics/[/code] when four of them already
## drive something.[/b] Each of those asks one question with the rest of the cycle
## held still — [code]test_ground_assembly.gd[/code] drives straight at a quarter
## throttle, [code]test_braking_and_reverse.gd[/code] stops four families one at a
## time, [code]test_drive_and_shoot.gd[/code] fires under a quarter throttle. None
## of them turns the Assembly at speed, and that is where it was falling over: doc
## 05 §6.5's anti-roll couple was applied inverted for the life of the project, so
## a full-lock corner from **3.3 m/s** rolled the reference build onto its roof.
## Every one of those files stayed green through it, because none of them asked
## the machine to change direction.
##
## [b]The ground is perfectly smooth and that is the point.[/b] Doc 09's basin
## adds a gravity component an order of magnitude larger than anything measured
## here (LEARNED_FACTS.md §1 fact 81), so a straight-line claim taken on terrain is
## a claim about the terrain. On a level slab there is exactly one thing that can
## turn this Assembly, and it is its own contacts.
##
## One Assembly on a slab reproduces run to run (fact 44), so this file asserts
## values. What it deliberately does not assert is a tick count (fact 54).

## ===== THE WINDOW ======================================================

## Ticks the build is given to fall onto its contacts and stop moving.
const SETTLE_TICKS: int = 180

## Ticks of full throttle. Six seconds: long enough to be clear of the launch and
## short enough that the run is still on the slab.
const ACCEL_TICKS: int = 360

## Ticks of full lock. Two and a half seconds — the steered axle reaches its
## authored 32° stop in under a quarter of a second at 140°/s, so the rest of the
## window is the steady state, which is the part a player feels.
const CORNER_TICKS: int = 150

## Speed, in m/s, the corner is entered at. See [method _corner]: the radius the
## geometry asks for is only reachable below about 6 m/s on this build, so a
## corner entered flat out measures the grip limit rather than the steering.
const CORNER_ENTRY_MPS: float = 5.0

## Throttle held through the corner. Enough to hold the entry speed against
## cornering drag without accelerating out of the window it is measured over.
const CORNER_THROTTLE: float = 0.25

## Ticks of the corner that count as the transient, excluded from the steady-state
## reading. Half a second, which is twice the time the axle takes to reach lock.
const CORNER_SETTLE_TICKS: int = 30

## Ticks of full brake. Four seconds, well beyond any stopping distance this build
## produces, so a build still moving at the end has not stopped.
const BRAKE_TICKS: int = 240

## Ticks of reverse-with-lock.
const REVERSE_TICKS: int = 180

## Ticks the trigger is held in each of the two firing phases.
const FIRE_TICKS: int = 180

## Ticks the mount is given to reach its commanded bearing before a firing phase
## opens. The autocannon slews at 65°/s and the aim point is dead ahead, so this
## is slack rather than a budget.
const AIM_TICKS: int = 120

## ===== WHAT COUNTS AS RIGHT =============================================

## Speed, in m/s, the acceleration phase must exceed for anything below it to mean
## anything. The fixture assertion: every claim about stopping, steering and recoil
## is satisfied in full by a build that never moved.
const MIN_TOP_SPEED_MPS: float = 4.0

## Lateral deviation, in metres, permitted across the whole acceleration run.
##
## [b]Measured against the line the Assembly was pointed down when the throttle
## opened[/b], not against its own nose — a build that curves away and keeps its
## nose on the curve has still not gone straight, and a heading measurement alone
## cannot see that.
##
## The build is metrically symmetric about its centreline and the slab is level,
## so the honest answer here is zero and the measured one is zero to the width of
## a float. The bound is a tenth of a metre because what it is defending against
## is an asymmetry entering the solver — a steer offset, a one-sided anti-roll
## term, a drive share that favours a flank — and any of those is worth far more
## than 0.1 m over twenty-five metres.
const STRAIGHT_LATERAL_M: float = 0.1

## Heading drift, in degrees, permitted across the same run with no steer demand.
const STRAIGHT_HEADING_DEG: float = 1.0

## Yaw rate, in rad/s, above which a straight-line run has spun rather than
## drifted. 0.35 rad/s is 20°/s — a rate a player would have to correct — and it is
## the quantity that separates "it wanders" from "it spins out".
const SPIN_OUT_RAD_S: float = 0.35

## Roll, in degrees, a full-lock corner may reach before the Assembly is on its way
## over. Ten is generous for a build whose static stability factor is 0.97 g; the
## measured steady state is under three, and the inverted couple this file was
## written to catch went past ninety.
const CORNER_ROLL_CEILING_DEG: float = 10.0

## Newtons of normal load the least loaded contact must still carry mid-corner. A
## contact at zero has left the ground, which is the step before a roll-over and
## the one a still frame cannot show.
const CORNER_MIN_NORMAL_N: float = 400.0

## Bounds on the steady-state turn radius at full lock, in metres, as a multiple of
## the bicycle model's `wheelbase / tan(lock)`.
##
## [b]A band rather than a figure, and both ends are a statement about feel.[/b]
## Below 0.8 the Assembly is turning tighter than its own geometry asks for, which
## is oversteer and is how a corner becomes a spin. Above 2.5 it is ploughing —
## the lock is on the stop and the machine is going somewhere else, which is what
## a player calls vague. The reference build measures about 1.9 at speed and 1.3 at
## a walking pace, which is the mild, speed-sensitive understeer a driver expects.
const RADIUS_RATIO_MIN: float = 0.8
const RADIUS_RATIO_MAX: float = 2.5

## Speed, in m/s, at or below which the build counts as stopped.
const STOPPED_MPS: float = 0.30

## Metres a full-lock reverse must cover backwards along the nose it started on.
const REVERSE_FLOOR_M: float = 2.0

## Degrees of heading a full-lock reverse must produce. A reverse that travels and
## does not turn is a reverse a player cannot use to get out of anything.
const REVERSE_YAW_FLOOR_DEG: float = 10.0

## Fraction of upright below which the hull has come off its contacts.
const UPRIGHT_FLOOR: float = 0.90

## Metres the hull may be pushed by a sustained burst while parked. The recoil is
## real and is meant to move it; what would be wrong is the burst driving it away.
const RECOIL_TRAVEL_CEILING_M: float = 3.0

## Range the aim point is placed at, dead ahead at muzzle height. Far enough that
## the mount solves a flat bearing and the elevation stays out of the measurement.
const AIM_RANGE_M: float = 200.0

var _cycle: Cycle = null


## ===== ACCELERATION ====================================================


func test_the_build_accelerates_from_rest_under_full_throttle() -> void:
	await _measure()
	check_true(
		_cycle.top_speed_mps > MIN_TOP_SPEED_MPS,
		(
			"full throttle from a standstill reached %.2f m/s over %.1f m"
			% [_cycle.top_speed_mps, _cycle.accel_travel_m]
		)
	)
	check_true(
		_cycle.accel_grounded_min >= 4,
		(
			"with all four contacts on the ground throughout: %d at worst, %.0f N "
			+ "lightest normal load"
		) % [_cycle.accel_grounded_min, _cycle.accel_min_normal_n]
	)


## [b]The question this file opens with.[/b] Doc 05 §7 gives each contact its own
## friction circle and nothing anywhere imposes symmetry between the two flanks,
## so a build going straight is a result rather than a construction.
func test_it_travels_straight_under_full_throttle_from_a_standstill() -> void:
	await _measure()
	check_true(
		_cycle.accel_lateral_m < STRAIGHT_LATERAL_M,
		(
			"it deviated %.4f m from the line it was pointed down, over %.1f m travelled"
			% [_cycle.accel_lateral_m, _cycle.accel_travel_m]
		)
	)
	check_true(
		_cycle.accel_heading_deg < STRAIGHT_HEADING_DEG,
		"and turned %.3f deg with no steering demand" % _cycle.accel_heading_deg
	)


func test_it_does_not_spin_out_under_full_throttle() -> void:
	await _measure()
	check_true(
		_cycle.accel_peak_yaw_rad_s < SPIN_OUT_RAD_S,
		(
			"peak yaw rate under full throttle was %.4f rad/s (%.2f deg/s)"
			% [_cycle.accel_peak_yaw_rad_s, rad_to_deg(_cycle.accel_peak_yaw_rad_s)]
		)
	)


## ===== THE CORNER ======================================================


## [b]The check that would have caught doc 05 §6.5's inverted couple, and the
## reason this file exists.[/b] A roll-over is not a soft failure that shows up as
## a worse lap time: the couple was positive feedback, so the roll diverged —
## −1.1°, −2.9°, −4.6°, −7.3°, −11.5°, −18.3°, −28.3°, −41.9°, −57.3°, −72.6° on
## successive samples — and the Assembly finished upside down from a walking pace.
func test_a_full_lock_corner_keeps_it_on_its_contacts() -> void:
	await _measure()
	check_true(
		_cycle.corner_worst_roll_deg < CORNER_ROLL_CEILING_DEG,
		(
			"full lock at %.2f m/s rolled it %.2f deg"
			% [_cycle.corner_entry_mps, _cycle.corner_worst_roll_deg]
		)
	)
	check_true(
		_cycle.corner_grounded_min >= 4,
		(
			"and it kept all four contacts loaded: %d at worst, %.0f N on the lightest"
			% [_cycle.corner_grounded_min, _cycle.corner_min_normal_n]
		)
	)
	check_true(
		_cycle.corner_min_normal_n > CORNER_MIN_NORMAL_N,
		(
			"with the inside pair carrying real load rather than skimming: %.0f N"
			% _cycle.corner_min_normal_n
		)
	)


## Tight and controlled, stated as two numbers a player would recognise: the
## Assembly reaches a steady rate of turn rather than winding up, and the radius it
## holds is close to the one its own steering geometry asks for.
func test_the_corner_settles_into_a_steady_rate_of_turn() -> void:
	await _measure()
	check_true(
		_cycle.corner_lock_deg > 30.0,
		"the steered axle reached %.1f deg of its authored lock" % _cycle.corner_lock_deg
	)
	check_true(
		_cycle.corner_yaw_spread_rad_s < 0.1,
		(
			"the yaw rate held inside %.4f rad/s of its mean %.3f across the steady "
			+ "part of the corner"
		) % [_cycle.corner_yaw_spread_rad_s, _cycle.corner_yaw_rad_s]
	)
	var ratio := _cycle.radius_ratio()
	check_true(
		ratio > RADIUS_RATIO_MIN and ratio < RADIUS_RATIO_MAX,
		(
			"and held %.1f m of radius against the %.1f m its geometry asks for "
			+ "(%.2fx) at %.2f m/s"
		) % [
			_cycle.corner_radius_m, _cycle.geometric_radius_m(), ratio,
			_cycle.corner_speed_mps
		]
	)


## ===== BRAKING =========================================================


func test_full_brake_stops_it() -> void:
	await _measure()
	check_true(
		_cycle.brake_end_mps < STOPPED_MPS,
		(
			"it shed %.2f m/s in %.2f m and finished at %.3f"
			% [_cycle.brake_entry_mps, _cycle.stopping_distance_m, _cycle.brake_end_mps]
		)
	)


## A stop that arrives pointed somewhere else is a stop a player has to correct out
## of, and it is a transition no single-phase file can see: the tick the throttle
## becomes the brake is the tick a flank that was driving starts retarding.
func test_it_stops_pointed_where_it_was_going() -> void:
	await _measure()
	check_true(
		_cycle.brake_heading_deg < STRAIGHT_HEADING_DEG,
		"the heading moved %.3f deg across the stop" % _cycle.brake_heading_deg
	)
	check_true(
		_cycle.brake_worst_upright > UPRIGHT_FLOOR,
		(
			"and it stayed on its contacts: %.3f of upright at worst"
			% _cycle.brake_worst_upright
		)
	)


## ===== REVERSE, WITH LOCK ==============================================


## §15.5's release and §7.1's steering geometry in the same window. The release is
## what lets one key be a brake and a reverse gear, and until it existed the demand
## that backed the build out was also holding its contacts still.
func test_it_reverses_under_full_lock() -> void:
	await _measure()
	check_true(
		_cycle.reverse_m < -REVERSE_FLOOR_M,
		"it backed %.2f m along the nose it started on" % _cycle.reverse_m
	)
	check_true(
		absf(_cycle.reverse_yaw_deg) > REVERSE_YAW_FLOOR_DEG,
		(
			"and turned %.1f deg doing it, at %.1f deg of lock"
			% [_cycle.reverse_yaw_deg, _cycle.reverse_lock_deg]
		)
	)
	check_true(
		_cycle.reverse_worst_upright > UPRIGHT_FLOOR,
		(
			"without coming off its contacts: %.3f of upright at worst"
			% _cycle.reverse_worst_upright
		)
	)


## The sign, which is the half a wrong steering convention satisfies. Doc 11 §7.2
## fixes positive steer as right on every input device, and a build reversing under
## right lock swings its nose the other way from a build driving forwards under it:
## the steered axle is the one being dragged.
func test_a_right_lock_reverse_turns_the_opposite_way_from_a_forward_one() -> void:
	await _measure()
	check_true(
		signf(_cycle.reverse_yaw_deg) != signf(_cycle.corner_yaw_deg),
		(
			"forward lock turned it %+.1f deg and reverse lock %+.1f, about the world up"
			% [_cycle.corner_yaw_deg, _cycle.reverse_yaw_deg]
		)
	)


## ===== SHOOTING ========================================================


func test_it_shoots_while_parked() -> void:
	await _measure()
	check_true(
		_cycle.park_entry_mps < STOPPED_MPS,
		"the burst was fired from a standstill: %.3f m/s" % _cycle.park_entry_mps
	)
	check_true(_cycle.park_shots > 0, "the trigger produced %d rounds" % _cycle.park_shots)
	check_true(
		_cycle.park_recoil_travel_m < RECOIL_TRAVEL_CEILING_M,
		(
			"and %d rounds of recoil pushed the parked hull %.2f m"
			% [_cycle.park_shots, _cycle.park_recoil_travel_m]
		)
	)


## The two firing phases differ in one field of one record — `input.brake` — and
## the comparison is the assertion. §7.7's holding brake already pins a parked
## Assembly, so a driver standing on the brake is asking the contacts for
## resistance they are largely producing anyway; what must not happen is the
## service brake making the platform [i]worse[/i].
func test_holding_the_brake_does_not_cost_it_the_firing_platform() -> void:
	await _measure()
	check_true(
		_cycle.brake_fire_shots > 0,
		"the trigger works with the brake held: %d rounds" % _cycle.brake_fire_shots
	)
	# Per round, because doc 07 §4.3.1's fire gate closes while the hull is moving
	# under recoil and the two phases therefore get different numbers of rounds
	# away — sixteen and twenty on the reference build. The disturbance is
	# proportional to the rounds that produced it, so a bare distance would be
	# comparing burst lengths.
	check_true(
		_cycle.brake_fire_travel_per_round() <= _cycle.park_travel_per_round() * 1.3,
		(
			"and the hull moved %.3f m per round against %.3f with no brake demand — "
			+ "it was 9x worse before §7.7 read §15.5's released demand"
		) % [_cycle.brake_fire_travel_per_round(), _cycle.park_travel_per_round()]
	)
	check_true(
		_cycle.brake_fire_heading_deg <= _cycle.park_heading_deg + 1.0,
		(
			"and turned %.3f deg against %.3f"
			% [_cycle.brake_fire_heading_deg, _cycle.park_heading_deg]
		)
	)


## ===== THE RUN =========================================================


func after_all() -> void:
	# Nothing to drain: the arena is closed the moment the record is taken
	# (LEARNED_FACTS.md §1 fact 48). This exists so that a run which failed part-way
	# through says so rather than leaking one.
	pass


func _measure() -> void:
	if _cycle != null:
		return
	_cycle = Cycle.new()
	var arena := CombatArena.new()
	arena.open()
	var c := arena.spawn(
		CombatArena.Recipe.WHEELED_LIGHT, 0, Vector2.ZERO, 0.0, AmmoLedger.UNLIMITED
	)
	# No pilot. The arena's command loop would drive this build toward a target and
	# its steering would be in every measurement below it.
	c.arena_piloted = false
	await arena.settle(SETTLE_TICKS)

	# The order is the one a person performs: open the throttle, stop, turn, back
	# out. The corner sits after the stop rather than before it because a brake
	# measurement taken out of a corner measures the corner — the first version of
	# this file reported 28.5° of heading change "across the stop" and every degree
	# of it was the turn still unwinding.
	await _accelerate(c)
	await _brake(c)
	await _corner(c)
	await _reverse(c)
	await _fire(c, false)
	await _fire(c, true)

	_cycle.report()
	arena.close()


## Full throttle from rest, held past the point the launch is over.
func _accelerate(c: CombatArena.Combatant) -> void:
	var body := c.runtime.body
	var start := body.global_position
	var line := _flat_dir(-body.global_transform.basis.z)
	var input := c.motion.input
	input.throttle = 1.0
	input.steer = 0.0
	input.brake = 0.0
	for i: int in ACCEL_TICKS:
		await physics_frames(1)
		_cycle.top_speed_mps = maxf(_cycle.top_speed_mps, _flat_speed(body))
		_cycle.accel_peak_yaw_rad_s = maxf(
			_cycle.accel_peak_yaw_rad_s, absf(body.angular_velocity.dot(Vector3.UP))
		)
		_cycle.accel_lateral_m = maxf(
			_cycle.accel_lateral_m, absf(_lateral_of(body.global_position - start, line))
		)
		_cycle.accel_heading_deg = maxf(_cycle.accel_heading_deg, _turned_deg(line, body))
		var reading := _contacts(c)
		_cycle.accel_grounded_min = mini(_cycle.accel_grounded_min, int(reading.x))
		_cycle.accel_min_normal_n = minf(_cycle.accel_min_normal_n, reading.y)
	_cycle.accel_travel_m = absf(_along_of(body.global_position - start, line))


## Full right lock from a standstill run-up to [constant CORNER_ENTRY_MPS], with
## the throttle still open through the turn.
##
## [b]The entry speed is held rather than inherited, because the radius ratio this
## phase asserts is only meaningful at a speed the geometry can be followed at.[/b]
## A 3 m wheelbase at 32° of lock asks for a 4.8 m radius, which at 5 m/s needs
## 0.53 g and at 9 needs 1.7 — so a corner entered flat out reports two and a half
## times the geometric radius and the number says "you cannot corner at 9 m/s",
## which is true of every vehicle and is not a fact about this one.
##
## The throttle stays on through the turn deliberately. A corner taken off the
## power is a coast, and doc 05 §7.2's friction circle makes a driving contact
## corner worse than a coasting one — which is correct and is the case a player
## is in.
func _corner(c: CombatArena.Combatant) -> void:
	var body := c.runtime.body
	var input := c.motion.input
	input.brake = 0.0
	input.throttle = 1.0
	for i: int in ACCEL_TICKS:
		await physics_frames(1)
		if _flat_speed(body) >= CORNER_ENTRY_MPS:
			break
	input.throttle = CORNER_THROTTLE
	var entry := _flat_dir(-body.global_transform.basis.z)
	_cycle.corner_entry_mps = _flat_speed(body)
	input.steer = 1.0
	var yaw_sum := 0.0
	var yaw_lo := INF
	var yaw_hi := -INF
	var speed_sum := 0.0
	var samples := 0
	for i: int in CORNER_TICKS:
		await physics_frames(1)
		_cycle.corner_worst_roll_deg = maxf(_cycle.corner_worst_roll_deg, absf(c.roll_deg()))
		_cycle.corner_lock_deg = maxf(_cycle.corner_lock_deg, absf(_widest_steer_deg(c)))
		var reading := _contacts(c)
		_cycle.corner_grounded_min = mini(_cycle.corner_grounded_min, int(reading.x))
		if i < CORNER_SETTLE_TICKS:
			continue
		# The steady state only. The first half-second is the axle travelling to its
		# stop and the hull loading up, and averaging that into the rate of turn
		# would report a corner that is milder than the one being held.
		_cycle.corner_min_normal_n = minf(_cycle.corner_min_normal_n, reading.y)
		var rate := body.angular_velocity.dot(Vector3.UP)
		yaw_sum += rate
		yaw_lo = minf(yaw_lo, rate)
		yaw_hi = maxf(yaw_hi, rate)
		speed_sum += _flat_speed(body)
		samples += 1
	if samples > 0:
		_cycle.corner_yaw_rad_s = yaw_sum / float(samples)
		_cycle.corner_yaw_spread_rad_s = (yaw_hi - yaw_lo) * 0.5
		_cycle.corner_speed_mps = speed_sum / float(samples)
	_cycle.corner_radius_m = _cycle.corner_speed_mps / maxf(absf(_cycle.corner_yaw_rad_s), 1e-4)
	_cycle.corner_wheelbase_m = c.motion.wheelbase_m()
	_cycle.corner_yaw_deg = rad_to_deg(
		entry.signed_angle_to(_flat_dir(-body.global_transform.basis.z), Vector3.UP)
	)
	input.steer = 0.0
	input.throttle = 0.0


## Full brake from whatever the corner left, held past the stop.
func _brake(c: CombatArena.Combatant) -> void:
	var body := c.runtime.body
	var start := body.global_position
	var heading := _flat_dir(-body.global_transform.basis.z)
	var input := c.motion.input
	# The throttle comes off first, because that is what a person does — the two are
	# separate controls on every device doc 11 §7.1 binds. Left on, the contacts get
	# drive and brake at once and settle into an equilibrium rather than stopping:
	# measured at 0.51 m/s, indefinitely, which is correct physics and is not what
	# "brake until it stops" means.
	input.throttle = 0.0
	input.brake = 1.0
	_cycle.brake_entry_mps = _flat_speed(body)
	_cycle.brake_worst_upright = body.global_transform.basis.y.dot(Vector3.UP)
	for i: int in BRAKE_TICKS:
		await physics_frames(1)
		_cycle.brake_worst_upright = minf(
			_cycle.brake_worst_upright, body.global_transform.basis.y.dot(Vector3.UP)
		)
		_cycle.brake_heading_deg = maxf(_cycle.brake_heading_deg, _turned_deg(heading, body))
	_cycle.brake_end_mps = _flat_speed(body)
	_cycle.stopping_distance_m = start.distance_to(body.global_position)


## Full reverse against full right lock, which is what one key and one stick
## produce together and is the manoeuvre a player makes to get off a wall.
func _reverse(c: CombatArena.Combatant) -> void:
	var body := c.runtime.body
	var input := c.motion.input
	# Out of the corner and stopped first, so that what is measured below is the
	# reverse rather than the tail of the turn that preceded it.
	input.throttle = 0.0
	input.steer = 0.0
	input.brake = 1.0
	for i: int in BRAKE_TICKS:
		await physics_frames(1)
	var start := body.global_position
	var nose := _flat_dir(-body.global_transform.basis.z)
	input.throttle = -1.0
	# Held with the brake, because that is what the key produces: §15.5 releases the
	# demand as the hull comes to a stop going forwards, so a driver holding the one
	# key gets a stop and then a reverse without letting go.
	input.brake = 1.0
	input.steer = 1.0
	_cycle.reverse_worst_upright = body.global_transform.basis.y.dot(Vector3.UP)
	for i: int in REVERSE_TICKS:
		await physics_frames(1)
		_cycle.reverse_lock_deg = maxf(_cycle.reverse_lock_deg, absf(_widest_steer_deg(c)))
		_cycle.reverse_worst_upright = minf(
			_cycle.reverse_worst_upright, body.global_transform.basis.y.dot(Vector3.UP)
		)
	_cycle.reverse_m = (body.global_position - start).dot(nose)
	_cycle.reverse_yaw_deg = rad_to_deg(
		nose.signed_angle_to(_flat_dir(-body.global_transform.basis.z), Vector3.UP)
	)
	input.throttle = 0.0
	input.steer = 0.0


## One firing phase: come to a stop, traverse the mount dead ahead, hold the
## trigger.
##
## [param braked] is the single field that differs between the two runs. The
## Assembly is stationary either way, so what the second run adds is a
## service-brake demand on top of a build that is already being held — which is
## exactly what a player does when they stop to shoot.
##
## [b]The stop is held with the brake rather than waited out, and that is a finding
## rather than a convenience.[/b] With no input at all a coasting Assembly is
## retarded by rolling resistance alone — 0.014 of its weight, about 0.14 m/s² —
## and §7.7's holding brake does not engage until 1.5 m/s, so it takes half a
## minute to come to rest from four. Firing during that coast measures the coast.
func _fire(c: CombatArena.Combatant, braked: bool) -> void:
	var body := c.runtime.body
	var input := c.motion.input
	input.throttle = 0.0
	input.steer = 0.0
	input.brake = 1.0
	for i: int in SETTLE_TICKS:
		await physics_frames(1)
	input.brake = 0.0

	var st := c.runtime.state(c.gun_slot)
	var def := c.runtime.definition_at(c.gun_slot)
	var hp := c.guns.hardpoint(c.gun_slot)
	var rest := EffectorSystem.muzzle_world_transform(c.runtime, st, def, 0, 0.0, 0.0)
	# Dead ahead at muzzle height. The recoil then acts down the hull's own
	# longitudinal axis, which is what a player shooting at what they are pointed at
	# produces and the case where a brake could plausibly matter.
	var aim := rest.origin - body.global_transform.basis.z * AIM_RANGE_M
	aim.y = rest.origin.y
	for i: int in AIM_TICKS:
		c.guns.aim_point_world = aim
		await physics_frames(1)
		if hp.on_target:
			break

	var entry := _flat_speed(body)
	var start := body.global_position
	var heading := _flat_dir(-body.global_transform.basis.z)
	var before := hp.shots_fired
	var travel := 0.0
	var turned := 0.0
	input.brake = 1.0 if braked else 0.0
	c.guns.set_trigger(0, true)
	for i: int in FIRE_TICKS:
		c.guns.aim_point_world = aim
		await physics_frames(1)
		travel = maxf(travel, start.distance_to(body.global_position))
		turned = maxf(turned, _turned_deg(heading, body))
	c.guns.set_trigger(0, false)
	input.brake = 0.0

	if braked:
		_cycle.brake_fire_shots = hp.shots_fired - before
		_cycle.brake_fire_travel_m = travel
		_cycle.brake_fire_heading_deg = turned
	else:
		_cycle.park_entry_mps = entry
		_cycle.park_shots = hp.shots_fired - before
		_cycle.park_recoil_travel_m = travel
		_cycle.park_heading_deg = turned


## ===== READINGS ========================================================


## Grounded contact count and lightest normal load this tick, as
## [code](count, newtons)[/code].
##
## The three fields nobody prints (LEARNED_FACTS.md §1 fact 77), and they are here
## for the reason that fact exists: every quantity describing the *demand* said the
## Assembly was cornering correctly right up to the frame it landed on its roof,
## and the contacts' normal loads said it was on two wheels a second earlier.
static func _contacts(c: CombatArena.Combatant) -> Vector2:
	var grounded := 0
	var lightest := INF
	for slot: int in c.motion.motive_slots():
		for i: int in c.motion.contact_count(slot):
			var contact := c.motion.contact_at(slot, i)
			if contact == null or not contact.grounded:
				continue
			grounded += 1
			lightest = minf(lightest, contact.normal_force_n)
	return Vector2(float(grounded), 0.0 if lightest == INF else lightest)


## The widest steer angle currently standing on any of this Assembly's contacts.
static func _widest_steer_deg(c: CombatArena.Combatant) -> float:
	var widest := 0.0
	for slot: int in c.motion.motive_slots():
		var angle := c.motion.steer_angle_deg(slot)
		if absf(angle) > absf(widest):
			widest = angle
	return widest


## Horizontal speed. The vertical component is the suspension and is not what any
## phase here is asking about.
static func _flat_speed(body: RigidBody3D) -> float:
	var v := body.linear_velocity
	return Vector2(v.x, v.z).length()


## [param v] flattened into the horizontal plane and normalised.
##
## Every heading reading in this file goes through it, and the reason is that
## [method Vector3.signed_angle_to] returns the angle between two vectors and only
## takes its [i]sign[/i] from the axis. Handed a nose that is pitched down under
## acceleration it reports that pitch as heading: the first version of this file
## read 0.65° of "drift" on a run whose yaw rate never left the fourth decimal.
static func _flat_dir(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length_squared() < SyndicateConstants.EPSILON_LINEAR:
		return Vector3.FORWARD
	return flat.normalized()


## Degrees between [param heading] and the hull's present nose, about the world up.
static func _turned_deg(heading: Vector3, body: RigidBody3D) -> float:
	return rad_to_deg(
		absf(
			heading.signed_angle_to(
				_flat_dir(-body.global_transform.basis.z), Vector3.UP
			)
		)
	)


## Component of [param offset] across [param line], in the horizontal plane.
static func _lateral_of(offset: Vector3, line: Vector3) -> float:
	return offset.dot(Vector3(line.z, 0.0, -line.x))


## Component of [param offset] along [param line], in the horizontal plane.
static func _along_of(offset: Vector3, line: Vector3) -> float:
	return offset.dot(line)


## One pass through the cycle, recorded while the arena is open. The runner sorts
## methods, and by the time an alphabetically later one runs the arena is closed
## (LEARNED_FACTS.md §1 fact 42).
class Cycle:
	extends RefCounted

	var top_speed_mps: float = 0.0
	var accel_travel_m: float = 0.0
	var accel_lateral_m: float = 0.0
	var accel_heading_deg: float = 0.0
	var accel_peak_yaw_rad_s: float = 0.0
	var accel_grounded_min: int = 99
	var accel_min_normal_n: float = INF

	var corner_entry_mps: float = 0.0
	var corner_worst_roll_deg: float = 0.0
	var corner_lock_deg: float = 0.0
	var corner_grounded_min: int = 99
	var corner_min_normal_n: float = INF
	var corner_yaw_rad_s: float = 0.0
	var corner_yaw_spread_rad_s: float = 0.0
	var corner_speed_mps: float = 0.0
	var corner_radius_m: float = 0.0
	var corner_wheelbase_m: float = 0.0
	var corner_yaw_deg: float = 0.0

	var brake_entry_mps: float = 0.0
	var brake_end_mps: float = 0.0
	var stopping_distance_m: float = 0.0
	var brake_heading_deg: float = 0.0
	var brake_worst_upright: float = 1.0

	var reverse_m: float = 0.0
	var reverse_yaw_deg: float = 0.0
	var reverse_lock_deg: float = 0.0
	var reverse_worst_upright: float = 1.0

	var park_entry_mps: float = 0.0
	var park_shots: int = 0
	var park_recoil_travel_m: float = 0.0
	var park_heading_deg: float = 0.0
	var brake_fire_shots: int = 0
	var brake_fire_travel_m: float = 0.0
	var brake_fire_heading_deg: float = 0.0

	## Metres the hull was pushed per round of the burst that pushed it.
	func park_travel_per_round() -> float:
		return park_recoil_travel_m / maxf(float(park_shots), 1.0)

	func brake_fire_travel_per_round() -> float:
		return brake_fire_travel_m / maxf(float(brake_fire_shots), 1.0)

	## The radius the Assembly's own steering geometry asks for at the lock it
	## reached, in metres: the bicycle model's `wheelbase / tan(lock)`.
	func geometric_radius_m() -> float:
		return corner_wheelbase_m / maxf(tan(deg_to_rad(corner_lock_deg)), 1e-4)

	## What it actually held, as a multiple of that. Above one is understeer.
	func radius_ratio() -> float:
		return corner_radius_m / maxf(geometric_radius_m(), 1e-4)

	## Printed as well as asserted, because half of what this file is for is the
	## shape of the numbers rather than any one threshold (LEARNED_FACTS.md §3,
	## "put the measurement in the assertion message").
	func report() -> void:
		print(
			(
				"  drive cycle: top %.2f m/s over %.1f m, %.4f m lateral, %.3f deg "
				+ "heading, peak yaw %.4f rad/s, %d contacts / %.0f N lightest"
			) % [
				top_speed_mps, accel_travel_m, accel_lateral_m, accel_heading_deg,
				accel_peak_yaw_rad_s, accel_grounded_min, accel_min_normal_n
			]
		)
		print(
			(
				"               corner from %.2f m/s at %.1f deg lock: roll %.2f deg, "
				+ "%d contacts / %.0f N lightest, yaw %.3f+-%.4f rad/s, R %.1f m "
				+ "(geometry %.1f, %.2fx)"
			) % [
				corner_entry_mps, corner_lock_deg, corner_worst_roll_deg,
				corner_grounded_min, corner_min_normal_n, corner_yaw_rad_s,
				corner_yaw_spread_rad_s, corner_radius_m, geometric_radius_m(),
				radius_ratio()
			]
		)
		print(
			(
				"               brake %.2f -> %.3f m/s in %.2f m, %.3f deg of heading, "
				+ "%.3f upright; reverse %+.2f m and %+.1f deg at %.1f deg lock"
			) % [
				brake_entry_mps, brake_end_mps, stopping_distance_m, brake_heading_deg,
				brake_worst_upright, reverse_m, reverse_yaw_deg, reverse_lock_deg
			]
		)
		print(
			(
				"               parked fire %d rounds, %.2f m (%.3f/round), %.3f deg; "
				+ "braked fire %d rounds, %.2f m (%.3f/round), %.3f deg"
			) % [
				park_shots, park_recoil_travel_m, park_travel_per_round(),
				park_heading_deg, brake_fire_shots, brake_fire_travel_m,
				brake_fire_travel_per_round(), brake_fire_heading_deg
			]
		)
