class_name Blueprint
extends RefCounted
## An ordered list of placements that reconstructs one Assembly, owned by
## [code]docs/GRID_SNAPPING_LOGIC.md[/code] §9.4.
##
## It is the form a build takes between the place that made it and the place
## that uses it: the garage hands one to the match, doc 06's auto-assembler
## produces one, and doc 12 §4.3's [code]BlueprintCodec[/code] is this object on
## the wire. Every one of those goes back through [PlacementValidator] to become
## an Assembly, which is CLAUDE.md §10 rule 9 — there is no second path into the
## lattice, and a blueprint therefore cannot describe a build the garage would
## have refused.
##
## [b]Order is the whole content.[/b] Placement [i]n[/i] mates against what the
## first [i]n[/i] placements built, so the list is a construction sequence rather
## than a set. The Core Module is first because Invariant I-2 puts it on slot 0
## and [method BuildContext.allocate_slot] hands out the lowest free slot; a
## station goes down before what hangs off it; and doc 05 §7.4's power budget is
## checked against what the context holds at that moment, so an Energy Cell
## precedes the draw it covers. That is the same order a player has to build in.
##
## [b]It stores part keys, not runtime ids.[/b] A [code]part_def_id[/code] is an
## index into the manifest and is the right thing on the wire, where the manifest
## hash is checked first (doc 12 §4.2). In memory a key survives a registry that
## has grown a part since, and it is what a reader of a stack trace can look up.

## One placement. A plain record: these are constructed in the hundreds when a
## catalogue of blueprints is loaded and carry no behaviour of their own.
class Placement:
	extends RefCounted

	var part_key: StringName = &""
	var origin_cell: Vector3i = Vector3i.ZERO
	var orientation_index: int = OrientationTable.IDENTITY_INDEX

	func _init(
		key: StringName = &"",
		cell: Vector3i = Vector3i.ZERO,
		orientation: int = OrientationTable.IDENTITY_INDEX
	) -> void:
		part_key = key
		origin_cell = cell
		orientation_index = orientation

	func copy() -> Placement:
		return Placement.new(part_key, origin_cell, orientation_index)


## Returned by [method apply] for a blueprint every placement of which was
## accepted. Anything else is the index of the placement that was refused.
const APPLIED_CLEANLY: int = -1

## Reason key for a placement naming a part the registry does not hold. Doc 01
## §14's manifest mismatch, seen from the loading end.
const KEY_UNKNOWN_PART: StringName = &"build.reject.unknown_part"

## The construction sequence, in order.
var placements: Array[Placement] = []


## Appends a placement. Returns the blueprint so a build can be written as a
## chain.
func add(
	part_key: StringName,
	origin_cell: Vector3i,
	orientation_index: int = OrientationTable.IDENTITY_INDEX
) -> Blueprint:
	placements.append(Placement.new(part_key, origin_cell, orientation_index))
	return self


func size() -> int:
	return placements.size()


func is_empty() -> bool:
	return placements.is_empty()


## An independent copy. The shell holds one blueprint across a whole session and
## hands it to the match; a match that mutated the object it was given would edit
## the player's build from inside the fight.
func copy() -> Blueprint:
	var out := Blueprint.new()
	for p: Placement in placements:
		out.placements.append(p.copy())
	return out


## Commits every placement into [param ctx] through the ordinary validation
## chain.
##
## Returns [constant APPLIED_CLEANLY], or the index of the first placement that
## was refused — at which point the context holds everything before it and
## nothing after, because a partially built Assembly is inspectable and a rolled
## back one is not. A caller that needs all-or-nothing applies to a fresh context
## and throws it away.
##
## [param on_reject] receives the placement index and a localisation key naming
## the reason. It is how the garage reports "that Energy Cell no longer covers
## your rotor discs" against the part that stopped being legal, rather than as a
## build that silently came back one part short.
##
## A key rather than a [enum PlacementValidator.Reject] value, because one of the
## reasons is not a rejection: a part key the registry does not hold is doc 01
## §14's manifest mismatch, and widening the frozen reject enum to carry it would
## put a data-version problem into a table doc 02 §12 asserts is about geometry.
func apply(ctx: BuildContext, on_reject: Callable = Callable()) -> int:
	for i: int in placements.size():
		var p: Placement = placements[i]
		var def := PartRegistry.definition_by_key(p.part_key)
		if def == null:
			# A warning rather than an error: doc 01 §14 makes this a manifest
			# mismatch, which is a data-version problem a caller can act on — and
			# the caller is told twice, by the reason key and by the return.
			push_warning("Blueprint: placement %d names unknown part '%s'" % [i, p.part_key])
			if on_reject.is_valid():
				on_reject.call(i, KEY_UNKNOWN_PART)
			return i
		var candidate := PlacementCandidate.create(def, p.origin_cell, p.orientation_index)
		var reject := PlacementValidator.validate(ctx, candidate)
		if reject != PlacementValidator.Reject.NONE:
			if on_reject.is_valid():
				on_reject.call(i, PlacementValidator.reject_key(reject))
			return i
		PlacementValidator.commit(ctx, candidate)
	return APPLIED_CLEANLY


## The blueprint that reconstructs [param ctx]: the lowest slot whose parent has
## already been written, over and over until the build is spent.
##
## [b]Slot order alone is not a construction order, and it took a removal to show
## it.[/b] [method BuildContext.allocate_slot] hands out the lowest free slot, so
## on a build that has only ever grown a parent's slot is lower than its child's
## and ascending order is exactly the order the player built in. Remove a part
## from the middle and the hole is handed to the next placement whatever it
## attaches to — put a part on slot 9 while slot 3 is free and the child is
## written as placement 3 and its parent as placement 9. [method apply] then
## refuses the child for having nothing to attach to, and a player who edited
## their build in the ordinary way loses it at the screen boundary.
##
## Taking the lowest [i]eligible[/i] slot each time is the smallest repair that
## closes it: on a build where ascending order is already legal — which is every
## build that has not been edited, including every shipped starter — this emits
## the identical list, so it is not a new ordering so much as the old one with
## its premise checked. Deterministic by construction (Invariant I-9): the choice
## at every step is the lowest slot that can legally go next.
##
## The parent link is the primary tree's, so a part's parent is one of the
## neighbours it mates with. It is sufficient rather than necessary — doc 02
## §7.3 accepts a placement with any legal mate, not specifically its recorded
## parent — and sufficiency is what a reconstruction needs.
static func from_context(ctx: BuildContext) -> Blueprint:
	var out := Blueprint.new()
	var written := PackedByteArray()
	written.resize(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY)
	written.fill(0)

	var remaining := 0
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		if ctx.state(slot) != null:
			remaining += 1

	while remaining > 0:
		var next := _lowest_writable(ctx, written)
		if next == SyndicateConstants.INVALID_SLOT:
			# Every remaining part is held up by something already released, which
			# the graph cannot produce: a live slot's parent is live.
			push_error("Blueprint: %d parts in assembly %d have no writable order"
				% [remaining, ctx.assembly_id])
			return out
		var st := ctx.state(next)
		written[next] = 1
		remaining -= 1
		var def := PartRegistry.definition(st.part_def_id)
		if def == null:
			push_error("Blueprint: slot %d holds unknown part id %d" % [next, st.part_def_id])
			continue
		out.add(def.part_key, st.origin_cell, st.orientation_index)
	return out


## The lowest occupied slot not yet written whose primary parent has been, or
## [constant SyndicateConstants.INVALID_SLOT] when there is none.
static func _lowest_writable(ctx: BuildContext, written: PackedByteArray) -> int:
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var st := ctx.state(slot)
		if st == null or written[slot] == 1:
			continue
		var parent := st.parent_slot
		if parent == SyndicateConstants.INVALID_SLOT or written[parent] == 1:
			return slot
	return SyndicateConstants.INVALID_SLOT
