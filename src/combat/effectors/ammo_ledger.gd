class_name AmmoLedger
extends RefCounted
## Per-Assembly ammunition stores, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §9.2.
##
## Ammunition is held by [b]projectile type[/b], per Assembly, not per Effector
## Module. Two autocannon firing the same round draw from one store, which is
## what makes carrying a second one a real trade against the Support Modules
## that hold the rounds — rather than a free doubling of a build's total output.
##
## Keyed on the projectile id, never the [StringName]. The fire gate reads this
## once per module per tick and a hash there is a hash in the hottest loop the
## combat layer has.

## Store with no limit. Distinguishable from an exhausted one, which is the
## whole point: an Assembly with no store entry at all for a round has never
## been given any, and an Assembly with a zero entry has fired all of them.
const UNLIMITED: int = -1

## assembly_id -> (projectile_id -> rounds)
var _stores: Dictionary = {}


## Grants [param rounds] of [param projectile_id] to an Assembly, adding to
## whatever it already had.
##
## [constant UNLIMITED] replaces rather than adds — an unlimited store plus
## twenty rounds is still unlimited, and adding to the sentinel would quietly
## turn it into a finite store of nineteen.
func add(assembly_id: int, projectile_id: int, rounds: int) -> void:
	var store: Dictionary = _stores.get(assembly_id, {})
	if rounds == UNLIMITED or int(store.get(projectile_id, 0)) == UNLIMITED:
		store[projectile_id] = UNLIMITED
	else:
		store[projectile_id] = int(store.get(projectile_id, 0)) + rounds
	_stores[assembly_id] = store


func has_rounds(assembly_id: int, projectile_id: int) -> bool:
	var store: Dictionary = _stores.get(assembly_id, {})
	var held := int(store.get(projectile_id, 0))
	return held == UNLIMITED or held > 0


## Removes [param rounds] and returns how many were actually taken.
##
## Returns the shortfall rather than refusing outright, so a burst that runs the
## store dry mid-way fires what it has instead of nothing at all.
func consume(assembly_id: int, projectile_id: int, rounds: int) -> int:
	var store: Dictionary = _stores.get(assembly_id, {})
	var held := int(store.get(projectile_id, 0))
	if held == UNLIMITED:
		return rounds
	var taken := mini(held, rounds)
	store[projectile_id] = held - taken
	_stores[assembly_id] = store
	return taken


func rounds_stored(assembly_id: int, projectile_id: int) -> int:
	return int((_stores.get(assembly_id, {}) as Dictionary).get(projectile_id, 0))


## Drops every store for an Assembly that has left the match.
##
## Without this the ledger is the one structure in the combat layer that grows
## for the life of the process: ids are never reused, so a long server session
## would accumulate an entry per Assembly ever spawned.
func forget(assembly_id: int) -> void:
	_stores.erase(assembly_id)


## Assembly ids holding a store, ascending. Determinism (Invariant I-9) and
## diagnostics; nothing in the firing path iterates this.
func assembly_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for key: int in _stores.keys():
		out.append(key)
	out.sort()
	return out
