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
##
## [b]It stands down when the player shows they do not need it, and it sits out of
## the way until then.[/b] Both halves were found by looking at a capture rather
## than at a test: centred, it covered exactly the band of screen the opponent
## approaches through, for the whole of the opening engagement, which is decided
## inside its own dwell. §14.6 owns both constants.
##
## [b]And the fight waits for it.[/b] Moving the card out of the middle of the
## screen stopped it hiding the opponent and did nothing about the opponent
## arriving at four seconds into an eleven-second dwell: the capture that verified
## the first-run rule has the player at 63% integrity with a part gone, stationary,
## still reading. §14.6's briefing hold is the answer — doc 05 §15.7.4 keeps an
## [AiDriver]'s trigger cold while [method is_briefing] is true — and it costs the
## player nothing they would want, because the card collapses to its fade the
## instant they touch a control.

## ===== TIMING (§14.6) ==================================================

## How long the card stays up unprompted at the start of a match, for a player
## who does nothing at all. It is a ceiling rather than a duration:
## [method age] takes the card down as soon as the player drives, steers, or
## fires, which is almost always first.
const DWELL_S: float = 11.0
## The fade at the end of the dwell, borrowed from §9.2's toast so that
## everything in this interface that goes away goes away at the same speed. It is
## also what the dwell collapses to when the player acts, so the card leaves the
## same way whichever thing takes it down.
const FADE_S: float = 0.35

const PANEL_MIN_WIDTH_PX: float = 300.0
const ROW_SEPARATION_PX: int = 2

## ===== PLACEMENT (§14.6) ===============================================

## The band of viewport the card is laid out inside, as fractions of the whole,
## and the inset from the two edges it hugs.
##
## [b]The upper left, and this was decided by looking at a capture.[/b] Centred —
## which is what this was, in the upper two fifths — the card covers the middle of
## the screen for the whole of a dwell that the opening engagement is decided
## inside. An opponent closes from ahead, so "the middle" is precisely where a
## first-time player needs to be looking, and the capture that found it — taken
## when the match spawned three of them — has one directly behind the panel at
## seven seconds.
##
## The other three corners are taken: §14.2's status panel is bottom left, §14.3's
## speed readout bottom right, and §14.4's event feed top right. The upper left is
## the only quarter of this interface with nothing in it, which is why the card
## can be moved at all rather than merely shrunk.
const BAND_LEFT: float = 0.0
const BAND_TOP: float = 0.0
const BAND_RIGHT: float = 0.34
const BAND_BOTTOM: float = 0.66
const BAND_INSET_PX: float = 16.0

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

## ===== STAND-DOWN (§14.6) ==============================================

## The actions that count as the player having learned the controls.
##
## Driving, steering, and firing — the three the card is mostly there to teach,
## and the three a player reaches for first. Deliberately [b]not[/b] the camera
## toggle, the zoom, or the mouse release: those are the rows a player is least
## likely to find on their own, so pressing one is not evidence they have read the
## rest, and the card being up is how they find the next one.
const ACTED_ACTIONS: Array[StringName] = [
	ACTION_THROTTLE, ACTION_BRAKE, ACTION_STEER_LEFT, ACTION_STEER_RIGHT, ACTION_FIRE
]

## Seconds of dwell left, or zero when the card is down. Negative is not a state:
## the card is either up with time on it or not up at all.
var _remaining_s: float = 0.0
## True only while the card is up because this is the player's first match, and
## false the moment it is up because they asked for it.
##
## The distinction exists because §14.6's briefing hold rides on it: doc 05
## §15.7.4 stops an [AiDriver] firing while a first-time player is reading, and a
## hold keyed on "the card is visible" would be a hold a player could take at
## will by leaning on [constant ACTION_TOGGLE_CARD]. A briefing is something the
## game gives once; a legend is something the player asks for and pays nothing
## for.
var _briefing: bool = false
## Rows are rebuilt whenever the card is raised, so a rebind made between two
## matches — or between two presses of [constant ACTION_TOGGLE_CARD] — is on the
## card the next time it is read.
var _rows: VBoxContainer = null


func _init() -> void:
	anchor_left = BAND_LEFT
	anchor_top = BAND_TOP
	anchor_right = BAND_RIGHT
	anchor_bottom = BAND_BOTTOM
	offset_left = BAND_INSET_PX
	offset_top = BAND_INSET_PX
	offset_right = 0.0
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
##
## This is the [b]player asked for it[/b] route. It clears the briefing, so a card
## raised by [constant ACTION_TOGGLE_CARD] mid-match buys no grace from doc 05
## §15.7.4 — see [member _briefing].
func raise() -> void:
	_briefing = false
	_raise()


## Raises the card as §14.6's first-run briefing: identical presentation, and it
## holds the opponent's fire for as long as it is up.
func raise_first_run() -> void:
	_briefing = true
	_raise()


func dismiss() -> void:
	_remaining_s = 0.0
	_briefing = false
	visible = false


func is_raised() -> bool:
	return _remaining_s > 0.0


## True while §14.6's first-run briefing is on screen. Doc 05 §15.7.4's third
## gate reads this, through [method MatchHud.briefing_is_up].
func is_briefing() -> bool:
	return _briefing and is_raised()


## [constant ACTION_TOGGLE_CARD]'s behaviour, as one call so that the HUD does
## not have to know which of the two states the card is in.
func toggle() -> void:
	if is_raised():
		dismiss()
	else:
		raise()


## Ages the dwell by [param dt] seconds of real time, fading over the last
## [constant FADE_S] of it. Driven by [MatchHud]; see the class comment.
##
## A player who drives, steers, or fires has demonstrated the half of this card
## that matters, so the remaining dwell collapses to the fade rather than running
## out on a clock. It reads the live [InputMap] through
## [method Input.is_action_pressed] and never a keycode, so a rebind is honoured
## here exactly as it is on the row that lists it.
func age(dt: float) -> void:
	if _remaining_s <= 0.0:
		return
	if _remaining_s > FADE_S and player_has_acted():
		_remaining_s = FADE_S
	_remaining_s -= dt
	if _remaining_s <= 0.0:
		dismiss()
		return
	modulate.a = minf(1.0, _remaining_s / FADE_S)


## True while the player is holding any of [constant ACTED_ACTIONS].
##
## Public because it is the whole of the stand-down rule and a test that could
## only reach it through [method age] would be asserting two things at once.
func player_has_acted() -> bool:
	for action: StringName in ACTED_ACTIONS:
		if Input.is_action_pressed(action):
			return true
	return false


## ===== PRIVATE =========================================================


func _raise() -> void:
	_rebuild()
	_remaining_s = DWELL_S
	modulate.a = 1.0
	visible = true


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
