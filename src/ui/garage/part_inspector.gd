class_name PartInspector
extends VBoxContainer
## What a part actually does, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §4.3.
##
## A [PartCard] carries a name, a class, a tier, a cost and a mass — enough to
## find a part and not enough to choose one. Everything that makes a build a
## decision is authored on [PartDefinition] and its profiles: whether a Motive
## Assembly steers, what a Prime Mover's shaft torque is, how far an Effector
## Module can traverse, what an Energy Cell supplies. Until this class none of it
## reached the screen, and a player's only way of learning what a part did was to
## fit it and drive it.
##
## [b]The rows are a static over a definition.[/b] [method rows_for] takes a
## [PartDefinition] and returns what should be shown for it, so the mapping —
## which figures a class is described by, and in what order — is assertable
## without a garage, a viewport or a selection. The [Control] half of this class
## is a loop over that list.
##
## [b]It shows the definition, never an instance.[/b] Invariant I-11:
## [PartDefinition] is immutable after [code]PartRegistry._ready[/code], and what
## a part is worth in the abstract is what a player is choosing between. A
## damaged part's *current* integrity is doc 08's business and belongs on a HUD,
## not on a catalogue entry.

## One line: a localised caption and a formatted value.
class Row:
	extends RefCounted

	var caption_key: StringName = &""
	var value: String = ""

	func _init(key: StringName = &"", text: String = "") -> void:
		caption_key = key
		value = text


const ROW_SEPARATION_PX: int = 3
## Rows past this are dropped rather than scrolled. A dock that grows without
## bound pushes the stat panel off the screen, and a part described by more than
## a dozen figures is one whose description has stopped being readable.
const MAX_ROWS: int = 14

## ===== STRING KEYS =====================================================

const KEY_TITLE: StringName = &"garage.inspector.title"
const KEY_EMPTY: StringName = &"garage.inspector.empty"

const KEY_MASS: StringName = &"garage.part.mass"
const KEY_INTEGRITY: StringName = &"garage.part.integrity"
const KEY_ARMOUR: StringName = &"garage.part.armour"
const KEY_COST: StringName = &"garage.part.cost"
const KEY_MOUNTS: StringName = &"garage.part.mounts"
const KEY_POWER_DRAW: StringName = &"garage.part.power_draw"
const KEY_POWER_SUPPLY: StringName = &"garage.part.power_supply"

const KEY_SPEED_CAP: StringName = &"garage.part.speed_cap"
const KEY_MOUNT_BUDGET: StringName = &"garage.part.mount_budget"
const KEY_POWER_CAPACITY: StringName = &"garage.part.power_capacity"
const KEY_MASS_TOLERANCE: StringName = &"garage.part.mass_tolerance"

const KEY_FAMILY: StringName = &"garage.part.family"
const KEY_STEERING: StringName = &"garage.part.steering"
const KEY_DRIVEN: StringName = &"garage.part.driven"
const KEY_RATED_LOAD: StringName = &"garage.part.rated_load"
const KEY_GRIP: StringName = &"garage.part.grip"

const KEY_TORQUE: StringName = &"garage.part.torque"
const KEY_DISCHARGE: StringName = &"garage.part.discharge"

const KEY_CYCLE: StringName = &"garage.part.cycle"
const KEY_MUZZLE: StringName = &"garage.part.muzzle"
const KEY_TRAVERSE: StringName = &"garage.part.traverse"
const KEY_ELEVATION: StringName = &"garage.part.elevation"
const KEY_RECOIL: StringName = &"garage.part.recoil"
const KEY_REACH: StringName = &"garage.part.reach"
const KEY_SWING_ARC: StringName = &"garage.part.swing_arc"
const KEY_STRIKE: StringName = &"garage.part.strike"

const KEY_ROLE: StringName = &"garage.part.role"
const KEY_MAGNITUDE: StringName = &"garage.part.magnitude"
const KEY_GRIP_RATING: StringName = &"garage.part.grip_rating"

## ===== VALUE FORMATS ===================================================
## Localised, because a decimal separator is a translation and a unit suffix is a
## word. Every one takes exactly the figures its caption names.

const FMT_KG: StringName = &"garage.value.kg"
const FMT_PU: StringName = &"garage.value.pu"
const FMT_NM: StringName = &"garage.value.nm"
const FMT_NS: StringName = &"garage.value.ns"
const FMT_MPS: StringName = &"garage.value.mps"
const FMT_METRES: StringName = &"garage.value.m"
const FMT_SECONDS: StringName = &"garage.value.s"
const FMT_DEGREES: StringName = &"garage.value.deg"
const FMT_ARC: StringName = &"garage.value.arc"
const FMT_INT: StringName = &"garage.value.int"
const FMT_RATIO: StringName = &"garage.value.ratio"
const KEY_YES: StringName = &"garage.value.yes"
const KEY_NO: StringName = &"garage.value.no"
const KEY_FIXED: StringName = &"garage.value.fixed"

## Localisation key per [enum SupportModuleProfile.SupportRole]. A raw enum
## ordinal in front of a player is worse than no row at all.
const SUPPORT_ROLE_KEYS: Array[StringName] = [
	&"garage.role.heat_sink",
	&"garage.role.magazine_store",
	&"garage.role.integrity_field",
	&"garage.role.signature_damper",
	&"garage.role.repair_emitter",
]

## Localisation key per [enum PartEnums.MotiveKind], for the locomotion row.
## Indexed by the enum, in the enum's own order, and asserted against it in
## `tests/unit/test_part_inspector.gd` — a table indexed by an enum that is one
## entry out of step names every part after it wrongly and looks like a data
## error in the parts rather than a transposition here.
const MOTIVE_KIND_KEYS: Array[StringName] = [
	&"garage.family.wheeled_steered",
	&"garage.family.wheeled_fixed",
	&"garage.family.tracked",
	&"garage.family.omni_roller",
	&"garage.family.ambulatory",
	&"garage.family.repulsor",
	&"garage.family.rotor",
]

var _title: Label = null
var _name: Label = null
var _description: Label = null
var _rows: VBoxContainer = null


func _init() -> void:
	add_theme_constant_override("separation", ROW_SEPARATION_PX)

	_title = Label.new()
	_title.theme_type_variation = &"StatCaption"
	_title.text = tr(KEY_TITLE)
	add_child(_title)

	_name = Label.new()
	_name.theme_type_variation = &"StatValue"
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_name)

	_description = Label.new()
	_description.theme_type_variation = &"StatCaption"
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_description)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", ROW_SEPARATION_PX)
	add_child(_rows)

	clear()


## Shows [param def], or clears the dock when it is null.
func show_part(def: PartDefinition) -> void:
	if def == null:
		clear()
		return
	_name.text = tr(def.display_name_key)
	_description.text = tr(def.description_key)
	_description.visible = true
	_fill(rows_for(def))


func clear() -> void:
	_name.text = tr(KEY_EMPTY)
	_description.text = ""
	_description.visible = false
	_fill([])


func _fill(rows: Array[Row]) -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for i: int in mini(rows.size(), MAX_ROWS):
		var row: Row = rows[i]
		var line := HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
		_rows.add_child(line)

		var caption := Label.new()
		caption.theme_type_variation = &"StatCaption"
		caption.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
		caption.text = tr(row.caption_key)
		line.add_child(caption)

		var value := Label.new()
		value.theme_type_variation = &"StatCaption"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.text = row.value
		line.add_child(value)


## ===== THE TABLE =======================================================


## What is shown for [param def]: the figures every part has, then the ones its
## class is described by.
##
## The common rows come first and are the same four for every class, so a player
## comparing two parts of different classes is comparing the same lines in the
## same order. What follows is what the class is *for*, and it is deliberately
## short — an Effector Module authors thirteen numbers and four of them decide
## whether you want it.
static func rows_for(def: PartDefinition) -> Array[Row]:
	var rows: Array[Row] = []
	if def == null:
		return rows
	rows.append(Row.new(KEY_MASS, _fmt(FMT_KG, def.mass_kg)))
	rows.append(Row.new(KEY_INTEGRITY, _fmt_int(def.integrity_max)))
	rows.append(Row.new(KEY_ARMOUR, _fmt_int(def.armour_rating)))
	rows.append(Row.new(KEY_COST, _fmt_int(float(def.build_cost))))
	if def.mount_weight > 0:
		rows.append(Row.new(KEY_MOUNTS, _fmt_int(float(def.mount_weight))))
	if def.power_draw_pu > 0.0:
		rows.append(Row.new(KEY_POWER_DRAW, _fmt(FMT_PU, def.power_draw_pu)))
	if def.power_supply_pu > 0.0:
		rows.append(Row.new(KEY_POWER_SUPPLY, _fmt(FMT_PU, def.power_supply_pu)))

	match def.part_class:
		PartEnums.PartClass.CORE_MODULE:
			_append_core(rows, def.core_profile)
		PartEnums.PartClass.MOTIVE_ASSEMBLY:
			_append_motive(rows, def.motive_profile)
		PartEnums.PartClass.PRIME_MOVER:
			_append_prime_mover(rows, def.prime_mover_profile)
		PartEnums.PartClass.ENERGY_CELL:
			_append_energy_cell(rows, def.energy_cell_profile)
		PartEnums.PartClass.EFFECTOR_MODULE:
			_append_effector(rows, def.effector_profile)
		PartEnums.PartClass.SUPPORT_MODULE:
			_append_support(rows, def.support_profile)
		PartEnums.PartClass.APPENDAGE:
			_append_appendage(rows, def.appendage_profile)
	return rows


static func _append_core(rows: Array[Row], p: CoreModuleProfile) -> void:
	if p == null:
		return
	rows.append(Row.new(KEY_SPEED_CAP, _fmt(FMT_MPS, p.speed_cap_mps)))
	rows.append(Row.new(KEY_MOUNT_BUDGET, _fmt_int(float(p.mount_budget))))
	rows.append(Row.new(KEY_POWER_CAPACITY, _fmt(FMT_PU, p.power_capacity_pu)))
	rows.append(Row.new(KEY_MASS_TOLERANCE, _fmt(FMT_KG, p.mass_tolerance_kg)))


## The steering row is the one that answers a real question, and it is why this
## reads `max_steer_angle_deg` rather than the family: doc 05 ships two wheeled
## rows that differ in nothing a player can see except this, and an Assembly on
## which everything steers crabs instead of turning.
static func _append_motive(rows: Array[Row], p: MotiveAssemblyProfile) -> void:
	if p == null:
		return
	rows.append(Row.new(KEY_FAMILY, InputPrompt.tr_key(_motive_kind_key(p.kind))))
	rows.append(
		Row.new(
			KEY_STEERING,
			(
				_fmt(FMT_DEGREES, p.max_steer_angle_deg)
				if p.max_steer_angle_deg > 0.0 and p.steer_rate_deg_s > 0.0
				else InputPrompt.tr_key(KEY_FIXED)
			)
		)
	)
	rows.append(Row.new(KEY_DRIVEN, InputPrompt.tr_key(KEY_YES if p.driven else KEY_NO)))
	rows.append(Row.new(KEY_RATED_LOAD, _fmt(FMT_KG, p.rated_load_kg)))
	rows.append(Row.new(KEY_GRIP, _fmt(FMT_RATIO, p.traction_coefficient)))


static func _append_prime_mover(rows: Array[Row], p: PrimeMoverProfile) -> void:
	if p == null:
		return
	rows.append(Row.new(KEY_TORQUE, _fmt(FMT_NM, p.drive_torque_nm)))


static func _append_energy_cell(rows: Array[Row], p: EnergyCellProfile) -> void:
	if p == null:
		return
	rows.append(Row.new(KEY_DISCHARGE, _fmt(FMT_PU, p.discharge_limit_pu)))


## A melee module and a ballistic one are described by different figures, and
## showing a cycle time and a muzzle velocity for an edge would be showing two
## zeroes. Doc 07 §15: melee is a property of the kind.
static func _append_effector(rows: Array[Row], p: EffectorModuleProfile) -> void:
	if p == null:
		return
	if PartEnums.is_melee_effector(p.kind) and p.melee_profile != null:
		var m := p.melee_profile
		rows.append(Row.new(KEY_REACH, _fmt(FMT_METRES, m.reach_m)))
		rows.append(Row.new(KEY_SWING_ARC, _fmt(FMT_DEGREES, m.swing_arc_deg)))
		rows.append(Row.new(KEY_STRIKE, _fmt_int(m.strike_damage)))
		rows.append(Row.new(KEY_CYCLE, _fmt(FMT_SECONDS, p.cycle_time_s)))
		return
	rows.append(Row.new(KEY_CYCLE, _fmt(FMT_SECONDS, p.cycle_time_s)))
	rows.append(Row.new(KEY_MUZZLE, _fmt(FMT_MPS, p.muzzle_velocity_mps)))
	rows.append(Row.new(KEY_TRAVERSE, _fmt_arc(p.yaw_limit_deg)))
	rows.append(Row.new(KEY_ELEVATION, _fmt_arc(p.pitch_limit_deg)))
	rows.append(Row.new(KEY_RECOIL, _fmt(FMT_NS, p.recoil_impulse_ns)))


static func _append_support(rows: Array[Row], p: SupportModuleProfile) -> void:
	if p == null:
		return
	rows.append(Row.new(KEY_ROLE, InputPrompt.tr_key(_support_role_key(p.role))))
	rows.append(Row.new(KEY_MAGNITUDE, _fmt(FMT_RATIO, p.effect_magnitude)))


static func _append_appendage(rows: Array[Row], p: AppendageProfile) -> void:
	if p == null:
		return
	rows.append(Row.new(KEY_REACH, _fmt(FMT_METRES, p.reach_m)))
	rows.append(Row.new(KEY_GRIP_RATING, _fmt_int(p.grip_rating_n)))


static func _support_role_key(role: int) -> StringName:
	if role < 0 or role >= SUPPORT_ROLE_KEYS.size():
		return SUPPORT_ROLE_KEYS[0]
	return SUPPORT_ROLE_KEYS[role]


static func _motive_kind_key(kind: int) -> StringName:
	if kind < 0 or kind >= MOTIVE_KIND_KEYS.size():
		return MOTIVE_KIND_KEYS[0]
	return MOTIVE_KIND_KEYS[kind]


static func _fmt(format_key: StringName, value: float) -> String:
	return InputPrompt.tr_key(format_key) % value


static func _fmt_int(value: float) -> String:
	return InputPrompt.tr_key(FMT_INT) % int(roundf(value))


## An arc as its two stops: "-8° / +34°". A single number cannot say that an
## Effector Module can look 34° up and only 8° down, which is the constraint that
## decides where on a build it can usefully go.
static func _fmt_arc(limits: Vector2) -> String:
	return InputPrompt.tr_key(FMT_ARC) % [limits.x, limits.y]
