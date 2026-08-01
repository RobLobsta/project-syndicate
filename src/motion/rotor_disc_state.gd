class_name RotorDiscState
extends RefCounted
## Per-tick state of one rotary Motive Assembly, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §12.1.
##
## One per [constant PartEnums.MotiveKind.ROTOR_DISC] part, in a flat array on
## [MotiveSystem]. Nothing outside the rotary family reads it; the two telemetry
## fields exist for the HUD lift meter and the power ledger, which take a copy.

var slot: int = SyndicateConstants.INVALID_SLOT

## Current angular rate, in rad/s. Approaches its command through the spool lag
## of §12.6, never jumps to it.
var omega_rad_s: float = 0.0
## Current blade pitch in degrees, rate-limited toward its command. Signed:
## negative collective pushes the Assembly down.
var collective_deg: float = 0.0
## Cyclic deflection in degrees. X pitches the thrust vector, Y rolls it. Bounded
## on the resultant rather than per component — a swashplate's authority is a
## cone, and a square limit makes a diagonal input sqrt(2) times faster.
var cyclic_deg: Vector2 = Vector2.ZERO

## ===== TELEMETRY =======================================================
## Written every tick, read by presentation and the power ledger. Nothing in the
## simulation branches on either.

var last_thrust_n: float = 0.0
var last_shaft_w: float = 0.0


## Signed reaction torque this disc contributes about its own axis, in N·m.
##
## Summed across an Assembly to decide whether it can hold a heading: a build
## whose total exceeds its yaw authority spins under its own torque. That build
## is legal and the garage reports it, for the reason §12.4 gives.
func reaction_torque_nm(profile: RotorProfile) -> float:
	return (
		float(profile.spin_sign)
		* profile.torque_reaction_ratio
		* RotorSolver.shaft_torque_nm(profile, omega_rad_s)
	)
