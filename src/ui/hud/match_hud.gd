class_name MatchHud
extends CanvasLayer
## The match HUD, owned by [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §14.
##
## [b]It holds no reference to an Assembly.[/b] §14.1: continuous quantities
## arrive as one [HudFrame] pushed by [MatchScreen] every tick, and discrete ones
## arrive as [code]EventBus[/code] signals. Nothing here touches an
## [AssemblyRuntime], a [ChassisGraph], or a [PartInstanceState], and nothing
## here iterates parts. That is what keeps doc 08 the only owner of what
## integrity means.
##
## The tree is §14.2's, built in code rather than authored as a scene because
## every node in it is a standard container with no editor-set property that a
## constructor cannot set — and a scene file would be one more thing to keep in
## step with this script by hand.
##
## §3's breakpoint tiers deliberately do not apply. A HUD has no docks to
## collapse, and the tier system exists to decide what to hide when a catalogue
## will not fit. What does apply is [code]UiScale[/code]: one preference scales
## the HUD and the garage together.

## §14.2 puts the HUD above the world and below the modal layer of §9.
const HUD_LAYER: int = 5

## ===== DAMAGE FLASH (§14.4) ============================================

const FLASH_ALPHA_PER_PACKET: float = 0.06
## A spall burst is several packets in one tick (HANDOFF.md §4's note on spall).
## Without the clamp a single kinetic hit would white out the screen.
const FLASH_ALPHA_MAX: float = 0.34
const FLASH_DECAY_HZ: float = 4.5

## ===== EVENT FEED (§14.4) ==============================================

const FEED_MAX_LINES: int = 5
## Borrowed from §9.2's toast dwell, so the two read as one system.
const FEED_DWELL_S: float = 3.2
const FEED_FADE_S: float = 0.25

const MARGIN_PX: int = 18

## ===== STRING KEYS =====================================================
## CLAUDE.md §10 rule 8: never a literal user-facing string.

const KEY_INTEGRITY: StringName = &"hud.integrity"
const KEY_POWER: StringName = &"hud.power"
const KEY_SPEED: StringName = &"hud.speed"
const KEY_ROUNDS: StringName = &"hud.rounds"
const KEY_UNLIMITED: StringName = &"hud.rounds.unlimited"
const KEY_PARTS: StringName = &"hud.parts"
const KEY_PART_LOST: StringName = &"hud.event.part_lost"
const KEY_ASSEMBLY_LOST: StringName = &"hud.event.assembly_lost"

## §14.6's card. Tab in §7.1's table, and the one consumer that action has ever
## had: in a match the card [i]is[/i] the HUD's expanded panel, because there is
## no separate stat panel to expand.
const ACTION_TOGGLE_CARD: StringName = &"hud_toggle_stats"

## The Assembly whose state this HUD shows. An id, not a node — §14.1.
var local_assembly_id: int = 0

var _reticle: Reticle = null
var _control_card: ControlCard = null
var _end_card: MatchEndCard = null
var _integrity: MeterRow = null
var _power: MeterRow = null
var _speed_value: Label = null
var _rounds_value: Label = null
var _parts_value: Label = null
var _feed: VBoxContainer = null
var _flash: ColorRect = null

var _flash_alpha: float = 0.0
## Line -> seconds remaining. Parallel to [member _feed]'s children, oldest first.
var _feed_ages: Array[float] = []


func _ready() -> void:
	layer = HUD_LAYER
	_build()
	# §14.6's first-run rule. The card is raised on a player's first match and not
	# on their second, which is the half that was missing while there was nowhere
	# to store "they have seen it". The flag is written the moment it goes up
	# rather than when it comes down: a player who quits during their first match
	# has still met the controls, and the alternative is a card that returns for
	# anybody who closed the window early.
	#
	# It never becomes unreachable — `hud_toggle_stats` raises it at any time, and
	# the card's own last row says so.
	if not SyndicateSettings.control_card_seen:
		_control_card.raise_first_run()
		SyndicateSettings.mark_control_card_seen()
	EventBus.part_damaged.connect(_on_part_damaged)
	EventBus.part_destroyed.connect(_on_part_destroyed)
	EventBus.assembly_terminated.connect(_on_assembly_terminated)


func _exit_tree() -> void:
	if EventBus.part_damaged.is_connected(_on_part_damaged):
		EventBus.part_damaged.disconnect(_on_part_damaged)
	if EventBus.part_destroyed.is_connected(_on_part_destroyed):
		EventBus.part_destroyed.disconnect(_on_part_destroyed)
	if EventBus.assembly_terminated.is_connected(_on_assembly_terminated):
		EventBus.assembly_terminated.disconnect(_on_assembly_terminated)


## §14.4. Decays the flash and ages the feed against real time.
##
## Real time rather than ticks, deliberately: both are presentation dwell, and a
## player pausing the simulation should not freeze a message mid-read.
func _process(dt: float) -> void:
	if _flash_alpha > 0.0:
		_flash_alpha = maxf(0.0, _flash_alpha - _flash_alpha * FLASH_DECAY_HZ * dt)
		if _flash_alpha < 0.001:
			_flash_alpha = 0.0
		_flash.color = Color(UiTokens.DANGER, _flash_alpha)
	_age_feed(dt)
	# The two cards keep no timer of their own; see [ControlCard]. One
	# per-frame callback in the HUD is the whole of §14's real-time budget.
	_control_card.age(dt)
	_end_card.age(dt)


## §14.6's toggle. The card is the one piece of this interface a player asks for
## rather than being shown, so it is the one piece that reads the input map.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION_TOGGLE_CARD):
		return
	# Not once the match is over. §16.2 takes the card down at the conclusion, and
	# raising it again would put a panel of driving controls behind the card
	# explaining that there is nothing left to drive.
	if _end_card.is_raised():
		return
	_control_card.toggle()
	get_viewport().set_input_as_handled()


## True while §14.6's first-run briefing is on screen, and false for a card the
## player raised themselves.
##
## The one thing outside this HUD that reads the control card, and the reason it
## is a query rather than a signal: doc 05 §15.7.4's hold has to be true on the
## tick it is read, and a briefing that ended between two ticks would leave a
## driver holding its fire until the next edge.
func briefing_is_up() -> bool:
	return _control_card.is_briefing()


## §14.1. The whole continuous half of the interface, once per tick.
func present(frame: HudFrame) -> void:
	if frame == null:
		return
	_reticle.set_state(frame.reticle_state)
	_reticle.set_target_acquired(frame.target_acquired)
	_integrity.set_condition(
		frame.integrity_fraction, "%d%%" % int(roundf(frame.integrity_fraction * 100.0))
	)
	_power.set_values(
		frame.power_draw_pu,
		frame.power_capacity_pu,
		"%d / %d" % [int(frame.power_draw_pu), int(frame.power_capacity_pu)]
	)
	_speed_value.text = "%.1f" % frame.speed_mps
	var rounds := tr(KEY_UNLIMITED)
	if frame.rounds_remaining != AmmoLedger.UNLIMITED:
		rounds = str(frame.rounds_remaining)
	_rounds_value.text = rounds
	_parts_value.text = "%d / %d" % [frame.parts_alive, frame.parts_total]


## §16.2. Raises the end card for [param outcome], a [enum MatchState.Outcome],
## and takes the control card down — a player being told the match is over does
## not also need to be told which key steers.
func present_outcome(outcome: int) -> void:
	_control_card.dismiss()
	# The reticle goes with them. §14.3's five states are all statements about a
	# mount the player no longer commands — [MatchScreen] stops feeding the aim
	# point and the trigger at the conclusion — so a reticle left up is a
	# crosshair promising a shot that cannot be taken.
	_reticle.visible = false
	_end_card.show_outcome(outcome)


## ===== CONSTRUCTION ====================================================


func _build() -> void:
	_flash = ColorRect.new()
	_flash.name = "DamageFlash"
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(UiTokens.DANGER, 0.0)
	add_child(_flash)

	_reticle = Reticle.new()
	_reticle.name = "Reticle"
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_reticle)

	var frame := MarginContainer.new()
	frame.name = "SafeAreaFrame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "top", "right", "bottom"] as Array[String]:
		frame.add_theme_constant_override("margin_%s" % side, MARGIN_PX)
	add_child(frame)

	var rows := VBoxContainer.new()
	rows.name = "HudRows"
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(rows)

	_feed = VBoxContainer.new()
	_feed.name = "EventFeed"
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.size_flags_horizontal = Control.SIZE_SHRINK_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(_feed)

	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.size_flags_vertical = Control.SIZE_FILL | Control.SIZE_EXPAND
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(spacer)

	var bottom := HBoxContainer.new()
	bottom.name = "BottomRow"
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(bottom)

	bottom.add_child(_build_status_panel())

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(gap)

	bottom.add_child(_build_speed_panel())

	# Both cards go above the rows and below nothing, so a message that matters
	# more than the meters is drawn over them rather than behind them.
	_control_card = ControlCard.new()
	_control_card.name = "ControlCard"
	add_child(_control_card)

	_end_card = MatchEndCard.new()
	_end_card.name = "MatchEndCard"
	add_child(_end_card)


func _build_status_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "StatusPanel"
	panel.theme_type_variation = &"DockPanel"
	panel.custom_minimum_size.x = 220.0

	var col := VBoxContainer.new()
	col.name = "Meters"
	panel.add_child(col)

	_integrity = MeterRow.new()
	_integrity.configure(KEY_INTEGRITY)
	col.add_child(_integrity)

	_power = MeterRow.new()
	_power.configure(KEY_POWER)
	col.add_child(_power)

	_rounds_value = _add_stat_row(col, KEY_ROUNDS)
	_parts_value = _add_stat_row(col, KEY_PARTS)

	return panel


## A caption on the left and a value on the right, returning the value label.
## Two of these went in by hand and immediately drifted — the rounds count ended
## up sharing the parts row, where "600 12/12" reads as six hundred parts.
func _add_stat_row(into: VBoxContainer, caption_key: StringName) -> Label:
	var row := HBoxContainer.new()
	into.add_child(row)

	var caption := Label.new()
	caption.theme_type_variation = &"StatCaption"
	caption.text = tr(caption_key)
	caption.size_flags_horizontal = Control.SIZE_FILL | Control.SIZE_EXPAND
	row.add_child(caption)

	var value := Label.new()
	value.theme_type_variation = &"StatValue"
	row.add_child(value)
	return value


func _build_speed_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "SpeedPanel"
	panel.theme_type_variation = &"DockPanel"

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	_speed_value = Label.new()
	_speed_value.theme_type_variation = &"StatValue"
	_speed_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_value.text = "0.0"
	col.add_child(_speed_value)

	var caption := Label.new()
	caption.theme_type_variation = &"StatCaption"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.text = tr(KEY_SPEED)
	col.add_child(caption)

	return panel


## ===== EVENTS ==========================================================


func _on_part_damaged(assembly_id: int, _slot: int, _amount: float, _channel: int) -> void:
	if assembly_id != local_assembly_id:
		return
	_flash_alpha = minf(FLASH_ALPHA_MAX, _flash_alpha + FLASH_ALPHA_PER_PACKET)
	_flash.color = Color(UiTokens.DANGER, _flash_alpha)


func _on_part_destroyed(assembly_id: int, slot: int, _cause: int) -> void:
	if assembly_id != local_assembly_id:
		return
	_push_line(tr(KEY_PART_LOST) % slot, UiTokens.WARN)


func _on_assembly_terminated(assembly_id: int, _killer_id: int) -> void:
	var colour := UiTokens.DANGER if assembly_id == local_assembly_id else UiTokens.TEXT_PRIMARY
	_push_line(tr(KEY_ASSEMBLY_LOST) % assembly_id, colour)


func _push_line(text: String, colour: Color) -> void:
	var label := Label.new()
	label.theme_type_variation = &"StatValue"
	label.text = text
	label.modulate = colour
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(label)
	_feed_ages.append(FEED_DWELL_S)
	# Oldest first, so trimming from the front drops the line that has been
	# readable longest rather than the one that just arrived.
	while _feed_ages.size() > FEED_MAX_LINES:
		_feed_ages.remove_at(0)
		var oldest := _feed.get_child(0)
		# Removed before it is freed: [method Node.queue_free] defers to the end
		# of the frame, so a node only queued would still be at index 0 and the
		# ages array and the child list would disagree until then.
		_feed.remove_child(oldest)
		oldest.queue_free()


func _age_feed(dt: float) -> void:
	var i := 0
	while i < _feed_ages.size():
		_feed_ages[i] -= dt
		var line := _feed.get_child(i) as Control
		if _feed_ages[i] <= 0.0:
			_feed_ages.remove_at(i)
			_feed.remove_child(line)
			line.queue_free()
			continue
		if line != null and _feed_ages[i] < FEED_FADE_S:
			line.modulate.a = _feed_ages[i] / FEED_FADE_S
		i += 1
