class_name GarageScreen
extends Control
## Where a player builds, owned by [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §4
## and §15.4.
##
## It owns the [BuildContext] the whole session edits, composes §4's container
## tree, and turns a pointer into a placement through [PlacementValidator] —
## the identical chain the auto-assembler, blueprint loading and server-side
## re-validation use (CLAUDE.md §10 rule 9). There is no garage-only path into
## the lattice and there must never be one: the rule the garage enforces is the
## rule the server enforces, and the only way to guarantee that is for them to be
## the same code.
##
## [b]It hands the match a [Blueprint], not a context.[/b] A match builds its own
## context from the blueprint and validates every placement again. That looks
## redundant across two screens in one process and is the whole point: the path a
## build takes from this screen to a match is the path it will take from a client
## to a server, and a shortcut here is a hole there.
##
## [b]The 3D half is [GaragePreview].[/b] This class decides; that one draws and
## resolves the pointer. Doc 04's rule about presentation applies inside the
## garage too — a commit emits [signal EventBusService.part_attached] and the
## preview reacts, so a part cannot be committed without appearing and cannot
## appear without being committed.

## Raised when the player asks for a test run. Carries a copy of the build, so a
## match cannot edit the blueprint the garage is still holding.
signal test_drive_requested(blueprint: Blueprint)
## Raised when the player leaves for the menu.
signal menu_requested

## ===== LAYOUT ==========================================================

const SAFE_MARGIN_PX: int = 12
const DOCK_SEPARATION_PX: int = 8
const TOOLBAR_SEPARATION_PX: int = 6

## Assembly id the garage's build carries. Distinct from anything a match spawns:
## the bus is global and a garage that used id 1 would answer signals meant for
## the player's Assembly in a match running behind it.
const GARAGE_ASSEMBLY_ID: int = 9000

## Metadata key carrying which [enum PartEnums.PartClass] a filter chip selects.
const META_CHIP_CLASS: StringName = &"chip_class"

## ===== STRING KEYS =====================================================

const KEY_TITLE: StringName = &"garage.title"
const KEY_TEST_DRIVE: StringName = &"garage.action.test_drive"
const KEY_MENU: StringName = &"garage.action.menu"
const KEY_RESET: StringName = &"garage.action.reset"
const KEY_SEARCH_PLACEHOLDER: StringName = &"garage.catalogue.search"
const KEY_CLASS_ANY: StringName = &"garage.catalogue.any_class"
const KEY_HINT: StringName = &"garage.hint"
const KEY_ORIENTATION: StringName = &"garage.orientation"
const KEY_SELECTED_NONE: StringName = &"garage.selected.none"
const KEY_REMOVED: StringName = &"garage.removed"
const KEY_CASCADE: StringName = &"garage.removed.cascade"
const KEY_NO_CORE: StringName = &"garage.no_core"

## The build being edited. Every placement in it went through the validator.
var context: BuildContext = null

## The blueprint the garage opened on, kept so that Reset can put it back. The
## live build is the context; this is the starting point.
var initial_blueprint: Blueprint = null

var preview: GaragePreview = null
var catalogue: CataloguePresenter = null
var stats: AssemblyStatPanel = null
var inspector: PartInspector = null

var _stat_solver: AssemblyStatSolver = null
var _viewport: SubViewport = null
var _catalogue_dock: PanelContainer = null
var _right_column: VBoxContainer = null
var _stat_dock: PanelContainer = null
var _catalogue_grid: GridContainer = null
var _catalogue_scroll: ScrollContainer = null
var _search: LineEdit = null
var _class_filter: HFlowContainer = null
var _status: Label = null
var _selection_label: Label = null
var _centre: Control = null
var _tier: Breakpoint.Tier = Breakpoint.Tier.EXPANDED
var _catalogue_configured: bool = false

## The orientation that is one quarter turn about the world up and nothing else,
## resolved from the table on first use. Not a constant: a constant may not call
## a static function (LEARNED_FACTS.md §1 fact 30), and
## [method OrientationTable.index_of_basis] is one.
var _quarter_turn_about_y: int = -1

## Orientation the armed part will be placed at. Cycled by
## [code]build_rotate_yaw[/code]; §4.3's rotation input model, reduced to the one
## axis a mouse and a keyboard can drive without a modal.
var _orientation_index: int = OrientationTable.IDENTITY_INDEX

## Last candidate the pointer resolved and the answer the validator gave for it.
## Cached so that §8's throttle holds: a stationary cursor performs no validation
## work at all.
var _ghost_cell: Vector3i = Vector3i.ZERO
var _ghost_orientation: int = -1
var _ghost_part_id: int = -1
var _ghost_candidate: PlacementCandidate = null

## Slot the inspector is currently describing, or
## [constant SyndicateConstants.INVALID_SLOT]. Held so that a pointer moving
## across one part does not rebuild the dock on every motion event.
var _inspected_slot: int = SyndicateConstants.INVALID_SLOT


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	if initial_blueprint == null:
		initial_blueprint = StarterBlueprint.skirmisher()
	_build_context()
	_build_viewport()
	_build_interface()
	_build_stat_solver()
	UiScale.scale_changed.connect(_on_scale_changed)
	_apply_tier(Breakpoint.tier_for(UiScale.logical_size))
	_load(initial_blueprint)
	InputMethod.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _exit_tree() -> void:
	if UiScale.scale_changed.is_connected(_on_scale_changed):
		UiScale.scale_changed.disconnect(_on_scale_changed)
	if _stat_solver != null and is_instance_valid(_stat_solver):
		# Remove before free: the solver joins its worker task in `_exit_tree`,
		# and `free()` on a node with a task in flight is refused before it ever
		# reaches there (LEARNED_FACTS.md §1 fact 53).
		_stat_solver.forget(GARAGE_ASSEMBLY_ID)
		_stat_solver.get_parent().remove_child(_stat_solver)
		_stat_solver.free()
		_stat_solver = null
	if context != null:
		context.dispose()
		context = null


## ===== INPUT ===========================================================


## §4.2's centre spacer is what routes a click here: the docks capture their own
## input and the middle of the screen does not, so a press that reaches this
## function is a press on the build.
func _unhandled_input(event: InputEvent) -> void:
	if preview != null and preview.handle_camera_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"build_rotate_yaw"):
		_orientation_index = _next_yaw_orientation(_orientation_index)
		_invalidate_ghost()
		_refresh_selection_label()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"build_cancel"):
		catalogue.select(-1)
		preview.hide_ghost()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"build_place"):
		_place_at(_preview_pointer())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"build_remove"):
		_remove_at(_preview_pointer())
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var pointer := _preview_pointer()
		_update_ghost(pointer)
		_inspect_under_pointer(pointer)


## ===== BUILD OPERATIONS ================================================


## Resolves the pointer, validates, and shows the answer as a coloured ghost.
##
## §8's throttle: the chain runs only when the cell, the orientation or the armed
## part changes. A stationary cursor performs zero validation work, which is what
## makes it affordable to run the [i]real[/i] validator for the preview rather
## than a cheaper approximation of it that could disagree with the commit.
func _update_ghost(screen_pos: Vector2) -> void:
	if preview == null:
		return
	var def := _armed_definition()
	if def == null:
		preview.hide_ghost()
		return
	var candidate := preview.resolve_candidate(def, _orientation_index, screen_pos)
	if candidate == null:
		preview.hide_ghost()
		_ghost_part_id = -1
		return
	if (
		candidate.origin_cell == _ghost_cell
		and _orientation_index == _ghost_orientation
		and def.runtime_id == _ghost_part_id
	):
		return
	_ghost_cell = candidate.origin_cell
	_ghost_orientation = _orientation_index
	_ghost_part_id = def.runtime_id
	_ghost_candidate = candidate

	var reject := PlacementValidator.validate(context, candidate)
	preview.show_ghost(def, candidate, reject)
	_status.text = (
		"" if reject == PlacementValidator.Reject.NONE
		else tr(PlacementValidator.reject_key(reject))
	)


func _place_at(screen_pos: Vector2) -> void:
	var def := _armed_definition()
	if def == null:
		return
	var candidate := preview.resolve_candidate(def, _orientation_index, screen_pos)
	if candidate == null:
		return
	var reject := PlacementValidator.validate(context, candidate)
	if reject != PlacementValidator.Reject.NONE:
		_status.text = tr(PlacementValidator.reject_key(reject))
		return
	PlacementValidator.commit(context, candidate)
	_status.text = ""
	_invalidate_ghost()
	_update_ghost(screen_pos)


## Doc 02 §9.2. Removing a part re-parents what it was carrying where a legal
## alternative parent exists and removes the rest with it.
##
## The cascade is [i]reported[/i] rather than confirmed. §9.2 requires a
## confirmation prompt showing the affected count, and that needs the undo stack
## of §9.3 to be worth agreeing to — a player who is told "this will also remove
## four parts", agrees, and then cannot undo it has been asked a question with
## one answer. The toast names the count; the modal is owed alongside
## [BuildCommand].
func _remove_at(screen_pos: Vector2) -> void:
	var slot := preview.slot_at(screen_pos)
	if slot == SyndicateConstants.INVALID_SLOT:
		return
	if slot == SyndicateConstants.CORE_SLOT:
		# Invariant I-2: the Core Module is the root. Removing it does not leave a
		# smaller Assembly, it leaves no Assembly, and the validator's own answer
		# to putting one back is DUPLICATE_CORE the moment a second is placed.
		_status.text = tr(KEY_NO_CORE)
		return
	var cascade := PlacementValidator.remove(context, slot)
	_status.text = (
		tr(KEY_REMOVED) if cascade.is_empty() else tr(KEY_CASCADE) % cascade.size()
	)
	_invalidate_ghost()


## The inspector shows what the pointer means: the armed part when there is one,
## and otherwise whatever the pointer is over.
##
## [b]Hover rather than [code]build_pick[/code].[/b] §7.1 binds that action to the
## middle mouse button and [code]cam_orbit[/code] to the same one, so in the
## garage — the one screen that consumes both — a click cannot be both. Hovering
## needs no binding, conflicts with nothing, and answers the question a player
## actually has, which is "what is that" rather than "select that".
##
## Throttled on the slot, so a pointer moving across one part rebuilds nothing.
func _inspect_under_pointer(screen_pos: Vector2) -> void:
	if inspector == null:
		return
	if _armed_definition() != null:
		return
	var slot := preview.slot_at(screen_pos)
	if slot == _inspected_slot:
		return
	_inspected_slot = slot
	inspector.show_part(
		null if slot == SyndicateConstants.INVALID_SLOT else context.definition_at(slot)
	)


## Replaces the build with [param bp]. Used on open and by Reset.
func _load(bp: Blueprint) -> void:
	_clear()
	var failed := bp.apply(context, _on_blueprint_reject)
	if failed != Blueprint.APPLIED_CLEANLY:
		push_error("GarageScreen: blueprint placement %d was refused" % failed)


func _clear() -> void:
	# Highest slot first. Removing a parent re-parents or cascades its children
	# (§9.2), so walking down means every removal is of a leaf and the cascade
	# path is never taken on a build that is simply being emptied.
	for slot: int in range(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY - 1, -1, -1):
		if context.state(slot) != null:
			PlacementValidator.remove(context, slot)
	_invalidate_ghost()


func _on_blueprint_reject(index: int, reason_key: StringName) -> void:
	_status.text = tr(reason_key)
	push_warning("GarageScreen: placement %d rejected: %s" % [index, reason_key])


## ===== TOOLBAR ACTIONS =================================================


func _on_test_drive_pressed() -> void:
	if context.state(SyndicateConstants.CORE_SLOT) == null:
		_status.text = tr(KEY_NO_CORE)
		return
	test_drive_requested.emit(Blueprint.from_context(context))


func _on_reset_pressed() -> void:
	_load(initial_blueprint)


func _on_menu_pressed() -> void:
	menu_requested.emit()


## ===== SELECTION =======================================================


func _armed_definition() -> PartDefinition:
	if catalogue == null or catalogue.selected_part_def_id < 0:
		return null
	return PartRegistry.definition(catalogue.selected_part_def_id)


func _on_part_selected(_part_def_id: int) -> void:
	_invalidate_ghost()
	_refresh_selection_label()
	_inspected_slot = SyndicateConstants.INVALID_SLOT
	if inspector != null:
		inspector.show_part(_armed_definition())


func _refresh_selection_label() -> void:
	var def := _armed_definition()
	if def == null:
		_selection_label.text = tr(KEY_SELECTED_NONE)
		return
	_selection_label.text = "%s   %s" % [
		tr(def.display_name_key), tr(KEY_ORIENTATION) % _orientation_index
	]


func _invalidate_ghost() -> void:
	_ghost_part_id = -1
	_ghost_orientation = -1
	_ghost_candidate = null
	if preview != null:
		preview.hide_ghost()


## The next orientation about the world up from [param index].
##
## Derived from [OrientationTable] rather than written down as four indices.
## Which of the 24 is a quarter turn about Y from another is a property of the
## table, and LEARNED_FACTS.md §3 records what writing an index down costs the
## first time the table is regenerated.
func _next_yaw_orientation(index: int) -> int:
	if _quarter_turn_about_y < 0:
		_quarter_turn_about_y = OrientationTable.index_of_basis(
			Basis(Vector3.UP, PI * 0.5)
		)
	return OrientationTable.compose(_quarter_turn_about_y, index)


## Pointer position inside the preview's viewport.
##
## The 3D view is rendered into a [SubViewport] scaled to the container, so the
## mouse position in the screen's space is not the position in the camera's. It
## is asked of the viewport, which knows its own stretch.
func _preview_pointer() -> Vector2:
	if _viewport == null:
		return Vector2.ZERO
	return _viewport.get_mouse_position()


## ===== CONSTRUCTION ====================================================


func _build_context() -> void:
	# With physics, because doc 02 §7.7's interpenetration check is the one step
	# of the chain that needs a space, and the garage is the screen it exists for.
	context = BuildContext.with_physics(GARAGE_ASSEMBLY_ID)


## §4's `ViewportLayer`. The 3D view is a [SubViewport] behind the whole
## interface rather than a viewport in a hole in the middle of it, which is what
## lets §4.2's centre spacer be a single `mouse_filter` property instead of a
## hit-testing special case in an input router.
func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.name = "ViewportLayer"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.own_world_3d = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)

	preview = GaragePreview.new()
	preview.name = "GaragePreviewScene"
	preview.assembly_id = GARAGE_ASSEMBLY_ID
	preview.context = context
	_viewport.add_child(preview)


func _build_stat_solver() -> void:
	_stat_solver = AssemblyStatSolver.new()
	_stat_solver.name = "AssemblyStatSolver"
	add_child(_stat_solver)
	_stat_solver.track(context)


func _build_interface() -> void:
	var safe := MarginContainer.new()
	safe.name = "SafeAreaFrame"
	safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, SAFE_MARGIN_PX)
	add_child(safe)

	var rows := VBoxContainer.new()
	rows.name = "RootRows"
	rows.add_theme_constant_override("separation", DOCK_SEPARATION_PX)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(rows)

	rows.add_child(_build_toolbar())

	var main := HBoxContainer.new()
	main.name = "MainRow"
	main.size_flags_vertical = Control.SIZE_FILL | Control.SIZE_EXPAND
	main.add_theme_constant_override("separation", DOCK_SEPARATION_PX)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(main)

	main.add_child(_build_catalogue_dock())

	# §4.2. The one property that lets a click pass through the middle of the
	# interface onto the build behind it.
	_centre = Control.new()
	_centre.name = "CentreSpacer"
	_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_centre.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	main.add_child(_centre)

	main.add_child(_build_right_column())
	rows.add_child(_build_status_row())


func _build_toolbar() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Toolbar"
	panel.theme_type_variation = &"DockPanel"

	var row := HBoxContainer.new()
	row.name = "ToolbarRow"
	row.add_theme_constant_override("separation", TOOLBAR_SEPARATION_PX)
	panel.add_child(row)

	var title := Label.new()
	title.theme_type_variation = &"StatValue"
	title.text = tr(KEY_TITLE)
	row.add_child(title)

	_selection_label = Label.new()
	_selection_label.theme_type_variation = &"StatCaption"
	_selection_label.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	_selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selection_label.text = tr(KEY_SELECTED_NONE)
	row.add_child(_selection_label)

	row.add_child(_toolbar_button(KEY_RESET, _on_reset_pressed))
	row.add_child(_toolbar_button(KEY_MENU, _on_menu_pressed))

	var test_drive := _toolbar_button(KEY_TEST_DRIVE, _on_test_drive_pressed)
	test_drive.theme_type_variation = &"PrimaryButton"
	row.add_child(test_drive)
	return panel


func _toolbar_button(key: StringName, handler: Callable) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"ToolbarButton"
	button.text = tr(key)
	button.pressed.connect(handler)
	return button


func _build_catalogue_dock() -> PanelContainer:
	_catalogue_dock = PanelContainer.new()
	_catalogue_dock.name = "CatalogueDock"
	_catalogue_dock.theme_type_variation = &"DockPanel"
	_catalogue_dock.size_flags_vertical = Control.SIZE_FILL | Control.SIZE_EXPAND

	var column := VBoxContainer.new()
	column.name = "CatalogueColumn"
	column.add_theme_constant_override("separation", TOOLBAR_SEPARATION_PX)
	_catalogue_dock.add_child(column)

	_search = LineEdit.new()
	_search.name = "SearchField"
	_search.placeholder_text = tr(KEY_SEARCH_PLACEHOLDER)
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	column.add_child(_search)

	_class_filter = HFlowContainer.new()
	_class_filter.name = "ClassFilter"
	column.add_child(_class_filter)
	_build_class_filter()

	_catalogue_scroll = ScrollContainer.new()
	_catalogue_scroll.name = "CatalogueScroll"
	_catalogue_scroll.size_flags_vertical = Control.SIZE_FILL | Control.SIZE_EXPAND
	_catalogue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_catalogue_scroll)

	_catalogue_grid = GridContainer.new()
	_catalogue_grid.name = "CatalogueGrid"
	_catalogue_grid.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	_catalogue_scroll.add_child(_catalogue_grid)

	catalogue = CataloguePresenter.new()
	catalogue.name = "CataloguePresenter"
	add_child(catalogue)
	catalogue.part_selected.connect(_on_part_selected)
	return _catalogue_dock


## One toggle per class that has a part in it, plus an "everything" chip.
##
## Built from the registry rather than from the enum: a class with no authored
## part is a chip that filters to an empty list, which reads as the catalogue
## being broken rather than as the class being unwritten.
func _build_class_filter() -> void:
	var any := Button.new()
	any.theme_type_variation = &"ToolbarButton"
	any.toggle_mode = true
	any.button_pressed = true
	any.text = tr(KEY_CLASS_ANY)
	any.set_meta(META_CHIP_CLASS, CataloguePresenter.CatalogueFilter.ANY_CLASS)
	any.pressed.connect(
		_on_class_filter_pressed.bind(CataloguePresenter.CatalogueFilter.ANY_CLASS)
	)
	_class_filter.add_child(any)

	for part_class: int in PartEnums.PART_CLASS_COUNT:
		if PartRegistry.ids_of_class(part_class).is_empty():
			continue
		var chip := Button.new()
		chip.theme_type_variation = &"ToolbarButton"
		chip.toggle_mode = true
		chip.text = tr(PartEnums.class_key(part_class))
		chip.set_meta(META_CHIP_CLASS, part_class)
		chip.pressed.connect(_on_class_filter_pressed.bind(part_class))
		_class_filter.add_child(chip)


func _build_right_column() -> VBoxContainer:
	_right_column = VBoxContainer.new()
	_right_column.name = "RightColumn"
	_right_column.add_theme_constant_override("separation", DOCK_SEPARATION_PX)

	var inspector_dock := PanelContainer.new()
	inspector_dock.name = "InspectorDock"
	inspector_dock.theme_type_variation = &"DockPanel"
	_right_column.add_child(inspector_dock)

	inspector = PartInspector.new()
	inspector.name = "PartInspector"
	inspector_dock.add_child(inspector)

	_stat_dock = PanelContainer.new()
	_stat_dock.name = "StatDock"
	_stat_dock.theme_type_variation = &"DockPanel"
	_right_column.add_child(_stat_dock)

	stats = AssemblyStatPanel.new()
	stats.name = "AssemblyStats"
	stats.assembly_id = GARAGE_ASSEMBLY_ID
	_stat_dock.add_child(stats)
	return _right_column


## The one-line strip §8 puts a rejection reason in, and the place the controls
## are named. A player who has never seen this screen is told what the two mouse
## buttons and the rotate key do, read live out of [InputMap].
func _build_status_row() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "StatusStrip"
	panel.theme_type_variation = &"DockPanel"

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", TOOLBAR_SEPARATION_PX)
	panel.add_child(row)

	_status = Label.new()
	_status.theme_type_variation = &"StatValue"
	_status.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	row.add_child(_status)

	var hint := Label.new()
	hint.theme_type_variation = &"StatCaption"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.text = tr(KEY_HINT) % [
		InputPrompt.label_for(&"build_place"),
		InputPrompt.label_for(&"build_remove"),
		InputPrompt.label_for(&"build_rotate_yaw"),
		InputPrompt.label_for(&"cam_orbit")
	]
	row.add_child(hint)
	return panel


## ===== BREAKPOINTS =====================================================


func _on_scale_changed(logical: Vector2, _scale: float) -> void:
	var tier := Breakpoint.tier_for(logical)
	if tier != _tier:
		_apply_tier(tier)


## §3.3: a breakpoint change reconfigures containers by setting properties, never
## by rebuilding the tree. Rebuilding would destroy focus, scroll position, and
## the catalogue's recycled pool — which is the thing §5 exists to keep.
func _apply_tier(tier: Breakpoint.Tier) -> void:
	_tier = tier
	_catalogue_grid.columns = Breakpoint.catalogue_columns(tier)
	_catalogue_dock.custom_minimum_size.x = Breakpoint.catalogue_dock_width(tier)
	_right_column.custom_minimum_size.x = Breakpoint.inspector_dock_width(tier)
	_catalogue_dock.visible = Breakpoint.is_docked(tier)
	_stat_dock.visible = Breakpoint.shows_stat_dock(tier)
	EventBus.ui_breakpoint_changed.emit(int(tier))
	if catalogue == null:
		return
	if _catalogue_configured:
		catalogue.reflow()
	else:
		catalogue.configure(_catalogue_scroll, _catalogue_grid)
		_catalogue_configured = true


func _on_search_changed(text: String) -> void:
	var filter := CataloguePresenter.CatalogueFilter.new()
	filter.part_class = catalogue.filter.part_class
	filter.search = text
	catalogue.set_filter(filter)


func _on_class_filter_pressed(part_class: int) -> void:
	var filter := CataloguePresenter.CatalogueFilter.new()
	filter.part_class = part_class
	filter.search = _search.text
	catalogue.set_filter(filter)
	# The chips are a radio group and Godot has no such container, so exactly one
	# is pressed by writing all of them. Read from the chip's own metadata rather
	# than by counting children: the set of chips is a function of which classes
	# have an authored part, and an index into it is a number that changes when
	# somebody adds a Control Surface.
	for child: Node in _class_filter.get_children():
		var button := child as Button
		if button == null:
			continue
		button.button_pressed = int(button.get_meta(META_CHIP_CLASS)) == part_class
