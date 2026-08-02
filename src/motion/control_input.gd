class_name ControlInput
extends RefCounted
## One tick of intent for an Assembly, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §6.0 and consumed by every
## locomotion family.
##
## A plain record. It is produced from the input map by [ControlSystem] for a
## local player, from the AI driver for a bot, and from the network's input
## channel for a remote Assembly on the server — and every one of those paths
## produces the same eight numbers, which is what lets the motion layer be
## written once.
##
## Every field is normalised to [-1, 1] or [0, 1] so that a keyboard, a stick,
## and a replayed packet are indistinguishable to the solvers.

## ===== SHARED =========================================================

## Forward drive demand, [-1, 1]. Negative is reverse.
var throttle: float = 0.0
## Steering demand, [-1, 1]. Positive is right.
var steer: float = 0.0
## Brake demand, [0, 1].
var brake: float = 0.0
var handbrake: bool = false
var boost: bool = false
## Traction-control authority, [0, 1]. 1.0 is the aid at full effect; 0.0 hands
## the driver every newton-metre the Prime Movers make, wheelspin included.
##
## A scalar rather than a flag because the interesting settings are between the
## two: doc 05 §7.6's limiter is a lerp toward the managed torque, so 0.5 is a
## real intermediate state and not an average of two behaviours.
var traction_control: float = 1.0

## ===== ROTARY =========================================================

## Collective demand, [-1, 1], mapped onto the disc's authored pitch range.
var collective: float = 0.0
## Cyclic demand. X pitches the thrust vector, Y rolls it; the resultant is
## bounded to the swashplate cone by [RotorSolver], not here.
var cyclic: Vector2 = Vector2.ZERO
## Pedal demand for yaw authority, [-1, 1].
var yaw: float = 0.0


## Desired horizontal velocity for the gait's foot placement law, given the
## Assembly's forward and right axes and its speed cap.
##
## The ambulatory family needs a velocity rather than a throttle, because the
## Raibert law in §13.5 corrects against a velocity error. Deriving it here
## rather than in the solver keeps the solver a pure function of physical
## quantities and keeps the mapping from stick to intent in one place.
func desired_velocity(forward: Vector3, right: Vector3, speed_cap_mps: float) -> Vector3:
	var v := forward * throttle + right * steer
	if v.length_squared() > 1.0:
		v = v.normalized()
	return v * speed_cap_mps


## True when the input asks for no motion at all, which is the state the gait
## freezes in and the suspension settles in.
func is_neutral() -> bool:
	return (
		is_zero_approx(throttle)
		and is_zero_approx(steer)
		and is_zero_approx(collective)
		and is_zero_approx(yaw)
		and cyclic.is_zero_approx()
	)
