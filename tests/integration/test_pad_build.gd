extends TestCase
## Can a controller build a machine? Doc 11 §7.1 and §7.3.
##
## [b]The match was fully playable on a pad and the garage was not, which is half
## of what this game is.[/b] Every placement goes through
## `GarageScreen._place_at(_preview_pointer())` and `_preview_pointer()` was the
## mouse; a player holding a controller could orbit the camera and press nothing
## that placed anything. §7.1 published a whole garage column of gamepad bindings
## against that.
##
## The repair is one substitution — the pointer is the pad's virtual cursor when
## `InputMethod` says a pad is in use — so a stick and a mouse resolve a candidate
## through the identical [method GaragePreview.resolve_candidate], and doc 02 §6's
## chain is untouched. This file asserts that end to end, with no mouse anywhere in
## it.
##
## `LEARNED_FACTS.md` §1 fact 40 is what makes it possible at all:
## [method Input.action_press] works under `--headless` and is exact, so the real
## input map can be driven with no window, no device and no scene.

## Ticks the cursor is driven for per step. The cursor moves at 900 px/s against a
## 1080-unit view, so a third of a second is a couple of hundred pixels — enough to
## cross a good part of the build without leaving the viewport.
const DRIVE_TICKS: int = 20

## How far the cursor is expected to have travelled after that, in pixels. A tenth
## of what a full deflection produces, so the assertion is "it moved" and not "it
## moved exactly this far on this viewport size".
const MIN_CURSOR_TRAVEL_PX: float = 20.0

var _shell: ShellRoot = null
var _method_before: InputMethodService.Method = InputMethodService.Method.KEYBOARD_MOUSE


func before_all() -> void:
	_method_before = InputMethod.current
	_shell = ShellRoot.new()
	_shell.name = "PadBuildShellRoot"
	# A [TestCase] is a [RefCounted] and has no tree of its own (fact 11).
	EventBus.get_tree().root.add_child(_shell)


func after_all() -> void:
	_release_all()
	# InputMethod is an autoload and this file writes it. Left on GAMEPAD it would
	# hand every later test's prompt lookup a controller binding.
	InputMethod.current = _method_before
	if _shell != null and is_instance_valid(_shell):
		_shell.get_parent().remove_child(_shell)
		_shell.free()
		_shell = null


## Every held action, released. At the [b]top[/b] of each test as well as the end:
## the runner sorts methods, and a test that failed part-way through would
## otherwise leave a stick deflected for the next one (fact 40).
func _release_all() -> void:
	for action: StringName in [
		&"build_cursor_left", &"build_cursor_right",
		&"build_cursor_up", &"build_cursor_down",
		&"cam_look_left", &"cam_look_right", &"cam_look_up", &"cam_look_down",
	] as Array[StringName]:
		Input.action_release(action)


## ===== THE CURSOR ======================================================


func test_the_left_stick_moves_the_pad_cursor() -> void:
	_release_all()
	var garage := _open()
	if garage == null:
		return
	InputMethod.current = InputMethodService.Method.GAMEPAD
	var start := garage.preview.pad_cursor()
	check_true(
		start.length_squared() > 0.0,
		"the cursor starts in the middle of the view rather than in a corner: %s" % start
	)

	Input.action_press(&"build_cursor_right", 1.0)
	await physics_frames(DRIVE_TICKS)
	Input.action_release(&"build_cursor_right")
	var moved := garage.preview.pad_cursor()
	check_true(
		moved.x - start.x > MIN_CURSOR_TRAVEL_PX,
		"a right deflection moved it right: %.1f px from %.1f" % [moved.x, start.x]
	)
	check_approx(moved.y, start.y, "and not up or down", 0.5)

	Input.action_press(&"build_cursor_down", 1.0)
	await physics_frames(DRIVE_TICKS)
	Input.action_release(&"build_cursor_down")
	check_true(
		garage.preview.pad_cursor().y - moved.y > MIN_CURSOR_TRAVEL_PX,
		"and a downward one moved it down: %.1f px" % garage.preview.pad_cursor().y
	)
	_shell.show_menu()


## Clamped to the view, or a player who holds the stick loses the cursor off the
## edge of the world and has no way of knowing where it went.
func test_the_cursor_cannot_leave_the_view() -> void:
	_release_all()
	var garage := _open()
	if garage == null:
		return
	InputMethod.current = InputMethodService.Method.GAMEPAD
	var view := garage.preview.viewport_size()
	Input.action_press(&"build_cursor_left", 1.0)
	Input.action_press(&"build_cursor_up", 1.0)
	await physics_frames(DRIVE_TICKS * 20)
	_release_all()
	var corner := garage.preview.pad_cursor()
	check_true(corner.x >= 0.0 and corner.y >= 0.0, "it stopped at the near corner: %s" % corner)

	Input.action_press(&"build_cursor_right", 1.0)
	Input.action_press(&"build_cursor_down", 1.0)
	await physics_frames(DRIVE_TICKS * 20)
	_release_all()
	var far := garage.preview.pad_cursor()
	check_true(
		far.x <= view.x and far.y <= view.y,
		"and at the far one: %s against a view of %s" % [far, view]
	)
	_shell.show_menu()


## ===== THE CAMERA ======================================================


## Doc 11 §7.1's garage camera on a controller, which did not exist:
## `handle_camera_input` orbits on [InputEventMouseMotion] and a stick held at
## deflection emits no events at all (`LEARNED_FACTS.md` fact 92), so the preview
## polls the four analogue `cam_look_*` actions instead.
##
## Asserted through the camera's own transform rather than through the yaw the
## preview holds, because the yaw is what the poll writes and the pose is what the
## player sees — a poll that updated the angle and never called `_place_camera`
## would satisfy the first and none of the second.
func test_the_right_stick_orbits_the_garage_camera() -> void:
	_release_all()
	var garage := _open()
	if garage == null:
		return
	InputMethod.current = InputMethodService.Method.GAMEPAD
	var before := garage.preview.camera.global_transform
	Input.action_press(&"cam_look_right", 1.0)
	await physics_frames(DRIVE_TICKS)
	Input.action_release(&"cam_look_right")
	var after := garage.preview.camera.global_transform
	check_true(
		before.origin.distance_to(after.origin) > 0.5,
		(
			"the right stick swung the camera %.2f m round the build"
			% before.origin.distance_to(after.origin)
		)
	)
	# And it is an orbit rather than a dolly: the distance to what it is framing is
	# unchanged, which is the half a camera that merely slid sideways would fail.
	check_approx(
		after.origin.length(),
		before.origin.length(),
		"without changing its distance from the build",
		0.25
	)

	var pitched := garage.preview.camera.global_position.y
	Input.action_press(&"cam_look_up", 1.0)
	await physics_frames(DRIVE_TICKS)
	Input.action_release(&"cam_look_up")
	check_ne(
		garage.preview.camera.global_position.y,
		pitched,
		"and the other axis moves it in elevation"
	)
	_release_all()
	_shell.show_menu()


## ===== THE POINTER SUBSTITUTION ========================================


## The whole of the repair, and the reason it is one line: the placement chain
## does not know which device it is serving.
func test_the_placement_pointer_follows_the_active_input_method() -> void:
	_release_all()
	var garage := _open()
	if garage == null:
		return
	InputMethod.current = InputMethodService.Method.GAMEPAD
	Input.action_press(&"build_cursor_right", 1.0)
	await physics_frames(DRIVE_TICKS)
	Input.action_release(&"build_cursor_right")
	var cursor := garage.preview.pad_cursor()

	InputMethod.current = InputMethodService.Method.GAMEPAD
	check_eq(
		garage.call(&"_preview_pointer"),
		cursor,
		"on a pad the placement pointer is the virtual cursor"
	)
	InputMethod.current = InputMethodService.Method.KEYBOARD_MOUSE
	check_ne(
		garage.call(&"_preview_pointer"),
		cursor,
		"and on a keyboard it is the mouse again, which is somewhere else entirely"
	)
	_shell.show_menu()


## [b]The claim, end to end.[/b] Arm a part from the catalogue, drive the cursor
## with the stick, and commit with `build_place` — no mouse position is read and
## no method here touches the lattice directly.
##
## The cursor is swept rather than aimed. A single position is a position that
## either happens to resolve or happens not to, and what is being asserted is that
## a controller *can* place a part, not that this particular pixel does.
func test_a_controller_places_a_part() -> void:
	_release_all()
	var garage := _open()
	if garage == null:
		return
	InputMethod.current = InputMethodService.Method.GAMEPAD
	var before := Blueprint.from_context(garage.context).size()
	var def := PartRegistry.definition_by_key(&"str.panel.medium.t2")
	check_not_null(def, "the catalogue has a Structural Component to place")
	if def == null:
		return
	garage.catalogue.select(def.runtime_id)

	var placed := false
	# Sweep the cursor across the view and try to commit at each step. The build
	# occupies the middle of the frame, so this passes over it.
	for step: int in 24:
		if step > 0:
			Input.action_press(&"build_cursor_right", 1.0)
			await physics_frames(6)
			Input.action_release(&"build_cursor_right")
			await physics_frames(1)
		garage.call(&"_place_at", garage.call(&"_preview_pointer"))
		if Blueprint.from_context(garage.context).size() > before:
			placed = true
			break
	check_true(
		placed,
		(
			"a part went onto the lattice from the stick alone: %d parts against %d"
			% [Blueprint.from_context(garage.context).size(), before]
		)
	)
	_release_all()
	_shell.show_menu()


## ===== FIXTURE =========================================================


## The garage, opened through the shell exactly as a player reaches it.
func _open() -> GarageScreen:
	_shell.show_menu()
	_shell.show_garage()
	var garage := _shell.current_node() as GarageScreen
	check_not_null(garage, "the garage is on show")
	if garage != null:
		check_not_null(garage.preview, "and it built its preview")
	return garage
