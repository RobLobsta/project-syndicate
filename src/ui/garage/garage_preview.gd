class_name GaragePreview
extends Node3D
## The 3D half of the garage: the Build Lattice, the Assembly standing on it, the
## orbit camera, and the ghost. Doc 11 §4's `GaragePreviewScene`, and doc 02 §6
## and §8 for everything it does with a pointer.
##
## [b]It owns no build state.[/b] The [BuildContext] belongs to [GarageScreen]
## and every placement goes through [PlacementValidator]; this class turns a
## screen position into a [PlacementCandidate] and draws what the answer was.
## That split is what stops the preview being a second, prettier validator —
## doc 02 §12 invariant 1 gives exactly one chain the right to accept a
## placement, and this is not it.
##
## [b]Meshes are driven by the bus, not by the caller.[/b] Architectural
## Invariant I-4 and the reading recorded in [code]LEARNED_FACTS.md[/code] §4:
## presentation is not on [BuildContext]. A commit emits
## [signal EventBusService.part_attached] and this class draws in response, which
## is the same wiring the match uses and the reason a part cannot be committed
## without appearing.

## ===== CAMERA ==========================================================

## Where the camera looks: the lattice origin cell, lifted so the frame is the
## build rather than the floor under it.
const FOCUS_HEIGHT_M: float = 0.9
const START_DISTANCE_M: float = 6.5
const MIN_DISTANCE_M: float = 2.0
const MAX_DISTANCE_M: float = 18.0
const ZOOM_STEP_M: float = 0.8
## Radians of orbit per pixel of mouse travel while [code]cam_orbit[/code] is
## held.
const ORBIT_RATE_RAD_PX: float = 0.006
## Pitch stops. Not ±90°: a camera looking straight down at a build has no
## silhouette to read, and one looking straight up is under the floor.
const MIN_PITCH_RAD: float = -0.15
const MAX_PITCH_RAD: float = 1.30
const START_YAW_RAD: float = 0.7
const START_PITCH_RAD: float = 0.42
const CAMERA_FOV_DEG: float = 55.0

## ===== THE LATTICE =====================================================

## Half-extent of the floor plate and of the drawn grid, in cells either side of
## the origin. The lattice is 48 cells across; a plate that size is 12 m of empty
## metal around a 2 m build, so the drawn region is the part of it a player uses.
const GRID_HALF_CELLS: int = 14
const FLOOR_THICKNESS_M: float = 0.4

const GRID_COLOUR := Color(0.42, 0.47, 0.55, 0.5)
const GRID_AXIS_COLOUR := Color(0.55, 0.62, 0.72, 0.85)

## ===== THE GHOST =======================================================

const GHOST_ALPHA_VALID: float = 0.45
const GHOST_ALPHA_REJECTED: float = 0.30

## How far the pointer ray is tested. Doc 02 §6.2.
const PICK_DISTANCE_M: float = 200.0

## Height of the build floor plane in assembly-local metres. Doc 02 §6.2's
## fallback surface, and the plane the lattice grid is drawn on: cell row
## [code]y = 4[/code] — the origin row — spans local y from 0 to one unit, so
## zero is the underside of the row a Core Module sits in.
const FLOOR_PLANE_Y: float = 0.0
## Below this the pointer ray is running along the floor plane rather than at it,
## and the intersection is either nowhere or everywhere.
const FLOOR_PARALLEL_EPSILON: float = 1e-4
## Answer from [method _floor_plane_hit] for a ray that never reaches the plane.
const NO_HIT := Vector3(INF, INF, INF)

## ===== PRESENTATION ====================================================

const SUN_EULER_DEG := Vector3(-48.0, -35.0, 0.0)
const SUN_ENERGY: float = 1.25
const SKY_TOP := Color("#1A2029")
const SKY_HORIZON := Color("#2E3742")
const FLOOR_ALBEDO := Color("#22272E")
const AMBIENT_ENERGY: float = 0.55

## The Assembly whose [signal EventBusService.part_attached] this preview draws.
## Assigned before the node enters the tree.
var assembly_id: int = 0

## The build being edited. Read, never written: [GarageScreen] owns it and every
## change to it goes through [PlacementValidator]. This class reads a committed
## part's cell and orientation to draw it, exactly as [AssemblyRuntime] reads its
## own states to do the same job in a match.
var context: BuildContext = null

var camera: Camera3D = null

## Slot -> its mesh. The same map [AssemblyRuntime] keeps, for the same reason:
## a removal has to find the node it drew, and finding it by name would be a
## string build per removal and a tree walk per lookup.
var _visuals: Dictionary = {}

var _focus: Node3D = null
var _ghost: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null
var _yaw_rad: float = START_YAW_RAD
var _pitch_rad: float = START_PITCH_RAD
var _distance_m: float = START_DISTANCE_M
var _orbiting: bool = false


func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_grid()
	_build_camera()
	_build_ghost()
	EventBus.part_attached.connect(_on_part_attached)
	EventBus.part_removed.connect(_on_part_removed)


func _exit_tree() -> void:
	EventBus.part_attached.disconnect(_on_part_attached)
	EventBus.part_removed.disconnect(_on_part_removed)


## ===== POINTER =========================================================


## Doc 02 §6, all four stages, from a position in this preview's viewport.
##
## Returns a resolved [PlacementCandidate] for [param def] at
## [param orientation_index], or null when the ray reaches nothing and when the
## anchor it reaches has no face the part can mate through. A null is an ordinary
## answer — the pointer is off the build — and never an error.
##
## [b]The floats end here.[/b] Invariant I-6: the ray, the hit and the normal are
## the only floating-point quantities in the placement path, and every one of
## them is quantised before it leaves this function. What the validator sees is
## an integer cell and an integer face.
func resolve_candidate(
	def: PartDefinition, orientation_index: int, screen_pos: Vector2
) -> PlacementCandidate:
	if camera == null or context == null:
		return null
	var origin := to_local(camera.project_ray_origin(screen_pos))
	var direction := (to_local(
		camera.project_ray_origin(screen_pos) + camera.project_ray_normal(screen_pos)
	) - origin).normalized()

	var face := Vector3i.ZERO
	var anchor := Vector3i.ZERO
	var hit := _query_proxies(origin, direction)
	if hit.is_empty():
		# Doc 02 §6.2's fallback: the build floor plane, so that the first part of
		# an empty build has somewhere to go. It answers the plane's own up face,
		# which is the face a part standing on the floor mates through.
		var floor_point := _floor_plane_hit(origin, direction)
		if floor_point == NO_HIT:
			return null
		face = Vector3i.UP
		anchor = _anchor_cell(floor_point, face)
	else:
		face = dominant_axis(hit["normal"] as Vector3)
		if face == Vector3i.ZERO:
			return null
		anchor = _anchor_cell(hit["position"] as Vector3, face)

	var origin_cell := solve_origin(def, orientation_index, anchor, face)
	if origin_cell == NO_ORIGIN:
		return null
	# The occupancy and mating checks are the validator's and this must not
	# pre-empt them. What is tested here is only that the candidate is a candidate
	# at all: a cell outside the lattice cannot be handed to a chain whose first
	# step indexes an array with it.
	if not LatticeMath.in_bounds(origin_cell):
		return null
	return PlacementCandidate.create(def, origin_cell, orientation_index)


## Doc 02 §6.2's query, against the build proxies in the context's own space.
##
## [b]Not the world's space.[/b] [method BuildContext.with_physics] gives the
## build its own, on [constant CollisionLayers.LAYER_BUILD_GHOST], so that a
## garage open behind a running match cannot perturb it — and so the pointer has
## to be asked there rather than of the viewport the picture is drawn in. The ray
## is converted into assembly-local coordinates for the same reason: the proxies
## are placed at [method PlacementCandidate.local_transform], which is a lattice
## pose and not a world one.
func _query_proxies(local_origin: Vector3, local_direction: Vector3) -> Dictionary:
	var space := context.space_state()
	if space == null:
		return {}
	var params := PhysicsRayQueryParameters3D.create(
		local_origin, local_origin + local_direction * PICK_DISTANCE_M
	)
	params.collision_mask = CollisionLayers.MASK_BUILD_GHOST
	params.collide_with_areas = false
	return space.intersect_ray(params)


## Where the ray crosses the build floor plane, or [constant NO_HIT] when it runs
## parallel to it or away from it.
static func _floor_plane_hit(local_origin: Vector3, local_direction: Vector3) -> Vector3:
	if absf(local_direction.y) < FLOOR_PARALLEL_EPSILON:
		return NO_HIT
	var t := (FLOOR_PLANE_Y - local_origin.y) / local_direction.y
	if t <= 0.0:
		return NO_HIT
	return local_origin + local_direction * t


## The committed slot under [param screen_pos], or
## [constant SyndicateConstants.INVALID_SLOT].
##
## Read from the build proxy's own body rather than from a mesh: the proxies are
## the geometry doc 02 §7.7 already queries, and picking off a visual would make
## which part a player can remove depend on how far an artist has promoted its
## mesh.
func slot_at(screen_pos: Vector2) -> int:
	if camera == null or context == null:
		return SyndicateConstants.INVALID_SLOT
	var origin := to_local(camera.project_ray_origin(screen_pos))
	var direction := (to_local(
		camera.project_ray_origin(screen_pos) + camera.project_ray_normal(screen_pos)
	) - origin).normalized()
	var hit := _query_proxies(origin, direction)
	if hit.is_empty():
		return SyndicateConstants.INVALID_SLOT
	var rid: RID = hit["rid"]
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		if context.proxy_body(slot) == rid:
			return slot
	return SyndicateConstants.INVALID_SLOT


## Doc 02 §6.3. The mating face is the dominant axis of the surface normal.
static func dominant_axis(n: Vector3) -> Vector3i:
	var ax := absf(n.x)
	var ay := absf(n.y)
	var az := absf(n.z)
	if ax >= ay and ax >= az:
		return Vector3i(signi(int(signf(n.x))), 0, 0)
	if ay >= az:
		return Vector3i(0, signi(int(signf(n.y))), 0)
	return Vector3i(0, 0, signi(int(signf(n.z))))


## Answer from [method solve_origin] when the part has no attachment node facing
## the way the anchor needs. Out of the lattice by construction, and an int32
## sentinel rather than a 64-bit one because a [Vector3i] component wraps
## silently (LEARNED_FACTS.md §1 fact 5).
const NO_ORIGIN := Vector3i(-2147483647, -2147483647, -2147483647)


## Doc 02 §6.4. The anchor cell must coincide with one of the candidate's own
## cells — the cell adjacent to the attachment node whose rotated face is
## [code]−face[/code] — so the origin is solved by subtraction.
##
## When several nodes share the required face, the lowest-indexed one wins.
## §6.4's rule is "nearest the raw hit point", which is a float comparison used
## to disambiguate between already-legal integer candidates; the first is chosen
## here instead, because a part with two nodes on one face is not yet authored
## and a tie-break nothing can exercise is a tie-break nobody can test.
static func solve_origin(
	def: PartDefinition, orientation_index: int, anchor_cell: Vector3i, mating_face: Vector3i
) -> Vector3i:
	var want := -mating_face
	for node: AttachmentNodeDef in def.attachment_nodes:
		if OrientationTable.rotate_face(orientation_index, node.face_normal) != want:
			continue
		return anchor_cell - OrientationTable.rotate_cell(orientation_index, node.cell)
	return NO_ORIGIN


## Doc 02 §6.3. The cell just outside the hit surface.
##
## The hit point is nudged a quarter of a cell back along the normal before it is
## quantised, which is what stops a hit exactly on a cell boundary landing in the
## cell on the far side of it.
static func _anchor_cell(local_hit: Vector3, face: Vector3i) -> Vector3i:
	var inside := local_hit - Vector3(face) * (SyndicateConstants.LATTICE_UNIT_M * 0.25)
	return LatticeMath.local_to_cell(inside) + face


## ===== THE GHOST =======================================================


## Doc 02 §8. Shows [param def] at [param candidate]'s pose in the colour of
## [param reject].
##
## The ghost never enters the occupancy array, never spawns a collider and never
## joins the Chassis Graph. Its layers are zero because it is a
## [MeshInstance3D] and cannot carry one.
func show_ghost(
	def: PartDefinition, candidate: PlacementCandidate, reject: PlacementValidator.Reject
) -> void:
	var mesh: Mesh = ProxyMeshCache.get_or_build(def)
	if mesh == null or candidate == null:
		hide_ghost()
		return
	_ghost.mesh = mesh
	_ghost.transform = PartMeshFactory.pose(
		def.visual_profile, candidate.origin_cell, candidate.orientation_index
	)
	var accepted := reject == PlacementValidator.Reject.NONE
	var colour := UiTokens.ACCENT_SECONDARY if accepted else UiTokens.DANGER
	colour.a = GHOST_ALPHA_VALID if accepted else GHOST_ALPHA_REJECTED
	_ghost_material.albedo_color = colour
	_ghost.visible = true


func hide_ghost() -> void:
	_ghost.visible = false


## ===== CAMERA ==========================================================


## Consumes doc 11 §7.1's [code]cam_orbit[/code], [code]cam_zoom_in[/code] and
## [code]cam_zoom_out[/code]. Returns whether the event was used, so the garage
## can leave a click that orbited the camera out of the placement path.
##
## §7.1 always intended these for the garage: the match camera took four
## analogue [code]cam_look_*[/code] actions instead, because [code]cam_orbit[/code]
## is a single action and cannot express two axes.
func handle_camera_input(event: InputEvent) -> bool:
	if event.is_action_pressed(&"cam_orbit"):
		_orbiting = true
		return true
	if event.is_action_released(&"cam_orbit"):
		_orbiting = false
		return true
	if event.is_action_pressed(&"cam_zoom_in"):
		_set_distance(_distance_m - ZOOM_STEP_M)
		return true
	if event.is_action_pressed(&"cam_zoom_out"):
		_set_distance(_distance_m + ZOOM_STEP_M)
		return true
	if event.is_action_pressed(&"cam_focus_selection"):
		_yaw_rad = START_YAW_RAD
		_pitch_rad = START_PITCH_RAD
		_set_distance(START_DISTANCE_M)
		return true
	if _orbiting and event is InputEventMouseMotion:
		var motion := (event as InputEventMouseMotion).relative
		_yaw_rad -= motion.x * ORBIT_RATE_RAD_PX
		_pitch_rad = clampf(
			_pitch_rad + motion.y * ORBIT_RATE_RAD_PX, MIN_PITCH_RAD, MAX_PITCH_RAD
		)
		_place_camera()
		return true
	return false


func _set_distance(metres: float) -> void:
	_distance_m = clampf(metres, MIN_DISTANCE_M, MAX_DISTANCE_M)
	_place_camera()


func _place_camera() -> void:
	var offset := Vector3(
		sin(_yaw_rad) * cos(_pitch_rad), sin(_pitch_rad), cos(_yaw_rad) * cos(_pitch_rad)
	) * _distance_m
	camera.global_position = _focus.global_position + offset
	camera.look_at(_focus.global_position, Vector3.UP)


## ===== CONSTRUCTION ====================================================


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	sky_material.ground_bottom_color = FLOOR_ALBEDO
	sky_material.ground_horizon_color = SKY_HORIZON

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(
		deg_to_rad(SUN_EULER_DEG.x), deg_to_rad(SUN_EULER_DEG.y), deg_to_rad(SUN_EULER_DEG.z)
	)
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	add_child(sun)


## The plate a build stands on.
##
## [b]It carries no collision at all.[/b] Doc 02 §6.2 tests the pointer against
## the build proxies and falls back to the floor [i]plane[/i], and the proxies
## live in the context's own physics space rather than in the world this picture
## is drawn in. A collider here would be in the wrong space to be hit by that
## query and would answer a second, disagreeing one — so the floor is geometry a
## player can see and the plane is the thing the pointer meets.
func _build_floor() -> void:
	var half := float(GRID_HALF_CELLS) * SyndicateConstants.LATTICE_UNIT_M

	var plate := MeshInstance3D.new()
	plate.name = "FloorPlate"
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(half * 2.0, FLOOR_THICKNESS_M, half * 2.0)
	plate.mesh = plate_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = FLOOR_ALBEDO
	material.roughness = 0.95
	plate.material_override = material
	plate.layers = RenderLayers.LAYER_GARAGE_ONLY
	add_child(plate)
	plate.position = Vector3(0.0, FLOOR_PLANE_Y - FLOOR_THICKNESS_M * 0.5, 0.0)


## The Build Lattice, drawn one line per cell boundary on the floor plane.
##
## It is what makes the quarter-metre unit visible. Without it a player is
## dragging parts onto an untextured plate and cannot see why a placement snapped
## where it did, which reads as the snapping being wrong.
func _build_grid() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var u := SyndicateConstants.LATTICE_UNIT_M
	var half := float(GRID_HALF_CELLS) * u
	var y := FLOOR_PLANE_Y
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for i: int in range(-GRID_HALF_CELLS, GRID_HALF_CELLS + 1):
		var t := float(i) * u
		var colour := GRID_AXIS_COLOUR if i == 0 else GRID_COLOUR
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(t, y, -half))
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(t, y, half))
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(-half, y, t))
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(half, y, t))
	mesh.surface_end()

	var node := MeshInstance3D.new()
	node.name = "LatticeGrid"
	node.mesh = mesh
	node.layers = RenderLayers.LAYER_GARAGE_ONLY
	add_child(node)


func _build_camera() -> void:
	_focus = Node3D.new()
	_focus.name = "Focus"
	add_child(_focus)
	_focus.position = Vector3(0.0, FOCUS_HEIGHT_M, 0.0)

	camera = Camera3D.new()
	camera.name = "PreviewCamera"
	camera.fov = CAMERA_FOV_DEG
	camera.current = true
	add_child(camera)
	_place_camera()


func _build_ghost() -> void:
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = UiTokens.ACCENT_SECONDARY

	_ghost = MeshInstance3D.new()
	_ghost.name = "PlacementGhost"
	_ghost.material_override = _ghost_material
	_ghost.layers = RenderLayers.LAYER_GARAGE_ONLY
	_ghost.visible = false
	add_child(_ghost)


## ===== THE BUILD =======================================================


func _on_part_attached(changed_id: int, slot: int) -> void:
	if changed_id != assembly_id or context == null:
		return
	var st := context.state(slot)
	if st == null:
		return
	var def := PartRegistry.definition(st.part_def_id)
	if def == null:
		return
	var node := PartMeshFactory.build(
		def, st.integrity_band, st.origin_cell, st.orientation_index
	)
	if node == null:
		return
	node.name = "part_s%03d" % slot
	add_child(node)
	_visuals[slot] = node


func _on_part_removed(changed_id: int, slot: int) -> void:
	if changed_id != assembly_id:
		return
	var node: MeshInstance3D = _visuals.get(slot, null)
	if node != null and is_instance_valid(node):
		remove_child(node)
		node.queue_free()
	_visuals.erase(slot)


## Slots this preview is currently drawing. Diagnostics and tests: the claim the
## bus wiring makes is that this set and the context's committed set are the
## same one, and nothing else in the class asserts it.
func drawn_slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for slot: int in _visuals.keys():
		out.append(slot)
	out.sort()
	return out
