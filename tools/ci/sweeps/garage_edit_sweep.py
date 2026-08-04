#!/usr/bin/env python3
"""Fault sweep over doc 02 §9's editing model: undo, removal, and reconstruction.

Eleven faults over the code session 27 added or repaired — the command stack, the
inversion of an attach and of a removal, the cascade's announcement, the order a
context is written back out in, and the ordering invariant the Chassis Graph
declares about its own children.

  attach-undo-does-nothing      §9.3: undo of a placement leaves it placed
  restore-loses-the-parent      §9.3: a part comes back under whatever mates
  restore-ignores-reparents     §9.2's re-parenting is not put back
  restore-in-reverse            the cascade comes back child before parent
  redo-branch-survives-an-edit  §9.3: one history, not a tree
  stack-is-unbounded            §9.3's 128 removed
  undo-pushes-nothing-to-redo   an undone command that cannot be redone
  cascade-announced-once        doc 04 §8: one part_removed for a whole cascade
  cascade-announces-only-others the named part left unannounced
  from-context-ascending        §9.4: slot order assumed to be build order
  children-appended             doc 04: `children` claims to be ascending

**Three of these are the session's own repairs, planted back in.** `from-context-
ascending` and `cascade-announced-once` were the shipped behaviour until this
session, and `children-appended` was the shipped behaviour since the graph was
written; each is here so the assertion that now covers it is proved to cover it
rather than merely to exist. If one of those three survives, the repair is
untested and the finding is worth more than the fix.

One fault that belongs here is not here: **a command keyed on a slot rather than
on a cell** cannot be planted by substituting one line, because the record has no
slot field to read. It is the design the obvious implementation reaches for and
it is correct for every single-removal case, diverging only once two removals are
undone through each other's holes. It was verified by hand instead — see
CHANGE_LOG.md — and `test_two_removals_undo_through_each_other_s_holes` is the
one fixture that can see it.

    python3 tools/ci/sweeps/garage_edit_sweep.py            # all of them, 4 workers
    python3 tools/ci/sweeps/garage_edit_sweep.py --list
    python3 tools/ci/sweeps/garage_edit_sweep.py -j1 --full restore-in-reverse

The loop, the parallelism, the timeout and the fail-fast rule all live in
`sweeplib.py`; read that before changing how this runs. Update BASELINE in the
same change as anything that moves the check count, or every fault after it
reads as caught.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sweeplib

COMMAND = "src/assembly/lattice/build_command.gd"
HISTORY = "src/assembly/lattice/build_history.gd"
VALIDATOR = "src/assembly/lattice/placement_validator.gd"
BLUEPRINT = "src/assembly/lattice/blueprint.gd"
GRAPH = "src/assembly/graph/chassis_graph.gd"

BASELINE = 5874

FAULTS = [
    # The inversion of an attach, gone. The stack still reports the command it
    # undid, so every count in the interface agrees and the part is still there.
    ("attach-undo-does-nothing", COMMAND,
     "	if kind == Kind.ATTACH:\n		var cascade := _erase(ctx)",
     "	if kind == Kind.ATTACH:\n		var cascade := PackedByteArray()"),

    # A restored part keeps whatever parent the mate selector picks for it now,
    # which is a legal tree and is not the one the player had. Nothing about the
    # build's geometry changes, so only an assertion on the tree can see it.
    ("restore-loses-the-parent", COMMAND,
     "	if slot == SyndicateConstants.INVALID_SLOT or parent_cell == NO_PARENT_CELL:\n		return",
     "	if true:\n		return"),

    # §9.2's re-parenting of a survivor is not recorded, so the survivor stays
    # hanging off the neighbour the removal moved it to.
    ("restore-ignores-reparents", COMMAND,
     "		cmd.reparents.append(moved)",
     "		pass"),

    # The cascade recorded child first, so the restore puts a part back before
    # the thing it rests on. Every placement but the first then has nothing to
    # mate with — a refusal rather than a wrong build, but one that `_restore`
    # reports and the interface does not.
    ("restore-in-reverse", COMMAND,
     "	cmd.placements.append(before[slot])\n	for s in cascaded:\n"
     "		cmd.placements.append(before[int(s)])",
     "	for s in cascaded:\n		cmd.placements.append(before[int(s)])\n"
     "	cmd.placements.append(before[slot])"),

    # A redo branch that survives the next edit, so redo puts back the part the
    # player replaced on purpose.
    ("redo-branch-survives-an-edit", HISTORY,
     "func _push(cmd: BuildCommand) -> void:\n	_redo.clear()",
     "func _push(cmd: BuildCommand) -> void:"),

    # §9.3's depth, removed. Nothing fails immediately; the stack simply grows
    # for as long as the garage is open.
    ("stack-is-unbounded", HISTORY,
     "	if _undo.size() > MAX_DEPTH:\n		_undo.remove_at(0)",
     "	if false:\n		_undo.remove_at(0)"),

    # An undo that inverts correctly and leaves nothing to redo. The build is
    # right after every single operation, which is what makes it survivable.
    ("undo-pushes-nothing-to-redo", HISTORY,
     "	_redo.push_back(cmd)\n	return cmd",
     "	return cmd"),

    # Doc 04 §8's contract, as it was shipped: one emission per call rather than
    # one per part. The build is correct and the garage draws meshes belonging to
    # parts that are gone.
    ("cascade-announced-once", VALIDATOR,
     "	for s in cascaded:\n		EventBus.part_removed.emit(ctx.assembly_id, int(s))",
     "	pass"),

    # The other half, in the other direction: the cascade announced and the part
    # the player actually clicked left out.
    ("cascade-announces-only-others", VALIDATOR,
     "	EventBus.part_removed.emit(ctx.assembly_id, slot)\n	for s in cascaded:",
     "	for s in cascaded:"),

    # §9.4 as it was shipped: ascending slot order assumed to be a construction
    # order. True of a build that has only ever grown, false the moment a removal
    # leaves a hole for a later placement to drop into.
    ("from-context-ascending", BLUEPRINT,
     "		if parent == SyndicateConstants.INVALID_SLOT or written[parent] == 1:\n			return slot",
     "		if true:\n			return slot"),

    # `children` appended rather than filed. It has said "ascending" since the
    # graph was written and was not, which makes `subtree_slots` a function of
    # edit history rather than of the tree.
    ("children-appended", GRAPH,
     "	var at := 0\n	while at < kids.size() and int(kids[at]) < slot:\n		at += 1",
     "	var at := kids.size()"),
]


if __name__ == "__main__":
    raise SystemExit(sweeplib.run_sweep(FAULTS, BASELINE, __doc__))
