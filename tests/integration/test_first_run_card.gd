extends TestCase
## Doc 11 §14.6's first-run rule and the briefing hold that hangs off it, through
## the four classes that implement them.
##
## The rule is one `if` in [MatchHud] and one flag on [SettingsService], and it is
## exactly the shape of thing that gets written, works when it is tried by hand,
## and is never asserted — at which point the next session that touches the HUD
## can delete it and watch the suite stay green. `tests/unit/test_control_card.gd`
## owns the card's own dwell and placement and needs no tree; this needs one,
## because what is being asserted is that the HUD [i]consults[/i] the flag.
##
## Both directions, because a rule with one is not a rule: a first-time player
## gets the card, a returning player does not, and the returning player's HUD is
## a second [MatchHud] built after the first has written the flag.
##
## [b]The second half is the hold.[/b] The card was moved out of the middle of the
## screen and raised only once, and the capture that verified both showed the
## thing neither fixed: the opponent arrives at four seconds into an eleven-second
## dwell, so a first-time player who does what the card is for loses a third of
## their machine doing it. Doc 05 §15.7.4 gained a third gate for that, and it is
## asserted here rather than in an engagement file because it is a rule about a
## boolean and not about a fight — [method AiDriver.step] is separable from the
## clock for exactly this.
##
## The two halves that must not be confused are asserted apart: a card raised by
## the player is not a briefing, or a hold would be something a player could take
## whenever they liked by leaning on `hud_toggle_stats`.
##
## The settings file is put back in [method after_all]. Raising the card writes
## it — that is the feature — and a test that left it written would silently
## change what a developer's next run of the game does.

## Where the two Assemblies stand, in metres apart. Inside
## [constant AiDriver.GROUND_STAND_OFF_M], so a driver spawned here has already
## arrived: §15.7.4's other two gates are open on the first tick and the only
## thing that can hold the trigger is the one under test.
const SEPARATION_M: float = 10.0

## Ticks of [method AiDriver.step] each phase is given. Enough to cover
## [method AiTargetSelector.initial_scan_offset_s] plus a scan interval, so the
## driver has certainly chosen a target and certainly acted on it.
const PHASE_TICKS: int = 60

## A store the attacker cannot run out of over 120 ticks. Nothing here reads the
## ledger — the trigger is the subject — but a driver with an empty magazine is a
## driver that would pass the held phase for the wrong reason.
const LOADED_ROUNDS: int = 400

var _saved: PackedByteArray = PackedByteArray()
var _had_file: bool = false
var _seen_before: bool = false

var _first_raised: bool = false
var _first_briefing: bool = false
var _flag_after_first: bool = false
var _second_raised: bool = false
var _second_briefing: bool = false
## A card the player asked for on a HUD that has already spent its first run:
## up, and not a briefing.
var _toggled_raised: bool = false
var _toggled_briefing: bool = false

## Whether the driver's trigger was ever open during each phase.
var _fired_while_held: bool = false
var _fired_once_released: bool = false
## What the driver was doing while it was held, so that a phase in which it
## simply had nothing to shoot at cannot pass as a hold.
var _target_while_held: int = 0
var _stopped_while_held: bool = false


func before_all() -> void:
	_had_file = FileAccess.file_exists(SettingsService.SETTINGS_PATH)
	if _had_file:
		_saved = FileAccess.get_file_as_bytes(SettingsService.SETTINGS_PATH)
	_seen_before = SyndicateSettings.control_card_seen

	SyndicateSettings.control_card_seen = false
	_measure_first_hud()
	_flag_after_first = SyndicateSettings.control_card_seen
	_measure_second_hud()
	_measure_hold()


func after_all() -> void:
	SyndicateSettings.control_card_seen = _seen_before
	if _had_file:
		var f := FileAccess.open(SettingsService.SETTINGS_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_saved)
			f.close()
	else:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(SettingsService.SETTINGS_PATH)
		)


func test_a_first_time_player_is_shown_the_controls() -> void:
	check_true(_first_raised, "the card is up on the first match a player ever opens")


func test_being_shown_them_is_recorded() -> void:
	check_true(
		_flag_after_first,
		"and the flag is written when it goes up, not when it comes down — a player "
			+ "who quits mid-match has still met the controls"
	)


func test_a_returning_player_is_not_shown_them_again() -> void:
	check_false(_second_raised, "the second match opens with the screen clear")
	check_false(_second_briefing, "and nothing is holding the opposition off it")


## ===== THE BRIEFING (§14.6) ============================================


func test_the_first_run_card_is_a_briefing() -> void:
	check_true(
		_first_briefing,
		"the HUD reports a briefing while §14.6's first-run card is up, which is "
			+ "what doc 05 §15.7.4's third gate reads"
	)


## The half that keeps the hold honest. A card the player raised is a legend, not
## a briefing: without this distinction `hud_toggle_stats` is a key that stops the
## opponent shooting for eleven seconds at a time, for as long as a player cares
## to hold it.
func test_a_card_the_player_asked_for_is_not_a_briefing() -> void:
	check_true(_toggled_raised, "the toggle puts the card up on a returning player's HUD")
	check_false(
		_toggled_briefing,
		"and it buys them no grace at all — a briefing is given once, not taken"
	)


## ===== THE HOLD (doc 05 §15.7.4) =======================================


## The gate itself, in both directions, on a driver that is stopped, inside its
## stand-off, and looking at a live enemy — which is to say on a driver whose
## other two gates are open and which would otherwise certainly be firing.
func test_a_held_driver_does_not_open_its_trigger() -> void:
	if not check_true(_target_while_held != 0, "the held driver had a target the whole time"):
		return
	if not check_true(_stopped_while_held, "and was stopped inside its stand-off"):
		return
	check_false(
		_fired_while_held,
		"and it held its fire for every one of the %d ticks the briefing was up"
			% PHASE_TICKS
	)


## The other direction, and it is the one that separates a hold from a driver
## that was never going to shoot. Same driver, same pose, same target: the hold
## comes off and the trigger goes down.
func test_the_same_driver_fires_the_moment_the_briefing_ends() -> void:
	check_true(
		_fired_once_released,
		"the trigger went down on the same driver once the card was gone"
	)


## ===== FIXTURE =========================================================


func _measure_first_hud() -> void:
	var hud := _new_hud()
	var card := hud.get_node("ControlCard") as ControlCard
	_first_raised = card != null and card.is_raised()
	_first_briefing = hud.briefing_is_up()
	_release_hud(hud)


func _measure_second_hud() -> void:
	var hud := _new_hud()
	var card := hud.get_node("ControlCard") as ControlCard
	_second_raised = card != null and card.is_raised()
	_second_briefing = hud.briefing_is_up()
	if card != null:
		# The player's own route back to it — [method ControlCard.toggle] is what
		# `hud_toggle_stats` reaches.
		card.toggle()
		_toggled_raised = card.is_raised()
		_toggled_briefing = hud.briefing_is_up()
		card.dismiss()
	_release_hud(hud)


## Builds a real [MatchHud]. The card is reached by node name rather than through
## an accessor added for this: §14.6's card is a child of the HUD with a fixed
## name, and a public getter would be API that only a test ever calls.
func _new_hud() -> MatchHud:
	var hud := MatchHud.new()
	hud.name = "TestMatchHud"
	EventBus.get_tree().root.add_child(hud)
	return hud


## Remove first, then free: `_exit_tree` is where the HUD drops its bus
## connections, and `free()` alone on a node this file owns would leave the next
## one built on top of a listener that no longer has a card (fact 69).
func _release_hud(hud: MatchHud) -> void:
	EventBus.get_tree().root.remove_child(hud)
	hud.free()


## Two Assemblies ten metres apart, one of them driven by a real [AiDriver], and
## sixty ticks of that driver with the hold on followed by sixty with it off.
##
## No physics frames at all. [method AiDriver.step] is separable from
## [signal MatchClockService.tick_started] precisely so that a rule about what the
## driver decides can be asserted without simulating what the decision does, and
## the bodies never move, so "stopped" and "inside its stand-off" are properties
## of the fixture rather than of a settle that might not have finished.
func _measure_hold() -> void:
	var arena := CombatArena.new()
	arena.open()
	var attacker := arena.spawn(
		CombatArena.Recipe.WHEELED_LIGHT,
		0,
		Vector2(0.0, SEPARATION_M * 0.5),
		0.0,
		LOADED_ROUNDS
	)
	arena.spawn(
		CombatArena.Recipe.WHEELED_LIGHT,
		1,
		Vector2(0.0, -SEPARATION_M * 0.5),
		PI,
		0
	)
	var driver := arena.make_autonomous(attacker, 1.0)

	driver.hold_fire = true
	_fired_while_held = _run_phase(driver, attacker)
	_target_while_held = driver.target_id()
	_stopped_while_held = driver.has_stopped()

	driver.hold_fire = false
	_fired_once_released = _run_phase(driver, attacker)

	# Closed the moment the record is taken (fact 48). A leaked arena stands four
	# Assemblies at the origin for every file that runs after this one.
	arena.close()


## Steps [param driver] for [constant PHASE_TICKS] and reports whether its
## trigger was ever down.
func _run_phase(driver: AiDriver, attacker: CombatArena.Combatant) -> bool:
	var fired := false
	for i: int in PHASE_TICKS:
		driver.step(SyndicateConstants.PHYSICS_DT)
		if attacker.guns.triggers[0] != 0:
			fired = true
	return fired
