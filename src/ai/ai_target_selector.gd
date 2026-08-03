class_name AiTargetSelector
extends RefCounted
## Picks what an AI Assembly shoots at, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §10.
##
## Four weighted terms over an [AiContext] and nothing else. It holds no state,
## reaches into no system, and runs on §10's scan interval rather than per tick —
## so it is a pure function of a record, and a test can put six candidates in
## front of it without building a match.
##
## [b]An AI Assembly uses the same [EffectorSystem] as a player.[/b] Only the
## source of the aim point differs. Nothing here nudges accuracy, damage, or
## rate of fire: §10's difficulty model is an offset applied to the aim point, so
## an AI miss is a real miss that puts a real tracer somewhere and can hit a
## third party.

## ===== §10's WEIGHTS ===================================================
## Written out as named constants rather than inline, and asserted by value in
## [code]tests/unit/test_ai_target_selector.gd[/code] against the document. A
## test that read these back out of this file would assert nothing.

## Seconds between scans. 2.9 Hz. Aim solving runs every tick because it must,
## but choosing a target is a decision and does not need to be revisited sixty
## times a second.
const SCAN_INTERVAL_S: float = 0.35
## Beyond this, a candidate is not considered at all.
const MAX_ENGAGEMENT_RANGE_M: float = 320.0
## Proximity: the nearest live enemy, expressed as a term rather than a rule so
## that the others can outvote it.
const PROXIMITY_WEIGHT: float = 240.0
## Range the proximity term stops growing at, so a candidate at two metres does
## not score a hundred times one at twenty.
const PROXIMITY_FLOOR_M: float = 8.0
## Finish wounded targets. §10.2 records that at these weights this is a
## tie-break between two candidates at equal range and cannot move one to the
## top; that is measured, not a defect.
const WOUNDED_WEIGHT: float = 1.6
## Retaliation: shoot whoever last hit you.
const RETALIATION_WEIGHT: float = 90.0
## Slew-time penalty for a target outside the mount's arc. §10.2: a boolean, not
## an angle, and at this weight a near-absolute preference for a target the mount
## can actually reach.
const ARC_COST_WEIGHT: float = 140.0

## ===== §10's DIFFICULTY MODEL ==========================================

## Metres of aim error at 100 m, at difficulty 0 and difficulty 1.
const SIGMA_AT_WORST_M: float = 2.4
const SIGMA_AT_BEST_M: float = 0.15
## Range the two figures above are quoted at.
const SIGMA_REFERENCE_RANGE_M: float = 100.0
## Vertical error as a fraction of the horizontal.
const VERTICAL_SIGMA_RATIO: float = 0.5

## Stagger between consecutive Assembly ids. Deliberately not a divisor of
## [constant SCAN_INTERVAL_S]: a step that divides the interval collides ids
## modulo the quotient, and 0.11 s walks ids 1, 2, 3 onto 0.11, 0.22 and 0.33
## before wrapping to a point none of them has taken.
const SCAN_STAGGER_STEP_S: float = 0.11


## The best candidate in [param ctx], or null when nothing qualifies.
##
## Ties break on the first candidate in [member AiContext.visible_assemblies],
## which is registry order and therefore ascending by id (Invariant I-9). Two
## drivers scanning on the same tick resolve an exact tie identically, and a
## replay resolves it the same way again.
static func select(ctx: AiContext) -> AiContext.TargetHandle:
	var best: AiContext.TargetHandle = null
	var best_score := -INF
	for candidate: AiContext.TargetHandle in ctx.visible_assemblies:
		if candidate.team == ctx.team:
			continue
		var d := candidate.position.distance_to(ctx.position)
		if d > MAX_ENGAGEMENT_RANGE_M:
			continue
		var score := score_for(ctx, candidate, d)
		if score > best_score:
			best_score = score
			best = candidate
	return best


## §10's four terms, split out so that a test can assert one weight at a time
## against a fixture that isolates it.
static func score_for(ctx: AiContext, candidate: AiContext.TargetHandle, distance: float) -> float:
	var score := PROXIMITY_WEIGHT / maxf(distance, PROXIMITY_FLOOR_M)
	score += WOUNDED_WEIGHT * (1.0 - candidate.integrity_fraction)
	if candidate.id == ctx.last_attacker_id:
		score += RETALIATION_WEIGHT
	if arc_cost(ctx, candidate):
		score -= ARC_COST_WEIGHT
	return score


## True when [param candidate] is outside the mount's authored arc from where the
## hull is pointing now. §10.2.
##
## Delegated to [method EffectorSystem.reaches] rather than re-derived, because
## an arc test that disagreed with the one §7.1's fire gate makes would produce a
## driver that picks targets it then declines to shoot at. A context with no
## mount costs nothing to reach: there is no arc to be outside of.
static func arc_cost(ctx: AiContext, candidate: AiContext.TargetHandle) -> bool:
	if ctx.effectors == null or ctx.effector_slot == SyndicateConstants.INVALID_SLOT:
		return false
	return not ctx.effectors.reaches(ctx.effector_slot, candidate.position)


## §10's difficulty model: an aim-point offset, never a hidden multiplier.
##
## The spread grows with range, so a low-skill driver is roughly as inaccurate in
## angular terms at every distance and misses by more metres further out — which
## is how a human misses. The vertical term is halved because a shot that is high
## or low by the same margin as it is left or right misses by more: a hull is
## wider than it is tall.
##
## §10.3: the caller rolls this once per scan and holds the result. Re-rolling it
## per tick puts a 60 Hz random walk on the aim point, §4.2 chases noise it never
## arrives at, and the mount never reads on target — so a per-tick roll does not
## make a driver less accurate, it makes it hold fire.
static func difficulty_error(
	distance: float, difficulty: float, rng: RandomNumberGenerator
) -> Vector3:
	var sigma := (
		lerpf(SIGMA_AT_WORST_M, SIGMA_AT_BEST_M, clampf(difficulty, 0.0, 1.0))
		* (distance / SIGMA_REFERENCE_RANGE_M)
	)
	return Vector3(
		rng.randfn(0.0, sigma),
		rng.randfn(0.0, sigma * VERTICAL_SIGMA_RATIO),
		rng.randfn(0.0, sigma)
	)


## The tick a driver first scans on, staggered by Assembly id. §10.4.
##
## Deterministic rather than a random phase, so a replay reproduces which tick
## each driver re-targeted on — and spread over the whole interval rather than
## over a fixed handful of ticks, so that sixteen Assemblies do not scan in four
## clusters of four.
static func initial_scan_offset_s(assembly_id: int) -> float:
	return fposmod(float(assembly_id) * SCAN_STAGGER_STEP_S, SCAN_INTERVAL_S)
