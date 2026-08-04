class_name MainBoot
extends Node
## The project's entry point, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §15.1.
##
## Its only job is to decide what to show and to instantiate it. It holds no
## gameplay state and survives no transition.
##
## A boot node rather than setting a screen as [code]run/main_scene[/code]
## directly is what keeps a headless server from constructing a camera, a HUD,
## and a viewport it has no use for. [code]SubsystemGate[/code] disables the
## [i]tags[/i]; this branch is what stops the nodes being built at all, which is
## the distinction doc 12 §9.2 draws between gating a subsystem and never
## instantiating one.
##
## A client gets a [ShellRoot], which owns the screen flow from that point on.
## This node decides once, between a client and a server, and never again.

const SERVER_SCENE := "res://scenes/net/dedicated_server.tscn"


func _ready() -> void:
	if _is_headless():
		if not ResourceLoader.exists(SERVER_SCENE):
			# Doc 12's server scene is not written yet. Saying so and stopping is
			# the honest failure: silently falling through to the client shell
			# would build a camera and a HUD on a machine with no display and
			# present as a server that mysteriously costs a GPU.
			push_error("MainBoot: %s does not exist; doc 12 §9 is unwritten" % SERVER_SCENE)
			get_tree().quit(1)
			return
		var packed: PackedScene = load(SERVER_SCENE)
		if packed == null:
			push_error("MainBoot: could not load %s" % SERVER_SCENE)
			get_tree().quit(1)
			return
		add_child(packed.instantiate())
		return

	var shell := ShellRoot.new()
	shell.name = "ShellRoot"
	add_child(shell)


## A dedicated-server build, or any run with no rendering device. The feature tag
## is the export preset's; the display-server check catches
## [code]--headless[/code] on an ordinary build, which is how the test suite and
## every validator run.
static func _is_headless() -> bool:
	return (
		OS.has_feature("dedicated_server")
		or DisplayServer.get_name() == "headless"
	)
