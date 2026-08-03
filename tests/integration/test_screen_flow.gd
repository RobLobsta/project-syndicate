extends TestCase
## The screen flow of doc 11 §15: menu, garage, match, and back.
##
## [b]The claim under test is that a screen can be left.[/b] Until session 26 the
## project had one scene and no way back to it, and everything in this file is a
## consequence of fixing that: the shell holds exactly one screen at a time, it
## retires the outgoing one before building the incoming one, and a screen that
## could not be retired would show up here as the [i]next[/i] one misbehaving.
##
## [b]It goes through the shell's own transitions, not through the screens.[/b]
## Doc 11 §15.1: the shell is the only thing that decides what exists, so a test
## that constructed a [GarageScreen] directly would be asserting something no
## player can reach.
##
## [b]The match is opened exactly once, and that is a budget rather than a
## preference.[/b] A [MatchScreen] builds a Dynamic Ground Array, primes its
## collision streaming and spawns four Assemblies, which costs most of a minute
## in this suite — so the one thing worth spending it on is the handoff itself:
## that what the garage produced is what the match was given. Everything else
## here runs against the menu and the garage, which are cheap. See
## [method _open_match_once].

## The signal a match raises when the player asks to go back and change the
## build. Named rather than emitted through the end card, because the card is a
## [Control] with a fade and this file is about the transition it triggers.
const GARAGE_REQUESTED: StringName = &"garage_requested"

var _shell: ShellRoot = null

var _match_opened: bool = false
var _match_screen_valid: bool = false
var _match_blueprint_size: int = 0
var _edited_size: int = 0
var _session_size_after_drive: int = 0
var _screen_after_drive: int = -1
var _screen_after_leaving_match: int = -1
var _match_freed_on_exit: bool = false


func before_all() -> void:
	_shell = ShellRoot.new()
	_shell.name = "TestShellRoot"
	# A [TestCase] is a [RefCounted] and has no tree of its own; the autoload's is
	# the one every node in the suite goes into (LEARNED_FACTS.md §1 fact 11).
	EventBus.get_tree().root.add_child(_shell)


func after_all() -> void:
	if _shell != null and is_instance_valid(_shell):
		_shell.get_parent().remove_child(_shell)
		_shell.free()
		_shell = null


## Returns the shell to the menu. Every method that opens something calls this
## when it is done, because the runner sorts them and a test that left the garage
## open would hand the next one a garage it did not build
## (LEARNED_FACTS.md §1 fact 42).
func _reset() -> void:
	_shell.show_menu()


func test_a_launch_opens_on_the_menu() -> void:
	_reset()
	check_eq(_shell.current_screen(), ShellRoot.Screen.MENU, "the shell opens on the menu")
	check_true(_shell.current_node() is MainMenu, "and the node on show is the menu")


## The one piece of state that survives a transition. A shell with no blueprint
## opens on the shipped starter, which is what makes a first launch a playable
## one rather than an empty lattice.
func test_a_session_starts_on_the_starter_build() -> void:
	check_not_null(_shell.blueprint, "the shell carries a blueprint")
	check_true(_shell.blueprint.size() > 0, "and it is not empty")


func test_the_menu_leads_to_the_garage_and_back() -> void:
	_reset()
	_shell.show_garage()
	check_eq(_shell.current_screen(), ShellRoot.Screen.GARAGE, "the garage is on show")
	var garage := _shell.current_node() as GarageScreen
	check_not_null(garage, "and the node on show is the garage")

	_shell.show_menu()
	check_eq(_shell.current_screen(), ShellRoot.Screen.MENU, "and the menu is reachable again")
	# The release is deferred to the end of the frame, because a transition
	# arrives inside a signal the outgoing screen is still emitting. Removal is
	# immediate; deletion is not.
	await physics_frames(2)
	check_false(
		is_instance_valid(garage),
		"the garage was released rather than hidden — one screen exists at a time"
	)


## The garage opens on the session's build, laid out through the ordinary
## validation chain. Every part on the lattice is the assertion that the
## blueprint crossed the boundary and was rebuilt, not merely carried.
func test_the_garage_opens_on_the_sessions_build() -> void:
	_reset()
	_shell.show_garage()
	var garage := _shell.current_node() as GarageScreen
	check_not_null(garage, "the garage is on show")
	if garage == null:
		return
	check_not_null(garage.context, "it built a context")
	check_eq(
		Blueprint.from_context(garage.context).size(),
		_shell.blueprint.size(),
		"and put every part of the session's build on the lattice"
	)
	check_not_null(
		garage.context.state(SyndicateConstants.CORE_SLOT),
		"with the Core Module on slot 0 (Invariant I-2)"
	)
	_reset()


## The garage edits a copy. A player who leaves through the menu without driving
## keeps the build they last drove, which is what makes "try something" safe.
func test_the_garage_edits_a_copy_of_the_sessions_build() -> void:
	_reset()
	var before := _shell.blueprint.size()
	_shell.show_garage()
	var garage := _shell.current_node() as GarageScreen
	check_not_null(garage, "the garage is on show")
	if garage == null:
		return
	PlacementValidator.remove(garage.context, _highest_slot(garage.context))
	check_eq(
		Blueprint.from_context(garage.context).size(),
		before - 1,
		"the edit landed on the garage's own build"
	)
	_shell.show_menu()
	check_eq(
		_shell.blueprint.size(),
		before,
		"and an edit that was never driven does not change the session's build"
	)


## The handoff, which is the whole point of the screen flow: what a player built
## is what a match is given.
func test_a_test_drive_hands_the_edited_build_to_the_match() -> void:
	await _open_match_once()
	check_eq(
		_screen_after_drive, ShellRoot.Screen.MATCH, "a test drive opens a match"
	)
	check_true(_match_screen_valid, "and the node on show is the match")
	check_eq(
		_match_blueprint_size,
		_edited_size,
		"which was handed the build the garage had, one part lighter than the starter"
	)
	check_eq(
		_session_size_after_drive,
		_edited_size,
		"and the session's build is now the one that was driven"
	)


## A match hands the player back. This is the exit the project did not have: the
## match concluded, and the only way to play again was to quit the process.
func test_a_match_can_hand_the_player_back_to_the_garage() -> void:
	await _open_match_once()
	check_eq(
		_screen_after_leaving_match,
		ShellRoot.Screen.GARAGE,
		"the garage is reachable from a finished match"
	)
	check_true(_match_freed_on_exit, "and the match was released on the way out")


## Opens the one match this file spends its budget on, and records everything the
## two methods above assert.
##
## Run once, for [code]tests/physics/[/code]'s reason: the fixture is expensive
## and a property of it is recorded when it is built, not when a method happens
## to ask (LEARNED_FACTS.md §1 facts 42 and 43).
func _open_match_once() -> void:
	if _match_opened:
		return
	_match_opened = true

	_reset()
	_shell.show_garage()
	var garage := _shell.current_node() as GarageScreen
	if garage == null:
		fail("the garage did not open")
		return
	PlacementValidator.remove(garage.context, _highest_slot(garage.context))
	var edited := Blueprint.from_context(garage.context)
	_edited_size = edited.size()

	# What the Test Drive button raises, without a button: the signal carries the
	# build and the shell decides what happens to it.
	garage.test_drive_requested.emit(edited)
	_screen_after_drive = _shell.current_screen()
	_session_size_after_drive = _shell.blueprint.size()
	var match_screen := _shell.current_node() as MatchScreen
	_match_screen_valid = match_screen != null
	if match_screen != null:
		_match_blueprint_size = match_screen.player_blueprint.size()
		match_screen.garage_requested.emit()
	_screen_after_leaving_match = _shell.current_screen()
	await physics_frames(2)
	_match_freed_on_exit = not is_instance_valid(match_screen)
	_reset()
	await physics_frames(2)


## The highest occupied slot: a leaf by construction, so removing it exercises no
## cascade and the edit is exactly one part.
static func _highest_slot(ctx: BuildContext) -> int:
	for slot: int in range(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY - 1, -1, -1):
		if ctx.state(slot) != null:
			return slot
	return SyndicateConstants.INVALID_SLOT
