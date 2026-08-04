class_name PartCard
extends Button
## One entry in the catalogue, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §5.3.
##
## [b]A card is bound, never built.[/b] [CataloguePresenter] keeps a pool of
## these sized to the screen and rebinds them as the list scrolls, so the cost of
## a catalogue is a function of how much of it is visible rather than of how
## large it is. Everything in here is therefore written to be overwritten: no
## card holds state that outlives its binding, and [method bind] sets every
## field it can set rather than only the ones that changed.
##
## [b]Amendment to §5.3.[/b] That section binds an icon from
## [code]PartIconCache[/code], a pip from [code]TierPalette[/code], and an owned
## overlay and a disabled state from [code]Inventory[/code], with a tooltip from
## [code]PartTooltipBuilder[/code]. None of the four exists, and three of them
## are systems rather than helpers — an icon cache is a [SubViewport] render and
## an atlas on disk, and an inventory is an entitlement model this project has
## not decided on. The card shows doc 13 §2.3's greybox class tint in place of
## the icon, which is the same colour the part is drawn in on the lattice two
## hundred pixels to the right, and it composes its tooltip from the definition's
## own localised description. What §5 is actually about — the pool and the
## windowed binding — is implemented in full.

## Height of a card in logical units. Fixed rather than derived from content,
## because §5.2's windowing computes which index is at the top of the viewport
## from a row height, and a row whose height depended on the length of a
## localised part name would put a different part under the scrollbar in every
## language.
const CARD_HEIGHT_PX: float = 74.0
## Side of the square class swatch, in logical units.
const SWATCH_PX: float = 18.0
const ROW_SEPARATION_PX: int = 2

## Takes the build cost and the mass: "140 · 96 kg".
const KEY_COST_MASS: StringName = &"garage.card.cost_mass"
## Takes the localised class name and the tier grade: "Motive Assembly · T2".
const KEY_CLASS_TIER: StringName = &"garage.card.class_tier"

## The definition this card is currently showing, or
## [constant PartRegistry.INVALID_ID] when it is bound to nothing — a card in the
## pool that the last row of the list did not fill.
var part_def_id: int = -1

var _swatch: ColorRect = null
var _name: Label = null
var _class_tier: Label = null
var _cost_mass: Label = null


func _init() -> void:
	theme_type_variation = &"PartCard"
	custom_minimum_size.y = CARD_HEIGHT_PX
	size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clip_text = true

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(SWATCH_PX, SWATCH_PX)
	_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_swatch)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_theme_constant_override("separation", ROW_SEPARATION_PX)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	_name = Label.new()
	_name.theme_type_variation = &"Label"
	_name.clip_text = true
	column.add_child(_name)

	_class_tier = Label.new()
	_class_tier.theme_type_variation = &"StatCaption"
	_class_tier.clip_text = true
	column.add_child(_class_tier)

	_cost_mass = Label.new()
	_cost_mass.theme_type_variation = &"StatCaption"
	_cost_mass.clip_text = true
	column.add_child(_cost_mass)


## Shows [param def]. Every field is written, including the ones a previous
## binding set: a card is reused, and a field left alone is a field showing
## another part's number.
func bind(def: PartDefinition) -> void:
	part_def_id = def.runtime_id
	_swatch.color = GreyboxMaterial.CLASS_TINT[int(def.part_class)]
	_name.text = tr(def.display_name_key)
	_class_tier.text = tr(KEY_CLASS_TIER) % [
		tr(PartEnums.class_key(def.part_class)), PartEnums.tier_label(def.tier)
	]
	_cost_mass.text = tr(KEY_COST_MASS) % [def.build_cost, def.mass_kg]
	tooltip_text = tr(def.description_key)
	visible = true
	disabled = false


## Empties the card. The pool is sized in whole rows, so the last row of a list
## that does not divide by the column count ends in cards bound to nothing; they
## are hidden rather than freed, because freeing them is what §5.2 exists to
## avoid.
func unbind() -> void:
	part_def_id = -1
	visible = false


## Marks this card as the one whose part is about to be placed. Selection is a
## property of the [i]catalogue[/i] and not of the card, because a card is
## rebound as the list scrolls: the presenter re-applies this after every bind.
func set_selected(selected: bool) -> void:
	button_pressed = selected
