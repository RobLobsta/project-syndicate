extends TestCase
## [SettingsService]'s stored facts, from
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §14.6.
##
## The subject is the [b]`seen` section[/b] rather than the preferences: a
## quality tier that fails to persist is an annoyance, and a first-run flag that
## fails to persist is doc 11 §14.6's card raised over every match a player ever
## plays, which is the thing the flag was added to stop. So the assertion that
## matters is the one that goes through the file.
##
## [b]Driven on a detached service, never on the autoload.[/b] `SyndicateSettings`
## has already loaded the real file by the time any test runs, and whether it has
## seen a control card depends on whether an earlier file in this run opened a
## match — so an assertion against it would be an assertion about the suite's own
## ordering (LEARNED_FACTS.md §1 fact 62). A service that was never added to the
## tree has run no [method Node._ready] and therefore holds exactly the defaults
## a new player gets.
##
## [b]And the file is put back.[/b] Saving writes every section, so a test that
## simply saved would overwrite whatever quality tier and rebinds the checkout's
## `user://` was carrying — which under `tools/ci/godot.sh` is `.tooling/`, and on
## anybody who ran the engine directly is their own settings.

var _service: SettingsService = null
## The file as it was before this file touched it, or an empty array when there
## was none. Restored in [method after_all].
var _saved: PackedByteArray = PackedByteArray()
var _had_file: bool = false


func before_all() -> void:
	_had_file = FileAccess.file_exists(SettingsService.SETTINGS_PATH)
	if _had_file:
		_saved = FileAccess.get_file_as_bytes(SettingsService.SETTINGS_PATH)
	_service = SettingsService.new()


func after_all() -> void:
	if _service != null:
		_service.free()
		_service = null
	if _had_file:
		var f := FileAccess.open(SettingsService.SETTINGS_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_saved)
			f.close()
	else:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(SettingsService.SETTINGS_PATH)
		)


## The default has to be "not seen", or the card is never raised for the one
## player it exists for.
func test_a_player_who_has_never_played_has_not_seen_the_card() -> void:
	check_false(_service.control_card_seen, "the flag starts down")


## It latches, and it latches once. The second match of a session must neither
## re-announce nor re-write, because the write is a file access and the
## announcement is what a settings screen would redraw on.
func test_marking_the_card_seen_latches_and_is_idempotent() -> void:
	var seen := SettingsService.new()
	# A recorder rather than a captured local: a GDScript lambda captures by
	# value, so a closure assigning to a local outside it writes to its own copy
	# and the assertion reads the value it started with (fact 68).
	var announcements: Array[int] = [0]
	seen.settings_changed.connect(
		func(_section: String, _key: String) -> void: announcements[0] += 1
	)
	seen.mark_control_card_seen()
	check_true(seen.control_card_seen, "the first match raises the card and records it")
	check_eq(announcements[0], 1, "and says so once")
	seen.mark_control_card_seen()
	check_eq(announcements[0], 1, "the second match neither re-records nor re-announces")
	seen.free()


## The half that makes it a first-run flag rather than a first-match one: it has
## to survive the process. A service that has never seen the file reads what the
## last one wrote.
func test_the_flag_survives_a_restart() -> void:
	var first := SettingsService.new()
	first.mark_control_card_seen()
	first.free()

	var second := SettingsService.new()
	second.load_settings()
	check_true(second.control_card_seen, "a returning player is not shown the card again")
	second.free()


## The section is not [constant SettingsService.SECTION_DISPLAY], and that is a
## decision rather than a detail: nothing in `seen` is a preference, so a
## settings screen that walked the display section would not offer to un-see
## something.
func test_what_the_player_has_seen_is_not_a_display_preference() -> void:
	check_ne(
		SettingsService.SECTION_SEEN, SettingsService.SECTION_DISPLAY,
		"a record of what was shown is not a setting"
	)
