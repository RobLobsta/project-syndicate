class_name MassRecomputeScheduler
extends Node
## Turns the five structural events of
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §4.1 into at most one mass solve per
## Assembly per tick, off the main thread, applied at a tick boundary.
##
## §4.1: mass properties are recomputed on part attach, part removal, part
## destruction, island detachment, and a consumable-mass step — and on nothing
## else. There is no per-frame recomputation, and a match in which nothing breaks
## costs this node one dictionary emptiness test per tick.
##
## §4.2's quantisation is what makes the last of those five tractable: ammunition
## drains continuously, so it is banked into 8 kg steps and only a crossing emits
## [signal EventBusService.consumable_mass_step]. A 240 kg magazine causes thirty
## recomputes over minutes rather than one per shot.
##
## [b]Amendment to §4.3.[/b] The document's scheduler does its work in
## [code]_physics_process[/code] and picks up a finished task on whichever later
## tick happens to notice it. Two changes:
##
## 1. It runs on [signal MatchClockService.tick_started] rather than on a raw
##    [code]_physics_process[/code]. §11 invariant 4 requires the result to land
##    at the [i]start[/i] of a tick, and a bare [code]_physics_process[/code]
##    cannot promise that — its position among the other physics callbacks is
##    scene-tree construction order, so the motion system could read last tick's
##    mass for a whole tick. [code]MatchClock[/code] sets
##    [code]process_physics_priority = -1000[/code] and is by definition first.
## 2. The task is joined on the next tick unconditionally rather than polled for
##    completion. A 255-part solve costs 0.29 ms against a 16.6 ms tick, so the
##    join has effectively never anything to wait for, and in exchange the result
##    lands a fixed one tick after the event on every machine instead of a
##    variable number of ticks later.
##
## Architectural Invariant I-4: the four signals below and the tick boundary are
## the only things that wake this node. It declares no [code]_process[/code], and
## the [code]_physics_process[/code] §4.3 speaks of is the clock's, not this
## one's.

## An Assembly's body has taken new mass properties. Distinct from
## [signal EventBusService.assembly_mass_dirty], which says a solve is
## [i]needed[/i]; this one says one has landed, and carries the tick its input
## was captured on so a consumer can tell a fresh solve from a superseded one.
signal mass_applied(assembly_id: int, source_tick: int)

## Assembly id -> [AssemblyRuntime]. Registered by whoever owns the Assembly.
##
## The same shape as [DetachmentScheduler]'s map and for the same reason:
## CLAUDE.md §2 lists an [code]assembly_registry.gd[/code] that does not exist
## yet, and registering directly avoids pre-empting its design. When it lands,
## [method register] and [method unregister] are the two calls to move.
var _targets: Dictionary = {}

## Assembly ids awaiting a solve. Ascending and duplicate-free, so a batch is
## captured in a reproducible order (Architectural Invariant I-9).
var _dirty: PackedInt32Array = PackedInt32Array()

## Snapshots handed to the worker, and the properties it produced from them.
## Written by the worker only between the launch and the join, and read by the
## main thread only after it.
var _inputs: Array[MassSolver.MassInput] = []
var _results: Array[MassSolver.MassProperties] = []
var _task_id: int = -1


func _ready() -> void:
	MatchClock.tick_started.connect(_on_tick_started)
	EventBus.assembly_mass_dirty.connect(_mark_dirty)
	EventBus.consumable_mass_step.connect(_mark_dirty)
	EventBus.part_attached.connect(_on_part_changed)
	EventBus.part_removed.connect(_on_part_changed)
	EventBus.island_detached.connect(_on_island_detached)


func _exit_tree() -> void:
	MatchClock.tick_started.disconnect(_on_tick_started)
	EventBus.assembly_mass_dirty.disconnect(_mark_dirty)
	EventBus.consumable_mass_step.disconnect(_mark_dirty)
	EventBus.part_attached.disconnect(_on_part_changed)
	EventBus.part_removed.disconnect(_on_part_changed)
	EventBus.island_detached.disconnect(_on_island_detached)
	# A task still running holds references into arrays this node is about to
	# drop. Physics server RIDs are not the only thing that leaks silently.
	_join()


## Registers the runtime whose body this scheduler writes for [param assembly_id].
func register(assembly_id: int, runtime: AssemblyRuntime) -> void:
	assert(not _targets.has(assembly_id), "assembly %d registered twice" % assembly_id)
	_targets[assembly_id] = runtime
	_mark_dirty(assembly_id)


func unregister(assembly_id: int) -> void:
	_targets.erase(assembly_id)
	var at := _dirty.find(assembly_id)
	if at != -1:
		_dirty.remove_at(at)


## Assemblies awaiting a solve, ascending. Diagnostics and tests only.
func pending() -> PackedInt32Array:
	return _dirty.duplicate()


## True while a worker task is in flight. Diagnostics and tests only.
func is_solving() -> bool:
	return _task_id != -1


func _on_part_changed(assembly_id: int, _slot: int) -> void:
	_mark_dirty(assembly_id)


func _on_island_detached(assembly_id: int, _slots: PackedByteArray, _body_id: int) -> void:
	_mark_dirty(assembly_id)


## Ascending insert rather than append-then-sort: the list is short, almost
## always length one, and keeping it ordered at all times means the capture order
## never depends on which event arrived first.
func _mark_dirty(assembly_id: int) -> void:
	if not _targets.has(assembly_id):
		return
	for i in _dirty.size():
		if _dirty[i] == assembly_id:
			return
		if _dirty[i] > assembly_id:
			_dirty.insert(i, assembly_id)
			return
	_dirty.append(assembly_id)


## Apply first, launch second. The tick's forces must see the newest properties,
## and a solve launched now cannot be part of that — it is for the next tick.
func _on_tick_started(tick: int) -> void:
	_join_and_apply()
	_launch(tick)


func _launch(tick: int) -> void:
	if _dirty.is_empty():
		return
	assert(_task_id == -1, "mass solve launched with one already in flight")
	# The batch arrays are emptied by the join that consumed the last one, not
	# here. Clearing in both places reads as belt and braces and is worse than
	# either alone: with two owners neither is load-bearing, so the one that is
	# actually required can be deleted without a single test noticing.
	assert(_inputs.is_empty() and _results.is_empty(), "a batch was never consumed")
	for assembly_id in _dirty:
		var runtime: AssemblyRuntime = _targets.get(assembly_id)
		if runtime == null:
			continue
		_inputs.append(
			MassSolver.capture(assembly_id, runtime.states, runtime.graph, tick)
		)
	_dirty.clear()
	if _inputs.is_empty():
		return
	_task_id = WorkerThreadPool.add_task(_solve_batch, true, "mass_recompute")


## Runs on a worker thread. Reads its snapshots and the immutable registry, and
## touches nothing else — no node, no signal, no [ChassisGraph].
func _solve_batch() -> void:
	for input in _inputs:
		_results.append(MassSolver.compute_from(input))


func _join_and_apply() -> void:
	if not _join():
		return
	for mp in _results:
		var runtime: AssemblyRuntime = _targets.get(mp.assembly_id)
		# An Assembly terminated during the solve has no body left to write to.
		# The result is discarded rather than re-queued: there is nothing to
		# recompute for a wreck.
		if runtime == null:
			continue
		runtime.apply_mass_properties(mp)
		mass_applied.emit(mp.assembly_id, mp.source_tick)
	_results.clear()
	_inputs.clear()


## Waits out the in-flight task, if any. Returns whether there was one.
func _join() -> bool:
	if _task_id == -1:
		return false
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	return true
