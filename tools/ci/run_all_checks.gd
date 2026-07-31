extends SceneTree
## Headless test runner. Discovers and runs every [TestCase] under
## [code]tests/[/code], then exits non-zero if anything failed.
##
## Invoke through [code]tools/ci/run_all_checks.sh[/code], which reimports first
## so that GDScript parse errors surface as errors rather than as silently
## missing test files.
##
## Discovery order is a sorted path walk, so the suite runs identically on every
## machine and a failure list can be diffed between runs.
##
## The run happens on the first [method _process] frame rather than in
## [method _init]. A [SceneTree] script's [code]_init[/code] runs before the main
## loop is initialised, and a [method SceneTree.quit] issued there is discarded —
## the process then idles forever with the suite's output still buffered. Waiting
## one frame also guarantees the eight autoloads are in the tree, which the
## integration tests need.

const TESTS_ROOT: String = "res://tests"
const TEST_FILE_PREFIX: String = "test_"

## Directories under tests/, in the order CLAUDE.md §9.1 lists them. Suites run
## cheapest-first so that a broken constant fails before a physics soak does.
const SUITE_ORDER: Array[String] = [
	"arch",
	"unit",
	"integration",
	"physics",
	"generation",
]


var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run()
	return true


func _run() -> void:
	var files := _discover()
	if files.is_empty():
		printerr("run_all_checks: no test files found under %s" % TESTS_ROOT)
		quit(1)
		return

	var total_checks := 0
	var total_failures := 0
	var failed_files := 0

	print("run_all_checks: %d test files" % files.size())
	for path in files:
		var result := _run_file(path)
		total_checks += int(result["checks"])
		var failures: PackedStringArray = result["failures"]
		total_failures += failures.size()
		if failures.is_empty():
			print("  PASS  %s  (%d checks)" % [_short(path), int(result["checks"])])
		else:
			failed_files += 1
			print("  FAIL  %s  (%d checks, %d failures)"
					% [_short(path), int(result["checks"]), failures.size()])
			for f in failures:
				print("        %s" % f)

	print("")
	print("run_all_checks: %d checks, %d failures across %d/%d files"
			% [total_checks, total_failures, failed_files, files.size()])
	quit(1 if total_failures > 0 else 0)


func _run_file(path: String) -> Dictionary:
	# ResourceLoader rather than load(): a script with a parse error makes load()
	# emit engine errors and hand back a GDScript that cannot be instantiated,
	# and calling new() on it aborts this function before it can report anything.
	# A file that will not parse has to surface as a failure, not as a silent
	# pass — that is the one bug in a test runner that hides every other bug.
	var script: GDScript = ResourceLoader.load(path, "GDScript") as GDScript
	if script == null:
		return _failure(path, "failed to load (parse error; see the engine log above)")
	if not script.can_instantiate():
		return _failure(path, "script has a parse error and cannot be instantiated")

	var instance: TestCase = script.new() as TestCase
	if instance == null:
		return _failure(path, "script does not extend TestCase")

	var methods := PackedStringArray()
	for m in instance.get_method_list():
		var name: String = m["name"]
		if name.begins_with(TEST_FILE_PREFIX) and int(m["args"].size()) == 0:
			methods.append(name)
	methods.sort()

	instance.before_all()
	for name in methods:
		instance._set_current(name)
		instance.call(name)
	instance.after_all()

	return {"checks": instance.check_count(), "failures": instance.failures()}


static func _failure(path: String, reason: String) -> Dictionary:
	return {"checks": 1, "failures": PackedStringArray(["%s: %s" % [path, reason]])}


## Sorted walk of the suite directories, skipping the base class itself.
func _discover() -> PackedStringArray:
	var out := PackedStringArray()
	for suite in SUITE_ORDER:
		out.append_array(_walk("%s/%s" % [TESTS_ROOT, suite]))
	return out


func _walk(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out

	var files := PackedStringArray()
	var subdirs := PackedStringArray()
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with("."):
				subdirs.append(entry)
		elif entry.begins_with(TEST_FILE_PREFIX) and entry.ends_with(".gd"):
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()

	files.sort()
	subdirs.sort()
	for f in files:
		out.append("%s/%s" % [dir_path, f])
	for s in subdirs:
		out.append_array(_walk("%s/%s" % [dir_path, s]))
	return out


static func _short(path: String) -> String:
	return path.trim_prefix("res://tests/")
