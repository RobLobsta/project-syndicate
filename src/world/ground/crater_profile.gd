class_name CraterProfile
extends RefCounted
## The crater shape function and its depth law, owned by
## [code]docs/TERRAIN_CRATER_DEFORMER.md[/code] §3.
##
## A crater is not a hemisphere. Real explosive cratering produces a bowl with a
## raised rim of ejecta, and the rim is what makes a crater read as a crater
## rather than a dent. In normalised radius [code]u = d / R[/code]:
## [codeblock]
##            -D * (1 - (u/u_r)^2)^p           u <  u_r    bowl
## dh(u)   =   H * sin(PI * (u - u_r)/(1 - u_r))  u_r <= u <= 1  rim
##             0                                u >  1      outside
## [/codeblock]
##
## Every constant here is §3's, by value. Nothing else in the project may
## restate them.

## Crater outer radius as a multiple of the blast radius.
const CRATER_RADIUS_FACTOR: float = 1.35

## Rim height as a fraction of bowl depth. Chosen so ejecta volume matches
## excavated volume — see [method rim_ratio_for_volume_match].
const RIM_RATIO: float = 0.28

## Normalised radius at which the bowl ends and the rim begins.
const RIM_BOUNDARY: float = 0.68

## Bowl sharpness exponent.
const BOWL_EXPONENT: float = 0.85

## ===== DEPTH LAW (§3.2) ================================================

const CRATER_DEPTH_K: float = 0.62
const CRATER_ENERGY_REF: float = 400.0
const CRATER_MAX_DEPTH_M: float = 3.4

## Floor on the hardness divisor, so a malformed surface entry cannot produce an
## unbounded depth before [constant CRATER_MAX_DEPTH_M] clamps it.
const MIN_HARDNESS: float = 0.15

## Samples used by the volume integrals in [method bowl_volume_coefficient] and
## [method rim_volume_coefficient]. Midpoint rule; 4096 puts both coefficients
## well inside the 1e-5 the continuity assertions use.
const VOLUME_INTEGRATION_SAMPLES: int = 4096


## Height change at normalised radius [param u] for a crater of [param depth].
##
## Continuous at both boundaries: the bowl term reaches zero at
## [constant RIM_BOUNDARY] because [code]1 - (u/u_r)^2[/code] does, and the rim
## term is [code]sin[/code] of a value that is zero at [constant RIM_BOUNDARY]
## and PI at [code]u = 1[/code]. There is therefore no step at the crater edge,
## which is what stops a crater from reading as a stamped hole.
static func delta_height(u: float, depth: float) -> float:
	if u >= 1.0:
		return 0.0
	if u < RIM_BOUNDARY:
		var t := u / RIM_BOUNDARY
		return -depth * pow(maxf(0.0, 1.0 - t * t), BOWL_EXPONENT)
	var s := (u - RIM_BOUNDARY) / (1.0 - RIM_BOUNDARY)
	return depth * RIM_RATIO * sin(PI * s)


## Bowl depth for a blast of [param blast_damage] against ground of
## [param hardness]. §3.2.
##
## Depth scales with the cube root of blast energy, which is the standard
## scaling law for explosive cratering: doubling the charge does not double the
## hole.
static func depth_for(blast_damage: float, hardness: float) -> float:
	var energy := maxf(blast_damage, 1.0) / CRATER_ENERGY_REF
	var d := CRATER_DEPTH_K * pow(energy, 1.0 / 3.0)
	return minf(d / maxf(hardness, MIN_HARDNESS), CRATER_MAX_DEPTH_M)


## Outer radius of the crater a blast of [param blast_radius_m] carves.
static func radius_for(blast_radius_m: float) -> float:
	return blast_radius_m * CRATER_RADIUS_FACTOR


## ===== VOLUME CONSERVATION (§3.3) ======================================
## The rim's ejecta volume should roughly match the bowl's excavated volume, or
## craters look like someone pressed a thumb into clay. Both integrals below are
## expressed as coefficients of [code]2 * PI * R^2 * D[/code], so a match means
## the two coefficients agree.
##
## These are not called at runtime. They exist so the relationship is checkable
## rather than asserted in prose, and so that changing [constant RIM_BOUNDARY]
## or [constant BOWL_EXPONENT] has a mechanical way to re-derive
## [constant RIM_RATIO] rather than a hand-waved one.


## [code]integral of u * (1 - (u/u_r)^2)^p du[/code] over the bowl.
static func bowl_volume_coefficient() -> float:
	var total := 0.0
	var step := RIM_BOUNDARY / float(VOLUME_INTEGRATION_SAMPLES)
	for i: int in VOLUME_INTEGRATION_SAMPLES:
		var u := (float(i) + 0.5) * step
		var t := u / RIM_BOUNDARY
		total += u * pow(maxf(0.0, 1.0 - t * t), BOWL_EXPONENT) * step
	return total


## [code]integral of u * sin(PI * (u - u_r)/(1 - u_r)) du[/code] over the rim,
## excluding [constant RIM_RATIO] so the two coefficients are comparable.
static func rim_volume_coefficient() -> float:
	var total := 0.0
	var span := 1.0 - RIM_BOUNDARY
	var step := span / float(VOLUME_INTEGRATION_SAMPLES)
	for i: int in VOLUME_INTEGRATION_SAMPLES:
		var u := RIM_BOUNDARY + (float(i) + 0.5) * step
		total += u * sin(PI * (u - RIM_BOUNDARY) / span) * step
	return total


## The [constant RIM_RATIO] that would make ejecta volume exactly match
## excavated volume for the current [constant RIM_BOUNDARY] and
## [constant BOWL_EXPONENT].
##
## [code]tests/unit/test_crater_profile.gd[/code] asserts the shipped
## [constant RIM_RATIO] is within tolerance of this. Change either shape
## constant and that assertion tells you the new value to ship.
static func rim_ratio_for_volume_match() -> float:
	var rim := rim_volume_coefficient()
	if is_zero_approx(rim):
		return 0.0
	return bowl_volume_coefficient() / rim
