extends TestCase
## The shape of the shipped build, measured rather than eyeballed.
##
## [b]This file exists because nothing else in the repository can see a
## proportion.[/b] Every validator in `tools/` checks one part against its own
## schema — mass positive, collider covering its occupancy, resistance under the
## ceiling — and not one of them compares a part against another part or against
## the Assembly it ends up in. So a part table can be internally consistent and
## still produce a silhouette that is a gun with a car attached, every check
## green (LEARNED_FACTS.md §1 fact 75).
##
## What it measures is the set of ratios a person notices in one frame of a
## capture and a test never notices at all: how long the vehicle is, what it
## masses for that size, where its centre of mass sits between the axles, how much
## of its length is weapon, and — the one that has been wrong since the project
## started — whether all of its contacts are on the ground.
##
## [b]Two of the assertions are asserted as they fail.[/b] `HANDOFF.md` §3.1.1
## records the finding: the reference build is nose-heavy enough to stand on its
## front axle, so the rear pair carries nothing. They are written the way they are
## measured today and are [i]supposed[/i] to break the day the build is re-laid or
## re-scaled — at which point the fix is to re-measure and re-assert, exactly as
## `test_family_duels` was re-measured when `release_part` closed the grind. The
## printed report below is the before-and-after instrument for that work.
##
## One Assembly on a slab, which reproduces exactly (LEARNED_FACTS.md §1 fact 44).

## Ticks the build is given to fall onto its contacts and settle.
const SETTLE_TICKS: int = 180

## Contacts the reference build actually puts weight on, of the four it carries.
##
## [b]The defect, and the number is exact rather than a bound.[/b] The centre of
## mass sits aft of the front axle by a quarter of a very short wheelbase, so the
## rear suspension cannot reach the ground and the hull rocks on the front pair.
## A build laid out to stand on all four would make this four and this file red.
const LOADED_CONTACTS: int = 2

## Share of the static weight the front axle carries. Measured at 73%; a road
## vehicle is 50–60% and anything past about two thirds cannot keep its rear
## suspension in contact.
const FRONT_BIAS_FLOOR: float = 0.65

## Newtons under which a contact counts as carrying nothing. Well below any real
## share of a 1282 kg build, and above the float noise on a settled spring.
const UNLOADED_N: float = 1.0

var _ran: bool = false
var _arena: CombatArena = null

var _mass_kg: float = 0.0
var _length_m: float = 0.0
var _width_m: float = 0.0
var _height_m: float = 0.0
var _wheelbase_m: float = 0.0
var _loaded: int = 0
var _front_n: float = 0.0
var _rear_n: float = 0.0


func after_all() -> void:
	_teardown()


## The finding. Half the running gear is along for the ride.
func test_the_build_stands_on_only_half_its_contacts() -> void:
	await _run()
	check_eq(
		_loaded,
		LOADED_CONTACTS,
		(
			"%d of %d contacts carry load. If this has risen, the build has been re-laid "
			+ "and this file is now the wrong way round — re-measure it, do not loosen it"
		) % [_loaded, _contact_count()]
	)


func test_the_static_weight_is_almost_all_on_the_front_axle() -> void:
	await _run()
	var total := _front_n + _rear_n
	var bias := 0.0 if total <= 0.0 else _front_n / total
	check_true(
		bias > FRONT_BIAS_FLOOR,
		(
			"the front axle carries %.0f%% of what the springs are holding. A build that "
			+ "had been balanced would put this near half and fail here"
		) % (bias * 100.0)
	)


## Not asserted as a defect — recorded so the rebuild has a datum. The wheelbase
## is a third of the hull length where a road vehicle is well over half, and it is
## the cheapest of the three levers §3.1.1 lists.
func test_the_wheelbase_is_short_for_the_hull() -> void:
	await _run()
	check_true(
		_wheelbase_m < _length_m * 0.5,
		(
			"wheelbase %.2f m under a %.2f m hull is %.0f%%; a road vehicle is 55-65%%"
			% [_wheelbase_m, _length_m, 100.0 * _wheelbase_m / maxf(_length_m, 0.01)]
		)
	)


## Runs once, and prints the whole report — which is the point of the file. Every
## figure here is one a rebuild has to move, and none of them is visible anywhere
## else in the suite.
func _run() -> void:
	if _ran:
		return
	_ran = true
	_arena = CombatArena.new()
	_arena.open()
	var c := _arena.spawn(CombatArena.Recipe.WHEELED_LIGHT, 0, Vector2.ZERO, 0.0, 0)
	await _arena.settle(SETTLE_TICKS)

	_mass_kg = c.runtime.body.mass
	_measure_extent(c)
	_measure_contacts(c)

	var volume := _length_m * _width_m * _height_m
	print(
		(
			"      build: %.0f kg, %.2f l x %.2f w x %.2f h m, %.0f kg/m3; wheelbase %.2f m "
			+ "(%.0f%% of hull); %d/%d contacts loaded, %.0f%% front"
		) % [
			_mass_kg, _length_m, _width_m, _height_m, _mass_kg / maxf(volume, 0.01),
			_wheelbase_m, 100.0 * _wheelbase_m / maxf(_length_m, 0.01),
			_loaded, _contact_count(),
			100.0 * _front_n / maxf(_front_n + _rear_n, 0.01)
		]
	)
	_teardown()


## Bounding box of the live parts, in metres, from the lattice rather than from
## any mesh — Architectural Invariant I-1 keeps those independent, and it is the
## occupancy that decides how big the machine is.
func _measure_extent(c: CombatArena.Combatant) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var st: PartInstanceState = c.runtime.states[slot]
		if st == null or not c.runtime.graph.is_alive(slot):
			continue
		var def := PartRegistry.definition(st.part_def_id)
		var basis := OrientationTable.basis_for(st.orientation_index)
		for cell: Vector3 in def.occupancy_cells:
			var p := LatticeMath.cell_to_local(st.origin_cell) + basis * (cell * SyndicateConstants.LATTICE_UNIT_M)
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	var unit := SyndicateConstants.LATTICE_UNIT_M
	_width_m = hi.x - lo.x + unit
	_height_m = hi.y - lo.y + unit
	_length_m = hi.z - lo.z + unit


## Which contacts are carrying anything, and how the load splits fore and aft.
##
## Read off the settled springs rather than computed from the part list, because
## what matters is not where the centre of mass is on paper but whether the
## suspension can reach the ground from there.
func _measure_contacts(c: CombatArena.Combatant) -> void:
	var lo := INF
	var hi := -INF
	var loads: Array[Vector2] = []
	for slot: int in c.motion.motive_slots():
		for i: int in c.motion.contact_count(slot):
			var contact := c.motion.contact_at(slot, i)
			if contact == null or contact.probe == null:
				continue
			var z: float = contact.probe.position.z
			lo = minf(lo, z)
			hi = maxf(hi, z)
			loads.append(Vector2(z, contact.normal_force_n))
			if contact.normal_force_n > UNLOADED_N:
				_loaded += 1
	_wheelbase_m = 0.0 if lo > hi else hi - lo
	var mid := (lo + hi) * 0.5
	for entry: Vector2 in loads:
		if entry.x <= mid:
			_front_n += entry.y
		else:
			_rear_n += entry.y


func _contact_count() -> int:
	if _arena == null or _arena.combatants.is_empty():
		return 0
	var c: CombatArena.Combatant = _arena.combatants[0]
	var n := 0
	for slot: int in c.motion.motive_slots():
		n += c.motion.contact_count(slot)
	return n


func _teardown() -> void:
	if _arena != null:
		_arena.close()
		_arena = null
