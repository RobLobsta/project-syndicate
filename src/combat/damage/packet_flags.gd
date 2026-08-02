class_name PacketFlags
extends RefCounted
## Bitfield on [member DamagePacket.flags], owned by
## [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code] §3.
##
## Separate from [PartFlags] because these describe how a packet [i]arose[/i]
## rather than what state a part is in. A packet flagged [constant PACKET_SPALL]
## is still an ordinary BLAST packet to every formula that touches it; the flag
## exists so that the resolver can refuse to spall a spall, and so the network
## and telemetry layers can tell a secondary from the shot that produced it.

## Secondary blast generated behind an overpenetrated part (§4.4).
const PACKET_SPALL: int = 1 << 0
## The originating projectile passed through and continued (§4.4).
const PACKET_OVERPEN: int = 1 << 1
## One instalment of a damage-over-time entry rather than a discrete hit (§7.3).
const PACKET_DOT: int = 1 << 2
## Produced by a Prime Mover or volatile Support Module detonating (§8.5).
const PACKET_DETONATION: int = 1 << 3
