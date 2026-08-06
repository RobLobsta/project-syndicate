extends Node3D
## Renders one framed still of each shipped vehicle, for the proportion review
## CLAUDE.md §10 rule 18 asks for.
##
## [codeblock]
## xvfb-run -a -s "-screen 0 1600x900x24" tools/ci/godot.sh --path . \
##   --rendering-driver opengl3 --resolution 1600x900 \
##   --main-scene res://tools/capture_vehicles.tscn \
##   --write-movie .build/capture/f.png --quit-after 900
## [/codeblock]
##
## [b]This exists because proportion is the one property of a part table nothing
## in the repository can check.[/b] Every validator in `tools/` compares a part
## against its own schema; `tests/physics/test_build_proportions.gd` compares one
## Assembly against a density and a wheelbase. Neither can see that a machine is
## the wrong shape, and one frame answers it immediately — LEARNED_FACTS.md §1
## fact 75 is the session that learned it and fact 55 is the capture route.
##
## [b]It reads its layouts from [CombatArena], and that is deliberate.[/b] The
## five recipes are authored there as validated cell lists and CLAUDE.md §1.1
## tolerates exactly two copies of the shipped build — [StarterBlueprint] and the
## arena. A third would be a third thing to keep true, and the whole point of a
## capture is that it shows the build the suite is actually measuring. This is a
## development harness under [code]tools/[/code] and is never in a shipped scene
## tree, so the dependency runs the safe way round.
##
## Each vehicle gets [constant FRAMES_PER_VEHICLE] frames: the first few are the
## settle, and the rest are the still. Movie Maker pins the frame rate, so the
## numbering is deterministic and a before/after is a diff of two directories.

## The vehicle set, in capture order.
##
## Named through [enum CombatArena.Recipe] rather than by index, because the enum
## is append-only and an integer here would silently reframe a different vehicle
## the next time a recipe is added.
##
## [b]There is no per-vehicle framing here any more and that is the repair.[/b]
## Every shot used to carry an authored distance and height, which meant the
## framing was a guess made against the machine as it stood when somebody last
## looked — so the walking recipes were cropped at the torso the moment they grew
## legs, and a capture that crops the subject is measuring the camera. The camera
## is now placed from each Assembly's own measured bounding box
## ([method _frame_subject]), so a vehicle that changes shape reframes itself.
static func shots() -> Array[Dictionary]:
	return [
		{"r": CombatArena.Recipe.WHEELED_REPEATER, "n": "car"},
		{"r": CombatArena.Recipe.WHEELED_UTILITY, "n": "truck"},
		{"r": CombatArena.Recipe.TRACKED, "n": "tank"},
		{"r": CombatArena.Recipe.AMBULATORY, "n": "walker"},
		{"r": CombatArena.Recipe.ROTARY, "n": "heli"},
		{"r": CombatArena.Recipe.BIPED, "n": "biped"},
		{"r": CombatArena.Recipe.MELEE, "n": "melee"},
	]

## How much of the frame the subject fills at its widest.
##
## Below one the machine has air around it; at one it touches the edges, which is
## where a limb mid-swing or a barrel at full traverse leaves the shot.
const FRAME_FILL: float = 0.72

## Where the camera looks, as a fraction of the subject's height above its floor.
## Slightly below the middle, so a tall machine's legs stay in shot rather than
## the sky above its head.
const FRAME_AIM_HEIGHT: float = 0.45

## Degrees above the horizontal the camera stands at. A reference photograph of a
## vehicle is taken from about eye height on a machine of this size, and a
## three-quarter view from dead level loses the deck of everything low.
const ELEVATION_DEG: float = 16.0

## Steps of the fit in [method _frame_subject]. Apparent size goes as one over
## distance, so the proportional correction converges geometrically and four is
## already past the pixel.
const FRAME_ITERATIONS: int = 5

## Frames each vehicle is held for, and how many of them are the settle.
##
## The settle is generous because an ambulatory build falls the last few
## centimetres onto its own springs and a rotary one has to spool its discs up
## before it holds altitude; framing either mid-transient is a picture of the
## spawn rather than of the machine.
const FRAMES_PER_VEHICLE: int = 120
const SETTLE_FRAMES: int = 96

## Three-quarter front, which is the angle every one of the reference images is
## shot from and therefore the only angle a comparison can be made at.
const AZIMUTH_DEG: float = 34.0

## The capture floor: wide enough that no framing distance sees past its edge,
## and a mid grey so a greybox machine reads against it in both directions.
const GROUND_SIZE_M: float = 120.0
const GROUND_COLOUR: Color = Color(0.42, 0.44, 0.46)

var _arena: CombatArena = null
var _shot: int = -1
var _frame: int = 0

## `current` is set in the scene as well as here. A [Camera3D] that is not
## current renders nothing at all — the environment background fills the frame
## and the CanvasLayer draws over it, which looks exactly like a scene whose
## geometry failed to spawn and is not.
@onready var _camera: Camera3D = $Camera3D
@onready var _label: Label = $Overlay/Label


## [b]The first arena is opened on the first frame and not in [method _ready], and
## the difference is the whole capture.[/b] [method CombatArena.open] adds its
## ground slab to `EventBus.get_tree().root`, and a `root` that is still setting
## up its own children refuses the call — "Parent node is busy setting up
## children". The arena then has no slab, so it has no [World3D], so
## `direct_space_state` is null and every system downstream of it fails in turn.
##
## What that looks like is a frame containing the label and nothing else: no
## vehicle, no ground, just the environment background. It reads exactly like a
## camera that is not current, which is the wrong thing to go and fix.
func _ready() -> void:
	_camera.current = true
	_add_ground()


## A visible floor at `y = 0`, which the arena itself does not have.
##
## [CombatArena] builds its slab as a [StaticBody3D] with a collision shape and
## no mesh, because nothing in `tests/` looks at it — so every machine in this
## capture floated in mid-air with no horizon to read its ride height against.
## The plane is added here rather than to the arena deliberately: an arena is
## constructed by nearly every file in `tests/physics/`, and adding nodes to one
## shifts the allocation history the whole suite's float ordering depends on
## (LEARNED_FACTS.md §1 fact 54). A development harness can afford what the
## fixture cannot.
func _add_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE_M, GROUND_SIZE_M)
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOUR
	material.roughness = 1.0
	var node := MeshInstance3D.new()
	node.name = "CaptureGround"
	node.mesh = plane
	node.material_override = material
	add_child(node)


func _process(_delta: float) -> void:
	if _shot < 0:
		_next_shot()
		return
	if _shot >= shots().size():
		return
	_frame += 1
	if _frame == SETTLE_FRAMES:
		_frame_subject()
	if _frame >= FRAMES_PER_VEHICLE:
		_next_shot()


## Closes the current arena and opens the next. One at a time and never two:
## every arena builds at the same world coordinates, so a second one open at once
## puts its Assembly inside the first one's (LEARNED_FACTS.md §1 fact 45).
func _next_shot() -> void:
	_close()
	_shot += 1
	_frame = 0
	var all := shots()
	if _shot >= all.size():
		get_tree().quit()
		return
	var shot := all[_shot]
	_arena = CombatArena.new()
	_arena.open()
	_arena.spawn(int(shot["r"]), 0, Vector2.ZERO, 0.0, 0)
	_label.text = str(shot["n"]).to_upper()


## Points the camera at the Assembly's measured bounding box and stands it back
## far enough to hold the whole of it.
##
## An Assembly's origin is its lattice origin and sits wherever the Core Module's
## pivot cell happens to be — on the walking recipes that is two and a half
## metres inside the machine, and framing on it puts the feet out of shot. The
## box is measured over the drawn meshes rather than over the occupancy, because
## a rotor's blades and a limb's shin are drawn well outside the cells the part
## occupies (doc 13 §2.1) and a frame that clipped them would be showing less of
## the machine than the game does.
func _frame_subject() -> void:
	if _arena == null or _arena.combatants.is_empty():
		return
	var c: CombatArena.Combatant = _arena.combatants[0]
	# A recipe that failed to build leaves a combatant whose body never reached
	# the tree, and `global_position` on one is an engine error per frame rather
	# than a bad picture.
	if c.runtime == null or c.runtime.body == null or not c.runtime.body.is_inside_tree():
		push_warning("capture_vehicles: %s has no body to frame" % _label.text)
		return
	var box := _visual_bounds(c.runtime)
	if box.size == Vector3.ZERO:
		push_warning("capture_vehicles: %s drew nothing to frame" % _label.text)
		return

	var focus := Vector3(
		box.position.x + box.size.x * 0.5,
		box.position.y + box.size.y * FRAME_AIM_HEIGHT,
		box.position.z + box.size.z * 0.5
	)
	# [b]The distance is fitted rather than derived, and the reason is that a
	# derived one is wrong for exactly the vehicles that need framing most.[/b]
	# Trigonometry against a bounding sphere frames a 7.00 m fuselage seen
	# three-quarter-on as though it were 7.00 m across the screen, when most of
	# that length is depth — so the long machines came out small and the tall ones
	# were cropped. Measuring what the camera actually projects and scaling the
	# distance by the miss converges in a handful of steps and cannot be wrong
	# about a shape nobody anticipated.
	var d := box.size.length()
	for _i: int in FRAME_ITERATIONS:
		_place_camera(focus, d)
		var fill := _screen_fill(box)
		if fill <= 0.0:
			break
		d *= fill / FRAME_FILL
	_place_camera(focus, d)


## Stands the camera [param d] metres off [param focus] on the capture's own
## orbit and points it back.
func _place_camera(focus: Vector3, d: float) -> void:
	var yaw := deg_to_rad(AZIMUTH_DEG)
	var pitch := deg_to_rad(ELEVATION_DEG)
	# `-cos` puts the camera on the subject's own `-Z`, which is the face every
	# part in this project is authored to point along and therefore the front of
	# the machine. It was `+cos` and shot every reference frame from behind.
	_camera.global_position = focus + Vector3(
		sin(yaw) * cos(pitch) * d, sin(pitch) * d, -cos(yaw) * cos(pitch) * d
	)
	_camera.look_at(focus, Vector3.UP)


## The largest fraction of the viewport [param box] currently projects onto, over
## the two screen axes. Zero when any corner is behind the camera, which is the
## signal to stop rather than to correct.
func _screen_fill(box: AABB) -> float:
	var view := get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i: int in 8:
		var corner := box.get_endpoint(i)
		if _camera.is_position_behind(corner):
			return 0.0
		var p := _camera.unproject_position(corner)
		lo = lo.min(p)
		hi = hi.max(p)
	return maxf((hi.x - lo.x) / maxf(view.x, 1.0), (hi.y - lo.y) / maxf(view.y, 1.0))


## World-space bounds of everything [param runtime] draws, or a zero box when it
## draws nothing.
func _visual_bounds(runtime: AssemblyRuntime) -> AABB:
	var box := AABB()
	var started := false
	for child: Node in runtime.visual_root.get_children():
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var world := mesh_node.global_transform * mesh_node.mesh.get_aabb()
		box = world if not started else box.merge(world)
		started = true
	return box


func _exit_tree() -> void:
	_close()


func _close() -> void:
	if _arena != null:
		_arena.close()
		_arena = null
