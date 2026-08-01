class_name AssemblyInterpolator
extends Node
## Drives [code]VisualRoot[/code] from the chassis body's previous and current
## physics transforms, per [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §10.2.
##
## §10.1 sets [code]physics_jitter_fix[/code] to zero because Godot's jitter fix
## stretches the physics delta to align with render frames, which makes the step
## size frame-rate dependent and breaks server/client agreement. Smoothness is
## therefore explicit, and this is where it happens: the visual mesh moves
## smoothly at any refresh rate while physics runs at a fixed 60 Hz.
##
## §11 invariant 2: [code]VisualRoot[/code] is a [b]sibling[/b] of the body, not
## a child. That is what makes this write authoritative — a child transform would
## be overwritten by the physics server every tick, and the two would fight.
##
## Presentation only. A dedicated server disables the
## [code]assembly_interpolator[/code] subsystem tag and never constructs one, so
## nothing here runs headless.

## Late enough that gameplay has finished writing, early enough to be before the
## frame is drawn.
const VISUAL_PROCESS_PRIORITY: int = 1000

@export var visual_root: Node3D = null
@export var body: RigidBody3D = null

var _prev_xform: Transform3D = Transform3D()
var _curr_xform: Transform3D = Transform3D()


func _ready() -> void:
	if body == null or visual_root == null:
		push_error("AssemblyInterpolator: body and visual_root must both be set")
		set_process(false)
		set_physics_process(false)
		return
	_curr_xform = body.global_transform
	_prev_xform = _curr_xform
	process_priority = VISUAL_PROCESS_PRIORITY


func _physics_process(_dt: float) -> void:
	_prev_xform = _curr_xform
	_curr_xform = body.global_transform


func _process(_dt: float) -> void:
	visual_root.global_transform = interpolated(Engine.get_physics_interpolation_fraction())


## The transform this node would write at [param fraction] through the tick.
## Public so that [code]tests/integration/test_assembly_runtime.gd[/code] can
## assert the interpolation without driving real frames.
func interpolated(fraction: float) -> Transform3D:
	return _prev_xform.interpolate_with(_curr_xform, clampf(fraction, 0.0, 1.0))
