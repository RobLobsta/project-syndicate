class_name TestCase
extends RefCounted
## Base class for every test in [code]tests/[/code].
##
## Deliberately dependency-free: no addon, no plugin, no editor requirement. The
## suite has to run under [code]--headless[/code] on a machine with nothing
## installed but the engine binary, because that is how CI runs it.
##
## A test class declares methods named [code]test_*[/code]. The runner
## instantiates the class once per file, calls [method before_all], then every
## [code]test_*[/code] method in sorted order, then [method after_all].
## Assertions record failures rather than halting, so one broken invariant does
## not hide the next twelve.

var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _current: String = ""


## Override for one-time setup shared by every test in the file.
func before_all() -> void:
	pass


## Override for one-time teardown.
func after_all() -> void:
	pass


func failures() -> PackedStringArray:
	return _failures


func check_count() -> int:
	return _checks


func _set_current(method: String) -> void:
	_current = method


## ===== PHYSICS ========================================================


## Suspends the calling test until the engine has stepped physics
## [param count] times. [code]await physics_frames(n)[/code].
##
## The only way a test observes a force. Everything the motion layer derives is
## a pure static solver a test can call directly, but the step from a solved
## force to a body that moved is the physics server's, and until this existed
## the suite did all of its work inside a single [code]_process[/code] callback
## and never let one tick run.
##
## Two consequences worth knowing before reaching for it. A body added to the
## tree is registered in the space immediately but keeps whatever transform it
## had when it was added until a tick flushes it — so a query before the first
## frame answers against a stale pose rather than answering nothing, which is
## the trap that reads as "the space is empty". And a physics test costs real
## wall time at 60 Hz: prefer the fewest frames that make the claim, and assert
## a derived number rather than soaking.
func physics_frames(count: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i: int in maxi(count, 1):
		await tree.physics_frame


## ===== ASSERTIONS ======================================================
## Every assertion returns true on success so that a test can bail out of a
## sequence whose later steps would crash on the failure it just recorded.

func check_true(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	_record(message)
	return false


func check_false(condition: bool, message: String) -> bool:
	return check_true(not condition, message)


func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	_checks += 1
	if _variant_eq(actual, expected):
		return true
	_record("%s\n      expected: %s\n      actual:   %s" % [message, expected, actual])
	return false


func check_ne(actual: Variant, unexpected: Variant, message: String) -> bool:
	_checks += 1
	if not _variant_eq(actual, unexpected):
		return true
	_record("%s\n      expected anything but: %s" % [message, unexpected])
	return false


func check_approx(actual: float, expected: float, message: String, tolerance := 1e-5) -> bool:
	_checks += 1
	if absf(actual - expected) <= tolerance:
		return true
	_record(
		"%s\n      expected: %.9f (+/- %.9f)\n      actual:   %.9f"
		% [message, expected, tolerance, actual]
	)
	return false


func check_null(value: Variant, message: String) -> bool:
	return check_true(value == null, message)


func check_not_null(value: Variant, message: String) -> bool:
	return check_true(value != null, message)


## Unconditional failure, for a branch that should be unreachable.
func fail(message: String) -> void:
	_checks += 1
	_record(message)


func _record(message: String) -> void:
	_failures.append("%s: %s" % [_current, message])


## Typed arrays and packed arrays compare correctly with ==, but comparing a
## float to an int silently succeeds in Variant comparison, which has hidden a
## real defect before. Floats therefore go through an explicit epsilon.
static func _variant_eq(a: Variant, b: Variant) -> bool:
	if a is float or b is float:
		if (a is float or a is int) and (b is float or b is int):
			return is_equal_approx(float(a), float(b))
		return false
	return a == b
