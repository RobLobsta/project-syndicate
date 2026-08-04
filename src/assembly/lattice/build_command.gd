class_name BuildCommand
extends RefCounted
## One reversible garage edit, owned by [code]docs/GRID_SNAPPING_LOGIC.md[/code]
## §9.3.
##
## A command is created [i]by performing[/i] the edit — [method attach] commits
## and [method remove] removes — because the state a command needs in order to
## invert itself is the state the edit destroys. A record built by the caller
## before or after the fact is a second description of what happened, and the two
## drift the first time the cascade rule changes.
##
## [b]It identifies a part by the cell it sits on, never by its slot.[/b]
## [method BuildContext.allocate_slot] hands out the lowest free slot, so a part
## put back after two removals lands in whichever hole is lowest rather than in
## the one it came out of — restore the two in the other order and every slot id
## in the stack below points at the wrong part. A cell does not move: the pivot
## cell is inside the part's own footprint by construction, so
## [method LatticeOccupancy.slot_at] answers with whatever slot is holding that
## part now. Invariant I-6 says placement is integer arithmetic over the lattice;
## this is the same statement about identity.
##
## Undo is therefore exact rather than approximate. Every field below is an
## integer or a lattice cell, so a part restored a hundred commands later comes
## back in the same cell at the same orientation under the same parent, with no
## float drift between the original placement and its restoration.

## What the edit did. The garage produces both; doc §9.3's [code]REPAINT[/code]
## and [code]REORIENT[/code] arrive with the operations that produce them — there
## is no tint editor and no in-place reorient, and a kind nothing can create is a
## branch nothing can reach.
enum Kind { ATTACH, REMOVE }

## Stands in for "this part has no parent", which is true of the Core Module and
## of nothing else (Invariant I-2). Outside the lattice on every axis, so no real
## placement can collide with it.
const NO_PARENT_CELL: Vector3i = Vector3i(-1, -1, -1)

## One part, as much of it as putting it back requires. Declared before the
## members that name it, as [code]Blueprint.Placement[/code] is.
class Placed:
	extends RefCounted

	var part_def_id: int = -1
	var origin_cell: Vector3i = Vector3i.ZERO
	var orientation_index: int = OrientationTable.IDENTITY_INDEX
	## Pivot cell of its primary parent, or [constant NO_PARENT_CELL].
	var parent_cell: Vector3i = Vector3i.ZERO


## A part that survived a removal but changed parents because of it. §9.2
## re-parents an orphan onto whatever it still rests on; undoing the removal has
## to put that link back, or the Chassis Graph comes out of an undo describing a
## different tree from the one that went into the removal.
class Reparent:
	extends RefCounted

	var cell: Vector3i = Vector3i.ZERO
	var prior_parent_cell: Vector3i = Vector3i.ZERO


var kind: Kind = Kind.ATTACH
## Every part this command put on the lattice ([constant Kind.ATTACH], exactly
## one) or took off it ([constant Kind.REMOVE], the part named and its cascade).
##
## In the order the lattice saw them, which for a cascade is breadth-first from
## the part that was removed — so a parent always precedes its children and
## restoring the list in order needs no sort.
var placements: Array[Placed] = []
## Survivors §9.2 re-parented. Empty for an attach.
var reparents: Array[Reparent] = []


## Commits [param cand] and returns the command that inverts it, or null when the
## commit was refused.
##
## [param cand] must already have validated: [method PlacementValidator.commit]
## asserts it, and this function does not re-run the chain because the caller has
## just run it to decide whether to offer the placement at all.
static func attach(ctx: BuildContext, cand: PlacementCandidate) -> BuildCommand:
	var slot := PlacementValidator.commit(ctx, cand)
	if slot == SyndicateConstants.INVALID_SLOT:
		return null
	var cmd := BuildCommand.new()
	cmd.kind = Kind.ATTACH
	cmd.placements.append(_record(ctx, slot))
	return cmd


## Removes [param slot] through §9.2 and returns the command that inverts it, or
## null when the slot was already empty.
##
## The snapshot is taken before the removal because that is the only moment the
## information exists: [method PlacementValidator.remove] reports which slots
## cascaded, and by then their states are gone.
static func remove(ctx: BuildContext, slot: int) -> BuildCommand:
	if ctx.state(slot) == null:
		return null

	var before: Array[Placed] = []
	before.resize(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY)
	for s in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		before[s] = _record(ctx, s) if ctx.state(s) != null else null

	var cascaded := PlacementValidator.remove(ctx, slot)

	var cmd := BuildCommand.new()
	cmd.kind = Kind.REMOVE
	cmd.placements.append(before[slot])
	for s in cascaded:
		cmd.placements.append(before[int(s)])

	# Everything still standing whose primary parent moved. Ascending by slot, so
	# the record is the same for the same removal however the graph is laid out
	# (Invariant I-9).
	for s in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var was: Placed = before[s]
		if was == null or ctx.state(s) == null:
			continue
		var now := _parent_cell_of(ctx, s)
		if now == was.parent_cell:
			continue
		var moved := Reparent.new()
		moved.cell = was.origin_cell
		moved.prior_parent_cell = was.parent_cell
		cmd.reparents.append(moved)
	return cmd


## Parts this command removed beyond the one the player named. Zero for an
## attach. This is the figure doc 11 §9.1 wants in the status strip after the
## fact; the confirmation before it counts dependents, which is a different
## question and a larger number.
func cascade_size() -> int:
	return 0 if kind == Kind.ATTACH else placements.size() - 1


## Puts the build back the way it was before this command ran.
func undo(ctx: BuildContext) -> bool:
	if kind == Kind.ATTACH:
		var cascade := _erase(ctx)
		# Undo is last-in-first-out, so nothing can have been built on this part
		# since it was placed — anything that was is already undone. A cascade
		# here means the stack was applied out of order.
		assert(cascade.is_empty(), "undo of an attach cascaded %d parts" % cascade.size())
		return true
	return _restore(ctx)


## Runs this command again, over a build that is in the state it was in before
## the command first ran.
func redo(ctx: BuildContext) -> bool:
	if kind == Kind.ATTACH:
		return _restore(ctx)
	# The cascade is not replayed from the record: re-running the removal
	# reproduces it through the same §9.2 code that produced it the first time,
	# which is deterministic over an identical build. Replaying a stored list
	# would be a second implementation of the cascade rule.
	_erase(ctx)
	return true


## ===== PRIVATE =========================================================


## Commits every part in [member placements], in order, and puts each one back
## under the parent it had.
##
## Order is enough: a cascade is recorded breadth-first from the part that was
## removed, so a part's recorded parent is either a survivor or an earlier entry
## in the list, and by the time it is committed the parent is on the lattice.
func _restore(ctx: BuildContext) -> bool:
	for p: Placed in placements:
		var def := PartRegistry.definition(p.part_def_id)
		if def == null:
			push_error("BuildCommand: undo cannot resolve part id %d" % p.part_def_id)
			return false
		var cand := PlacementCandidate.create(def, p.origin_cell, p.orientation_index)
		var reject := PlacementValidator.validate(ctx, cand)
		if reject != PlacementValidator.Reject.NONE:
			# The build is exactly what it was when the part came off, so a
			# refusal here is a defect in this class rather than a placement the
			# player should be told about.
			push_error(
				(
					"BuildCommand: restoring '%s' at %v was refused: %s"
					% [def.part_key, p.origin_cell, PlacementValidator.reject_key(reject)]
				)
			)
			return false
		var slot := PlacementValidator.commit(ctx, cand)
		if slot == SyndicateConstants.INVALID_SLOT:
			return false
		_set_parent(ctx, slot, p.parent_cell)

	for r: Reparent in reparents:
		_set_parent(ctx, ctx.occupancy.slot_at(r.cell), r.prior_parent_cell)
	return true


## Removes the part this command's first placement describes, and returns
## whatever came with it.
func _erase(ctx: BuildContext) -> PackedByteArray:
	var slot := ctx.occupancy.slot_at(placements[0].origin_cell)
	if slot == SyndicateConstants.INVALID_SLOT:
		push_error("BuildCommand: nothing occupies %v" % placements[0].origin_cell)
		return PackedByteArray()
	return PlacementValidator.remove(ctx, slot)


## Moves [param slot] back under the part occupying [param parent_cell].
##
## The graph and the instance state are written together: [ChassisGraph] carries
## the tree the strain model walks and [member PartInstanceState.parent_slot] is
## what a blueprint and a snapshot read, and a build in which the two disagree
## has no single answer to "what holds this up".
static func _set_parent(ctx: BuildContext, slot: int, parent_cell: Vector3i) -> void:
	if slot == SyndicateConstants.INVALID_SLOT or parent_cell == NO_PARENT_CELL:
		return
	var parent := ctx.occupancy.slot_at(parent_cell)
	if parent == SyndicateConstants.INVALID_SLOT or int(ctx.graph.parent[slot]) == parent:
		return
	ctx.graph.reparent(slot, parent)
	ctx.states[slot].parent_slot = parent


static func _record(ctx: BuildContext, slot: int) -> Placed:
	var st := ctx.state(slot)
	var out := Placed.new()
	out.part_def_id = st.part_def_id
	out.origin_cell = st.origin_cell
	out.orientation_index = st.orientation_index
	out.parent_cell = _parent_cell_of(ctx, slot)
	return out


static func _parent_cell_of(ctx: BuildContext, slot: int) -> Vector3i:
	var parent := ctx.state(slot).parent_slot
	var parent_state := ctx.state(parent)
	return NO_PARENT_CELL if parent_state == null else parent_state.origin_cell
