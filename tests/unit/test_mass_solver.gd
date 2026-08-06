extends TestCase
## [MassSolver] and [InertiaSolver] — §3 of doc 05, and §6's island tensor.
##
## Mass properties are the second quantity in the project that is computed
## rather than recorded, and they fail the same way strain does: quietly, and
## into a number that still looks plausible. A dropped parallel-axis term leaves
## an Assembly that rotates far too easily; a centre of mass computed over the
## wrong slot set leaves one that pulls to the side a part used to be on. Neither
## produces an error, and both are indistinguishable from bad handling balance.
##
## So every expected value below is written out as arithmetic against the
## published part tables, not derived by calling the code under test with
## different arguments. A test that computes its expectation the way the solver
## does passes with the solver wrong.

const CORE_KEY := &"core.command.compact.t2"
const PANEL_KEY := &"str.panel.medium.t2"

const CORE_ORIGIN := Vector3i(24, 4, 24)
const DECK_ORIGIN := Vector3i(24, 8, 24)

## Doc 01 §10. Re-asserted in [method test_fixture_parts_are_what_the_arithmetic_assumes]
## so that a data change names itself rather than failing as a wrong tensor.
const CORE_MASS := 1800.0
const PANEL_MASS := 100.0

## Centre of mass of one part in assembly-local metres, from doc 05 §3.2:
## [code]cell_to_local(origin) + R · com_offset[/code]. At orientation 0 with the
## published offsets these come out round.
##
## Panel at (24, 8, 24): cell centre (0.125, 1.125, 0.125) + (-0.125, 0, -0.125).
const PANEL_COM_AT_DECK := Vector3(0.0, 1.125, 0.0)
## Core at (24, 4, 24): cell centre (0.125, 0.125, 0.125) + (-0.125, 0.375, -0.125).
## The z term went to zero when the hull went from 13 cells to 14: an odd cell
## count centres on the pivot cell and an even one straddles it.
const CORE_COM_AT_ORIGIN := Vector3(0.0, 0.5, 0.0)

## Box tensor of one panel about its own centre, doc 05 §3.3. The panel occupies
## 4 x 1 x 4 cells, so its full extents are (1.0, 0.25, 1.0) m:
##   I_xx = (100/12)(0.25² + 1.00²) = 8.333333 · 1.0625  = 8.854167
##   I_yy = (100/12)(1.00² + 1.00²) = 8.333333 · 2.0     = 16.666667
##   I_zz = (100/12)(1.00² + 0.25²) = 8.333333 · 1.0625  = 8.854167
const PANEL_TENSOR := Vector3(8.854167, 16.666667, 8.854167)

## The Core Module occupies 8 x 4 x 14 cells: full extents (2.0, 1.0, 3.5) m.
##   I_xx = (1800/12)(1.00² + 3.50²) = 150.0 · 13.25 = 1987.5
##   I_yy = (1800/12)(2.00² + 3.50²) = 150.0 · 16.25 = 2437.5
##   I_zz = (1800/12)(2.00² + 1.00²) = 150.0 ·  5.00 =  750.0
##
## The tensor is the quantity a rebuild moves furthest and the one nothing else
## notices: doc 01 §10 records that an inertia grows as the square of the extents
## while a mass does not. This hull kept its 1800 kg and changed shape, and its
## `I_zz` went up by 54% — every rotational authority in the project is a torque
## over one of these three numbers, so the build turns more slowly than it did
## for no reason a mass table would show.
const CORE_TENSOR := Vector3(1987.5, 2437.5, 750.0)

## Tensors run to two significant figures past the decimal point in the
## constants above; the solver's own arithmetic is exact to float precision.
const TENSOR_TOLERANCE := 1e-4

var _core: PartDefinition = null
var _panel: PartDefinition = null


func before_all() -> void:
	_core = PartRegistry.definition_by_key(CORE_KEY)
	_panel = PartRegistry.definition_by_key(PANEL_KEY)


## ===== FIXTURE SANITY ==================================================


func test_fixture_parts_are_what_the_arithmetic_assumes() -> void:
	check_not_null(_core, "the Core Module is registered")
	check_not_null(_panel, "the Structural Component is registered")
	check_approx(_core.mass_kg, CORE_MASS, "core mass matches doc 01 §10.1")
	check_approx(_panel.mass_kg, PANEL_MASS, "panel mass matches doc 01 §10.2")
	check_eq(_core.bounds_size_cells, Vector3i(8, 4, 14), "core occupies 8 x 4 x 14 cells")
	check_eq(_panel.bounds_size_cells, Vector3i(4, 1, 4), "panel occupies 4 x 1 x 4 cells")
	check_eq(
		_panel.inertia_box_half_extents_m, Vector3.ZERO,
		"the panel has no authored inertia override, so its bounds are its box"
	)


## ===== §3.2 CENTRE OF MASS =============================================


func test_part_centre_of_mass_is_the_cell_centre_plus_the_rotated_offset() -> void:
	var st := _state(0, _panel, DECK_ORIGIN)
	_check_vector(
		MassSolver.part_com_local(st, _panel), PANEL_COM_AT_DECK,
		"panel centre of mass at the deck origin"
	)
	var core_st := _state(0, _core, CORE_ORIGIN)
	_check_vector(
		MassSolver.part_com_local(core_st, _core), CORE_COM_AT_ORIGIN,
		"core centre of mass at the lattice origin"
	)


func test_orientation_rotates_the_offset_rather_than_the_cell() -> void:
	# The pivot cell does not move when a part is rotated in place — only the
	# authored offset from it does. A solver that rotated the whole position
	# would put every non-identity part somewhere near the lattice origin.
	var yaw := _orientation_mapping_x_to(Vector3(0, 0, 1))
	if not check_ne(yaw, -1, "the orientation group contains a +X to +Z rotation"):
		return
	var st := _state(0, _panel, DECK_ORIGIN, yaw)
	var expected := (
		LatticeMath.cell_to_local(DECK_ORIGIN)
		+ OrientationTable.basis_for(yaw) * _panel.com_offset_m
	)
	_check_vector(MassSolver.part_com_local(st, _panel), expected, "rotated panel centre")
	check_approx(
		MassSolver.part_com_local(st, _panel).y, PANEL_COM_AT_DECK.y,
		"a rotation about Y leaves the height alone"
	)


func test_assembly_centre_of_mass_is_the_mass_weighted_mean() -> void:
	var f := _core_and_deck_panel()
	var mp := MassSolver.compute(f.states, f.graph)

	check_eq(mp.part_count, 2, "both parts counted")
	check_approx(mp.total_mass, CORE_MASS + PANEL_MASS, "total mass is 1900 kg")
	# (1800 · (0, 0.5, 0) + 100 · (0, 1.125, 0)) / 1900
	var expected := (
		CORE_COM_AT_ORIGIN * CORE_MASS + PANEL_COM_AT_DECK * PANEL_MASS
	) / (CORE_MASS + PANEL_MASS)
	_check_vector(mp.com_local, expected, "centre of mass of the two-part Assembly")
	check_approx(mp.com_local.y, 0.532895, "the panel on top raises the centre of mass")


func test_a_symmetric_pair_puts_the_centre_of_mass_exactly_between_them() -> void:
	var f := _two_panels_apart()
	var mp := MassSolver.compute(f.states, f.graph)
	check_approx(mp.total_mass, PANEL_MASS + PANEL_MASS, "two panels weigh 200 kg")
	_check_vector(
		mp.com_local, Vector3(0.0, 1.125, 0.5),
		"equal masses one metre apart in Z meet at the halfway point"
	)


func test_an_empty_assembly_has_no_mass_and_a_finite_centre() -> void:
	var f := _fixture()
	var mp := MassSolver.compute(f.states, f.graph)
	check_eq(mp.part_count, 0, "no parts")
	check_approx(mp.total_mass, 0.0, "no mass")
	_check_vector(mp.com_local, Vector3.ZERO, "the centre of mass is finite, not NaN")
	_check_vector(
		InertiaSolver.diagonal_of(mp.inertia_full), Vector3.ZERO, "no inertia"
	)


## ===== §3.1 THE LIVE SET ===============================================


func test_a_detached_part_contributes_nothing() -> void:
	var f := _core_and_deck_panel()
	f.states[1].set_flag(PartFlags.FLAG_DETACHED, true)
	var mp := MassSolver.compute(f.states, f.graph)

	check_eq(mp.part_count, 1, "only the core is live")
	check_approx(mp.total_mass, CORE_MASS, "the detached panel's mass is gone")
	_check_vector(mp.com_local, CORE_COM_AT_ORIGIN, "the centre of mass falls back")
	_check_vector(
		mp.inertia_diag, CORE_TENSOR,
		"and so does the tensor, to the core's own box about its own centre"
	)


func test_a_slot_the_graph_has_killed_contributes_nothing() -> void:
	# Two independent gates, and both are load-bearing: the graph kills a slot on
	# removal without touching its state, and the damage layer flags a state
	# without waiting for the graph.
	var f := _core_and_deck_panel()
	f.graph.detach(1)
	var mp := MassSolver.compute(f.states, f.graph)

	check_eq(mp.part_count, 1, "a slot the graph reports dead is skipped")
	check_approx(mp.total_mass, CORE_MASS, "its mass goes with it")


func test_capture_records_live_slots_in_ascending_order() -> void:
	var f := _core_and_deck_panel()
	var input := MassSolver.capture(7, f.states, f.graph, 42)

	check_eq(input.assembly_id, 7, "the snapshot carries its Assembly id")
	check_eq(input.source_tick, 42, "and the tick it was taken on")
	check_eq(input.slots, PackedByteArray([0, 1]), "slots ascending")
	check_eq(
		input.def_ids, PackedInt32Array([_core.runtime_id, _panel.runtime_id]),
		"definition ids in the same order"
	)
	check_eq(input.orientations, PackedByteArray([0, 0]), "orientations in the same order")
	check_eq(
		Vector3i(input.origin_cells[0]), CORE_ORIGIN,
		"lattice cells survive the float round trip exactly"
	)


func test_the_snapshot_is_the_whole_input() -> void:
	# The worker thread sees the snapshot and nothing else, so mutating the
	# Assembly after capture must not change the result. If it does, the solve
	# is racing the tick that scheduled it.
	var f := _core_and_deck_panel()
	var input := MassSolver.capture(0, f.states, f.graph, 0)
	f.graph.detach(1)
	f.states[1] = null

	var mp := MassSolver.compute_from(input)
	check_eq(mp.part_count, 2, "the snapshot still holds both parts")
	check_approx(mp.total_mass, CORE_MASS + PANEL_MASS, "and both masses")


## ===== §3.3 THE TENSOR =================================================


func test_a_single_part_at_the_centre_of_mass_is_its_own_box_tensor() -> void:
	# With one part the Assembly centre of mass is that part's centre, so the
	# parallel-axis term is zero and what is left is the box alone.
	var f := _fixture()
	_place(f, 0, _panel, DECK_ORIGIN, ChassisGraph.INVALID)
	var mp := MassSolver.compute(f.states, f.graph)
	_check_vector(mp.inertia_diag, PANEL_TENSOR, "one panel's tensor is its box")


func test_the_box_tensor_matches_the_uniform_prism_formula() -> void:
	_check_vector(
		InertiaSolver.box_tensor(PANEL_MASS, InertiaSolver.half_extents(_panel)),
		PANEL_TENSOR,
		"panel box tensor"
	)
	_check_vector(
		InertiaSolver.box_tensor(CORE_MASS, InertiaSolver.half_extents(_core)),
		CORE_TENSOR,
		"core box tensor"
	)
	check_eq(
		InertiaSolver.half_extents(_panel), Vector3(0.5, 0.125, 0.5),
		"half extents come from the lattice bounds when nothing overrides them"
	)


func test_an_authored_override_replaces_the_lattice_bounds() -> void:
	var def := PartDefinition.new()
	def.occupancy_cells = _panel.occupancy_cells
	def.inertia_box_half_extents_m = Vector3(1.0, 2.0, 3.0)
	def._bake_derived_fields()
	check_eq(
		InertiaSolver.half_extents(def), Vector3(1.0, 2.0, 3.0),
		"the override wins over the bounds it disagrees with"
	)


func test_offset_parts_carry_the_parallel_axis_term() -> void:
	# Two panels one metre apart in Z, so each sits 0.5 m from the shared centre.
	# Every axis perpendicular to that offset gains m·d² = 100 · 0.25 = 25 per
	# panel; the axis along it gains nothing.
	var f := _two_panels_apart()
	var mp := MassSolver.compute(f.states, f.graph)
	var shift := PANEL_MASS * 0.25

	check_approx(
		mp.inertia_diag.x, 2.0 * PANEL_TENSOR.x + 2.0 * shift,
		"I_xx picks up both shifts", TENSOR_TOLERANCE
	)
	check_approx(
		mp.inertia_diag.y, 2.0 * PANEL_TENSOR.y + 2.0 * shift,
		"I_yy picks up both shifts", TENSOR_TOLERANCE
	)
	check_approx(
		mp.inertia_diag.z, 2.0 * PANEL_TENSOR.z,
		"I_zz gains nothing from an offset along Z", TENSOR_TOLERANCE
	)


func test_a_diagonal_offset_produces_the_products_of_inertia() -> void:
	# The off-diagonal terms are the entire reason §3.4 exists: Godot's
	# RigidBody3D.inertia is a Vector3, so these are discarded when the body is
	# written and reapplied as an explicit coupling torque. A solver that never
	# produced them would make that correction a no-op and an asymmetric
	# Assembly would refuse to precess.
	var f := _fixture()
	_place(f, 0, _panel, DECK_ORIGIN, ChassisGraph.INVALID)
	_place(f, 1, _panel, DECK_ORIGIN + Vector3i(4, 0, 4), 0)
	var mp := MassSolver.compute(f.states, f.graph)

	_check_vector(mp.com_local, Vector3(0.5, 1.125, 0.5), "the pair meets on the diagonal")
	# Each panel sits at d = (±0.5, 0, ±0.5), so −m·d_x·d_z = −25 twice over.
	check_approx(
		mp.inertia_full.x.z, -2.0 * PANEL_MASS * 0.25,
		"I_zx carries the product of inertia", TENSOR_TOLERANCE
	)
	check_approx(
		mp.inertia_full.z.x, mp.inertia_full.x.z, "the tensor is symmetric", TENSOR_TOLERANCE
	)
	check_approx(mp.inertia_full.x.y, 0.0, "no product where the offset has no Y")
	check_approx(
		mp.inertia_diag.x, mp.inertia_full.x.x,
		"the diagonal Godot gets is the tensor's own diagonal", TENSOR_TOLERANCE
	)


func test_rotating_a_part_permutes_its_tensor() -> void:
	# The panel's box is 4 x 1 x 4 cells, so its Y axis is the odd one out. Stand
	# it on edge and the large moment must move with it. A solver that rotated
	# the position but not the tensor leaves it pointing the original way.
	var pitch := _orientation_mapping_y_to(Vector3(0, 0, 1))
	if not check_ne(pitch, -1, "the orientation group contains a +Y to +Z rotation"):
		return
	var f := _fixture()
	_place(f, 0, _panel, DECK_ORIGIN, ChassisGraph.INVALID, pitch)
	var mp := MassSolver.compute(f.states, f.graph)

	check_approx(
		mp.inertia_diag.z, PANEL_TENSOR.y, "the large moment followed Y onto Z", TENSOR_TOLERANCE
	)
	check_approx(
		mp.inertia_diag.y, PANEL_TENSOR.z, "and the small one took its place", TENSOR_TOLERANCE
	)
	check_approx(
		mp.inertia_diag.x, PANEL_TENSOR.x, "the axis the rotation left alone is unchanged",
		TENSOR_TOLERANCE
	)


func test_zero_is_the_additive_identity_and_the_basis_default_is_not() -> void:
	# Basis() is the identity matrix. Accumulating onto it adds a unit tensor to
	# every Assembly in the game — small enough to look like rounding on a heavy
	# build and dominant on a light one.
	var z := InertiaSolver.zero()
	_check_vector(InertiaSolver.diagonal_of(z), Vector3.ZERO, "zero() has a zero diagonal")
	_check_vector(
		InertiaSolver.diagonal_of(Basis()), Vector3.ONE, "Basis() is the identity, not zero"
	)
	var t := InertiaSolver.parallel_axis(PANEL_MASS, Vector3(0.0, 0.0, 0.5))
	_check_vector(
		InertiaSolver.diagonal_of(InertiaSolver.add(z, t)),
		InertiaSolver.diagonal_of(t),
		"adding zero changes nothing"
	)


## ===== §6 ISLAND TENSOR ================================================


func test_an_island_of_one_part_is_that_part_about_its_own_centre() -> void:
	var f := _core_and_deck_panel()
	var com := MassSolver.part_com_local(f.states[1], _panel)
	_check_vector(
		InertiaSolver.island_inertia(f.states, PackedByteArray([1]), com),
		PANEL_TENSOR,
		"a single-part island carries only its box"
	)


func test_an_island_tensor_is_taken_about_the_island_centre_not_the_assembly() -> void:
	# The distinction is the whole of §6's re-centring: debris spins about its
	# own centre of mass, and using the parent Assembly's would give a panel the
	# rotational inertia of the vehicle it came off.
	var f := _two_panels_apart()
	var island := PackedByteArray([0, 1])
	var about_island := InertiaSolver.island_inertia(f.states, island, Vector3(0.0, 1.125, 0.5))
	var about_origin := InertiaSolver.island_inertia(f.states, island, Vector3.ZERO)

	check_approx(
		about_island.x, 2.0 * PANEL_TENSOR.x + 2.0 * PANEL_MASS * 0.25,
		"about its own centre each panel is 0.5 m out", TENSOR_TOLERANCE
	)
	check_true(
		about_origin.x > about_island.x,
		"and about any other point it is larger, which is the parallel-axis theorem"
	)


func test_an_island_ignores_slots_that_hold_nothing() -> void:
	var f := _core_and_deck_panel()
	var com := MassSolver.part_com_local(f.states[1], _panel)
	_check_vector(
		InertiaSolver.island_inertia(f.states, PackedByteArray([1, 9]), com),
		PANEL_TENSOR,
		"an empty slot in the island list contributes nothing"
	)


## ===== §3.5 APPLICATION ================================================


func test_applied_properties_reach_the_body() -> void:
	var f := _core_and_deck_panel()
	var mp := MassSolver.compute(f.states, f.graph)
	var body := RigidBody3D.new()
	MassSolver.apply_mass_properties(body, mp)

	check_approx(body.mass, CORE_MASS + PANEL_MASS, "the body carries the solved mass")
	check_eq(
		body.center_of_mass_mode, RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM,
		"the solved centre is used rather than one derived from the shapes"
	)
	_check_vector(body.center_of_mass, mp.com_local, "the solved centre reaches the body")
	_check_vector(body.inertia, mp.inertia_diag, "and so does the diagonal", TENSOR_TOLERANCE)
	body.free()


func test_an_assembly_that_loses_everything_is_floored_rather_than_left_stale() -> void:
	# Reachable, and worth pinning: doc 04 §7.2 turns every remaining part into
	# debris when the Core Module dies, so a solve can find nothing live while
	# the body is still registered. Godot rejects a mass of zero outright and
	# leaves whatever the body had — a wreck still reporting its live mass — and reads a
	# zero inertia component as "derive it from the collision shapes", which is
	# exactly the coupling Architectural Invariant I-1 forbids.
	var loaded := _core_and_deck_panel()
	var body := RigidBody3D.new()
	MassSolver.apply_mass_properties(body, MassSolver.compute(loaded.states, loaded.graph))
	check_approx(body.mass, CORE_MASS + PANEL_MASS, "the body starts out loaded")

	var empty := _fixture()
	MassSolver.apply_mass_properties(body, MassSolver.compute(empty.states, empty.graph))
	check_approx(body.mass, MassSolver.MIN_BODY_MASS_KG, "mass is floored, not left stale")
	_check_vector(body.inertia, Vector3.ONE * MassSolver.MIN_BODY_INERTIA, "so is the tensor")
	body.free()


## ===== FIXTURES ========================================================


func _fixture() -> Fixture:
	var f := Fixture.new()
	f.states.resize(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY)
	f.graph = ChassisGraph.new()
	return f


## Core Module at slot 0, one Structural Component on its deck at slot 1.
func _core_and_deck_panel() -> Fixture:
	var f := _fixture()
	_place(f, 0, _core, CORE_ORIGIN, ChassisGraph.INVALID)
	_place(f, 1, _panel, DECK_ORIGIN, 0)
	return f


## Two panels one metre apart along Z, so the arithmetic stays exact. The graph
## does not care that slot 0 is not a Core Module — only [PlacementValidator]
## enforces I-2 — and a symmetric pair is what makes the parallel-axis term
## readable.
func _two_panels_apart() -> Fixture:
	var f := _fixture()
	_place(f, 0, _panel, DECK_ORIGIN, ChassisGraph.INVALID)
	_place(f, 1, _panel, DECK_ORIGIN + Vector3i(0, 0, 4), 0)
	return f


func _place(
	f: Fixture,
	slot: int,
	def: PartDefinition,
	cell: Vector3i,
	parent: int,
	orientation: int = 0
) -> void:
	f.states[slot] = _state(slot, def, cell, orientation)
	f.graph.attach(slot, parent, [] as Array[MateRecord], def.mass_kg)


func _state(
	slot: int, def: PartDefinition, cell: Vector3i, orientation: int = 0
) -> PartInstanceState:
	var st := PartInstanceState.new()
	st.slot = slot
	st.part_def_id = def.runtime_id
	st.origin_cell = cell
	st.orientation_index = orientation
	st.integrity = def.integrity_max
	return st


## Lowest orientation index whose basis carries part-local +X onto [param axis].
## Used to name a rotation by what it does rather than by an index literal.
func _orientation_mapping_x_to(axis: Vector3) -> int:
	for i in SyndicateConstants.ORIENTATION_COUNT:
		if (OrientationTable.basis_for(i) * Vector3(1, 0, 0)).is_equal_approx(axis):
			return i
	return -1


func _orientation_mapping_y_to(axis: Vector3) -> int:
	for i in SyndicateConstants.ORIENTATION_COUNT:
		if (OrientationTable.basis_for(i) * Vector3(0, 1, 0)).is_equal_approx(axis):
			return i
	return -1


func _check_vector(
	actual: Vector3, expected: Vector3, message: String, tolerance := 1e-5
) -> void:
	check_approx(actual.x, expected.x, "%s (x)" % message, tolerance)
	check_approx(actual.y, expected.y, "%s (y)" % message, tolerance)
	check_approx(actual.z, expected.z, "%s (z)" % message, tolerance)


class Fixture:
	extends RefCounted

	var states: Array[PartInstanceState] = []
	var graph: ChassisGraph = null
