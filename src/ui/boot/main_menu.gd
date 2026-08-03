class_name MainMenu
extends Control
## The first thing a player sees, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §15.2.
##
## Until session 26 the project launched straight into a match, and the reason it
## did was that there was nowhere else to go: one scene, no way back to it, and a
## player who lost in a minute had to quit the process. A menu is not window
## dressing on that — it is the screen that makes every other one leavable.
##
## It holds no game state and survives no transition. [ShellRoot] frees it on the
## way to the garage and builds a new one on the way back, which is what keeps
## the shell's rule true: exactly one screen exists at a time.

## Raised when the player chooses to build. The garage is the only way into a
## match, deliberately: a player who has never seen the build screen does not
## know the game has one.
signal garage_requested
signal quit_requested

const TITLE_KEY: StringName = &"menu.title"
const SUBTITLE_KEY: StringName = &"menu.subtitle"
const KEY_ENTER_GARAGE: StringName = &"menu.action.garage"
const KEY_QUIT: StringName = &"menu.action.quit"

const PANEL_MIN_WIDTH_PX: float = 420.0
const ROW_SEPARATION_PX: int = 10
const BUTTON_MIN_HEIGHT_PX: float = 40.0

var _garage_button: Button = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = UiTokens.SURFACE_BASE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var centre := CenterContainer.new()
	centre.name = "Centre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := PanelContainer.new()
	panel.name = "MenuPanel"
	panel.theme_type_variation = &"DockPanel"
	panel.custom_minimum_size.x = PANEL_MIN_WIDTH_PX
	centre.add_child(panel)

	var margin := MarginContainer.new()
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", ROW_SEPARATION_PX)
	margin.add_child(rows)

	var title := Label.new()
	title.theme_type_variation = &"StatValue"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = tr(TITLE_KEY)
	rows.add_child(title)

	var subtitle := Label.new()
	subtitle.theme_type_variation = &"StatCaption"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.text = tr(SUBTITLE_KEY)
	rows.add_child(subtitle)

	_garage_button = _add_button(rows, KEY_ENTER_GARAGE)
	_garage_button.theme_type_variation = &"PrimaryButton"
	_garage_button.pressed.connect(func() -> void: garage_requested.emit())

	var quit_button := _add_button(rows, KEY_QUIT)
	quit_button.pressed.connect(func() -> void: quit_requested.emit())


func _ready() -> void:
	# A gamepad and a keyboard both need somewhere for focus to start; §7.4's
	# focus navigation has nothing to navigate from otherwise, and the first
	# screen of the game is the worst place to make a player find the mouse.
	_garage_button.grab_focus()
	InputMethod.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _add_button(rows: VBoxContainer, key: StringName) -> Button:
	var button := Button.new()
	button.text = tr(key)
	button.custom_minimum_size.y = BUTTON_MIN_HEIGHT_PX
	rows.add_child(button)
	return button
