extends TestCase
## Enforces Architectural Invariant I-1: the Decoupled Collision Architecture.
##
## Physics geometry and visual geometry are separate, independently authored
## assets, and the simulation reads only the physics geometry. This is the
## invariant that lets art iterate without a balance review, and it fails
## quietly: a [CollisionShape3D] accidentally parented under a visual node
## produces a hitbox that moves with an animation, and nothing reports an error.
##
## Scenes are parsed as text. A [code].tscn[/code] node header carries its parent
## path, so the parent chain of every node is recoverable without instantiating
## anything.

const VISUAL_ROOT_NAME: String = "VisualRoot"

## Node types that must never appear beneath a VisualRoot.
const PHYSICS_TYPES: Array[String] = [
	"CollisionShape3D",
	"CollisionPolygon3D",
	"StaticBody3D",
	"RigidBody3D",
	"CharacterBody3D",
	"Area3D",
]


class SceneNode:
	extends RefCounted

	var name: String = ""
	var type: String = ""
	var parent: String = ""
	var line: int = 0


func test_no_physics_node_lives_under_a_visual_root() -> void:
	var scanned := 0
	for path in SourceScanner.scene_files(SourceScanner.SCENES_ROOT):
		scanned += 1
		for node in _parse_nodes(path):
			if not PHYSICS_TYPES.has(node.type):
				continue
			if not _is_under_visual_root(node):
				continue
			fail(
				"%s:%d — %s '%s' is under %s; physics never lives beneath a visual (I-1)"
				% [SourceScanner.short(path), node.line, node.type, node.name, VISUAL_ROOT_NAME]
			)
	check_true(true, "scanned %d scene files for visual/physics coupling" % scanned)


func test_src_never_derives_a_shape_from_a_mesh() -> void:
	# The runtime equivalent of the same mistake. ColliderProfile is the only
	# source of Assembly collision geometry.
	var patterns := PackedStringArray([
		"create_trimesh_collision",
		"create_convex_collision",
		"create_multiple_convex_collisions",
		"ConvexPolygonShape3D\\s*\\.\\s*new",
		"\\.create_from_mesh\\s*\\(",
	])
	for p: String in patterns:
		var regex := SourceScanner.compile(p)
		for path in SourceScanner.gd_files(SourceScanner.SRC_ROOT):
			for line in SourceScanner.match_lines(path, regex):
				fail(
					"%s:%d derives collision from mesh geometry (I-1)"
					% [SourceScanner.short(path), line]
				)
	check_true(true, "src/ scanned for mesh-derived collision")


func test_collider_primitives_are_restricted_to_the_four_permitted_kinds() -> void:
	var kinds := ColliderPrimitiveDef.PrimitiveKind.keys()
	check_eq(kinds.size(), 4, "exactly four primitive kinds are permitted")
	for expected: String in ["BOX", "CYLINDER", "CAPSULE", "SPHERE"]:
		check_true(kinds.has(expected), "PrimitiveKind must include %s" % expected)


func test_collider_primitive_ceiling_is_three() -> void:
	check_eq(
		ColliderProfile.MAX_PRIMITIVES_PER_PART,
		3,
		"docs/PART_DATA_SCHEMA.md §6.2 caps a part at three collision primitives"
	)


## Node headers of a text scene, in file order. Godot writes each as
## [code][node name="X" type="Y" parent="A/B"][/code]; the root has no parent
## attribute and a direct child of the root has [code]parent="."[/code].
func _parse_nodes(path: String) -> Array[SceneNode]:
	var out: Array[SceneNode] = []
	var header := SourceScanner.compile("^\\[node\\s+(?<attrs>.*)\\]\\s*$")
	var attr := SourceScanner.compile("(?<key>\\w+)\\s*=\\s*\"(?<value>[^\"]*)\"")
	var lines := SourceScanner.read(path).split("\n")
	for i in lines.size():
		var m := header.search(lines[i])
		if m == null:
			continue
		var node := SceneNode.new()
		node.line = i + 1
		for a in attr.search_all(m.get_string("attrs")):
			match a.get_string("key"):
				"name":
					node.name = a.get_string("value")
				"type":
					node.type = a.get_string("value")
				"parent":
					node.parent = a.get_string("value")
		out.append(node)
	return out


## A node is under a VisualRoot when that name appears as a path segment of its
## parent path, or when the node's own parent is literally the visual root.
func _is_under_visual_root(node: SceneNode) -> bool:
	if node.parent.is_empty() or node.parent == ".":
		return false
	for segment in node.parent.split("/"):
		if segment == VISUAL_ROOT_NAME:
			return true
	return false
