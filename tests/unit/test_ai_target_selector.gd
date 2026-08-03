extends TestCase
## [AiTargetSelector] — doc 07 §10's target acquisition.
##
## Every weight below is written out by hand from the document rather than
## imported from the class under test. That is §2's oldest lesson: a test that
## reads the same constant the source does moves its expectation along with the
## defect, and the one time this repository forgot it — the probe-radius check —
## a probe five times too large passed.
##
## The scoring is asserted one term at a time, against fixtures built so that the
## term under test is the only thing separating two candidates. A test that
## handed the selector six different candidates and checked which one came out
## would pass against three of the four weights being zero.

## §10, by value.
const SCAN_INTERVAL_S: float = 0.35
const MAX_ENGAGEMENT_RANGE_M: float = 320.0
const PROXIMITY_WEIGHT: float = 240.0
const PROXIMITY_FLOOR_M: float = 8.0
const WOUNDED_WEIGHT: float = 1.6
const RETALIATION_WEIGHT: float = 90.0
## §10.2's arc penalty needs a real mount to be paid, so it is asserted by value
## in [code]tests/physics/test_ai_engagement.gd[/code] rather than here.

const OWN_TEAM: int = 0
const ENEMY_TEAM: int = 1

## Ids for candidates. Deliberately not consecutive from 1: a selector that
## returned the first entry, or the lowest id, must not accidentally agree with
## the right answer.
const NEAR_ID: int = 7
const FAR_ID: int = 3
const FRIEND_ID: int = 9


func _context() -> AiContext:
	var ctx := AiContext.new()
	ctx.assembly_id = 1
	ctx.team = OWN_TEAM
	ctx.position = Vector3.ZERO
	return ctx


## A candidate at [param distance] due north, intact unless told otherwise.
func _candidate(
	id: int, team: int, distance: float, integrity: float = 1.0
) -> AiContext.TargetHandle:
	var handle := AiContext.TargetHandle.new()
	handle.id = id
	handle.team = team
	handle.position = Vector3(0.0, 0.0, -distance)
	handle.integrity_fraction = integrity
	return handle


## ===== THE FILTERS =====================================================


func test_a_context_with_no_candidates_selects_nothing() -> void:
	check_null(AiTargetSelector.select(_context()), "nothing to shoot at")


## §10's first line. A driver that shot at its own side would make the roster
## worse than useless: without one, friendly fire is at least symmetrical.
func test_a_candidate_on_the_same_team_is_never_selected() -> void:
	var ctx := _context()
	ctx.visible_assemblies = [_candidate(FRIEND_ID, OWN_TEAM, 10.0)]
	check_null(AiTargetSelector.select(ctx), "the only candidate is a friend")


func test_the_nearer_of_two_enemies_is_selected() -> void:
	var ctx := _context()
	ctx.visible_assemblies = [
		_candidate(FAR_ID, ENEMY_TEAM, 120.0), _candidate(NEAR_ID, ENEMY_TEAM, 30.0)
	]
	var choice := AiTargetSelector.select(ctx)
	check_not_null(choice, "one of the two")
	check_eq(choice.id, NEAR_ID, "and it is the near one")


## Asserted in both directions, one metre either side of the gate, because a
## range check that never rejects and one that rejects everything both pass an
## assertion made only on the inside of it.
func test_a_candidate_beyond_the_engagement_range_is_not_considered() -> void:
	var ctx := _context()
	ctx.visible_assemblies = [_candidate(FAR_ID, ENEMY_TEAM, MAX_ENGAGEMENT_RANGE_M + 1.0)]
	check_null(AiTargetSelector.select(ctx), "321 m is out of range")

	ctx.visible_assemblies = [_candidate(FAR_ID, ENEMY_TEAM, MAX_ENGAGEMENT_RANGE_M - 1.0)]
	var choice := AiTargetSelector.select(ctx)
	check_not_null(choice, "319 m is in range")
	check_eq(choice.id, FAR_ID, "and it is the one that was out of range a moment ago")


## ===== THE TERMS =======================================================
## Each asserted as arithmetic against the table above, with no mount attached —
## so the arc term contributes nothing and the other three are visible.


func test_the_proximity_term_is_the_documented_curve() -> void:
	var ctx := _context()
	var far := _candidate(FAR_ID, ENEMY_TEAM, 60.0)
	check_approx(
		AiTargetSelector.score_for(ctx, far, 60.0), PROXIMITY_WEIGHT / 60.0, "240 / 60", 1e-4
	)


## The floor is what stops a candidate at two metres scoring a hundred times one
## at twenty and drowning every other term.
func test_the_proximity_term_stops_growing_at_the_floor() -> void:
	var ctx := _context()
	var point_blank := _candidate(NEAR_ID, ENEMY_TEAM, 1.0)
	check_approx(
		AiTargetSelector.score_for(ctx, point_blank, 1.0),
		PROXIMITY_WEIGHT / PROXIMITY_FLOOR_M,
		"a metre away scores what eight metres does",
		1e-4
	)
	check_approx(
		AiTargetSelector.score_for(ctx, point_blank, PROXIMITY_FLOOR_M),
		PROXIMITY_WEIGHT / PROXIMITY_FLOOR_M,
		"and eight metres scores it too",
		1e-4
	)


func test_a_wounded_candidate_scores_the_documented_bonus() -> void:
	var ctx := _context()
	var hurt := _candidate(NEAR_ID, ENEMY_TEAM, 40.0, 0.25)
	var whole := _candidate(FAR_ID, ENEMY_TEAM, 40.0, 1.0)
	check_approx(
		AiTargetSelector.score_for(ctx, hurt, 40.0)
		- AiTargetSelector.score_for(ctx, whole, 40.0),
		WOUNDED_WEIGHT * 0.75,
		"1.6 x the fraction missing",
		1e-4
	)


## §10.2 records this as measured rather than adjusted: at these weights the
## wounded term is a tie-break and cannot lift a distant candidate over a near
## one. Asserted so that a later change to either weight has to come here and
## say so.
func test_the_wounded_term_cannot_outrank_proximity() -> void:
	var ctx := _context()
	var nearly_dead_and_far := _candidate(FAR_ID, ENEMY_TEAM, 90.0, 0.0)
	var untouched_and_near := _candidate(NEAR_ID, ENEMY_TEAM, 30.0, 1.0)
	ctx.visible_assemblies = [nearly_dead_and_far, untouched_and_near]
	check_eq(AiTargetSelector.select(ctx).id, NEAR_ID, "proximity wins")


## Retaliation, by contrast, is meant to move a target: 90 against a proximity
## span of 0.75 to 30 turns "shoot the nearest" into "shoot whoever is shooting
## at you", which is the whole point of the term.
func test_the_last_attacker_outranks_a_nearer_enemy() -> void:
	var ctx := _context()
	ctx.last_attacker_id = FAR_ID
	ctx.visible_assemblies = [
		_candidate(FAR_ID, ENEMY_TEAM, 120.0), _candidate(NEAR_ID, ENEMY_TEAM, 30.0)
	]
	check_eq(AiTargetSelector.select(ctx).id, FAR_ID, "the one that hit us")
	check_approx(
		AiTargetSelector.score_for(ctx, ctx.visible_assemblies[0], 120.0)
		- (PROXIMITY_WEIGHT / 120.0),
		RETALIATION_WEIGHT,
		"and the bonus is 90 exactly",
		1e-4
	)


## With no mount, nothing is out of arc — a context with no Effector Module must
## not penalise every candidate equally, which would be invisible in a ranking
## and would show up the first time an arc test was added.
func test_a_context_with_no_mount_pays_no_arc_cost() -> void:
	var ctx := _context()
	var enemy := _candidate(NEAR_ID, ENEMY_TEAM, 40.0)
	check_false(AiTargetSelector.arc_cost(ctx, enemy), "no mount, no arc")
	check_approx(
		AiTargetSelector.score_for(ctx, enemy, 40.0),
		PROXIMITY_WEIGHT / 40.0,
		"and the score is the proximity term alone",
		1e-4
	)


## ===== TIE-BREAKING ====================================================


## Invariant I-9. Two candidates that score identically must resolve the same way
## every run, and [method AiContext.rescan] fills the list in ascending registry
## order — so "the first entry" is a deterministic rule and not an accident of
## the hash.
func test_an_exact_tie_resolves_to_the_first_candidate() -> void:
	var ctx := _context()
	var first := _candidate(FAR_ID, ENEMY_TEAM, 50.0)
	var second := _candidate(NEAR_ID, ENEMY_TEAM, 50.0)
	ctx.visible_assemblies = [first, second]
	check_eq(AiTargetSelector.select(ctx).id, FAR_ID, "the first of the two")
	ctx.visible_assemblies = [second, first]
	check_eq(AiTargetSelector.select(ctx).id, NEAR_ID, "and it is the order, not the id")


## ===== §10.3's DIFFICULTY MODEL ========================================


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## The error is an offset and never a multiplier, so it must be able to point in
## every direction. A model that only ever fell short would be a range bias.
func test_the_difficulty_error_is_a_three_dimensional_offset() -> void:
	var rng := _rng(4)
	var saw_positive := false
	var saw_negative := false
	for i: int in 64:
		var e := AiTargetSelector.difficulty_error(100.0, 0.5, rng)
		saw_positive = saw_positive or e.x > 0.0
		saw_negative = saw_negative or e.x < 0.0
	check_true(saw_positive and saw_negative, "it misses both ways")


## Invariant I-9: two Assemblies must not miss in lockstep, and a replay must
## reproduce the same misses. Asserted as an equality between two generators at
## one seed and an inequality between two seeds, because either alone passes
## against a model that returns a constant.
func test_the_difficulty_error_is_reproducible_and_not_shared() -> void:
	var a := AiTargetSelector.difficulty_error(80.0, 0.4, _rng(11))
	var b := AiTargetSelector.difficulty_error(80.0, 0.4, _rng(11))
	var c := AiTargetSelector.difficulty_error(80.0, 0.4, _rng(12))
	check_true(a.is_equal_approx(b), "one seed, one answer")
	check_false(a.is_equal_approx(c), "a different seed misses differently")


## The spread scales with range, so a driver is about as inaccurate in angular
## terms at every distance. Measured over a sample rather than asserted on one
## draw: a single draw at twice the range can land anywhere.
func test_the_error_grows_with_range() -> void:
	var near_rms := _rms_error(40.0, 0.5)
	var far_rms := _rms_error(160.0, 0.5)
	check_true(
		far_rms > near_rms * 3.0,
		"four times the range is about four times the error: %.3f against %.3f"
		% [far_rms, near_rms]
	)


## And it shrinks with difficulty, which is the direction that makes the
## parameter mean what its name says. A sign error here produces an AI that is
## worse the better it is set, and nothing else in the project would notice.
func test_a_higher_difficulty_aims_closer() -> void:
	check_true(
		_rms_error(100.0, 0.95) < _rms_error(100.0, 0.05),
		"difficulty 0.95 lands nearer than 0.05"
	)


## Root-mean-square offset over a fixed sample, at one seed so the comparison is
## between two spreads rather than between two draws.
func _rms_error(distance: float, difficulty: float) -> float:
	var rng := _rng(7)
	var total := 0.0
	for i: int in 256:
		total += AiTargetSelector.difficulty_error(distance, difficulty, rng).length_squared()
	return sqrt(total / 256.0)


## ===== §10.4's STAGGER =================================================


func test_the_scan_interval_is_the_documented_cadence() -> void:
	check_approx(AiTargetSelector.SCAN_INTERVAL_S, SCAN_INTERVAL_S, "2.9 Hz", 1e-6)


## Consecutive ids must not land on the same phase, or the stagger buys nothing
## and every driver in a sixteen-Assembly match scans on one tick.
func test_consecutive_assembly_ids_scan_on_different_phases() -> void:
	var seen: Array[float] = []
	for id: int in range(1, 9):
		var offset := AiTargetSelector.initial_scan_offset_s(id)
		check_true(
			offset >= 0.0 and offset < SCAN_INTERVAL_S,
			"id %d starts inside the interval: %.3f" % [id, offset]
		)
		for other: float in seen:
			check_true(
				absf(other - offset) > 0.001,
				"id %d does not collide with an earlier phase" % id
			)
		seen.append(offset)
