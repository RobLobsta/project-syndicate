extends TestCase
## [DamageResolver]'s pure statics, asserted against the constant tables
## published in [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code] §4 to §8.
##
## The document's figures are written out here by hand rather than imported from
## the class under test. A test that reads the same constant its subject reads
## asserts nothing — change the constant and the expectation moves with it — so
## §4 is the owner, this file is where the code is checked against §4, and
## [code]tests/physics/test_duel.gd[/code] is where the whole chain is checked
## against two Assemblies actually shooting at each other.

## §4's table, quoted.
const DOC_COS_FLOOR: float = 0.20
const DOC_RICOCHET_COS: float = 0.309
const DOC_RICOCHET_PEN_FACTOR: float = 1.15
const DOC_PEN_DEFEAT: float = 0.55
const DOC_PEN_PARTIAL_SCALE: float = 0.42
const DOC_PEN_SURPLUS_GAIN: float = 0.30
const DOC_PEN_SURPLUS_CAP: float = 1.5
const DOC_OVERPEN_RATIO: float = 1.85
const DOC_BLAST_EXPONENT: float = 1.85
const DOC_IMPACT_K: float = 2.4
const DOC_IMPACT_THRESHOLD_MPS: float = 3.5
const DOC_IMPACT_EXPONENT: float = 1.15
const DOC_IMPACT_MAX_PER_CONTACT: float = 900.0
const DOC_MAX_CHAIN_DEPTH: int = 3


func test_the_published_constants_are_what_the_document_says() -> void:
	check_approx(DamageResolver.COS_FLOOR, DOC_COS_FLOOR, "COS_FLOOR")
	check_approx(DamageResolver.RICOCHET_COS, DOC_RICOCHET_COS, "RICOCHET_COS")
	check_approx(
		DamageResolver.RICOCHET_PEN_FACTOR, DOC_RICOCHET_PEN_FACTOR, "RICOCHET_PEN_FACTOR"
	)
	check_approx(DamageResolver.PEN_DEFEAT, DOC_PEN_DEFEAT, "PEN_DEFEAT")
	check_approx(DamageResolver.PEN_PARTIAL_SCALE, DOC_PEN_PARTIAL_SCALE, "PEN_PARTIAL_SCALE")
	check_approx(DamageResolver.PEN_SURPLUS_GAIN, DOC_PEN_SURPLUS_GAIN, "PEN_SURPLUS_GAIN")
	check_approx(DamageResolver.PEN_SURPLUS_CAP, DOC_PEN_SURPLUS_CAP, "PEN_SURPLUS_CAP")
	check_approx(DamageResolver.OVERPEN_RATIO, DOC_OVERPEN_RATIO, "OVERPEN_RATIO")
	check_approx(DamageResolver.BLAST_EXPONENT, DOC_BLAST_EXPONENT, "BLAST_EXPONENT")
	check_approx(DamageResolver.IMPACT_K, DOC_IMPACT_K, "IMPACT_K")
	check_approx(
		DamageResolver.IMPACT_THRESHOLD_MPS, DOC_IMPACT_THRESHOLD_MPS, "IMPACT_THRESHOLD_MPS"
	)
	check_approx(DamageResolver.IMPACT_EXPONENT, DOC_IMPACT_EXPONENT, "IMPACT_EXPONENT")
	check_eq(DamageResolver.MAX_CHAIN_DEPTH, DOC_MAX_CHAIN_DEPTH, "MAX_CHAIN_DEPTH (I-12)")


## ===== ANGLE OF INCIDENCE (§4.1) =======================================


func test_a_square_hit_sees_the_armour_as_authored() -> void:
	check_approx(
		DamageResolver.effective_armour(40.0, 1.0), 40.0, "cos(0) is 1 and 40 armour is 40"
	)


func test_a_sloped_hit_sees_more_armour() -> void:
	# 60 degrees of slope: cos is 0.5, so the round traverses twice the material.
	check_approx(
		DamageResolver.effective_armour(40.0, 0.5), 80.0, "a 60-degree slope doubles it"
	)


func test_the_slope_benefit_is_capped_at_five_times() -> void:
	# Without the floor a grazing hit produces unbounded effective armour and a
	# mathematically guaranteed ricochet, which reads to a player as broken.
	check_approx(
		DamageResolver.effective_armour(40.0, 0.0),
		40.0 / DOC_COS_FLOOR,
		"a perfectly grazing hit is capped at five times, not infinity"
	)
	check_approx(
		DamageResolver.effective_armour(40.0, 0.01),
		DamageResolver.effective_armour(40.0, 0.0),
		"and anything under the floor gets the same treatment"
	)


## ===== THE PENETRATION CURVE (§4.3) ====================================


func test_a_round_under_the_defeat_ratio_does_nothing() -> void:
	# 0.55 of the effective armour. Below it the round is stopped outright, and
	# the gap between "my gun works" and "it doesn't" is the point of the curve.
	check_approx(
		DamageResolver.kinetic_multiplier(40.0 * 0.54, 40.0, 1.0),
		0.0,
		"just under the threshold is nothing at all"
	)


func test_the_partial_band_ramps_quadratically() -> void:
	# Halfway between defeat and full: t = 0.5, so 0.42 x 0.25 = 0.105. A linear
	# ramp would give 0.21 here, which is the difference the quadratic makes and
	# is what stops the region under the threshold being quietly usable.
	var rho := DOC_PEN_DEFEAT + (1.0 - DOC_PEN_DEFEAT) * 0.5
	check_approx(
		DamageResolver.kinetic_multiplier(40.0 * rho, 40.0, 1.0),
		DOC_PEN_PARTIAL_SCALE * 0.25,
		"halfway through the partial band is a quarter of its scale, not half"
	)
	check_approx(
		DamageResolver.kinetic_multiplier(40.0 * 0.999, 40.0, 1.0),
		DOC_PEN_PARTIAL_SCALE,
		"and the top of the band reaches the scale itself",
		0.01
	)


func test_full_penetration_is_full_damage_and_surplus_pays_a_bonus() -> void:
	check_approx(
		DamageResolver.kinetic_multiplier(40.0, 40.0, 1.0), 1.0, "exactly enough is exactly full"
	)
	check_approx(
		DamageResolver.kinetic_multiplier(80.0, 40.0, 1.0),
		1.0 + DOC_PEN_SURPLUS_GAIN * 1.0,
		"twice the armour pays a 30% bonus"
	)


func test_the_surplus_bonus_is_capped() -> void:
	# Otherwise a heavy round against an unarmoured part scales without bound,
	# and the cheapest way to kill anything becomes shooting the weakest thing.
	var capped := 1.0 + DOC_PEN_SURPLUS_GAIN * DOC_PEN_SURPLUS_CAP
	check_approx(
		DamageResolver.kinetic_multiplier(4000.0, 40.0, 1.0), capped, "a hundredfold is capped"
	)
	check_approx(
		DamageResolver.kinetic_multiplier(40.0 * 2.5, 40.0, 1.0),
		capped,
		"and the cap is reached at 2.5x, exactly where §4.3 puts it"
	)


func test_a_slope_can_defeat_a_round_that_would_penetrate_square_on() -> void:
	# The behaviour §4.1 exists to produce, and the reason a wedge is worth mass.
	check_true(
		DamageResolver.kinetic_multiplier(45.0, 40.0, 1.0) > 0.0, "square on, it goes through"
	)
	check_approx(
		DamageResolver.kinetic_multiplier(45.0, 40.0, 0.25),
		0.0,
		"at 75 degrees of slope, the same round is defeated"
	)


## ===== RICOCHET AND OVERPENETRATION (§4.2, §4.4) =======================


func test_a_steep_oblique_hit_with_a_weak_round_deflects() -> void:
	var shallow := DOC_RICOCHET_COS * 0.5
	check_true(
		DamageResolver.is_ricochet(10.0, 40.0, shallow), "past 72 degrees a weak round deflects"
	)


func test_a_strong_round_defeats_the_angle_rather_than_deflecting() -> void:
	# The pen factor is what stops sloped armour being an absolute defence: bring
	# enough gun and the angle stops mattering.
	var shallow := DOC_RICOCHET_COS * 0.5
	var armour_seen := DamageResolver.effective_armour(40.0, shallow)
	check_false(
		DamageResolver.is_ricochet(armour_seen * DOC_RICOCHET_PEN_FACTOR * 1.01, 40.0, shallow),
		"a round over 1.15x the effective armour goes in rather than bouncing"
	)


func test_a_square_hit_never_ricochets_however_weak() -> void:
	check_false(
		DamageResolver.is_ricochet(1.0, 4000.0, 1.0),
		"the angle gate comes first: a square hit is stopped, not deflected"
	)


func test_overpenetration_starts_where_the_document_puts_it() -> void:
	check_false(
		DamageResolver.is_overpenetration(40.0 * (DOC_OVERPEN_RATIO - 0.01), 40.0, 1.0),
		"just under 1.85 the round stays in"
	)
	check_true(
		DamageResolver.is_overpenetration(40.0 * DOC_OVERPEN_RATIO, 40.0, 1.0),
		"and at 1.85 it passes through"
	)


func test_a_slope_can_stop_a_round_overpenetrating() -> void:
	# Same round, same plate, steeper angle: it still goes in but no longer comes
	# out the other side, so nothing behind it is spalled.
	check_true(DamageResolver.is_overpenetration(80.0, 40.0, 1.0), "square on, it passes through")
	check_false(
		DamageResolver.is_overpenetration(80.0, 40.0, 0.5), "at 60 degrees it stays in the plate"
	)


## ===== BLAST FALLOFF (§5.1) ============================================


func test_blast_is_full_at_the_epicentre_and_nothing_at_the_edge() -> void:
	check_approx(DamageResolver.blast_falloff(0.0, 6.0), 1.0, "everything at the centre")
	check_approx(DamageResolver.blast_falloff(6.0, 6.0), 0.0, "and nothing at the radius")
	check_approx(DamageResolver.blast_falloff(9.0, 6.0), 0.0, "or beyond it")


func test_the_falloff_exponent_concentrates_damage_near_the_centre() -> void:
	# Halfway out, an exponent of 1.85 gives 0.278 where a linear falloff would
	# give 0.5. That is what rewards placing ordnance accurately over lobbing it
	# in the general direction of a target.
	check_approx(
		DamageResolver.blast_falloff(3.0, 6.0),
		pow(0.5, DOC_BLAST_EXPONENT),
		"halfway out is well under half the damage"
	)
	check_true(
		DamageResolver.blast_falloff(3.0, 6.0) < 0.5, "which is the whole point of the exponent"
	)


func test_a_blast_with_no_radius_does_nothing() -> void:
	check_approx(DamageResolver.blast_falloff(0.0, 0.0), 0.0, "no radius is no blast")


## ===== IMPACT (§6.1) ===================================================


func test_a_gentle_contact_does_no_damage() -> void:
	# The threshold is essential: without it an Assembly resting on the ground
	# takes continuous micro-damage from contact resolution noise, forever.
	var m := 1000.0
	var impulse := DOC_IMPACT_THRESHOLD_MPS * 0.9 * (m * 1.0e9) / (m + 1.0e9)
	check_approx(
		DamageResolver.impact_damage(impulse, m, 1.0e9),
		0.0,
		"under 3.5 m/s of effective closing speed, nothing happens"
	)


func test_impact_damage_follows_the_documented_curve() -> void:
	# A 1000 kg body against a static one: the reduced mass is the body's own, so
	# v_eff is impulse over mass. 10 m/s of it is 6.5 past the threshold.
	var m := 1000.0
	var v_eff := 10.0
	var impulse := v_eff * (m * 1.0e9) / (m + 1.0e9)
	check_approx(
		DamageResolver.impact_damage(impulse, m, 1.0e9),
		DOC_IMPACT_K * pow(v_eff - DOC_IMPACT_THRESHOLD_MPS, DOC_IMPACT_EXPONENT),
		"the curve is taken on the excess over the threshold, not on the speed",
		0.01
	)


func test_impact_damage_is_capped_per_contact() -> void:
	check_approx(
		DamageResolver.impact_damage(1.0e7, 1000.0, 1.0e9),
		DOC_IMPACT_MAX_PER_CONTACT,
		"one contact may not exceed the per-contact ceiling"
	)


func test_a_light_body_hitting_a_heavy_one_is_the_one_that_suffers() -> void:
	# The reduced mass is what makes ramming asymmetric. The same impulse against
	# a much heavier body produces a far larger effective speed for the light one.
	var impulse := 8000.0
	check_true(
		DamageResolver.impact_damage(impulse, 400.0, 1.0e9)
		> DamageResolver.impact_damage(impulse, 4000.0, 1.0e9),
		"the same impulse hurts the lighter body more"
	)


## ===== BANDS (§8.1) ====================================================


func test_the_band_thresholds_are_where_the_document_puts_them() -> void:
	check_eq(
		DamageResolver.band_for(1.0), PartEnums.IntegrityBand.NOMINAL, "full integrity is NOMINAL"
	)
	check_eq(
		DamageResolver.band_for(0.76),
		PartEnums.IntegrityBand.NOMINAL,
		"and so is anything at or above 75%"
	)
	check_eq(
		DamageResolver.band_for(0.74), PartEnums.IntegrityBand.STRESSED, "under 75% is STRESSED"
	)
	check_eq(
		DamageResolver.band_for(0.49),
		PartEnums.IntegrityBand.IMPAIRED,
		"under 50% is IMPAIRED — the mandated Motive Assembly behaviour"
	)
	check_eq(
		DamageResolver.band_for(0.29),
		PartEnums.IntegrityBand.CRITICAL,
		"under 30% is CRITICAL — the mandated Effector Module behaviour"
	)
	check_eq(
		DamageResolver.band_for(0.0), PartEnums.IntegrityBand.DESTROYED, "and zero is DESTROYED"
	)


func test_the_boundaries_belong_to_the_healthier_band() -> void:
	# Exactly at a threshold the part is not yet in the worse band. Getting this
	# backwards makes a part that has taken no damage at all read as STRESSED at
	# a fraction of 0.75, which is every fresh part on a build with a 75% start.
	check_eq(
		DamageResolver.band_for(SyndicateConstants.BAND_STRESSED),
		PartEnums.IntegrityBand.NOMINAL,
		"exactly 75% is still NOMINAL"
	)
	check_eq(
		DamageResolver.band_for(SyndicateConstants.BAND_IMPAIRED),
		PartEnums.IntegrityBand.STRESSED,
		"exactly 50% is still STRESSED"
	)
	check_eq(
		DamageResolver.band_for(SyndicateConstants.BAND_CRITICAL),
		PartEnums.IntegrityBand.IMPAIRED,
		"and exactly 30% is still IMPAIRED"
	)
