class_name DebrisReaper
extends Node
## Lifetime, settling, and disposal for [DebrisPool]'s bodies, per
## [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §6.2.
##
## Three jobs, all temporal. A body that has been asleep for
## [constant FREEZE_AFTER_ASLEEP_S] is frozen — out of the solver entirely, but
## exactly where it came to rest. At
## [constant IslandDetacher.DEBRIS_LIFETIME_S] it is [b]retired[/b]: it stops
## being an obstacle, on that tick, everywhere. And some time after that it is
## recycled.
##
## [b]Amendment to §6.2: retirement and disposal are two events, not one.[/b] As
## written, a body's lifetime ended with it vanishing — which, watched, is a
## wreck blinking out of the world in front of the player. Waiting for the player
## to look away is the obvious fix and the wrong one if it is a single event,
## because a debris body is an obstacle: `MASK_ASSEMBLY_HULL` includes
## `LAYER_DEBRIS`, so a wreck kept alive by one player's camera would be a
## collision every other machine has already stopped simulating, and doc 12 §9.3
## has the dedicated server spawning these bodies for exactly that reason.
## Splitting the event settles it. Retirement is on the scheduled tick and is
## identical on the server and on every client, so nothing simulated depends on
## where anyone is looking; the linger that follows is presentation, and is the
## only part a camera influences.
##
## A retired body is therefore recycled when it has been off every screen for
## [constant OFFSCREEN_DWELL_S], or at [constant LINGER_MAX_S] regardless — the
## bound Architectural Invariant I-12 wants — or when [DebrisPool] needs the slot,
## which takes retired bodies before simulated ones for the same reason.
##
## Architectural Invariant I-4: this declares no [code]_process[/code] and no
## [code]_physics_process[/code]. It runs on
## [signal MatchClockService.tick_started], the same seam [MassRecomputeScheduler]
## uses, and with no debris in flight the sweep returns on its first line. Every
## deadline below is a tick count rather than an accumulated float, so a body
## leaves the simulation on the same tick everywhere.

## §6.2. A body asleep this long is frozen out of the solver.
const FREEZE_AFTER_ASLEEP_S: float = 4.0

## How long a retired body must be off every screen before it is recycled.
##
## Not zero. A camera shake or a pan that clips a wreck out of frame for two
## frames would otherwise recycle it, and the player who panned back would find
## it gone — the same pop this whole mechanism exists to avoid, just harder to
## reproduce.
const OFFSCREEN_DWELL_S: float = 0.5

## The longest a retired body may wait for every viewer to look away.
##
## Without it a player parked in front of a wreck holds a pool slot for the rest
## of the match, and I-12's bound on debris would be a bound on count only and
## not on time. Generous, because reaching it is the one case where a wreck does
## disappear in view — which is what §6.2's 0.25 s fade is for, once debris has
## meshes to fade.
const LINGER_MAX_S: float = 30.0

## The pool this reaper returns bodies to. Set by [DebrisPool], which owns it.
var pool: DebrisPool = null

## The three durations above in ticks. Members rather than [code]const[/code]
## because the conversion is a function call and a const expression may not make
## one; each is written once at construction and never again.
var _freeze_after_ticks: int = MatchClockService.ticks_for_seconds(FREEZE_AFTER_ASLEEP_S)
var _offscreen_dwell_ticks: int = MatchClockService.ticks_for_seconds(OFFSCREEN_DWELL_S)
var _linger_max_ticks: int = MatchClockService.ticks_for_seconds(LINGER_MAX_S)


func _ready() -> void:
	MatchClock.tick_started.connect(_on_tick_started)


func _exit_tree() -> void:
	MatchClock.tick_started.disconnect(_on_tick_started)


## Starts [param body]'s simulated lifetime, per §6's call at the end of
## detachment.
func schedule(body: DebrisBodyRef, lifetime_s: float) -> void:
	body.expires_at_tick = MatchClock.tick + MatchClockService.ticks_for_seconds(lifetime_s)
	body.asleep_since_tick = DebrisBodyRef.INVALID_TICK


## Ages every body in flight against [param tick]. Public so that a test can
## drive it without waiting out 22 s of wall clock.
func sweep(tick: int) -> void:
	if pool == null or pool.in_flight_count() == 0:
		return  # the overwhelmingly common path
	for body in pool.in_flight_bodies():
		if body.retired:
			_sweep_retired(body, tick)
		else:
			_sweep_simulated(body, tick)


## Ticks a body spends between retirement and its unconditional recycle.
## Diagnostics and tests.
func linger_max_ticks() -> int:
	return _linger_max_ticks


## A body that is still an obstacle: its deadline, and §6.2's settling freeze.
func _sweep_simulated(body: DebrisBodyRef, tick: int) -> void:
	if body.expires_at_tick != DebrisBodyRef.INVALID_TICK and tick >= body.expires_at_tick:
		# A build with no viewers has nothing to linger for, and skipping the
		# phase there means a dedicated server never carries a retired body at
		# all — doc 12 §9.2's gate applied at its cheapest point.
		if body.tracks_visibility():
			pool.retire(body, tick + _linger_max_ticks)
		else:
			pool.release(body)
		return
	if body.freeze:
		# Already static. Reading `sleeping` on it would be meaningless: a
		# frozen body never reports itself asleep, so the accumulator would
		# reset every tick and the freeze would look like it never happened.
		return
	if not body.sleeping:
		body.asleep_since_tick = DebrisBodyRef.INVALID_TICK
		return
	if body.asleep_since_tick == DebrisBodyRef.INVALID_TICK:
		body.asleep_since_tick = tick
	elif tick - body.asleep_since_tick >= _freeze_after_ticks:
		body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		body.freeze = true


## A body that has left the simulation and is waiting to stop being looked at.
func _sweep_retired(body: DebrisBodyRef, tick: int) -> void:
	if tick >= body.linger_deadline_tick:
		pool.release(body)
		return
	if body.is_on_screen():
		body.offscreen_since_tick = DebrisBodyRef.INVALID_TICK
		return
	if body.offscreen_since_tick == DebrisBodyRef.INVALID_TICK:
		body.offscreen_since_tick = tick
	elif tick - body.offscreen_since_tick >= _offscreen_dwell_ticks:
		pool.release(body)


func _on_tick_started(tick: int) -> void:
	sweep(tick)
