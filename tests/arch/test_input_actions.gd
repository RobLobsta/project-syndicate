extends TestCase
## Enforces the canonical action list in [code]CLAUDE.md[/code] §7.2.
##
## Adding an action requires updating this list, CLAUDE.md §7.2, and
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §7.1 together. The test exists
## because gameplay code never reads a raw key: an action that silently
## disappears from [code]project.godot[/code] produces a control that does
## nothing, with no error anywhere.

## Normative. Grouped by domain prefix, matching CLAUDE.md §7.2.
const CANONICAL: Array[String] = [
	"veh_throttle",
	"veh_brake",
	"veh_steer_left",
	"veh_steer_right",
	"veh_handbrake",
	"veh_boost",
	"veh_pitch_forward",
	"veh_pitch_back",
	"veh_roll_left",
	"veh_roll_right",
	"effector_fire_primary",
	"effector_fire_secondary",
	"effector_fire_tertiary",
	"effector_cycle_group",
	"build_place",
	"build_remove",
	"build_pick",
	"build_rotate_yaw",
	"build_rotate_pitch",
	"build_rotate_roll",
	"build_mirror_toggle",
	"build_undo",
	"build_redo",
	"build_cancel",
	"cam_orbit",
	"cam_pan",
	"cam_zoom_in",
	"cam_zoom_out",
	"cam_focus_selection",
	"cam_toggle_view",
	"cam_look_left",
	"cam_look_right",
	"cam_look_up",
	"cam_look_down",
	"catalogue_search",
	"catalogue_next_class",
	"catalogue_prev_class",
	"hud_toggle_stats",
	"hud_ping",
	"hud_scoreboard",
	"net_diagnostics_toggle",
]

## Prefixes CLAUDE.md §7.1 permits. Anything else is an ungrouped action.
const DOMAIN_PREFIXES: Array[String] = [
	"veh_", "effector_", "build_", "cam_", "catalogue_", "hud_", "net_"
]

## ===== CONTEXTS ========================================================
## Doc 11 §7.1: the action set spans two screens and a binding may appear in both.
## What it may not do is appear twice in one — a gamepad has one Right Trigger,
## and an action set in which that trigger both opens the throttle and pulls the
## trigger is a controller that cannot be driven.
##
## [b]This is the check that was missing, and the table was wrong.[/b] §7.1
## published Right Trigger against `veh_throttle` and `effector_fire_primary`,
## Left Trigger against `veh_brake` and `effector_fire_secondary`, and D-Pad Right
## against `veh_roll_right` and `cam_toggle_view` — three collisions inside the
## match, in a document whose own prose says bindings collide only across
## contexts. Nothing could see it, because nothing had ever compared two rows.

## Actions live while an Assembly is being driven.
const MATCH_CONTEXT: Array[String] = [
	"veh_throttle", "veh_brake", "veh_steer_left", "veh_steer_right",
	"veh_handbrake", "veh_boost", "veh_pitch_forward", "veh_pitch_back",
	"veh_roll_left", "veh_roll_right",
	"effector_fire_primary", "effector_fire_secondary", "effector_fire_tertiary",
	"effector_cycle_group",
	"cam_look_left", "cam_look_right", "cam_look_up", "cam_look_down",
	"cam_zoom_in", "cam_zoom_out", "cam_toggle_view",
	"hud_toggle_stats", "hud_ping", "hud_scoreboard",
	"net_diagnostics_toggle",
]

## Actions live while a build is being assembled.
const GARAGE_CONTEXT: Array[String] = [
	"build_place", "build_remove", "build_pick",
	"build_rotate_yaw", "build_rotate_pitch", "build_rotate_roll",
	"build_mirror_toggle", "build_undo", "build_redo", "build_cancel",
	"cam_orbit", "cam_pan", "cam_zoom_in", "cam_zoom_out",
	"cam_focus_selection", "cam_toggle_view",
	"cam_look_left", "cam_look_right", "cam_look_up", "cam_look_down",
	"catalogue_search", "catalogue_next_class", "catalogue_prev_class",
]


func test_project_action_set_matches_the_canonical_list() -> void:
	var declared := _project_actions()
	var declared_sorted := declared.duplicate()
	declared_sorted.sort()
	var canonical_sorted := CANONICAL.duplicate()
	canonical_sorted.sort()

	for name: String in canonical_sorted:
		check_true(declared_sorted.has(name), "action '%s' is missing from project.godot" % name)
	for name: String in declared_sorted:
		check_true(canonical_sorted.has(name), "action '%s' is not in CLAUDE.md §7.2" % name)
	check_eq(declared.size(), CANONICAL.size(), "action count must match CLAUDE.md §7.2")


func test_every_action_is_registered_in_the_input_map() -> void:
	for name: String in CANONICAL:
		check_true(InputMap.has_action(name), "InputMap is missing action '%s'" % name)


func test_every_action_uses_a_domain_prefix() -> void:
	for name: String in CANONICAL:
		var matched := false
		for prefix: String in DOMAIN_PREFIXES:
			if name.begins_with(prefix):
				matched = true
				break
		check_true(matched, "action '%s' has no domain prefix (CLAUDE.md §7.1)" % name)


func test_every_action_has_at_least_one_binding() -> void:
	for name: String in CANONICAL:
		if not InputMap.has_action(name):
			continue
		check_false(
			InputMap.action_get_events(name).is_empty(),
			"action '%s' has no bound event; the control would silently do nothing" % name
		)


func test_bindings_match_events_from_any_device() -> void:
	# Godot stores a device id on every serialised InputEvent. If a binding is
	# written with a concrete device rather than a wildcard, the action matches
	# only on that exact device and fails on every other machine. Synthesising a
	# fresh event and asking the InputMap is the only check that catches it.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	check_true(
		InputMap.event_is_action(key, &"veh_throttle"),
		"a synthesised W keypress must match veh_throttle regardless of device id"
	)

	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	check_true(
		InputMap.event_is_action(pad, &"veh_handbrake"),
		"a synthesised gamepad A press must match veh_handbrake"
	)


func test_every_action_in_a_context_is_in_the_canonical_list() -> void:
	# The two context lists above are hand-maintained, so an action added to
	# CLAUDE.md §7.2 and to neither of them would be exempt from the collision
	# check below without anybody noticing. Both directions, because a stale name
	# left in a context list silently stops guarding anything.
	var named: Array[String] = []
	named.append_array(MATCH_CONTEXT)
	named.append_array(GARAGE_CONTEXT)
	for name: String in named:
		check_true(CANONICAL.has(name), "context list names '%s', which is not an action" % name)
	for name: String in CANONICAL:
		check_true(
			MATCH_CONTEXT.has(name) or GARAGE_CONTEXT.has(name),
			(
				"action '%s' is in no context, so nothing checks it for a binding "
				+ "collision (doc 11 §7.1)"
			) % name
		)


func test_no_two_actions_in_one_context_share_a_gamepad_binding() -> void:
	var contexts: Array[Array] = [MATCH_CONTEXT, GARAGE_CONTEXT]
	for context: Array in contexts:
		var claimed := {}
		for name: String in context:
			if not InputMap.has_action(name):
				continue
			for event: InputEvent in InputMap.action_get_events(name):
				var slot := _gamepad_slot(event)
				if slot.is_empty():
					continue
				check_false(
					claimed.has(slot),
					(
						"'%s' and '%s' are both bound to %s and are live on the same "
						+ "screen; a pad has one of it"
					) % [claimed.get(slot, ""), name, slot]
				)
				if not claimed.has(slot):
					claimed[slot] = name


func test_every_action_a_player_uses_in_a_match_has_a_gamepad_binding() -> void:
	# Doc 11 §7.2's claim that the game is playable on a controller, made
	# checkable. `net_diagnostics_toggle` is exempt and is the only exemption:
	# it is a developer overlay, not a control.
	for name: String in MATCH_CONTEXT:
		if name == "net_diagnostics_toggle":
			continue
		var found := false
		for event: InputEvent in InputMap.action_get_events(name):
			if not _gamepad_slot(event).is_empty():
				found = true
				break
		check_true(found, "match action '%s' cannot be reached from a controller" % name)


## A stable name for the physical control [param event] occupies, or "" when the
## event is not a gamepad one.
##
## An axis is keyed by its axis number and the sign of its value, so the two ends
## of one stick are two slots and `veh_steer_left` does not collide with
## `veh_steer_right`.
static func _gamepad_slot(event: InputEvent) -> String:
	var button := event as InputEventJoypadButton
	if button != null:
		return "button %d" % button.button_index
	var motion := event as InputEventJoypadMotion
	if motion != null:
		return "axis %d %s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]
	return ""


func test_builtin_ui_actions_are_left_alone() -> void:
	# CLAUDE.md §7.1: Godot's ui_* actions drive menu navigation and are never
	# rebound. Redefining them in project.godot breaks Control focus traversal.
	for name: String in _project_actions():
		check_false(name.begins_with("ui_"), "project.godot must not override built-in '%s'" % name)


## Actions actually declared in project.godot's [code][input][/code] section.
##
## Read from the file rather than from [ProjectSettings]. The property list
## reports every built-in [code]ui_*[/code] action too, whether or not the
## project declares it, so reflecting over it cannot distinguish "the project
## defines this" from "the engine ships this" — which is precisely the
## distinction both this test and the override test need.
func _project_actions() -> PackedStringArray:
	var out := PackedStringArray()
	var section := SourceScanner.compile("^\\[(?<name>\\w+)\\]\\s*$")
	var action := SourceScanner.compile("^(?<name>[a-z_][a-z0-9_.]*)\\s*=\\s*\\{")
	var in_input := false
	for line in SourceScanner.read("res://project.godot").split("\n"):
		var s := section.search(line)
		if s != null:
			in_input = s.get_string("name") == "input"
			continue
		if not in_input:
			continue
		var a := action.search(line)
		if a != null:
			out.append(a.get_string("name"))
	return out
