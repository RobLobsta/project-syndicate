extends TestCase
## Doc 02 §10's symmetry mirroring, against the one build in the repository that
## was mirrored by hand.
##
## [b]The shipped starter is the ground truth.[/b] It was authored placement by
## placement, in session 26, by somebody working out each flank separately — and
## the two flanks disagree about the pivot on every part that is not on the
## centre line. That is not sloppiness in the data: a pivot is not the middle of
## a footprint, and a mirrored part is rotated as well as moved, so the two
## flanks of a correct build *have* to carry different origin cells. Any mirror
## implementation that reproduces the shipped starter has dealt with both, and
## one that mirrors the pivot cell reproduces neither.
##
## So the first test below is worth more than the rest together: it takes every
## part of a real build in turn and demands that its reflection is the part
## already standing on the other flank.

const CORE_KEY: StringName = &"core.command.compact.t2"
const PANEL_KEY: StringName = &"str.panel.medium.t2"

## Off-centre on the Core Module's deck, overhanging to starboard. Its mirror is
## the same panel overhanging to port, and neither overlaps the other.
const OFF_CENTRE_CELL := Vector3i(26, 8, 24)
const OFF_CENTRE_MIRROR_CELL := Vector3i(22, 8, 24)

var _contexts: Array[BuildContext] = []


func after_all() -> void:
	for ctx: BuildContext in _contexts:
		ctx.dispose()
	_contexts.clear()


## ===== THE REFLECTION ==================================================


## Every part of the shipped starter mirrors onto a part of the shipped starter.
##
## Twelve placements: four that straddle the centre plane and are their own
## reflection, and eight that pair up across it. A mirror that is off by one cell
## fails on the stations, one that ignores orientation fails on the contacts, and
## one that mirrors the pivot instead of the footprint fails on both.
func test_the_shipped_starter_is_its_own_mirror() -> void:
	var ctx := _starter()
	var checked := 0
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var st := ctx.state(slot)
		if st == null:
			continue
		checked += 1
		var here := PlacementCandidate.create(
			PartRegistry.definition(st.part_def_id), st.origin_cell, st.orientation_index
		)
		var there := here.mirrored_x()
		var other := _slot_filling(ctx, there.cells)
		check_true(
			other != SyndicateConstants.INVALID_SLOT,
			"the mirror of slot %d at %v is a part of this build" % [slot, st.origin_cell]
		)
		if other == SyndicateConstants.INVALID_SLOT:
			continue
		check_eq(
			ctx.state(other).part_def_id,
			st.part_def_id,
			"and it is the same part as slot %d" % slot
		)
		check_eq(
			ctx.state(other).orientation_index,
			there.orientation_index,
			"in the orientation the reflection asks for, for slot %d" % slot
		)
	check_eq(checked, 12, "the starter is twelve parts and every one of them was mirrored")


## The trap, stated as a test so that nobody re-derives it.
##
## `LatticeMath.mirror_x` reflects a *cell*, which is what doc 02 §10's sketch
## applies to an origin cell. On the shipped station that answer is one cell
## short, because the station's pivot sits at the high-x end of its own two-cell
## footprint and the reflection puts it at the low-x end.
func test_a_mirror_reflects_the_footprint_and_not_the_pivot() -> void:
	var ctx := _starter()
	var station := PartRegistry.definition_by_key(StarterBlueprint.HUB_KEY)
	var port := PlacementCandidate.create(
		station, StarterBlueprint.HUB_CELLS[0], OrientationTable.IDENTITY_INDEX
	)
	var starboard := port.mirrored_x()

	check_eq(
		starboard.origin_cell,
		StarterBlueprint.HUB_CELLS[1],
		"the station mirrors onto the station the starter authored opposite it"
	)
	check_ne(
		LatticeMath.mirror_x(port.origin_cell),
		starboard.origin_cell,
		"which is not where reflecting the pivot cell alone would have put it"
	)
	check_true(
		_slot_filling(ctx, starboard.cells) != SyndicateConstants.INVALID_SLOT,
		"and the cells it lands on are the ones that station occupies"
	)


## A reflection is its own inverse, and a rotation group that cannot express one
## is where that stops being true. Every one of the twenty-four is tried, because
## `mirror_x_index` picks a best match and a best match that is not an involution
## would make mirror mode drift a part's facing each time it is used.
func test_mirroring_twice_is_the_placement_it_started_from() -> void:
	var panel := PartRegistry.definition_by_key(PANEL_KEY)
	for orientation: int in SyndicateConstants.ORIENTATION_COUNT:
		var here := PlacementCandidate.create(panel, OFF_CENTRE_CELL, orientation)
		var back := here.mirrored_x().mirrored_x()
		check_eq(back.origin_cell, here.origin_cell, "orientation %d returns" % orientation)
		check_true(
			back.occupies_the_same_cells_as(here),
			"and occupies the cells it started on, from orientation %d" % orientation
		)


func test_a_part_across_the_centre_plane_is_its_own_reflection() -> void:
	# Invariant I-2's Core Module is four cells wide and seated on the origin, so
	# the only plane that maps it onto itself is the one §10 mirrors in. If this
	# ever fails, the mirror plane has moved and every build is asymmetric.
	var core := PlacementCandidate.create(
		PartRegistry.definition_by_key(CORE_KEY),
		StarterBlueprint.CORE_CELL,
		OrientationTable.IDENTITY_INDEX
	)
	check_true(
		core.mirrored_x().occupies_the_same_cells_as(core),
		"the Core Module reflects onto itself"
	)


## ===== THE EDIT ========================================================


## §10's whole purpose: one gesture, two parts — and one undo, because the pair
## is one command. Two commands would mean a mirrored build comes apart under
## Ctrl+Z one flank at a time, which is what mirror mode exists to stop a player
## doing by hand.
func test_a_mirrored_placement_is_one_command() -> void:
	var ctx := _core_only()
	var history := BuildHistory.new()
	var before := ctx.occupancy.occupied_count

	var cand := _candidate(ctx, OFF_CENTRE_CELL)
	var cmd := history.attach(ctx, cand, cand.mirrored_x())
	check_not_null(cmd, "the placement committed")
	if cmd == null:
		return
	check_eq(cmd.attach_size(), 2, "carrying both halves")
	check_true(
		ctx.occupancy.slot_at(OFF_CENTRE_CELL) != SyndicateConstants.INVALID_SLOT,
		"the panel is on the lattice"
	)
	check_true(
		ctx.occupancy.slot_at(OFF_CENTRE_MIRROR_CELL) != SyndicateConstants.INVALID_SLOT,
		"and so is its mirror"
	)

	check_eq(history.depth(), 1, "one gesture is one command")
	history.undo(ctx)
	check_eq(ctx.occupancy.occupied_count, before, "and one undo takes both halves back")


## §10: a refused mirror never blocks a legal placement.
##
## The mirror lands on a panel that is already there, so the validator refuses it
## for occupancy — and the placement the player actually pointed at still goes
## down. The alternative reading, refusing both, would make mirror mode something
## a player has to turn off to finish a build.
func test_a_refused_mirror_leaves_the_placement_alone() -> void:
	var ctx := _core_only()
	var history := BuildHistory.new()
	PlacementValidator.commit(ctx, _candidate(ctx, OFF_CENTRE_MIRROR_CELL))
	var taken := ctx.occupancy.slot_at(OFF_CENTRE_MIRROR_CELL)

	var cand := _candidate(ctx, OFF_CENTRE_CELL)
	var cmd := history.attach(ctx, cand, cand.mirrored_x())
	check_not_null(cmd, "the placement committed anyway")
	if cmd == null:
		return
	check_eq(cmd.attach_size(), 1, "with the mirror skipped rather than forced")
	check_true(
		ctx.occupancy.slot_at(OFF_CENTRE_CELL) != SyndicateConstants.INVALID_SLOT,
		"the part the player pointed at is on the lattice"
	)
	check_eq(
		ctx.occupancy.slot_at(OFF_CENTRE_MIRROR_CELL),
		taken,
		"and the part that was already there is untouched"
	)

	history.undo(ctx)
	check_eq(
		ctx.occupancy.slot_at(OFF_CENTRE_MIRROR_CELL),
		taken,
		"an undo takes back what went on, and not what was already there"
	)


## What mirror mode is for, stated as the build it saves.
##
## The shipped starter is twelve placements and four of them are the reflection
## of another four. With mirror mode on it is eight gestures — and the result has
## to be the shipped build rather than something like it, or the feature is a
## different way to make a different vehicle.
func test_the_starter_is_eight_gestures_with_mirroring_on() -> void:
	var ctx := _context()
	var history := BuildHistory.new()
	var gestures := 0

	# The centre line, in the starter's own order: doc 05 §7.4's power budget is
	# checked against what the context holds at that moment, so the Energy Cell
	# precedes the draw it covers. Each of these is its own reflection and takes
	# no mirror.
	for placement: Array in [
		[StarterBlueprint.CORE_KEY, StarterBlueprint.CORE_CELL],
		[StarterBlueprint.POWER_KEY, StarterBlueprint.POWER_CELL],
		[StarterBlueprint.CELL_KEY, StarterBlueprint.CELL_CELL],
		[StarterBlueprint.EFFECTOR_KEY, StarterBlueprint.EFFECTOR_CELL],
	]:
		gestures += 1
		_place(ctx, history, placement[0], placement[1], OrientationTable.IDENTITY_INDEX)

	# One flank. Stations before the contacts they carry, exactly as a player has
	# to build it.
	for cell: Vector3i in [StarterBlueprint.HUB_CELLS[0], StarterBlueprint.HUB_CELLS[2]]:
		gestures += 1
		_place(ctx, history, StarterBlueprint.HUB_KEY, cell, OrientationTable.IDENTITY_INDEX)
	for cell: Vector3i in [StarterBlueprint.CONTACT_CELLS[0], StarterBlueprint.CONTACT_CELLS[1]]:
		gestures += 1
		var key := (
			StarterBlueprint.WHEEL_KEY if cell.z < StarterBlueprint.FRONT_AXLE_Z
			else StarterBlueprint.REAR_KEY
		)
		_place(ctx, history, key, cell, OrientationTable.upright_facing(Vector3.RIGHT))

	check_eq(gestures, 8, "eight placements rather than twelve")
	check_eq(history.depth(), 8, "and eight things to undo, one per gesture")

	# The claim is the build, not the count. Every cell the shipped starter
	# occupies is occupied here, by the same part, in the same orientation.
	var shipped := _starter()
	check_eq(
		ctx.occupancy.occupied_count,
		shipped.occupancy.occupied_count,
		"the mirrored build fills the same cells as the authored one"
	)
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var want := shipped.state(slot)
		if want == null:
			continue
		var here := ctx.occupancy.slot_at(want.origin_cell)
		check_true(
			here != SyndicateConstants.INVALID_SLOT,
			"a part stands where the starter's slot %d does" % slot
		)
		if here == SyndicateConstants.INVALID_SLOT:
			continue
		check_eq(ctx.state(here).part_def_id, want.part_def_id, "and it is the same part")
		check_eq(
			ctx.state(here).orientation_index,
			want.orientation_index,
			"in the same orientation"
		)


## ===== FIXTURES ========================================================


func _context() -> BuildContext:
	var ctx := BuildContext.headless(_contexts.size() + 1)
	_contexts.append(ctx)
	return ctx


func _core_only() -> BuildContext:
	var ctx := _context()
	var core := PlacementCandidate.create(
		PartRegistry.definition_by_key(CORE_KEY),
		StarterBlueprint.CORE_CELL,
		OrientationTable.IDENTITY_INDEX
	)
	if PlacementValidator.validate(ctx, core) != PlacementValidator.Reject.NONE:
		fail("fixture: the Core Module was refused")
		return ctx
	PlacementValidator.commit(ctx, core)
	return ctx


func _starter() -> BuildContext:
	var ctx := _context()
	if StarterBlueprint.skirmisher().apply(ctx) != Blueprint.APPLIED_CLEANLY:
		fail("fixture: the shipped starter did not build")
	return ctx


## One gesture with mirror mode on: the placement, and its reflection where the
## reflection is a different part of the build.
func _place(
	ctx: BuildContext,
	history: BuildHistory,
	key: StringName,
	cell: Vector3i,
	orientation: int
) -> void:
	var cand := PlacementCandidate.create(
		PartRegistry.definition_by_key(key), cell, orientation
	)
	var reject := PlacementValidator.validate(ctx, cand)
	if reject != PlacementValidator.Reject.NONE:
		fail("fixture: '%s' at %v was refused with %d" % [key, cell, reject])
		return
	var mirror := cand.mirrored_x()
	if history.attach(
		ctx, cand, null if mirror.occupies_the_same_cells_as(cand) else mirror
	) == null:
		fail("fixture: '%s' at %v did not commit" % [key, cell])


func _candidate(ctx: BuildContext, cell: Vector3i) -> PlacementCandidate:
	var cand := PlacementCandidate.create(
		PartRegistry.definition_by_key(PANEL_KEY), cell, OrientationTable.IDENTITY_INDEX
	)
	var reject := PlacementValidator.validate(ctx, cand)
	if reject != PlacementValidator.Reject.NONE:
		fail("fixture: a panel at %v was refused with %d" % [cell, reject])
	return cand


## The one slot occupying exactly [param cells], or
## [constant SyndicateConstants.INVALID_SLOT].
##
## Every cell is tested rather than just the first: a part whose footprint merely
## overlaps the reflection is not the reflection, and checking one cell would
## accept a station sitting one cell out — which is the defect this whole file
## exists to catch.
static func _slot_filling(ctx: BuildContext, cells: PackedVector3Array) -> int:
	if cells.is_empty():
		return SyndicateConstants.INVALID_SLOT
	var slot := ctx.occupancy.slot_at(Vector3i(cells[0]))
	if slot == SyndicateConstants.INVALID_SLOT:
		return SyndicateConstants.INVALID_SLOT
	for c in cells:
		if ctx.occupancy.slot_at(Vector3i(c)) != slot:
			return SyndicateConstants.INVALID_SLOT
	if ctx.occupancy.cells_of_slot(slot).size() != cells.size():
		return SyndicateConstants.INVALID_SLOT
	return slot
