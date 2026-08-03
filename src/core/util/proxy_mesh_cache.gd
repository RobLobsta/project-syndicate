class_name ProxyMeshCache
extends RefCounted
## Shared stage-PROXY meshes, keyed by [code]part_def_id[/code], owned by
## [code]docs/EXTENSION_PIPELINE.md[/code] §2.1.
##
## Forty structural panels on one Assembly are forty [MeshInstance3D] nodes and
## [b]one[/b] [ArrayMesh]. Without this every panel would triangulate its own
## copy at spawn — a ten-Assembly match is several hundred needless
## triangulations in the same frame, which presents as a spawn hitch rather than
## as anything a profiler points at directly.
##
## A static cache rather than an autoload: CLAUDE.md §4 sets a deliberately high
## bar for a ninth global, and this needs no lifecycle, no signals, and no
## ordering against anything.
##
## Invariant I-11 is why the key is the definition id and not the definition: a
## [PartDefinition] is immutable after [code]PartRegistry._ready()[/code], so one
## id means one mesh for the life of the process, and there is no invalidation
## case to get wrong.

static var _meshes: Dictionary = {}


## The shared mesh for [param def], building it on first request. Null only when
## the part has neither proxy primitives nor a collider to mirror, which
## [ProxyMeshBuilder] has already reported.
static func get_or_build(def: PartDefinition) -> ArrayMesh:
	if def == null:
		return null
	var key := def.runtime_id
	if _meshes.has(key):
		return _meshes[key]
	var mesh := ProxyMeshBuilder.build(def)
	# Cached even when null. A part with no buildable proxy will not acquire one
	# by being asked twice, and a null entry is what stops every spawn of it
	# re-running the builder and re-emitting the same warning.
	_meshes[key] = mesh
	return mesh


## Number of definitions currently cached. Diagnostics and tests.
static func size() -> int:
	return _meshes.size()


## Drops every cached mesh. For tests, which must not carry one file's registry
## into the next.
static func clear() -> void:
	_meshes.clear()
