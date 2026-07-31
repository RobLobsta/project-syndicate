extends SceneTree
## CI entry point for the registry rules of
## [code]docs/PART_DATA_SCHEMA.md[/code] §14.
##
## [codeblock]
## godot --headless --path . --script tools/validate_part_registry.gd
## [/codeblock]
##
## Exits 1 on any failure and writes the §14 report to
## [constant REPORT_PATH] either way, so a passing run still produces the
## review artefact a balance change is reviewed against.
##
## The work happens on the first [method _process] frame, not in
## [method _init]: a [SceneTree] script's [code]_init[/code] runs before the main
## loop exists and a [method SceneTree.quit] issued there is discarded, leaving
## the process idling with its output still buffered.

const REPORT_DIR: String = "res://.build"
const REPORT_PATH: String = "res://.build/part_registry_report.md"

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(0 if _run() else 1)
	return true


func _run() -> bool:
	var validator := PartRegistryValidator.new()
	var ok := validator.validate_registry()

	print("validate_part_registry: %d parts checked" % validator.definitions().size())
	for warning in validator.warnings():
		print("  WARN  %s" % warning)
	for failure in validator.failures():
		printerr("  FAIL  %s" % failure)

	_write_report(validator.report_markdown())

	if ok:
		print("validate_part_registry: OK (%d warnings)" % validator.warnings().size())
	else:
		printerr("validate_part_registry: %d failures" % validator.failures().size())
	return ok


func _write_report(markdown: String) -> void:
	if not DirAccess.dir_exists_absolute(REPORT_DIR):
		var err := DirAccess.make_dir_recursive_absolute(REPORT_DIR)
		if err != OK:
			push_error("validate_part_registry: cannot create %s (error %d)" % [REPORT_DIR, err])
			return

	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error(
			"validate_part_registry: cannot write %s (error %d)"
			% [REPORT_PATH, FileAccess.get_open_error()]
		)
		return
	file.store_string(markdown)
	file.close()
	print("validate_part_registry: report written to %s" % REPORT_PATH)
