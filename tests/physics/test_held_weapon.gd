extends TestCase
## An Appendage holding an Effector Module, and the held module cutting
## something. Doc 01 §4.3 and §7.8, doc 07 §15.
##
## Three things arrived together and none of them is worth anything alone: a
## part class that can hold a weapon, a keyed connector that makes "held"
## different from "bolted", and the swept-volume query of §15.3 that had been
## computed but never run since session 8. An arm with nothing to hold is a
## bracket; a sword nothing can hold is scenery; and a sword that cannot cut is
## a mass penalty.
##
## The file therefore asserts the whole chain in one fixture: the sword goes in
## the hand, the sword goes [i]nowhere else[/i], the arm is recognised as its
## holder, and a swing delivers doc 08 §4's damage to a different Assembly with
## the THERMAL share the edge authors. The energy-damage half of that is the
## point of using this weapon rather than the autocannon — until now nothing in
## the repository had ever delivered a non-KINETIC packet from a weapon.

const CORE_KEY := &"core.command.compact.t2"
const PANEL_KEY := &"str.panel.medium.t2"
const ARM_KEY := &"apx.arm.manipulator.t3"
const SWORD_KEY := &"eff.melee.beam_edge.t4"

const ATTACKER := 61
const TARGET := 62

const CORE_ORIGIN := Vector3i(24, 8, 24)
## The arm hangs off the Core Module's -Z face, so the hand points forward and
## the blade extends forward from it. A shoulder mounted underneath would put the
## blade in the ground.
const ARM_ORIGIN := Vector3i(24, 8, 20)

const ATTACKER_POSE := Vector3(400.0, 60.0, 400.0)
## How far along the blade the target is planted, measured from the hand.
##
## [b]Deliberately not the blade's midpoint.[/b] §15.3's capsule spans hand to
## tip and the shape it replaced was a ball at half the reach, so a target parked
## at half the reach is found by both and separates neither — a fault sweep is
## what said so, after this fixture was first written that way and let a
## reverted capsule through. At the full reach the ball falls 0.40 m short of the
## target's nearest face while the capsule overlaps it by 0.63 m, and a capsule
## left standing on its own +Y misses by more still.
const TARGET_RANGE_M: float = 2.40

## §10.5's authored mix: overwhelmingly thermal, which is what makes this an
## energy weapon rather than a club. Quoted, not imported.
const DOC_THERMAL_SHARE: float = 0.75
const DOC_KINETIC_SHARE: float = 0.10

## Long enough for wind-up (0.28 s) plus the swing (0.22 s) at 60 Hz, with room
## for the mount to slew onto the target first.
const SWING_TICKS := 90

## ===== SUSTAINED CONTACT (§15.5) =======================================

## Doc 01 §10.5's authored sustained rate for the shipped edge, and doc 01
## §10.1's thermal figures for the chassis it is held against. Quoted, never
## imported.
const DOC_SUSTAINED_DAMAGE_S: float = 340.0
const DOC_CORE_THERMAL_RESISTANCE: float = 0.10
const DOC_CORE_ARMOUR: float = 18.0
const DOC_ARMOUR_HALF: float = 40.0
## (1 − 0.10) · (1 − 18/(18 + 40)) = 0.6206897 of a thermal point reaches this
## chassis. Doc 08 §4.5's absorption curve and §7's resistance row, multiplied
## out once here so that every expectation below is arithmetic rather than a
## second call into the code under test.
const CORE_THERMAL_FRACTION: float = 0.6206897
## One tick of contact: 340 damage/s at a 0.75 thermal share over 1/60 s, through
## the fraction above. 340 · 0.75 / 60 = 4.25 raw, and 4.25 · 0.6206897 = 2.6379.
const EXPECTED_SUSTAINED_THERMAL_PER_TICK: float = 2.6379

## Ceiling on the held phase. Contact deposits 140 HU/s of heat (§7.1's ratio on
## the same raw amount), so 480 HU arrives about three and a half seconds in and
## this is roughly twice that — a budget, not a duration.
const SUSTAIN_TICK_BUDGET: int = 420
## Ticks the trigger is off at the end, to watch the fire burn without contact.
## Seven tenths of a second is seven of §7.3's instalments.
const BURN_TICKS: int = 42
## The floor those seven instalments have to clear. 7 · 4.0 · 0.1 · 0.6206897 =
## 1.74, and the assertion is written at 1.0 so that a scheduler which lost an
## instalment to the tick it ignited on is still a pass and one running at zero
## is not.
const MIN_BURN_DAMAGE: float = 1.0

var _contexts: Array[BuildContext] = []
var _runtimes: Array[AssemblyRuntime] = []
var _resolver: DamageResolver = null
var _dot: DotScheduler = null
var _guns: EffectorSystem = null
var _registry: AssemblyRegistry = null

var _measured: bool = false
var _sword_slot: int = SyndicateConstants.INVALID_SLOT
var _arm_slot: int = SyndicateConstants.INVALID_SLOT
var _sword_on_structure_rejected: bool = false
var _damage_by_channel: PackedFloat32Array = PackedFloat32Array()
var _victims: PackedInt32Array = PackedInt32Array()
var _swings_started: int = 0
var _swept_samples: int = 0
## Swings that reached the target at all, and strikes resolved against it. §15.3
## deduplicates per swing, so these two must be equal however many capsules cover
## the arc — which is the assertion the sample count would otherwise break.
var _swings_landed: int = 0
var _strikes_on_target: int = 0
## Swing indices that reached the target, so a swing striking on two ticks is one
## landed swing and not two.
var _landed_swings: PackedInt32Array = PackedInt32Array()
## The target's velocity the first tick it has one — §15.4's impulse, read
## through the only layer that consumes it.
var _first_push: Vector3 = Vector3.ZERO
## The hand the edge swings from, and where the strike landed. The vector between
## them is the radius at the contact, which is what the impulse must be square to.
var _hand_world: Vector3 = Vector3.ZERO
var _strike_point: Vector3 = Vector3.ZERO
## One entry per distinct (swing, slot) pair seen, so the several per-channel
## packets of one strike are counted once. Keyed on the swing rather than cleared
## per swing, because the packets arrive inside a physics frame and the stage is
## only sampled between them.
var _struck_keys: PackedInt32Array = PackedInt32Array()

## True while the discrete-strike half of the fixture is running. Everything the
## swing counters hold is a property of [i]one swing[/i], and a held edge submits
## a packet every tick; without the switch the sustained phase would be counted
## as several hundred strikes and §15.3's per-swing deduplication would look
## broken.
var _recording_swing: bool = true
## THERMAL damage the target took during the sustained phase alone.
var _sustained_thermal: float = 0.0
## Where the target was planted, so the sustained phase can put it back after
## §15.4's impulse has moved it.
var _target_pose: Vector3 = Vector3.ZERO

## §15.5's record: the ticks a held edge resolved on, the first instalment it
## delivered, and what the heat it deposited did to the target afterwards.
var _sustain_contact_ticks: int = 0
var _first_sustained_thermal: float = -1.0
var _energised_ticks: int = 0
var _ignited: bool = false
var _burning_at_release: bool = false
var _integrity_at_release: float = -1.0
var _integrity_after_burn: float = -1.0
var _contact_after_release: bool = false


func before_all() -> void:
	_damage_by_channel.resize(PartEnums.DAMAGE_CHANNEL_COUNT)
	EventBus.part_damaged.connect(_on_part_damaged)


func after_all() -> void:
	EventBus.part_damaged.disconnect(_on_part_damaged)
	if _guns != null:
		_guns.free()
	if _dot != null:
		_dot.free()
	if _resolver != null:
		_resolver.free()
	for runtime in _runtimes:
		runtime.free()
	_runtimes.clear()
	for ctx in _contexts:
		ctx.dispose()
	_contexts.clear()


## ===== THE GRIP (doc 01 §4.3) ==========================================


func test_the_sword_is_held_in_the_arms_hand() -> void:
	await _measure()
	check_true(_arm_slot != SyndicateConstants.INVALID_SLOT, "the Appendage was placed")
	check_true(_sword_slot != SyndicateConstants.INVALID_SLOT, "and the edge went into its hand")


## The other half of the keying, and the half that makes it mean something. A
## GRIP node mates only with another GRIP, so the same edge that the hand accepts
## is refused by every structural face in the game.
func test_the_same_sword_cannot_be_bolted_to_structure() -> void:
	await _measure()
	check_true(
		_sword_on_structure_rejected,
		"a held Effector Module is refused by a Structural Component"
	)


## §7.8's holder resolution: [EffectorSystem] walks the Chassis Graph up from the
## module to the first Appendage. Without it §8.2's Appendage row has nothing to
## multiply and damage to an arm would not slow the sword in it.
func test_the_arm_is_recognised_as_the_holder() -> void:
	await _measure()
	if _guns == null:
		return
	check_approx(
		_guns.effective_cycle_multiplier(_sword_slot), 1.0,
		"an undamaged arm holding an undamaged edge costs nothing"
	)
	_guns.on_holder_band_changed(_arm_slot, PartEnums.IntegrityBand.IMPAIRED)
	check_approx(
		_guns.effective_cycle_multiplier(_sword_slot), 1.45,
		"§8.2's Appendage row at IMPAIRED reaches the edge the arm is holding"
	)
	_guns.on_holder_band_changed(_arm_slot, PartEnums.IntegrityBand.NOMINAL)


## ===== THE SWING (doc 07 §15) ==========================================


func test_the_swing_runs_its_stage_machine() -> void:
	await _measure()
	var state := _guns.strike_state(_sword_slot)
	if not check_not_null(state, "the melee module has a §15.2 strike record"):
		return
	check_true(
		_swings_started > 0,
		"the trigger started %d strike(s) once the mount was on target" % _swings_started
	)
	check_true(_swept_samples > 0, "and §15.3's sweep ran: %d capsule queries" % _swept_samples)


## §15.3's sweep lands, which is the whole reason the class, the connector and
## the part were authored.
func test_the_swing_cuts_the_other_assembly() -> void:
	await _measure()
	check_true(
		_victims.size() > 0,
		"the edge reached the target hull: %d packets" % _victims.size()
	)


## §15.4's channel split, and the first non-KINETIC damage anything in this
## repository has ever produced from a weapon.
##
## Asserted as a [i]ratio[/i] against the authored mix rather than as an absolute,
## because the absolute has doc 08 §4's armour curve between it and the profile
## and this file is not the place that curve is owned. The ratio survives that:
## both channels meet the same part with the same armour, so whatever §4 does to
## one it does to the other, and 0.75 against 0.10 has to come out the far side
## as thermal dominating.
func test_the_edge_delivers_its_damage_as_heat() -> void:
	await _measure()
	var thermal := _damage_by_channel[PartEnums.DamageChannel.THERMAL]
	var kinetic := _damage_by_channel[PartEnums.DamageChannel.KINETIC]
	if not check_true(thermal > 0.0, "the THERMAL channel was delivered: %.1f" % thermal):
		return
	check_true(
		thermal > kinetic,
		"and it dominates the KINETIC share it is authored against: %.1f vs %.1f"
			% [thermal, kinetic]
	)


## §15.3's target set is deduplicated per swing, so the sample count is invisible
## to balance. Without it a 16-sample swing would deal sixteen times a 6-sample
## one and [member MeleeProfile.swing_samples] would be unauthorable.
##
## The load-bearing assertion is the packet [b]count[/b], not the strike count: a
## strike submits exactly one packet per non-zero channel share (§15.4), so a
## swing that resolved once produces three and a swing that resolved per sample
## produces up to forty-eight. Nothing weaker separates those, which is why this
## does not simply assert that damage arrived.
func test_a_swing_resolves_once_however_many_samples_cover_it() -> void:
	await _measure()
	var melee: MeleeProfile = _sword_definition().effector_profile.melee_profile
	# Everything after this is unfalsifiable if one capsule covered the arc.
	if not check_true(
		melee.swing_samples > 2,
		"the arc is covered by %d capsules, so a per-sample resolve would show"
			% melee.swing_samples
	):
		return
	var shares := 0
	for channel: int in PartEnums.DAMAGE_CHANNEL_COUNT:
		if melee.channel_mix[channel] > 0.0:
			shares += 1
	check_eq(
		_strikes_on_target, _swings_landed,
		"each landed swing struck the one target once"
	)
	check_eq(
		_victims.size(), _strikes_on_target * shares,
		"and delivered one packet per authored channel share, not one per capsule"
	)


## §15.1's third reason a projectile is the wrong implementation, asserted as a
## direction: [i]a blade swung across a target knocks it sideways, not
## backwards.[/i]
##
## This is the assertion the impulse direction cannot survive being taken from
## the blade's own axis instead of from the edge's travel. Both are unit vectors
## out of the same transform and they are perpendicular, so nothing that reads a
## magnitude can tell them apart — and the target has to be unfrozen for either
## to be visible at all.
##
## Asserted against the radius the edge is actually swinging on rather than
## against a world axis. The blade reaches this target on its [i]corner[/i], about
## 50° into the arc rather than at the middle of it, so an assertion phrased in
## world X and Z is right for one contact angle and wrong for every other. The
## radius is the frame the claim is true in at all of them: the travel is a chord
## of the swing circle and a chord is square to its own radius.
func test_the_strike_knocks_the_target_sideways_not_backwards() -> void:
	await _measure()
	if not check_true(_first_push.length() > 0.01, "§15.4's impulse reached the target"):
		return
	var radius := _strike_point - _hand_world
	var melee: MeleeProfile = _sword_definition().effector_profile.melee_profile
	# Also pins the capsule's centring: §15.3 puts the edge origin at half the
	# reach along the blade, and a strike recorded anywhere else means the volume
	# being queried is not the volume the blade occupies.
	check_approx(
		radius.length(), melee.reach_m * 0.5,
		"the strike landed half a reach from the hand", 0.01
	)
	var alignment := absf(_first_push.normalized().dot(radius.normalized()))
	check_true(
		alignment < 0.15,
		"and the push is square to that radius: |cos| = %.3f, %.1f° off perpendicular"
			% [alignment, rad_to_deg(asin(alignment))]
	)


## §15.3's gap arithmetic, asserted by value against the document rather than by
## importing it.
##
## The query is a sequence of static capsules — `intersect_shape` ignores
## `motion`, measured — so consecutive placements only overlap out to
## [code]2·r·(n−1)/arc[/code]. This is the check that fails if anyone lowers the
## sample count back toward the 6 that left a 1.26 m hole at the blade tip.
func test_the_arc_samples_overlap_over_most_of_the_blade() -> void:
	await _measure()
	var melee: MeleeProfile = _sword_definition().effector_profile.melee_profile
	var gapless := (
		2.0 * melee.edge_radius_m * float(melee.swing_samples - 1)
		/ deg_to_rad(melee.swing_arc_deg)
	)
	check_approx(gapless, 2.063, "§15.3's gap-free radius for the shipped edge", 0.01)
	check_true(
		gapless > melee.reach_m * 0.85,
		"which covers %.2f m of the %.2f m blade" % [gapless, melee.reach_m]
	)


## ===== SUSTAINED CONTACT (§15.5) =======================================


## The stage that does not advance, seen from the far end: an edge held against a
## hull goes on cutting it instead of recovering.
##
## The load-bearing number is the [b]tick count[/b], not the damage. §15.3
## deduplicates a target for the whole swing, so an implementation that held the
## stage and forgot §15.5's one line — clearing the victim set per tick rather
## than per swing — delivers exactly one packet and then nothing at all for as
## long as the trigger is down, which no assertion about damage arriving can
## separate from a correct one.
func test_a_held_edge_cuts_every_tick_rather_than_once() -> void:
	await _measure()
	if not check_true(_energised_ticks > 0, "the edge stayed in contact past its arc"):
		return
	check_eq(
		_sustain_contact_ticks, _energised_ticks,
		"and resolved on every one of the %d ticks it was held, not on the first"
			% _energised_ticks
	)
	check_true(
		_sustain_contact_ticks > 60,
		"over %d ticks of contact, which is long enough for a per-swing "
			% _sustain_contact_ticks + "immunity to show as a gap"
	)


## The rate, against the authored figure rather than against itself. One tick of
## contact is [member MeleeProfile.sustained_damage_s] over the tick, split by
## the same [member MeleeProfile.channel_mix] a strike uses — which is what makes
## a held edge worth 340 a second and not 640 a tick.
func test_one_tick_of_contact_is_worth_the_authored_rate() -> void:
	await _measure()
	if not check_true(_first_sustained_thermal > 0.0, "an instalment was delivered"):
		return
	check_approx(
		_first_sustained_thermal, EXPECTED_SUSTAINED_THERMAL_PER_TICK,
		"340 damage/s at a 0.75 thermal share over 1/60 s, through this chassis's armour",
		1e-3
	)


## Doc 08 §7.1, reached the way a match reaches it. A thermal packet deposits
## heat as well as damage, so an edge held on one part for three and a half
## seconds sets it alight — which is the first time anything in this project has
## produced a burning part from a weapon.
func test_holding_the_edge_on_a_part_sets_it_on_fire() -> void:
	await _measure()
	check_true(
		_ignited,
		"the target's Core Module crossed the ignition threshold after %d ticks of contact"
			% _sustain_contact_ticks
	)
	check_true(_burning_at_release, "and was in §7.3's list when the trigger came off")


## And the fire is a fire: it goes on taking integrity with nothing touching the
## part. Without §7.3 the flag is set, nothing reads it, and this reads zero.
func test_the_fire_burns_on_after_the_edge_is_taken_away() -> void:
	await _measure()
	check_false(_contact_after_release, "the edge recovered when the trigger came off")
	if not check_true(_integrity_at_release > 0.0, "the target survived the contact"):
		return
	check_true(
		_integrity_at_release - _integrity_after_burn > MIN_BURN_DAMAGE,
		"and burned for %.2f more integrity over half a second of nothing"
			% [_integrity_at_release - _integrity_after_burn]
	)


## ===== FIXTURE =========================================================


func _measure() -> void:
	if _measured:
		return
	_measured = true

	_registry = AssemblyRegistry.new()

	var attacker := _build_attacker()
	if attacker == null:
		return
	# The target is placed from where the edge actually is, not from a guessed
	# offset. The sword sits forward of the arm, which sits forward of the hull,
	# and the edge extends a further reach beyond that — three separate lattice
	# facts whose sum is not worth writing down by hand and is wrong the moment
	# any of them changes.
	var target := _build_target(_edge_world_origin(attacker))
	if target == null:
		return

	_resolver = DamageResolver.new()
	_resolver.registry = _registry
	EventBus.get_tree().root.add_child(_resolver)

	# Doc 08 §7.3, in the tree so that it runs itself: the burn phase below is
	# about what happens with nothing driving anything, and a scheduler this file
	# stepped by hand would be a fixture asserting its own loop.
	_dot = DotScheduler.new()
	_dot.resolver = _resolver
	_resolver.dot = _dot
	EventBus.get_tree().root.add_child(_dot)

	_guns = EffectorSystem.new()
	_guns.runtime = attacker
	_guns.resolver = _resolver
	_guns.space = EventBus.get_tree().root.world_3d.direct_space_state
	_guns.seed_rng(7)
	EventBus.get_tree().root.add_child(_guns)
	_guns.register(_sword_slot, attacker.definition_at(_sword_slot))

	# The mount has to converge before §15 will start a strike, exactly as a
	# barrel does — an edge pinned outside its arc holds off (§4.3.1).
	# The hull, not the lattice origin. Those differ by 1.375 m on this build, and
	# a mount authoring 20° of depression cannot reach the second from the first.
	_guns.aim_point_world = target.part_world_position(0)
	_guns.set_trigger(0, true)
	# Driven by the system's own [code]_physics_process[/code] and by nothing else.
	# Calling [method EffectorSystem.step] here as well would advance the stage
	# machine twice per tick, which halves every authored duration and puts half
	# the swing outside anything this loop can observe.
	var previous := MeleeStrikeState.Stage.READY
	for i: int in SWING_TICKS:
		await physics_frames(1)
		var state := _guns.strike_state(_sword_slot)
		if state.stage == MeleeStrikeState.Stage.WIND_UP and previous != state.stage:
			_swings_started += 1
			# Released the moment the strike commits, and the discrete half of
			# this file is what that buys. §15.5 holds a sustained edge in the
			# swing for as long as the trigger is down, so a trigger left on
			# would run one swing and then cut continuously — and every
			# per-swing assertion above would be measuring a beam. A committed
			# swing runs to completion whatever the trigger does (§15.2), so
			# nothing about the strike itself changes.
			_guns.set_trigger(0, false)
		if state.stage == MeleeStrikeState.Stage.SWINGING:
			_swept_samples += MeleeSolver.sample_progress(
				attacker.definition_at(_sword_slot).effector_profile.melee_profile
			).size()
		if _first_push.is_zero_approx():
			_first_push = target.body.linear_velocity
			_strike_point = state.last_strike_point_world
		previous = state.stage

	await _sustain(target)



## §15.5's half: the trigger goes back down, the edge holds where the arc ended,
## and the target takes an instalment a tick until it catches fire. Then the
## trigger comes off and doc 08 §7.3's list is left to burn on its own.
##
## The target is put back where it was planted first. §15.4's impulse moved it —
## which is the measurement immediately above — and a sustained phase measuring
## an edge that is no longer touching anything would report zero and read as
## §15.5 being unimplemented. That is not a hypothetical: it is what the first
## run of this phase did, and the reading was "the edge cut once and stopped".
func _sustain(target: AssemblyRuntime) -> void:
	_recording_swing = false
	target.body.linear_velocity = Vector3.ZERO
	target.body.angular_velocity = Vector3.ZERO
	target.body.global_position = _target_pose
	# Frozen for this phase, and it takes nothing out of the measurement: §15.5
	# delivers no impulse, so the only thing that could move this hull is the
	# discrete strike that precedes the hold — and a target knocked half a metre
	# down the blade mid-phase measures the drift rather than the contact. A
	# frozen body is still found by the sweep and still resolves damage (fact 41).
	target.body.freeze = true

	var core: PartInstanceState = target.states[SyndicateConstants.CORE_SLOT]
	# The heat the first swing deposited is discarded, so that the ignition below
	# is a property of this phase alone. Doc 08 §7.1 treats a packet with no
	# interval as a full second's deposit, so one 480-raw thermal strike is worth
	# 264 HU and two of them light this chassis without any contact at all —
	# which is real, is how a beam edge behaves in a fight, and is not what §15.5
	# is being measured for here.
	core.accumulated_heat_hu = 0.0
	_guns.set_trigger(0, true)
	for i: int in SUSTAIN_TICK_BUDGET:
		var before := _sustained_thermal
		await physics_frames(1)
		var state := _guns.strike_state(_sword_slot)
		if not state.energised:
			continue
		_energised_ticks += 1
		var delta := _sustained_thermal - before
		if delta > 0.0:
			_sustain_contact_ticks += 1
			if _first_sustained_thermal < 0.0:
				# The first instalment only. Once the target is alight §7.3's own
				# packets arrive on the same channel and the delta stops being
				# one tick of contact.
				_first_sustained_thermal = delta
		if _dot.is_burning(TARGET, SyndicateConstants.CORE_SLOT):
			_ignited = true
			break

	_burning_at_release = _dot.is_burning(TARGET, SyndicateConstants.CORE_SLOT)
	_integrity_at_release = core.integrity
	_guns.set_trigger(0, false)
	for i: int in BURN_TICKS:
		await physics_frames(1)
	_integrity_after_burn = core.integrity
	_contact_after_release = _guns.strike_state(_sword_slot).energised
	print(
		(
			"  held edge: %d ticks of contact at %.3f thermal a tick, "
			% [_sustain_contact_ticks, _first_sustained_thermal]
		)
		+ (
			"ignited: %s; burned %.2f more integrity over %d ticks with nothing touching it"
			% [_ignited, _integrity_at_release - _integrity_after_burn, BURN_TICKS]
		)
	)


func _build_attacker() -> AssemblyRuntime:
	var ctx := BuildContext.with_physics(ATTACKER)
	_contexts.append(ctx)
	var core := PartRegistry.definition_by_key(CORE_KEY)
	var arm := PartRegistry.definition_by_key(ARM_KEY)
	var sword := PartRegistry.definition_by_key(SWORD_KEY)

	PlacementValidator.commit(ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))

	# Shoulder (+Y) onto the Core Module's -Z face, so the hand points forward
	# and the blade runs on ahead of it rather than into the ground.
	var arm_orientation := _orientation_carrying(Vector3.UP, Vector3.BACK)
	_arm_slot = _place_near(ctx, arm, CORE_ORIGIN, arm_orientation)
	if _arm_slot == SyndicateConstants.INVALID_SLOT:
		return null

	# The hilt (+Z) has to oppose the hand, which now faces -Z, so the edge goes
	# in unrotated and its blade continues along -Z.
	var arm_origin: Vector3i = ctx.states[_arm_slot].origin_cell
	_sword_slot = _place_near(ctx, sword, arm_origin, 0)
	if _sword_slot == SyndicateConstants.INVALID_SLOT:
		return null

	# The rejection half, in the same context so the comparison is honest: the
	# same edge, offered to every face of a Structural Component rather than to a
	# hand. GRIP mates only with GRIP, so every one of them must refuse it.
	var panel := PartRegistry.definition_by_key(PANEL_KEY)
	var panel_slot := _place_near(ctx, panel, CORE_ORIGIN, 0)
	if panel_slot != SyndicateConstants.INVALID_SLOT:
		var panel_origin: Vector3i = ctx.states[panel_slot].origin_cell
		_sword_on_structure_rejected = _first_accepting_cell(ctx, sword, panel_origin, 0) \
			== Vector3i(SEARCH_MISS, SEARCH_MISS, SEARCH_MISS)

	var runtime := AssemblyRuntime.new()
	_runtimes.append(runtime)
	EventBus.get_tree().root.add_child(runtime)
	runtime.adopt(ctx)
	runtime.apply_mass_properties(MassSolver.compute(runtime.states, runtime.graph))
	runtime.body.freeze = true
	runtime.body.global_transform = Transform3D(Basis(), ATTACKER_POSE)
	_registry.register(runtime)
	return runtime


## A point [constant TARGET_RANGE_M] out along the blade at mid-swing, in world
## space — where the target hull is planted.
##
## Records the hand on the way past, because §15.4's impulse direction can only
## be checked against the radius the edge is swinging on, and the hand is where
## that radius starts.
func _edge_world_origin(attacker: AssemblyRuntime) -> Vector3:
	var st: PartInstanceState = attacker.states[_sword_slot]
	var def := attacker.definition_at(_sword_slot)
	var mount := EffectorSystem.muzzle_world_transform(attacker, st, def, 0, 0.0, 0.0)
	var arm_def := attacker.definition_at(_arm_slot)
	mount = mount.translated_local(arm_def.appendage_profile.held_edge_origin_offset())
	_hand_world = mount.origin
	# Along the blade's own -Z at zero swing, which is where the arc's midpoint
	# points. Not through [method MeleeSolver.edge_transform], whose origin is
	# pinned to half the reach and is the very distance this must avoid.
	return mount.translated_local(Vector3(0.0, 0.0, -TARGET_RANGE_M)).origin


func _build_target(at: Vector3) -> AssemblyRuntime:
	var ctx := BuildContext.with_physics(TARGET)
	_contexts.append(ctx)
	PlacementValidator.commit(
		ctx, PlacementCandidate.create(PartRegistry.definition_by_key(CORE_KEY), CORE_ORIGIN, 0)
	)
	var runtime := AssemblyRuntime.new()
	_runtimes.append(runtime)
	EventBus.get_tree().root.add_child(runtime)
	runtime.adopt(ctx)
	runtime.apply_mass_properties(MassSolver.compute(runtime.states, runtime.graph))
	# Left [b]unfrozen[/b], unlike the attacker, and that is the whole of what
	# makes §15.4's impulse on the target observable: a frozen body takes a
	# 2800 N·s strike and does not move (§3.41), so the call is made and nothing
	# anywhere can tell whether it was. Gravity and damping are off instead, so
	# the only thing that can move this Assembly is the edge — which makes the
	# velocity it ends up with a clean reading of one impulse.
	runtime.body.freeze = false
	runtime.body.gravity_scale = 0.0
	runtime.body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	runtime.body.linear_damp = 0.0
	# Positioned by its hull rather than by its lattice origin, and by asking the
	# runtime where the hull is rather than by reconstructing it. A Core Module's
	# collider sits at its origin cell plus its own centre-of-mass offset — 1.375 m
	# above the body origin on this build — and an 0.18 m edge aimed at the lattice
	# origin passes a metre under the box. Deriving that sum by hand here is how
	# this fixture came to measure a miss and report it as a §15 defect.
	runtime.body.global_transform = Transform3D(Basis(), Vector3.ZERO)
	runtime.body.global_position = at - runtime.part_world_position(0)
	_target_pose = runtime.body.global_position
	_registry.register(runtime)
	return runtime


## Sentinel component for "no cell in the search box was accepted".
const SEARCH_MISS: int = -9999

## Search half-extent, in cells, around the anchor. Large enough to clear the
## Core Module and a six-cell arm, small enough to stay cheap.
const SEARCH_RADIUS: int = 12


## Commits [param def] at the first cell near [param anchor] the validator
## accepts, and returns its slot.
##
## A search rather than an authored coordinate, for the reason §9 gives about
## orientation indices: where exactly a six-cell arm's shoulder lands against a
## Core Module's face is a property of two occupancy grids, and a literal would
## be re-derived by hand every time either changed.
func _place_near(ctx: BuildContext, def: PartDefinition, anchor: Vector3i, orientation: int) -> int:
	var cell := _first_accepting_cell(ctx, def, anchor, orientation)
	if cell == Vector3i(SEARCH_MISS, SEARCH_MISS, SEARCH_MISS):
		return SyndicateConstants.INVALID_SLOT
	return PlacementValidator.commit(ctx, PlacementCandidate.create(def, cell, orientation))


func _first_accepting_cell(
	ctx: BuildContext, def: PartDefinition, anchor: Vector3i, orientation: int
) -> Vector3i:
	for dy: int in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for dz: int in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			for dx: int in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
				var cell := anchor + Vector3i(dx, dy, dz)
				var cand := PlacementCandidate.create(def, cell, orientation)
				if PlacementValidator.validate(ctx, cand) == PlacementValidator.Reject.NONE:
					return cell
	return Vector3i(SEARCH_MISS, SEARCH_MISS, SEARCH_MISS)


## The orientation index carrying [param from] onto [param onto].
##
## Searched with a stated predicate rather than written down: which of the 24
## does this is a property of [OrientationTable], and the integer would not
## survive a change to the table (§9's fixture conventions).
func _orientation_carrying(from: Vector3, onto: Vector3) -> int:
	for i: int in SyndicateConstants.ORIENTATION_COUNT:
		if (OrientationTable.basis_for(i) * from).is_equal_approx(onto):
			return i
	return 0


func _sword_definition() -> PartDefinition:
	return PartRegistry.definition_by_key(SWORD_KEY)


func _on_part_damaged(assembly_id: int, slot: int, amount: float, channel: int) -> void:
	if assembly_id != TARGET:
		return
	if not _recording_swing:
		if channel == PartEnums.DamageChannel.THERMAL:
			_sustained_thermal += amount
		return
	_victims.append(assembly_id)
	_damage_by_channel[channel] += amount
	# One strike submits one packet per non-zero channel share (§15.4), so the
	# strike count is per (swing, slot) pair rather than per packet.
	var key := _swings_started * SyndicateConstants.MAX_PARTS_PER_ASSEMBLY + slot
	if _struck_keys.has(key):
		return
	_struck_keys.append(key)
	_strikes_on_target += 1
	if not _landed_swings.has(_swings_started):
		_landed_swings.append(_swings_started)
		_swings_landed += 1
