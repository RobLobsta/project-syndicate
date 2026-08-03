class_name MeleeStrikeState
extends RefCounted
## Stage machine for one melee Effector Module, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §15.2.
##
## Melee reuses [code]HardpointState[/code] for aiming — an edge on a two-DOF
## mount tracks an aim point exactly as a barrel does — and adds this record for
## everything a swing needs that a cycle timer cannot express.

enum Stage {
	READY = 0,
	WIND_UP = 1,
	SWINGING = 2,
	RECOVERING = 3,
}

var slot: int = SyndicateConstants.INVALID_SLOT
var stage: Stage = Stage.READY
var stage_timer_s: float = 0.0
## Progress through the swing arc, [0, 1]. Only meaningful in SWINGING.
var swing_t: float = 0.0
## Assembly ids struck by the current swing.
##
## What makes [member MeleeProfile.swing_samples] invisible to balance: an
## Assembly already struck this swing is skipped, so a six-sample swing and a
## sixteen-sample swing deal the same damage. Without it the sample count would
## silently be a damage multiplier and the profile field would be unauthorable.
var struck_this_swing: PackedInt32Array = PackedInt32Array()
## True while a sustained edge is energised and drawing power.
var energised: bool = false
## Where the last strike of this swing landed, in world space — the edge's own
## origin at the sample that connected, which is [member MeleeProfile.reach_m]
## halved along the blade from the hand.
##
## Diagnostics, in the same sense and for the same reason as
## [method ProjectileSystem.strikes_of]: it is the only observable that says at
## [i]what angle through the arc[/i] a swing connected, and without it §15.4's
## impulse direction can only be checked against a contact angle guessed from
## outside. Written by the resolver, read by nothing that simulates.
var last_strike_point_world: Vector3 = Vector3.ZERO


## True when the module may begin a new strike.
func can_start() -> bool:
	return stage == Stage.READY


## Begins a strike, clearing the per-swing target set.
func begin() -> void:
	stage = Stage.WIND_UP
	stage_timer_s = 0.0
	swing_t = 0.0
	struck_this_swing.clear()


## Aborts a committed swing without resolving it, dropping straight to recovery.
##
## The jam path. A blade that has already committed and delivers nothing is
## exactly as punishing as a jammed autocannon, and needed no new mechanism.
func abort_to_recovery() -> void:
	stage = Stage.RECOVERING
	stage_timer_s = 0.0
	swing_t = 0.0


## True when [param assembly_id] has already been struck by the current swing,
## or the swing has reached its target budget.
func already_struck(assembly_id: int, max_targets: int) -> bool:
	if struck_this_swing.size() >= max_targets:
		return true
	return struck_this_swing.has(assembly_id)
