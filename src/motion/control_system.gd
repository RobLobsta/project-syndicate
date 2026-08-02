class_name ControlSystem
extends Node
## Samples the local player's input into one [ControlInput] per tick, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §15.
##
## One of three producers of the same record. The AI driver is the second and
## the network input channel is the third, and none of them may add a field: a
## locomotion family reads eight normalised numbers and cannot tell which
## producer wrote them, which is what lets §6 and §7 be written once.
##
## [b]It reacts to [signal MatchClockService.tick_started] and declares no
## per-frame callback.[/b] The clock runs at
## [code]process_physics_priority = -1000[/code], so that signal fires before
## every other [code]_physics_process[/code] in the tree — [MotiveSystem]'s
## included. Sampling there is what guarantees the intent a family reads was
## captured on the tick it is being solved for, and it makes the ordering a
## property of the clock rather than of where the match scene happened to add
## this node.
##
## Nothing here branches on locomotion family. §15.3 maps one axis onto several
## fields and each family reads the ones it uses, because a build may carry more
## than one family at once and a mode switch would have to pick a winner.

## ===== ACTIONS =========================================================
## The [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §7.1 action set. Quoted as
## [StringName] constants so that no per-tick read builds one, and read through
## the input map rather than as key codes, which CLAUDE.md §7.3 requires of all
## gameplay code.

const ACTION_THROTTLE: StringName = &"veh_throttle"
const ACTION_BRAKE: StringName = &"veh_brake"
const ACTION_STEER_LEFT: StringName = &"veh_steer_left"
const ACTION_STEER_RIGHT: StringName = &"veh_steer_right"
const ACTION_HANDBRAKE: StringName = &"veh_handbrake"
const ACTION_BOOST: StringName = &"veh_boost"
const ACTION_PITCH_FORWARD: StringName = &"veh_pitch_forward"
const ACTION_PITCH_BACK: StringName = &"veh_pitch_back"
const ACTION_ROLL_LEFT: StringName = &"veh_roll_left"
const ACTION_ROLL_RIGHT: StringName = &"veh_roll_right"

## The record written every tick. Shared with the [MotiveSystem] that reads it;
## set once, before this node enters the tree.
var input: ControlInput = null

## §7.6's traction-control authority, in [code][0, 1][/code]. A driver setting
## rather than an intent, which is why it lives on the system and not on the
## input map: the player picks it once in a menu and the record carries it every
## tick so that the network path and the AI path carry it identically.
var aid_authority: float = 1.0


func _enter_tree() -> void:
	# A control system with no record samples the input map sixty times a second
	# and throws all of it away, which presents as an Assembly that ignores the
	# controls rather than as anything diagnosable.
	assert(input != null, "ControlSystem.input must be set before it enters the tree")
	MatchClock.tick_started.connect(_on_tick_started)


func _exit_tree() -> void:
	MatchClock.tick_started.disconnect(_on_tick_started)


## Writes this tick's intent into [member input].
##
## Separable from the clock so that a test can take one sample without running
## the engine, through the identical path the clock uses.
func sample() -> void:
	var drive := axis(ACTION_BRAKE, ACTION_THROTTLE)
	var lateral := axis(ACTION_STEER_LEFT, ACTION_STEER_RIGHT)
	input.throttle = drive
	input.collective = drive
	input.brake = Input.get_action_strength(ACTION_BRAKE)
	input.steer = lateral
	input.yaw = lateral
	input.cyclic = cyclic_demand()
	input.handbrake = Input.is_action_pressed(ACTION_HANDBRAKE)
	input.boost = Input.is_action_pressed(ACTION_BOOST)
	input.traction_control = clampf(aid_authority, 0.0, 1.0)


## Signed strength of an opposed pair of actions, in [code][-1, 1][/code].
##
## Both halves go through [method Input.get_action_strength] rather than
## [method Input.is_action_pressed], so a trigger, a stick and a key produce the
## same number without a special case, and the deadzone declared on the action
## in [code]project.godot[/code] is the only deadzone in the chain.
static func axis(negative_action: StringName, positive_action: StringName) -> float:
	return (
		Input.get_action_strength(positive_action)
		- Input.get_action_strength(negative_action)
	)


## Cyclic demand in the swashplate convention §12.3 solves in.
##
## §15.4: §12.3 rotates the disc axis about [code]+X[/code] by
## [code]cyclic.x[/code] and about [code]+Z[/code] by [code]cyclic.y[/code], and
## under that order a positive x carries the thrust vector toward [code]+Z[/code]
## — backwards — and a positive y carries it toward [code]-X[/code], which is
## left. A demand to pitch forward is therefore a negative x and a demand to roll
## right a negative y. The inversion belongs here rather than in the solver:
## §12.3's rotation order is the physics, and this is the mapping onto it.
static func cyclic_demand() -> Vector2:
	return Vector2(
		axis(ACTION_PITCH_FORWARD, ACTION_PITCH_BACK),
		axis(ACTION_ROLL_RIGHT, ACTION_ROLL_LEFT)
	)


func _on_tick_started(_tick: int) -> void:
	sample()
