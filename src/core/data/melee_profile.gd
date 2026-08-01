class_name MeleeProfile
extends Resource
## Melee Effector Module payload, owned by
## [code]docs/PART_DATA_SCHEMA.md[/code] §7.4.1. Firing semantics are owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §15.
##
## Carried by an [EffectorModuleProfile] whose [member EffectorModuleProfile.kind]
## is [constant PartEnums.EffectorKind.KINETIC_MELEE] or
## [constant PartEnums.EffectorKind.ENERGY_MELEE], and by no other.
##
## A melee module emits no projectile and consumes no ammunition, so the
## emission fields of its parent profile — muzzle velocity, cycle time, spread,
## magazine, recoil — are meaningless for it and the registry validator requires
## them to be zero rather than merely ignored (§14 rule 20).

## ===== REACH ===========================================================

## Distance from the hardpoint pivot to the tip of the striking edge.
@export var reach_m: float = 2.40
## Radius of the swept capsule. The edge is a volume, not a line: a zero-radius
## sweep passes between two adjacent parts of a lattice-built Assembly and
## reports a clean miss where an edge would have cut both.
@export var edge_radius_m: float = 0.18
## Angular extent of one swing about the hardpoint yaw axis. Zero describes a
## fixed edge that does not swing at all, which is what a ram is.
@export var swing_arc_deg: float = 150.0
## Sweep segments per swing. Fixes the query cost of a swing rather than letting
## it follow how fast the arc happens to travel. Never a damage multiplier:
## [MeleeStrikeState] skips an Assembly the current swing has already struck.
@export var swing_samples: int = 6

## ===== TIMING ==========================================================

@export var wind_up_s: float = 0.28
@export var swing_duration_s: float = 0.22
@export var recovery_s: float = 0.46

## ===== EFFECT ==========================================================

## Damage of one strike, split across channels by [member channel_mix].
@export var strike_damage: float = 640.0
## Fractions summing to 1.0, indexed by [enum PartEnums.DamageChannel].
##
## What separates the two melee kinds without a second code path: a kinetic
## spike is overwhelmingly IMPACT, an energy edge overwhelmingly THERMAL, and
## the thermal resistance spread across the structural families does the balance
## work. The kind enum selects presentation and the power model; this does the
## rest.
@export var channel_mix: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
## Impulse delivered to the struck Assembly, along the edge's travel direction.
@export var strike_impulse_ns: float = 2800.0
## Fraction of that impulse applied back to the wielder. What stops melee being
## a free weapon, and why melee rewards mass.
@export var reaction_ratio: float = 0.35
## Assemblies one swing may strike before it stops. CLAUDE.md §6 I-12.
@export var max_targets_per_swing: int = 3

## ===== REGIME ==========================================================

## Closing speed below which a strike does nothing. A ram needs the Assembly to
## be moving; a powered edge does not, and authors 0.0.
@export var min_closing_speed_mps: float = 0.0
## True for a continuously energised edge that damages for as long as it is held
## against a target, rather than only on a discrete swing.
@export var sustained: bool = false
## Damage per second while sustained contact is maintained.
@export var sustained_damage_s: float = 0.0
## Power drawn while the edge is energised, on top of the definition's
## [member PartDefinition.power_draw_pu].
@export var energised_draw_pu: float = 0.0


## Total duration of one uninterrupted strike cycle, in seconds. Scaled by the
## effector cycle-time band multiplier, which is the one substitution §15.6
## makes against the ballistic degradation path.
func cycle_duration_s() -> float:
	return wind_up_s + swing_duration_s + recovery_s


## Sum of [member channel_mix]. The validator requires 1.0 within 0.001; a mix
## summing to anything else silently scales every strike this part ever lands.
func channel_mix_sum() -> float:
	var total := 0.0
	for share: float in channel_mix:
		total += share
	return total
