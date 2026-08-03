class_name ChaseCamera
extends Camera3D
## The match camera, owned by [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §13.
##
## [b]It follows [code]VisualRoot[/code], never [code]ChassisBody[/code].[/b]
## §13.2 is the reasoning and it is the one thing here that is easy to get
## backwards: doc 05 §10.1 pins [code]physics_jitter_fix[/code] at zero, so the
## body's transform changes 60 times a second and holds still in between, while
## [AssemblyInterpolator] writes [code]VisualRoot[/code] every render frame at
## the physics interpolation fraction. A camera reading the body samples the
## un-interpolated value: at 60 Hz the two agree and nothing is visibly wrong, and
## above 60 Hz the hull is drawn smoothly while the camera steps between 60
## poses, so the world shudders around a steady vehicle. That is the exact
## inverse of the artefact the interpolator exists to remove, and it is much
## harder to diagnose, because the vehicle looks perfect and everything else
## looks broken.
##
## Architectural Invariant I-1: this is a [Camera3D] and never a
## [CollisionObject3D]. §13.7's ground avoidance is a shape [i]cast[/i] — it
## reads the world and presents nothing to it, the same distinction
## [method AssemblyRuntime._build_motive_probes] draws for suspension probes.
##
## The camera declares [code]_process[/code] and is allowlisted in
## [code]tests/arch/test_no_polling.gd[/code]. Invariant I-4 is about structural
## state, and nothing here reads integrity, connectivity, or attachment: a camera
## is per-render-frame work by definition, and there is no event that means "the
## player is looking somewhere else now".

## ===== FRAMING (§13.5) =================================================

const CHASE_DISTANCE_BASE_M: float = 6.0
const CHASE_DISTANCE_PER_RADIUS: float = 2.1
const CHASE_DISTANCE_MAX_M: float = 34.0
const CHASE_HEIGHT_PER_RADIUS: float = 0.75
const CHASE_HEIGHT_MIN_M: float = 1.6

const PITCH_DEFAULT_DEG: float = -12.0
const PITCH_MIN_DEG: float = -72.0
## Deliberately less than the down limit: the useful information in this game is
## on the ground, and a camera that can point at the sky spends travel budget
## somewhere a player never needs it.
const PITCH_MAX_DEG: float = 34.0

const ZOOM_MIN: float = 0.55
const ZOOM_MAX: float = 2.30
const ZOOM_STEP: float = 0.14

const FOV_BASE_DEG: float = 68.0
const FOV_SPEED_GAIN_DEG: float = 12.0
const FOV_SPEED_REFERENCE_MPS: float = 28.0

## ===== RATES (§13.5) ===================================================
## Every rate is a hertz applied as [code]1 - exp(-rate * dt)[/code], never a
## per-frame alpha. A raw alpha is frame-rate dependent — the same 0.15 settles
## four times faster at 240 Hz than at 60 — so the camera would feel different on
## different machines while every simulated quantity stayed identical.

const HEADING_LAG_HZ: float = 3.2
const POSITION_LAG_HZ: float = 14.0
const LOOK_RECENTRE_HZ: float = 1.4
const COLLISION_RELEASE_HZ: float = 6.0

## ===== LOOK INPUT (§13.6) ==============================================

const ACTION_LOOK_LEFT: StringName = &"cam_look_left"
const ACTION_LOOK_RIGHT: StringName = &"cam_look_right"
const ACTION_LOOK_UP: StringName = &"cam_look_up"
const ACTION_LOOK_DOWN: StringName = &"cam_look_down"
const ACTION_ZOOM_IN: StringName = &"cam_zoom_in"
const ACTION_ZOOM_OUT: StringName = &"cam_zoom_out"
const ACTION_TOGGLE_VIEW: StringName = &"cam_toggle_view"
const ACTION_FOCUS: StringName = &"cam_focus_selection"

const MOUSE_DEG_PER_PIXEL: float = 0.11
const STICK_DEG_PER_SECOND: float = 165.0
const LOOK_YAW_LIMIT_DEG: float = 120.0

## ===== GEOMETRY (§13.4, §13.7, §13.8) ==================================

## Above this |dot| against world up the hull's forward has no meaningful
## horizontal projection, and the camera holds its previous heading rather than
## snapping to whatever the projection produces.
const HEADING_DEGENERATE_DOT: float = 0.985

const COLLISION_PROBE_RADIUS_M: float = 0.4
const COLLISION_MARGIN_M: float = 0.3
## Floor on the pulled-in distance, so the camera can never coincide with the
## point it looks at.
const MIN_DISTANCE_M: float = 0.8

const AIM_RAY_LENGTH_M: float = 2000.0
## Where the aim point goes when the ray hits nothing. A mount handed
## [constant Vector3.ZERO] does not decline to fire — it aims at the world origin
## and shoots the ground.
const AIM_FALLBACK_RANGE_M: float = 220.0

## §13.2: after [constant AssemblyInterpolator.VISUAL_PROCESS_PRIORITY].
const CAMERA_PROCESS_PRIORITY: int = 2000

enum Mode { CHASE = 0, ORBIT = 1 }

## What the camera follows. Set to an [AssemblyRuntime]'s [code]visual_root[/code]
## and never to its body.
var target: Node3D = null

## Half the Assembly's diagonal extent, in metres. Scales the follow distance,
## because a lattice build has no fixed silhouette: the shipped wheeled recipe is
## about 3 m long and a forty-part build is several times that, and one fixed
## distance either buries the camera in the hull or strands it in the sky.
var bounding_radius_m: float = 2.0

var mode: Mode = Mode.CHASE

## Excluded from the aim ray, so a player aims across their own hull rather than
## having the reticle snap to their own armour (doc 07 §3).
var own_body_rid: RID = RID()

var _heading_rad: float = 0.0
var _look_yaw_rad: float = 0.0
var _look_pitch_rad: float = deg_to_rad(PITCH_DEFAULT_DEG)
var _zoom: float = 1.0
var _distance_scale: float = 1.0

var _mouse_delta: Vector2 = Vector2.ZERO
var _position: Vector3 = Vector3.ZERO
var _has_position: bool = false

var _prev_target_pos: Vector3 = Vector3.ZERO
var _speed_mps: float = 0.0

var _probe_shape: SphereShape3D = null

## Whether the last [method aim_point] ended on an Assembly hull. Written there
## and read by [MatchScreen]; see [member HudFrame.target_acquired].
var _aim_on_hull: bool = false


func _ready() -> void:
	process_priority = CAMERA_PROCESS_PRIORITY
	cull_mask = RenderLayers.CULL_MATCH_CAMERA
	fov = FOV_BASE_DEG
	_probe_shape = SphereShape3D.new()
	_probe_shape.radius = COLLISION_PROBE_RADIUS_M
	if target != null:
		_heading_rad = _hull_heading(target.global_transform.basis, 0.0)
		_prev_target_pos = target.global_position


## §13.6. Mouse motion is the one input in the project read outside
## [InputMap], and it is not the raw-key read CLAUDE.md §7.3 rule 1 forbids:
## Godot cannot bind a motion event to an action at all, so there is no action to
## read and no rebind to respect. Sensitivity is the rebindable quantity and it
## lives in [code]SyndicateSettings[/code] with the other driver preferences.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if InputMethod.mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			return
		# Accumulated rather than applied: several motion events can arrive
		# between two render frames, and applying each one separately makes the
		# sensitivity depend on the mouse's polling rate.
		_mouse_delta += (event as InputEventMouseMotion).relative


func _process(dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_read_discrete_input()
	_accumulate_look(dt)

	var pivot := target.global_position
	_speed_mps = (pivot - _prev_target_pos).length() / maxf(dt, SyndicateConstants.EPSILON_LINEAR)
	_prev_target_pos = pivot

	var yaw := _solve_yaw(dt)
	var desired := _desired_position(pivot, yaw)
	var resolved := _avoid_ground(pivot, desired, dt)

	if not _has_position:
		_position = resolved
		_has_position = true
	else:
		_position = _position.lerp(resolved, _lag(POSITION_LAG_HZ, dt))

	global_position = _position
	look_at(pivot + Vector3.UP * _eye_height(), Vector3.UP)
	fov = (
		FOV_BASE_DEG
		+ FOV_SPEED_GAIN_DEG * clampf(_speed_mps / FOV_SPEED_REFERENCE_MPS, 0.0, 1.0)
	)


## World position the player is aiming at. §13.8, and the sole producer of the
## aim point doc 07 §3 consumes.
##
## Also the sole producer of [method aim_on_hull], because the two answers come
## out of one ray and asking twice would be a second query per tick for a fact
## the first one already had.
func aim_point() -> Vector3:
	_aim_on_hull = false
	var vp := get_viewport()
	if vp == null:
		return global_position - global_transform.basis.z * AIM_FALLBACK_RANGE_M
	var centre := vp.get_visible_rect().size * 0.5
	var origin := project_ray_origin(centre)
	var dir := project_ray_normal(centre)
	var world := get_world_3d()
	if world == null:
		return origin + dir * AIM_FALLBACK_RANGE_M
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * AIM_RAY_LENGTH_M)
	q.collision_mask = CollisionLayers.MASK_AIM_TRACE
	if own_body_rid.is_valid():
		q.exclude = [own_body_rid]
	var hit := world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return origin + dir * AIM_FALLBACK_RANGE_M
	_aim_on_hull = is_hull(hit.get("collider", null) as CollisionObject3D)
	return hit["position"]


## Whether the last [method aim_point] ray ended on an Assembly hull rather than
## on ground, on a Static Volume, or on nothing. §14.3's target bracket.
func aim_on_hull() -> bool:
	return _aim_on_hull


## Whether [param body] presents on [constant CollisionLayers.LAYER_ASSEMBLY_HULL].
##
## Read off the body's own layer rather than by resolving it to an
## [AssemblyRuntime]: the camera holds no registry and §13's whole arrangement is
## that it reads the world and knows nothing about who is in it. The own body is
## already excluded from the ray, so a hull here is somebody else's.
static func is_hull(body: CollisionObject3D) -> bool:
	if body == null:
		return false
	return (body.collision_layer & CollisionLayers.LAYER_ASSEMBLY_HULL) != 0


## Speed of the followed node, in m/s. Derived from the interpolated position
## rather than read from a body, so the camera holds no physics reference.
func speed_mps() -> float:
	return _speed_mps


## §13.3. Switches mode without moving the picture.
##
## The two modes solve the same yaw out of different terms — chase adds the look
## offset to the hull's heading, orbit uses the look offset alone — so assigning
## the mode on its own swings the camera by the whole hull heading in one frame,
## which at any heading but due north is a hard cut in the middle of a fight. The
## offset is rebased instead, so the view direction is identical either side of
## the press and every subsequent frame differs only in what the camera follows.
##
## Coming back to chase, §13.6's clamp and recentre then pull the offset back
## onto the hull's line, which is what chase mode is for.
func toggle_mode() -> void:
	if mode == Mode.CHASE:
		mode = Mode.ORBIT
		_look_yaw_rad = wrapf(_look_yaw_rad + _heading_rad, -PI, PI)
	else:
		mode = Mode.CHASE
		_look_yaw_rad = wrapf(_look_yaw_rad - _heading_rad, -PI, PI)


## Drops the look offset back to the resting pose. [code]cam_focus_selection[/code].
func recentre() -> void:
	_look_yaw_rad = 0.0
	_look_pitch_rad = deg_to_rad(PITCH_DEFAULT_DEG)
	_zoom = 1.0


## §13.4. Yaw from the hull's forward projected onto the horizontal plane, and
## nothing else from its attitude.
##
## Invariant I-3 makes an Assembly one rigid body, so a build that noses into a
## crater or takes a recoil impulse it cannot carry rolls entirely — and a camera
## bolted to that basis rolls the whole screen with it. Handoff §4.11 measured
## the shipped chassis pitching 3.6 rad/s from one round of its own autocannon.
##
## Holds [param previous] when the projection is degenerate, because the
## projected vector's direction is meaningless exactly when its length approaches
## zero, and a camera that spins at the worst moment of a fight is worse than one
## that briefly stops following.
static func _hull_heading(basis: Basis, previous: float) -> float:
	var fwd := -basis.z
	if absf(fwd.dot(Vector3.UP)) > HEADING_DEGENERATE_DOT:
		return previous
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length_squared() < SyndicateConstants.EPSILON_LINEAR:
		return previous
	return atan2(-flat.x, -flat.z)


## Frame-rate independent first-order blend factor for a rate in hertz.
static func _lag(rate_hz: float, dt: float) -> float:
	return 1.0 - exp(-rate_hz * maxf(dt, 0.0))


## Shortest signed angle from [param from] to [param to], in [-PI, PI].
static func _angle_delta(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)


func _read_discrete_input() -> void:
	if Input.is_action_just_pressed(ACTION_TOGGLE_VIEW):
		toggle_mode()
	if Input.is_action_just_pressed(ACTION_FOCUS):
		recentre()
	if Input.is_action_just_pressed(ACTION_ZOOM_IN):
		_zoom = clampf(_zoom - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	if Input.is_action_just_pressed(ACTION_ZOOM_OUT):
		_zoom = clampf(_zoom + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


func _accumulate_look(dt: float) -> void:
	var stick := Vector2(
		ControlSystem.axis(ACTION_LOOK_LEFT, ACTION_LOOK_RIGHT),
		ControlSystem.axis(ACTION_LOOK_UP, ACTION_LOOK_DOWN)
	)
	var delta := stick * STICK_DEG_PER_SECOND * dt
	delta += _mouse_delta * MOUSE_DEG_PER_PIXEL
	_mouse_delta = Vector2.ZERO

	_look_yaw_rad -= deg_to_rad(delta.x)
	_look_pitch_rad -= deg_to_rad(delta.y)
	_look_pitch_rad = clampf(
		_look_pitch_rad, deg_to_rad(PITCH_MIN_DEG), deg_to_rad(PITCH_MAX_DEG)
	)

	if mode == Mode.CHASE:
		# Glancing sideways is a gesture, not a mode: clamped, and decayed back to
		# the hull's line once the input is released. ORBIT neither clamps nor
		# recentres, which is what makes it the mode for looking at a wreck.
		var limit := deg_to_rad(LOOK_YAW_LIMIT_DEG)
		_look_yaw_rad = clampf(_look_yaw_rad, -limit, limit)
		if is_zero_approx(stick.x) and is_zero_approx(delta.x):
			_look_yaw_rad = lerpf(_look_yaw_rad, 0.0, _lag(LOOK_RECENTRE_HZ, dt))


func _solve_yaw(dt: float) -> float:
	if mode == Mode.ORBIT:
		return _look_yaw_rad
	var hull := _hull_heading(target.global_transform.basis, _heading_rad)
	# Chased through the shortest arc rather than assigned, so a hull spinning
	# through north does not take the camera the long way round.
	_heading_rad = wrapf(
		_heading_rad + _angle_delta(_heading_rad, hull) * _lag(HEADING_LAG_HZ, dt),
		-PI,
		PI
	)
	return _heading_rad + _look_yaw_rad


## The unobstructed follow distance. [member _distance_scale] is deliberately
## [i]not[/i] applied here: §13.7's pull-in is applied once, to the solved
## position, and folding it in here as well would feed each frame's pull-in back
## into the next frame's desired position and walk the camera into the pivot.
func _distance() -> float:
	return (
		minf(
			CHASE_DISTANCE_BASE_M + CHASE_DISTANCE_PER_RADIUS * bounding_radius_m,
			CHASE_DISTANCE_MAX_M
		)
		* _zoom
	)


func _eye_height() -> float:
	return maxf(CHASE_HEIGHT_MIN_M, CHASE_HEIGHT_PER_RADIUS * bounding_radius_m)


func _desired_position(pivot: Vector3, yaw: float) -> Vector3:
	var dist := _distance()
	var pitch := _look_pitch_rad
	var back := Vector3(sin(yaw), 0.0, cos(yaw))
	var horizontal := cos(pitch) * dist
	var vertical := -sin(pitch) * dist
	return pivot + Vector3.UP * _eye_height() + back * horizontal + Vector3.UP * vertical


## §13.7. Pulls the camera in when ground or a Static Volume is between it and
## the Assembly.
##
## The pull toward the pivot is immediate and only the release is smoothed. A
## camera that eases into a wall is a camera that spends several frames inside
## it, and one frame of geometry filling the screen is worse than a hard cut.
##
## Deliberately blind to [constant CollisionLayers.LAYER_ASSEMBLY_HULL]: pulling
## in on the player's own roof would make a fight a series of lurches, and
## pulling in on an enemy hull would hand the player a free proximity warning.
func _avoid_ground(pivot: Vector3, desired: Vector3, dt: float) -> Vector3:
	var world := get_world_3d()
	if world == null:
		return desired
	var motion := desired - pivot
	if motion.length_squared() < SyndicateConstants.EPSILON_LINEAR:
		return desired

	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe_shape
	q.transform = Transform3D(Basis(), pivot)
	q.motion = motion
	q.collision_mask = CollisionLayers.MASK_GROUND | CollisionLayers.MASK_STATIC_VOLUME
	var result := world.direct_space_state.cast_motion(q)
	# cast_motion answers [1, 1] for a clear path and [0, 0] when the shape starts
	# already overlapping — which at the pivot means the Assembly is buried, and
	# holding the camera at the pivot is the least bad answer available.
	var safe := 1.0 if result.size() < 1 else result[0]

	var length := motion.length()
	var allowed := maxf(0.0, length * safe - COLLISION_MARGIN_M)
	# Floored rather than allowed to reach zero. At zero the camera sits exactly
	# on the point it is told to look at, and [method Node3D.look_at] with a
	# zero-length direction is an engine error every frame rather than a bad
	# picture — and the picture at the floor is inside the hull anyway, which is
	# the least bad thing available when the Assembly is buried.
	var target_scale := clampf(allowed / length, MIN_DISTANCE_M / length, 1.0)
	if target_scale < _distance_scale:
		_distance_scale = target_scale
	else:
		_distance_scale = lerpf(_distance_scale, target_scale, _lag(COLLISION_RELEASE_HZ, dt))
	return pivot + motion.normalized() * (length * _distance_scale)
