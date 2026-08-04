class_name AiDriver
extends Node
## Drives one Assembly that has no player on it, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §15.7 and
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §10.
##
## The second of §15's three producers of a [ControlInput]. It writes the same
## eight numbers [ControlSystem] writes, out of world state rather than out of the
## input map, and no locomotion family can tell which of them produced the record
## it is reading. That indistinguishability is the contract: everything this
## class does reaches the simulation through [ControlInput],
## [member EffectorSystem.aim_point_world] and a firing-group trigger, which are
## exactly the three surfaces a person with a keyboard reaches the same systems
## through. A driver that could do more would fly a build a player cannot, and
## the first thing anybody learned from watching it fight would be false.
##
## [b]It reacts to [signal MatchClockService.tick_started] and declares no
## per-frame callback[/b], for §15.1's reason: the intent a family reads has to
## have been produced on the tick it is being solved for, and making that a
## property of the clock rather than of scene-construction order is what stops
## one build having a frame of lag the next one does not.
##
## [b]It reads no integrity per tick.[/b] Invariant I-5 keeps integrity and band
## derivation out of hot loops. §10's scoring does read a Core Module's integrity
## fraction, and that read happens inside [method _scan] on §10's 2.9 Hz
## interval; the per-tick path reads a body transform and nothing else.
##
## [b]The rotary family is deliberately not driven here[/b] — §15.7.3. Holding a
## hover is three closed loops that resolve a demand into a world-space thrust
## direction and invert §12.3 back out into swash angles, and a human flying a
## rotary build needs exactly the same loops. That belongs in a stability
## augmentation layer sitting between [i]both[/i] producers and the motion layer,
## which doc 05 does not have yet. Asked to drive a rotary Assembly this aims and
## fires but writes a neutral motion record rather than a wrong one;
## [code]tests/combat_arena.gd[/code] carries the only implementation of the
## hover and names itself a fixture.
##
## [b]It closes with its guns cold[/b] — §15.7.4. The recoil is applied at the
## muzzle, so a mount traversed toward a target off the nose swings its line of
## action out to the two and a quarter metres it sits forward of the centre of
## mass: one round there yaws the reference hull sixty-five times harder than the
## same round fired dead ahead, and a driver that fires on the move is turned off
## its heading faster than it can steer back. This was recorded as a workaround
## for the shipped module's off-centre bore; the bore has since been centred and
## the approach still fails, so what it is really waiting on is a mounting
## position rather than a data fix. The document has the numbers.

## ===== §15.7.1's TACTIC ================================================
## The arithmetic is the whole of the driving, and it is exposed as statics so
## that a unit test — and [code]tests/combat_arena.gd[/code], which runs its own
## command loop over five recipes — can assert it without a node, a clock, or an
## Assembly. Two owners of these gains would be two answers to how a bot drives.

## Heading error, in radians, at which the steering demand saturates.
const STEER_SATURATION_RAD: float = 0.35
## The same, for the ambulatory family, which turns far more slowly.
const AMBULATORY_TURN_SATURATION_RAD: float = 0.60
## Steering demand per radian per second of hull yaw, opposing it. §15.7.2: this
## is what holds an ambulatory hull under the ~30°/s its own mount can track.
const AMBULATORY_YAW_DAMPING: float = 0.55
## Ceiling on an ambulatory steering demand. Below one because §13.5 spends the
## same number on the lateral half of the desired velocity, and a saturated
## demand walks the Assembly 45° off its own nose — a circle rather than an
## approach.
const AMBULATORY_STEER_AUTHORITY: float = 0.5
## Metres from its target a wheeled or tracked driver stops closing at.
##
## [b]It was 6.0, and 6.0 was authored against a hull length nobody had
## measured.[/b] `tests/physics/test_ram_attitude.gd` measures it from the
## colliders — Invariant I-1 makes those the physical footprint — and the
## reference wheeled build reaches [b]2.4 m[/b] from its body origin to its nose.
## Two of them therefore touch at 4.8 m of origin separation, so a six-metre
## stand-off was never a stand-off: it was nose-to-nose parking with 1.2 m of
## air, and the arrival overshoot is about 1.2 m. Measured, the nearest driver
## finished 4.8 m out with an [b]eight-centimetre[/b] gap, which is contact, and
## a stationary 1107 kg Assembly ended up 5.3 m from where it settled.
##
## Ten metres is that touching range plus a full hull length of clear air. It is
## the smallest range at which an approach that overshoots is still an approach,
## and it is what makes §15.7.5's ladder read as a firing line rather than as
## three Assemblies in a heap.
const GROUND_STAND_OFF_M: float = 10.0
## The same, for the ambulatory family, and further out for a reason that is
## about gunnery rather than survivability — §15.7.2.
const AMBULATORY_STAND_OFF_M: float = 20.0
## Metres from its target a rotary driver would hold station at. Carried for the
## day §15.7.3's augmentation layer exists; this class does not fly.
const ROTARY_STAND_OFF_M: float = 22.0
## Throttle a ground driver crawls at while its target is off its nose, and the
## reason §15.7.1 has a throttle law at all rather than a boolean.
##
## Measured. Full throttle held through the turn drives a wheeled build round an
## arc wider than the range it is trying to close: spawned facing away from a
## target 40 m off it turned 53° in two and a half seconds, and the range grew
## from 40 m to 46 m while the bearing sat at 135° — an outward spiral, which is
## what pure pursuit does when the turn radius exceeds the range. Tapering the
## throttle on the heading error tightens the arc until it converges.
##
## The floor is what stops the taper reaching zero, because a steered contact
## needs road speed to make any lateral force at all.
const APPROACH_MIN_THROTTLE: float = 0.35

## Speed, in m/s, below which the taper above is overridden outright.
##
## [b]The floor alone is not enough, and raising it is not the answer.[/b] A
## build stopped dead with the lock over sits there scrubbing its front contacts:
## driven on the taper alone from 180° of heading error it settled at about
## 0.2 m/s and never came round at all. Driving that case off a higher floor was
## tried and measured — 0.80 turns it in 270 ticks on a flat slab — and it
## [i]broke the match[/i], because on the arena's fifteen metres of relief a
## ground build under sustained heavy throttle breaks traction on every slope it
## crosses and the opponents never reached the player at all. A flat fixture
## cannot see that, and the suite was green for it.
##
## So the two failures get the two different treatments they need. The taper's
## floor stays where terrain says it belongs, and the stall is answered by what
## it actually is — a standing start — with a breakaway demand that applies only
## while the Assembly is barely moving and stops applying the moment it is.
const APPROACH_BREAKAWAY_SPEED_MPS: float = 3.0

## Throttle demanded below that speed. High enough to break a scrubbing contact
## away from a standstill, and self-limiting: it stops the instant the Assembly
## is rolling, so it never becomes the sustained heavy throttle that loses grip
## on a slope.
const APPROACH_BREAKAWAY_THROTTLE: float = 0.80

## §15.7.1's arrival brake: the deceleration, in m/s², a ground driver plans its
## approach on.
##
## [b]The document predicted the case that brings this back, and the shipped
## match is it.[/b] §15.7.1 tried an arrival brake, measured it against the
## breakaway law, found it made no difference — 6.4 m and 9 rounds with it, 5.8 m
## and 10 rounds without — and removed it rather than carry a demand nothing
## could distinguish from its absence. It then wrote down exactly what would
## bring it back: [i]an approach that ends fast[/i]. That measurement was taken
## on a driver spawned facing [b]away[/b] from its target, which spends its whole
## approach on the cosine taper and arrives at walking pace. A driver spawned
## facing its target never touches the taper: it holds full throttle for the
## whole run-in, and 34 m of it — the shipped match's nearest opponent spawn — is
## enough to arrive at [b]18.2 m/s[/b]. A bare throttle cut cannot stop 1107 kg
## from there inside a six-metre stand-off, so it does not stop; it drives over
## whatever is standing on the mark.
##
## The demand is a stopping-distance law rather than a gain, because the quantity
## that decides whether a driver arrives or rams is not its speed but
## [code]v² / 2s[/code] — the deceleration the remaining slack would require. The
## profile it holds is [code]v = sqrt(2 · a · slack)[/code]: the driver still
## crosses the field at fifteen metres a second and still arrives at a walk, and
## no part of it is a function of how far away the fight started.
##
## 4.0 is well inside what the reference build can make. Four contacts at
## §7.4's 2600 N·m over a 0.5 m radius is 20.8 kN against 1107 kg, and the
## surface takes that down to about one g — so the plan is under half the
## authority, which is the margin that lets the same number hold on a slope
## without the taper's terrain problem coming back.
const ARRIVAL_DECEL_MPS2: float = 4.0

## Closing speed, in m/s, under which the arrival brake is not demanded at all.
##
## A driver holding station at its stand-off closes and opens by centimetres a
## second as the hull settles and the target drifts, and without a deadband the
## law reads every one of those as an arrival and stands on the brakes. Below
## this there is nothing to arrest.
const ARRIVAL_CLOSURE_DEADBAND_MPS: float = 0.5


## §15.7.5. Extra stand-off, in metres, for each friendly Assembly already closer
## to this driver's target than this driver is.
##
## Three opponents converging on one target at a six-metre stand-off end up in a
## heap, firing through each other: nothing in [code]src/combat/[/code] knows what
## a team is, so a round that clips a friend on the way past does full damage, and
## at least one of them dies to another before the player fires a shot. Not
## obviously wrong as a rule — friendly fire is doc 08's question and a larger one
## — but plainly wrong as a spectacle.
##
## The ladder is what fixes the geometry rather than the rule. Each driver counts
## only the friends [i]nearer[/i] the target than itself, so the set is a strict
## ordering by range and the demands are consistent: the nearest holds at the base
## stand-off, the second at one step out, the third at two. Nobody negotiates,
## nothing is shared, and the arrangement is stable because a driver that
## overtakes its neighbour inherits the shorter stand-off in the same swap that
## gives the neighbour the longer one.
##
## One step is a little over an Assembly's own length, which is the smallest
## spacing at which a hull is not between a friend and the target.
const ALLY_STAND_OFF_STEP_M: float = 4.5
## Cap on the ladder, in steps. Past this the extra range costs more accuracy than
## the spacing buys, and doc 07 §10 does not model a target being obscured, so a
## driver held at sixty metres would be shooting at a hull it cannot resolve.
const ALLY_STAND_OFF_MAX_STEPS: int = 3

## ===== WIRING ==========================================================
## Set before the node enters the tree. The match layer owns every one of these
## and hands them over; nothing here resolves a node by path or searches the tree.

## The Assembly being driven.
var runtime: AssemblyRuntime = null
## The record this driver writes. Shared with the [MotiveSystem] that reads it —
## the same arrangement [ControlSystem] has, and for the same reason.
var input: ControlInput = null
## The motion layer, read only for [method MotiveSystem.family_of]. The driver
## needs to know how the Assembly gets around and nothing else about it.
var motion: MotiveSystem = null
## The Effector Modules. Null on an Assembly that carries none, which then drives
## and never fires rather than failing.
var guns: EffectorSystem = null
## Slot of the mount §10.2's arc cost is asked about, and the one the trigger is
## held on.
var effector_slot: int = SyndicateConstants.INVALID_SLOT
## Where candidates come from.
var registry: AssemblyRegistry = null
## Assembly id -> team. Owned by the match layer; see [AiContext].
var roster: Dictionary = {}

## ===== SETTINGS ========================================================

## §10's difficulty, in [code][0, 1][/code]. 1.0 aims at the Core Module almost
## exactly; 0.0 misses by 2.4 m at a hundred metres. It is an aim-point offset
## and never a damage or rate-of-fire multiplier.
var difficulty: float = 0.75
## Range this driver stops closing at, in metres, before §15.7.5's ladder. Negative
## means "take the family's default at [method _enter_tree]"; set it before then
## to override.
var stand_off_m: float = -1.0
## §7.6's aid authority, carried onto the record exactly as [ControlSystem]
## carries it. A bot drives with the aids a player has, no more and no fewer.
var aid_authority: float = 1.0

## ===== STATE ===========================================================

var _context: AiContext = null
var _rng := RandomNumberGenerator.new()
## Seconds until the next scan. Seeded from the Assembly id by §10.4 so that
## several drivers spawned on one tick do not scan together forever after.
var _scan_countdown_s: float = 0.0
## Id of the current target, or 0. Held by id rather than by handle so that a
## selection made two hundred milliseconds ago can never be aimed at after the
## Assembly it names has been destroyed.
var _target_id: int = 0
## Where that target's Core Module was this tick. Only meaningful when
## [method _resolve_target] has just answered true.
var _target_point: Vector3 = Vector3.ZERO
## §10.3's offset, rolled once per scan and held between them.
var _aim_error: Vector3 = Vector3.ZERO
## Locomotion family, cached at [method _enter_tree] from the lowest-slotted
## Motive Assembly. A build carrying two families is driven as whichever that
## slot carries, which is the same discipline §6.0 rule 1 asks of the force side:
## each family reads what it uses and ignores the rest.
var _family: int = PartEnums.LocomotionMode.GROUND
## Whether this tick's drive demand was an approach rather than station-keeping.
## §15.7.4's trigger reads it: an [AiDriver] closes with its guns cold.
var _closing: bool = false
## §15.7.5's laddered stand-off, resolved once per scan. Per scan rather than per
## tick because it is a function of where everybody is, which §10.1 samples on the
## scan interval and this class may not go behind.
var _stand_off_now_m: float = 0.0


func _enter_tree() -> void:
	# A driver with no record writes its intent into nothing sixty times a second,
	# which presents as an Assembly that sits still rather than as anything
	# diagnosable — the identical failure ControlSystem asserts against.
	assert(input != null, "AiDriver.input must be set before it enters the tree")
	assert(runtime != null, "AiDriver.runtime must be set before it enters the tree")
	_family = _resolve_family()
	if stand_off_m < 0.0:
		stand_off_m = default_stand_off_m(_family)
	# Until the first scan there is no candidate list to count friends in, and a
	# driver spawned inside its own stand-off must not spend that interval closing.
	_stand_off_now_m = stand_off_m
	# Invariant I-9. Two drivers must not miss in lockstep, and the same match
	# must replay identically.
	_rng.seed = runtime.assembly_id
	_scan_countdown_s = AiTargetSelector.initial_scan_offset_s(runtime.assembly_id)
	_context = AiContext.new()
	_context.assembly_id = runtime.assembly_id
	_context.team = int(roster.get(runtime.assembly_id, 0))
	_context.effectors = guns
	_context.effector_slot = effector_slot
	MatchClock.tick_started.connect(_on_tick_started)


func _exit_tree() -> void:
	MatchClock.tick_started.disconnect(_on_tick_started)


## ===== PER TICK ========================================================


## One tick of intent. Separable from the clock so that a test can drive one
## tick without running the engine, through the identical path the clock uses.
func step(dt: float) -> void:
	if not _is_alive():
		idle()
		return

	_scan_countdown_s -= dt
	if _scan_countdown_s <= 0.0:
		_scan_countdown_s += AiTargetSelector.SCAN_INTERVAL_S
		_scan()

	if not _resolve_target():
		# Nothing left to shoot at. An Assembly with no target holds still rather
		# than driving at the last place it saw one: this is the state a match
		# ends in, and an arena of vehicles circling a memory reads as broken
		# rather than as finished.
		idle()
		return

	# Driving first, because §15.7.4's trigger is a function of what the drive
	# demand turned out to be. The mount is aimed either way: a driver that only
	# aimed when it was allowed to shoot would arrive at its stand-off with the
	# barrel still pointing where it set off from.
	_drive_toward(_target_point)
	if guns != null and effector_slot != SyndicateConstants.INVALID_SLOT:
		guns.aim_point_world = _target_point + _aim_error
		# §15.7.4. It closes with its guns cold, because recoil applied at a
		# muzzle two metres forward of the centre of mass yaws the Assembly
		# harder than its steering can correct the moment the mount is traversed
		# — which is every moment it is driving toward something. Measured; the
		# document has the numbers.
		guns.set_trigger(0, not _closing)


## Drops the trigger and centres the controls.
func idle() -> void:
	if guns != null:
		guns.set_trigger(0, false)
	_centre_controls()


## The id this driver is currently shooting at, or 0. Diagnostics and tests.
func target_id() -> int:
	return _target_id


## §15.7.5's laddered stand-off as of the last scan, in metres. Diagnostics and
## tests; [member stand_off_m] is the base it was derived from.
func stand_off_now_m() -> float:
	return _stand_off_now_m


## The context as of the last scan. Diagnostics and tests; a caller that mutates
## it is lying to the next scan, which overwrites it wholesale anyway.
func context() -> AiContext:
	return _context


## ===== THE STATICS =====================================================


## Signed heading error from [param basis]'s forward to [param offset], about the
## world up, in radians. Flattened: a target up a hill is not a target to the
## left, and pitching the bearing into the steering demand makes it one.
static func bearing_to(basis: Basis, offset: Vector3) -> float:
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
	var flat := Vector3(offset.x, 0.0, offset.z)
	if forward.is_zero_approx() or flat.is_zero_approx():
		return 0.0
	return forward.normalized().signed_angle_to(flat.normalized(), Vector3.UP)


## §15.7.1's steering demand for a wheeled or tracked Assembly.
##
## [b]The negation is the rule.[/b] Positive steer is right and a right turn is a
## negative rotation about the world up, so the demand is the negated bearing
## error. Any assertion that only checks the Assembly turned passes against the
## sign that drives it away from its target.
static func steer_demand(bearing_rad: float) -> float:
	return clampf(-bearing_rad / STEER_SATURATION_RAD, -1.0, 1.0)


## §15.7.2's steering demand for an ambulatory Assembly: a yaw [i]rate[/i]
## command rather than a heading command, damped on the hull's own yaw so that it
## never turns faster than its own mount can track.
static func ambulatory_steer_demand(bearing_rad: float, yaw_rate_rad_s: float) -> float:
	return (
		clampf(
			-bearing_rad / AMBULATORY_TURN_SATURATION_RAD
			+ yaw_rate_rad_s * AMBULATORY_YAW_DAMPING,
			-1.0,
			1.0
		)
		* AMBULATORY_STEER_AUTHORITY
	)


## §15.7.1's throttle law: full ahead on the nose, tapering to a crawl as the
## target moves onto the beam and behind.
##
## The cosine is the projection of the approach onto the direction the Assembly
## can actually travel in, which is why it is a cosine rather than a ramp: at 60°
## off the nose only half the speed is closing the range and the rest is widening
## the arc.
static func approach_throttle(bearing_rad: float, speed_mps: float) -> float:
	var demand := clampf(cos(bearing_rad), APPROACH_MIN_THROTTLE, 1.0)
	if speed_mps < APPROACH_BREAKAWAY_SPEED_MPS:
		return maxf(demand, APPROACH_BREAKAWAY_THROTTLE)
	return demand


## §15.7.1's arrival brake demand for a driver [param range_m] from its target,
## stopping at [param stand_off_m], closing at [param closure_mps].
##
## Zero while the remaining slack can absorb the closure at
## [constant ARRIVAL_DECEL_MPS2], rising to full as the deceleration the slack
## would require reaches twice that, and full outright once the driver is inside
## its stand-off and still coming on — which is the one case that is a ram
## rather than an arrival.
##
## [param closure_mps] is the component of velocity along the bearing, not the
## speed: a driver crossing in front of its target is not arriving at it, and
## braking for a range that is not closing would stop the ladder's outer rungs
## from ever taking station.
static func arrival_brake(range_m: float, stand_off_m: float, closure_mps: float) -> float:
	if closure_mps <= ARRIVAL_CLOSURE_DEADBAND_MPS:
		return 0.0
	var slack := range_m - stand_off_m
	if slack <= 0.0:
		return 1.0
	var needed := closure_mps * closure_mps / (2.0 * slack)
	return clampf(needed / ARRIVAL_DECEL_MPS2 - 1.0, 0.0, 1.0)


## The closing speed of [param velocity] onto an offset of [param offset], in
## m/s, positive toward it. Flattened for §15.7.1's reason: a target down a hill
## is not a target being closed on faster.
static func closure_mps(velocity: Vector3, offset: Vector3) -> float:
	var flat := Vector3(offset.x, 0.0, offset.z)
	if flat.is_zero_approx():
		return 0.0
	return Vector3(velocity.x, 0.0, velocity.z).dot(flat.normalized())


## The stand-off a family fights at by default.
static func default_stand_off_m(family: int) -> float:
	match family:
		PartEnums.LocomotionMode.AMBULATORY:
			return AMBULATORY_STAND_OFF_M
		PartEnums.LocomotionMode.ROTARY:
			return ROTARY_STAND_OFF_M
	return GROUND_STAND_OFF_M


## §15.7.5's ladder: [param base_m] pushed out one step per friend already closer
## to the target, capped at [constant ALLY_STAND_OFF_MAX_STEPS].
static func laddered_stand_off_m(base_m: float, closer_allies: int) -> float:
	var steps := clampi(closer_allies, 0, ALLY_STAND_OFF_MAX_STEPS)
	return base_m + float(steps) * ALLY_STAND_OFF_STEP_M


## How many Assemblies on [param context]'s own side are nearer [param target]
## than [param context] is.
##
## Counted off the scan's candidate list rather than off the registry, so it costs
## nothing per tick and reads only what §10.1 already sampled. Ties are not broken
## — two friends at exactly equal range both count as not-closer, which puts them
## on the same rung and is the correct answer for two Assemblies abreast.
static func closer_allies(context: AiContext, target: AiContext.TargetHandle) -> int:
	if context == null or target == null:
		return 0
	var own := context.position.distance_squared_to(target.position)
	var count := 0
	for handle: AiContext.TargetHandle in context.visible_assemblies:
		if handle.team != context.team or handle.id == target.id:
			continue
		if handle.position.distance_squared_to(target.position) < own:
			count += 1
	return count


## ===== PRIVATE =========================================================


func _on_tick_started(_tick: int) -> void:
	step(SyndicateConstants.PHYSICS_DT)


func _drive_toward(aim: Vector3) -> void:
	if _family == PartEnums.LocomotionMode.ROTARY:
		# §15.7.3. Not flying it is the decision; flying it badly would be the bug.
		# A rotary Assembly this driver cannot fly is still a mount that can shoot.
		_centre_controls()
		_closing = false
		return

	var body := runtime.body
	var offset := aim - body.global_position
	offset.y = 0.0
	input.brake = 0.0
	input.traction_control = clampf(aid_authority, 0.0, 1.0)
	if offset.length_squared() < SyndicateConstants.EPSILON_LINEAR:
		input.throttle = 0.0
		input.steer = 0.0
		_closing = false
		return

	var bearing := bearing_to(body.global_transform.basis, offset)
	var closing := offset.length() > _stand_off_now_m
	_closing = closing
	if _family == PartEnums.LocomotionMode.AMBULATORY:
		# An ambulatory Assembly walks in the direction §13.5's placement law is
		# given, not along its own nose, so a heading error does not widen its
		# approach and the taper would only slow it down.
		input.throttle = 1.0 if closing else 0.0
		input.steer = ambulatory_steer_demand(bearing, body.angular_velocity.y)
		return
	# §15.7.1's arrival law. The brake and the throttle come out of one number so
	# that the two cannot fight: at half demand the driver has lifted off and is
	# braking gently, at full it is off the throttle entirely. A driver that
	# accelerated and braked at once would be asking the same contacts for both.
	var arrival := arrival_brake(
		offset.length(), _stand_off_now_m, closure_mps(body.linear_velocity, offset)
	)
	input.brake = arrival
	input.throttle = (
		approach_throttle(bearing, body.linear_velocity.length()) * (1.0 - arrival)
		if closing
		else 0.0
	)
	input.steer = steer_demand(bearing)


func _centre_controls() -> void:
	if input == null:
		return
	input.throttle = 0.0
	input.steer = 0.0
	input.brake = 0.0
	input.collective = 0.0
	input.cyclic = Vector2.ZERO
	input.yaw = 0.0


## §10's scan: rebuild the candidate set, score it, and roll the aim error for
## the interval that follows.
func _scan() -> void:
	if registry == null:
		return
	_context.rescan(registry, roster)
	var choice := AiTargetSelector.select(_context)
	if choice == null:
		_target_id = 0
		_aim_error = Vector3.ZERO
		_stand_off_now_m = stand_off_m
		return
	_target_id = choice.id
	_aim_error = AiTargetSelector.difficulty_error(
		choice.position.distance_to(_context.position), difficulty, _rng
	)
	# §15.7.5. Recomputed here rather than per tick: it is a function of where
	# every Assembly is, and the candidate list is sampled on this interval.
	_stand_off_now_m = laddered_stand_off_m(stand_off_m, closer_allies(_context, choice))


## Writes this tick's aim point into [member _target_point], resolved fresh from
## the registry rather than read off the scan's handle. False when the target is
## gone, which drops the trigger this tick and leaves the next scan to pick again.
##
## §10 runs selection at 2.9 Hz and aim solving every tick, and this is the
## difference between the two. A handle's position is 350 ms old at worst, which
## at a closing speed of 4 m/s is more than a metre of error in the wrong
## direction — an AI shooting at where its target used to be would look like a
## targeting defect and would in fact be a scheduling one.
func _resolve_target() -> bool:
	if _target_id == 0 or registry == null:
		return false
	var target := registry.get_runtime(_target_id)
	if target == null:
		_target_id = 0
		return false
	var st := target.state(SyndicateConstants.CORE_SLOT)
	if st == null or st.has_flag(PartFlags.FLAG_DESTROYED):
		_target_id = 0
		return false
	_target_point = target.part_world_position(SyndicateConstants.CORE_SLOT)
	return true


## Invariant I-2, read from the part rather than from a flag this class keeps, so
## that nothing here can disagree with [DamageResolver].
func _is_alive() -> bool:
	if runtime == null or not is_instance_valid(runtime):
		return false
	var core := runtime.state(SyndicateConstants.CORE_SLOT)
	return core != null and not core.has_flag(PartFlags.FLAG_DESTROYED)


## The family of the lowest-slotted Motive Assembly, or GROUND when there is
## none — a build with no way of moving still aims and fires, and driving it is
## then a no-op rather than a special case.
func _resolve_family() -> int:
	if motion == null:
		return PartEnums.LocomotionMode.GROUND
	var slots := motion.motive_slots()
	if slots.is_empty():
		return PartEnums.LocomotionMode.GROUND
	return motion.family_of(slots[0])
