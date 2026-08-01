class_name AeroSolver
extends RefCounted
## Control Surface aerodynamics and body drag, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §8.
##
## Shares [constant SyndicateConstants.AIR_DENSITY_KG_M3] with [RotorSolver], for
## the reason document 01 §3 gives: an Assembly carrying both a Control Surface
## and a rotor disc must not generate its lift and its drag in two different
## airs.

## Below this speed aerodynamic forces are skipped entirely, which saves the work
## for the majority of contacts and prevents numerical noise at rest.
const MIN_SPEED_MPS: float = 4.0

## Bluff-body drag coefficient for the Assembly as a whole. A boxy, unfaired
## shape; the lattice does not produce anything else.
const BODY_DRAG_CD: float = 0.82

## Steepness of the post-stall lift collapse.
const STALL_FALLOFF: float = 2.2

## Induced-drag growth with angle of attack.
const DRAG_INDUCED_GAIN: float = 2.0


## Dynamic pressure in pascals at [param speed_mps].
static func dynamic_pressure_pa(speed_mps: float) -> float:
	return 0.5 * SyndicateConstants.AIR_DENSITY_KG_M3 * speed_mps * speed_mps


## Lift retention past the stall angle, in [0, 1].
##
## Unity inside the stall angle, falling linearly beyond it and floored at zero.
## A hard cutoff would make a Control Surface stop working between one tick and
## the next, which reads as the Assembly being dropped.
static func stall_factor(angle_rad: float, stall_angle_rad: float) -> float:
	var a := absf(angle_rad)
	if stall_angle_rad <= 0.0:
		return 1.0
	if a <= stall_angle_rad:
		return 1.0
	return maxf(0.0, 1.0 - STALL_FALLOFF * (a - stall_angle_rad) / stall_angle_rad)


## Lift force in newtons, applied along the surface's local -Y.
##
## Negative for a downforce surface, which is the usual case on a ground
## Assembly and why [member ControlSurfaceProfile.lift_coefficient] is authored
## negative.
static func lift_n(
	profile: ControlSurfaceProfile, speed_mps: float, angle_rad: float, band: int
) -> float:
	if speed_mps < MIN_SPEED_MPS:
		return 0.0
	return (
		dynamic_pressure_pa(speed_mps)
		* profile.reference_area_m2
		* profile.lift_coefficient
		* cos(angle_rad)
		* stall_factor(angle_rad, deg_to_rad(profile.stall_angle_deg))
		* DegradationTable.multiplier(DegradationTable.CONTROL_COEFF, band)
	)


## Drag force in newtons, applied along the negative velocity direction.
##
## Grows with the square of the sine of the angle of attack: a surface presented
## edge-on costs almost nothing and one presented flat costs three times its
## nominal drag.
static func drag_n(
	profile: ControlSurfaceProfile, speed_mps: float, angle_rad: float, band: int
) -> float:
	if speed_mps < MIN_SPEED_MPS:
		return 0.0
	var s := sin(angle_rad)
	return (
		dynamic_pressure_pa(speed_mps)
		* profile.reference_area_m2
		* profile.drag_coefficient
		* (1.0 + DRAG_INDUCED_GAIN * s * s)
		* DegradationTable.multiplier(DegradationTable.CONTROL_COEFF, band)
	)


## Bluff-body drag on the Assembly as a whole, in newtons.
##
## Applied at the centre of mass, so it produces no moment. The projected
## frontal area comes from the occupancy lattice and is recomputed on mass
## recompute only.
static func body_drag_n(frontal_area_m2: float, speed_mps: float) -> float:
	if speed_mps < MIN_SPEED_MPS:
		return 0.0
	return dynamic_pressure_pa(speed_mps) * frontal_area_m2 * BODY_DRAG_CD


## Projected frontal area of an occupancy cell set, in square metres.
##
## Collapses the cells onto the XY plane and counts the distinct columns, so a
## deep Assembly presents the same frontal area as a shallow one of the same
## silhouette — which is what frontal area means.
static func frontal_area_m2(cells: PackedVector3Array) -> float:
	var seen := {}
	for c: Vector3 in cells:
		seen[Vector2i(int(c.x), int(c.y))] = true
	var unit := SyndicateConstants.LATTICE_UNIT_M
	return float(seen.size()) * unit * unit
