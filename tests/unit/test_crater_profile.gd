extends TestCase
## [CraterProfile] against the tables published in
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §3.
##
## Every published value is written out here by hand rather than imported from
## the class under test. A test that reads the same constant its subject reads
## asserts nothing: change the constant and the expectation moves with it.

## §3.1's table, quoted.
const DOC_CRATER_RADIUS_FACTOR: float = 1.35
const DOC_RIM_RATIO: float = 0.28
const DOC_RIM_BOUNDARY: float = 0.68
const DOC_BOWL_EXPONENT: float = 0.85

## §3.2's table, quoted.
const DOC_CRATER_DEPTH_K: float = 0.62
const DOC_CRATER_ENERGY_REF: float = 400.0
const DOC_CRATER_MAX_DEPTH_M: float = 3.4

## §3.3's amended table, quoted. These are the integrals of the shape function,
## as coefficients of 2*PI*R^2*D.
const DOC_BOWL_COEFFICIENT: float = 0.124973
const DOC_RIM_INTEGRAL: float = 0.171123
const DOC_EJECTA_FRACTION: float = 0.3834
const DOC_RIM_RATIO_FOR_VOLUME_MATCH: float = 0.730309

## §7.1's worked example, quoted: a typical 1.4 m crater has a 0.39 m rim.
const DOC_TYPICAL_DEPTH_M: float = 1.4
const DOC_TYPICAL_RIM_HEIGHT_M: float = 0.39


func test_the_published_constants_are_what_the_document_says() -> void:
	check_approx(
		CraterProfile.CRATER_RADIUS_FACTOR, DOC_CRATER_RADIUS_FACTOR, "CRATER_RADIUS_FACTOR"
	)
	check_approx(CraterProfile.RIM_RATIO, DOC_RIM_RATIO, "RIM_RATIO")
	check_approx(CraterProfile.RIM_BOUNDARY, DOC_RIM_BOUNDARY, "RIM_BOUNDARY")
	check_approx(CraterProfile.BOWL_EXPONENT, DOC_BOWL_EXPONENT, "BOWL_EXPONENT")
	check_approx(CraterProfile.CRATER_DEPTH_K, DOC_CRATER_DEPTH_K, "CRATER_DEPTH_K")
	check_approx(CraterProfile.CRATER_ENERGY_REF, DOC_CRATER_ENERGY_REF, "CRATER_ENERGY_REF")
	check_approx(CraterProfile.CRATER_MAX_DEPTH_M, DOC_CRATER_MAX_DEPTH_M, "CRATER_MAX_DEPTH_M")


## §3.1. The profile is continuous at both boundaries, which is what stops a
## crater reading as a stamped hole. Asserted from both sides of each boundary
## rather than at it, because evaluating exactly at the boundary takes one
## branch and says nothing about the other.
func test_the_profile_is_continuous_at_the_bowl_rim_boundary() -> void:
	var depth := 2.0
	var eps := 1e-6
	var below := CraterProfile.delta_height(DOC_RIM_BOUNDARY - eps, depth)
	var above := CraterProfile.delta_height(DOC_RIM_BOUNDARY + eps, depth)
	check_approx(below, 0.0, "bowl term reaches zero at u_r", 1e-4)
	check_approx(above, 0.0, "rim term starts at zero at u_r", 1e-4)
	check_approx(below, above, "profile is C0 at u_r", 1e-4)


func test_the_profile_is_continuous_at_the_crater_edge() -> void:
	var depth := 2.0
	var inside := CraterProfile.delta_height(1.0 - 1e-6, depth)
	var outside := CraterProfile.delta_height(1.0 + 1e-6, depth)
	check_approx(outside, 0.0, "nothing happens outside the crater")
	check_approx(inside, 0.0, "profile is C0 at u = 1", 1e-4)


## The bowl is below datum and the rim is above it. A sign error here would
## produce a mound where the shell landed, which no continuity check would
## notice because both boundaries are still zero.
func test_the_bowl_digs_down_and_the_rim_stands_up() -> void:
	var depth := 2.0
	check_true(
		CraterProfile.delta_height(0.0, depth) < 0.0, "crater centre is below datum"
	)
	check_approx(
		CraterProfile.delta_height(0.0, depth), -depth, "crater centre is exactly one depth down"
	)
	var rim_peak := (DOC_RIM_BOUNDARY + 1.0) * 0.5
	check_true(CraterProfile.delta_height(rim_peak, depth) > 0.0, "rim is above datum")


## §3.1: the rim's peak is RIM_RATIO of the depth, and it sits at the midpoint
## of the annulus because sin peaks at PI/2.
func test_the_rim_peaks_at_the_documented_fraction_of_depth() -> void:
	var depth := DOC_TYPICAL_DEPTH_M
	var rim_peak_u := (DOC_RIM_BOUNDARY + 1.0) * 0.5
	var h := CraterProfile.delta_height(rim_peak_u, depth)
	check_approx(h, depth * DOC_RIM_RATIO, "rim peak is RIM_RATIO * depth", 1e-4)
	# §7.1's worked number, which is what makes the rim a lip rather than a wall.
	check_approx(h, DOC_TYPICAL_RIM_HEIGHT_M, "§7.1's 0.39 m rim on a 1.4 m crater", 0.005)


## §3.2. Depth scales with the cube root of blast energy: doubling the charge
## does not double the hole.
func test_depth_follows_the_cube_root_energy_law() -> void:
	var at_ref := CraterProfile.depth_for(DOC_CRATER_ENERGY_REF, 1.0)
	check_approx(at_ref, DOC_CRATER_DEPTH_K, "at the reference energy, depth is K")

	var at_eight := CraterProfile.depth_for(DOC_CRATER_ENERGY_REF * 8.0, 1.0)
	check_approx(at_eight, DOC_CRATER_DEPTH_K * 2.0, "eight times the energy doubles the depth")

	var at_eighth := CraterProfile.depth_for(DOC_CRATER_ENERGY_REF / 8.0, 1.0)
	check_approx(at_eighth, DOC_CRATER_DEPTH_K * 0.5, "an eighth of the energy halves it")


func test_hardness_divides_depth_and_the_maximum_clamps() -> void:
	var soft := CraterProfile.depth_for(DOC_CRATER_ENERGY_REF, 0.5)
	check_approx(soft, DOC_CRATER_DEPTH_K / 0.5, "soft ground digs deeper")
	var hard := CraterProfile.depth_for(DOC_CRATER_ENERGY_REF, 3.2)
	check_approx(hard, DOC_CRATER_DEPTH_K / 3.2, "hard ground barely craters")
	# A colossal blast on the softest legal ground still cannot exceed the cap.
	var huge := CraterProfile.depth_for(400000.0, 0.15)
	check_approx(huge, DOC_CRATER_MAX_DEPTH_M, "depth clamps at CRATER_MAX_DEPTH_M")


func test_the_crater_is_wider_than_its_blast() -> void:
	check_approx(
		CraterProfile.radius_for(4.0),
		4.0 * DOC_CRATER_RADIUS_FACTOR,
		"crater radius is the blast radius times the factor"
	)


## §3.3, as amended. The rim deliberately does NOT conserve volume, and this is
## the assertion that makes changing any of the three shape constants a decision
## rather than an accident.
func test_the_ejecta_fraction_is_the_documented_one() -> void:
	check_approx(
		CraterProfile.bowl_volume_coefficient(),
		DOC_BOWL_COEFFICIENT,
		"§3.3's bowl integral",
		1e-4
	)
	check_approx(
		CraterProfile.rim_volume_coefficient(), DOC_RIM_INTEGRAL, "§3.3's rim integral", 1e-4
	)
	var ejecta := CraterProfile.rim_volume_coefficient() * DOC_RIM_RATIO
	var fraction := ejecta / CraterProfile.bowl_volume_coefficient()
	check_approx(fraction, DOC_EJECTA_FRACTION, "§3.3's ejecta fraction", 1e-3)
	check_true(fraction < 1.0, "the rim holds less than the bowl gave up")


## The conserving ratio is computed rather than asserted in prose, so that
## anyone changing RIM_BOUNDARY or BOWL_EXPONENT is told the new number.
##
## Shipping it would put a 1.02 m wall around a typical crater, which §3.3
## refuses on gameplay grounds — so this asserts the value AND that it is not
## what the profile uses.
func test_the_volume_matching_ratio_is_known_and_deliberately_not_shipped() -> void:
	check_approx(
		CraterProfile.rim_ratio_for_volume_match(),
		DOC_RIM_RATIO_FOR_VOLUME_MATCH,
		"the ratio that would conserve volume",
		1e-3
	)
	check_true(
		CraterProfile.RIM_RATIO < CraterProfile.rim_ratio_for_volume_match(),
		"the shipped rim is deliberately lower than the conserving one"
	)
	var conserving_rim := DOC_TYPICAL_DEPTH_M * DOC_RIM_RATIO_FOR_VOLUME_MATCH
	check_true(
		conserving_rim > 1.0,
		"a conserving rim on a typical crater exceeds a metre, which is the wall §3.3 refuses"
	)


## The bowl is monotonic outward and the rim rises then falls. A profile that
## wobbled would put a ridge inside the bowl for a suspension probe to catch on,
## and no boundary assertion would see it.
func test_the_bowl_shallows_monotonically_toward_the_rim() -> void:
	var depth := 2.0
	var previous := CraterProfile.delta_height(0.0, depth)
	var steps := 60
	for i: int in range(1, steps + 1):
		var u := DOC_RIM_BOUNDARY * float(i) / float(steps)
		var h := CraterProfile.delta_height(u, depth)
		if not check_true(h >= previous - 1e-6, "bowl shallows outward at u=%.3f" % u):
			return
		previous = h
