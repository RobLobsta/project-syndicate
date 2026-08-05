extends TestCase
## [BuildHistory] and [BuildCommand]: doc 02 §9.3's undo model, over real parts.
##
## The claim being defended is narrow and absolute — **the build after an undo is
## the build before the edit** — and almost every way of getting it wrong looks
## right at a glance. A part comes back in the right cell under a different
## parent; a cascade comes back but the survivor §9.2 re-parented does not go
## home; two removals undone in the other order come back holding each other's
## slots. So the tests here assert the structure that came back rather than the
## part count, and the cycle test exists because none of those structures fails
## loudly.
##
## Headless contexts throughout. Doc 02 §7.7 is the one check that needs a
## physics space and it may only reject, so nothing an undo does can be admitted
## by its absence.

const CORE_KEY: StringName = &"core.command.compact.t2"
const PANEL_KEY: StringName = &"str.panel.medium.t2"

const CORE_CELL := Vector3i(24, 4, 24)
## Slot 1: on the Core Module's deck.
const DECK_CELL := Vector3i(24, 8, 24)
## Slot 2: directly above it, resting on it and on nothing else.
const ABOVE_DECK_CELL := Vector3i(24, 9, 24)
## Slot 3: aft of slot 2 and touching only it at the moment it is placed.
const BRIDGE_CELL := Vector3i(24, 9, 28)
## Slot 4: below slot 3, bridging to the Core Module's aft edge.
const BESIDE_CELL := Vector3i(24, 8, 28)

var _contexts: Array[BuildContext] = []


func after_all() -> void:
	for ctx: BuildContext in _contexts:
		ctx.dispose()
	_contexts.clear()


## ===== ATTACH ==========================================================


func test_an_attach_is_undone_and_redone_into_the_same_cell() -> void:
	var ctx := _core_only()
	var history := BuildHistory.new()
	var before := ctx.occupancy.occupied_count
	var mounts := ctx.budgets.mount_used

	check_not_null(history.attach(ctx, _candidate(ctx, DECK_CELL)), "the panel committed")
	var slot := ctx.occupancy.slot_at(DECK_CELL)
	check_true(slot != SyndicateConstants.INVALID_SLOT, "and is on the lattice")
	check_true(history.can_undo(), "and the stack has something to undo")

	check_not_null(history.undo(ctx), "the undo reports the command it inverted")
	check_null(ctx.state(slot), "the slot is empty again")
	check_eq(ctx.occupancy.occupied_count, before, "the lattice is back where it started")
	check_eq(ctx.budgets.mount_used, mounts, "and so is the mount ledger")
	check_false(history.can_undo(), "with nothing left to undo")
	check_true(history.can_redo(), "and the command waiting to be redone")

	check_not_null(history.redo(ctx), "the redo reports the command")
	var back := ctx.occupancy.slot_at(DECK_CELL)
	check_true(back != SyndicateConstants.INVALID_SLOT, "the panel is on the lattice again")
	check_eq(ctx.state(back).origin_cell, DECK_CELL, "in the cell it was placed in")
	check_eq(
		int(ctx.graph.parent[back]),
		SyndicateConstants.CORE_SLOT,
		"resting on the Core Module as before"
	)


func test_nothing_to_undo_is_answered_rather_than_guessed() -> void:
	var ctx := _core_only()
	var history := BuildHistory.new()
	check_false(history.can_undo(), "a new stack has no history")
	check_null(history.undo(ctx), "and undoing it does nothing")
	check_null(history.redo(ctx), "nor does redoing it")
	check_eq(ctx.occupancy.occupied_count, _core_cells(), "the build is untouched")


## ===== REMOVAL =========================================================


func test_a_removal_comes_back_with_its_cascade_and_its_tree() -> void:
	# The panel above the deck rests on the deck panel alone, so removing the
	# deck panel takes it too (§9.2). The undo has to put both back, in an order
	# where each has something to mate with, and under the parents they had.
	var ctx := _tower()
	var history := BuildHistory.new()
	var cells := ctx.occupancy.occupied_count

	var cmd := history.remove(ctx, ctx.occupancy.slot_at(DECK_CELL))
	check_not_null(cmd, "the removal produced a command")
	if cmd == null:
		return
	check_eq(cmd.cascade_size(), 1, "the panel above it had no other support")
	check_eq(
		ctx.occupancy.slot_at(ABOVE_DECK_CELL),
		SyndicateConstants.INVALID_SLOT,
		"and its cell is empty"
	)

	check_not_null(history.undo(ctx), "the removal is undone")
	check_eq(ctx.occupancy.occupied_count, cells, "every cell is occupied again")
	var lower := ctx.occupancy.slot_at(DECK_CELL)
	var upper := ctx.occupancy.slot_at(ABOVE_DECK_CELL)
	check_true(lower != SyndicateConstants.INVALID_SLOT, "the deck panel is back")
	check_true(upper != SyndicateConstants.INVALID_SLOT, "and so is the one above it")
	check_eq(
		int(ctx.graph.parent[lower]),
		SyndicateConstants.CORE_SLOT,
		"the deck panel rests on the Core Module"
	)
	check_eq(int(ctx.graph.parent[upper]), lower, "and the upper one rests on it")


func test_undo_puts_back_the_parent_the_removal_moved() -> void:
	# §9.2 re-parents an orphan onto whatever it still rests on rather than
	# removing it. That is a change to the Chassis Graph the removal made and
	# recorded nowhere else, so an undo that only restores parts leaves the
	# survivor hanging off the wrong thing — a tree that is legal, is not the one
	# the player had, and attributes strain to a different joint.
	var ctx := _bridge()
	var history := BuildHistory.new()

	history.remove(ctx, ctx.occupancy.slot_at(DECK_CELL))
	var bridge := ctx.occupancy.slot_at(BRIDGE_CELL)
	check_true(bridge != SyndicateConstants.INVALID_SLOT, "the bridging panel survived")
	check_eq(
		int(ctx.graph.parent[bridge]),
		ctx.occupancy.slot_at(BESIDE_CELL),
		"re-parented onto the neighbour it still rests on"
	)

	history.undo(ctx)
	check_eq(
		int(ctx.graph.parent[ctx.occupancy.slot_at(BRIDGE_CELL)]),
		ctx.occupancy.slot_at(ABOVE_DECK_CELL),
		"and the undo hands it back to the part it was resting on"
	)


## The reason a command names a cell and not a slot.
##
## Two removals, undone in the order undo has to take them: the second removal is
## inverted first, and the lowest free slot at that moment is the hole the
## [i]first[/i] removal left. So a part comes back holding a slot it never had,
## and every command still on the stack that named a slot is now pointing at the
## wrong part. Identifying a part by the cell it sits on is immune to it, because
## the cell is where the player put it.
func test_two_removals_undo_through_each_other_s_holes() -> void:
	var ctx := _bridge()
	var history := BuildHistory.new()
	var cells := ctx.occupancy.occupied_count
	var first := ctx.occupancy.slot_at(BRIDGE_CELL)
	var second := ctx.occupancy.slot_at(BESIDE_CELL)
	check_true(first < second, "the fixture removes a low slot before a high one")

	history.remove(ctx, first)
	history.remove(ctx, second)
	history.undo(ctx)
	history.undo(ctx)

	check_eq(ctx.occupancy.occupied_count, cells, "every cell is occupied again")
	for cell: Vector3i in [DECK_CELL, ABOVE_DECK_CELL, BRIDGE_CELL, BESIDE_CELL]:
		var slot := ctx.occupancy.slot_at(cell)
		check_true(slot != SyndicateConstants.INVALID_SLOT, "%v holds a part" % cell)
		if slot == SyndicateConstants.INVALID_SLOT:
			continue
		check_eq(ctx.state(slot).origin_cell, cell, "and it is seated on %v" % cell)
		check_true(ctx.graph.is_connected_to_core(slot), "and %v reaches the core" % cell)

	# The two parts have swapped slots by now, which is the whole hazard: a
	# command that named a slot is pointing at the other one's part. Redo is
	# where that shows, because it is the only operation that has to find a
	# part it did not just put there.
	check_true(
		ctx.occupancy.slot_at(BRIDGE_CELL) > ctx.occupancy.slot_at(BESIDE_CELL),
		"the parts came back holding each other's slots"
	)
	history.redo(ctx)
	check_eq(
		ctx.occupancy.slot_at(BRIDGE_CELL),
		SyndicateConstants.INVALID_SLOT,
		"the first redo takes the part the first removal took"
	)
	check_true(
		ctx.occupancy.slot_at(BESIDE_CELL) != SyndicateConstants.INVALID_SLOT,
		"and leaves the other one where it is"
	)
	history.redo(ctx)
	check_eq(
		ctx.occupancy.slot_at(BESIDE_CELL),
		SyndicateConstants.INVALID_SLOT,
		"and the second redo takes the other"
	)


## ===== THE STACK =======================================================


func test_a_new_edit_discards_the_redo_branch() -> void:
	# There is one history, not a tree. A redo that survived an edit would put
	# back the part the player replaced on purpose.
	var ctx := _core_only()
	var history := BuildHistory.new()
	history.attach(ctx, _candidate(ctx, DECK_CELL))
	history.undo(ctx)
	check_true(history.can_redo(), "the undone placement is redoable")

	history.attach(ctx, _candidate(ctx, BESIDE_CELL))
	check_false(history.can_redo(), "and is discarded by the next edit")
	check_eq(
		ctx.occupancy.slot_at(DECK_CELL),
		SyndicateConstants.INVALID_SLOT,
		"the cell it was in stays empty"
	)


func test_the_stack_stops_at_the_documented_depth() -> void:
	# §9.3 caps undo at 128 commands. Asserted by value rather than against
	# [constant BuildHistory.MAX_DEPTH], so that raising the constant does not
	# quietly raise the expectation with it.
	var ctx := _core_only()
	var history := BuildHistory.new()
	for i in 80:
		history.attach(ctx, _candidate(ctx, DECK_CELL))
		history.remove(ctx, ctx.occupancy.slot_at(DECK_CELL))
	check_eq(history.depth(), 128, "the stack holds the last 128 of 160 commands")

	# What is left still has to invert: the oldest commands were dropped, not
	# corrupted, so undoing everything the stack still holds is legal and lands
	# on the state that preceded the oldest command it kept.
	while history.can_undo():
		check_not_null(history.undo(ctx), "each remaining command inverts")
	check_eq(ctx.occupancy.occupied_count, _core_cells(), "back to the Core Module alone")


func test_clear_forgets_a_build_that_is_gone() -> void:
	var ctx := _core_only()
	var history := BuildHistory.new()
	history.attach(ctx, _candidate(ctx, DECK_CELL))
	history.clear()
	check_false(history.can_undo(), "nothing to undo")
	check_false(history.can_redo(), "and nothing to redo")
	check_eq(history.depth(), 0, "the stack is empty")


## Cycle tests catch what point tests cannot: every structure a command touches
## is maintained incrementally and none of them fails loudly. Twenty round trips
## make a one-cell or one-mount leak in any of them obvious.
func test_undo_and_redo_cycles_do_not_drift() -> void:
	var ctx := _tower()
	var history := BuildHistory.new()
	var cells := ctx.occupancy.occupied_count
	var mounts := ctx.budgets.mount_used
	var mass := ctx.graph.subtree_mass[SyndicateConstants.CORE_SLOT]

	for i in 20:
		history.remove(ctx, ctx.occupancy.slot_at(DECK_CELL))
		history.undo(ctx)
		check_eq(ctx.occupancy.occupied_count, cells, "occupancy after cycle %d" % i)
		check_eq(ctx.budgets.mount_used, mounts, "mount ledger after cycle %d" % i)
		check_approx(
			ctx.graph.subtree_mass[SyndicateConstants.CORE_SLOT],
			mass,
			"subtree mass after cycle %d" % i
		)
		check_eq(
			int(ctx.graph.parent[ctx.occupancy.slot_at(ABOVE_DECK_CELL)]),
			ctx.occupancy.slot_at(DECK_CELL),
			"and the tree after cycle %d" % i
		)


## ===== FIXTURES ========================================================


func _context() -> BuildContext:
	var ctx := BuildContext.headless(_contexts.size() + 1)
	_contexts.append(ctx)
	return ctx


func _candidate(ctx: BuildContext, cell: Vector3i) -> PlacementCandidate:
	var cand := PlacementCandidate.create(
		PartRegistry.definition_by_key(PANEL_KEY), cell, OrientationTable.IDENTITY_INDEX
	)
	var reject := PlacementValidator.validate(ctx, cand)
	if reject != PlacementValidator.Reject.NONE:
		fail("fixture: a panel at %v was refused with %d" % [cell, reject])
	return cand


## The Core Module alone, on slot 0.
func _core_only() -> BuildContext:
	var ctx := _context()
	var core := PlacementCandidate.create(
		PartRegistry.definition_by_key(CORE_KEY), CORE_CELL, OrientationTable.IDENTITY_INDEX
	)
	if PlacementValidator.validate(ctx, core) != PlacementValidator.Reject.NONE:
		fail("fixture: the Core Module was refused")
		return ctx
	PlacementValidator.commit(ctx, core)
	return ctx


## Two panels stacked on the deck. Removing the lower one cascades the upper.
func _tower() -> BuildContext:
	var ctx := _core_only()
	PlacementValidator.commit(ctx, _candidate(ctx, DECK_CELL))
	PlacementValidator.commit(ctx, _candidate(ctx, ABOVE_DECK_CELL))
	if int(ctx.graph.parent[2]) != 1:
		fail("fixture: slot 2's parent is %d, expected 1" % int(ctx.graph.parent[2]))
	return ctx


## The tower, plus a panel bridged aft off its top and a fourth below that one
## reaching the Core Module. Removing the deck panel then re-parents the bridging
## panel instead of taking it.
func _bridge() -> BuildContext:
	var ctx := _tower()
	PlacementValidator.commit(ctx, _candidate(ctx, BRIDGE_CELL))
	PlacementValidator.commit(ctx, _candidate(ctx, BESIDE_CELL))
	# The fixture only means anything if the tree came out as described.
	if int(ctx.graph.parent[3]) != 2:
		fail("fixture: slot 3's parent is %d, expected 2" % int(ctx.graph.parent[3]))
	if int(ctx.graph.parent[4]) != SyndicateConstants.CORE_SLOT:
		fail("fixture: slot 4's parent is %d, expected 0" % int(ctx.graph.parent[4]))
	return ctx


func _core_cells() -> int:
	return PartRegistry.definition_by_key(CORE_KEY).occupancy_cells.size()
