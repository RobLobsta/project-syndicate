extends TestCase
## What a physics frame gives the suite, and what the suite still does not get.
##
## Until this session every test ran inside a single [code]_process[/code]
## callback and the engine never stepped physics underneath it. That made an
## entire layer untestable — a solved force is only a number until the server
## integrates it — and it produced a wrong conclusion that was recorded and
## worked around for two sessions: that a query against the main world "answers
## nothing". It does answer. It answers against a [b]stale transform[/b], which
## looks identical to an empty space when the body you are looking for has been
## moved somewhere your query is not.
##
## The distinction matters because the two have opposite fixes. "The space is
## empty" says build your own space with
## [method PhysicsServer3D.space_create]. "The pose is stale" says step once.
## This file pins the real behaviour down so the next session inherits the
## measurement rather than the inference.

## The ground box's top surface, at the world origin plane.
const GROUND_TOP_Y: float = 0.0
const GROUND_HALF_HEIGHT: float = 2.0
const GROUND_SPAN_M: float = 60.0

## Where the ground body sits before anything moves it. A body added to the tree
## is registered at the identity transform, so this is the pose a query sees
## until a tick flushes the one it was actually given.
const UNMOVED_TOP_Y: float = GROUND_HALF_HEIGHT

const DROP_HEIGHT_M: float = 5.0
const CUBE_HALF_M: float = 0.5
## Ticks to fall 4.5 m and settle. Free fall alone is 0.96 s; the rest is the
## solver resolving the contact and the body going to sleep.
const SETTLE_TICKS: int = 150

var _nodes: Array[Node3D] = []


func after_all() -> void:
	for n: Node3D in _nodes:
		n.queue_free()
	_nodes.clear()


## ===== THE STALE-POSE FACT =============================================


func test_a_query_before_any_tick_answers_against_the_unmoved_pose() -> void:
	var ground := _ground()
	var space := EventBus.get_tree().root.world_3d.direct_space_state

	var before := _floor_hit_y(space)
	check_approx(
		before, UNMOVED_TOP_Y, "before a tick the ray finds the ground at its unmoved height"
	)
	check_ne(before, GROUND_TOP_Y, "which is not where the body was actually put")

	await physics_frames(1)

	check_approx(
		_floor_hit_y(space), GROUND_TOP_Y, "one tick flushes the pose and the ray agrees"
	)
	check_eq(ground.global_position.y, -GROUND_HALF_HEIGHT, "the node knew all along")


func test_a_shape_query_is_answered_in_the_same_frame_the_body_is_added() -> void:
	# The body is visible immediately — it is the transform that lags, not the
	# registration. Asserted separately from the ray because a shape query is
	# what the build lattice's interpenetration check of doc 02 §7.7 uses.
	_ground()
	var space := EventBus.get_tree().root.world_3d.direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	query.shape = sphere
	query.collision_mask = CollisionLayers.MASK_GROUND
	query.transform = Transform3D(Basis(), Vector3(0.0, UNMOVED_TOP_Y - 0.25, 0.0))
	check_false(
		space.intersect_shape(query, 4).is_empty(),
		"the shape query finds the body before any tick has run"
	)


## ===== INTEGRATION =====================================================


func test_a_body_falls_and_comes_to_rest_on_the_ground() -> void:
	# The claim the whole of tests/physics/ rests on: forces applied through the
	# server actually move something, and the result is observable from GDScript.
	_ground()
	var cube := _falling_cube(Vector3(6.0, DROP_HEIGHT_M, 0.0))
	await physics_frames(1)
	check_approx(
		cube.global_position.y, DROP_HEIGHT_M, "one tick has barely moved it", 0.01
	)

	await physics_frames(SETTLE_TICKS)
	check_approx(
		cube.global_position.y,
		GROUND_TOP_Y + CUBE_HALF_M,
		"it rests on the surface, one half-extent up",
		0.02
	)
	check_true(
		cube.linear_velocity.length() < 0.01, "and it has come to rest rather than still moving"
	)


func test_a_shape_cast_parented_to_a_body_reports_the_ground_under_it() -> void:
	# The exact mechanism doc 05 §6.1 uses for suspension: a ShapeCast3D carried
	# by the body, sweeping down. Asserted here on a bare cube so that a failure
	# in the motion layer's probes is distinguishable from a failure in the
	# engine feature they are built on.
	_ground()
	var cube := _falling_cube(Vector3(-6.0, DROP_HEIGHT_M, 0.0))
	var cast := ShapeCast3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.25
	cast.shape = sphere
	cast.target_position = Vector3(0.0, -2.0, 0.0)
	cast.collision_mask = CollisionLayers.MASK_GROUND
	cast.max_results = 1
	cube.add_child(cast)

	await physics_frames(SETTLE_TICKS)
	if not check_true(cast.is_colliding(), "the cast finds the ground beneath the settled body"):
		return
	check_approx(
		cast.get_collision_point(0).y, GROUND_TOP_Y, "at the ground's surface", 0.02
	)
	check_true(
		cast.get_collision_normal(0).dot(Vector3.UP) > 0.99, "with an upward normal"
	)


## ===== FIXTURES ========================================================


func _floor_hit_y(space: PhysicsDirectSpaceState3D) -> float:
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 8.0, 0.0), Vector3(0.0, -8.0, 0.0)
	)
	ray.collision_mask = CollisionLayers.MASK_GROUND
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


## A static slab on [constant CollisionLayers.LAYER_GROUND] whose top face is the
## world origin plane. Not a Dynamic Ground Array — document 09 owns that, and
## nothing here may pre-empt it. This is a test fixture and says so.
func _ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = CollisionLayers.LAYER_GROUND
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SPAN_M, GROUND_HALF_HEIGHT * 2.0, GROUND_SPAN_M)
	shape.shape = box
	body.add_child(shape)
	EventBus.get_tree().root.add_child(body)
	body.global_position = Vector3(0.0, GROUND_TOP_Y - GROUND_HALF_HEIGHT, 0.0)
	_nodes.append(body)
	return body


func _falling_cube(at: Vector3) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.collision_layer = CollisionLayers.LAYER_ASSEMBLY_HULL
	body.collision_mask = CollisionLayers.MASK_ASSEMBLY_HULL
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * (CUBE_HALF_M * 2.0)
	shape.shape = box
	body.add_child(shape)
	EventBus.get_tree().root.add_child(body)
	body.global_position = at
	_nodes.append(body)
	return body
