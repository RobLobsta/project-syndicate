class_name BuildHistory
extends RefCounted
## The garage's command stack, owned by [code]docs/GRID_SNAPPING_LOGIC.md[/code]
## §9.3.
##
## Every edit a player makes goes through here rather than through
## [PlacementValidator] directly, and that is the whole of the class: it performs
## the edit by asking [BuildCommand] to perform it, keeps the command that
## inverts it, and hands the inverse back on demand. Nothing else in the garage
## knows how an edit is undone.
##
## [b]A redo branch does not survive a new edit.[/b] Place a part, undo it, place
## a different one, and the first is gone for good — there is one history, not a
## tree. That is what every editor does and what a player expects; the
## alternative is a redo that puts back something they replaced on purpose.
##
## [b]The stack is bounded and the bound is not a memory limit.[/b] A command is
## a handful of integers and a hundred and twenty-eight of them cost nothing.
## What the bound buys is a promise the class can keep: an undo restores the
## build exactly, and the further back a command is the more of the build has
## been rearranged around it. §9.3 fixes the depth at 128 and this is the only
## place it is written down.

## §9.3's undo depth. Commands older than this leave the bottom of the stack.
const MAX_DEPTH: int = 128

var _undo: Array[BuildCommand] = []
var _redo: Array[BuildCommand] = []


## Commits [param cand], and doc 02 §10's [param mirror] alongside it where one
## is given, as a single undoable edit. Returns the command, or null when the
## placement was refused.
##
## The mirror is validated here rather than by the caller, because §10's rule is
## that a refused mirror is skipped and the primary still commits — so whether
## there is a second placement is an answer this function has to have before it
## can record what it did.
func attach(
	ctx: BuildContext, cand: PlacementCandidate, mirror: PlacementCandidate = null
) -> BuildCommand:
	var extra := mirror
	if extra != null and PlacementValidator.validate(ctx, extra) != PlacementValidator.Reject.NONE:
		extra = null
	var cmd := BuildCommand.attach(ctx, cand, extra)
	if cmd == null:
		return null
	_push(cmd)
	return cmd


## Removes [param slot] through §9.2 and records it. Returns the command, so the
## caller can report what came with it, or null when the slot was already empty.
func remove(ctx: BuildContext, slot: int) -> BuildCommand:
	var cmd := BuildCommand.remove(ctx, slot)
	if cmd == null:
		return null
	_push(cmd)
	return cmd


## Inverts the most recent edit. Returns the command that was undone, or null
## when there is nothing left to undo.
func undo(ctx: BuildContext) -> BuildCommand:
	if _undo.is_empty():
		return null
	var cmd: BuildCommand = _undo.pop_back()
	if not cmd.undo(ctx):
		# The command has already reported what it could not put back. Keeping it
		# out of both stacks is the conservative answer: a command that half
		# inverted describes a build that no longer exists, and redoing it would
		# apply the other half to the wrong one.
		return null
	_redo.push_back(cmd)
	return cmd


## Re-applies the most recently undone edit. Returns the command, or null when
## there is nothing to redo.
func redo(ctx: BuildContext) -> BuildCommand:
	if _redo.is_empty():
		return null
	var cmd: BuildCommand = _redo.pop_back()
	if not cmd.redo(ctx):
		return null
	_undo.push_back(cmd)
	return cmd


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Commands available to [method undo]. Never above [constant MAX_DEPTH].
func depth() -> int:
	return _undo.size()


## Commands available to [method redo].
func redo_depth() -> int:
	return _redo.size()


## Forgets everything. Called when the build is replaced wholesale rather than
## edited — a reset, or a blueprint loaded over the top — because a command
## stack whose commands describe cells belonging to a build that is gone is a
## stack that would undo into somebody else's Assembly.
func clear() -> void:
	_undo.clear()
	_redo.clear()


func _push(cmd: BuildCommand) -> void:
	_redo.clear()
	_undo.push_back(cmd)
	if _undo.size() > MAX_DEPTH:
		_undo.remove_at(0)
