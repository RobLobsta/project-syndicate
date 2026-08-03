extends TestCase
## Doc 11 §14.6's binding lookup.
##
## The control card exists so that a player can find out which keys do anything,
## and it is worth exactly as much as this class's honesty: a card that shows a
## binding nobody has is worse than no card, because a player who presses the
## wrong key concludes the control does not work rather than that the hint was
## stale. CLAUDE.md §7.3 rule 3 puts rebinds in [InputMap], so [InputMap] is what
## this reads and what these tests exercise.
##
## Glyphs are asserted as [i]distinct and non-empty[/i] rather than as literal
## letters. [method DisplayServer.keyboard_get_keycode_from_physical] answers
## against the active layout by design — that is the whole reason the physical
## keycode is used — so a test demanding "W" would be asserting the tester's
## keyboard rather than the rule.

## Two actions §7.1 binds to a key and a gamepad control each, which is what
## makes [method InputPrompt.event_for]'s choice observable at all.
const ACTION_THROTTLE: StringName = &"veh_throttle"
const ACTION_BRAKE: StringName = &"veh_brake"
## Not in §7.2's canonical list, and never will be.
const ACTION_ABSENT: StringName = &"veh_teleport"

var _method_before: InputMethodService.Method = InputMethodService.Method.KEYBOARD_MOUSE


func before_all() -> void:
	_method_before = InputMethod.current


func after_all() -> void:
	# InputMethod is an autoload and this file writes it. Left on GAMEPAD it would
	# hand every later test's prompt lookup a controller binding.
	InputMethod.current = _method_before


## ===== EVENT NAMING ====================================================


func test_two_different_keys_produce_two_different_glyphs() -> void:
	var w := _key_event(KEY_W)
	var s := _key_event(KEY_S)
	var w_text := InputPrompt.text_for_event(w)
	var s_text := InputPrompt.text_for_event(s)
	check_false(w_text.is_empty(), "a bound key names itself")
	check_false(s_text.is_empty(), "so does the other one")
	check_ne(w_text, s_text, "and two keys do not read alike")


## The modifier is part of the glyph, or `Ctrl+Z` reads as `Z` and undo looks
## like a key that does nothing.
func test_a_modifier_is_carried_into_the_glyph() -> void:
	var bare := _key_event(KEY_Z)
	var with_ctrl := _key_event(KEY_Z)
	with_ctrl.ctrl_pressed = true
	var bare_text := InputPrompt.text_for_event(bare)
	var ctrl_text := InputPrompt.text_for_event(with_ctrl)
	check_ne(ctrl_text, bare_text, "a modified key does not read as the bare one")
	check_true(
		ctrl_text.ends_with(bare_text),
		"the modifier is a prefix: got '%s' against '%s'" % [ctrl_text, bare_text]
	)


## The named mouse buttons come out of the string table, so a locale change moves
## them. Asserted as translated rather than as "Left Mouse", because the second
## would fail the moment somebody adds a second locale.
func test_a_named_mouse_button_is_localised() -> void:
	var left := InputEventMouseButton.new()
	left.button_index = MOUSE_BUTTON_LEFT
	var text := InputPrompt.text_for_event(left)
	check_ne(text, String(InputPrompt.KEY_MOUSE_LEFT), "the key was translated")
	check_false(text.is_empty(), "and produced something to read")


## The fallback row is the one with a format specifier in it, and applying `%` to
## a string without one is a runtime error rather than a no-op — so the two paths
## are asserted separately.
func test_an_unnamed_mouse_button_carries_its_index() -> void:
	var extra := InputEventMouseButton.new()
	extra.button_index = MOUSE_BUTTON_XBUTTON2
	var text := InputPrompt.text_for_event(extra)
	check_true(
		text.contains(str(MOUSE_BUTTON_XBUTTON2)),
		"an unnamed button is identified by index: got '%s'" % text
	)


## ===== ACTION LOOKUP ===================================================


func test_a_bound_action_reads_as_its_binding() -> void:
	var label := InputPrompt.label_for(ACTION_THROTTLE)
	check_false(label.is_empty(), "the throttle has a binding")
	check_ne(label, InputPrompt.tr_key(InputPrompt.KEY_UNBOUND), "and it is not the unbound dash")


## An action that does not exist must not bring down the HUD that draws it.
func test_an_undeclared_action_reads_as_unbound() -> void:
	check_eq(
		InputPrompt.label_for(ACTION_ABSENT),
		InputPrompt.tr_key(InputPrompt.KEY_UNBOUND),
		"an action nobody declared has no binding to show"
	)
	check_null(InputPrompt.event_for(ACTION_ABSENT), "and no event behind it")


## §14.6's axis rows are one control and read as one label.
func test_a_pair_reads_as_both_halves() -> void:
	var pair := InputPrompt.label_for_pair(ACTION_THROTTLE, ACTION_BRAKE)
	check_true(
		pair.contains(InputPrompt.label_for(ACTION_THROTTLE)), "the first half is in it"
	)
	check_true(pair.contains(InputPrompt.label_for(ACTION_BRAKE)), "and so is the second")
	check_true(pair.contains(InputPrompt.PAIR_SEPARATOR), "joined by the separator")


## ===== §7.2's INPUT METHOD =============================================


## The rule this class exists for beyond reading [InputMap]: every action in §7.1
## carries both a key and a gamepad control, so "the first event" would show a
## key to somebody holding a controller. Asserted in both directions, because a
## lookup that always returned the gamepad event would satisfy half of it.
func test_the_active_input_method_chooses_which_binding_is_shown() -> void:
	InputMethod.current = InputMethodService.Method.KEYBOARD_MOUSE
	var on_keyboard := InputPrompt.event_for(ACTION_THROTTLE)
	check_true(on_keyboard is InputEventKey, "a player on a keyboard is shown a key")

	InputMethod.current = InputMethodService.Method.GAMEPAD
	var on_pad := InputPrompt.event_for(ACTION_THROTTLE)
	check_true(
		on_pad is InputEventJoypadMotion or on_pad is InputEventJoypadButton,
		"a player holding a controller is shown a controller binding"
	)

	InputMethod.current = _method_before


## An action bound to one device only still shows something to everybody, rather
## than reading as unbound to half the players.
func test_an_action_bound_to_one_device_falls_back_to_it() -> void:
	# §13.6: `cam_look_*` has no keyboard binding at all by construction, so a
	# keyboard player is the one this rule has to answer for.
	InputMethod.current = InputMethodService.Method.KEYBOARD_MOUSE
	var label := InputPrompt.label_for(&"cam_look_left")
	check_ne(
		label,
		InputPrompt.tr_key(InputPrompt.KEY_UNBOUND),
		"an action with only a gamepad binding still names it"
	)
	InputMethod.current = _method_before


## ===== §14.6's CAPTIONS ================================================


## The card's rows are captions plus bindings, and a caption that fell out of the
## string table would render as its own key. Every one of §14.6's is checked
## here, because they are added by hand and the CSV is not compiled against them.
func test_every_control_card_caption_is_translated() -> void:
	var keys: Array[StringName] = [
		ControlCard.KEY_TITLE,
		ControlCard.KEY_DRIVE,
		ControlCard.KEY_STEER,
		ControlCard.KEY_AIM,
		ControlCard.KEY_FIRE,
		ControlCard.KEY_CAMERA,
		ControlCard.KEY_ZOOM,
		ControlCard.KEY_RELEASE_MOUSE,
		ControlCard.KEY_TOGGLE_HINT,
		ControlCard.KEY_MOUSE_MOTION,
	]
	for key: StringName in keys:
		check_ne(InputPrompt.tr_key(key), String(key), "'%s' is in the string table" % key)


## The one caption that is not a plain string: it takes the toggle binding.
func test_the_toggle_hint_takes_one_argument() -> void:
	var hint := InputPrompt.tr_key(ControlCard.KEY_TOGGLE_HINT)
	check_true(hint.contains("%s"), "the hint names the binding rather than describing it")


## ===== FIXTURE =========================================================


## §7.1 binds by physical keycode throughout, so a fixture that set `keycode`
## would exercise the branch the project never takes.
func _key_event(physical: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical
	return event
