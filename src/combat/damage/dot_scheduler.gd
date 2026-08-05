class_name DotScheduler
extends Node
## Damage over time, owned by
## [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code] §7.3.
##
## One flat list, processed at 10 Hz, holding every part that is currently
## burning. The early return on an empty list is the important line: a match with
## nothing on fire costs one array size check per tick, which is what lets §7.1's
## fire exist at all without a per-part per-frame walk that Invariant I-4 forbids.
##
## [b]The shipped entry is §7.1's fire and it is the only one.[/b] §7.3 writes a
## generic [code]DotEntry[/code] with a [code]remaining_s[/code] countdown, which
## is the right shape for an incendiary round or a burning fuel spill; neither is
## authored, and a public submit path with no producer is dead code that a fault
## sweep cannot reach. So an entry here lives for as long as its part carries
## [constant PartFlags.FLAG_OVERHEATED] — the hysteresis band of §7.1 rather than
## a duration — and a timed entry is the second kind, to be added with the first
## thing that produces one.
##
## [b]It cools the part it burns, and only that part.[/b] §7.1 ends a fire when
## heat falls under [constant DamageResolver.THERMAL_EXTINCTION_HU] and the
## document says nothing about what makes it fall. Cooling every part in the
## match per tick is precisely the poll I-4 exists to forbid, and a part below the
## ignition point that keeps its heat is a part closer to catching fire next time,
## which is the more interesting of the two readings. So the cooling rides on the
## entry: a part that is burning sheds heat, a part that is merely warm does not,
## and the band is reachable in the one place it is observable.

## §7.3's cadence. Ten instalments a second rather than sixty, because a burn is
## a rate and nothing a player can see distinguishes the two.
const TICK_INTERVAL_S: float = 0.1

## Architectural Invariant I-12: every repeatable reaction carries an explicit
## bound. One entry per burning part and a part ignites once, so this is reached
## only by an Assembly whose every part is alight at once — but a bound nobody
## reaches is still cheaper than a list nobody bounded.
const MAX_ENTRIES: int = 128

## Where instalments go. Null leaves the scheduler inert, which is what a
## headless peer that resolves no damage wants.
var resolver: DamageResolver = null

var _entries: Array[DotEntry] = []
var _accum_s: float = 0.0


func _physics_process(dt: float) -> void:
	step(dt)


## Lights [param slot] of [param assembly_id], burning until its heat falls back
## under §7.1's extinction threshold.
##
## [b]Offered on every packet that leaves the part alight[/b], including an
## instalment of the part's own fire, so the de-duplication here is the one owner
## of "one entry per burning part" — a build held in a beam burns at §7.1's rate
## and not at that rate times however many packets arrived. A part already alight
## has its entry re-attributed to the latest source rather than gaining a second
## one, which is what makes a kill by fire belong to whoever last fed it.
func ignite(assembly_id: int, slot: int, source_assembly_id: int) -> void:
	for entry: DotEntry in _entries:
		if entry.assembly_id == assembly_id and entry.slot == slot:
			entry.source_assembly_id = source_assembly_id
			return
	if _entries.size() >= MAX_ENTRIES:
		return
	var fresh := DotEntry.new()
	fresh.assembly_id = assembly_id
	fresh.slot = slot
	fresh.source_assembly_id = source_assembly_id
	_entries.push_back(fresh)


## Parts currently burning. Diagnostics and tests.
func entry_count() -> int:
	return _entries.size()


## True while [param slot] of [param assembly_id] is alight.
func is_burning(assembly_id: int, slot: int) -> bool:
	for entry: DotEntry in _entries:
		if entry.assembly_id == assembly_id and entry.slot == slot:
			return true
	return false


## One tick of §7.3's list. Public for the same reason [method EffectorSystem.step]
## is: a test drives a synthetic dt through the identical path the engine uses.
func step(dt: float) -> void:
	if _entries.is_empty():
		return
	_accum_s += dt
	if _accum_s < TICK_INTERVAL_S:
		return
	var elapsed := _accum_s
	_accum_s = 0.0
	if resolver == null or resolver.registry == null:
		return
	# Backwards, so an entry that goes out is removed without moving the index of
	# one that has not been visited yet. §7.3's loop, and its reason.
	var i := _entries.size() - 1
	while i >= 0:
		if not _burn(_entries[i], elapsed):
			_entries.remove_at(i)
		i -= 1


## ===== PRIVATE =========================================================


## One instalment against one part. Returns false when the fire is out and the
## entry should leave the list.
##
## Damage first, then cooling, then the extinction test, and the order is the
## whole function: a THERMAL packet raises the heat it is resolved against
## (§7.1), so cooling applied before the packet would be testing yesterday's
## number and a fire would take an extra instalment to notice it had gone out.
func _burn(entry: DotEntry, elapsed: float) -> bool:
	var runtime := resolver.registry.get_runtime(entry.assembly_id)
	if runtime == null:
		return false
	if entry.slot < 0 or entry.slot >= runtime.states.size():
		return false
	var st: PartInstanceState = runtime.states[entry.slot]
	if st == null or st.is_inactive():
		return false
	if not st.has_flag(PartFlags.FLAG_OVERHEATED):
		# Extinguished by something other than this entry — a repair, or a part
		# that was reignited and cooled inside one instalment.
		return false

	var outcome := resolver.apply(entry.build_packet(elapsed))
	if outcome.destroyed:
		return false

	st.accumulated_heat_hu = maxf(
		0.0, st.accumulated_heat_hu - DamageResolver.THERMAL_COOLING_HU_S * elapsed
	)
	if st.accumulated_heat_hu >= DamageResolver.THERMAL_EXTINCTION_HU:
		return true
	st.flags &= ~PartFlags.FLAG_OVERHEATED
	st.flags |= PartFlags.FLAG_VISUAL_DIRTY | PartFlags.FLAG_NET_DIRTY
	return false


## One burning part. §7.3's [code]DotEntry[/code], carrying provenance rather
## than a duration; see the class comment for why there is no countdown on it.
class DotEntry:
	extends RefCounted

	var assembly_id: int = -1
	var slot: int = SyndicateConstants.INVALID_SLOT
	## Whoever set it alight, so a kill by fire is attributed to the Assembly that
	## lit it rather than to nobody. §8.2 allows an unattributed termination and
	## this is deliberately not one.
	var source_assembly_id: int = -1

	## The instalment covering [param elapsed] seconds.
	##
	## [member DamagePacket.raw_amount] is the damage for the instalment and
	## [member DamagePacket.interval_s] is what it covers, so §7.1's rate is
	## multiplied out exactly once and a scheduler that fell behind delivers the
	## same total as one that did not.
	func build_packet(elapsed: float) -> DamagePacket:
		var packet := DamagePacket.new()
		packet.target_assembly_id = assembly_id
		packet.target_slot = slot
		packet.channel = PartEnums.DamageChannel.THERMAL
		packet.raw_amount = DamageResolver.THERMAL_SELF_DAMAGE_PER_S * elapsed
		packet.interval_s = elapsed
		packet.source_assembly_id = source_assembly_id
		packet.source_tick = MatchClock.tick
		packet.flags = PacketFlags.PACKET_DOT
		return packet
