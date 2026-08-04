class_name CataloguePresenter
extends Node
## The virtualised part catalogue of
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §5.
##
## §5.1 is the largest UI performance trap in a game of this shape: a registry of
## four hundred definitions costs about 180 ms and 40 MB to instantiate as cards,
## and every re-filter rebuilds all of it. §5.2's answer is a pool sized to what
## fits on screen plus two rows of overscan, with cards [b]bound[/b] to an index
## rather than created and destroyed.
##
## [b]It is worth having at twelve parts, and that is not obvious.[/b] The
## shipped registry fits on one screen and a naive catalogue would be
## indistinguishable today. It is written now because the alternative is writing
## it later, against a garage whose selection, focus and scroll behaviour have
## all been built on the assumption that a card and a part are the same object —
## which is the assumption §5.2 breaks, and the reason the section exists.
##
## The pool is sized in whole rows, so a list that does not divide by the column
## count ends in cards bound to nothing. Those are hidden rather than freed.

signal part_selected(part_def_id: int)

## Rows of cards kept bound above and below the viewport, so a scroll of less
## than two rows never has to rebind anything. §5.2.
const OVERSCAN_ROWS: int = 2

## Spacing between cards in the grid, in logical units. Read by the row-height
## arithmetic as well as set on the container, so the two cannot disagree.
const GRID_SEPARATION_PX: int = 4

## Filter the catalogue is showing. Assigned through [method set_filter], never
## written directly: a filter change resets the bound window, and a caller that
## edited this in place would leave cards showing parts the new filter excludes.
var filter: CatalogueFilter = null

## The part currently armed for placement, or -1. Held here rather than on a card
## because a card is rebound as the list scrolls, and a selection that lived on
## one would move to a different part when the player scrolled past it.
var selected_part_def_id: int = -1

var _scroll: ScrollContainer = null
var _grid: GridContainer = null
var _pool: Array[PartCard] = []
var _filtered: PackedInt32Array = PackedInt32Array()
var _first_bound_index: int = -1


## [param scroll] and [param grid] are the containers §4's tree puts the cards
## in. They are passed rather than exported because the garage builds its own
## tree in code; the presenter never reaches for them through the scene.
func configure(scroll: ScrollContainer, grid: GridContainer) -> void:
	_scroll = scroll
	_grid = grid
	_grid.add_theme_constant_override("h_separation", GRID_SEPARATION_PX)
	_grid.add_theme_constant_override("v_separation", GRID_SEPARATION_PX)
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	EventBus.ui_breakpoint_changed.connect(_on_breakpoint_changed)
	if filter == null:
		filter = CatalogueFilter.new()
	_rebuild_filter()


func _exit_tree() -> void:
	if EventBus.ui_breakpoint_changed.is_connected(_on_breakpoint_changed):
		EventBus.ui_breakpoint_changed.disconnect(_on_breakpoint_changed)


## Applies [param f] and rebinds from the top. The window is reset rather than
## kept: index 40 of one filter has nothing to do with index 40 of the next, and
## a player who narrows a search expects to be looking at the first result.
func set_filter(f: CatalogueFilter) -> void:
	filter = f
	_rebuild_filter()


## Part definition ids the current filter admits, in registry order. Diagnostics
## and tests.
func filtered_ids() -> PackedInt32Array:
	return _filtered.duplicate()


## Cards in the pool, bound or not. Diagnostics and tests: §5.2's whole claim is
## that this stays a function of the screen rather than of the registry.
func pool_size() -> int:
	return _pool.size()


## Arms [param part_def_id] for placement, or -1 to disarm. Idempotent, because
## the garage calls it both from a card press and from a cancel.
func select(part_def_id: int) -> void:
	if selected_part_def_id == part_def_id:
		return
	selected_part_def_id = part_def_id
	_apply_selection()
	part_selected.emit(part_def_id)


## Recomputes the pool size and rebinds. Called on a breakpoint change, on a
## filter change, and by the garage when the dock is first laid out.
func reflow() -> void:
	if _grid == null or _scroll == null:
		return
	var columns := maxi(1, _grid.columns)
	var rows_visible := int(ceil(_scroll.size.y / _row_height()))
	_resize_pool((rows_visible + OVERSCAN_ROWS * 2) * columns)
	_first_bound_index = -1
	_bind_window(_current_first_index())


func _rebuild_filter() -> void:
	_filtered = filter.run()
	_first_bound_index = -1
	if _scroll != null:
		_scroll.scroll_vertical = 0
	reflow()


func _row_height() -> float:
	return PartCard.CARD_HEIGHT_PX + float(GRID_SEPARATION_PX)


func _resize_pool(needed: int) -> void:
	var wanted := mini(maxi(needed, 1), _filtered.size() if not _filtered.is_empty() else 1)
	# Never more cards than there are parts to put in them: the overscan is there
	# to absorb a scroll, and a list that fits on screen has nothing to absorb.
	while _pool.size() < wanted:
		var card := PartCard.new()
		card.pressed.connect(_on_card_pressed.bind(card))
		_grid.add_child(card)
		_pool.push_back(card)
	while _pool.size() > wanted:
		var card: PartCard = _pool.pop_back()
		_grid.remove_child(card)
		card.queue_free()


func _current_first_index() -> int:
	if _grid == null:
		return 0
	var row := int(floor(_scroll.scroll_vertical / _row_height()))
	return maxi(0, (row - OVERSCAN_ROWS) * maxi(1, _grid.columns))


func _bind_window(first: int) -> void:
	if first == _first_bound_index:
		return
	_first_bound_index = first
	for i: int in _pool.size():
		var card: PartCard = _pool[i]
		var index := first + i
		if index >= _filtered.size():
			card.unbind()
			continue
		var def := PartRegistry.definition(_filtered[index])
		if def == null:
			card.unbind()
			continue
		card.bind(def)
	_apply_selection()


## Re-applies the armed part to whichever card is now showing it. Runs after
## every bind, which is what makes the selection a property of the part rather
## than of the card that happens to be displaying it.
func _apply_selection() -> void:
	for card: PartCard in _pool:
		card.set_selected(
			card.part_def_id >= 0 and card.part_def_id == selected_part_def_id
		)


func _on_card_pressed(card: PartCard) -> void:
	if card.part_def_id < 0:
		return
	select(card.part_def_id)


func _on_scrolled(_value: float) -> void:
	_bind_window(_current_first_index())


func _on_breakpoint_changed(_tier: int) -> void:
	reflow()


## What the catalogue is currently showing: a class, a search string, or
## everything.
##
## §4's tree gives the dock a search field, a class filter and a tier slider.
## This carries the first two; the tier slider is not built, because a registry
## whose parts run from T2 to T4 has nothing to slide.
class CatalogueFilter:
	extends RefCounted

	## Restrict to one [enum PartEnums.PartClass], or [constant ANY_CLASS].
	const ANY_CLASS: int = -1

	var part_class: int = ANY_CLASS
	## Matched case-insensitively against the part key and the localised name. A
	## player searching for "wheel" finds nothing, and that is CLAUDE.md §8
	## working rather than the search failing.
	var search: String = ""

	## The admitted ids, ascending.
	##
	## Registry order rather than a sort by name: ids are the manifest's order,
	## which is stable across a rebuild and across a locale, so a card does not
	## move under a player's cursor when the interface language changes.
	func run() -> PackedInt32Array:
		var out := PackedInt32Array()
		var needle := search.strip_edges().to_lower()
		# Ids run from 1: 0 is [constant PartManifest.INVALID_PART_ID] and the
		# registry answers null for it.
		for id: int in range(1, PartRegistry.part_count() + 1):
			var def := PartRegistry.definition(id)
			if def == null or def.deprecated:
				continue
			if part_class != ANY_CLASS and int(def.part_class) != part_class:
				continue
			if needle != "" and not _matches(def, needle):
				continue
			out.append(id)
		return out

	static func _matches(def: PartDefinition, needle: String) -> bool:
		return (
			String(def.part_key).to_lower().contains(needle)
			or InputPrompt.tr_key(def.display_name_key).to_lower().contains(needle)
		)
