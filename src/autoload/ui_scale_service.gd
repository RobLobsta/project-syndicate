class_name UiScaleService
extends Node
## Autoload: [code]UiScale[/code]. Logical size, DPI adaptation, and content
## scale, owned by [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §2.2.
##
## [code]content_scale_factor[/code] is the mechanism: it multiplies every
## Control's effective size without touching individual node properties, so one
## float rescales the entire interface with no layout code involved.
##
## The logical size this publishes is the input to the breakpoint tier, which is
## a separate axis from the active input method — a keyboard on a tablet gives a
## compact layout with a desktop interaction model, and the code treats those as
## orthogonal because they are.

signal scale_changed(logical_size: Vector2, scale: float)

const BASE_HEIGHT: float = 1080.0
const MIN_SCALE: float = 0.70
const MAX_SCALE: float = 1.60

## Reference densities for the density factor. Phones need larger controls than
## their pixel count alone implies, hence the separate mobile divisor.
const DESKTOP_REFERENCE_DPI: float = 96.0
const MOBILE_REFERENCE_DPI: float = 200.0
const DESKTOP_DENSITY_RANGE: Vector2 = Vector2(0.9, 1.35)
const MOBILE_DENSITY_RANGE: Vector2 = Vector2(1.0, 1.9)

## Size reported when there is no display server, so that headless runs produce
## the same logical size on every machine and layout tests stay deterministic.
const HEADLESS_LOGICAL_SIZE: Vector2 = Vector2(1920, 1080)

var user_scale: float = 1.0:
	set = set_user_scale
var effective_scale: float = 1.0
var logical_size: Vector2 = HEADLESS_LOGICAL_SIZE


func _ready() -> void:
	user_scale = SyndicateSettings.ui_scale
	get_tree().root.size_changed.connect(_recalculate)
	_recalculate()


func set_user_scale(value: float) -> void:
	var clamped := clampf(value, MIN_SCALE, MAX_SCALE)
	if is_equal_approx(user_scale, clamped) and is_inside_tree():
		return
	user_scale = clamped
	if is_inside_tree():
		_recalculate()


func _recalculate() -> void:
	if _is_headless():
		# No window to measure and no DPI to query. Publishing a fixed size keeps
		# server-side and test-harness layout resolution reproducible.
		effective_scale = 1.0
		logical_size = HEADLESS_LOGICAL_SIZE
		scale_changed.emit(logical_size, effective_scale)
		return
	var vp := get_tree().root.get_visible_rect().size
	effective_scale = clampf(user_scale * _density_factor(), MIN_SCALE, MAX_SCALE)
	logical_size = vp / effective_scale
	get_tree().root.content_scale_factor = effective_scale
	scale_changed.emit(logical_size, effective_scale)


func _density_factor() -> float:
	var dpi := DisplayServer.screen_get_dpi()
	if dpi <= 0:
		return 1.0
	if OS.has_feature("mobile"):
		return clampf(
			float(dpi) / MOBILE_REFERENCE_DPI, MOBILE_DENSITY_RANGE.x, MOBILE_DENSITY_RANGE.y
		)
	return clampf(
		float(dpi) / DESKTOP_REFERENCE_DPI, DESKTOP_DENSITY_RANGE.x, DESKTOP_DENSITY_RANGE.y
	)


static func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
