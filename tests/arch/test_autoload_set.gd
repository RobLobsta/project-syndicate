extends TestCase
## Enforces the autoload table in [code]CLAUDE.md[/code] §4.
##
## Order matters: a later autoload may depend on an earlier one, and Godot
## instantiates them in declaration order. [code]UiScale[/code] reads
## [code]SyndicateSettings.ui_scale[/code] in its [code]_ready[/code], so an
## alphabetised autoload list would leave the interface at the wrong scale on
## every cold start, intermittently, depending on nothing the reader can see.
##
## An autoload is a global. Each one is a permanent increase in coupling, so the
## bar for adding one is deliberately high: this test, CLAUDE.md §4, and the
## architecture documents all have to change together.

## Name and script path, in registration order. Normative.
const EXPECTED: Array[Array] = [
	["SyndicateSettings", "res://src/autoload/settings_service.gd"],
	["SubsystemGate", "res://src/autoload/subsystem_gate.gd"],
	["PartRegistry", "res://src/autoload/part_registry.gd"],
	["EventBus", "res://src/autoload/event_bus.gd"],
	["MatchClock", "res://src/autoload/match_clock.gd"],
	["NetAuthority", "res://src/autoload/net_authority.gd"],
	["UiScale", "res://src/autoload/ui_scale_service.gd"],
	["InputMethod", "res://src/autoload/input_method_service.gd"],
]


func test_autoload_list_matches_exactly() -> void:
	var declared := _declared_autoloads()
	check_eq(declared.size(), EXPECTED.size(), "autoload count must match CLAUDE.md §4")
	for i in mini(declared.size(), EXPECTED.size()):
		check_eq(declared[i][0], EXPECTED[i][0], "autoload %d name" % i)
		check_eq(declared[i][1], EXPECTED[i][1], "autoload '%s' script path" % EXPECTED[i][0])


func test_every_autoload_is_present_in_the_tree() -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if not check_not_null(loop, "main loop must be a SceneTree"):
		return
	for entry in EXPECTED:
		var name: String = entry[0]
		check_true(
			loop.root.has_node(NodePath(name)),
			"autoload '%s' must be in the tree; a typo'd path fails silently" % name
		)


func test_autoload_singletons_resolve_to_their_service_classes() -> void:
	check_true(EventBus is EventBusService, "EventBus must be an EventBusService")
	check_true(MatchClock is MatchClockService, "MatchClock must be a MatchClockService")
	check_true(PartRegistry is PartRegistryService, "PartRegistry must be a PartRegistryService")
	check_true(NetAuthority is NetAuthorityService, "NetAuthority must be a NetAuthorityService")
	check_true(SubsystemGate is SubsystemGateService, "SubsystemGate must be a SubsystemGateService")
	check_true(SyndicateSettings is SettingsService, "SyndicateSettings must be a SettingsService")
	check_true(UiScale is UiScaleService, "UiScale must be a UiScaleService")
	check_true(InputMethod is InputMethodService, "InputMethod must be an InputMethodService")


## Autoloads in ProjectSettings declaration order, as [name, path] pairs. The
## leading "*" marks an autoload enabled as a singleton and is stripped.
func _declared_autoloads() -> Array[Array]:
	var out: Array[Array] = []
	for info in ProjectSettings.get_property_list():
		var property: String = info["name"]
		if not property.begins_with("autoload/"):
			continue
		var name := property.trim_prefix("autoload/")
		var value := String(ProjectSettings.get_setting(property, ""))
		check_true(value.begins_with("*"), "autoload '%s' must be enabled as a singleton" % name)
		out.append([name, value.trim_prefix("*")])
	return out
