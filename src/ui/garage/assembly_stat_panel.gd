class_name AssemblyStatPanel
extends VBoxContainer
## The garage's read-out of what the build weighs, draws and can survive, owned
## by [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §6.
##
## [b]It never asks the build anything.[/b] §6's rule and Architectural Invariant
## I-4: it connects to [signal EventBusService.assembly_structure_changed] to dim
## itself and to [signal EventBusService.assembly_stats_ready] to fill itself, and
## it declares no per-frame callback at all. A panel that polled a
## [BuildContext] would be recomputing a mass solve sixty times a second for a
## build nobody is editing.
##
## The dimmed pending state between the two signals is honest feedback rather
## than a stall: the solve runs on a worker and lands on the next tick, so the
## panel is briefly showing the numbers for the build as it was one part ago and
## says so.
##
## §6.1's rule holds throughout: over budget is [i]shown[/i], never blocked. The
## placement validator already refuses an illegal build, so a meter in the red is
## information — and in Sandbox mode, where the soft limits are advisory, it is
## the only information there is.

## Alpha the values are drawn at while a solve is in flight.
const PENDING_ALPHA: float = 0.45
const ROW_SEPARATION_PX: int = 4

## ===== STRING KEYS =====================================================

const KEY_TITLE: StringName = &"garage.stats.title"
const KEY_MASS: StringName = &"garage.stats.mass"
const KEY_POWER: StringName = &"garage.stats.power"
const KEY_MOUNTS: StringName = &"garage.stats.mounts"
const KEY_PARTS: StringName = &"garage.stats.parts"
const KEY_SPEED: StringName = &"garage.stats.speed"
const KEY_INTEGRITY: StringName = &"garage.stats.integrity"
const KEY_STABILITY: StringName = &"garage.stats.stability"
## Takes a value and its budget: "1107 / 4200 kg".
const KEY_MASS_VALUE: StringName = &"garage.stats.mass.value"
const KEY_POWER_VALUE: StringName = &"garage.stats.power.value"
const KEY_MOUNTS_VALUE: StringName = &"garage.stats.mounts.value"
const KEY_PARTS_VALUE: StringName = &"garage.stats.parts.value"
const KEY_SPEED_VALUE: StringName = &"garage.stats.speed.value"
const KEY_INTEGRITY_VALUE: StringName = &"garage.stats.integrity.value"
const KEY_STABILITY_VALUE: StringName = &"garage.stats.stability.value"

## Static stability factor below which the build is shown in the warning colour,
## and below which in the danger colour. Doc 05 §5.1: the SSF is the lateral
## acceleration in `g` at which the Assembly tips, so 1.0 is a build that rolls
## over in a hard turn and 0.7 is one that rolls over on a camber.
const STABILITY_WARN_G: float = 1.0
const STABILITY_DANGER_G: float = 0.7

## The Assembly this panel reports on. Set by the garage before the panel enters
## the tree; a panel with no id shows every Assembly's stats, which in a garage
## with one build is the same thing and in a garage with two is a defect.
var assembly_id: int = 0

var _mass: MeterRow = null
var _power: MeterRow = null
var _mounts: MeterRow = null
var _parts: MeterRow = null
var _speed: Label = null
var _integrity: Label = null
var _stability: Label = null
var _values: VBoxContainer = null
var _last: AssemblyStats = null


func _init() -> void:
	add_theme_constant_override("separation", ROW_SEPARATION_PX)

	var title := Label.new()
	title.theme_type_variation = &"StatCaption"
	title.text = tr(KEY_TITLE)
	add_child(title)

	_values = VBoxContainer.new()
	_values.name = "Values"
	_values.add_theme_constant_override("separation", ROW_SEPARATION_PX)
	add_child(_values)

	_mass = _add_meter(KEY_MASS)
	_power = _add_meter(KEY_POWER)
	_mounts = _add_meter(KEY_MOUNTS)
	_parts = _add_meter(KEY_PARTS)
	_speed = _add_row(KEY_SPEED)
	_integrity = _add_row(KEY_INTEGRITY)
	_stability = _add_row(KEY_STABILITY)


## §6 connects the pending state to
## [signal EventBusService.assembly_structure_changed] alone. In a garage that is
## not enough and the difference is not cosmetic: that signal is emitted by
## [DetachmentScheduler] when an island comes off, which is a match event, and
## the thing a player does in a garage is attach and remove parts. Both are
## reasons the numbers on the screen are now one edit old, so both dim it.
func _ready() -> void:
	EventBus.assembly_structure_changed.connect(_on_structure_changed)
	EventBus.part_attached.connect(_on_part_changed)
	EventBus.part_removed.connect(_on_part_changed)
	EventBus.assembly_stats_ready.connect(_on_stats_ready)


func _exit_tree() -> void:
	EventBus.assembly_structure_changed.disconnect(_on_structure_changed)
	EventBus.part_attached.disconnect(_on_part_changed)
	EventBus.part_removed.disconnect(_on_part_changed)
	EventBus.assembly_stats_ready.disconnect(_on_stats_ready)


## The last stats this panel was given, or null. Diagnostics and tests.
func last_stats() -> AssemblyStats:
	return _last


func _on_part_changed(changed_id: int, _slot: int) -> void:
	_on_structure_changed(changed_id)


func _on_structure_changed(changed_id: int) -> void:
	if changed_id != assembly_id:
		return
	_values.modulate.a = PENDING_ALPHA


func _on_stats_ready(stats: AssemblyStats) -> void:
	if stats.assembly_id != assembly_id:
		return
	_last = stats
	_values.modulate.a = 1.0
	present(stats)


## Fills every row from [param stats].
##
## Public and separate from the signal handler so that the mapping from a record
## to what a player reads is assertable without a bus, a tick, or a worker.
func present(stats: AssemblyStats) -> void:
	_mass.set_values(
		stats.total_mass_kg,
		stats.mass_tolerance_kg,
		tr(KEY_MASS_VALUE) % [stats.total_mass_kg, stats.mass_tolerance_kg]
	)
	_power.set_values(
		stats.power_draw_pu,
		stats.power_capacity_pu,
		tr(KEY_POWER_VALUE) % [stats.power_draw_pu, stats.power_capacity_pu]
	)
	_mounts.set_values(
		float(stats.mounts_used),
		float(stats.mount_budget),
		tr(KEY_MOUNTS_VALUE) % [stats.mounts_used, stats.mount_budget]
	)
	_parts.set_values(
		float(stats.part_count),
		float(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY),
		tr(KEY_PARTS_VALUE) % [stats.part_count, SyndicateConstants.MAX_PARTS_PER_ASSEMBLY]
	)
	_speed.text = tr(KEY_SPEED_VALUE) % stats.projected_top_speed_mps
	_integrity.text = tr(KEY_INTEGRITY_VALUE) % int(stats.total_integrity)
	_stability.text = tr(KEY_STABILITY_VALUE) % stats.rollover_lateral_g
	_stability.modulate = stability_colour(stats.rollover_lateral_g)


## §10 rule 5: the number carries the meaning and the colour is emphasis. A
## player who cannot tell amber from green still reads "0.62 g" beside a build
## that is about to fall over.
static func stability_colour(rollover_lateral_g: float) -> Color:
	if rollover_lateral_g < STABILITY_DANGER_G:
		return UiTokens.DANGER
	if rollover_lateral_g < STABILITY_WARN_G:
		return UiTokens.WARN
	return UiTokens.TEXT_PRIMARY


func _add_meter(caption_key: StringName) -> MeterRow:
	var row := MeterRow.new()
	row.configure(caption_key)
	_values.add_child(row)
	return row


## A caption and a value on one line, for the three figures that have no budget
## to be measured against. §4's tree calls this a `StatRow`; it is two labels and
## a container, and a class of its own would be a file that never grew.
func _add_row(caption_key: StringName) -> Label:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	_values.add_child(row)

	var caption := Label.new()
	caption.theme_type_variation = &"StatCaption"
	caption.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	caption.text = tr(caption_key)
	row.add_child(caption)

	var value := Label.new()
	value.theme_type_variation = &"StatValue"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return value
