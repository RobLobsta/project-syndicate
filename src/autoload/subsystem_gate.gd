class_name SubsystemGateService
extends Node
## Autoload: [code]SubsystemGate[/code]. Feature-tag registry consulted at
## subsystem construction, owned by
## [code]docs/HEADLESS_NETWORK_SYNC.md[/code] §9.2.
##
## Disabled subsystems are never instantiated, so their [code]_process[/code]
## and [code]_physics_process[/code] never run and their memory is never
## allocated. This is why the gate must be queried at construction time and not
## consulted per frame.
##
## Everything is enabled by default. Only the headless server bootstrap and the
## quality tiers subtract from that set.

## Presentation subsystems the dedicated server switches off. Listed here rather
## than in the server bootstrap so that the set is greppable from one place.
const PRESENTATION_TAGS: Array[StringName] = [
	&"fusion_sdf_baker",
	&"skirting_system",
	&"vfx_pool",
	&"decal_system",
	&"audio_bus",
	&"ui_root",
	&"ground_height_texture",
	&"assembly_interpolator",
	&"projectile_multimesh",
	&"icon_cache",
	&"rubble_multimesh",
]

## Tags known to the project. Querying an unlisted tag is a programming error:
## a typo would otherwise silently read as "enabled" and the subsystem it was
## meant to gate would run on the dedicated server.
const KNOWN_TAGS: Array[StringName] = [
	&"fusion_sdf_baker",
	&"skirting_system",
	&"vfx_pool",
	&"decal_system",
	&"audio_bus",
	&"ui_root",
	&"ground_height_texture",
	&"assembly_interpolator",
	&"projectile_multimesh",
	&"icon_cache",
	&"rubble_multimesh",
	&"ground_deform_solver",
	&"structure_collapse_solver",
	&"prediction_system",
	&"ai_driver",
]

signal subsystem_gated(tag: StringName, enabled: bool)

var _disabled: Dictionary = {}


func _ready() -> void:
	if OS.has_feature("dedicated_server"):
		disable(PRESENTATION_TAGS)


func is_enabled(tag: StringName) -> bool:
	assert(KNOWN_TAGS.has(tag), "unknown subsystem tag: %s" % tag)
	return not _disabled.has(tag)


func disable(tags: Array[StringName]) -> void:
	for tag in tags:
		if not KNOWN_TAGS.has(tag):
			push_error("SubsystemGate: refusing to disable unknown tag '%s'" % tag)
			continue
		if _disabled.has(tag):
			continue
		_disabled[tag] = true
		subsystem_gated.emit(tag, false)


func enable(tags: Array[StringName]) -> void:
	for tag in tags:
		if not _disabled.has(tag):
			continue
		_disabled.erase(tag)
		subsystem_gated.emit(tag, true)


## Sorted list of currently disabled tags. Sorted so that diagnostics output and
## the network handshake's capability line are reproducible.
func disabled_tags() -> Array[StringName]:
	var out: Array[StringName] = []
	for tag: StringName in _disabled:
		out.append(tag)
	out.sort()
	return out
