class_name MatchEndCard
extends CenterContainer
## What a player is told when the match is over, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §16.2.
##
## Before this existed the Core Module went, the event feed said so in red, and
## the match carried on with a camera bolted to a corpse. The event had a
## producer and no consumer; this is the visible half of the one [MatchState]
## gave it.
##
## [b]It is raised once and never lowered.[/b] §16.2: a match concludes exactly
## once, so there is no dismissal, no timer, and no second state to be in. What
## the card does say is that the camera is now free — because it is, and because
## a player looking at a wreck with no idea they may look away is being shown a
## bug rather than an ending — and how to leave, which §16.3 could not say until
## §15 had a screen to leave to.
##
## Like [ControlCard] it declares no per-frame callback and is faded in by
## [MatchHud]; see that class for why there is one timer in this interface.

## Seconds the card takes to fade up. Long enough that it reads as an ending
## rather than as a popup, short enough that a player who has just been
## destroyed is not left wondering whether the game has stopped responding.
const FADE_IN_S: float = 0.9

const PANEL_MIN_WIDTH_PX: float = 380.0
const ROW_SEPARATION_PX: int = 6

## Fraction of the viewport height the card is centred within, measured from the
## top. Above centre for [ControlCard]'s reason and one of its own: the card
## tells the player the camera is theirs now, and centred it sits exactly on the
## wreck it is inviting them to look at.
const VERTICAL_BAND: float = 0.60

## ===== STRING KEYS =====================================================

const KEY_VICTORY: StringName = &"hud.outcome.victory"
const KEY_DEFEAT: StringName = &"hud.outcome.defeat"
const KEY_DRAW: StringName = &"hud.outcome.draw"
const KEY_DETAIL_VICTORY: StringName = &"hud.outcome.detail.victory"
const KEY_DETAIL_DEFEAT: StringName = &"hud.outcome.detail.defeat"
const KEY_DETAIL_DRAW: StringName = &"hud.outcome.detail.draw"
## Takes the camera-toggle binding: what a player may still do with the picture.
const KEY_HINT: StringName = &"hud.outcome.hint"
## Takes the rematch binding and the garage binding, in that order. The two ways
## out of a finished match.
const KEY_EXITS: StringName = &"hud.outcome.exits"

const ACTION_CAMERA: StringName = &"cam_toggle_view"
const ACTION_REMATCH: StringName = &"ui_accept"
const ACTION_GARAGE: StringName = &"build_cancel"

var _title: Label = null
var _detail: Label = null
var _hint: Label = null
var _exits: Label = null
var _elapsed_s: float = 0.0
var _raised: bool = false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_bottom = VERTICAL_BAND
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var panel := PanelContainer.new()
	panel.name = "OutcomePanel"
	panel.theme_type_variation = &"DockPanel"
	panel.custom_minimum_size.x = PANEL_MIN_WIDTH_PX
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", ROW_SEPARATION_PX)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(rows)

	_title = Label.new()
	_title.theme_type_variation = &"StatValue"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_title)

	_detail = Label.new()
	_detail.theme_type_variation = &"StatCaption"
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_detail)

	_hint = Label.new()
	_hint.theme_type_variation = &"StatCaption"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_hint)

	_exits = Label.new()
	_exits.theme_type_variation = &"StatValue"
	_exits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_exits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_exits)


## Raises the card for [param outcome], a [enum MatchState.Outcome].
##
## [constant MatchState.Outcome.UNDECIDED] is ignored rather than asserted: it is
## the value the state machine holds for the whole match, and a card that brought
## the game down when handed it would turn a wiring slip into a crash at the one
## moment a player is least able to tell what went wrong.
func show_outcome(outcome: int) -> void:
	if outcome == MatchState.Outcome.UNDECIDED or _raised:
		return
	_title.text = tr(title_key_for(outcome))
	_title.modulate = colour_for(outcome)
	_detail.text = tr(detail_key_for(outcome))
	_hint.text = tr(KEY_HINT) % InputPrompt.label_for(ACTION_CAMERA)
	# The two exits are the last line and the largest, because they are the
	# answer to the question a player has at this moment. Until session 26 there
	# was no answer: the match ended, and the only way to play again was to quit
	# the process and relaunch.
	_exits.text = (
		tr(KEY_EXITS)
		% [InputPrompt.label_for(ACTION_REMATCH), InputPrompt.label_for(ACTION_GARAGE)]
	)
	_raised = true
	_elapsed_s = 0.0
	modulate.a = 0.0
	visible = true


func is_raised() -> bool:
	return _raised


## Advances the fade by [param dt] seconds of real time. Driven by [MatchHud].
func age(dt: float) -> void:
	if not _raised or _elapsed_s >= FADE_IN_S:
		return
	_elapsed_s = minf(FADE_IN_S, _elapsed_s + dt)
	modulate.a = _elapsed_s / FADE_IN_S


## §16.2's table, as three statics so that the mapping is assertable without a
## match, a HUD, or a viewport.
static func title_key_for(outcome: int) -> StringName:
	match outcome:
		MatchState.Outcome.VICTORY:
			return KEY_VICTORY
		MatchState.Outcome.DEFEAT:
			return KEY_DEFEAT
	return KEY_DRAW


static func detail_key_for(outcome: int) -> StringName:
	match outcome:
		MatchState.Outcome.VICTORY:
			return KEY_DETAIL_VICTORY
		MatchState.Outcome.DEFEAT:
			return KEY_DETAIL_DEFEAT
	return KEY_DETAIL_DRAW


## §10 rule 5 is satisfied by the words rather than by the colour — the three
## titles are three different sentences — so the token here is emphasis and never
## the only carrier of the meaning.
static func colour_for(outcome: int) -> Color:
	match outcome:
		MatchState.Outcome.VICTORY:
			return UiTokens.ACCENT_SECONDARY
		MatchState.Outcome.DEFEAT:
			return UiTokens.DANGER
	return UiTokens.WARN
