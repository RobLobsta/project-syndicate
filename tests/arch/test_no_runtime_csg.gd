extends TestCase
## Enforces Architectural Invariant I-10: no runtime CSG.
##
## No [CSGShape3D] may exist in any scene loaded during a match. CSG rebuilds its
## mesh and its collision on the main thread whenever anything in its subtree
## changes, which is precisely the cost this project's offline bake pipeline
## exists to avoid.
##
## Scenes are parsed as text rather than instantiated: instantiating an arena to
## test it would require the whole runtime to be present, and the check has to
## work on a bare checkout.

const CSG_TYPE_PATTERN: String = "type\\s*=\\s*\"CSG[A-Za-z0-9]*\""


func test_no_scene_contains_a_csg_node() -> void:
	var regex := SourceScanner.compile(CSG_TYPE_PATTERN)
	var scanned := 0
	for path in SourceScanner.scene_files(SourceScanner.SCENES_ROOT):
		scanned += 1
		var text := SourceScanner.read(path)
		var lines := text.split("\n")
		for i in lines.size():
			if regex.search(lines[i]) != null:
				fail(
					"%s:%d contains a CSG node; bake it to an ArrayMesh offline (I-10)"
					% [SourceScanner.short(path), i + 1]
				)
	check_true(true, "scanned %d scene files for CSG nodes" % scanned)


func test_no_scene_uses_a_concave_shape_on_a_dynamic_body() -> void:
	# ConcavePolygonShape3D is legal on static world geometry and forbidden on
	# anything that moves. A scene declaring one at all is worth flagging: the
	# streamed Ground Array and Static Volume colliders are built at runtime
	# from partition geometry, never authored into a scene file.
	var regex := SourceScanner.compile("ConcavePolygonShape3D")
	for path in SourceScanner.scene_files(SourceScanner.SCENES_ROOT):
		var lines := SourceScanner.read(path).split("\n")
		for i in lines.size():
			if regex.search(lines[i]) != null:
				fail(
					"%s:%d declares a ConcavePolygonShape3D (I-1)"
					% [SourceScanner.short(path), i + 1]
				)
	check_true(true, "scenes scanned for concave shapes")
