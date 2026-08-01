class_name MotiveContact
extends RefCounted
## One ground contact belonging to a Motive Assembly, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §6 and §7.
##
## A GROUND or AMBULATORY Motive Assembly has exactly one. A TRACKED one has
## [member TrackProfile.road_stations] of them, distinguished by
## [member station_index]. A ROTARY one has none at all — a disc touches
## nothing, which is why §12 is the cheapest family per tick.
##
## Populated from the probe sweep on the main thread and then read by the pure
## solvers, which is the seam that keeps every formula in this layer testable
## without a physics space: a test constructs contacts directly and asserts an
## exact force.

var slot: int = SyndicateConstants.INVALID_SLOT
## Road station along a tracked patch, fore to aft. Always 0 for the families
## that carry one contact.
var station_index: int = 0

## ===== PROBE RESULT ====================================================

var grounded: bool = false
## Distance from the probe origin to the contact, in metres. Compared against
## the suspension rest length to give compression.
var distance_m: float = 0.0
var point_world: Vector3 = Vector3.ZERO
var normal_world: Vector3 = Vector3.UP
## Index into [code]SurfaceTable[/code]; sets the friction multiplier.
var surface_id: int = 0

## ===== KINEMATICS ======================================================

## Velocity of the contact point in world space, including the chassis's
## angular contribution. The quantity slip is measured from.
var velocity_world: Vector3 = Vector3.ZERO
## Rolling direction in world space.
var forward: Vector3 = Vector3.FORWARD
## Lateral direction in world space, orthogonal to [member forward] and the
## contact normal.
var lateral: Vector3 = Vector3.RIGHT
## Angular rate of this contact, in rad/s. Integrated by the traction solver;
## the reason slip ratio is a meaningful quantity rather than a fiction.
var contact_omega: float = 0.0

## ===== SOLVER STATE ====================================================

## Compression consumed last tick, in metres. The damper term differentiates it.
var prev_compression_m: float = 0.0
## Normal force from the suspension solve, in newtons. Written by
## [SuspensionSolver] and read by [TractionSolver] in the same tick, which is
## the one ordering dependency between the two.
var normal_force_n: float = 0.0


## Resets the per-tick probe fields without disturbing the state the solvers
## carry between ticks.
##
## [member prev_compression_m] and [member contact_omega] are deliberately not
## cleared: both are integrated across ticks, and clearing either here would
## silently zero the damper term and the slip ratio on every contact, every
## tick — which reads as a suspension with no damping and a wheel that never
## spins up, neither of which announces itself.
func clear_probe() -> void:
	grounded = false
	distance_m = 0.0
	point_world = Vector3.ZERO
	normal_world = Vector3.UP
	surface_id = 0
	normal_force_n = 0.0
