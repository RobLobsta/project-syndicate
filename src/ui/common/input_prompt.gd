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
## Glyph names come from the engine — [method OS.get_keycode_string] and
## [method InputEvent.as_text] — rather than from the string table, because a
## keyboard layout is not a translation: a French player pressing the key
## §7.1 calls [code]W[/code] wants to read [code]Z[/code], which is what the
## physical keycode resolves to and what no [code]tr()[/code] key could know.
## The captions beside them are localised in the ordinary way.

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


## The binding for [param action], as a player would read it.
static func label_for(action: StringName) -> String:
	var event := event_for(action)
	if event == null:
		return tr_key(KEY_UNBOUND)
	return text_for_event(event)


## Both halves of an axis as one label — "W / S" — for the rows of §14.6's card
## that are one control rather than two.
static func label_for_pair(low: StringName, high: StringName) -> String:
	return label_for(low) + PAIR_SEPARATOR + label_for(high)


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
	# Joypad buttons and axes, where the engine's own text — "Joypad Button 14
	# (D-Pad Right)" — is the only naming in the project that knows what a
	# controller's fourteenth button is called.
	return event.as_text()


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
