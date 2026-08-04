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
## On the Core Module's deck.
const DECK_CELL := Vector3i(24, 7, 24)
## Beside it, bridging to the deck's aft edge and to the panel above.
const BESIDE_DECK_CELL := Vector3i(24, 7, 28)
## Directly on top of that one, and touching nothing else.
const ABOVE_BESIDE_CELL := Vector3i(24, 8, 28)

## Recoil impulse, in N·s, above which an Effector Module has no business being
## on the build a player is handed. Doc 01 §10.5.
##
## Chosen to sit above `eff.ballistic.repeater_12.t2`'s 26 with room for a
## rebalance and far below `eff.ballistic.autocannon_20.t2`'s 980, which is the
## next lightest row in the table — so it separates "a module that can be fired
## from a moving hull" from "every other direct-fire row published", and does not
## pin the shipped figure.
const STARTER_RECOIL_CEILING_NS: float = 120.0

var _contexts: Array[BuildContext] = []


func after_all() -> void:
	for ctx: BuildContext in _contexts:
		ctx.dispose()
	_contexts.clear()


func _context() -> BuildContext:
	var ctx := BuildContext.headless(_contexts.size() + 1)
	_contexts.append(ctx)
	return ctx


## Places [param key] at [param cell] and returns its slot, failing the test
## rather than returning a slot nothing is in if the fixture does not build.
func _commit(ctx: BuildContext, key: StringName, cell: Vector3i) -> int:
	var def := PartRegistry.definition_by_key(key)
	var cand := PlacementCandidate.create(def, cell, OrientationTable.IDENTITY_INDEX)
	var reject := PlacementValidator.validate(ctx, cand)
	if reject != PlacementValidator.Reject.NONE:
		fail("fixture: '%s' at %v was refused with %d" % [key, cell, reject])
		return SyndicateConstants.INVALID_SLOT
	return PlacementValidator.commit(ctx, cand)


func test_the_starter_carries_a_module_its_own_chassis_can_fire_while_moving() -> void:
	# The rule the shipped starter has to keep, stated where it can fail.
	#
	# Doc 07 §8 applies the recoil at the muzzle, so a mount traversed across the
	# hull yaws it by `impulse × lever ÷ I_yy`, and the build a player is *handed*
	# is the one build in the project that has to be drivable before they know
	# what any of that means. `tests/physics/test_drive_and_shoot.gd` measures the
	# consequence on real contacts and costs seconds of simulation; this asserts
	# the authored precondition and costs a dictionary lookup, so a starter
	# quietly re-armed with a heavier row fails here first and legibly.
	#
	# The ceiling is stated by value rather than read off a row. A test that
	# imported the module's own figure would move with it and assert nothing,
	# which is `LEARNED_FACTS.md` §2's oldest lesson.
	var def := PartRegistry.definition_by_key(StarterBlueprint.EFFECTOR_KEY)
	if not check_not_null(def, "the starter's Effector Module is in the registry"):
		return
	check_eq(
		def.part_class,
		PartEnums.PartClass.EFFECTOR_MODULE,
		"and it is an Effector Module"
	)
	check_true(
		def.effector_profile.recoil_impulse_ns <= STARTER_RECOIL_CEILING_NS,
		(
			"'%s' recoils at %.0f N·s against a ceiling of %.0f"
			% [
				def.part_key,
				def.effector_profile.recoil_impulse_ns,
				STARTER_RECOIL_CEILING_NS
			]
		)
	)
	# And the ceiling separates something, which is the half a bound cannot
	# assert about itself. A threshold raised past every published row keeps the
	# check above green forever — a fault sweep planted exactly that and nothing
	# noticed — so the catalogue's heaviest direct-fire module is asserted to be
	# on the other side of it.
	var heavy := PartRegistry.definition_by_key(&"eff.ballistic.autocannon_30.t3")
	if not check_not_null(heavy, "the heavy direct-fire row is in the registry"):
		return
	check_true(
		heavy.effector_profile.recoil_impulse_ns > STARTER_RECOIL_CEILING_NS,
		(
			"and the ceiling is one a heavy module fails: '%s' at %.0f N·s"
			% [heavy.part_key, heavy.effector_profile.recoil_impulse_ns]
		)
	)


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


## The order [method Blueprint.from_context] writes is a construction order even
## when ascending slot order is not one, and the difference is one ordinary
## garage session away.
##
## [method BuildContext.allocate_slot] hands out the lowest free slot, so a
## removal leaves a hole and the next placement drops into it whatever that
## placement attaches to. Take a part off the deck, put one on top of its
## neighbour, and the child is now slot 1 while the thing holding it up is slot
## 2 — at which point ascending order describes a build that cannot be built.
## What the player sees is a test drive that arrives one part short, or does not
## arrive, with nothing on the screen having gone wrong.
##
## Asserted through [method Blueprint.apply] rather than by reading the order,
## because the property is "this reconstructs" and not "this is sorted".
func test_a_build_edited_into_a_slot_hole_still_reconstructs() -> void:
	var ctx := _context()
	_commit(ctx, CORE_KEY, CORE_CELL)
	var removed := _commit(ctx, PANEL_KEY, DECK_CELL)
	var support := _commit(ctx, PANEL_KEY, BESIDE_DECK_CELL)
	check_eq(removed, 1, "the panel on the deck took slot 1")
	check_eq(support, 2, "and the one beside it took slot 2")

	check_eq(
		PlacementValidator.remove(ctx, removed),
		PackedByteArray(),
		"removing the first panel takes nothing with it"
	)
	var child := _commit(ctx, PANEL_KEY, ABOVE_BESIDE_CELL)
	check_eq(child, 1, "the new panel drops into the hole the removal left")
	check_eq(int(ctx.graph.parent[child]), support, "and rests on slot 2")

	# The claim: the blueprint that comes out of that context builds again. In
	# ascending slot order it does not — placement 1 is the child and placement 2
	# is what holds it up.
	var bp := Blueprint.from_context(ctx)
	check_eq(bp.size(), 3, "the Core Module, the survivor, and the part on top of it")
	var log := RejectLog.new()
	var rebuilt := _context()
	check_eq(
		bp.apply(rebuilt, log.record),
		Blueprint.APPLIED_CLEANLY,
		"and every one of them is accepted in the order it was written"
	)
	check_eq(
		rebuilt.occupancy.occupied_count,
		ctx.occupancy.occupied_count,
		"the rebuild occupies the same cells"
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
