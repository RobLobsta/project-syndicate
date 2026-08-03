extends TestCase
## [Blueprint]: the form a build takes between the garage and a match, doc 02
## §9.4.
##
## The claims worth defending here are all about what a blueprint [i]cannot[/i]
## do, because that is what makes it safe to accept one from a client: it cannot
## place a part the validator would refuse, it cannot describe a build in an
## order that skips a power check, and a copy of one cannot be edited by whoever
## it was handed to.

const CORE_KEY: StringName = &"core.command.compact.t2"
const PANEL_KEY: StringName = &"str.panel.medium.t2"

const CORE_CELL := Vector3i(24, 4, 24)
## A cell nothing occupies and nothing is adjacent to.
const ORPHAN_CELL := Vector3i(12, 20, 12)

var _contexts: Array[BuildContext] = []


func after_all() -> void:
	for ctx: BuildContext in _contexts:
		ctx.dispose()
	_contexts.clear()


func _context() -> BuildContext:
	var ctx := BuildContext.headless(_contexts.size() + 1)
	_contexts.append(ctx)
	return ctx


func test_the_starter_applies_cleanly_and_reconstructs_itself() -> void:
	var ctx := _context()
	var bp := StarterBlueprint.skirmisher()
	check_eq(
		bp.apply(ctx), Blueprint.APPLIED_CLEANLY, "the shipped starter is a legal build"
	)
	check_eq(bp.size(), 12, "the starter is twelve parts")

	# The round trip is the claim a match makes when it rebuilds what the garage
	# sent: every placement, in an order that still validates.
	var round_trip := Blueprint.from_context(ctx)
	check_eq(round_trip.size(), bp.size(), "the round trip has the same part count")
	var rebuilt := _context()
	check_eq(
		round_trip.apply(rebuilt),
		Blueprint.APPLIED_CLEANLY,
		"a blueprint read back out of a context builds again"
	)
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var a := ctx.state(slot)
		var b := rebuilt.state(slot)
		if a == null and b == null:
			continue
		check_not_null(b, "slot %d exists in the rebuild" % slot)
		if b == null:
			continue
		check_eq(b.part_def_id, a.part_def_id, "slot %d holds the same part" % slot)
		check_eq(b.origin_cell, a.origin_cell, "slot %d is in the same cell" % slot)
		check_eq(
			b.orientation_index,
			a.orientation_index,
			"slot %d is in the same orientation" % slot
		)


## Doc 02 §9.4: the list is a construction sequence, not a set. The Core Module
## is first because Invariant I-2 puts it on slot 0, and the lowest free slot is
## the one [method BuildContext.allocate_slot] hands out.
func test_the_core_module_lands_on_slot_zero() -> void:
	var ctx := _context()
	StarterBlueprint.skirmisher().apply(ctx)
	var core := ctx.state(SyndicateConstants.CORE_SLOT)
	check_not_null(core, "slot 0 is occupied")
	if core == null:
		return
	check_eq(
		PartRegistry.definition(core.part_def_id).part_key,
		CORE_KEY,
		"slot 0 is the Core Module"
	)


## The refusal, which is the half that makes accepting a blueprint safe. A
## placement with nothing to mate against is refused by the identical chain the
## garage uses, and [method Blueprint.apply] reports which one.
func test_an_illegal_placement_is_refused_and_named() -> void:
	var ctx := _context()
	var bp := Blueprint.new()
	bp.add(CORE_KEY, CORE_CELL)
	bp.add(PANEL_KEY, ORPHAN_CELL)

	# A recorder object rather than a lambda writing to locals: GDScript closures
	# capture by value, so a lambda assigning to a local outside it writes to its
	# own copy and the test asserts against the value it started with.
	var log := RejectLog.new()
	check_eq(bp.apply(ctx, log.record), 1, "the second placement is the one refused")
	check_eq(log.index, 1, "the reject is reported against its own index")
	check_eq(
		log.key,
		PlacementValidator.reject_key(PlacementValidator.Reject.NO_MATING_NODE),
		"a part floating in space has nothing to attach to"
	)
	# What was committed before the refusal stays committed. A partially built
	# Assembly is inspectable and a rolled-back one is not; a caller that needs
	# all-or-nothing applies to a fresh context and throws it away.
	check_not_null(ctx.state(SyndicateConstants.CORE_SLOT), "the Core Module is still there")


## A part key the registry does not hold is doc 01 §14's manifest mismatch, and
## it is reported as its own reason rather than as one of the geometric ones.
func test_an_unknown_part_is_its_own_reason() -> void:
	var ctx := _context()
	var bp := Blueprint.new()
	bp.add(&"core.command.does_not_exist.t9", CORE_CELL)
	var log := RejectLog.new()
	check_eq(bp.apply(ctx, log.record), 0, "the first placement is refused")
	check_eq(log.key, Blueprint.KEY_UNKNOWN_PART, "an unknown key is named as one")


## Doc 02 §9.4: the list is a construction sequence and the order is content.
## Placement [i]n[/i] mates against what the first [i]n[/i] built, so a part that
## hangs off a station placed before the station has nothing to attach to — the
## same three parts, in the other order, are a different answer.
func test_order_is_content_and_not_presentation() -> void:
	var station_first := _context()
	var contact_first := _context()

	var ordered := Blueprint.new()
	ordered.add(CORE_KEY, StarterBlueprint.CORE_CELL)
	ordered.add(StarterBlueprint.HUB_KEY, StarterBlueprint.HUB_CELLS[0])
	ordered.add(
		StarterBlueprint.WHEEL_KEY,
		StarterBlueprint.CONTACT_CELLS[0],
		OrientationTable.upright_facing(Vector3.RIGHT)
	)
	check_eq(
		ordered.apply(station_first),
		Blueprint.APPLIED_CLEANLY,
		"a station before what hangs off it is a legal sequence"
	)

	var inverted := Blueprint.new()
	inverted.add(CORE_KEY, StarterBlueprint.CORE_CELL)
	inverted.add(
		StarterBlueprint.WHEEL_KEY,
		StarterBlueprint.CONTACT_CELLS[0],
		OrientationTable.upright_facing(Vector3.RIGHT)
	)
	inverted.add(StarterBlueprint.HUB_KEY, StarterBlueprint.HUB_CELLS[0])
	var log := RejectLog.new()
	check_eq(
		inverted.apply(contact_first, log.record),
		1,
		"the same three parts in the other order are refused at the contact"
	)
	check_eq(
		log.key,
		PlacementValidator.reject_key(PlacementValidator.Reject.NO_MATING_NODE),
		"because the station it mates through is not there yet"
	)


## A copy is independent. [ShellRoot] holds one blueprint for a whole session and
## hands it to a match; a match that edited the object it was given would be
## editing the build the garage is still holding.
func test_a_copy_is_independent() -> void:
	var original := StarterBlueprint.skirmisher()
	var copy := original.copy()
	copy.placements[0].origin_cell = ORPHAN_CELL
	copy.add(PANEL_KEY, ORPHAN_CELL)
	check_eq(
		original.placements[0].origin_cell,
		StarterBlueprint.CORE_CELL,
		"editing a copy's placement does not move the original's"
	)
	check_eq(original.size(), 12, "and appending to a copy does not lengthen the original")


func test_an_empty_blueprint_is_empty() -> void:
	var bp := Blueprint.new()
	check_true(bp.is_empty(), "a new blueprint holds nothing")
	check_eq(bp.size(), 0, "and its size says so")
	var ctx := _context()
	check_eq(
		bp.apply(ctx), Blueprint.APPLIED_CLEANLY, "applying nothing refuses nothing"
	)
	check_true(ctx.is_empty(), "and commits nothing")


## What [method Blueprint.apply] reported, and to whom.
class RejectLog:
	extends RefCounted

	var index: int = -1
	var key: StringName = &""

	func record(placement_index: int, reason_key: StringName) -> void:
		index = placement_index
		key = reason_key
