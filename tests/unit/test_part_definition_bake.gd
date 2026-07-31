extends TestCase
## Derived-field baking on [PartDefinition].
##
## These fields are computed once, by [code]PartRegistry[/code], and are then
## read by the lattice solver, the fusion SDF baker, and the damage model for
## the rest of the process lifetime. Architectural Invariant I-11 means nothing
## recomputes them, so an error here is permanent and silent: a wrong
## [code]bounds_min_cell[/code] does not crash, it just makes a part's occupancy
## bitset disagree with its cell list.


func test_bounds_cover_every_occupied_cell() -> void:
	var def := _make_l_shape()
	check_eq(def.bounds_min_cell, Vector3i(0, 0, 0), "bounds minimum")
	check_eq(def.bounds_max_cell, Vector3i(2, 1, 0), "bounds maximum")
	check_eq(def.bounds_size_cells, Vector3i(3, 2, 1), "bounds size is inclusive of both faces")


func test_volume_and_integrity_per_cell() -> void:
	var def := _make_l_shape()
	check_eq(def.volume_cells, 4, "four occupied cells")
	check_approx(def.integrity_per_cell, def.integrity_max / 4.0, "integrity spread over cells")


func test_occupancy_bitset_agrees_with_the_cell_list() -> void:
	var def := _make_l_shape()
	# Every authored cell reads back as occupied...
	for c in def.occupancy_cells:
		var cell := Vector3i(int(c.x), int(c.y), int(c.z))
		check_true(def.occupies_local(cell), "authored cell %v must read as occupied" % cell)
	# ...and every other cell in the bounding box reads back as empty.
	var empties := 0
	for x in def.bounds_size_cells.x:
		for y in def.bounds_size_cells.y:
			for z in def.bounds_size_cells.z:
				var cell := def.bounds_min_cell + Vector3i(x, y, z)
				if def.occupies_local(cell):
					continue
				empties += 1
	check_eq(empties, 2, "the L shape leaves two cells of its 3x2x1 box empty")


func test_occupies_local_rejects_cells_outside_the_bounds() -> void:
	var def := _make_l_shape()
	check_false(def.occupies_local(Vector3i(-1, 0, 0)), "below bounds on x")
	check_false(def.occupies_local(Vector3i(0, -1, 0)), "below bounds on y")
	check_false(def.occupies_local(Vector3i(3, 0, 0)), "above bounds on x")
	check_false(def.occupies_local(Vector3i(0, 0, 1)), "above bounds on z")


func test_bake_is_idempotent() -> void:
	# Validators re-run the bake to check a definition without mutating it.
	var def := _make_l_shape()
	var bounds := def.bounds_min_cell
	var bitset := def.occupancy_bitset.duplicate()
	def._bake_derived_fields()
	def._bake_derived_fields()
	check_eq(def.bounds_min_cell, bounds, "bounds stable across repeated bakes")
	check_eq(def.occupancy_bitset, bitset, "bitset stable across repeated bakes")
	check_eq(def.volume_cells, 4, "volume stable across repeated bakes")


func test_single_cell_part_bakes_cleanly() -> void:
	var def := PartDefinition.new()
	def.occupancy_cells = PackedVector3Array([Vector3.ZERO])
	def.integrity_max = 100.0
	def._bake_derived_fields()
	check_eq(def.bounds_size_cells, Vector3i.ONE, "a one-cell part has a 1x1x1 box")
	check_eq(def.volume_cells, 1, "one cell")
	check_approx(def.integrity_per_cell, 100.0, "all integrity in the single cell")
	check_true(def.occupies_local(Vector3i.ZERO), "the pivot cell is occupied")
	check_eq(def.occupancy_bitset.size(), 1, "one cell packs into one byte")


func test_empty_occupancy_does_not_produce_inverted_bounds() -> void:
	# A malformed definition must still bake to something the validator can
	# report on, rather than leaving INT_MAX/INT_MIN bounds that overflow every
	# downstream size computation.
	var def := PartDefinition.new()
	def._bake_derived_fields()
	check_eq(def.bounds_min_cell, Vector3i.ZERO, "empty bounds collapse to origin")
	check_eq(def.bounds_max_cell, Vector3i.ZERO, "empty bounds collapse to origin")
	check_eq(def.volume_cells, 0, "no cells")
	check_true(def.integrity_per_cell > 0.0, "integrity_per_cell must not divide by zero")


func test_occupancy_volume_uses_the_lattice_unit() -> void:
	var def := _make_l_shape()
	var u := SyndicateConstants.LATTICE_UNIT_M
	check_approx(def.occupancy_volume_m3(), 4.0 * u * u * u, "four cells at the lattice unit")


func test_class_payload_resolves_per_part_class() -> void:
	var def := PartDefinition.new()
	def.occupancy_cells = PackedVector3Array([Vector3.ZERO])
	def._bake_derived_fields()

	def.part_class = PartEnums.PartClass.CORE_MODULE
	def.core_profile = CoreModuleProfile.new()
	check_eq(def.class_payload(), def.core_profile, "core module resolves its core profile")

	def.part_class = PartEnums.PartClass.EFFECTOR_MODULE
	def.effector_profile = EffectorModuleProfile.new()
	check_eq(def.class_payload(), def.effector_profile, "effector resolves its effector profile")

	# Structural Components carry no class payload by design, which is a valid
	# state rather than a malformed one.
	def.part_class = PartEnums.PartClass.STRUCTURAL_COMPONENT
	check_null(def.class_payload(), "structural components have no class payload")


## An L-shaped part occupying four of the six cells of a 3x2x1 box.
## Deliberately not a rectangular solid: a bitset bug that stores the bounding
## box rather than the occupancy would pass on any convex footprint.
func _make_l_shape() -> PartDefinition:
	var def := PartDefinition.new()
	def.occupancy_cells = PackedVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(2, 0, 0),
		Vector3(0, 1, 0),
	])
	def.integrity_max = 400.0
	def._bake_derived_fields()
	return def
