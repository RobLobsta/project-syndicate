extends TestCase
## Every GDScript file in the project must parse.
##
## This exists because [code]godot --import[/code] registers global class names
## by scanning source without fully compiling it, so a script with a parse error
## imports cleanly, registers its [code]class_name[/code], and only fails at the
## moment something loads it. A file nothing loads yet can therefore sit broken
## in the tree indefinitely, and the failure surfaces later as an unrelated
## "identifier not declared" error in whichever file first touches it.
##
## Loading each script explicitly turns that into an immediate, located failure.

const ROOTS: Array[String] = [
	SourceScanner.SRC_ROOT,
	SourceScanner.TOOLS_ROOT,
	SourceScanner.TESTS_ROOT,
]


func test_every_script_loads_and_can_be_instantiated() -> void:
	var count := 0
	for root: String in ROOTS:
		for path in SourceScanner.gd_files(root):
			count += 1
			var script: GDScript = ResourceLoader.load(path, "GDScript") as GDScript
			if script == null:
				fail("%s failed to load; see the engine log for the parse error" % SourceScanner.short(path))
				continue
			check_true(
				script.can_instantiate(),
				"%s parsed but cannot be instantiated" % SourceScanner.short(path)
			)
	check_true(count > 0, "script scan must find files; an empty scan is a broken test")


func test_no_source_file_is_empty() -> void:
	for root: String in ROOTS:
		for path in SourceScanner.gd_files(root):
			check_false(
				SourceScanner.read(path).strip_edges().is_empty(),
				"%s is empty" % SourceScanner.short(path)
			)


func test_no_placeholder_markers_in_src() -> void:
	# CLAUDE.md §10 rule 15: code committed to this repository is complete.
	var regex := SourceScanner.compile("(?<![\\w])(TODO|FIXME|XXX|HACK)(?![\\w])")
	for path in SourceScanner.gd_files(SourceScanner.SRC_ROOT):
		# Deliberately scans raw source including comments: a TODO left in a
		# comment is exactly the case the rule bans.
		var lines := SourceScanner.read(path).split("\n")
		for i in lines.size():
			if regex.search(lines[i]) != null:
				fail(
					"%s:%d contains a placeholder marker; src/ ships complete (CLAUDE.md §10.15)"
					% [SourceScanner.short(path), i + 1]
				)
	check_true(true, "src/ scanned for placeholder markers")
