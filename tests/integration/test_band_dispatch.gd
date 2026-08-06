extends TestCase
## Doc 08 §8.4's dispatch: a band transition written by [DamageResolver] reaches
## the flat multiplier arrays that [MotiveSystem] and [EffectorSystem] read every
## tick.
##
## This is the join between document 08 and everything that degrades, and it was
## missing until session 14. Both systems already had an
## [code]on_band_changed[/code] that wrote the right numbers, and both were called
## exactly once — at registration, with NOMINAL — and never again. A Motive
## Assembly could be shot to within a hair of destruction and keep full traction;
## an Effector Module could be shot to CRITICAL and never jam. Everything looked
## correct in isolation and the chain did nothing.
##
## The test drives the real signal rather than calling the handlers, because
## calling them would assert that the handlers work, which was never in doubt.
## What is in doubt is whether anything raises the signal, whether anything
## subscribes, and whether the id filter lets one Assembly's damage into another
## Assembly's arrays.

const CORE_KEY := &"core.command.compact.t2"
const WHEEL_KEY := &"mot.wheeled.light_road.t1"
const HUB_KEY := &"str.hub.axle_station.t2"
const GUN_KEY := &"eff.ballistic.autocannon_30.t3"
const POWER_KEY := &"pmv.combustion.flat.t2"

const CORE_ORIGIN := Vector3i(24, 4, 24)
const POWER_ORIGIN := Vector3i(24, 4, 34)
const GUN_ORIGIN := Vector3i(24, 8, 24)
const HUB_ORIGIN := Vector3i(21, 2, 19)
const WHEEL_ORIGIN := Vector3i(18, 3, 19)

## §8.2's IMPAIRED row for a Motive Assembly, quoted rather than imported. The
## mandated behaviour: below 50% integrity a drive unit loses 40% of its grip.
const DOC_MOTIVE_TRACTION_IMPAIRED: float = 0.60
## §8.2's CRITICAL row for an Effector Module: an 18% jam chance per shot.
const DOC_EFF_JAM_CRITICAL: float = 0.18

var _ctx: BuildContext = null
var _runtime: AssemblyRuntime = null
var _motion: MotiveSystem = null
var _guns: EffectorSystem = null
var _registry: AssemblyRegistry = null
var _resolver: DamageResolver = null
var _motive_slot: int = SyndicateConstants.INVALID_SLOT
var _gun_slot: int = SyndicateConstants.INVALID_SLOT
## Captured at registration. The runner sorts test methods, so by the time an
## alphabetically later name runs, two of them have already shot this fixture to
## pieces — a property of the fixture is recorded when the fixture is built.
var _initial_traction: float = 0.0
var _initial_jam: float = -1.0


func before_all() -> void:
	_registry = AssemblyRegistry.new()
	_ctx = BuildContext.with_physics(1)
	PlacementValidator.commit(
		_ctx, PlacementCandidate.create(PartRegistry.definition_by_key(CORE_KEY), CORE_ORIGIN, 0)
	)
	PlacementValidator.commit(
		_ctx, PlacementCandidate.create(PartRegistry.definition_by_key(POWER_KEY), POWER_ORIGIN, 0)
	)
	PlacementValidator.commit(
		_ctx, PlacementCandidate.create(PartRegistry.definition_by_key(GUN_KEY), GUN_ORIGIN, 0)
	)
	PlacementValidator.commit(
		_ctx, PlacementCandidate.create(PartRegistry.definition_by_key(HUB_KEY), HUB_ORIGIN, 0)
	)
	PlacementValidator.commit(
		_ctx,
		PlacementCandidate.create(
			PartRegistry.definition_by_key(WHEEL_KEY), WHEEL_ORIGIN, _wheel_orientation()
		)
	)

	_runtime = AssemblyRuntime.new()
	EventBus.get_tree().root.add_child(_runtime)
	_runtime.adopt(_ctx)
	_runtime.apply_mass_properties(MassSolver.compute(_runtime.states, _runtime.graph))
	_registry.register(_runtime)

	_resolver = DamageResolver.new()
	_resolver.registry = _registry
	EventBus.get_tree().root.add_child(_resolver)

	_motion = MotiveSystem.new()
	_motion.runtime = _runtime
	_motion.input = ControlInput.new()
	_motion.power = PowerSystem.new()
	_runtime.add_child(_motion)

	_guns = EffectorSystem.new()
	_guns.runtime = _runtime
	_guns.seed_rng(1)
	_runtime.add_child(_guns)

	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var def := _runtime.definition_at(slot)
		if def == null:
			continue
		if def.part_class == PartEnums.PartClass.MOTIVE_ASSEMBLY:
			_motion.register(slot, def, _runtime.states[slot])
			_motive_slot = slot
		elif def.part_class == PartEnums.PartClass.EFFECTOR_MODULE:
			_guns.register(slot, def)
			_gun_slot = slot

	_initial_traction = _motion.traction_multiplier(_motive_slot)
	_initial_jam = _guns.jam_chance(_gun_slot)


func after_all() -> void:
	if _runtime != null:
		_runtime.free()
	if _resolver != null:
		_resolver.free()
	if _ctx != null:
		_ctx.dispose()


func test_the_fixture_has_the_two_parts_this_file_is_about() -> void:
	check_true(_motive_slot != SyndicateConstants.INVALID_SLOT, "a Motive Assembly is registered")
	check_true(_gun_slot != SyndicateConstants.INVALID_SLOT, "and an Effector Module is too")
	check_approx(_initial_traction, 1.0, "a fresh drive unit has full traction")
	check_approx(_initial_jam, 0.0, "and a fresh module never jams")


func test_damage_that_crosses_a_band_reaches_the_motive_cache() -> void:
	# The mandated behaviour of Invariant I-5, end to end: shoot a drive unit
	# below half integrity and its traction multiplier becomes 0.60. Nothing in
	# the tick loop reads integrity to get there — the resolver writes a band, the
	# signal carries it, and the multiplier is an array index from then on.
	var state: PartInstanceState = _runtime.states[_motive_slot]
	var def := _runtime.definition_at(_motive_slot)
	state.integrity = def.integrity_max
	state.integrity_band = PartEnums.IntegrityBand.NOMINAL
	_motion.on_band_changed(_motive_slot, PartEnums.IntegrityBand.NOMINAL)

	_apply_until_band(_motive_slot, PartEnums.IntegrityBand.IMPAIRED)

	check_eq(
		state.integrity_band, PartEnums.IntegrityBand.IMPAIRED, "the part is below 50% integrity"
	)
	check_approx(
		_motion.traction_multiplier(_motive_slot),
		DOC_MOTIVE_TRACTION_IMPAIRED,
		"and the traction multiplier the physics loop reads is §8.2's 0.60"
	)
	check_true(
		_motion.rolling_multiplier(_motive_slot) > 1.0,
		"with the rolling resistance raised, not merely the grip lowered"
	)


func test_damage_that_crosses_a_band_reaches_the_effector_cache() -> void:
	# The other mandated behaviour: an Effector Module below 30% integrity gains
	# an 18% jam chance per shot. The multiplier is what §7.2's roll reads, so a
	# handler that never fired is a weapon that never jams however broken it is.
	var state: PartInstanceState = _runtime.states[_gun_slot]
	var def := _runtime.definition_at(_gun_slot)
	state.integrity = def.integrity_max
	state.integrity_band = PartEnums.IntegrityBand.NOMINAL
	_guns.on_band_changed(_gun_slot, PartEnums.IntegrityBand.NOMINAL)

	_apply_until_band(_gun_slot, PartEnums.IntegrityBand.CRITICAL)

	check_eq(
		state.integrity_band, PartEnums.IntegrityBand.CRITICAL, "the module is below 30% integrity"
	)
	check_approx(
		_guns.jam_chance(_gun_slot),
		DOC_EFF_JAM_CRITICAL,
		"and the jam chance §7.2 rolls against is §8.2's 0.18"
	)
	check_true(
		_guns.cycle_multiplier(_gun_slot) > 1.0, "with the cycle time lengthened as well"
	)


func test_another_assemblys_damage_does_not_touch_these_arrays() -> void:
	# The id filter. Both systems subscribe to one global signal, so without it
	# every Assembly in the match would cache every other Assembly's band
	# transitions — at the same slot numbers, which every Assembly has.
	var before := _motion.traction_multiplier(_motive_slot)
	EventBus.part_band_changed.emit(
		_runtime.assembly_id + 1000,
		_motive_slot,
		PartEnums.IntegrityBand.NOMINAL,
		PartEnums.IntegrityBand.CRITICAL
	)
	check_approx(
		_motion.traction_multiplier(_motive_slot),
		before,
		"a band change on a different Assembly changes nothing here"
	)


func test_a_slot_this_system_does_not_own_is_ignored() -> void:
	# The Core Module is on this Assembly and is not a Motive Assembly. A handler
	# that wrote every slot it was told about would put a Core Module's band into
	# the traction array, where the physics loop would read it as a drive unit's.
	var before := _motion.traction_multiplier(_motive_slot)
	EventBus.part_band_changed.emit(
		_runtime.assembly_id,
		SyndicateConstants.CORE_SLOT,
		PartEnums.IntegrityBand.NOMINAL,
		PartEnums.IntegrityBand.CRITICAL
	)
	check_approx(
		_motion.traction_multiplier(_motive_slot),
		before,
		"a Core Module's band does not land in the Motive Assembly's slot"
	)
	check_approx(
		_motion.traction_multiplier(SyndicateConstants.CORE_SLOT),
		1.0,
		"nor in the Core Module's own entry, which no motive loop reads"
	)


## The same rule on the other subscriber, which had no test of its own.
##
## Session 17's sweep dropped [EffectorSystem]'s [code]_hardpoints.has(slot)[/code]
## guard and the suite stayed green, while the identical fault on [MotiveSystem]
## was caught by the method above. One filter had a test and its mirror did not,
## which is the ordinary way a second subscriber to a shared signal goes
## uncovered: the file was written when there was only one.
func test_a_slot_the_effector_system_does_not_own_is_ignored() -> void:
	var before := _guns.jam_chance(_gun_slot)
	EventBus.part_band_changed.emit(
		_runtime.assembly_id,
		SyndicateConstants.CORE_SLOT,
		PartEnums.IntegrityBand.NOMINAL,
		PartEnums.IntegrityBand.CRITICAL
	)
	check_approx(
		_guns.jam_chance(_gun_slot),
		before,
		"a Core Module's band does not land in the Effector Module's slot"
	)
	# CRITICAL is the band that carries §8.2's 0.18 jam chance, so an unfiltered
	# handler writes a number this assertion can see rather than a harmless 1.0.
	check_approx(
		_guns.jam_chance(SyndicateConstants.CORE_SLOT),
		0.0,
		"nor in the Core Module's own entry, which would jam a Core Module"
	)


## ===== FIXTURES ========================================================


## Damages [param slot] through real packets until it reaches [param target].
##
## Real packets rather than a direct integrity write, because the whole subject
## of this file is what happens on the way: the resolver has to compute the band,
## notice the transition, and announce it. Assigning integrity would skip all
## three and assert nothing.
func _apply_until_band(slot: int, target: PartEnums.IntegrityBand) -> void:
	var state: PartInstanceState = _runtime.states[slot]
	for i: int in 200:
		if state.integrity_band == target:
			return
		var packet := DamagePacket.new()
		packet.target_assembly_id = _runtime.assembly_id
		packet.target_slot = slot
		packet.channel = PartEnums.DamageChannel.KINETIC
		packet.raw_amount = 40.0
		# Comfortably past any shipped armour rating, so the §4.3 curve is not
		# what this test is measuring.
		packet.penetration = 400.0
		packet.impact_normal_world = Vector3.UP
		packet.incoming_direction = Vector3.DOWN
		_resolver.apply(packet)


func _wheel_orientation() -> int:
	for i: int in SyndicateConstants.ORIENTATION_COUNT:
		var basis := OrientationTable.basis_for(i)
		if not (basis * Vector3.FORWARD).is_equal_approx(Vector3(1.0, 0.0, 0.0)):
			continue
		if (basis * Vector3.UP).is_equal_approx(Vector3.UP):
			return i
	return 0
