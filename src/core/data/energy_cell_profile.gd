class_name EnergyCellProfile
extends Resource
## Energy Cell payload, owned by [code]docs/PART_DATA_SCHEMA.md[/code] §7.7.
##
## An Energy Cell stores and supplies power and produces no shaft torque at all.
## It is the other half of the split described in §7.3: a Prime Mover makes
## torque and supplies a little power on the side, a cell makes no torque and
## supplies a great deal.
##
## The distinction is not cosmetic. [PowerSystem]'s available fraction gates a
## rotor's spool, so a rotary Assembly is limited by supply and does not care
## about torque; a wheeled one is limited by torque and needs only enough supply
## to keep its modules alive. Two classes let the garage state that trade as a
## choice between parts rather than as a number buried in one.

## ===== SUPPLY =========================================================

## Sustained draw the cell can cover indefinitely, in PU. The headline number,
## and the one [member PartDefinition.power_supply_pu] carries for every class.
@export var discharge_limit_pu: float = 260.0
## Reserve the cell holds, in PU-seconds. Covers a transient overdraw — a salvo
## and a spool at once — rather than raising the sustained figure.
@export var capacity_pu_s: float = 900.0
## Rate the reserve refills at when supply exceeds draw, in PU per second.
@export var recharge_pu_s: float = 45.0

## ===== THERMAL AND FAILURE ============================================

@export var thermal_throttle_start_hu: float = 540.0
@export var thermal_shutdown_hu: float = 820.0
## A cell fails harder than a Prime Mover of the same mass: it is a tank of
## energy with nowhere to go. §10.4's blast columns carry the shipping values.
@export var detonation_blast_radius_m: float = 3.4
@export var detonation_blast_damage: float = 300.0
