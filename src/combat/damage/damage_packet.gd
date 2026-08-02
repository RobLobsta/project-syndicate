class_name DamagePacket
extends RefCounted
## One unit of damage offered to [DamageResolver], owned by
## [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code] §3.
##
## Every damage source in the project produces one of these and nothing else
## writes [member PartInstanceState.integrity]. A projectile hit, a blast, a
## ram, a burning Prime Mover and a repair emitter all arrive through the same
## door, which is what makes resistance, armour, band transitions and
## destruction impossible to bypass by accident.
##
## A plain record with no behaviour. It is deliberately not a [Resource]: these
## are constructed per hit, at up to several hundred a second, and a
## [RefCounted] costs an allocation where a Resource costs an allocation plus a
## path, a uid and a place in the resource cache.

## ===== TARGET ==========================================================

var target_assembly_id: int = -1
var target_slot: int = SyndicateConstants.INVALID_SLOT

## ===== THE DAMAGE ======================================================

var channel: PartEnums.DamageChannel = PartEnums.DamageChannel.KINETIC
## Before resistance, armour, angle, and band multipliers.
var raw_amount: float = 0.0
## KINETIC only: armour-piercing capability, compared against the part's
## angle-adjusted armour rating in §4.3.
var penetration: float = 0.0

## ===== GEOMETRY ========================================================

var impact_point_world: Vector3 = Vector3.ZERO
var impact_normal_world: Vector3 = Vector3.ZERO
## Unit vector the damage arrived along. §4.1 takes the angle of incidence from
## this and [member impact_normal_world].
var incoming_direction: Vector3 = Vector3.ZERO

## ===== PROVENANCE ======================================================

var source_assembly_id: int = -1
var source_slot: int = SyndicateConstants.INVALID_SLOT
var source_tick: int = 0
## Guards recursive blast and detonation. §8.5 bounds this at
## [constant DamageResolver.MAX_CHAIN_DEPTH].
var chain_depth: int = 0
## Bitfield; see [PacketFlags].
var flags: int = 0
## Seconds this instalment covers. Only meaningful for a
## [constant PacketFlags.PACKET_DOT] packet, where §7.1's and §7.2's rates are
## per second and the scheduler fires at 10 Hz.
var interval_s: float = 0.0


func has_flag(flag: int) -> bool:
	return (flags & flag) != 0


## Cosine of the angle of incidence, in [code][0, 1][/code]. §4.1.
##
## Zero for a packet with no geometry — a detonation resolved at its own
## epicentre has no meaningful surface angle — which §4.1's [constant
## DamageResolver.COS_FLOOR] then floors, so an armour rating is never divided
## by zero and a geometry-less packet is treated as the most oblique hit rather
## than as a special case.
func cos_incidence() -> float:
	if incoming_direction.is_zero_approx() or impact_normal_world.is_zero_approx():
		return 0.0
	return clampf(-incoming_direction.normalized().dot(impact_normal_world.normalized()), 0.0, 1.0)
