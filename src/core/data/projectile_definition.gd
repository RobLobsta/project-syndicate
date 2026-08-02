class_name ProjectileDefinition
extends Resource
## One projectile type, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §12.
##
## Immutable at runtime like every other definition (Architectural Invariant
## I-11). Projectiles carry no per-instance state at all — the pool holds it in
## flat arrays — so there is nothing here a shot could want to write back.
##
## The damage figures are what [DamageResolver] receives; the flight figures are
## what [ProjectileSystem] integrates. Nothing else reads this.

## ===== IDENTITY ========================================================

## `proj.<channel>.<variant>`; the key an [EffectorModuleProfile] names.
@export var projectile_key: StringName = &"proj.kinetic.ap_30"

## ===== DAMAGE ==========================================================

@export var channel: PartEnums.DamageChannel = PartEnums.DamageChannel.KINETIC
## Before resistance, armour and angle.
@export var damage: float = 120.0
## Armour-piercing capability, compared against the target's angle-adjusted
## armour rating by §4.3. Meaningful on the KINETIC channel only.
@export var penetration: float = 95.0
## Non-zero turns the hit into a blast at the impact point instead of a
## single-part packet.
@export var blast_radius_m: float = 0.0

## ===== FLIGHT ==========================================================

## Seconds before the round expires unspent. Bounds the pool's occupancy no
## matter what the geometry does.
@export var life_s: float = 4.0
## 1.0 falls under gravity; 0.0 flies flat. A beam is 0.0 and a mortar is 1.0.
@export var gravity_scale: float = 1.0
## Quadratic drag per metre. Zero is a vacuum round.
@export var drag_coefficient_per_m: float = 0.0
## True when the round continues after a hit it overpenetrated.
@export var penetrates_after_hit: bool = false


## Speed lost to drag over [param dt] at [param speed_mps], in m/s.
##
## Semi-implicit and applied against the direction of travel, so a round can be
## slowed to a stop but never reversed by its own drag.
func drag_delta_mps(speed_mps: float, dt: float) -> float:
	if drag_coefficient_per_m <= 0.0 or speed_mps <= 0.0:
		return 0.0
	return minf(drag_coefficient_per_m * speed_mps * speed_mps * dt, speed_mps)
