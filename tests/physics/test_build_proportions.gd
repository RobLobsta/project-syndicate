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
## [b]It was written with two of its assertions asserted as they failed, and the
## rebuild closed both.[/b] The build it was written against was 1107 kg at
## 46 kg/m³ — a fifth of balsa — on a 1.50 m wheelbase under a 4.25 m hull, and
## it stood on two of its four contacts with the front axle carrying every newton.
## It is now 3630 kg at 141 kg/m³ on a 2.75 m wheelbase, standing on all four.
##
## Two findings survive and are asserted the way they are measured, which is this
## file's convention rather than a lapse: the static split is 38% front, so the
## build is rear-biased where a road vehicle is nose-biased, and the wheelbase is
## 73% of the hull where a road vehicle is 55–65%. Both follow from a chassis
## whose axle stations sit on its two ends. Re-measure them when the layout moves;
## do not loosen them.
##
## One Assembly on a slab, which reproduces exactly (LEARNED_FACTS.md §1 fact 44).

## Ticks the build is given to fall onto its contacts and settle.
const SETTLE_TICKS: int = 180

## Contacts the reference build carries, and it stands on every one of them.
const CONTACT_COUNT: int = 4

## Share of the static weight the front axle carries, measured at 38%. The band
## is asserted in both directions: below the floor the build is standing on its
## rear pair the way it used to stand on its front, and above the ceiling it has
## been rebalanced and this constant is the thing to re-measure.
const FRONT_BIAS_FLOOR: float = 0.30
const FRONT_BIAS_CEILING: float = 0.50

## Mass per cubic metre of the bounding box, measured at 141. A passenger car is
## about 115 and the build this file was written against was 46 — the ratio
## LEARNED_FACTS.md §1 fact 75 is about, and the one number that says whether the
## part table is the right shape rather than merely self-consistent.
const DENSITY_FLOOR_KG_M3: float = 100.0
const DENSITY_CEILING_KG_M3: float = 200.0

## Wheelbase as a fraction of hull length, measured at 0.73. A road vehicle is
## 0.55–0.65; this hull carries its axle stations on its two ends, so it runs
## long. Asserted above the road floor and recorded as being past the band.
const WHEELBASE_FRACTION_FLOOR: float = 0.55

## Newtons under which a contact counts as carrying nothing. Well below any real
## share of a 3630 kg build, and above the float noise on a settled spring.
const UNLOADED_N: float = 1.0

var _ran: bool = false
var _arena: CombatArena = null

var _mass_kg: float = 0.0
var _length_m: float = 0.0
var _width_m: float = 0.0
var _height_m: float = 0.0
var _wheelbase_m: float = 0.0
var _loaded: int = 0
var _contacts: int = 0
var _front_n: float = 0.0
var _rear_n: float = 0.0


func after_all() -> void:
	_teardown()


## The whole of the running gear is on the ground, which it was not for the first
## thirty-three sessions of this project.
func test_the_build_stands_on_every_contact_it_carries() -> void:
	await _run()
	check_eq(_contacts, CONTACT_COUNT, "the reference build carries four contacts")
	check_eq(
		_loaded,
		_contacts,
		(
			"%d of %d contacts carry load. If this has fallen, the build has been re-laid "
			+ "and the stance has gone with it — re-measure it, do not loosen it"
		) % [_loaded, _contacts]
	)


## The split, in both directions. A single-sided bound here is satisfied by a
## build standing on one axle, which is the state this file was written to record.
func test_the_static_weight_is_shared_between_the_axles() -> void:
	await _run()
	var total := _front_n + _rear_n
	var bias := 0.0 if total <= 0.0 else _front_n / total
	check_true(
		bias > FRONT_BIAS_FLOOR,
		(
			"the front axle carries %.0f%% of what the springs are holding, which is a "
			+ "share rather than nothing"
		) % (bias * 100.0)
	)
	check_true(
		bias < FRONT_BIAS_CEILING,
		(
			"and the build is still rear-biased at %.0f%% front, because its Prime Mover "
			+ "is on the aft half of the deck. Re-measure if the layout moves"
		) % (bias * 100.0)
	)


## The one number that says whether the part table is the right [i]shape[/i].
func test_the_build_is_as_dense_as_a_vehicle_rather_than_as_balsa() -> void:
	await _run()
	var density := _mass_kg / maxf(_length_m * _width_m * _height_m, 0.01)
	check_true(
		density > DENSITY_FLOOR_KG_M3,
		"%.0f kg/m3 of bounding box, against a passenger car's 115" % density
	)
	check_true(
		density < DENSITY_CEILING_KG_M3,
		"and it is a vehicle rather than a solid billet: %.0f kg/m3" % density
	)


## The remaining proportion finding, recorded rather than repaired: the axle
## stations sit on the hull's two ends, so the wheelbase runs long.
func test_the_wheelbase_spans_the_hull() -> void:
	await _run()
	var fraction := _wheelbase_m / maxf(_length_m, 0.01)
	check_true(
		fraction > WHEELBASE_FRACTION_FLOOR,
		(
			"wheelbase %.2f m under a %.2f m hull is %.0f%%, which is a road vehicle's "
			+ "proportion rather than the 35%% it was"
		) % [_wheelbase_m, _length_m, 100.0 * fraction]
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
	_contacts = _contact_count()
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
			_loaded, _contacts,
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
