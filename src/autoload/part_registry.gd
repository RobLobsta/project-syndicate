class_name PartRegistryService
extends Node
## Autoload: [code]PartRegistry[/code]. The immutable part definition registry,
## owned by [code]docs/PART_DATA_SCHEMA.md[/code] §5.3.
##
## Architectural Invariant I-11: immutable after [method _ready]. All accessors
## are O(1) and allocation-free.
##
## Any subsystem needing a part attribute resolves it through here. This is what
## eliminates stat drift — the failure mode where the garage UI, the physics
## solver, and the damage model each read from divergent copies of the same
## number.

const MANIFEST_PATH: String = "res://data/parts/registry_manifest.tres"

## Emitted once the registry is populated and sealed. Systems that need part
## data at startup wait on this rather than on tree order.
signal registry_ready

var _by_id: Array[PartDefinition] = []
var _by_key: Dictionary = {}  # StringName -> PartDefinition
var _by_class: Array[PackedInt32Array] = []
var _manifest_hash: int = 0
var _sealed: bool = false


func _ready() -> void:
	_by_class.resize(PartEnums.PART_CLASS_COUNT)
	for i in PartEnums.PART_CLASS_COUNT:
		_by_class[i] = PackedInt32Array()

	var manifest: PartManifest = load(MANIFEST_PATH) as PartManifest
	if manifest == null:
		push_error("PartRegistry: manifest missing or malformed at %s" % MANIFEST_PATH)
		_by_id.resize(1)
		_seal()
		return

	_by_id.resize(manifest.keys.size() + 1)
	_by_id[0] = null  # PartManifest.INVALID_PART_ID
	for i in manifest.keys.size():
		var key := StringName(manifest.keys[i])
		var path := _path_for_key(key)
		var def: PartDefinition = load(path) as PartDefinition
		if def == null:
			push_error("PartRegistry: manifest entry %d ('%s') has no definition at %s"
					% [i, key, path])
			continue
		if def.part_key != key:
			push_error("PartRegistry: '%s' declares part_key '%s'" % [path, def.part_key])
			continue
		def._bind_runtime_id(i + 1)
		def._bake_derived_fields()
		_by_id[i + 1] = def
		_by_key[key] = def
		_by_class[int(def.part_class)].push_back(i + 1)

	_manifest_hash = manifest.compute_content_hash()
	_seal()


## Definition for a part id, or null for [constant PartManifest.INVALID_PART_ID]
## and for any id outside the registry.
func definition(part_def_id: int) -> PartDefinition:
	if part_def_id <= 0 or part_def_id >= _by_id.size():
		return null
	return _by_id[part_def_id]


func definition_by_key(key: StringName) -> PartDefinition:
	return _by_key.get(key, null)


func has_key(key: StringName) -> bool:
	return _by_key.has(key)


## Ids of every registered part of a class, in manifest order.
func ids_of_class(part_class: int) -> PackedInt32Array:
	if part_class < 0 or part_class >= _by_class.size():
		return PackedInt32Array()
	return _by_class[part_class]


## Number of registered parts, excluding the reserved invalid id.
func part_count() -> int:
	return maxi(0, _by_id.size() - 1)


## Transmitted in the network handshake. A client/server mismatch aborts the
## connection with ERR_INCOMPATIBLE_CONTENT rather than allowing silent
## desynchronisation of damage numbers.
func manifest_hash() -> int:
	return _manifest_hash


func is_sealed() -> bool:
	return _sealed


func _seal() -> void:
	_sealed = true
	registry_ready.emit()


func _path_for_key(key: StringName) -> String:
	return PartManifest.definition_path(key)
