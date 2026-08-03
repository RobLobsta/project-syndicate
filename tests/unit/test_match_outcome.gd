extends TestCase
## Doc 11 §16 — what a list of standing teams means, and what a player is told.
##
## The rule is a static over a [PackedInt32Array], which is the whole reason it
## is one: two of its four rows are states nothing in an arena can currently
## stage. A draw needs both sides destroyed on the same tick, and a one-team
## match needs a scene nobody has built. A rule reachable only through
## [signal EventBusService.assembly_terminated] would leave both untested for as
## long as they stayed unreachable, which is exactly how a match ends up unable
## to decide the one case it eventually meets.
##
## [code]tests/integration/test_match_conclusion.gd[/code] is the other half: the
## bookkeeping that turns terminations into that list, driven through the bus.

## §16's teams, by value. Two integers with no meaning of their own — which is
## the point, because [method MatchState.resolve_outcome] compares them and never
## interprets them.
const LOCAL_TEAM: int = 0
const OPPOSING_TEAM: int = 1
## A third side, so that "the local team is not standing" and "exactly one other
## team is standing" can be told apart.
const THIRD_TEAM: int = 7

## §16.2's tokens, by value. LEARNED_FACTS.md §2: a test that imports the constant
## it checks moves with the defect.
const TOKEN_ACCENT_SECONDARY := "39d98a"
const TOKEN_DANGER := "e0554e"
const TOKEN_WARN := "f2c14e"


## ===== §16.1's RULE ====================================================


func test_two_teams_standing_is_undecided() -> void:
	check_eq(
		MatchState.resolve_outcome(
			PackedInt32Array([LOCAL_TEAM, OPPOSING_TEAM]), LOCAL_TEAM
		),
		MatchState.Outcome.UNDECIDED,
		"a match with both sides in it has not been decided"
	)


## The bound is at two, not at "more than the number of sides this arena spawns".
func test_three_teams_standing_is_also_undecided() -> void:
	check_eq(
		MatchState.resolve_outcome(
			PackedInt32Array([LOCAL_TEAM, OPPOSING_TEAM, THIRD_TEAM]), LOCAL_TEAM
		),
		MatchState.Outcome.UNDECIDED,
		"three sides standing is no more decided than two"
	)


## The two single-team rows, asserted against each other rather than one at a
## time. A rule that answered VICTORY for every survivor passes any test that
## only checks the case the local team won — and that is the shipped case, so it
## is the one a fixture reaches by accident.
func test_the_last_team_standing_decides_which_way_it_went() -> void:
	check_eq(
		MatchState.resolve_outcome(PackedInt32Array([LOCAL_TEAM]), LOCAL_TEAM),
		MatchState.Outcome.VICTORY,
		"the local team alone is a win"
	)
	check_eq(
		MatchState.resolve_outcome(PackedInt32Array([OPPOSING_TEAM]), LOCAL_TEAM),
		MatchState.Outcome.DEFEAT,
		"somebody else alone is a loss"
	)


## The local team is whatever it is told it is, not zero. A rule that hard-coded
## team 0 as the player's would pass every other assertion in this file.
func test_the_local_team_is_read_and_not_assumed() -> void:
	check_eq(
		MatchState.resolve_outcome(PackedInt32Array([OPPOSING_TEAM]), OPPOSING_TEAM),
		MatchState.Outcome.VICTORY,
		"team 1 winning is a victory to a player on team 1"
	)
	check_eq(
		MatchState.resolve_outcome(PackedInt32Array([LOCAL_TEAM]), OPPOSING_TEAM),
		MatchState.Outcome.DEFEAT,
		"and team 0 winning is that player's defeat"
	)


## The row nothing in the arena can stage: both sides gone on the same tick.
func test_nobody_standing_is_a_draw() -> void:
	check_eq(
		MatchState.resolve_outcome(PackedInt32Array(), LOCAL_TEAM),
		MatchState.Outcome.DRAW,
		"an empty standing list is a draw, not a victory for team 0"
	)


## ===== §16.2's TABLE ===================================================


func test_each_outcome_has_its_own_title() -> void:
	var victory := MatchEndCard.title_key_for(MatchState.Outcome.VICTORY)
	var defeat := MatchEndCard.title_key_for(MatchState.Outcome.DEFEAT)
	var draw := MatchEndCard.title_key_for(MatchState.Outcome.DRAW)
	check_ne(victory, defeat, "a win does not read as a loss")
	check_ne(defeat, draw, "a loss does not read as a draw")
	check_ne(victory, draw, "a win does not read as a draw")


func test_each_outcome_has_its_own_detail_line() -> void:
	var victory := MatchEndCard.detail_key_for(MatchState.Outcome.VICTORY)
	var defeat := MatchEndCard.detail_key_for(MatchState.Outcome.DEFEAT)
	var draw := MatchEndCard.detail_key_for(MatchState.Outcome.DRAW)
	check_ne(victory, defeat, "a win is explained differently from a loss")
	check_ne(defeat, draw, "a loss is explained differently from a draw")
	check_ne(victory, draw, "a win is explained differently from a draw")


## §16.2's tokens by value, so a token that drifts names itself here.
func test_each_outcome_carries_its_documented_token() -> void:
	check_eq(
		MatchEndCard.colour_for(MatchState.Outcome.VICTORY).to_html(false),
		TOKEN_ACCENT_SECONDARY,
		"a win is accent_secondary"
	)
	check_eq(
		MatchEndCard.colour_for(MatchState.Outcome.DEFEAT).to_html(false),
		TOKEN_DANGER,
		"a loss is danger"
	)
	check_eq(
		MatchEndCard.colour_for(MatchState.Outcome.DRAW).to_html(false),
		TOKEN_WARN,
		"a draw is warn"
	)


## Every string the card can show has to exist in the table, or a player reads
## the key. Asserted through [method TranslationServer.translate] rather than by
## parsing the CSV, because the translation the game loads is the compiled one.
func test_every_outcome_string_is_translated() -> void:
	for outcome: int in (
		[MatchState.Outcome.VICTORY, MatchState.Outcome.DEFEAT, MatchState.Outcome.DRAW]
		as Array[int]
	):
		var title := MatchEndCard.title_key_for(outcome)
		var detail := MatchEndCard.detail_key_for(outcome)
		check_ne(
			InputPrompt.tr_key(title), String(title), "title for outcome %d is translated" % outcome
		)
		check_ne(
			InputPrompt.tr_key(detail),
			String(detail),
			"detail for outcome %d is translated" % outcome
		)
	check_ne(
		InputPrompt.tr_key(MatchEndCard.KEY_HINT),
		String(MatchEndCard.KEY_HINT),
		"the camera hint is translated"
	)
