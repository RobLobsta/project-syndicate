class_name AssemblyStats
extends RefCounted
## Snapshot of an Assembly's aggregate properties, produced by the worker-thread
## stat solver on structural change and delivered by
## [signal EventBusService.assembly_stats_ready].
##
## A plain record with no behaviour: it crosses a thread boundary, so it must
## hold no node references and touch no shared mutable state. Consumers read it
## and discard it; it is never cached as authority for anything.

var assembly_id: int = 0
## Tick at which the solve was requested, so a late result can be discarded when
## a newer edit has already superseded it.
var source_tick: int = 0

var total_mass_kg: float = 0.0
## Core Module's mass_tolerance_kg; above it, handling penalties accrue.
var mass_tolerance_kg: float = 0.0
var centre_of_mass_local: Vector3 = Vector3.ZERO

var power_draw_pu: float = 0.0
var power_capacity_pu: float = 0.0

var mounts_used: int = 0
var mount_budget: int = 0

var projected_top_speed_mps: float = 0.0
var total_integrity: float = 0.0
## Lateral acceleration at which the Assembly rolls, in g.
var rollover_lateral_g: float = 0.0

var part_count: int = 0
var build_cost: int = 0


func over_mass() -> bool:
	return total_mass_kg > mass_tolerance_kg


func over_power() -> bool:
	return power_draw_pu > power_capacity_pu


func over_mounts() -> bool:
	return mounts_used > mount_budget
