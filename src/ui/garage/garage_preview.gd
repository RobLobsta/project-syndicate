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
## Degrees of orbit per second at full stick deflection, for the four analogue
## [code]cam_look_*[/code] actions.
##
## The same figure [ChaseCamera] turns at, deliberately: a player who learns how
## fast the right stick swings the camera in a match should not have to relearn it
## in the garage. It is published there — doc 11 §13.6's `STICK_DEG_PER_SECOND` —
## and read from there, because two copies of a feel constant is how the two
## screens end up feeling different.
const ORBIT_STICK_DEG_S: float = ChaseCamera.STICK_DEG_PER_SECOND

## ===== LOOK INPUT ======================================================
## Doc 11 §7.1's analogue camera actions. They carry no keyboard binding — a mouse
## produces motion and Godot's [InputMap] cannot bind a motion event to an action
## — so on a keyboard these four are always zero and this costs four strength
## lookups a frame.

const ACTION_LOOK_LEFT: StringName = &"cam_look_left"
const ACTION_LOOK_RIGHT: StringName = &"cam_look_right"
const ACTION_LOOK_UP: StringName = &"cam_look_up"
const ACTION_LOOK_DOWN: StringName = &"cam_look_down"

## ===== THE PAD CURSOR ==================================================
## Doc 11 §7.3. A controller has no pointer, and doc 02 §6's whole placement chain
## starts from one — so the pad is given a virtual pointer in this viewport's own
## coordinates and everything downstream is unchanged. That is the point of doing
## it this way rather than with a lattice cursor: the mouse and the stick resolve
## a candidate through the identical [method resolve_candidate], so a pad cannot
## place something a mouse could not.

const ACTION_CURSOR_LEFT: StringName = &"build_cursor_left"
const ACTION_CURSOR_RIGHT: StringName = &"build_cursor_right"
const ACTION_CURSOR_UP: StringName = &"build_cursor_up"
const ACTION_CURSOR_DOWN: StringName = &"build_cursor_down"

## Pixels per second the cursor travels at full stick deflection, against a
## 1080-unit-tall viewport. Scaled by the viewport's actual height so the cursor
## crosses the view in the same time on every screen — a fixed pixel rate is four
## times slower to cross a 4K view than a 1080p one.
const CURSOR_RATE_PX_S: float = 900.0
const CURSOR_REFERENCE_HEIGHT_PX: float = 1080.0

## Emitted when the stick has moved the cursor. [GarageScreen] drives its ghost
## and its inspector from this, exactly as it does from mouse motion — which is
## what stops the pad path being a second, quieter copy of the placement chain.
signal pad_cursor_moved(position: Vector2)
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
## Doc 02 §10's mirror, drawn fainter than the placement the pointer is on.
## Both are the player's placement and only one is under the cursor, so the
## difference has to be visible without either reading as rejected — which is
## what the [constant UiTokens.DANGER] tint is for and this is not.
const GHOST_ALPHA_MIRROR: float = 0.24

## Wash laid over the part the pointer is on. A [member
## GeometryInstance3D.material_overlay] draws the mesh a second time unshaded, so
## it reads as the part lighting up rather than as the part changing colour —
## which matters because a part's colour is doc 13 §2.1's class tint and is
## carrying information the highlight must not overwrite.
##
## Faint on purpose. The inspector already says what the part is; this only has
## to answer "which one is that", and a highlight strong enough to be a selection
## would read as one on a screen where nothing is selectable.
const HOVER_ALPHA: float = 0.18

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

## ===== READING THE BUILD ===============================================
##
## A garage lit by one sun over a dark sky is a garage in which half of every
## part is unlit, and the sky is what the ambient term samples — so the shaded
## faces of a build sitting inside these colours fall to near black and the
## Assembly reads as one silhouette rather than as parts. That is not a taste
## question: doc 13 §2.1's class tints exist so a player can see where their
## Prime Mover is, and a tint nothing illuminates carries no information at all.
##
## The fix is two lights and a floor bounce rather than brighter tints, because
## brighter tints would wash out the sunlit faces to fix the shaded ones.

const AMBIENT_ENERGY: float = 0.9
## A cool fill from behind and to the other side, at a fraction of the key's
## energy. Enough to separate two adjacent shaded faces; not enough to flatten
## the form, which is what a fill matched to its key does.
const FILL_EULER_DEG := Vector3(-16.0, 138.0, 0.0)
const FILL_ENERGY: float = 0.45
const FILL_COLOUR := Color("#8FA6C4")
## Bounced up off the plate, so a part's underside is not the darkest surface on
## the screen. A build is looked at from slightly above, and its undersides are
## where the Motive Assemblies are.
const BOUNCE_EULER_DEG := Vector3(62.0, -10.0, 0.0)
const BOUNCE_ENERGY: float = 0.22
const BOUNCE_COLOUR := Color("#6E7686")

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
var _mirror_ghost: MeshInstance3D = null
var _mirror_material: StandardMaterial3D = null
var _hover_material: StandardMaterial3D = null
## Slot the wash is on, or [constant SyndicateConstants.INVALID_SLOT]. Held so a
## pointer moving across one part writes nothing, and so a part removed while
## highlighted does not leave the map naming a mesh that has gone.
var _hovered_slot: int = SyndicateConstants.INVALID_SLOT
var _yaw_rad: float = START_YAW_RAD
var _pitch_rad: float = START_PITCH_RAD
var _distance_m: float = START_DISTANCE_M
var _orbiting: bool = false
## Doc 11 §7.3's virtual pointer, in this preview's viewport coordinates.
var _pad_cursor: Vector2 = Vector2.ZERO
var _pad_cursor_placed: bool = false


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


## Orbits the camera on the right stick.
##
## [b]A poll rather than an event handler, and it is the only way a stick can
## drive this.[/b] [method handle_camera_input] orbits on
## [InputEventMouseMotion], which arrives only while the pointer moves; a stick
## held at deflection produces no further events at all, so an event-driven orbit
## sits still for a player who is holding it over. That left the garage with no
## camera control on a controller whatsoever — doc 11 §7.1 published "Right Stick"
## against `cam_orbit` and `cam_orbit` is a single action that cannot express two
## axes, which is why §13.6 added these four for the match camera.
##
## This is presentation and Architectural Invariant I-4 is untouched: the frame
## callback reads two input axes and writes a camera pose. Nothing structural is
## polled, and a frame in which the stick is centred does no work beyond four
## strength lookups.
func _process(dt: float) -> void:
	_orbit_on_stick(dt)
	_move_cursor_on_stick(dt)


func _orbit_on_stick(dt: float) -> void:
	var stick := Vector2(
		ControlSystem.axis(ACTION_LOOK_LEFT, ACTION_LOOK_RIGHT),
		ControlSystem.axis(ACTION_LOOK_UP, ACTION_LOOK_DOWN)
	)
	if stick.is_zero_approx():
		return
	# The same signs the drag path above uses, so the stick and the mouse orbit the
	# build the same way round rather than the player learning two conventions on
	# one screen.
	var step := deg_to_rad(ORBIT_STICK_DEG_S) * dt
	_yaw_rad -= stick.x * step
	_pitch_rad = clampf(_pitch_rad + stick.y * step, MIN_PITCH_RAD, MAX_PITCH_RAD)
	_place_camera()


## Doc 11 §7.3's pad cursor: the left stick moves a virtual pointer across this
## preview's viewport, clamped to it.
func _move_cursor_on_stick(dt: float) -> void:
	var stick := Vector2(
		ControlSystem.axis(ACTION_CURSOR_LEFT, ACTION_CURSOR_RIGHT),
		ControlSystem.axis(ACTION_CURSOR_UP, ACTION_CURSOR_DOWN)
	)
	if stick.is_zero_approx():
		return
	var view := viewport_size()
	if view.y <= 0.0:
		return
	# Scaled by the view's height, so the cursor takes the same time to cross a
	# 4K viewport as a 1080p one. A rate in raw pixels is a control that gets
	# slower as the player's monitor gets better.
	var rate := CURSOR_RATE_PX_S * view.y / CURSOR_REFERENCE_HEIGHT_PX
	_pad_cursor = (_pad_cursor + stick * rate * dt).clamp(Vector2.ZERO, view)
	pad_cursor_moved.emit(_pad_cursor)


## Where the pad's virtual pointer is, in this preview's viewport coordinates.
##
## Centred on first use rather than at construction: the viewport has no size
## until it has been laid out, and a cursor initialised at (0, 0) starts in the
## corner of the screen where there is nothing to point at.
func pad_cursor() -> Vector2:
	if not _pad_cursor_placed:
		var view := viewport_size()
		if view.y > 0.0:
			_pad_cursor = view * 0.5
			_pad_cursor_placed = true
	return _pad_cursor


## The size of the viewport this preview draws into, or zero before layout.
func viewport_size() -> Vector2:
	var view := get_viewport()
	if view == null:
		return Vector2.ZERO
	return Vector2(view.get_visible_rect().size)


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


## Doc 02 §10's mirror of the placement [method show_ghost] is showing.
##
## A second ghost rather than a marker, because what a player needs to know
## before they click is what the second part will [i]be[/i]: mirroring rotates
## the part as well as moving it, and on a Motive Assembly that is the difference
## between a contact that drives inboard and one that drives into the hull.
func show_mirror_ghost(
	def: PartDefinition, candidate: PlacementCandidate, reject: PlacementValidator.Reject
) -> void:
	var mesh: Mesh = ProxyMeshCache.get_or_build(def)
	if mesh == null or candidate == null:
		hide_mirror_ghost()
		return
	_mirror_ghost.mesh = mesh
	_mirror_ghost.transform = PartMeshFactory.pose(
		def.visual_profile, candidate.origin_cell, candidate.orientation_index
	)
	var accepted := reject == PlacementValidator.Reject.NONE
	var colour := UiTokens.ACCENT_SECONDARY if accepted else UiTokens.DANGER
	colour.a = GHOST_ALPHA_MIRROR
	_mirror_material.albedo_color = colour
	_mirror_ghost.visible = true


func hide_mirror_ghost() -> void:
	_mirror_ghost.visible = false


## Lights up [param slot], and takes the wash off whatever had it.
##
## [constant SyndicateConstants.INVALID_SLOT] clears it. Nothing else in the
## garage tells a player which part the inspector is describing — the dock names
## a class and a set of figures, and a build carries four parts of one class —
## so without this the inspector is answering a question the player cannot ask
## precisely.
func highlight_slot(slot: int) -> void:
	if slot == _hovered_slot:
		return
	var previous: MeshInstance3D = _visuals.get(_hovered_slot, null)
	if previous != null and is_instance_valid(previous):
		previous.material_overlay = null
	_hovered_slot = slot
	var node: MeshInstance3D = _visuals.get(slot, null)
	if node != null:
		node.material_overlay = _hover_material


## The slot the wash is on. Diagnostics and tests.
func highlighted_slot() -> int:
	return _hovered_slot


## Hides both. The mirror never stands on its own: it is drawn beside a placement
## and goes when that placement goes.
func hide_ghost() -> void:
	_ghost.visible = false
	_mirror_ghost.visible = false


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

	var sun := _directional("Sun", SUN_EULER_DEG, SUN_ENERGY, Color.WHITE)
	# One shadow caster. A fill that casts is a second set of shadows crossing the
	# first, which reads as dirt on the model.
	sun.shadow_enabled = true
	add_child(sun)
	add_child(_directional("Fill", FILL_EULER_DEG, FILL_ENERGY, FILL_COLOUR))
	add_child(_directional("Bounce", BOUNCE_EULER_DEG, BOUNCE_ENERGY, BOUNCE_COLOUR))


static func _directional(
	node_name: String, euler_deg: Vector3, energy: float, colour: Color
) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = node_name
	light.rotation = Vector3(
		deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)
	)
	light.light_energy = energy
	light.light_color = colour
	return light


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
	_hover_material = _new_ghost_material()
	var wash := UiTokens.ACCENT_SECONDARY
	wash.a = HOVER_ALPHA
	_hover_material.albedo_color = wash
	_ghost_material = _new_ghost_material()
	_ghost = _new_ghost_node("PlacementGhost", _ghost_material)
	_mirror_material = _new_ghost_material()
	_mirror_ghost = _new_ghost_node("MirrorGhost", _mirror_material)


static func _new_ghost_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = UiTokens.ACCENT_SECONDARY
	return mat


func _new_ghost_node(node_name: String, material: StandardMaterial3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.material_override = material
	node.layers = RenderLayers.LAYER_GARAGE_ONLY
	node.visible = false
	add_child(node)
	return node


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
	# The wash is keyed on the slot, and a slot that has just been freed is one
	# the next placement may be handed (lowest-free-first). Forgetting it here is
	# what stops a new part arriving already lit.
	if slot == _hovered_slot:
		_hovered_slot = SyndicateConstants.INVALID_SLOT


## Slots this preview is currently drawing. Diagnostics and tests: the claim the
## bus wiring makes is that this set and the context's committed set are the
## same one, and nothing else in the class asserts it.
func drawn_slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for slot: int in _visuals.keys():
		out.append(slot)
	out.sort()
	return out
