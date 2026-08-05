class_name InputPrompt
extends RefCounted
## Turns an action into the key or button a player would actually press, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §14.6.
##
## [b]It reads [InputMap], never a table.[/b] CLAUDE.md §7.3 rule 3 stores
## rebinds in [code]SyndicateSettings[/code] and applies them through
## [InputMap] at startup, so a prompt built from a hard-coded list of key names
## is a prompt that lies to every player who has rebound anything — and it lies
## silently, which is the worst way for a control hint to be wrong. §7.1's table
## is the [i]default[/i] binding and this is the live one.
##
## [b]Which event it picks is a function of [code]InputMethod[/code].[/b] Every
## action in §7.1 carries a keyboard event and a gamepad event, so "the first
## one" would show a key to somebody holding a controller. The active method
## decides, and the first event of any kind is the fallback for an action bound
## to only one device.
##
## Key glyphs come from the engine — [method OS.get_keycode_string] — rather than
## from the string table, because a keyboard layout is not a translation: a French
## player pressing the key §7.1 calls [code]W[/code] wants to read [code]Z[/code],
## which is what the physical keycode resolves to and what no [code]tr()[/code]
## key could know. The captions beside them are localised in the ordinary way.
##
## [b]Gamepad glyphs are a table here and deliberately not
## [method InputEvent.as_text].[/b] The engine's answer for button 0 is
## [code]"Joypad Button 0 (Bottom Action, Sony Cross, Xbox A, Nintendo B)"[/code],
## which is correct, complete, and forty-eight characters of it wrong for a card
## that has to read [code]A[/code]. §7.2's families each print something different
## on the same physical button, so the glyph is chosen from the connected pad's
## name — see [method gamepad_family]. Face, shoulder and trigger markings are not
## translated for the same reason a keycap is not: they are what is moulded into
## the plastic.

## ===== STRING KEYS =====================================================

const KEY_MOUSE_LEFT: StringName = &"input.mouse.left"
const KEY_MOUSE_RIGHT: StringName = &"input.mouse.right"
const KEY_MOUSE_MIDDLE: StringName = &"input.mouse.middle"
const KEY_MOUSE_WHEEL_UP: StringName = &"input.mouse.wheel_up"
const KEY_MOUSE_WHEEL_DOWN: StringName = &"input.mouse.wheel_down"
## Takes the button index.
const KEY_MOUSE_OTHER: StringName = &"input.mouse.other"
## What an action with no binding at all reads as.
const KEY_UNBOUND: StringName = &"input.unbound"
## Joins the two halves of an axis: "W / S".
const PAIR_SEPARATOR: String = " / "

## [method DisplayServer.get_name] under [code]--headless[/code]. Named here
## because [method _layout_keycode] branches on it and a bare literal in that
## branch reads as a typo rather than as a rule.
const HEADLESS_DISPLAY_SERVER: String = "headless"

const MODIFIER_JOIN: String = "+"
const KEY_MODIFIER_CTRL: StringName = &"input.modifier.ctrl"
const KEY_MODIFIER_SHIFT: StringName = &"input.modifier.shift"
const KEY_MODIFIER_ALT: StringName = &"input.modifier.alt"

## ===== GAMEPAD GLYPHS ==================================================
## Doc 11 §7.2. One logical binding set covers every pad Godot's controller
## database recognises — a DualShock, a Switch Pro and an 8BitDo all report the
## same button indices — so what varies between them is only what is printed on
## the button, and that is all these tables carry.

## Which of the three markings a connected pad uses.
enum GamepadFamily { GENERIC = 0, PLAYSTATION = 1, NINTENDO = 2 }

## Substrings of [method Input.get_joy_name] that identify a family, lower-cased.
##
## Matched against the name Godot's controller database resolved, not against a
## vendor id, because that database is what already did the hard part: an 8BitDo
## in its X-input mode reports as an Xbox pad and in its Switch mode as a
## Nintendo one, and in both cases the name says so and the button indices are
## already correct.
const PLAYSTATION_NAMES: Array[String] = [
	"playstation", "ps3", "ps4", "ps5", "dualshock", "dualsense", "sony"
]
const NINTENDO_NAMES: Array[String] = ["nintendo", "switch", "joy-con", "joycon"]

## Button index -> marking, per family. Index 5 is the guide button, which is
## never bound (doc 11 §7.1) and has no marking here.
const PAD_BUTTONS_GENERIC: Dictionary = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
}
const PAD_BUTTONS_PLAYSTATION: Dictionary = {
	JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle",
	JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_BACK: "Share", JOY_BUTTON_START: "Options",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
}
## The face markings are the Xbox layout's mirror image, which is the whole reason
## this table exists: a Switch pad's bottom button is printed [code]B[/code].
const PAD_BUTTONS_NINTENDO: Dictionary = {
	JOY_BUTTON_A: "B", JOY_BUTTON_B: "A", JOY_BUTTON_X: "Y", JOY_BUTTON_Y: "X",
	JOY_BUTTON_BACK: "-", JOY_BUTTON_START: "+",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "L", JOY_BUTTON_RIGHT_SHOULDER: "R",
}

const PAD_TRIGGERS_GENERIC: Array[String] = ["LT", "RT"]
const PAD_TRIGGERS_PLAYSTATION: Array[String] = ["L2", "R2"]
const PAD_TRIGGERS_NINTENDO: Array[String] = ["ZL", "ZR"]

## The worded ones, which are the same on every pad and are therefore ordinary
## localised strings.
const KEY_PAD_DPAD_UP: StringName = &"input.pad.dpad_up"
const KEY_PAD_DPAD_DOWN: StringName = &"input.pad.dpad_down"
const KEY_PAD_DPAD_LEFT: StringName = &"input.pad.dpad_left"
const KEY_PAD_DPAD_RIGHT: StringName = &"input.pad.dpad_right"
const KEY_PAD_STICK_LEFT_X: StringName = &"input.pad.stick_left_x"
const KEY_PAD_STICK_LEFT_Y: StringName = &"input.pad.stick_left_y"
const KEY_PAD_STICK_RIGHT_X: StringName = &"input.pad.stick_right_x"
const KEY_PAD_STICK_RIGHT_Y: StringName = &"input.pad.stick_right_y"
## Takes the button index, for a pad with more buttons than §7.1 knows about.
const KEY_PAD_OTHER: StringName = &"input.pad.other"


## The binding for [param action], as a player would read it.
static func label_for(action: StringName) -> String:
	var event := event_for(action)
	if event == null:
		return tr_key(KEY_UNBOUND)
	return text_for_event(event)


## Both halves of an axis as one label — "W / S" — for the rows of §14.6's card
## that are one control rather than two.
##
## Collapses to one when both halves read the same, which is what a stick does:
## `veh_steer_left` and `veh_steer_right` are the two ends of one axis and a card
## reading "Left Stick X / Left Stick X" is a card nobody proof-read.
static func label_for_pair(low: StringName, high: StringName) -> String:
	var a := label_for(low)
	var b := label_for(high)
	if a == b:
		return a
	return a + PAIR_SEPARATOR + b


## The event [InputMap] holds for [param action] that best matches the active
## input method, or null when the action is unbound or undeclared.
##
## Undeclared rather than asserted: an action removed from §7.1 must make the
## card read "—" for one row, not bring down the HUD that draws it.
static func event_for(action: StringName) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return null
	var want_gamepad := InputMethod.is_gamepad()
	for event: InputEvent in events:
		if _is_gamepad_event(event) == want_gamepad:
			return event
	return events[0]


## A player-readable name for [param event].
static func text_for_event(event: InputEvent) -> String:
	var key := event as InputEventKey
	if key != null:
		return _modifier_prefix(key) + _key_glyph(key)
	var mouse := event as InputEventMouseButton
	if mouse != null:
		var named := _mouse_key(mouse.button_index)
		# Only the fallback row carries a format specifier, and a `%` applied to a
		# string without one is a runtime error rather than a no-op.
		if named == KEY_MOUSE_OTHER:
			return _modifier_prefix(mouse) + tr_key(named) % mouse.button_index
		return _modifier_prefix(mouse) + tr_key(named)
	var button := event as InputEventJoypadButton
	if button != null:
		return pad_button_glyph(button.button_index, gamepad_family())
	var motion := event as InputEventJoypadMotion
	if motion != null:
		return pad_axis_glyph(motion.axis, gamepad_family())
	return event.as_text()


## The marking on [param index] for [param family].
##
## Public and taking its family as a parameter so that a test can assert all three
## without a controller plugged in — which is the only way this table can be
## checked at all, since [method Input.get_joy_name] answers nothing headless.
static func pad_button_glyph(index: int, family: GamepadFamily) -> String:
	var table := PAD_BUTTONS_GENERIC
	if family == GamepadFamily.PLAYSTATION:
		table = PAD_BUTTONS_PLAYSTATION
	elif family == GamepadFamily.NINTENDO:
		table = PAD_BUTTONS_NINTENDO
	if table.has(index):
		return String(table[index])
	match index:
		JOY_BUTTON_DPAD_UP:
			return tr_key(KEY_PAD_DPAD_UP)
		JOY_BUTTON_DPAD_DOWN:
			return tr_key(KEY_PAD_DPAD_DOWN)
		JOY_BUTTON_DPAD_LEFT:
			return tr_key(KEY_PAD_DPAD_LEFT)
		JOY_BUTTON_DPAD_RIGHT:
			return tr_key(KEY_PAD_DPAD_RIGHT)
	return tr_key(KEY_PAD_OTHER) % index


## The marking on [param axis] for [param family]. The two triggers are the only
## axes whose name changes between families; the sticks are sticks everywhere.
static func pad_axis_glyph(axis: int, family: GamepadFamily) -> String:
	var triggers := PAD_TRIGGERS_GENERIC
	if family == GamepadFamily.PLAYSTATION:
		triggers = PAD_TRIGGERS_PLAYSTATION
	elif family == GamepadFamily.NINTENDO:
		triggers = PAD_TRIGGERS_NINTENDO
	match axis:
		JOY_AXIS_LEFT_X:
			return tr_key(KEY_PAD_STICK_LEFT_X)
		JOY_AXIS_LEFT_Y:
			return tr_key(KEY_PAD_STICK_LEFT_Y)
		JOY_AXIS_RIGHT_X:
			return tr_key(KEY_PAD_STICK_RIGHT_X)
		JOY_AXIS_RIGHT_Y:
			return tr_key(KEY_PAD_STICK_RIGHT_Y)
		JOY_AXIS_TRIGGER_LEFT:
			return triggers[0]
		JOY_AXIS_TRIGGER_RIGHT:
			return triggers[1]
	return tr_key(KEY_PAD_OTHER) % axis


## The family of the first connected pad, or
## [constant GamepadFamily.GENERIC] when there is none.
##
## Recomputed per call rather than cached. A cache on a [RefCounted] is a static
## and therefore process-wide (see [method _key_glyph]'s neighbours), so it would
## outlive the controller that filled it and a player who unplugged a DualShock
## and plugged in a Switch pad would keep reading Sony markings for the rest of
## the session. This costs one array index and a handful of substring tests, on a
## card that redraws when the input method changes.
static func gamepad_family() -> GamepadFamily:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return GamepadFamily.GENERIC
	return family_of_name(Input.get_joy_name(pads[0]))


## The family [param joy_name] belongs to. Split out so the matching is testable
## without a device: headless has no pads and [method gamepad_family] can only
## ever answer GENERIC there.
static func family_of_name(joy_name: String) -> GamepadFamily:
	var lower := joy_name.to_lower()
	for needle: String in PLAYSTATION_NAMES:
		if lower.contains(needle):
			return GamepadFamily.PLAYSTATION
	for needle: String in NINTENDO_NAMES:
		if lower.contains(needle):
			return GamepadFamily.NINTENDO
	return GamepadFamily.GENERIC


## [method Object.tr] without an [Object]. This class is a [RefCounted] with no
## tree, and every caller of it is drawing into one.
static func tr_key(key: StringName) -> String:
	return String(TranslationServer.translate(key))


## ===== PRIVATE =========================================================


static func _is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## The physical key, so the glyph matches the player's own layout rather than the
## US layout §7.1's table was written against.
static func _key_glyph(key: InputEventKey) -> String:
	if key.physical_keycode != KEY_NONE:
		return OS.get_keycode_string(_layout_keycode(key.physical_keycode))
	if key.keycode != KEY_NONE:
		return OS.get_keycode_string(key.keycode)
	return tr_key(KEY_UNBOUND)


## The physical keycode resolved against the player's keyboard layout.
##
## [b]The headless branch is not optional.[/b]
## [method DisplayServer.keyboard_get_keycode_from_physical] is unimplemented on
## the headless display server and answers by pushing an engine error rather than
## by returning anything — which the suite wrapper fails on, so the whole run goes
## red for a HUD label. The physical code is the right fallback: it is the US
## layout, which is what §7.1's table is written against.
static func _layout_keycode(physical: Key) -> Key:
	if DisplayServer.get_name() == HEADLESS_DISPLAY_SERVER:
		return physical
	return DisplayServer.keyboard_get_keycode_from_physical(physical)


static func _modifier_prefix(event: InputEventWithModifiers) -> String:
	var out := ""
	if event.ctrl_pressed:
		out += tr_key(KEY_MODIFIER_CTRL) + MODIFIER_JOIN
	if event.shift_pressed:
		out += tr_key(KEY_MODIFIER_SHIFT) + MODIFIER_JOIN
	if event.alt_pressed:
		out += tr_key(KEY_MODIFIER_ALT) + MODIFIER_JOIN
	return out


static func _mouse_key(button_index: int) -> StringName:
	match button_index:
		MOUSE_BUTTON_LEFT:
			return KEY_MOUSE_LEFT
		MOUSE_BUTTON_RIGHT:
			return KEY_MOUSE_RIGHT
		MOUSE_BUTTON_MIDDLE:
			return KEY_MOUSE_MIDDLE
		MOUSE_BUTTON_WHEEL_UP:
			return KEY_MOUSE_WHEEL_UP
		MOUSE_BUTTON_WHEEL_DOWN:
			return KEY_MOUSE_WHEEL_DOWN
	return KEY_MOUSE_OTHER
