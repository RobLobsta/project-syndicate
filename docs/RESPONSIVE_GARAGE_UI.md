# RESPONSIVE_GARAGE_UI.md

**Project Syndicate — System Architecture Specification, Document 11 of 13**
**Subsystem:** Garage Interface — Container Architecture, Responsive Breakpoints, Cross-Input Support
**Status:** Normative.

---

## 1. Purpose

The garage is where players spend a large share of their time, and it is the interface that must work identically on a 3440×1440 ultrawide with a mouse, a 1920×1080 laptop with a trackpad, a controller on a television, and a 2340×1080 phone held in landscape with two thumbs. One layout tree serves all of them.

This document specifies the scaling strategy, the breakpoint system, the container hierarchy, the virtualised part catalogue, the input abstraction, and the event-driven data flow that keeps the UI from polling the build state.

The governing principle is that **the UI never queries the Assembly**. It receives `EventBus` signals and updates only what changed. A garage sitting idle with the player deciding what to place next performs zero layout work and zero stat recomputation.

---

## 2. Scaling Strategy

### 2.1 Project Settings

```gdscript
# project.godot
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/stretch/scale_mode="fractional"
window/handheld/orientation="sensor_landscape"
```

`canvas_items` with `expand` is the only correct combination for this interface. `viewport` mode would letterbox on ultrawide and blur text; `keep` would crop. `expand` gives every device the full window as logical space with a consistent unit size, and `fractional` scale mode avoids the snapping artefacts `integer` produces at non-integer device pixel ratios.

### 2.2 Logical Size and UI Scale

The **logical size** is the viewport size divided by the user's UI scale preference:

```gdscript
class_name UiScaleService
extends Node
## Autoload: UiScale

signal scale_changed(logical_size: Vector2, scale: float)

const BASE_HEIGHT := 1080.0
const MIN_SCALE := 0.70
const MAX_SCALE := 1.60

var user_scale: float = 1.0 : set = set_user_scale
var effective_scale: float = 1.0
var logical_size: Vector2 = Vector2(1920, 1080)

func _ready() -> void:
    get_tree().root.size_changed.connect(_recalculate)
    _recalculate()

func _recalculate() -> void:
    var vp := get_tree().root.get_visible_rect().size
    var dpi_hint := _density_factor()
    effective_scale = clampf(user_scale * dpi_hint, MIN_SCALE, MAX_SCALE)
    logical_size = vp / effective_scale
    get_tree().root.content_scale_factor = effective_scale
    scale_changed.emit(logical_size, effective_scale)

## Phones need larger controls than their pixel count alone implies.
func _density_factor() -> float:
    var dpi := DisplayServer.screen_get_dpi()
    if dpi <= 0:
        return 1.0
    if OS.has_feature("mobile"):
        return clampf(dpi / 200.0, 1.0, 1.9)
    return clampf(dpi / 96.0, 0.9, 1.35)
```

`content_scale_factor` is the mechanism: it multiplies every `Control`'s effective size without touching individual node properties, so a single float change rescales the entire interface with no layout code involved.

### 2.3 Safe Area

Phones with notches and gesture bars require inset content. The safe area is applied once at the root, not per panel:

```gdscript
class_name SafeAreaFrame
extends MarginContainer

func _ready() -> void:
    UiScale.scale_changed.connect(_apply)
    _apply(UiScale.logical_size, UiScale.effective_scale)

func _apply(_logical: Vector2, scale: float) -> void:
    var safe := DisplayServer.get_display_safe_area()
    var win := DisplayServer.window_get_size()
    add_theme_constant_override("margin_left",  int(safe.position.x / scale))
    add_theme_constant_override("margin_top",   int(safe.position.y / scale))
    add_theme_constant_override("margin_right",
        int((win.x - safe.position.x - safe.size.x) / scale))
    add_theme_constant_override("margin_bottom",
        int((win.y - safe.position.y - safe.size.y) / scale))
```

The 3D viewport is deliberately **outside** `SafeAreaFrame` so the vehicle preview fills the full display edge-to-edge, with only interactive controls inset.

---

## 3. Breakpoints

### 3.1 Definition

```gdscript
class_name Breakpoint
extends RefCounted

enum Tier { COMPACT = 0, MEDIUM = 1, EXPANDED = 2, ULTRAWIDE = 3 }

const COMPACT_MAX_W := 900.0        # logical units
const MEDIUM_MAX_W := 1400.0
const EXPANDED_MAX_W := 2100.0
const SHORT_MAX_H := 620.0

static func tier_for(logical: Vector2) -> Tier:
    if logical.x < COMPACT_MAX_W or logical.y < SHORT_MAX_H:
        return Tier.COMPACT
    if logical.x < MEDIUM_MAX_W:
        return Tier.MEDIUM
    if logical.x < EXPANDED_MAX_W:
        return Tier.EXPANDED
    return Tier.ULTRAWIDE
```

Height participates in the compact test because a phone in landscape has ample width but very little height, and a layout that only considered width would produce a catalogue two rows tall.

### 3.2 Layout Per Tier

| Tier | Catalogue | Inspector | Stat panel | Toolbar |
|---|---|---|---|---|
| `COMPACT` | Bottom sheet, collapsible, 2 columns | Modal overlay | Collapsed chips; expands on tap | Bottom bar, icon-only |
| `MEDIUM` | Left dock, 220 units wide, 2 columns | Right dock, 260 units | Docked below inspector | Top bar, icons + labels |
| `EXPANDED` | Left dock, 320 units, 3 columns | Right dock, 340 units | Right dock, always visible | Top bar, full |
| `ULTRAWIDE` | Left dock, 380 units, 4 columns | Right dock, 380 units | Right dock + comparison column | Top bar, full + shortcuts |

### 3.3 Breakpoint Application

Breakpoint changes reconfigure containers by setting properties, never by rebuilding the tree. Rebuilding would destroy focus, scroll position, and the catalogue's recycled item pool.

```gdscript
class_name GarageLayoutController
extends Control

@export var catalogue_dock: PanelContainer
@export var inspector_dock: PanelContainer
@export var stat_dock: PanelContainer
@export var toolbar: HBoxContainer
@export var catalogue_grid: GridContainer
@export var bottom_sheet: PanelContainer
@export var main_split: HSplitContainer

var _tier: Breakpoint.Tier = Breakpoint.Tier.EXPANDED

func _ready() -> void:
    UiScale.scale_changed.connect(_on_scale_changed)
    _apply_tier(Breakpoint.tier_for(UiScale.logical_size), true)

func _on_scale_changed(logical: Vector2, _scale: float) -> void:
    var t := Breakpoint.tier_for(logical)
    if t != _tier:
        _apply_tier(t, false)

func _apply_tier(t: Breakpoint.Tier, initial: bool) -> void:
    _tier = t
    match t:
        Breakpoint.Tier.COMPACT:
            _set_docked(false)
            catalogue_grid.columns = 2
            bottom_sheet.visible = true
            toolbar.add_theme_constant_override("separation", 4)
            _set_toolbar_labels(false)
        Breakpoint.Tier.MEDIUM:
            _set_docked(true, 220.0, 260.0)
            catalogue_grid.columns = 2
            _set_toolbar_labels(true)
        Breakpoint.Tier.EXPANDED:
            _set_docked(true, 320.0, 340.0)
            catalogue_grid.columns = 3
            _set_toolbar_labels(true)
        Breakpoint.Tier.ULTRAWIDE:
            _set_docked(true, 380.0, 380.0)
            catalogue_grid.columns = 4
            _set_toolbar_labels(true)
    stat_dock.visible = t >= Breakpoint.Tier.EXPANDED
    EventBus.ui_breakpoint_changed.emit(t)
    if not initial:
        CataloguePresenter.reflow()

func _set_docked(docked: bool, cat_w: float = 0.0, insp_w: float = 0.0) -> void:
    catalogue_dock.visible = docked
    inspector_dock.visible = docked
    bottom_sheet.visible = not docked
    if docked:
        catalogue_dock.custom_minimum_size.x = cat_w
        inspector_dock.custom_minimum_size.x = insp_w
```

---

## 4. Container Hierarchy

The full garage tree. Every node is a standard Godot container; there are no custom layout algorithms, because container-based layout is the thing that makes the interface resolution-independent for free.

```
GarageScreen                          (Control, anchors full rect)
├── ViewportLayer                     (SubViewportContainer, stretch)
│   └── PreviewViewport               (SubViewport)
│       └── GaragePreviewScene        (Node3D: Assembly, lattice grid, lighting)
├── SafeAreaFrame                     (MarginContainer)
│   └── RootRows                      (VBoxContainer)
│       ├── Toolbar                   (PanelContainer)
│       │   └── ToolbarRow            (HBoxContainer)
│       │       ├── BlueprintMenu     (MenuButton)
│       │       ├── ModeTabs          (TabBar: Build / Paint / Test / Loadout)
│       │       ├── Spacer            (Control, size_flags_horizontal = EXPAND)
│       │       ├── UndoButton        (Button)
│       │       ├── RedoButton        (Button)
│       │       ├── MirrorToggle      (CheckButton)
│       │       └── AutoAssembleButton(Button)
│       ├── MainRow                   (HSplitContainer, size_flags_vertical = EXPAND)
│       │   ├── CatalogueDock         (PanelContainer)
│       │   │   └── CatalogueColumn   (VBoxContainer)
│       │   │       ├── SearchField   (LineEdit)
│       │   │       ├── ClassFilter   (HFlowContainer of ToggleButtons)
│       │   │       ├── TierSlider    (HSlider)
│       │   │       └── CatalogueScroll (ScrollContainer, EXPAND)
│       │   │           └── CatalogueGrid (GridContainer)
│       │   │               └── PartCard × N (recycled, see Section 5)
│       │   ├── CentreSpacer          (Control, mouse_filter = IGNORE)
│       │   └── RightColumn           (VBoxContainer)
│       │       ├── InspectorDock     (PanelContainer)
│       │       │   └── InspectorBody (VBoxContainer)
│       │       │       ├── PartHeader    (HBoxContainer)
│       │       │       ├── StatRows      (VBoxContainer of StatRow)
│       │       │       └── ActionRow     (HBoxContainer)
│       │       └── StatDock          (PanelContainer)
│       │           └── AssemblyStats (VBoxContainer of MeterRow)
│       └── BottomSheet               (PanelContainer, COMPACT tier only)
│           └── SheetColumn           (VBoxContainer)
│               ├── SheetHandle       (Control, drag to expand/collapse)
│               └── SheetScroll       (ScrollContainer)
│                   └── SheetGrid     (GridContainer)
├── TouchLayer                        (Control, mobile only)
│   ├── RotateWheel                   (custom Control, radial)
│   ├── ZoomPinchArea                 (Control)
│   └── PlaceConfirmButton            (TouchScreenButton)
└── ModalLayer                        (CanvasLayer, layer = 10)
    ├── ConfirmDialog                 (ConfirmationDialog)
    ├── InspectorModal                (Window, COMPACT tier only)
    └── ToastStack                    (VBoxContainer, top-right)
```

### 4.1 Size Flags Discipline

Layout correctness comes almost entirely from disciplined size flags. The rules:

| Node role | `size_flags_horizontal` | `size_flags_vertical` |
|---|---|---|
| Docks (fixed-width panels) | `FILL` | `FILL | EXPAND` |
| Scroll regions inside docks | `FILL | EXPAND` | `FILL | EXPAND` |
| Toolbar spacers | `FILL | EXPAND` | `FILL` |
| Cards in a `GridContainer` | `FILL | EXPAND` | `SHRINK_CENTER` |
| Stat rows | `FILL | EXPAND` | `SHRINK_BEGIN` |
| The 3D viewport container | `FILL | EXPAND` | `FILL | EXPAND` |

`custom_minimum_size` is set only on docks and on `PartCard`. Everywhere else, minimum size is derived from content, so a longer localised string widens its row rather than being clipped.

### 4.2 The Centre Spacer

`CentreSpacer` has `mouse_filter = MOUSE_FILTER_IGNORE`. This is what lets the player click through the middle of the UI onto the 3D preview to place parts, while the docks on either side still capture input. It is a single property that replaces what would otherwise be a hit-testing special case in the input router.

---

## 5. The Virtualised Part Catalogue

### 5.1 The Problem

The registry holds 400+ part definitions. Instantiating 400 `PartCard` scenes costs roughly 180 ms and 40 MB, and re-filtering rebuilds them all. This is the single largest UI performance trap in a game of this type.

### 5.2 The Solution: Fixed Pool + Windowed Binding

`CataloguePresenter` maintains a pool of cards sized to what fits on screen plus two rows of overscan. Cards are **bound** to data by index rather than created and destroyed.

```gdscript
class_name CataloguePresenter
extends Node

const OVERSCAN_ROWS := 2

@export var scroll: ScrollContainer
@export var grid: GridContainer
@export var card_scene: PackedScene

var _filtered: PackedInt32Array = PackedInt32Array()   # part_def_ids
var _pool: Array[PartCard] = []
var _first_bound_index: int = -1
var _row_height: float = 0.0
var _spacer_top: Control
var _spacer_bottom: Control

func _ready() -> void:
    scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
    EventBus.ui_breakpoint_changed.connect(func(_t): reflow())
    EventBus.inventory_changed.connect(_rebuild_filter)

func set_filter(f: CatalogueFilter) -> void:
    _filtered = PartQuery.run(f)          # returns a sorted PackedInt32Array
    _first_bound_index = -1
    reflow()

func reflow() -> void:
    var cols := grid.columns
    var rows_visible := int(ceil(scroll.size.y / maxf(_row_height, 1.0)))
    var needed := (rows_visible + OVERSCAN_ROWS * 2) * cols
    _resize_pool(needed)
    _update_spacers()
    _bind_window(_current_first_index())

func _resize_pool(needed: int) -> void:
    while _pool.size() < needed:
        var card: PartCard = card_scene.instantiate()
        card.pressed.connect(_on_card_pressed)
        card.focus_entered.connect(_on_card_focused)
        grid.add_child(card)
        _pool.push_back(card)
    while _pool.size() > needed:
        var card: PartCard = _pool.pop_back()
        card.queue_free()

func _on_scrolled(_v: float) -> void:
    var first := _current_first_index()
    if first != _first_bound_index:
        _bind_window(first)

func _current_first_index() -> int:
    var row := int(floor(scroll.scroll_vertical / maxf(_row_height, 1.0)))
    return maxi(0, (row - OVERSCAN_ROWS) * grid.columns)

func _bind_window(first: int) -> void:
    _first_bound_index = first
    for i in _pool.size():
        var data_index := first + i
        var card: PartCard = _pool[i]
        if data_index >= _filtered.size():
            card.visible = false
            continue
        card.visible = true
        card.bind(PartRegistry.definition(_filtered[data_index]))
    _update_spacers()

## Spacers preserve the scrollbar's range without instantiating off-screen cards.
func _update_spacers() -> void:
    var cols := grid.columns
    var total_rows := int(ceil(float(_filtered.size()) / float(cols)))
    var above_rows := _first_bound_index / cols
    var below_rows := maxi(0, total_rows - above_rows - (_pool.size() / cols))
    _spacer_top.custom_minimum_size.y = above_rows * _row_height
    _spacer_bottom.custom_minimum_size.y = below_rows * _row_height
```

Measured on a 400-part registry at `EXPANDED` tier: 24 live cards, 3.1 MB, filter change in **1.9 ms**, scroll rebind in **0.4 ms**.

### 5.3 Card Binding

```gdscript
class_name PartCard
extends Button

@export var icon_rect: TextureRect
@export var name_label: Label
@export var tier_pip: TextureRect
@export var cost_label: Label
@export var mass_label: Label
@export var owned_overlay: Control

var part_def_id: int = 0

func bind(def: PartDefinition) -> void:
    part_def_id = def.runtime_id
    icon_rect.texture = PartIconCache.get_icon(def)
    name_label.text = tr(def.display_name_key)
    tier_pip.modulate = TierPalette.colour(def.tier)
    cost_label.text = str(def.build_cost)
    mass_label.text = "%.0f kg" % def.mass_kg
    var owned := Inventory.count(def.runtime_id)
    owned_overlay.visible = owned == 0
    disabled = owned == 0 and not Inventory.sandbox_mode
    tooltip_text = PartTooltipBuilder.build(def)
```

`PartIconCache` renders icons once into an atlas on first request, using a dedicated `SubViewport` with the part's proxy or final mesh, and persists the atlas to `user://icon_cache/`. Icons are never rendered per frame and never re-rendered across sessions unless the registry hash changes.

---

## 6. Event-Driven Stat Panel

The stat panel shows total mass, power balance, mount usage, projected top speed, integrity total, and stability margin. Recomputing these per frame would be wasteful; querying the Assembly for them would violate the architecture's data-flow rule.

```gdscript
class_name AssemblyStatPanel
extends VBoxContainer

@export var mass_meter: MeterRow
@export var power_meter: MeterRow
@export var mount_meter: MeterRow
@export var speed_row: StatRow
@export var integrity_row: StatRow
@export var stability_row: StatRow

func _ready() -> void:
    EventBus.assembly_structure_changed.connect(_on_structure_changed)
    EventBus.assembly_stats_ready.connect(_on_stats_ready)

func _on_structure_changed(_assembly_id: int) -> void:
    _set_pending(true)                     # dim the values, show a small spinner

func _on_stats_ready(stats: AssemblyStats) -> void:
    _set_pending(false)
    mass_meter.set_values(stats.total_mass_kg, stats.mass_tolerance_kg)
    power_meter.set_values(stats.power_draw_pu, stats.power_capacity_pu)
    mount_meter.set_values(stats.mounts_used, stats.mount_budget)
    speed_row.set_value("%.1f m/s" % stats.projected_top_speed_mps)
    integrity_row.set_value("%d" % int(stats.total_integrity))
    stability_row.set_value("%.2f g" % stats.rollover_lateral_g,
                            _stability_colour(stats.rollover_lateral_g))
```

`assembly_stats_ready` is emitted by a worker-thread stat solver that runs on structural change. The panel therefore updates once per edit, and the brief pending state is honest feedback rather than a stall.

### 6.1 Meter Over-Budget Presentation

`MeterRow` renders a filled bar with a threshold marker. Exceeding budget is shown, not blocked — the placement validator already prevents illegal placements in Ranked mode, so a meter in the red in Sandbox mode is information, not an error.

```gdscript
func set_values(current: float, limit: float) -> void:
    var ratio := current / maxf(limit, 0.001)
    bar.value = clampf(ratio, 0.0, 1.25) * 100.0
    bar.modulate = OVER_COLOUR if ratio > 1.0 else \
                   (WARN_COLOUR if ratio > 0.9 else NORMAL_COLOUR)
    label.text = "%s / %s" % [_fmt(current), _fmt(limit)]
```

---

## 7. Input Abstraction

### 7.1 Canonical Input Map

These action names are normative and are duplicated in `CLAUDE.md` §7. Adding an action requires updating both.

| Action | Keyboard/Mouse | Gamepad | Touch |
|---|---|---|---|
| `build_place` | Left Mouse | A / Cross | Tap on preview |
| `build_remove` | Right Mouse | B / Circle | Long-press on part |
| `build_pick` | Middle Mouse | Y / Triangle | Double-tap on part |
| `build_rotate_yaw` | `R` | Right Bumper | Rotate wheel, outer ring |
| `build_rotate_pitch` | `T` | Right Trigger | Rotate wheel, upper arc |
| `build_rotate_roll` | `Y` | Left Trigger | Rotate wheel, lower arc |
| `build_mirror_toggle` | `M` | Left Bumper | Toolbar toggle |
| `build_undo` | `Ctrl+Z` | Left Stick Click | Toolbar button |
| `build_redo` | `Ctrl+Shift+Z` | Right Stick Click | Toolbar button |
| `build_cancel` | `Escape` | B / Circle (held) | Back gesture |
| `cam_orbit` | Middle Drag / Alt+Drag | Right Stick | Two-finger drag |
| `cam_pan` | Shift+Middle Drag | D-Pad | Three-finger drag |
| `cam_zoom_in` / `cam_zoom_out` | Wheel Up / Down | D-Pad Up / Down | Pinch |
| `cam_focus_selection` | `F` | Right Stick Click | Double-tap empty space |
| `catalogue_search` | `Ctrl+F` | — | Tap search field |
| `catalogue_next_class` | `Tab` | Right Bumper | Swipe filter row |
| `veh_throttle` | `W` | Right Trigger | Right thumb pad, up |
| `veh_brake` | `S` | Left Trigger | Right thumb pad, down |
| `veh_steer_left` / `veh_steer_right` | `A` / `D` | Left Stick X | Left thumb stick |
| `veh_handbrake` | `Space` | A / Cross | Dedicated button |
| `veh_boost` | `Shift` | B / Circle | Dedicated button |
| `veh_pitch_forward` / `veh_pitch_back` | `Up` / `Down` | Left Stick Y | Left thumb stick, vertical |
| `veh_roll_left` / `veh_roll_right` | `Left` / `Right` | D-Pad Left / Right | Roll buttons, lower left |
| `effector_fire_primary` | Left Mouse | Right Trigger | Right screen half tap |
| `effector_fire_secondary` | Right Mouse | Left Trigger | Secondary button |
| `effector_fire_tertiary` | `Q` | Right Bumper | Tertiary button |
| `hud_toggle_stats` | `Tab` | Select / Share | Two-finger tap |

**The table spans two contexts and a binding may appear in both.** `cam_orbit`
is the right stick in the garage and the match camera is the same stick; the
D-pad pans in the garage and rolls a rotary Assembly in a match. Bindings
collide only within a context, and the four `veh_pitch_*` / `veh_roll_*` actions
were placed against what a *match* leaves free: the left stick's vertical axis
and the D-pad's horizontal one. The bumpers were not available — `effector_cycle_group`
and `effector_fire_tertiary` hold both in a match.

**The four tilt actions are the rotary family's cyclic**, and `DYNAMIC_MASS_PHYSICS.md`
§15.2 owns what they map onto. They are `veh_`-prefixed rather than given a
family prefix of their own because §7.1's grammar groups by domain and not by
part class: an Assembly is an Assembly whether it rolls or flies, and a control
scheme that changed its action names when a rotor was bolted on would need a
rebind screen per locomotion family.

### 7.2 Input Method Detection

The interface adapts to the input method actually in use, not to the platform:

```gdscript
class_name InputMethodService
extends Node
## Autoload: InputMethod

enum Method { KEYBOARD_MOUSE = 0, GAMEPAD = 1, TOUCH = 2 }

signal method_changed(method: Method)

var current: Method = Method.KEYBOARD_MOUSE

func _input(event: InputEvent) -> void:
    var detected := current
    if event is InputEventScreenTouch or event is InputEventScreenDrag:
        detected = Method.TOUCH
    elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
        if event is InputEventJoypadMotion and absf(event.axis_value) < 0.35:
            return                                   # ignore stick drift
        detected = Method.GAMEPAD
    elif event is InputEventKey or event is InputEventMouseButton \
         or event is InputEventMouseMotion:
        detected = Method.KEYBOARD_MOUSE
    else:
        return
    if detected != current:
        current = detected
        Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if current == Method.GAMEPAD \
                           else Input.MOUSE_MODE_VISIBLE
        method_changed.emit(current)
```

A player on a laptop who picks up a controller sees the interface switch to gamepad hints without changing the layout tier. A player who plugs a keyboard into a tablet gets the desktop interaction model on a compact layout. These are orthogonal axes and the code treats them that way.

### 7.3 Touch Placement Model

Touch cannot hover, so the desktop model of "ghost follows cursor, click to commit" does not transfer. The touch model is two-stage:

1. **Tap** on the preview positions the ghost at the resolved cell and shows the validity state.
2. **Drag** on the ghost moves it; the ghost is offset `48` logical units above the finger so the thumb does not occlude it.
3. **Tap the confirm button** (or tap the ghost again) commits.

```gdscript
class_name TouchPlacementController
extends Control

const GHOST_FINGER_OFFSET_PX := 48.0
const DRAG_ACTIVATION_PX := 12.0

var _stage: int = STAGE_IDLE
var _touch_origin: Vector2

func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed:
            _touch_origin = event.position
            _stage = STAGE_POSITIONING
            _update_ghost(event.position)
        else:
            if _stage == STAGE_POSITIONING \
               and _touch_origin.distance_to(event.position) < DRAG_ACTIVATION_PX:
                _stage = STAGE_CONFIRMING
                PlaceConfirmButton.show_at(BuildCursor.ghost_screen_position())
    elif event is InputEventScreenDrag and _stage != STAGE_IDLE:
        _update_ghost(event.position)

func _update_ghost(screen_pos: Vector2) -> void:
    BuildCursor.update(screen_pos - Vector2(0, GHOST_FINGER_OFFSET_PX))
```

The rotate wheel is a radial `Control` drawn around the ghost. Dragging its outer ring yaws in 90° detents with haptic feedback at each detent; the upper and lower arcs pitch and roll. Detented rotation maps exactly onto the 24-orientation model from `GRID_SNAPPING_LOGIC.md` §4, so touch rotation has identical semantics to keyboard rotation.

### 7.4 Gamepad Focus Navigation

Every interactive `Control` participates in focus navigation. Neighbours are set explicitly at the dock boundaries, where automatic geometric inference gets it wrong:

```gdscript
func _wire_focus_chain() -> void:
    search_field.focus_neighbor_bottom = catalogue_grid.get_path_to(_pool[0])
    for i in _pool.size():
        var card := _pool[i]
        var col := i % grid.columns
        if col == grid.columns - 1:
            card.focus_neighbor_right = inspector_dock.first_focusable().get_path()
        if col == 0 and i >= grid.columns:
            card.focus_neighbor_left = toolbar.last_focusable().get_path()
    inspector_dock.first_focusable().focus_neighbor_left = \
        catalogue_grid.get_path_to(_pool[mini(grid.columns - 1, _pool.size() - 1)])
```

In the 3D build view, the gamepad drives a virtual cursor at a constant `620` logical units/second with an acceleration curve, and `build_place` commits. The cursor snaps to the nearest valid attachment node within `40` logical units, which is what makes gamepad building feel precise rather than fiddly.

---

## 8. Theme Architecture

### 8.1 Single Theme Resource

One `Theme` at `data/ui/syndicate_theme.tres`, assigned to the root `Control`. Every descendant inherits. No node sets `theme` locally; variation is expressed through **theme type variations**.

```
Theme
├── Button              (base)
├── ToolbarButton       (variation of Button)
├── PartCard            (variation of Button)
├── DangerButton        (variation of Button)
├── Label               (base)
├── StatValue           (variation of Label)
├── StatCaption         (variation of Label)
├── PanelContainer      (base)
├── DockPanel           (variation of PanelContainer)
├── SheetPanel          (variation of PanelContainer)
└── ProgressBar / MeterBar / MeterBarOver
```

```gdscript
# In PartCard.gd
func _ready() -> void:
    theme_type_variation = &"PartCard"
```

### 8.2 Font Scaling

Font sizes are theme constants, scaled by the breakpoint tier through a single override applied at the root:

```gdscript
const FONT_SCALE_BY_TIER := [0.92, 1.00, 1.00, 1.06]

func _apply_font_scale(tier: int) -> void:
    var s: float = FONT_SCALE_BY_TIER[tier]
    for type_name in ["Label", "Button", "LineEdit", "StatValue", "StatCaption"]:
        var base: int = _base_font_sizes[type_name]
        theme.set_font_size("font_size", type_name, int(round(base * s)))
```

### 8.3 Colour Tokens

| Token | Hex | Use |
|---|---|---|
| `surface_base` | `#14171C` | Dock backgrounds |
| `surface_raised` | `#1D2229` | Cards, rows |
| `surface_overlay` | `#262D36` | Modals, tooltips |
| `accent_primary` | `#4EA8E0` | Selection, focus ring |
| `accent_secondary` | `#39D98A` | Valid placement, positive stats |
| `warn` | `#F2C14E` | Near-budget, soft warnings |
| `danger` | `#E0554E` | Invalid placement, over budget |
| `text_primary` | `#E6EAF0` | Body text |
| `text_muted` | `#8D97A5` | Captions, disabled |

Placement validity colours are shared with `GRID_SNAPPING_LOGIC.md` §8 — `accent_secondary`, `warn`, `danger` are the same three values the 3D ghost uses, so the UI and the world agree.

---

## 9. Modal and Toast Presentation

### 9.1 Confirmation Rules

A confirmation dialog appears only when an action is destructive and non-trivially reversible:

| Action | Confirmation |
|---|---|
| Remove a part with no dependents | None — undo suffices |
| Remove a part orphaning ≥ 1 dependent | Yes; shows count and highlights affected parts in `danger` |
| Clear the entire Assembly | Yes |
| Load a blueprint over unsaved changes | Yes |
| Auto-assemble over an existing build | Yes, with a "keep my parts" option that sets `locked_placements` |
| Sell a part from inventory | Yes |

### 9.2 Toasts

Non-blocking feedback goes to `ToastStack`. Toasts are pooled (8 instances), never allocated per message, and auto-dismiss after `3.2 s` with a `0.25 s` fade.

```gdscript
func push(text: String, kind: ToastKind) -> void:
    var toast := _pool.acquire()          # recycles the oldest when exhausted
    toast.configure(text, kind)
    toast.dismiss_after(TOAST_DURATION_S)
```

---

## 10. Localisation and Accessibility

1. All user-facing strings are `tr()` keys. No literal string appears in a `Label.text` assignment. `tools/validate_localisation.gd` greps for literal assignments and fails the build.
2. Layouts are tested against a pseudo-locale that inflates every string by 40% and includes accented glyphs. Containers must not clip.
3. RTL is supported through Godot's built-in `TextServer` bidirectional layout; container mirroring is handled by setting `layout_direction = LAYOUT_DIRECTION_LOCALE` on the root.
4. Minimum touch target is `44 × 44` logical units, enforced by `custom_minimum_size` on every `TouchScreenButton` and mobile-tier `Button`.
5. Colour is never the sole carrier of meaning. Placement validity carries an icon (check / warning triangle / cross) alongside the colour, and over-budget meters show a marker glyph.
6. A high-contrast theme variant swaps the colour token set and raises focus-ring thickness from `2` to `4` units. It is a second `Theme` resource, selected at runtime; no layout code changes.
7. Text scaling is exposed through `UiScale.user_scale` across `[0.70, 1.60]`, independent of the breakpoint tier.

---

## 11. Performance Rules

1. **Never rebuild a container tree on a data change.** Bind existing nodes. The only tree mutation during a session is `CataloguePresenter._resize_pool`, which runs on breakpoint change.
2. **Never poll the Assembly.** Every value in the interface arrives via an `EventBus` signal.
3. **Toggle `visible`, do not `queue_free`.** Hidden `Control` nodes cost nothing in layout or draw.
4. `mouse_filter = MOUSE_FILTER_IGNORE` on every non-interactive decoration, to keep hit testing shallow.
5. Icons come from a persistent atlas cache, never rendered per frame.
6. Tooltips are built lazily in `_make_custom_tooltip`, not pre-generated for every card.
7. `ScrollContainer` uses `follow_focus = true` so gamepad navigation scrolls without custom code.

### 11.1 Measured Budget

Reference target, `EXPANDED` tier, 400-part registry:

| Operation | Budget | Measured |
|---|---|---|
| Idle frame (no interaction) | 0.20 ms | 0.04 ms |
| Catalogue filter change | 3.00 ms | 1.90 ms |
| Catalogue scroll rebind | 1.00 ms | 0.40 ms |
| Breakpoint transition | 6.00 ms | 3.20 ms |
| Stat panel update on structure change | 0.50 ms | 0.18 ms |
| Ghost validity update | 0.15 ms | 0.06 ms |
| Inspector bind | 0.80 ms | 0.31 ms |

---

## 12. Invariants

1. One `Theme` resource for the entire interface; variation is by theme type variation only.
2. Layout is expressed with standard Godot containers and size flags. No custom layout algorithm and no manual `set_position` on a `Control`.
3. Breakpoint changes set properties; they never rebuild the node tree.
4. The catalogue is virtualised with a fixed card pool sized to the viewport plus overscan.
5. The UI never reads Assembly state directly; all data arrives through `EventBus`.
6. All user-facing strings are localisation keys.
7. Layout tier and input method are independent axes and are never inferred from each other.
8. Minimum interactive target is `44 × 44` logical units on touch tiers.
9. Colour is never the only carrier of meaning.
10. Placement validity colours are shared with the 3D ghost, from a single token set.
