class_name ControlCard
extends CenterContainer
## The card that tells a first-time player which keys do anything, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §14.6.
##
## It exists because the game had no way at all to learn its controls: no
## prompts, no pause screen, no settings. [code]C[/code] for the camera toggle is
## not guessable and [code]Escape[/code] releasing the mouse is not discoverable,
## and a player who never finds either plays a different, worse game than the one
## that was built.
##
## [b]Every binding on it comes from [InputPrompt][/b], which reads [InputMap].
## A card that listed §7.1's defaults would be wrong for every player who has
## rebound anything, and wrong silently.
##
## [b]It declares no per-frame callback[/b] — Invariant I-4's discipline applied
## to presentation. Its dwell is aged by [MatchHud], which already has the one
## allowlisted [code]_process[/code] in the HUD and already ages the event feed
## against real time for §14.4. A second timer on a second node would be a second
## answer to how long a message stays up.

## ===== TIMING (§14.6) ==================================================

## How long the card stays up unprompted at the start of a match. Long enough to
## read eight rows without hurrying, short enough that it is gone before the
## opponents arrive — they close in about fifteen seconds.
const DWELL_S: float = 11.0
## The fade at the end of the dwell, borrowed from §9.2's toast so that
## everything in this interface that goes away goes away at the same speed.
const FADE_S: float = 0.35

const PANEL_MIN_WIDTH_PX: float = 300.0
const ROW_SEPARATION_PX: int = 2

## Fraction of the viewport height the card is centred within, measured from the
## top.
##
## [b]Not the whole screen, and this was found by looking at it.[/b] Centred on
## the viewport the card sits exactly on top of the player's own Assembly, which
## §13.5 frames at about the middle — so the first thing a new player is shown is
## a panel over the one object the panel is telling them how to drive. Centred in
## the upper two fifths it clears the hull and still reads as the thing to look
## at, because nothing else is up there.
const VERTICAL_BAND: float = 0.44

## ===== STRING KEYS =====================================================
## CLAUDE.md §10 rule 8: never a literal user-facing string.

const KEY_TITLE: StringName = &"hud.controls.title"
const KEY_DRIVE: StringName = &"hud.controls.drive"
const KEY_STEER: StringName = &"hud.controls.steer"
const KEY_AIM: StringName = &"hud.controls.aim"
const KEY_FIRE: StringName = &"hud.controls.fire"
const KEY_CAMERA: StringName = &"hud.controls.camera"
const KEY_ZOOM: StringName = &"hud.controls.zoom"
const KEY_RELEASE_MOUSE: StringName = &"hud.controls.release_mouse"
const KEY_TOGGLE_HINT: StringName = &"hud.controls.toggle_hint"
## The aim row has no action behind it: §13.6 reads mouse motion directly,
## because Godot cannot bind a motion event to an action at all.
const KEY_MOUSE_MOTION: StringName = &"input.mouse.motion"

## ===== ACTIONS =========================================================
## The rows, in the order a player needs them: move, then aim, then shoot, then
## everything that is only discoverable by being told.

const ACTION_THROTTLE: StringName = &"veh_throttle"
const ACTION_BRAKE: StringName = &"veh_brake"
const ACTION_STEER_LEFT: StringName = &"veh_steer_left"
const ACTION_STEER_RIGHT: StringName = &"veh_steer_right"
const ACTION_FIRE: StringName = &"effector_fire_primary"
const ACTION_CAMERA: StringName = &"cam_toggle_view"
const ACTION_ZOOM_IN: StringName = &"cam_zoom_in"
const ACTION_ZOOM_OUT: StringName = &"cam_zoom_out"
const ACTION_RELEASE_MOUSE: StringName = &"build_cancel"
const ACTION_TOGGLE_CARD: StringName = &"hud_toggle_stats"

## Seconds of dwell left, or zero when the card is down. Negative is not a state:
## the card is either up with time on it or not up at all.
var _remaining_s: float = 0.0
## Rows are rebuilt whenever the card is raised, so a rebind made between two
## matches — or between two presses of [constant ACTION_TOGGLE_CARD] — is on the
## card the next time it is read.
var _rows: VBoxContainer = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_bottom = VERTICAL_BAND
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var panel := PanelContainer.new()
	panel.name = "CardPanel"
	panel.theme_type_variation = &"DockPanel"
	panel.custom_minimum_size.x = PANEL_MIN_WIDTH_PX
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", ROW_SEPARATION_PX)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_rows)


## Raises the card and restarts its dwell, rebuilding every row from the live
## [InputMap].
func raise() -> void:
	_rebuild()
	_remaining_s = DWELL_S
	modulate.a = 1.0
	visible = true


func dismiss() -> void:
	_remaining_s = 0.0
	visible = false


func is_raised() -> bool:
	return _remaining_s > 0.0


## [constant ACTION_TOGGLE_CARD]'s behaviour, as one call so that the HUD does
## not have to know which of the two states the card is in.
func toggle() -> void:
	if is_raised():
		dismiss()
	else:
		raise()


## Ages the dwell by [param dt] seconds of real time, fading over the last
## [constant FADE_S] of it. Driven by [MatchHud]; see the class comment.
func age(dt: float) -> void:
	if _remaining_s <= 0.0:
		return
	_remaining_s -= dt
	if _remaining_s <= 0.0:
		dismiss()
		return
	modulate.a = minf(1.0, _remaining_s / FADE_S)


## ===== PRIVATE =========================================================


func _rebuild() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()

	var title := Label.new()
	title.theme_type_variation = &"StatValue"
	title.text = tr(KEY_TITLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(title)

	_add_row(KEY_DRIVE, InputPrompt.label_for_pair(ACTION_THROTTLE, ACTION_BRAKE))
	_add_row(KEY_STEER, InputPrompt.label_for_pair(ACTION_STEER_LEFT, ACTION_STEER_RIGHT))
	_add_row(KEY_AIM, tr(KEY_MOUSE_MOTION))
	_add_row(KEY_FIRE, InputPrompt.label_for(ACTION_FIRE))
	_add_row(KEY_CAMERA, InputPrompt.label_for(ACTION_CAMERA))
	_add_row(KEY_ZOOM, InputPrompt.label_for_pair(ACTION_ZOOM_IN, ACTION_ZOOM_OUT))
	_add_row(KEY_RELEASE_MOUSE, InputPrompt.label_for(ACTION_RELEASE_MOUSE))

	var hint := Label.new()
	hint.theme_type_variation = &"StatCaption"
	hint.text = tr(KEY_TOGGLE_HINT) % InputPrompt.label_for(ACTION_TOGGLE_CARD)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(hint)


## A caption on the left and its binding on the right, matching §14.2's stat rows
## so that the card reads as part of the same interface as the status panel.
func _add_row(caption_key: StringName, binding: String) -> void:
	var row := HBoxContainer.new()
	_rows.add_child(row)

	var caption := Label.new()
	caption.theme_type_variation = &"StatCaption"
	caption.text = tr(caption_key)
	caption.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	row.add_child(caption)

	var value := Label.new()
	value.theme_type_variation = &"StatValue"
	value.text = binding
	row.add_child(value)
