extends TestCase
## Doc 08 §7.1's fire and §7.3's scheduler, against a live part.
##
## Thermal damage has been resolvable since session 17 and has never [i]burned[/i]:
## a part crossing [constant DamageResolver.THERMAL_IGNITION_HU] gained
## [constant PartFlags.FLAG_OVERHEATED] and nothing read it, so the difference
## between an energy weapon and a kinetic one was a number in a resistance row.
## §7.3's list is what turns the flag into damage, and this file is the whole of
## that chain: ignition through real packets, an instalment worth the documented
## amount, the 10 Hz cadence, the cooling that makes §7.1's hysteresis band
## reachable, and the part going out the far side.
##
## [b]The burning part is a Core Module and that is arithmetic rather than
## taste.[/b] Thermal damage and heat come off the same [member
## DamagePacket.raw_amount], so a part must survive
## [code]480 / 0.55 · (1 − resist) · (1 − absorption)[/code] points of thermal
## damage before it can reach the ignition threshold at all — 542 on this
## chassis. Five shipped parts clear that bar and twelve do not: a Structural
## Component is destroyed by the fire it would have caught, which is a finding
## about the part table rather than about this system and is recorded as one.

const CORE_KEY := &"core.command.compact.t2"
const PANEL_KEY := &"str.panel.medium.t2"

const CORE_ORIGIN := Vector3i(24, 4, 24)
const PANEL_ORIGIN := Vector3i(24, 8, 24)

const ASSEMBLY := 41
const CORE_SLOT := 0
const PANEL_SLOT := 1

## ===== THE PUBLISHED FIGURES, QUOTED ===================================
## Written out by hand rather than imported: a test that reads the same constant
## its subject reads moves its own expectation when the constant moves.

## Doc 08 §7.1.
const DOC_IGNITION_HU: float = 480.0
const DOC_EXTINCTION_HU: float = 320.0
const DOC_HEAT_RATIO: float = 0.55
const DOC_SELF_DAMAGE_PER_S: float = 4.0
const DOC_COOLING_HU_S: float = 18.0
## Doc 08 §7.3.
const DOC_TICK_INTERVAL_S: float = 0.1
## Doc 08 §4.5's absorption half-point, and doc 01 §10.1's figures for the
## chassis this fires on.
const DOC_ARMOUR_HALF: float = 40.0
const DOC_CORE_ARMOUR: float = 18.0
const DOC_CORE_THERMAL_RESISTANCE: float = 0.10
const DOC_CORE_INTEGRITY: float = 4200.0

## ===== THE DERIVED FIGURES =============================================

## absorption = 18 / (18 + 40) = 0.3103448, so a thermal point delivers
## (1 − 0.10) · (1 − 0.3103448) = 0.6206897 of itself to this chassis.
const CORE_THERMAL_FRACTION: float = 0.6206897

## One instalment: 4.0 damage/s over 0.1 s, through the fraction above.
const EXPECTED_INSTALMENT_DAMAGE: float = 0.2482759

## The ignition packet, and how many of them it takes.
##
## 200 raw is 110 HU of heat and 124.14 of damage, so the fifth packet crosses
## 480 with 550 HU on the part and 621 of its 4200 integrity gone — comfortably
## inside NOMINAL, which keeps §8.2's armour row out of every number below.
const IGNITION_RAW: float = 200.0
const IGNITION_PACKETS: int = 5
const HEAT_AT_IGNITION: float = 550.0

## Heat an instalment nets off: 18.0 · 0.1 shed against the 0.4 · 0.55 the
## instalment's own packet deposits. §7.1's fire is a thermal source like any
## other and is resolved through the same door, which is what makes it 1.58
## rather than 1.80.
const NET_HEAT_PER_INSTALMENT: float = 1.58

## ceil((550.0 − 320.0) / 1.58) = ceil(145.57) = 146. The 145th instalment leaves
## 320.90 HU and the 146th leaves 319.32, which is the one that puts the fire out.
const INSTALMENTS_TO_EXTINCTION: int = 146

## Enough instalments to be sure, so that a fire which never goes out is a
## failure rather than a hang.
const BURN_INSTALMENT_BUDGET: int = 400

## §3.16's float32 round-trip on `resistance` is worth about 1e-7 relative, and
## the expectations above are written to seven figures.
const DAMAGE_TOLERANCE: float = 1e-4
const HEAT_TOLERANCE: float = 1e-3

var _registry: AssemblyRegistry = null
var _ctx: BuildContext = null
var _runtime: AssemblyRuntime = null
var _resolver: DamageResolver = null
var _dot: DotScheduler = null

var _measured: bool = false
## Was the part alight after four ignition packets, and after the fifth.
var _burning_before_threshold: bool = true
var _burning_at_threshold: bool = false
var _entries_after_reignition: int = -1
var _heat_at_ignition: float = -1.0
## Integrity and heat straddling one below-cadence step and one instalment.
var _integrity_before_step: float = -1.0
var _integrity_after_half_interval: float = -1.0
var _integrity_after_instalment: float = -1.0
var _heat_after_instalment: float = -1.0
## The burn to extinction.
var _instalments_burned: int = 0
var _integrity_at_extinction: float = -1.0
var _flag_after_extinction: bool = true
var _entries_after_extinction: int = -1
## The destroyed-part path.
var _entries_after_destruction: int = -1


func before_all() -> void:
	_registry = AssemblyRegistry.new()
	_ctx = BuildContext.with_physics(ASSEMBLY)
	PlacementValidator.commit(
		_ctx, PlacementCandidate.create(PartRegistry.definition_by_key(CORE_KEY), CORE_ORIGIN, 0)
	)
	PlacementValidator.commit(
		_ctx, PlacementCandidate.create(PartRegistry.definition_by_key(PANEL_KEY), PANEL_ORIGIN, 0)
	)

	_runtime = AssemblyRuntime.new()
	EventBus.get_tree().root.add_child(_runtime)
	_runtime.adopt(_ctx)
	_registry.register(_runtime)

	_resolver = DamageResolver.new()
	_resolver.registry = _registry
	EventBus.get_tree().root.add_child(_resolver)

	# Deliberately [b]not[/b] in the tree. §7.3 drives itself from
	# [method Node._physics_process] in a match; here every instalment is a
	# [method DotScheduler.step] this file made, so a cadence assertion is
	# measuring the scheduler and not the engine's frame pacing.
	_dot = DotScheduler.new()
	_dot.resolver = _resolver
	_resolver.dot = _dot

	_measure()


func after_all() -> void:
	if _dot != null:
		_dot.free()
	if _resolver != null:
		_resolver.free()
	if _runtime != null:
		_runtime.free()
	if _ctx != null:
		_ctx.dispose()


## ===== IGNITION (§7.1) =================================================


## The threshold is a threshold in both directions, which is the assertion a
## fixture that only ever crossed it could not make.
func test_a_part_under_the_ignition_threshold_is_not_burning() -> void:
	check_false(
		_burning_before_threshold,
		"440 HU of heat leaves the part hot and not alight"
	)


func test_crossing_the_ignition_threshold_lights_the_part() -> void:
	check_true(_burning_at_threshold, "550 HU puts it in §7.3's list")
	check_approx(
		_heat_at_ignition, HEAT_AT_IGNITION,
		"and it carries the heat the five packets deposited", HEAT_TOLERANCE
	)


## A part already alight does not gain a second entry, which is what stops a
## build held in a beam burning at some multiple of §7.1's authored rate.
func test_further_heat_does_not_light_an_already_burning_part_twice() -> void:
	check_eq(_entries_after_reignition, 1, "one entry per burning part, however many packets")


## ===== THE INSTALMENT (§7.3) ===========================================


## §7.3's cadence, asserted as the thing it is for: work below the interval is
## accumulated rather than done, so a 60 Hz caller pays for ten instalments a
## second and not sixty.
func test_a_step_under_the_cadence_delivers_nothing() -> void:
	check_approx(
		_integrity_after_half_interval, _integrity_before_step,
		"half an interval removed nothing", DAMAGE_TOLERANCE
	)


func test_one_instalment_removes_the_documented_amount() -> void:
	check_approx(
		_integrity_before_step - _integrity_after_instalment, EXPECTED_INSTALMENT_DAMAGE,
		"4.0 damage/s over 0.1 s through this chassis's thermal resistance and armour",
		DAMAGE_TOLERANCE
	)


## The cooling that makes the hysteresis band reachable, and the reason it is
## 1.58 and not 1.80: the fire's own packet is a thermal source and deposits heat
## on the way through.
func test_an_instalment_nets_heat_off_the_burning_part() -> void:
	check_approx(
		_heat_at_ignition - _heat_after_instalment, NET_HEAT_PER_INSTALMENT,
		"18.0 HU/s shed against the 2.2 HU/s the instalment itself deposits",
		HEAT_TOLERANCE
	)


## ===== EXTINCTION (§7.1) ===============================================


func test_the_fire_goes_out_at_the_extinction_threshold() -> void:
	check_eq(
		_instalments_burned, INSTALMENTS_TO_EXTINCTION,
		"the burn ran the 146 instalments the two thresholds and the net rate ask for"
	)
	check_false(_flag_after_extinction, "and the part no longer carries the flag")
	check_eq(_entries_after_extinction, 0, "and has left §7.3's list")


## The whole burn, as a number a balance change would move: fourteen and a half
## seconds of fire is 36 integrity, which is 0.9% of this chassis. A fire is a
## cost of being hit by an energy weapon and is not a second weapon.
func test_the_whole_burn_is_worth_what_the_rate_and_the_duration_say() -> void:
	check_approx(
		_integrity_before_step - _integrity_at_extinction,
		EXPECTED_INSTALMENT_DAMAGE * float(INSTALMENTS_TO_EXTINCTION),
		"146 instalments at the documented rate", 1e-2
	)


## A part destroyed while alight leaves the list, rather than leaving the
## scheduler resolving packets against a slot the resolver rejects every tick.
func test_a_destroyed_part_stops_burning() -> void:
	check_eq(_entries_after_destruction, 0, "the entry went with the part")


## ===== FIXTURE =========================================================


## One run, in order, recording as it goes. §3's convention: a destructive
## fixture is built once and every method asserts one thing about the record.
func _measure() -> void:
	if _measured:
		return
	_measured = true
	var st: PartInstanceState = _runtime.states[CORE_SLOT]

	for i: int in IGNITION_PACKETS - 1:
		_resolver.apply(_thermal_packet(CORE_SLOT, IGNITION_RAW))
	_burning_before_threshold = _dot.is_burning(ASSEMBLY, CORE_SLOT)

	_resolver.apply(_thermal_packet(CORE_SLOT, IGNITION_RAW))
	_burning_at_threshold = _dot.is_burning(ASSEMBLY, CORE_SLOT)
	_heat_at_ignition = st.accumulated_heat_hu

	# A sixth thermal packet against a part that is already over the threshold.
	# The resolver offers every such packet to §7.3's list, so this reaches
	# [method DotScheduler.ignite] and the entry it does not create is that
	# function's own de-duplication. It carries no raw amount, so it leaves every
	# number below where the five packets left it.
	_resolver.apply(_thermal_packet(CORE_SLOT, 0.0))
	_entries_after_reignition = _dot.entry_count()

	_integrity_before_step = st.integrity
	# Two halves of the cadence rather than an arbitrary pair: halving a float is
	# exact, so the two add back to the interval bit for bit and §3.17's "an
	# accumulated float never lands on a round threshold" does not apply.
	_dot.step(DOC_TICK_INTERVAL_S * 0.5)
	_integrity_after_half_interval = st.integrity
	_dot.step(DOC_TICK_INTERVAL_S * 0.5)
	_integrity_after_instalment = st.integrity
	_heat_after_instalment = st.accumulated_heat_hu
	_instalments_burned = 1

	while _dot.is_burning(ASSEMBLY, CORE_SLOT) and _instalments_burned < BURN_INSTALMENT_BUDGET:
		_dot.step(DOC_TICK_INTERVAL_S)
		_instalments_burned += 1
	_integrity_at_extinction = st.integrity
	_flag_after_extinction = st.has_flag(PartFlags.FLAG_OVERHEATED)
	_entries_after_extinction = _dot.entry_count()

	# Last, because it ends a part: the panel is lit by hand — it cannot reach
	# the ignition threshold through packets and survive, which is the finding in
	# the class comment — and then destroyed under the fire.
	var panel: PartInstanceState = _runtime.states[PANEL_SLOT]
	panel.accumulated_heat_hu = DOC_IGNITION_HU
	_resolver.apply(_thermal_packet(PANEL_SLOT, 1.0))
	_resolver.apply(_overkill_packet(PANEL_SLOT))
	_dot.step(DOC_TICK_INTERVAL_S)
	_entries_after_destruction = _dot.entry_count()


func _thermal_packet(slot: int, raw: float) -> DamagePacket:
	var packet := DamagePacket.new()
	packet.target_assembly_id = ASSEMBLY
	packet.target_slot = slot
	packet.channel = PartEnums.DamageChannel.THERMAL
	packet.raw_amount = raw
	packet.source_assembly_id = ASSEMBLY + 1
	return packet


## Far past the panel's 380, through the kinetic path so that it deposits no
## further heat on the way.
func _overkill_packet(slot: int) -> DamagePacket:
	var packet := DamagePacket.new()
	packet.target_assembly_id = ASSEMBLY
	packet.target_slot = slot
	packet.channel = PartEnums.DamageChannel.KINETIC
	packet.raw_amount = 10000.0
	packet.penetration = 400.0
	packet.impact_normal_world = Vector3.UP
	packet.incoming_direction = Vector3.DOWN
	return packet
