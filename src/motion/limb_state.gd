class_name LimbState
extends RefCounted
## Per-tick state of one ambulatory Motive Assembly, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §13.2.
##
## One per [constant PartEnums.MotiveKind.AMBULATORY_LIMB] part, in a flat array
## on [MotiveSystem].

var slot: int = SyndicateConstants.INVALID_SLOT

## Position in the gait cycle, [0, 1). In stance while below the profile's
## duty factor.
var phase: float = 0.0
## This limb's offset within the Assembly's shared gait clock. Assigned by
## [method GaitSolver.assign_phase_offsets] once per structural change, never
## per tick.
var phase_offset: float = 0.0
## Hip position in assembly-local space, cached at registration.
##
## Fixed from placement to destruction — the part does not move relative to the
## chassis — so it is resolved once rather than recomposed from the lattice cell
## and orientation basis on every phase assignment. It is also what lets the gait
## re-phase itself without reaching back into the Assembly for a definition it
## was already handed.
var hip_local: Vector3 = Vector3.ZERO

## ===== FOOT ============================================================

var planted: bool = false
## World position the foot was planted at on touchdown. Meaningless in swing,
## and deliberately not cleared there: the swing arc interpolates from it to the
## next target, so clearing it would restart every swing from the origin.
var foot_world: Vector3 = Vector3.ZERO
## Hip-to-foot distance last tick, in metres. The damper term differentiates it.
var prev_length_m: float = 0.0
## True when the last stance tick demanded more shear than friction allowed. Read
## by presentation for the scuff effect, and by nothing in the simulation.
var slipping: bool = false


## True when this limb is in the stance half of its cycle and carrying load.
func in_stance(profile: LimbProfile) -> bool:
	return phase < profile.duty_factor
