class_name EventBusService
extends Node
## Autoload: [code]EventBus[/code]. Every cross-system signal in the project,
## owned by [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §8.
##
## Architectural Invariant I-4: connectivity, mass properties, fusion SDF,
## skirting, strain, and functional degradation are recomputed only in response
## to the signals below. A match with no destruction costs zero graph CPU time.
##
## Enum-valued payloads are declared [code]int[/code] because Godot signals
## carry enums as plain integers, and typing them otherwise would drag UI and
## combat types into the autoload's dependency set.

## ===== STRUCTURE: CONSUMED BY THE GRAPH ================================

## Integrity reached zero. [param cause] is a [enum PartEnums.DamageChannel].
signal part_destroyed(assembly_id: int, slot: int, cause: int)
## Strain exceeded the joint's rated strength.
signal joint_failed(assembly_id: int, slot_a: int, slot_b: int)
## Garage build command removed a part.
signal part_removed(assembly_id: int, slot: int)
## Garage build command or blueprint load attached a part.
signal part_attached(assembly_id: int, slot: int)
## End of each physics tick. Emitted by [code]MatchClock[/code] only.
signal tick_resolved

## ===== STRUCTURE: EMITTED BY THE GRAPH =================================

signal assembly_structure_changed(assembly_id: int)
signal island_detached(assembly_id: int, slots: PackedByteArray, body_id: int)
signal assembly_mass_dirty(assembly_id: int)
signal assembly_terminated(assembly_id: int, killer_id: int)
signal joint_strain_changed(assembly_id: int, slot_a: int, slot_b: int, strain: float)

## ===== DAMAGE ==========================================================

## [param channel] is a [enum PartEnums.DamageChannel].
signal part_damaged(assembly_id: int, slot: int, amount: float, channel: int)
## Resistance and armour reduced the packet to nothing.
signal damage_negated(assembly_id: int, slot: int, channel: int)
## [param before] and [param after] are [enum PartEnums.IntegrityBand] values.
signal part_band_changed(assembly_id: int, slot: int, before: int, after: int)

## ===== COMBAT ==========================================================

signal effector_fired(assembly_id: int, slot: int, tick: int)
signal effector_jammed(assembly_id: int, slot: int)

## ===== WORLD ===========================================================

signal ground_deformed(deform_id: int, centre_world: Vector3, radius_m: float)
## [param cause] is a Static Volume failure kind; see doc 10 §6.
signal section_failed(volume_id: int, section_index: int, cause: int)

## ===== PRESENTATION AND UI =============================================

signal part_visual_swapped(assembly_id: int, slot: int)
## [param stats] is produced off-thread; see [AssemblyStats].
signal assembly_stats_ready(stats: AssemblyStats)
## [param tier] is a [code]Breakpoint.Tier[/code] value.
signal ui_breakpoint_changed(tier: int)
signal inventory_changed
## One step of consumable mass depletion (ammunition, fuel) has accumulated
## enough to justify a mass resolve.
signal consumable_mass_step(assembly_id: int)

## ===== TICK PRIORITY GROUPS ============================================
## A handler registered at a lower priority may never observe state produced by
## a higher one within the same tick. This ordering is what makes the whole
## event-driven design tractable to reason about.

const PRIORITY_DAMAGE: int = 100  # integrity writes complete
const PRIORITY_DETACHMENT: int = 200  # islands determined, debris spawned
const PRIORITY_MASS: int = 300  # mass/COM/inertia recomputed
const PRIORITY_FUNCTIONAL: int = 400  # power, traction, targeting sets updated
const PRIORITY_PRESENTATION: int = 500  # SDF/skirt/UI marked dirty
const PRIORITY_NETWORK: int = 600  # snapshot assembled

var _tick_entries: Array[TickEntry] = []
## Monotonic sequence number giving a total order to equal priorities, so that
## dispatch order never depends on sort stability or on hash iteration.
var _tick_sequence: int = 0


## Connects [param handler] to [signal tick_resolved] within a priority group.
##
## [b]Always use this rather than connecting to the signal directly.[/b] A raw
## connect runs in connection order, which is registration order, which depends
## on scene tree construction and is therefore not reproducible.
func connect_tick_resolved(handler: Callable, priority: int) -> void:
	assert(not _has_tick_handler(handler), "handler registered twice: %s" % handler)
	var entry := TickEntry.new()
	entry.priority = priority
	entry.sequence = _tick_sequence
	entry.handler = handler
	_tick_sequence += 1
	_tick_entries.append(entry)
	_rebuild_tick_connections()


func disconnect_tick_resolved(handler: Callable) -> void:
	for i in _tick_entries.size():
		if _tick_entries[i].handler == handler:
			if tick_resolved.is_connected(handler):
				tick_resolved.disconnect(handler)
			_tick_entries.remove_at(i)
			_rebuild_tick_connections()
			return
	push_warning("EventBus: disconnect of unregistered tick handler: %s" % handler)


## Priorities of the registered handlers in dispatch order. Used by
## [code]tests/integration/test_tick_ordering.gd[/code].
func tick_handler_priorities() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(_tick_entries.size())
	for i in _tick_entries.size():
		out[i] = _tick_entries[i].priority
	return out


func _has_tick_handler(handler: Callable) -> bool:
	for e in _tick_entries:
		if e.handler == handler:
			return true
	return false


## Godot dispatches a signal in connection order, so imposing a priority means
## rebuilding every connection whenever the set changes. This runs only on
## subsystem registration, never per tick.
func _rebuild_tick_connections() -> void:
	for e in _tick_entries:
		if tick_resolved.is_connected(e.handler):
			tick_resolved.disconnect(e.handler)
	_tick_entries.sort_custom(_compare_tick_entries)
	for e in _tick_entries:
		tick_resolved.connect(e.handler)


static func _compare_tick_entries(a: TickEntry, b: TickEntry) -> bool:
	if a.priority != b.priority:
		return a.priority < b.priority
	return a.sequence < b.sequence


class TickEntry:
	extends RefCounted

	var priority: int = 0
	var sequence: int = 0
	var handler: Callable = Callable()
