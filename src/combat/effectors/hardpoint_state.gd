class_name HardpointState
extends RefCounted
## Per-Effector-Module kinematic and firing state, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §2.1.
##
## [code]hardpoint[/code] is the one permitted use of that word in this project
## (CLAUDE.md §8) and it means exactly this: the two-DOF rotational mount
## internal to an Effector Module. It carries no collision geometry — a rotated
## barrel does not rotate its collider, which is Architectural Invariant I-1 and
## is what makes hit registration identical on a client and a server regardless
## of animation state.
##
## All of an Assembly's hardpoint state lives in one contiguous array sized to
## its Effector Module count, at most sixteen. Iteration is a tight loop over a
## handful of objects.

var slot: int = SyndicateConstants.INVALID_SLOT

## ===== ORIENTATION =====================================================

## Current mount angles, within the profile's limits.
var yaw_rad: float = 0.0
var pitch_rad: float = 0.0
## Commanded angles, from §4's aim solve.
var yaw_target_rad: float = 0.0
var pitch_target_rad: float = 0.0
## True when the mount is within convergence tolerance of its command. The fire
## gate reads this and nothing else about aim: a module that has not arrived
## does not shoot, which is what stops a turret spraying rounds across the
## arena while it slews.
var on_target: bool = false

## ===== FIRING ==========================================================

## Seconds until the module may fire again.
var cycle_timer_s: float = 0.0
var burst_remaining: int = 0
var burst_recovery_s: float = 0.0
var rounds_in_magazine: int = 0
var reload_timer_s: float = 0.0
## Seconds of jam recovery remaining. §7.2's roll sets this and only the CRITICAL
## band can produce one.
var jam_timer_s: float = 0.0
var heat_hu: float = 0.0
## Current cone half-angle in degrees, bloomed by fire and decayed by §7.5.
var spread_current_deg: float = 0.0
## Which muzzle the next round leaves, for a multi-barrel module.
var next_muzzle_index: int = 0
## Rounds this module has emitted. Diagnostics, tests, and the scoreboard.
var shots_fired: int = 0


## Resets to the state a freshly attached module is in.
##
## Called at registration rather than in [method _init] so that re-registering a
## repaired module cannot leave a jam timer or a bloomed cone behind.
func reset(profile: EffectorModuleProfile) -> void:
	yaw_rad = 0.0
	pitch_rad = 0.0
	yaw_target_rad = 0.0
	pitch_target_rad = 0.0
	on_target = false
	cycle_timer_s = 0.0
	burst_recovery_s = 0.0
	reload_timer_s = 0.0
	jam_timer_s = 0.0
	heat_hu = 0.0
	next_muzzle_index = 0
	shots_fired = 0
	if profile == null:
		return
	spread_current_deg = profile.spread_base_deg
	rounds_in_magazine = profile.magazine_rounds
	burst_remaining = profile.burst_count


## Advances every timer by [param dt], flooring each at zero.
##
## Clearing the jam flag is the caller's job, not this function's: the flag lives
## on [PartInstanceState] and this class deliberately holds no reference to one.
func tick_timers(dt: float) -> void:
	cycle_timer_s = maxf(cycle_timer_s - dt, 0.0)
	burst_recovery_s = maxf(burst_recovery_s - dt, 0.0)
	reload_timer_s = maxf(reload_timer_s - dt, 0.0)
	jam_timer_s = maxf(jam_timer_s - dt, 0.0)


## True when the module is out of every timed lockout. §7.1 tests more than this
## — ammunition, heat, and aim — but this is the part that is purely time.
func timers_clear() -> bool:
	return (
		cycle_timer_s <= 0.0
		and burst_recovery_s <= 0.0
		and reload_timer_s <= 0.0
		and jam_timer_s <= 0.0
	)
