class_name MeterRow
extends VBoxContainer
## A labelled bar with a value readout, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §6.1.
##
## Shared by the garage stat panel and the match HUD. §6.1's rule holds in both:
## over budget is [i]shown[/i], never blocked. The placement validator already
## refuses an illegal build, so a meter in the red is information rather than an
## error — and in a match it is the difference between a player understanding why
## their Assembly slowed down and a player thinking it broke.
##
## §10 rule 5: the bar carries a colour and the readout carries the numbers, so
## the same state is legible without either one.

## §6.1 lets a bar overrun its budget by this much before it stops growing, so
## "slightly over" and "hopelessly over" are distinguishable.
const OVERRUN_LIMIT: float = 1.25

var _caption: Label = null
var _value: Label = null
var _bar: ProgressBar = null


func _init() -> void:
	add_theme_constant_override("separation", 1)

	var head := HBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	add_child(head)

	_caption = Label.new()
	_caption.theme_type_variation = &"StatCaption"
	_caption.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	head.add_child(_caption)

	_value = Label.new()
	_value.theme_type_variation = &"StatValue"
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_value)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.custom_minimum_size.y = 4.0
	add_child(_bar)


## [param caption_key] is a [method Object.tr] key, never a literal (§10 rule 1).
func configure(caption_key: StringName) -> void:
	_caption.text = tr(caption_key)


## Fills the bar to [param current] against [param limit] and colours it by
## §6.1's thresholds.
func set_values(current: float, limit: float, text: String) -> void:
	var ratio := current / maxf(limit, SyndicateConstants.EPSILON_LINEAR)
	_bar.value = clampf(ratio, 0.0, OVERRUN_LIMIT) * 100.0
	_bar.modulate = UiTokens.meter_colour(ratio)
	_value.text = text


## Fills the bar where a [i]high[/i] value is the healthy one — integrity rather
## than power draw. The colour ramp is inverted against
## [method UiTokens.meter_colour], which is written for usage against a budget.
func set_condition(fraction: float, text: String) -> void:
	var f := clampf(fraction, 0.0, 1.0)
	_bar.value = f * 100.0
	_bar.modulate = UiTokens.meter_colour(1.0 - f)
	_value.text = text
