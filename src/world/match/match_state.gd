class_name MatchState
extends Node
## Who is still standing, and what that means, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §16.
##
## Doc 04 §8.2 names three consumers for [signal EventBusService.assembly_terminated]
## — match state, scoring, and respawn — and until now the signal had a producer
## and none of them. This is the first: it holds the roster the match layer
## already owns, counts a team out when its last Assembly loses its Core Module,
## and says once, and only once, that the match is over.
##
## [b]It is event-driven and holds no Assembly.[/b] Invariant I-4: the roster is
## a dictionary of integers, a termination is a signal, and there is no tick at
## which this class walks anything. A match that nobody dies in costs it nothing
## at all.
##
## [b]The rule is a static function over a standing-team list[/b], because a rule
## reachable only through a signal is a rule that can only be tested by staging a
## death. [method resolve_outcome] is the whole law and takes three lines of
## arguments; everything else here is bookkeeping that feeds it.
##
## [b]What it deliberately does not do.[/b] It does not despawn, respawn, freeze
## the simulation, or decide what the player sees. §16.2 records why the wreck is
## left in the road: an Assembly that vanishes when its Core Module goes takes
## with it the debris, the craters and the hulk that are the entire record of the
## fight, and the camera then has nothing to look at. The presentation is
## [MatchEndCard]'s and the transition is [MatchScreen]'s.

## Emitted once, on the tick the last opposing team is counted out.
##
## A signal on this class rather than one more entry in [EventBusService]: doc 04
## §8's list is the project's cross-system contract and every addition to it is a
## permanent widening of what any class may listen to. This has one producer and
## one consumer, both inside the match layer, and the [MatchScreen] that owns
## this object is the only thing that ever connects.
signal match_concluded(outcome: int, winning_team: int)

enum Outcome {
	## Two or more teams are still standing. The starting state.
	UNDECIDED = 0,
	## The local team is the last one standing.
	VICTORY = 1,
	## Somebody else is.
	DEFEAT = 2,
	## Nobody is — the last two Assemblies were destroyed on the same tick.
	DRAW = 3,
}

## Answer of [method winning_team] for every outcome but [constant Outcome.VICTORY]
## and [constant Outcome.DEFEAT].
const NO_TEAM: int = -1

## The side the player is on. Only [method resolve_outcome] reads it, and only to
## turn "team 1 won" into "you lost".
var local_team: int = 0

## Assembly id -> team, for every Assembly this match spawned.
var _team_of: Dictionary = {}
## Team -> number of its Assemblies whose Core Module is intact.
var _live_per_team: Dictionary = {}
## Assembly ids already counted out, as a set. Doc 04 §8.2 makes
## [DamageResolver] the only producer and it emits once per Assembly, so this
## guards a contract rather than a known bug — but the failure it prevents is
## silent and total: a second decrement takes a live team's count to zero and
## ends the match against a side that is still standing.
var _counted_out: Dictionary = {}
var _outcome: int = Outcome.UNDECIDED
var _winning_team: int = NO_TEAM


func _ready() -> void:
	EventBus.assembly_terminated.connect(_on_assembly_terminated)


func _exit_tree() -> void:
	if EventBus.assembly_terminated.is_connected(_on_assembly_terminated):
		EventBus.assembly_terminated.disconnect(_on_assembly_terminated)


## Adds an Assembly to the roster on [param team].
##
## Called as each Assembly is spawned, before it can be shot at. An id this has
## never seen is ignored when it terminates — the same discipline [AiContext]
## applies to a candidate whose side nobody stated, and for the same reason: a
## team inferred from silence is a team that decides a match by accident.
func register(assembly_id: int, team: int) -> void:
	if _team_of.has(assembly_id):
		push_warning("MatchState: assembly %d registered twice" % assembly_id)
		return
	_team_of[assembly_id] = team
	_live_per_team[team] = int(_live_per_team.get(team, 0)) + 1


## Teams with at least one Assembly whose Core Module is intact, ascending.
##
## Sorted rather than left in insertion order for Invariant I-9: this list is the
## sole argument to [method resolve_outcome], and a rule whose answer depends on
## the order two teams happened to spawn in is a rule that can disagree with
## itself between a server and a client.
func teams_standing() -> PackedInt32Array:
	var out := PackedInt32Array()
	for team: int in _live_per_team.keys():
		if int(_live_per_team[team]) > 0:
			out.append(team)
	out.sort()
	return out


func outcome() -> int:
	return _outcome


## The team that won, or [constant NO_TEAM] for an undecided or drawn match.
func winning_team() -> int:
	return _winning_team


func is_concluded() -> bool:
	return _outcome != Outcome.UNDECIDED


## The team [param assembly_id] is on, or [constant NO_TEAM].
func team_of(assembly_id: int) -> int:
	return int(_team_of.get(assembly_id, NO_TEAM))


## §16.1's whole law: what a list of standing teams means to [param local_team].
##
## A static over the list rather than a method over the roster, so that every
## case — including the two nothing in a match can currently stage, a draw and a
## match that starts with one team in it — is reachable without killing anybody.
static func resolve_outcome(standing: PackedInt32Array, local_team: int) -> int:
	if standing.size() >= 2:
		return Outcome.UNDECIDED
	if standing.is_empty():
		return Outcome.DRAW
	return Outcome.VICTORY if standing[0] == local_team else Outcome.DEFEAT


## ===== PRIVATE =========================================================


## Doc 04 §8.2. [param killer_id] is not read here — who landed the round is
## §16.3's scoreboard question and this class answers the other one.
func _on_assembly_terminated(assembly_id: int, _killer_id: int) -> void:
	if _outcome != Outcome.UNDECIDED:
		# A match concludes once. Two Assemblies destroyed on the same tick raise
		# two signals, and a second conclusion would put a second end card over
		# the first one.
		return
	if not _team_of.has(assembly_id) or _counted_out.has(assembly_id):
		return
	_counted_out[assembly_id] = true
	var team := int(_team_of[assembly_id])
	_live_per_team[team] = maxi(0, int(_live_per_team.get(team, 0)) - 1)

	var standing := teams_standing()
	var next := resolve_outcome(standing, local_team)
	if next == Outcome.UNDECIDED:
		return
	_outcome = next
	_winning_team = standing[0] if standing.size() == 1 else NO_TEAM
	match_concluded.emit(_outcome, _winning_team)
