class_name HudFrame
extends RefCounted
## One tick's worth of continuous state for the match HUD, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §14.1.
##
## §11 rule 2 says the interface never polls the Assembly, and in the garage that
## is easy: a build changes only when the player edits it, so every value has a
## structural event behind it. A match has no such luxury — speed, throttle, and
## whether a mount is on target change every tick by construction, and there is
## no signal that means "the vehicle is now doing 14.2 m/s".
##
## So the rule is restated rather than relaxed. [MatchScreen] fills one of these
## per tick and hands it over; the HUD renders it and keeps no other source. The
## HUD holds no [AssemblyRuntime], no [ChassisGraph], and no [PartInstanceState],
## and iterates no parts.
##
## That is not a stylistic preference. A HUD that walked the part array to total
## integrity would be an O(parts) loop at 60 Hz duplicating arithmetic doc 08
## already owns — a second owner of one quantity, which is the failure
## [code]HANDOFF.md[/code] §2.1 records nine separate times.
##
## Like [AssemblyStats], and for the same reason: a record that can reach back
## into the tree has stopped being a record. Nothing here is a node reference.

enum ReticleState {
	## The Assembly carries no Effector Module.
	NO_EFFECTOR = 0,
	## A mount exists, but its solution is outside its arc or has not converged.
	SEEKING = 1,
	## Converging, in arc, not yet on target.
	TRACKING = 2,
	ON_TARGET = 3,
	## On target with an empty store.
	NO_AMMO = 4,
}

## ===== MOTION ==========================================================

var speed_mps: float = 0.0
var throttle: float = 0.0
var steer: float = 0.0
var brake: float = 0.0

## ===== CONDITION =======================================================

## Total live integrity over total integrity at spawn, in [code][0, 1][/code].
var integrity_fraction: float = 1.0
var parts_alive: int = 0
var parts_total: int = 0

var power_draw_pu: float = 0.0
var power_capacity_pu: float = 0.0

## ===== COMBAT ==========================================================

var reticle_state: ReticleState = ReticleState.NO_EFFECTOR
## [constant AmmoLedger.UNLIMITED] renders as a dash rather than as a number.
var rounds_remaining: int = 0

## ===== MATCH ===========================================================

var assemblies_standing: int = 0
var tick: int = 0
