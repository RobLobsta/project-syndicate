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
