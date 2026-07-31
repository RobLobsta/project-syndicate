class_name MatchClockService
extends Node
## Autoload: [code]MatchClock[/code]. The authoritative tick counter and the
## sole emitter of [signal EventBusService.tick_resolved].
##
## This is one of the two classes in the project permitted to declare
## [code]_physics_process[/code] without violating Architectural Invariant I-4,
## because it is the thing that defines a tick. Everything else reacts to it.
##
## The clock runs whether or not a match is in progress: the garage needs a
## monotonic tick for undo grouping and the network layer needs one for
## handshake timing. [member running] gates only the tick advance.

signal tick_started(tick: int)

## Current authoritative tick. On a client this is the server tick estimate
## after clock sync; see [code]docs/HEADLESS_NETWORK_SYNC.md[/code] §6.
var tick: int = 0
## Seconds of simulated time elapsed, derived from [member tick] so that it can
## never drift from the tick count.
var time_s: float = 0.0
## Wall-clock cost of the last physics tick, surfaced by the diagnostics overlay.
var last_physics_ms: float = 0.0
var running: bool = true

var _tick_start_usec: int = 0


func _ready() -> void:
	# Nothing may run before the clock: it must observe a complete tick.
	process_physics_priority = -1000


func _physics_process(_delta: float) -> void:
	if not running:
		return
	_tick_start_usec = Time.get_ticks_usec()
	tick += 1
	time_s = float(tick) * SyndicateConstants.PHYSICS_DT
	tick_started.emit(tick)
	# Systems mutate state during the tick; EventBus dispatches the resolve
	# phase in priority order once every _physics_process has run.
	call_deferred(&"_resolve")


func _resolve() -> void:
	EventBus.tick_resolved.emit()
	last_physics_ms = float(Time.get_ticks_usec() - _tick_start_usec) / 1000.0


## Resets the clock to a server-provided tick. Used on match join and on a
## clock-sync correction large enough to warrant a hard set rather than a slew.
func reset_to(new_tick: int) -> void:
	tick = new_tick
	time_s = float(new_tick) * SyndicateConstants.PHYSICS_DT


## Ticks corresponding to a duration in seconds, rounded to nearest.
static func ticks_for_seconds(seconds: float) -> int:
	return int(roundf(seconds * float(SyndicateConstants.PHYSICS_HZ)))
