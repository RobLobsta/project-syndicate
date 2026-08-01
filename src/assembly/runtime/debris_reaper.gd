class_name DebrisReaper
extends Node
## Lifetime and sleep management for [DebrisPool]'s bodies, per
## [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §6.2.
##
## Two jobs, both temporal. A debris body is returned to the pool
## [constant IslandDetacher.DEBRIS_LIFETIME_S] after it was spawned, and one that
## has been asleep for [constant FREEZE_AFTER_ASLEEP_S] is frozen — taken out of
## the solver entirely while staying exactly where it came to rest.
##
## Architectural Invariant I-4: this declares no [code]_process[/code] and no
## [code]_physics_process[/code]. It runs on
## [signal MatchClockService.tick_started], the same seam [MassRecomputeScheduler]
## uses, and with no debris in flight the sweep returns on its first line. Every
## deadline below is a tick count rather than an accumulated float, so a body
## expires on the same tick on the server and on every client.

## §6.2. A body asleep this long is frozen out of the solver.
const FREEZE_AFTER_ASLEEP_S: float = 4.0

## The pool this reaper returns bodies to. Set by [DebrisPool], which owns it.
var pool: DebrisPool = null

## [constant FREEZE_AFTER_ASLEEP_S] in ticks. A member rather than a [code]const[/code]
## because the conversion is a function call and a const expression may not make
## one; it is written once at construction and never again.
var _freeze_after_ticks: int = MatchClockService.ticks_for_seconds(FREEZE_AFTER_ASLEEP_S)


func _ready() -> void:
	MatchClock.tick_started.connect(_on_tick_started)


func _exit_tree() -> void:
	MatchClock.tick_started.disconnect(_on_tick_started)


## Starts [param body]'s lifetime, per §6's call at the end of detachment.
func schedule(body: DebrisBodyRef, lifetime_s: float) -> void:
	body.expires_at_tick = MatchClock.tick + MatchClockService.ticks_for_seconds(lifetime_s)
	body.asleep_since_tick = DebrisBodyRef.INVALID_TICK


## Ages every body in flight against [param tick]. Public so that a test can
## drive it without waiting out 22 s of wall clock.
func sweep(tick: int) -> void:
	if pool == null or pool.active_count() == 0:
		return  # the overwhelmingly common path
	for body in pool.active_bodies():
		if body.expires_at_tick != DebrisBodyRef.INVALID_TICK and tick >= body.expires_at_tick:
			pool.release(body)
			continue
		if body.freeze:
			# Already static. Reading `sleeping` on it would be meaningless: a
			# frozen body never reports itself asleep, so the accumulator would
			# reset every tick and the freeze would look like it never happened.
			continue
		if not body.sleeping:
			body.asleep_since_tick = DebrisBodyRef.INVALID_TICK
			continue
		if body.asleep_since_tick == DebrisBodyRef.INVALID_TICK:
			body.asleep_since_tick = tick
		elif tick - body.asleep_since_tick >= _freeze_after_ticks:
			body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			body.freeze = true


func _on_tick_started(tick: int) -> void:
	sweep(tick)
