class_name AssemblyStatSolver
extends Node
## Produces [signal EventBusService.assembly_stats_ready] for the garage, owned
## by [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §6.
##
## §6 requires the stat panel to update [i]once per edit[/i] rather than per
## frame, and to get its numbers from a solver that runs off the main thread on a
## structural change. That signal had a declaration in [EventBusService] and no
## producer at all until this class; the panel is written against it and nothing
## polls a [BuildContext] (Architectural Invariant I-4).
##
## [b]It follows [MassRecomputeScheduler]'s shape deliberately.[/b] Dirty on the
## structural signals, capture and launch on
## [signal MatchClockService.tick_started], join on the next one. Two schedulers
## with different disciplines for the same job is how one of them ends up reading
## a half-written snapshot; and the amendment that scheduler records — join
## unconditionally rather than poll — is what makes the result land a fixed one
## tick after the edit on every machine.
##
## [b]It works from a [BuildContext], not from an [AssemblyRuntime].[/b] The
## garage has no rigid body, no contacts and no world: it has the lattice, and
## every figure §6 asks for is derivable from it. That is what lets the panel
## answer before the build has ever been driven.

## Floor on the centre-of-mass height in the static stability factor, from doc 05
## §5.1. A build whose COM sits at or below its contacts cannot tip at any
## lateral acceleration, and the division would answer infinity.
const MIN_COM_HEIGHT_M: float = 0.05

## Assemblies awaiting a solve. Ascending and duplicate-free, so a batch is
## captured in a reproducible order (Architectural Invariant I-9).
var _dirty: PackedInt32Array = PackedInt32Array()

## Contexts this solver reports on, by assembly id. The garage registers its own
## and unregisters it before disposing of it.
var _contexts: Dictionary = {}

var _inputs: Array[StatInput] = []
var _results: Array[AssemblyStats] = []
var _task_id: int = -1


func _ready() -> void:
	MatchClock.tick_started.connect(_on_tick_started)
	EventBus.part_attached.connect(_on_part_changed)
	EventBus.part_removed.connect(_on_part_changed)


func _exit_tree() -> void:
	MatchClock.tick_started.disconnect(_on_tick_started)
	EventBus.part_attached.disconnect(_on_part_changed)
	EventBus.part_removed.disconnect(_on_part_changed)
	# A task still running holds references into arrays this node is about to
	# drop, and a node with a task in flight cannot be freed at all
	# (LEARNED_FACTS.md §1 fact 53).
	_join()


## Reports on [param ctx] from now on, and solves it once immediately so that a
## panel has numbers before the first edit rather than after it.
func track(ctx: BuildContext) -> void:
	_contexts[ctx.assembly_id] = ctx
	_mark_dirty(ctx.assembly_id)


## Stops reporting on [param assembly_id]. Call this before disposing of the
## context: a solve captured against a context whose physics space has been
## freed is a solve against a dangling RID.
func forget(assembly_id: int) -> void:
	_contexts.erase(assembly_id)
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


## Ascending insert rather than append-then-sort: the list is short and keeping
## it ordered means the capture order never depends on which event arrived first.
func _mark_dirty(assembly_id: int) -> void:
	if not _contexts.has(assembly_id):
		return
	for i: int in _dirty.size():
		if _dirty[i] == assembly_id:
			return
		if _dirty[i] > assembly_id:
			_dirty.insert(i, assembly_id)
			return
	_dirty.append(assembly_id)


## Publish first, launch second, for [MassRecomputeScheduler]'s reason: a solve
## launched now is for the next tick, and the panel must not be shown a result
## that is one edit behind the one that woke it.
func _on_tick_started(tick: int) -> void:
	_join_and_publish()
	_launch(tick)


func _launch(tick: int) -> void:
	if _dirty.is_empty():
		return
	assert(_task_id == -1, "stat solve launched with one already in flight")
	assert(_inputs.is_empty() and _results.is_empty(), "a batch was never consumed")
	for assembly_id: int in _dirty:
		var ctx: BuildContext = _contexts.get(assembly_id, null)
		if ctx == null:
			continue
		_inputs.append(StatInput.capture(ctx, tick))
	_dirty.clear()
	if _inputs.is_empty():
		return
	_task_id = WorkerThreadPool.add_task(_solve_batch, true, "assembly_stats")


## Runs on a worker thread. Reads its own snapshots and the immutable
## [PartRegistry], and touches nothing else — no node, no signal, no
## [BuildContext].
func _solve_batch() -> void:
	for input: StatInput in _inputs:
		_results.append(solve(input))


func _join_and_publish() -> void:
	if not _join():
		return
	for stats: AssemblyStats in _results:
		EventBus.assembly_stats_ready.emit(stats)
	_results.clear()
	_inputs.clear()


func _join() -> bool:
	if _task_id == -1:
		return false
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	return true


## ===== THE SOLVE =======================================================


## §6's figures, from one snapshot. A [code]static[/code] over a plain record, so
## that every one of them is assertable without a garage, a viewport, or a tick.
static func solve(input: StatInput) -> AssemblyStats:
	var stats := AssemblyStats.new()
	stats.assembly_id = input.assembly_id
	stats.source_tick = input.source_tick
	stats.part_count = input.part_count
	stats.build_cost = input.build_cost
	stats.total_integrity = input.total_integrity
	stats.power_draw_pu = input.power_draw_pu
	stats.power_capacity_pu = input.power_capacity_pu
	stats.mounts_used = input.mounts_used
	stats.mount_budget = input.mount_budget
	stats.mass_tolerance_kg = input.mass_tolerance_kg
	stats.projected_top_speed_mps = input.speed_cap_mps

	var mp := MassSolver.compute_from(input.mass)
	stats.total_mass_kg = mp.total_mass
	stats.centre_of_mass_local = mp.com_local
	stats.rollover_lateral_g = static_stability_factor(
		mp.com_local, input.contact_half_track_m, input.lowest_contact_y_m
	)
	return stats


## Doc 05 §5.1's `SSF = t / 2h`: half the track width over the centre of mass's
## height above the contacts, which is the lateral acceleration in `g` at which
## the Assembly tips.
##
## [b]The support polygon is a rectangle here, and that is exact rather than an
## approximation.[/b] §5.1 takes the half-track from
## [code]ConvexHull2D.half_width_x[/code] of the contact hull, and the widest
## point of a hull in x is the outermost of the points it was built from — so for
## this figure the hull and the maximum agree by construction, and building one
## in the garage would be arithmetic with no consequence.
##
## Returns 0 for a build with no contacts at all. A build that cannot stand up
## has no lateral acceleration at which it tips over, and reporting a large
## number for it would read as the most stable thing a player could construct.
static func static_stability_factor(
	com_local: Vector3, half_track_m: float, lowest_contact_y_m: float
) -> float:
	if half_track_m <= 0.0:
		return 0.0
	var height := maxf(com_local.y - lowest_contact_y_m, MIN_COM_HEIGHT_M)
	return half_track_m / height


## What one solve is given: everything it needs, and no reference to anything the
## main thread can edit while it runs.
class StatInput:
	extends RefCounted

	var assembly_id: int = 0
	var source_tick: int = 0
	var mass: MassSolver.MassInput = null

	var part_count: int = 0
	var build_cost: int = 0
	var total_integrity: float = 0.0
	var power_draw_pu: float = 0.0
	var power_capacity_pu: float = 0.0
	var mounts_used: int = 0
	var mount_budget: int = 0
	var mass_tolerance_kg: float = 0.0
	var speed_cap_mps: float = 0.0

	## Lateral distance from the Assembly's centreline to the outermost Motive
	## Assembly contact, and the height of the lowest one. Doc 05 §5.1's two
	## geometric inputs to the rollover threshold.
	var contact_half_track_m: float = 0.0
	var lowest_contact_y_m: float = 0.0

	## Snapshots [param ctx]. Everything read here is read on the main thread; the
	## worker sees only the copy.
	static func capture(ctx: BuildContext, tick: int) -> StatInput:
		var out := StatInput.new()
		out.assembly_id = ctx.assembly_id
		out.source_tick = tick
		out.mass = MassSolver.capture(ctx.assembly_id, ctx.states, ctx.graph, tick)

		var ledger := ctx.budgets
		out.build_cost = ledger.total_build_cost
		out.power_draw_pu = ledger.power_draw_pu
		out.power_capacity_pu = ledger.power_available_pu()
		out.mounts_used = ledger.mount_used
		out.mount_budget = ledger.mount_budget()
		if ledger.core_profile != null:
			out.mass_tolerance_kg = ledger.core_profile.mass_tolerance_kg
			out.speed_cap_mps = ledger.core_profile.speed_cap_mps

		var lowest := 0.0
		var seen_contact := false
		for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
			var st := ctx.state(slot)
			if st == null:
				continue
			var def := PartRegistry.definition(st.part_def_id)
			if def == null:
				continue
			out.part_count += 1
			out.total_integrity += st.integrity
			if def.part_class != PartEnums.PartClass.MOTIVE_ASSEMBLY:
				continue
			# The contact sits at the part's own origin: doc 05 §6.1 casts its
			# probe from there, and §2's `contact_radius_m` is measured from it.
			var centre := LatticeMath.cell_to_local(st.origin_cell)
			out.contact_half_track_m = maxf(out.contact_half_track_m, absf(centre.x))
			var radius := 0.0
			if def.motive_profile != null:
				radius = def.motive_profile.contact_radius_m
			var foot := centre.y - radius
			lowest = foot if not seen_contact else minf(lowest, foot)
			seen_contact = true
		out.lowest_contact_y_m = lowest
		return out
