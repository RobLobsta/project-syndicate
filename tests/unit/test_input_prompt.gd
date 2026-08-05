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


## ===== §7.2's GAMEPAD FAMILIES =========================================
## The tables are asserted through their public statics with the family passed
## in, which is the only way they can be checked at all: headless has no
## controller, so [method InputPrompt.gamepad_family] can only ever answer
## `GENERIC` here.


## The reason the tables exist. A Switch pad's bottom button is printed `B` and an
## Xbox pad's is printed `A`, so a card built from one naming tells half the
## players to press the wrong button.
func test_the_three_families_print_different_things_on_one_button() -> void:
	var generic := InputPrompt.pad_button_glyph(JOY_BUTTON_A, InputPrompt.GamepadFamily.GENERIC)
	var sony := InputPrompt.pad_button_glyph(
		JOY_BUTTON_A, InputPrompt.GamepadFamily.PLAYSTATION
	)
	var nintendo := InputPrompt.pad_button_glyph(
		JOY_BUTTON_A, InputPrompt.GamepadFamily.NINTENDO
	)
	check_eq(generic, "A", "the bottom face is A on a generic pad")
	check_eq(sony, "Cross", "and Cross on a PlayStation one")
	check_eq(nintendo, "B", "and B on a Nintendo one, which is the trap")
	# The mirror, in the other direction: an Xbox B and a Nintendo B are not the
	# same physical button, and a table that merely renamed the letters would pass
	# the three checks above.
	check_eq(
		InputPrompt.pad_button_glyph(JOY_BUTTON_B, InputPrompt.GamepadFamily.NINTENDO),
		"A",
		"and the right face is A on a Nintendo pad — the row is mirrored, not renamed"
	)


func test_the_triggers_and_shoulders_are_named_per_family() -> void:
	check_eq(
		InputPrompt.pad_axis_glyph(
			JOY_AXIS_TRIGGER_RIGHT, InputPrompt.GamepadFamily.PLAYSTATION
		),
		"R2",
		"the right trigger is R2 on a PlayStation pad"
	)
	check_eq(
		InputPrompt.pad_axis_glyph(JOY_AXIS_TRIGGER_RIGHT, InputPrompt.GamepadFamily.NINTENDO),
		"ZR",
		"and ZR on a Nintendo one"
	)
	check_eq(
		InputPrompt.pad_axis_glyph(JOY_AXIS_TRIGGER_RIGHT, InputPrompt.GamepadFamily.GENERIC),
		"RT",
		"and RT everywhere else"
	)
	check_eq(
		InputPrompt.pad_button_glyph(
			JOY_BUTTON_LEFT_SHOULDER, InputPrompt.GamepadFamily.PLAYSTATION
		),
		"L1",
		"the left shoulder is L1 on a PlayStation pad"
	)


## The worded controls go through the string table, because "D-Pad Up" is a phrase
## and "Cross" is a marking moulded into plastic.
func test_the_worded_controls_are_localised_and_the_same_on_every_family() -> void:
	var first := InputPrompt.pad_button_glyph(
		JOY_BUTTON_DPAD_UP, InputPrompt.GamepadFamily.GENERIC
	)
	check_ne(first, String(InputPrompt.KEY_PAD_DPAD_UP), "the D-pad key was translated")
	check_eq(
		InputPrompt.pad_button_glyph(JOY_BUTTON_DPAD_UP, InputPrompt.GamepadFamily.NINTENDO),
		first,
		"and a D-pad is a D-pad on every pad there is"
	)
	var stick := InputPrompt.pad_axis_glyph(JOY_AXIS_LEFT_X, InputPrompt.GamepadFamily.GENERIC)
	check_ne(stick, String(InputPrompt.KEY_PAD_STICK_LEFT_X), "and so was the stick")
	check_ne(
		stick,
		InputPrompt.pad_axis_glyph(JOY_AXIS_RIGHT_X, InputPrompt.GamepadFamily.GENERIC),
		"and the two sticks do not read alike"
	)


## The fallback carries an index, and it is the one row with a format specifier in
## it — applying `%` to a string without one is a runtime error rather than a
## no-op, which is why it is asserted apart from the named rows.
func test_a_button_no_family_names_falls_back_to_its_index() -> void:
	var text := InputPrompt.pad_button_glyph(31, InputPrompt.GamepadFamily.GENERIC)
	check_true(text.contains("31"), "an unnamed button is identified by index: got '%s'" % text)


## Matched on the name Godot's controller database resolved, which is what makes
## one binding set cover all three families.
func test_a_pad_is_recognised_from_the_name_the_engine_reports() -> void:
	var cases: Dictionary = {
		"Sony DualSense Wireless Controller": InputPrompt.GamepadFamily.PLAYSTATION,
		"PS4 Controller": InputPrompt.GamepadFamily.PLAYSTATION,
		"Nintendo Switch Pro Controller": InputPrompt.GamepadFamily.NINTENDO,
		"Joy-Con (L)": InputPrompt.GamepadFamily.NINTENDO,
		"8BitDo SN30 Pro": InputPrompt.GamepadFamily.GENERIC,
		"Xbox Series Controller": InputPrompt.GamepadFamily.GENERIC,
		"": InputPrompt.GamepadFamily.GENERIC,
	}
	for name: String in cases:
		check_eq(
			InputPrompt.family_of_name(name),
			cases[name],
			"'%s' resolves to the family whose markings it carries" % name
		)
	# An 8BitDo switched into its Nintendo mode reports as one, and the point of
	# matching on the resolved name rather than on a vendor id is that this works
	# without the project knowing anything about 8BitDo.
	check_eq(
		InputPrompt.family_of_name("8BitDo SN30 Pro (Nintendo Switch Pro Controller)"),
		InputPrompt.GamepadFamily.NINTENDO,
		"and the same pad in its Switch mode carries Nintendo markings"
	)


## The whole reason this replaced [method InputEvent.as_text]: the engine's answer
## for the bottom face button is forty-eight characters long.
func test_a_pad_binding_reads_as_a_glyph_rather_than_a_sentence() -> void:
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	var text := InputPrompt.text_for_event(button)
	check_true(text.length() <= 12, "'%s' is short enough for a control card" % text)
	check_false(text.contains("Joypad Button"), "and is not the engine's enumeration")
	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_TRIGGER_RIGHT
	motion.axis_value = 1.0
	check_false(
		InputPrompt.text_for_event(motion).contains("Joypad Motion"),
		"and neither is an axis"
	)


## §14.6's rows are one control, and on a stick both halves of an axis are the
## same control. "Left Stick X / Left Stick X" is a card nobody proof-read.
func test_a_pair_bound_to_one_stick_reads_once() -> void:
	InputMethod.current = InputMethodService.Method.GAMEPAD
	var pair := InputPrompt.label_for_pair(&"veh_steer_left", &"veh_steer_right")
	check_false(pair.contains(InputPrompt.PAIR_SEPARATOR), "one stick reads as one control")
	check_eq(pair, InputPrompt.label_for(&"veh_steer_left"), "and names that control")
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
