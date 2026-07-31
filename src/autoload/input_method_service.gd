class_name InputMethodService
extends Node
## Autoload: [code]InputMethod[/code]. Active input device detection, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §7.2.
##
## The interface adapts to the input method actually in use, not to the
## platform. A player on a laptop who picks up a controller sees gamepad hints
## without the layout tier changing; a player who plugs a keyboard into a tablet
## gets the desktop interaction model on a compact layout. These are orthogonal
## axes and the code treats them that way.

enum Method { KEYBOARD_MOUSE = 0, GAMEPAD = 1, TOUCH = 2 }

signal method_changed(method: Method)

## Stick deflection below this is drift, not intent. Without it, a resting
## controller plugged into a desktop machine steals the hint set from the mouse.
const STICK_DEADZONE: float = 0.35

var current: Method = Method.KEYBOARD_MOUSE


func _input(event: InputEvent) -> void:
	var detected := current
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		detected = Method.TOUCH
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if motion != null and absf(motion.axis_value) < STICK_DEADZONE:
			return
		detected = Method.GAMEPAD
	elif (
		event is InputEventKey
		or event is InputEventMouseButton
		or event is InputEventMouseMotion
	):
		detected = Method.KEYBOARD_MOUSE
	else:
		return
	if detected != current:
		_set_method(detected)


func _set_method(method: Method) -> void:
	current = method
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = (
			Input.MOUSE_MODE_HIDDEN if current == Method.GAMEPAD else Input.MOUSE_MODE_VISIBLE
		)
	method_changed.emit(current)


func is_touch() -> bool:
	return current == Method.TOUCH


func is_gamepad() -> bool:
	return current == Method.GAMEPAD
