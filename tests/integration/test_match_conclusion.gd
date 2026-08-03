extends TestCase
## Doc 11 §16.1's bookkeeping, driven through the signal its real producer raises.
##
## [code]tests/unit/test_match_outcome.gd[/code] asserts the rule over a list of
## standing teams. This file asserts the thing that builds that list: a roster, a
## count per team, and [signal EventBusService.assembly_terminated] arriving from
## the bus rather than from a direct call — LEARNED_FACTS.md §3, because the
## contract being defended is that the resolver's signal is enough and nothing in
## the match layer has to re-derive Invariant I-2 for itself.
##
## Every test builds its own [MatchState]. A conclusion is one-way by design, so
## a shared fixture would let the first alphabetically-sorted method decide the
## match for all the others.

const LOCAL_TEAM: int = 0
const OPPOSING_TEAM: int = 1

## Assembly ids. Arbitrary and non-contiguous, so that nothing here can be
## passing because an id happened to equal an index.
const PLAYER_ID: int = 11
const ENEMY_A: int = 23
const ENEMY_B: int = 24
## Never registered with any [MatchState] in this file.
const STRANGER_ID: int = 99

var _states: Array[MatchState] = []
var _conclusions: int = 0
var _last_outcome: int = MatchState.Outcome.UNDECIDED
var _last_winner: int = MatchState.NO_TEAM


func after_all() -> void:
	# The guard for a run that failed part-way through; every test frees its own.
	# A MatchState left in the tree stays connected to the bus and counts the next
	# file's terminations (LEARNED_FACTS.md §1 fact 11).
	while not _states.is_empty():
		_release(_states[0])


## The shipped shape: one player against two, and the player survives.
func test_the_match_ends_when_the_last_opposing_assembly_is_terminated() -> void:
	var state := _open(LOCAL_TEAM)
	state.register(PLAYER_ID, LOCAL_TEAM)
	state.register(ENEMY_A, OPPOSING_TEAM)
	state.register(ENEMY_B, OPPOSING_TEAM)

	EventBus.assembly_terminated.emit(ENEMY_A, PLAYER_ID)
	check_eq(_conclusions, 0, "one of two opponents gone is not a conclusion")
	check_eq(state.outcome(), MatchState.Outcome.UNDECIDED, "and the state agrees")

	EventBus.assembly_terminated.emit(ENEMY_B, PLAYER_ID)
	check_eq(_conclusions, 1, "the second one ends it")
	check_eq(_last_outcome, MatchState.Outcome.VICTORY, "the local team is left standing")
	check_eq(_last_winner, LOCAL_TEAM, "and is named as the winner")
	_release(state)


## The case a player reaches every time, inside a minute.
func test_the_match_ends_when_the_player_is_terminated() -> void:
	var state := _open(LOCAL_TEAM)
	state.register(PLAYER_ID, LOCAL_TEAM)
	state.register(ENEMY_A, OPPOSING_TEAM)
	state.register(ENEMY_B, OPPOSING_TEAM)

	EventBus.assembly_terminated.emit(PLAYER_ID, ENEMY_A)
	check_eq(_conclusions, 1, "the player's side is out, so the match is over")
	check_eq(_last_outcome, MatchState.Outcome.DEFEAT, "which is a defeat")
	check_eq(_last_winner, OPPOSING_TEAM, "credited to the side still standing")
	_release(state)


## Doc 04 §8.2 emits per Assembly, so a mutual kill raises two signals. The second
## must not conclude a match that has already concluded — and it must not
## re-decide it, which is the failure that would put a second card over the first.
func test_a_second_termination_does_not_conclude_the_match_twice() -> void:
	var state := _open(LOCAL_TEAM)
	state.register(PLAYER_ID, LOCAL_TEAM)
	state.register(ENEMY_A, OPPOSING_TEAM)

	EventBus.assembly_terminated.emit(ENEMY_A, PLAYER_ID)
	check_eq(_conclusions, 1, "the opponent going ends it")
	check_eq(_last_outcome, MatchState.Outcome.VICTORY, "as a victory")

	EventBus.assembly_terminated.emit(PLAYER_ID, ENEMY_A)
	check_eq(_conclusions, 1, "the player going on the same tick does not end it again")
	check_eq(state.outcome(), MatchState.Outcome.VICTORY, "and does not turn the win into a draw")
	_release(state)


## §16.1: an Assembly the roster does not name cannot decide a match. The failure
## this defends against is silent — an unregistered id decrementing a team that
## does not exist, or worse, defaulting onto one that does.
func test_an_unregistered_assembly_cannot_end_the_match() -> void:
	var state := _open(LOCAL_TEAM)
	state.register(PLAYER_ID, LOCAL_TEAM)
	state.register(ENEMY_A, OPPOSING_TEAM)

	EventBus.assembly_terminated.emit(STRANGER_ID, PLAYER_ID)
	check_eq(_conclusions, 0, "a stranger's destruction decides nothing")
	check_eq(
		state.teams_standing().size(), 2, "and takes nobody off the standing list"
	)
	check_eq(state.team_of(STRANGER_ID), MatchState.NO_TEAM, "it is on no side at all")
	_release(state)


## The same id terminated twice must not take a team below zero, which would make
## a standing team read as missing and conclude the match against whoever was
## still alive.
func test_a_repeated_termination_does_not_count_a_team_out_twice() -> void:
	var state := _open(LOCAL_TEAM)
	state.register(PLAYER_ID, LOCAL_TEAM)
	state.register(ENEMY_A, OPPOSING_TEAM)
	state.register(ENEMY_B, OPPOSING_TEAM)

	EventBus.assembly_terminated.emit(ENEMY_A, PLAYER_ID)
	EventBus.assembly_terminated.emit(ENEMY_A, PLAYER_ID)
	check_eq(_conclusions, 0, "one opponent gone twice is still one opponent gone")
	var standing := state.teams_standing()
	check_eq(standing.size(), 2, "both sides are still standing")
	_release(state)


## Invariant I-9. The standing list is the rule's only argument, so its order must
## not depend on which side happened to register first.
func test_the_standing_list_is_sorted() -> void:
	var state := _open(LOCAL_TEAM)
	state.register(ENEMY_A, OPPOSING_TEAM)
	state.register(PLAYER_ID, LOCAL_TEAM)
	var standing := state.teams_standing()
	check_eq(standing.size(), 2, "two sides registered")
	check_true(
		standing[0] < standing[1],
		"ascending regardless of registration order: got %s" % [standing]
	)
	_release(state)


## The roster is read back, not just written. A [method MatchState.register] that
## recorded the count and dropped the mapping would pass every test above.
func test_the_roster_answers_which_side_an_assembly_is_on() -> void:
	var state := _open(LOCAL_TEAM)
	state.register(PLAYER_ID, LOCAL_TEAM)
	state.register(ENEMY_A, OPPOSING_TEAM)
	check_eq(state.team_of(PLAYER_ID), LOCAL_TEAM, "the player is on the local team")
	check_eq(state.team_of(ENEMY_A), OPPOSING_TEAM, "and the opponent is not")
	_release(state)


## ===== FIXTURE =========================================================


## A [MatchState] in the real tree with the counters reset. It has to be in a tree
## for [method Node._ready] to connect it to the bus, and a [TestCase] has none of
## its own (LEARNED_FACTS.md §1 fact 11).
func _open(local_team: int) -> MatchState:
	_conclusions = 0
	_last_outcome = MatchState.Outcome.UNDECIDED
	_last_winner = MatchState.NO_TEAM
	var state := MatchState.new()
	state.local_team = local_team
	state.match_concluded.connect(_on_match_concluded)
	EventBus.get_tree().root.add_child(state)
	_states.append(state)
	return state


## Removes then frees, and drops the handle. Dropping it matters: a freed object
## passed back into a typed parameter is a runtime type error before the body
## runs, so [method after_all] can only sweep entries it knows are still live.
func _release(state: MatchState) -> void:
	if state == null or not is_instance_valid(state):
		return
	_states.erase(state)
	if state.get_parent() != null:
		state.get_parent().remove_child(state)
	state.free()


func _on_match_concluded(outcome: int, winning_team: int) -> void:
	_conclusions += 1
	_last_outcome = outcome
	_last_winner = winning_team
