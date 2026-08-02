class_name ProjectileRegistry
extends RefCounted
## Immutable lookup from a projectile key to its definition, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §12.
##
## Deliberately [b]not[/b] an autoload. CLAUDE.md §4 freezes that list at eight
## and the bar for adding one is a permanent increase in coupling; a projectile
## table is read by exactly two classes ([EffectorSystem] and
## [ProjectileSystem]), both of which are constructed by the match scene, so it
## is handed to them the way [AssemblyRegistry] is.
##
## Definitions are addressed by a small integer at runtime, never by key. The
## key is authoring vocabulary; the id is what a pool array holds and what a
## snapshot quantises, and resolving a [StringName] per projectile per tick would
## put a hash in the hottest loop in the combat layer.

## Definitions in registration order. The index is the id.
var _definitions: Array[ProjectileDefinition] = []
var _id_by_key: Dictionary = {}
var _sealed: bool = false


## Registers [param def] and returns its id.
##
## Append-only, exactly as the part manifest is: an id is written into snapshots
## and a reorder would repoint every projectile in flight on every client.
func register(def: ProjectileDefinition) -> int:
	if _sealed:
		push_error("ProjectileRegistry: register after seal for '%s'" % def.projectile_key)
		return -1
	if def == null:
		push_error("ProjectileRegistry: refusing to register a null definition")
		return -1
	if _id_by_key.has(def.projectile_key):
		push_error("ProjectileRegistry: duplicate key '%s'" % def.projectile_key)
		return int(_id_by_key[def.projectile_key])
	var id := _definitions.size()
	_definitions.append(def)
	_id_by_key[def.projectile_key] = id
	return id


## Closes the registry. Every read path assumes the table cannot move under it.
func seal() -> void:
	_sealed = true


func definition(id: int) -> ProjectileDefinition:
	if id < 0 or id >= _definitions.size():
		return null
	return _definitions[id]


func id_of(key: StringName) -> int:
	return int(_id_by_key.get(key, -1))


func definition_by_key(key: StringName) -> ProjectileDefinition:
	return definition(id_of(key))


func count() -> int:
	return _definitions.size()


func is_sealed() -> bool:
	return _sealed
