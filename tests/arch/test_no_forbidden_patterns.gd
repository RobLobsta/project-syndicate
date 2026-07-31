extends TestCase
## Enforces the forbidden-pattern table in [code]CLAUDE.md[/code] §3.3.
##
## Each entry below names the construct, the pattern that finds it, and the
## replacement. The message is the point: a conformance test that only says
## "forbidden" costs the reader a trip to the documentation, and the rule then
## gets worked around instead of followed.

class Rule:
	extends RefCounted

	var pattern: String
	var reason: String

	func _init(p: String, r: String) -> void:
		pattern = p
		reason = r


func _rules() -> Array[Rule]:
	return [
		Rule.new(
			"(?<![\\w.])find_child(ren)?\\s*\\(",
			"O(n) tree walk at runtime; cache the reference at spawn instead"
		),
		Rule.new(
			"\\.call_group\\s*\\(",
			"reflection cost in a hot path; emit a direct EventBus signal instead"
		),
		Rule.new(
			"\\.callv?\\s*\\(\\s*[\"']",
			"string method dispatch is unverifiable; use a Callable instead"
		),
		Rule.new(
			"create_(trimesh|convex)_collision\\s*\\(",
			"generates collision from a visual mesh; colliders come from ColliderProfile (I-1)"
		),
		Rule.new(
			"(?<![\\w.])ConcavePolygonShape3D(?![\\w])",
			"forbidden on anything dynamic; use primitives or convex hulls (I-1)"
		),
		Rule.new(
			"(?<![\\w.])CSG[A-Za-z0-9]*3D(?![\\w])",
			"runtime CSG is forbidden; bake to an ArrayMesh offline (I-10)"
		),
		Rule.new(
			"get_node\\s*\\(\\s*[\"'][^\"']*/",
			"hard-coded node path is fragile against scene edits; use an @export reference"
		),
	]


func test_src_is_free_of_forbidden_patterns() -> void:
	for rule in _rules():
		var regex := SourceScanner.compile(rule.pattern)
		for path in SourceScanner.gd_files(SourceScanner.SRC_ROOT):
			for line in SourceScanner.match_lines(path, regex):
				fail("%s:%d — %s" % [SourceScanner.short(path), line, rule.reason])
	check_true(true, "src/ scanned against CLAUDE.md §3.3")


func test_no_await_inside_a_physics_callback() -> void:
	# await in _physics_process breaks determinism: the continuation resumes on
	# an arbitrary later frame, so tick N's work can land in tick N+3.
	var func_start := SourceScanner.compile("^\\s*func\\s+")
	var physics_start := SourceScanner.compile("^\\s*func\\s+_physics_process\\s*\\(")
	var await_call := SourceScanner.compile("(?<![\\w.])await\\s")

	for path in SourceScanner.gd_files(SourceScanner.SRC_ROOT):
		var lines := SourceScanner.strip_noise(SourceScanner.read(path)).split("\n")
		var inside := false
		for i in lines.size():
			var line := lines[i]
			if func_start.search(line) != null:
				inside = physics_start.search(line) != null
				continue
			if inside and await_call.search(line) != null:
				fail(
					"%s:%d — await inside _physics_process breaks determinism"
					% [SourceScanner.short(path), i + 1]
				)
	check_true(true, "src/ scanned for await in physics callbacks")


func test_mutable_state_is_not_declared_on_part_definition() -> void:
	# I-11: PartDefinition is shared and immutable. Its non-exported vars are
	# the baked derived fields, written once by the registry. An @export var
	# added below the derived-fields banner, or a setter on one, would mean a
	# runtime write to shared data.
	var path := "res://src/core/data/part_definition.gd"
	var source := SourceScanner.read(path)
	# Word-bounded: a plain substring search also matches the assignment to
	# occupancy_bitset, which is exactly the sort of false positive that gets a
	# conformance test disabled rather than fixed.
	var setter := SourceScanner.compile("(?<![\\w])set\\s*=")
	for line in SourceScanner.match_lines(path, setter):
		fail("%s:%d declares a property setter; PartDefinition is immutable (I-11)"
				% [SourceScanner.short(path), line])
	check_true(
		source.contains("_bake_derived_fields"),
		"PartDefinition must bake its derived fields in one place"
	)
