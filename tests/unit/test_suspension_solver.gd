extends TestCase
## [SuspensionSolver], from [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §6.
##
## Every expected value below is written out as arithmetic against the published
## constants rather than derived by calling the code under test with different
## arguments. A test that only asserts "more compression gives more force" passes
## against a model with the damper removed entirely.

## `mot.wheeled.allroad.t2`, §10.3: 42000 N/m, 3400 Ns/m, 0.32 m rest,
## 0.24 m travel, 620 kg rated.
const K: float = 42000.0
const C: float = 3400.0
const REST: float = 0.32
const TRAVEL: float = 0.24
const RATED_KG: float = 620.0

## Above the settle threshold, so the damper is not scaled back.
const MOVING: float = 1.0

var _profile: MotiveAssemblyProfile = null


func before_all() -> void:
	_profile = MotiveAssemblyProfile.new()
	_profile.suspension_rest_length_m = REST
	_profile.suspension_stiffness_n_m = K
	_profile.suspension_damping_ns_m = C
	_profile.suspension_travel_limit_m = TRAVEL
	_profile.rated_load_kg = RATED_KG


func _contact(distance: float, grounded: bool = true) -> MotiveContact:
	var c := MotiveContact.new()
	c.grounded = grounded
	c.distance_m = distance
	return c


## ===== COMPRESSION =====================================================


func test_compression_is_rest_minus_distance() -> void:
	check_approx(
		SuspensionSolver.compression(_profile, _contact(0.20)),
		0.12,
		"0.32 m rest less a 0.20 m probe is 0.12 m of travel consumed"
	)


func test_compression_floors_at_zero_beyond_rest() -> void:
	check_approx(
		SuspensionSolver.compression(_profile, _contact(0.40)),
		0.0,
		"a probe hanging past its rest length carries no load"
	)


func test_compression_clamps_at_the_travel_limit() -> void:
	check_approx(
		SuspensionSolver.compression(_profile, _contact(0.02)),
		TRAVEL,
		"0.30 m of demand against a 0.24 m limit bottoms out at the limit"
	)


## An airborne Motive Assembly must contribute nothing rather than pulling the
## chassis down, which is what an unguarded rest-minus-distance would do.
func test_an_ungrounded_probe_has_no_compression() -> void:
	check_approx(
		SuspensionSolver.compression(_profile, _contact(0.05, false)),
		0.0,
		"a probe that found nothing is not compressed, whatever its stale distance"
	)


func test_compression_rate_differentiates_the_stored_value() -> void:
	var c := _contact(0.20)
	c.prev_compression_m = 0.10
	check_approx(
		SuspensionSolver.compression_rate(c, 0.12, SyndicateConstants.PHYSICS_DT),
		1.2,
		"0.02 m over one 60 Hz tick is 1.2 m/s"
	)


## ===== DROOP (§16.1) ===================================================


func test_droop_is_the_travel_the_spring_has_not_used() -> void:
	# 0.32 m rest less a 0.20 m probe is 0.12 m consumed, so 0.12 m of the
	# 0.24 m travel is left and the wheel hangs by that much.
	check_approx(
		SuspensionSolver.droop_m(_profile, _contact(0.20)),
		0.12,
		"half the travel consumed leaves half of it hanging"
	)


func test_a_bottomed_out_contact_is_drawn_in_its_placed_cell() -> void:
	# The far end of the range, and the one a sign error cannot reach: a wheel
	# pressed into its stops has no extension left to show.
	check_approx(
		SuspensionSolver.droop_m(_profile, _contact(0.02)),
		0.0,
		"a probe past the travel limit draws the part where it was placed"
	)


func test_an_ungrounded_contact_hangs_at_full_droop() -> void:
	# The behaviour §16.1 exists for. A wheel over a crest finds nothing, reads
	# zero compression, and extends — where the old code drew it at its cell and
	# left it hanging in the air above the ground it had just left.
	check_approx(
		SuspensionSolver.droop_m(_profile, _contact(0.05, false)),
		TRAVEL,
		"a probe that found nothing extends the whole travel"
	)


func test_droop_and_compression_always_sum_to_the_travel() -> void:
	# The invariant the definition is, stated across the whole range rather than
	# at the two ends: what is drawn plus what is carried is the strut, always.
	# A droop derived from the contact point instead would satisfy this only
	# where the authored rest length happens to equal radius plus travel.
	for step: int in 9:
		var distance := 0.02 + 0.05 * float(step)
		var c := _contact(distance)
		check_approx(
			SuspensionSolver.droop_m(_profile, c) + SuspensionSolver.compression(_profile, c),
			TRAVEL,
			"at a %.2f m probe distance" % distance
		)


## ===== FORCE ===========================================================


func test_static_force_is_the_spring_alone() -> void:
	check_approx(
		SuspensionSolver.force(K, C, TRAVEL, 0.12, 0.0, 1.0, MOVING),
		5040.0,
		"42000 N/m times 0.12 m is 5040 N with no rate"
	)


## Compression and rebound must produce different answers, or REBOUND_DAMP_RATIO
## is not load-bearing and could be deleted without a test noticing.
func test_rebound_is_damped_less_than_compression() -> void:
	var compressing := SuspensionSolver.force(K, C, TRAVEL, 0.12, 0.5, 1.0, MOVING)
	var rebounding := SuspensionSolver.force(K, C, TRAVEL, 0.12, -0.5, 1.0, MOVING)
	check_approx(compressing, 5040.0 + 3400.0 * 0.5, "compression uses the full damper")
	check_approx(
		rebounding,
		5040.0 - 3400.0 * SuspensionSolver.REBOUND_DAMP_RATIO * 0.5,
		"rebound uses 0.65 of it"
	)
	check_true(
		compressing - 5040.0 > 5040.0 - rebounding,
		"the compression term is larger in magnitude than the rebound term"
	)


func test_force_never_pulls() -> void:
	check_approx(
		SuspensionSolver.force(K, C, TRAVEL, 0.0, -2.0, 1.0, MOVING),
		0.0,
		"a fully extended probe rebounding hard still pushes nothing; §11 invariant 6"
	)


func test_force_clamps_at_the_bottom_out_limit() -> void:
	check_approx(
		SuspensionSolver.force(K, C, TRAVEL, TRAVEL, 100.0, 1.0, MOVING),
		K * TRAVEL * SuspensionSolver.BOTTOM_OUT_MULT,
		"a violent compression is capped at 3.2 times the full-travel force"
	)


func test_the_settle_scale_applies_only_below_the_threshold() -> void:
	var settled := SuspensionSolver.force(K, C, TRAVEL, 0.12, 0.5, 1.0, 0.01)
	var moving := SuspensionSolver.force(K, C, TRAVEL, 0.12, 0.5, 1.0, MOVING)
	check_approx(
		settled,
		5040.0 + 3400.0 * SuspensionSolver.SETTLE_DAMP_SCALE * 0.5,
		"below 0.05 m/s the damper is scaled to 0.4"
	)
	check_ne(settled, moving, "and the two states must not agree, or the scale does nothing")


## The band multiplier reaches the force through the damper, not the spring: a
## CRITICAL Motive Assembly wallows, it does not sag.
func test_the_damp_multiplier_scales_only_the_damper() -> void:
	var critical := DegradationTable.MOTIVE_SUSP_DAMP[PartEnums.IntegrityBand.CRITICAL]
	check_approx(
		SuspensionSolver.force(K, C, TRAVEL, 0.12, 0.5, critical, MOVING),
		5040.0 + 3400.0 * 0.60 * 0.5,
		"CRITICAL damping is 0.60 of nominal"
	)
	check_approx(
		SuspensionSolver.force(K, C, TRAVEL, 0.12, 0.0, critical, MOVING),
		5040.0,
		"with no rate the multiplier changes nothing, because the spring is untouched"
	)


## ===== RETUNE ==========================================================


func test_retune_at_the_rated_load_leaves_the_spring_alone() -> void:
	var rated_n := RATED_KG * SyndicateConstants.GRAVITY_MPS2
	var tuned := SuspensionSolver.retune(_profile, rated_n)
	check_approx(tuned.x, K, "a contact carrying exactly its rating scales by 1.0")
	# c = 2 * 0.42 * sqrt(42000 * 620)
	check_approx(
		tuned.y,
		2.0 * SuspensionSolver.DAMPING_RATIO * sqrt(K * RATED_KG),
		"the damper follows from critical damping against the corner mass",
		0.01
	)


func test_retune_clamps_the_spring_scale_both_ways() -> void:
	check_approx(
		SuspensionSolver.retune(_profile, 0.0).x,
		K * SuspensionSolver.SPRING_SCALE_MIN,
		"an unloaded contact floors at 0.55"
	)
	check_approx(
		SuspensionSolver.retune(_profile, 1.0e6).x,
		K * SuspensionSolver.SPRING_SCALE_MAX,
		"a grossly overloaded contact caps at 2.40"
	)


## A heavier build must get a stiffer spring, or the whole point of retuning —
## that a heavy Assembly does not sit on its bump stops — is absent.
func test_a_heavier_load_gets_a_stiffer_spring() -> void:
	var rated_n := RATED_KG * SyndicateConstants.GRAVITY_MPS2
	check_true(
		SuspensionSolver.retune(_profile, rated_n * 1.5).x
		> SuspensionSolver.retune(_profile, rated_n).x,
		"1.5 times the rated load gets a stiffer effective spring"
	)


## ===== ANTI-ROLL AND PAIRING ===========================================


func test_anti_roll_follows_the_compression_difference() -> void:
	check_approx(
		SuspensionSolver.anti_roll_force(K, 0.10, 0.04, SuspensionSolver.ANTI_ROLL_RATIO),
		K * SuspensionSolver.ANTI_ROLL_RATIO * 0.06,
		"0.22 of the spring rate across a 0.06 m difference"
	)
	check_approx(
		SuspensionSolver.anti_roll_force(K, 0.07, 0.07, SuspensionSolver.ANTI_ROLL_RATIO),
		0.0,
		"an even pair produces no roll couple"
	)


func test_axle_pairing_needs_both_proximity_and_opposite_sides() -> void:
	check_true(
		SuspensionSolver.is_axle_pair(Vector3(-0.8, 0, 1.0), Vector3(0.8, 0, 1.1)),
		"close in Z and on opposite sides is a pair"
	)
	check_false(
		SuspensionSolver.is_axle_pair(Vector3(-0.8, 0, 1.0), Vector3(0.8, 0, 2.0)),
		"a metre apart longitudinally is not one axle"
	)
	check_false(
		SuspensionSolver.is_axle_pair(Vector3(-0.8, 0, 1.0), Vector3(-0.6, 0, 1.0)),
		"two probes on the same side have no roll couple between them"
	)
	check_false(
		SuspensionSolver.is_axle_pair(Vector3(0.0, 0, 1.0), Vector3(0.8, 0, 1.0)),
		"a probe on the centreline pairs with nothing"
	)
