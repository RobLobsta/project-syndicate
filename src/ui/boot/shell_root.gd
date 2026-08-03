class_name ShellRoot
extends Node
## The screen flow, owned by [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §15.
##
## [b]Exactly one screen exists at a time.[/b] The shell frees the current one
## before building the next, and every screen is written to be freed: the garage
## disposes its [BuildContext], the match disposes its four and tears down its
## schedulers. That is a rule about physics-server RIDs rather than about tidy
## code — an RID is not reference counted, and a garage opened and closed a
## hundred times without it leaks a hundred spaces that go on stepping for the
## life of the process.
##
## [b]The only state that survives a transition is the blueprint.[/b] Everything
## else about a screen dies with it. A player builds, drives what they built,
## comes back to it unchanged, and changes it — and the object that carries the
## build between those is a list of integer placements that is re-validated at
## every crossing.
##
## [b]Why a shell rather than [code]change_scene_to_file[/code].[/b] The engine's
## scene switch frees the old scene at the end of the frame, on its own schedule,
## and the ordering that matters here is the opposite one: a match's Assemblies
## and the garage's build proxies are on the physics server, and a new screen
## constructed before the old one has released its RIDs is two builds in one
## space. The shell makes the ordering explicit, and it is the same ordering the
## test suite has needed since [code]LEARNED_FACTS.md[/code] §1 fact 45.

enum Screen { MENU, GARAGE, MATCH }

## Each screen is a scene rather than a bare [code]new()[/code], and each scene
## is one node with one script on it.
##
## That looks like ceremony and is doc 11 §15.2's decision one level up: a screen
## is the thing an artist, a designer or a localiser opens, and a screen that
## exists only as a constructor call is one none of them can touch. Preloaded at
## module level, never inside a function — a [method @GDScript.preload] in a
## transition is a load stall at the exact moment the picture changes.
const MENU_SCENE: PackedScene = preload("res://scenes/boot/main_menu.tscn")
const GARAGE_SCENE: PackedScene = preload("res://scenes/garage/garage_screen.tscn")
const MATCH_SCENE: PackedScene = preload("res://scenes/match/arena_basin.tscn")

## The build this session is carrying. Survives every transition; nothing else
## does.
var blueprint: Blueprint = null

var _current: Node = null
var _screen: Screen = Screen.MENU


func _ready() -> void:
	if blueprint == null:
		blueprint = StarterBlueprint.skirmisher()
	show_menu()


## The screen now on show. Diagnostics and tests.
func current_screen() -> Screen:
	return _screen


## The node now on show, or null. Diagnostics and tests.
func current_node() -> Node:
	return _current


func show_menu() -> void:
	var menu: MainMenu = MENU_SCENE.instantiate()
	menu.garage_requested.connect(show_garage)
	menu.quit_requested.connect(_on_quit_requested)
	_present(Screen.MENU, menu)


func show_garage() -> void:
	var garage: GarageScreen = GARAGE_SCENE.instantiate()
	# Set before it enters the tree: the garage lays its build out in `_ready`,
	# and one handed its blueprint afterwards has already opened on the starter.
	garage.initial_blueprint = blueprint.copy()
	garage.test_drive_requested.connect(_on_test_drive_requested)
	garage.menu_requested.connect(show_menu)
	_present(Screen.GARAGE, garage)


## Builds a match around [param bp]. The blueprint is copied on the way in, so a
## match cannot edit the build the garage is holding.
func show_match(bp: Blueprint) -> void:
	var match_screen: MatchScreen = MATCH_SCENE.instantiate()
	match_screen.player_blueprint = bp.copy()
	match_screen.garage_requested.connect(show_garage)
	match_screen.rematch_requested.connect(_on_rematch_requested)
	_present(Screen.MATCH, match_screen)


func _on_test_drive_requested(bp: Blueprint) -> void:
	# The garage's build becomes the session's build at the moment it is driven,
	# not at the moment it is edited. A player who tries something, hates it, and
	# leaves through the menu still comes back to what they last drove.
	blueprint = bp.copy()
	show_match(bp)


func _on_rematch_requested() -> void:
	show_menu()


func _on_quit_requested() -> void:
	get_tree().quit()


## Retires the outgoing screen and builds the incoming one, in that order.
##
## Two rules, and both were paid for.
##
## [b]Remove before releasing.[/b] A screen may hold a node with a
## [WorkerThreadPool] task in flight, and [method Object.free] on one of those is
## [i]refused[/i] — the node survives, still connected to the bus, still holding
## every space it built ([code]LEARNED_FACTS.md[/code] §1 fact 53).
## [method Node.remove_child] runs `_exit_tree`, which is where every screen here
## joins its tasks, disposes its contexts and disconnects from the bus. After
## that there is nothing left to refuse.
##
## [b]Release deferred, not immediately.[/b] Every transition is raised by the
## screen being left — a button in the garage, a key on the end card — so the
## call arrives inside a signal the outgoing screen is still emitting. Freeing it
## there tears down the object whose method is running, which the engine reports
## as an unrelated parenting error and which leaves the screen unchanged.
## [method Node.queue_free] releases it at the end of the frame, by which point
## the emission has returned. The removal is what makes that safe rather than
## merely later: a node removed from the tree can do nothing further whether it
## has been deleted yet or not.
func _present(screen: Screen, node: Node) -> void:
	if _current != null and is_instance_valid(_current):
		remove_child(_current)
		_current.queue_free()
	_current = node
	_screen = screen
	add_child(node)
