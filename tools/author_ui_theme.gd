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
## Only the types with a consumer today are emitted. The garage variations §8.1
## lists — [code]PartCard[/code], [code]ToolbarButton[/code],
## [code]SheetPanel[/code] — are added with the garage that uses them; authoring
## them now would be guessing at metrics nothing can check.

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


func _process(_dt: float) -> bool:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE_BASE

	_add_labels(theme)
	_add_panels(theme)
	_add_progress_bar(theme)

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


func _panel_box(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(colour, PANEL_ALPHA)
	box.set_corner_radius_all(PANEL_CORNER_PX)
	box.content_margin_left = PANEL_MARGIN_PX
	box.content_margin_right = PANEL_MARGIN_PX
	box.content_margin_top = PANEL_MARGIN_PX
	box.content_margin_bottom = PANEL_MARGIN_PX
	return box
