extends TestCase
## Doc 11 §14.6's first-run rule, through the two classes that implement it.
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
## The settings file is put back in [method after_all]. Raising the card writes
## it — that is the feature — and a test that left it written would silently
## change what a developer's next run of the game does.

var _saved: PackedByteArray = PackedByteArray()
var _had_file: bool = false
var _seen_before: bool = false

var _first_raised: bool = false
var _flag_after_first: bool = false
var _second_raised: bool = false


func before_all() -> void:
	_had_file = FileAccess.file_exists(SettingsService.SETTINGS_PATH)
	if _had_file:
		_saved = FileAccess.get_file_as_bytes(SettingsService.SETTINGS_PATH)
	_seen_before = SyndicateSettings.control_card_seen

	SyndicateSettings.control_card_seen = false
	_first_raised = _card_raised_by_a_new_hud()
	_flag_after_first = SyndicateSettings.control_card_seen
	_second_raised = _card_raised_by_a_new_hud()


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


## ===== FIXTURE =========================================================


## Builds a real [MatchHud], reads whether its card came up, and takes it down
## again. The card is reached by node name rather than through an accessor added
## for this: §14.6's card is a child of the HUD with a fixed name, and a public
## getter would be API that only a test ever calls.
func _card_raised_by_a_new_hud() -> bool:
	var hud := MatchHud.new()
	hud.name = "TestMatchHud"
	EventBus.get_tree().root.add_child(hud)
	var card := hud.get_node("ControlCard") as ControlCard
	var raised := card != null and card.is_raised()
	# Remove first, then free: `_exit_tree` is where the HUD drops its bus
	# connections, and `free()` alone on a node this file owns would leave the
	# next one built on top of a listener that no longer has a card (fact 69).
	EventBus.get_tree().root.remove_child(hud)
	hud.free()
	return raised
