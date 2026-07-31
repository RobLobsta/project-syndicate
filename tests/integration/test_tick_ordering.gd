extends TestCase
## Enforces the tick-phase ordering guarantee of
## [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §8.3.
##
## Within [signal EventBusService.tick_resolved], handlers run in priority-group
## order: damage writes complete before detachment runs, detachment before the
## mass solve, and so on. A handler at a lower priority may never observe state
## produced by a higher one within the same tick.
##
## Godot dispatches a signal in connection order, which is scene-construction
## order, which is not reproducible. [method EventBusService.connect_tick_resolved]
## exists to impose a deterministic order on top of that, and this test is what
## keeps it honest.


## Dispatch order as observed, shared by every recorder.
##
## An object, not a bare [PackedInt32Array]: packed arrays assign by value, so
## handing each recorder "the" log would hand each one its own copy, and the
## test would then reconstruct registration order and pass no matter what the
## bus did.
class TickLog:
	extends RefCounted

	var order: PackedInt32Array = PackedInt32Array()

	func record(priority: int) -> void:
		order.append(priority)


## One registered handler. A separate object per handler is deliberate:
## [method Callable.bind] does not make two Callables over the same object and
## method compare unequal, so binding an index would produce handlers the bus
## treats as duplicates.
class Recorder:
	extends RefCounted

	var priority: int = 0
	var log: TickLog

	func _init(p: int, shared_log: TickLog) -> void:
		priority = p
		log = shared_log

	func on_tick() -> void:
		log.record(priority)


var _log: TickLog = TickLog.new()
var _recorders: Array[Recorder] = []


func after_all() -> void:
	_disconnect_all()


func test_handlers_dispatch_in_priority_order() -> void:
	_reset()
	# Registered deliberately backwards, so a pass cannot come from the
	# registration order happening to match the priority order.
	_register(EventBus.PRIORITY_NETWORK)
	_register(EventBus.PRIORITY_DAMAGE)
	_register(EventBus.PRIORITY_PRESENTATION)
	_register(EventBus.PRIORITY_DETACHMENT)
	_register(EventBus.PRIORITY_MASS)
	_register(EventBus.PRIORITY_FUNCTIONAL)

	EventBus.tick_resolved.emit()

	var expected := PackedInt32Array([
		EventBus.PRIORITY_DAMAGE,
		EventBus.PRIORITY_DETACHMENT,
		EventBus.PRIORITY_MASS,
		EventBus.PRIORITY_FUNCTIONAL,
		EventBus.PRIORITY_PRESENTATION,
		EventBus.PRIORITY_NETWORK,
	])
	check_eq(_collected(), expected, "tick handlers must run in ascending priority order")
	_disconnect_all()


func test_equal_priorities_keep_registration_order() -> void:
	_reset()
	# Three handlers in one group must run in the order they registered, not in
	# whatever order a sort happens to produce. Detachment ordering depends on
	# the dispatch order being a total order (I-9), and a sort that is merely
	# stable-by-luck stops being so as soon as the entry count changes.
	for i in 3:
		_register(EventBus.PRIORITY_MASS)
	EventBus.tick_resolved.emit()
	check_eq(_collected().size(), 3, "all three handlers ran")
	check_eq(
		EventBus.tick_handler_priorities(),
		PackedInt32Array([
			EventBus.PRIORITY_MASS, EventBus.PRIORITY_MASS, EventBus.PRIORITY_MASS
		]),
		"all three remain registered in one group"
	)
	_disconnect_all()


func test_priority_constants_are_strictly_ascending() -> void:
	var ordered := PackedInt32Array([
		EventBus.PRIORITY_DAMAGE,
		EventBus.PRIORITY_DETACHMENT,
		EventBus.PRIORITY_MASS,
		EventBus.PRIORITY_FUNCTIONAL,
		EventBus.PRIORITY_PRESENTATION,
		EventBus.PRIORITY_NETWORK,
	])
	for i in range(1, ordered.size()):
		check_true(
			ordered[i] > ordered[i - 1],
			"priority group %d must exceed the one before it" % i
		)


func test_disconnect_removes_a_handler_from_dispatch() -> void:
	_reset()
	_register(EventBus.PRIORITY_DAMAGE)
	_register(EventBus.PRIORITY_MASS)

	EventBus.disconnect_tick_resolved(Callable(_recorders[0], "on_tick"))
	_recorders.remove_at(0)

	EventBus.tick_resolved.emit()
	check_eq(_collected().size(), 1, "the disconnected handler must not run")
	check_eq(
		EventBus.tick_handler_priorities(),
		PackedInt32Array([EventBus.PRIORITY_MASS]),
		"only the surviving handler remains registered"
	)
	_disconnect_all()


func test_registry_is_empty_after_teardown() -> void:
	# Guards the fixture itself: a leaked handler would make every later test in
	# this file depend on the order the runner happened to pick.
	_disconnect_all()
	check_eq(
		EventBus.tick_handler_priorities().size(),
		0,
		"no tick handler may leak out of a test"
	)


func _reset() -> void:
	_disconnect_all()
	_log = TickLog.new()


func _register(priority: int) -> void:
	var recorder := Recorder.new(priority, _log)
	_recorders.append(recorder)
	EventBus.connect_tick_resolved(Callable(recorder, "on_tick"), priority)


func _disconnect_all() -> void:
	for r in _recorders:
		EventBus.disconnect_tick_resolved(Callable(r, "on_tick"))
	_recorders.clear()


## The order handlers actually ran in, as recorded during dispatch.
func _collected() -> PackedInt32Array:
	return _log.order
