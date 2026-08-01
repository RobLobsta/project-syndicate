extends TestCase
## [MotiveSystem]'s registration and dispatch, driven through the shipped part
## definitions.
##
## The force application itself is not exercised here. A query against the main
## world's physics space answers nothing in this suite (see HANDOFF §3), so
## [method MotiveSystem.step] cannot be given a grounded contact to solve. What
## is testable — and what this covers — is the bookkeeping that decides which
## solver a part reaches, what per-family state it gets, and what happens to the
## gait when a limb is lost. Every formula those solvers apply is asserted
## exactly in the unit tests.

const WHEEL: StringName = &"mot.wheeled.allroad.t2"
const TRACK: StringName = &"mot.tracked.short_bogie.t2"
const ROTOR: StringName = &"mot.rotor.coaxial_mid.t3"
const LIMB: StringName = &"mot.limb.strider.t4"
const PANEL: StringName = &"str.panel.medium.t2"

var _systems: Array[MotiveSystem] = []


## A [TestCase] is a [RefCounted] and has no [method Node.get_tree], so a Node
## under test goes into the tree through an autoload. Freed in [method after_all]:
## a leaked node stays connected to the bus and resolves the next file's fixture
## underneath it.
func _system() -> MotiveSystem:
	var sys := MotiveSystem.new()
	EventBus.get_tree().root.add_child(sys)
	_systems.append(sys)
	return sys


func after_all() -> void:
	for sys: MotiveSystem in _systems:
		sys.queue_free()
	_systems.clear()


func _def(key: StringName) -> PartDefinition:
	return PartRegistry.definition_by_key(key)


## A placement for slot [param slot], at one of four lattice corners around the
## origin so a limb set has real geometry to phase from.
##
## Slots 1..4 map to left-front, left-rear, right-front, right-rear. Fore is -Z.
static func _placed(slot: int) -> PartInstanceState:
	var st := PartInstanceState.new()
	st.slot = slot
	var lateral := -4 if slot <= 2 else 4
	var longitudinal := -4 if slot % 2 == 1 else 4
	st.origin_cell = SyndicateConstants.LATTICE_ORIGIN_CELL + Vector3i(lateral, 0, longitudinal)
	st.orientation_index = 0
	return st


## ===== REGISTRATION ====================================================


func test_registration_routes_each_part_to_its_family() -> void:
	var sys := _system()
	sys.register(1, _def(WHEEL))
	sys.register(2, _def(TRACK))
	sys.register(3, _def(ROTOR))
	sys.register(4, _def(LIMB))
	check_eq(sys.family_of(1), PartEnums.LocomotionMode.GROUND, "the wheel is a ground contact")
	check_eq(sys.family_of(2), PartEnums.LocomotionMode.TRACKED, "the track is its own family")
	check_eq(sys.family_of(3), PartEnums.LocomotionMode.ROTARY, "the disc is rotary")
	check_eq(sys.family_of(4), PartEnums.LocomotionMode.AMBULATORY, "and the limb ambulatory")


## The class test is the sole guard on registration, and this is what defends it.
##
## [MotiveSystem.register] used to carry a second check for a Motive Assembly
## with a null profile. Fault injection showed the two were indistinguishable —
## both returned without registering, and no test could tell which had fired —
## so the second is now an `assert` naming registry validator rule 6, which
## rejects such a definition at build time. There is deliberately no test for the
## assert: it fires only on data that has bypassed the validator, and a test that
## reached it would halt the runner rather than fail a check.
func test_a_non_motive_part_is_not_registered() -> void:
	var sys := _system()
	sys.register(1, _def(PANEL))
	check_eq(sys.motive_slot_count(), 0, "a Structural Component moves nothing")
	sys.register(2, null)
	check_eq(sys.motive_slot_count(), 0, "and a null definition registers nothing either")


func test_registered_slots_are_kept_in_ascending_order() -> void:
	var sys := _system()
	sys.register(7, _def(WHEEL))
	sys.register(2, _def(WHEEL))
	sys.register(5, _def(WHEEL))
	check_eq(
		sys.motive_slots(),
		PackedInt32Array([2, 5, 7]),
		"iteration order is slot order, so the per-tick force sum is reproducible"
	)


## A part registered twice would be solved twice and contribute double force,
## which reads as an Assembly that is inexplicably faster than its build.
func test_registering_a_slot_twice_does_not_duplicate_it() -> void:
	var sys := _system()
	sys.register(3, _def(WHEEL))
	sys.register(3, _def(WHEEL))
	check_eq(sys.motive_slot_count(), 1, "the slot appears once")


func test_re_registration_moves_a_slot_between_families() -> void:
	var sys := _system()
	sys.register(3, _def(WHEEL))
	sys.register(3, _def(ROTOR))
	check_eq(sys.family_of(3), PartEnums.LocomotionMode.ROTARY, "the family follows the new part")
	check_eq(sys.motive_slot_count(), 1, "and the slot is still only there once")


## ===== PER-FAMILY STATE ================================================


## A tracked Motive Assembly carries one contact per road station, and that is
## the whole cost difference between it and a wheel.
func test_a_track_gets_one_contact_per_road_station() -> void:
	var sys := _system()
	sys.register(1, _def(WHEEL))
	sys.register(2, _def(TRACK))
	check_eq(sys.contact_count(1), 1, "a wheel has a single contact under its hub")
	check_eq(
		sys.contact_count(2),
		_def(TRACK).motive_profile.track_profile.road_stations,
		"and a track has one per station"
	)


## A disc touches nothing, which is why the rotary family is the cheapest per
## tick — it costs the shape cast it does not perform.
func test_a_disc_gets_no_contact_at_all() -> void:
	var sys := _system()
	sys.register(1, _def(ROTOR))
	check_eq(sys.contact_count(1), 0, "no probe, no contact")
	check_not_null(sys.disc_state(1), "but it does get a disc state")
	check_null(sys.limb_state(1), "and not a limb state")


func test_a_limb_gets_a_limb_state_and_one_foot_contact() -> void:
	var sys := _system()
	sys.register(1, _def(LIMB))
	check_not_null(sys.limb_state(1), "the gait needs somewhere to keep its phase")
	check_eq(sys.contact_count(1), 1, "and the foot needs somewhere to land")
	check_null(sys.disc_state(1), "but no disc state")


func test_contact_station_indices_run_fore_to_aft() -> void:
	var sys := _system()
	sys.register(2, _def(TRACK))
	for i: int in sys.contact_count(2):
		check_eq(sys.contact_at(2, i).station_index, i, "station %d knows its own index" % i)
		check_eq(sys.contact_at(2, i).slot, 2, "and which part it belongs to")


## ===== BAND MULTIPLIERS ================================================


## Architectural Invariant I-5: the per-tick path reads a cached float array and
## never touches integrity. A part registers at NOMINAL and moves only when its
## band changes.
func test_a_part_registers_at_nominal() -> void:
	var sys := _system()
	sys.register(1, _def(WHEEL))
	check_approx(sys.traction_multiplier(1), 1.0, "an undamaged part is unmodified")


func test_a_band_change_writes_the_cached_multipliers() -> void:
	var sys := _system()
	sys.register(1, _def(WHEEL))
	sys.on_band_changed(1, PartEnums.IntegrityBand.IMPAIRED)
	check_approx(
		sys.traction_multiplier(1),
		DegradationTable.MOTIVE_TRACTION[PartEnums.IntegrityBand.IMPAIRED],
		"the mandated 40% traction loss, read from the shared table"
	)
	check_approx(
		sys.damp_multiplier(1),
		DegradationTable.MOTIVE_SUSP_DAMP[PartEnums.IntegrityBand.IMPAIRED],
		"and the damping row moves independently of it"
	)


## Damping degrades only at CRITICAL where traction degrades at IMPAIRED. A test
## reading one multiplier would pass against an implementation that wrote the
## same value into all four arrays.
func test_the_four_multipliers_are_not_the_same_number() -> void:
	var sys := _system()
	sys.register(1, _def(WHEEL))
	sys.on_band_changed(1, PartEnums.IntegrityBand.IMPAIRED)
	check_ne(
		sys.traction_multiplier(1),
		sys.damp_multiplier(1),
		"at IMPAIRED, traction has fallen to 0.60 and damping has not moved"
	)


## ===== GAIT PHASES =====================================================


## Registration caches the hip position, so a limb set can be phased without
## reaching back into the Assembly for a definition it was already handed.
func test_registration_caches_the_hip_position() -> void:
	var sys := _system()
	sys.register(1, _def(LIMB), _placed(1))
	check_ne(
		sys.limb_state(1).hip_local,
		Vector3.ZERO,
		"a placed limb resolves its hip from the lattice cell it sits on"
	)
	sys.register(2, _def(LIMB))
	check_eq(
		sys.limb_state(2).hip_local,
		Vector3.ZERO,
		"and one registered before placement keeps it at the origin rather than guessing"
	)


## Phases are a function of the surviving limb set, so losing one re-phases the
## rest. Leaving the others on their old offsets would leave a hole in the cycle
## that nothing steps into.
func test_losing_a_limb_rephases_the_survivors() -> void:
	var sys := _system()
	for slot: int in [1, 2, 3, 4]:
		sys.register(slot, _def(LIMB), _placed(slot))
	check_eq(sys.motive_slot_count(), 4, "four limbs registered")

	sys.unregister(4)
	check_eq(sys.motive_slot_count(), 3, "one lost")
	var seen: Array[float] = []
	for slot: int in [1, 2, 3]:
		seen.append(sys.limb_state(slot).phase_offset)
	seen.sort()
	for i: int in seen.size():
		check_approx(seen[i], float(i) / 3.0, "the survivors re-space over thirds, not quarters")


func test_unregistering_drops_every_trace_of_a_slot() -> void:
	var sys := _system()
	sys.register(1, _def(ROTOR))
	sys.unregister(1)
	check_eq(sys.motive_slot_count(), 0, "the slot is gone")
	check_null(sys.disc_state(1), "and so is its disc state")
	check_eq(sys.contact_count(1), 0, "and its contacts")


func test_unregistering_an_unknown_slot_is_harmless() -> void:
	var sys := _system()
	sys.register(1, _def(WHEEL))
	sys.unregister(99)
	check_eq(sys.motive_slot_count(), 1, "a destroyed part that was never motive changes nothing")
