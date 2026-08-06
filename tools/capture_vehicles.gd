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

## The vehicle set, in capture order, with the framing each one needs.
##
## `d` and `h` are metres from the Assembly's own origin; an 8.50 m tracked
## platform and a 5.00 m road car do not read at the same range, and a capture
## that framed them identically would be measuring the camera.
## Named through [enum CombatArena.Recipe] rather than by index, because the enum
## is append-only and an integer here would silently reframe a different vehicle
## the next time a recipe is added.
static func shots() -> Array[Dictionary]:
	return [
		{"r": CombatArena.Recipe.WHEELED_REPEATER, "n": "car", "d": 9.0, "h": 2.2},
		{"r": CombatArena.Recipe.WHEELED_UTILITY, "n": "truck", "d": 11.0, "h": 3.0},
		{"r": CombatArena.Recipe.TRACKED, "n": "tank", "d": 15.0, "h": 3.4},
		{"r": CombatArena.Recipe.AMBULATORY, "n": "walker", "d": 11.0, "h": 3.6},
		{"r": CombatArena.Recipe.ROTARY, "n": "heli", "d": 13.0, "h": 4.5},
		{"r": CombatArena.Recipe.BIPED, "n": "biped", "d": 10.0, "h": 3.6},
		{"r": CombatArena.Recipe.MELEE, "n": "melee", "d": 13.0, "h": 4.0},
	]

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

var _arena: CombatArena = null
var _shot: int = -1
var _frame: int = 0

@onready var _camera: Camera3D = $Camera3D
@onready var _label: Label = $Overlay/Label


func _ready() -> void:
	_next_shot()


func _process(_delta: float) -> void:
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


## Points the camera at the Assembly's measured centre rather than at its origin.
##
## An Assembly's origin is its lattice origin and sits wherever the Core Module's
## pivot cell happens to be — on the walking recipes that is two and a half
## metres inside the machine, and framing on it puts the feet out of shot.
func _frame_subject() -> void:
	if _arena == null or _arena.combatants.is_empty():
		return
	var c: CombatArena.Combatant = _arena.combatants[0]
	var shot := shots()[_shot]
	var focus := c.runtime.body.global_position
	var yaw := deg_to_rad(AZIMUTH_DEG)
	var d: float = shot["d"]
	var h: float = shot["h"]
	_camera.global_position = focus + Vector3(sin(yaw) * d, h, cos(yaw) * d)
	_camera.look_at(focus, Vector3.UP)


func _exit_tree() -> void:
	_close()


func _close() -> void:
	if _arena != null:
		_arena.close()
		_arena = null
