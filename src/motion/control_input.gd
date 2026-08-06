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
## Assembly's forward axis and its speed cap.
##
## The ambulatory family needs a velocity rather than a throttle, because the
## Raibert law in §13.5 corrects against a velocity error. Deriving it here
## rather than in the solver keeps the solver a pure function of physical
## quantities and keeps the mapping from stick to intent in one place.
##
## [b]It used to be `forward · throttle + right · steer`, and dropping the second
## term is doc 05 §13.12.[/b] A walking Assembly is not driven like a car and is
## not driven like a drone either: `throttle` walks it along its own facing and
## `steer` turns it, which is what a person does and what every player expects of
## a machine with legs. While `steer` also strafed, one number did two jobs — it
## commanded a sideways velocity *and* rotated §13.5's plant target — and the two
## fought each other, which is most of why the demand behaved as a disturbance
## with a sign attached rather than as a heading authority.
func desired_velocity(forward: Vector3, speed_cap_mps: float) -> Vector3:
	return forward * clampf(throttle, -1.0, 1.0) * speed_cap_mps


## True when the input asks for no motion at all, which is the state the gait
## freezes in and the suspension settles in.
##
## There used to be an `is_coasting()` beside this for doc 05 §7.7's holding
## brake, and it is gone rather than kept: §7.7 now reads the brake half off
## §15.5's [i]released[/i] demand, which is a quantity only [MotiveSystem] holds,
## so a predicate over the raw record could no longer answer the question it was
## named for.
func is_neutral() -> bool:
	return (
		is_zero_approx(throttle)
		and is_zero_approx(steer)
		and is_zero_approx(collective)
		and is_zero_approx(yaw)
		and cyclic.is_zero_approx()
	)
