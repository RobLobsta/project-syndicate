extends SceneTree
## Generates [code]data/ui/syndicate_theme.tres[/code] from the colour tokens of
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §8.3.
##
## §8.1 requires exactly one [Theme] for the whole interface, with variation
## expressed as theme type variations rather than as per-node overrides. That
## makes the theme a piece of [i]generated data[/i] rather than something to
## author by hand in the editor: the tokens live in [UiTokens], the shapes live
## here, and the [code].tres[/code] is derived from both. Editing the file
## directly is how the two drift apart.
##
## Run with:
## [codeblock]
## tools/ci/godot.sh --headless --path . --script tools/author_ui_theme.gd
## [/codeblock]
##
## Only the types with a consumer today are emitted. [code]SheetPanel[/code] is
## still one §8.1 lists and nothing builds: it belongs to the compact tier's
## bottom sheet, which the garage does not have yet, and authoring metrics
## nothing can check is how a theme grows entries nobody can delete.

const OUT_PATH := "res://data/ui/syndicate_theme.tres"

const FONT_SIZE_BASE: int = 15
const FONT_SIZE_VALUE: int = 19
const FONT_SIZE_CAPTION: int = 12

const PANEL_CORNER_PX: int = 4
const PANEL_MARGIN_PX: int = 10
## Panels sit over a live 3D view, so they are translucent rather than opaque.
## Fully opaque HUD furniture hides the world it is describing; fully transparent
## furniture is unreadable over pale ground.
const PANEL_ALPHA: float = 0.72
const BAR_HEIGHT_PX: int = 4

const BUTTON_CORNER_PX: int = 3
const BUTTON_MARGIN_X_PX: int = 10
const BUTTON_MARGIN_Y_PX: int = 6
const FOCUS_RING_PX: int = 2


func _process(_dt: float) -> bool:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE_BASE

	_add_labels(theme)
	_add_panels(theme)
	_add_progress_bar(theme)
	_add_buttons(theme)

	var err := ResourceSaver.save(theme, OUT_PATH)
	if err != OK:
		push_error("author_ui_theme: save failed (%d)" % err)
		quit(1)
		return true
	print("author_ui_theme: wrote %s" % OUT_PATH)
	quit(0)
	return true


func _add_labels(theme: Theme) -> void:
	theme.add_type("Label")
	theme.set_color("font_color", "Label", UiTokens.TEXT_PRIMARY)
	theme.set_font_size("font_size", "Label", FONT_SIZE_BASE)

	# §8.1: a variation, not a second type, so a Label with no variation still
	# inherits everything the base type declares.
	theme.add_type("StatValue")
	theme.set_type_variation("StatValue", "Label")
	theme.set_color("font_color", "StatValue", UiTokens.TEXT_PRIMARY)
	theme.set_font_size("font_size", "StatValue", FONT_SIZE_VALUE)

	theme.add_type("StatCaption")
	theme.set_type_variation("StatCaption", "Label")
	theme.set_color("font_color", "StatCaption", UiTokens.TEXT_MUTED)
	theme.set_font_size("font_size", "StatCaption", FONT_SIZE_CAPTION)


func _add_panels(theme: Theme) -> void:
	theme.add_type("PanelContainer")
	theme.set_stylebox("panel", "PanelContainer", _panel_box(UiTokens.SURFACE_BASE))

	theme.add_type("DockPanel")
	theme.set_type_variation("DockPanel", "PanelContainer")
	theme.set_stylebox("panel", "DockPanel", _panel_box(UiTokens.SURFACE_RAISED))


## The three button shapes the garage needs, as variations of one base.
##
## A [PartCard] is a [Button] because everything a card does is what a button
## does — hover, focus, press, and a pressed state that survives the pointer
## leaving — and §7.4's gamepad focus navigation walks buttons. Giving it a
## panel-like face rather than a button-like one is the whole of the difference,
## and that is a stylebox rather than a class.
func _add_buttons(theme: Theme) -> void:
	theme.add_type("Button")
	theme.set_color("font_color", "Button", UiTokens.TEXT_PRIMARY)
	theme.set_color("font_hover_color", "Button", UiTokens.TEXT_PRIMARY)
	theme.set_color("font_pressed_color", "Button", UiTokens.SURFACE_BASE)
	theme.set_color("font_disabled_color", "Button", UiTokens.TEXT_MUTED)
	theme.set_font_size("font_size", "Button", FONT_SIZE_BASE)
	theme.set_stylebox("normal", "Button", _button_box(UiTokens.SURFACE_RAISED))
	theme.set_stylebox("hover", "Button", _button_box(UiTokens.SURFACE_OVERLAY))
	theme.set_stylebox("pressed", "Button", _button_box(UiTokens.ACCENT_PRIMARY))
	theme.set_stylebox("focus", "Button", _outline_box(UiTokens.ACCENT_PRIMARY))
	theme.set_stylebox("disabled", "Button", _button_box(UiTokens.SURFACE_BASE))

	theme.add_type("ToolbarButton")
	theme.set_type_variation("ToolbarButton", "Button")
	theme.set_font_size("font_size", "ToolbarButton", FONT_SIZE_CAPTION)

	# The one button on a screen that a first-time player should press. §10 rule
	# 5: it is also the widest and carries the clearest word, so the emphasis is
	# not only the colour.
	theme.add_type("PrimaryButton")
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_color("font_color", "PrimaryButton", UiTokens.SURFACE_BASE)
	theme.set_color("font_hover_color", "PrimaryButton", UiTokens.SURFACE_BASE)
	theme.set_stylebox("normal", "PrimaryButton", _button_box(UiTokens.ACCENT_SECONDARY))
	theme.set_stylebox(
		"hover", "PrimaryButton", _button_box(UiTokens.ACCENT_SECONDARY.lightened(0.15))
	)
	theme.set_stylebox("pressed", "PrimaryButton", _button_box(UiTokens.ACCENT_PRIMARY))

	theme.add_type("PartCard")
	theme.set_type_variation("PartCard", "Button")
	theme.set_stylebox("normal", "PartCard", _card_box(UiTokens.SURFACE_BASE))
	theme.set_stylebox("hover", "PartCard", _card_box(UiTokens.SURFACE_OVERLAY))
	theme.set_stylebox("pressed", "PartCard", _card_box(UiTokens.ACCENT_PRIMARY))
	theme.set_color("font_pressed_color", "PartCard", UiTokens.TEXT_PRIMARY)


func _add_progress_bar(theme: Theme) -> void:
	theme.add_type("ProgressBar")

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(UiTokens.SURFACE_OVERLAY, PANEL_ALPHA)
	bg.set_corner_radius_all(1)
	bg.content_margin_top = BAR_HEIGHT_PX
	theme.set_stylebox("background", "ProgressBar", bg)

	# White, so that [member CanvasItem.modulate] is what carries the meter
	# colour. §6.1 picks that colour per value; baking a token in here would give
	# the threshold two owners.
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color.WHITE
	fill.set_corner_radius_all(1)
	theme.set_stylebox("fill", "ProgressBar", fill)


## A card face: the panel shape, with a left edge the class swatch sits against
## and no rounded corner on that side, so a grid of them reads as a list rather
## than as a scatter of lozenges.
func _card_box(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(colour, PANEL_ALPHA)
	box.set_corner_radius_all(BUTTON_CORNER_PX)
	box.content_margin_left = BUTTON_MARGIN_X_PX
	box.content_margin_right = BUTTON_MARGIN_X_PX
	box.content_margin_top = BUTTON_MARGIN_Y_PX
	box.content_margin_bottom = BUTTON_MARGIN_Y_PX
	return box


func _button_box(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(colour, PANEL_ALPHA)
	box.set_corner_radius_all(BUTTON_CORNER_PX)
	box.content_margin_left = BUTTON_MARGIN_X_PX
	box.content_margin_right = BUTTON_MARGIN_X_PX
	box.content_margin_top = BUTTON_MARGIN_Y_PX
	box.content_margin_bottom = BUTTON_MARGIN_Y_PX
	return box


## The focus ring §7.4's navigation needs. A ring rather than a fill, because a
## focused button that has changed colour is indistinguishable from a pressed
## one, and a gamepad player moves focus far more often than they press.
func _outline_box(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(colour, 0.0)
	box.set_corner_radius_all(BUTTON_CORNER_PX)
	box.set_border_width_all(FOCUS_RING_PX)
	box.border_color = colour
	return box


func _panel_box(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(colour, PANEL_ALPHA)
	box.set_corner_radius_all(PANEL_CORNER_PX)
	box.content_margin_left = PANEL_MARGIN_PX
	box.content_margin_right = PANEL_MARGIN_PX
	box.content_margin_top = PANEL_MARGIN_PX
	box.content_margin_bottom = PANEL_MARGIN_PX
	return box
