class_name DamageOutcome
extends RefCounted
## What [method DamageResolver.apply] did with a packet, owned by
## [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code] §3.1.
##
## Three results, and the difference between two of them matters to the caller.
## [b]Rejected[/b] means the packet was never eligible — a client tried to author
## damage, or the target is already gone — and the shot should be treated as
## though it had missed. [b]Negated[/b] means the packet was eligible and the
## armour ate it, which is a hit, is worth a spark and a hit marker, and is what
## [signal EventBusService.damage_negated] announces. A caller that treated the
## two alike would show a player their armour-piercing round bouncing off a part
## that had already fallen off.

enum Result { APPLIED = 0, NEGATED = 1, REJECTED = 2 }

var result: Result = Result.REJECTED
## Integrity actually removed, after every multiplier. Zero unless applied.
var amount: float = 0.0
## The band the part is in now. Meaningful only when applied.
var band: PartEnums.IntegrityBand = PartEnums.IntegrityBand.NOMINAL
## True when this packet is what took the part to zero.
var destroyed: bool = false
## Why the packet was rejected. Empty otherwise; diagnostics only.
var reason: String = ""


static func applied(
	dealt: float, new_band: PartEnums.IntegrityBand, was_destroyed: bool
) -> DamageOutcome:
	var out := DamageOutcome.new()
	out.result = Result.APPLIED
	out.amount = dealt
	out.band = new_band
	out.destroyed = was_destroyed
	return out


static func negated() -> DamageOutcome:
	var out := DamageOutcome.new()
	out.result = Result.NEGATED
	return out


static func rejected(why: String) -> DamageOutcome:
	var out := DamageOutcome.new()
	out.result = Result.REJECTED
	out.reason = why
	return out


func was_applied() -> bool:
	return result == Result.APPLIED


## True when the packet reached a live part, whether or not any integrity came
## off it. This is the test a hit marker wants; [method was_applied] is the test
## a damage number wants.
func hit_something() -> bool:
	return result != Result.REJECTED
