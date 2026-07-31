class_name SettingsService
extends Node
## Autoload: [code]SyndicateSettings[/code]. User settings, quality tiers, and
## key rebinds.
##
## Loaded first of the eight autoloads because every later one may read from it.
## Rebinds are applied through [InputMap] here and nowhere else: CLAUDE.md §7.3
## forbids hard-coding a rebind anywhere in gameplay code.
##
## Quality tiers gate presentation only. Architectural Invariant I-7 guarantees
## that no value below can affect hit registration, damage, mass, or any other
## simulated quantity — a player on LOW and a player on ULTRA resolve identical
## fights.

const SETTINGS_PATH: String = "user://settings.cfg"

const SECTION_DISPLAY: String = "display"
const SECTION_QUALITY: String = "quality"
const SECTION_INPUT: String = "input"
const SECTION_NET: String = "net"

enum QualityTier { LOW = 0, MEDIUM = 1, HIGH = 2, ULTRA = 3 }

signal settings_changed(section: String, key: String)

## ===== DISPLAY =========================================================
## Multiplies the whole interface through content_scale_factor. See UiScale.
var ui_scale: float = 1.0
var high_contrast: bool = false

## ===== QUALITY =========================================================
var quality_tier: QualityTier = QualityTier.HIGH
## Resolution of the per-Assembly occupancy SDF. Presentation only.
var fusion_quality: QualityTier = QualityTier.HIGH
var debris_enabled: bool = true

## ===== NET =============================================================
var show_net_diagnostics: bool = false

## action name -> array of serialised InputEvent
var _rebinds: Dictionary = {}
var _config: ConfigFile = ConfigFile.new()


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err != OK:
		# First run, or a settings file wiped by a crash. Defaults stand and are
		# written back on the next save; this is not an error worth logging.
		return
	ui_scale = float(_config.get_value(SECTION_DISPLAY, "ui_scale", ui_scale))
	high_contrast = bool(_config.get_value(SECTION_DISPLAY, "high_contrast", high_contrast))
	quality_tier = _config.get_value(SECTION_QUALITY, "tier", quality_tier) as QualityTier
	fusion_quality = _config.get_value(SECTION_QUALITY, "fusion", fusion_quality) as QualityTier
	debris_enabled = bool(_config.get_value(SECTION_QUALITY, "debris", debris_enabled))
	show_net_diagnostics = bool(
		_config.get_value(SECTION_NET, "diagnostics", show_net_diagnostics)
	)
	_rebinds = _config.get_value(SECTION_INPUT, "rebinds", {}) as Dictionary
	apply_rebinds()


func save_settings() -> Error:
	_config.set_value(SECTION_DISPLAY, "ui_scale", ui_scale)
	_config.set_value(SECTION_DISPLAY, "high_contrast", high_contrast)
	_config.set_value(SECTION_QUALITY, "tier", int(quality_tier))
	_config.set_value(SECTION_QUALITY, "fusion", int(fusion_quality))
	_config.set_value(SECTION_QUALITY, "debris", debris_enabled)
	_config.set_value(SECTION_NET, "diagnostics", show_net_diagnostics)
	_config.set_value(SECTION_INPUT, "rebinds", _rebinds)
	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		push_error("SettingsService: could not write %s (error %d)" % [SETTINGS_PATH, err])
	return err


## Replaces every event bound to [param action]. Passing an empty array unbinds
## the action entirely, which the rebind UI uses for "clear".
func set_rebind(action: StringName, events: Array[InputEvent]) -> void:
	if not InputMap.has_action(action):
		push_error("SettingsService: rebind of unknown action '%s'" % action)
		return
	_rebinds[String(action)] = events
	_apply_action(action, events)
	settings_changed.emit(SECTION_INPUT, String(action))


func clear_rebind(action: StringName) -> void:
	if not _rebinds.has(String(action)):
		return
	_rebinds.erase(String(action))
	# The project default is restored by reloading the action from ProjectSettings.
	var defaults := ProjectSettings.get_setting("input/%s" % action, {}) as Dictionary
	var events: Array[InputEvent] = []
	for e: InputEvent in defaults.get("events", []):
		events.append(e)
	_apply_action(action, events)
	settings_changed.emit(SECTION_INPUT, String(action))


## Re-applies every stored rebind. Called at startup and after an InputMap reset.
func apply_rebinds() -> void:
	for action_name: String in _rebinds:
		var action := StringName(action_name)
		if not InputMap.has_action(action):
			push_warning("SettingsService: stored rebind for removed action '%s'" % action)
			continue
		var events: Array[InputEvent] = []
		for e: InputEvent in _rebinds[action_name]:
			events.append(e)
		_apply_action(action, events)


func set_quality_tier(tier: QualityTier) -> void:
	if quality_tier == tier:
		return
	quality_tier = tier
	settings_changed.emit(SECTION_QUALITY, "tier")


func set_ui_scale(value: float) -> void:
	var clamped := clampf(value, UiScaleService.MIN_SCALE, UiScaleService.MAX_SCALE)
	if is_equal_approx(ui_scale, clamped):
		return
	ui_scale = clamped
	settings_changed.emit(SECTION_DISPLAY, "ui_scale")


func _apply_action(action: StringName, events: Array[InputEvent]) -> void:
	InputMap.action_erase_events(action)
	for e in events:
		InputMap.action_add_event(action, e)
