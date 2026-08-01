class_name AssemblyRegistry
extends RefCounted
## The directory of live Assemblies: assembly id -> [AssemblyRuntime].
##
## Four documents assume a lookup of this shape —
## [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code] §5.1 and §5.3 resolve a damage
## packet's target, [code]docs/HEADLESS_NETWORK_SYNC.md[/code] §7.2 resolves a
## body to rewind, and [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §6 resolves the
## Assembly an island came off — and until this existed each of them would have
## had to invent its own map. Two already had:
## [DetachmentScheduler] and [MassRecomputeScheduler] each kept one.
##
## [b]Amendment to §5.3 of doc 08 and §7.2 of doc 12.[/b] Both call
## [code]AssemblyRegistry.get(aid)[/code], as though this were a global.
## CLAUDE.md §4 freezes the autoload list at eight, and a [code]static var[/code]
## holding the same dictionary would be that global with less of the visibility
## that makes an autoload reviewable. This is therefore an ordinary object owned
## by the match scene and handed to the systems that need it — the same shape
## [DebrisPool] took, and for the same reason. Both documents record it.
##
## Architectural Invariant I-9: [method ids] is ascending, so every sweep built
## on it is reproducible. A raw [method Dictionary.keys] is not, and a blast that
## touches three Assemblies resolves them in that order (doc 08 §5.3).

## An Assembly entered the match. Carries the id rather than the runtime so a
## consumer that only tracks ids does not have to hold a node reference.
signal assembly_registered(assembly_id: int)
## An Assembly left it. Emitted [i]before[/i] the entry is dropped, so a handler
## can still resolve the runtime it is cleaning up after.
signal assembly_unregistered(assembly_id: int)

var _by_id: Dictionary = {}
## Registered ids, ascending. Maintained on every edit rather than sorted on
## demand: the list is at most sixteen long, and keeping it ordered at all times
## means no caller can observe an unordered one.
var _ids: PackedInt32Array = PackedInt32Array()


## Adds [param runtime] under its own [member AssemblyRuntime.assembly_id].
##
## The id comes off the runtime rather than being passed alongside it, because
## the runtime already carries it — on its body, where a physics query finds it
## — and a second copy is a second chance to disagree about who just took a hit.
func register(runtime: AssemblyRuntime) -> void:
	assert(runtime != null, "registering a null AssemblyRuntime")
	var assembly_id := runtime.assembly_id
	assert(not _by_id.has(assembly_id), "assembly %d registered twice" % assembly_id)
	_by_id[assembly_id] = runtime
	_insert_id(assembly_id)
	assembly_registered.emit(assembly_id)


func unregister(assembly_id: int) -> void:
	if not _by_id.has(assembly_id):
		return
	assembly_unregistered.emit(assembly_id)
	_by_id.erase(assembly_id)
	var at := _ids.find(assembly_id)
	if at != -1:
		_ids.remove_at(at)


## The runtime for [param assembly_id], or [code]null[/code].
##
## Named [code]get_runtime[/code] rather than the documents' [code]get[/code]:
## [method Object.get] already exists and shadowing it on a [RefCounted] would
## make every property read on this object go somewhere surprising.
func get_runtime(assembly_id: int) -> AssemblyRuntime:
	return _by_id.get(assembly_id)


## The Chassis Graph of [param assembly_id], or [code]null[/code]. The graph is
## what the structural systems actually want, and routing them through here keeps
## them from holding a runtime reference they would otherwise have no use for.
func graph_of(assembly_id: int) -> ChassisGraph:
	var runtime: AssemblyRuntime = _by_id.get(assembly_id)
	return null if runtime == null else runtime.graph


func has(assembly_id: int) -> bool:
	return _by_id.has(assembly_id)


## Every registered id, ascending (Architectural Invariant I-9). A copy: a caller
## must not be able to change what the next sweep iterates.
func ids() -> PackedInt32Array:
	return _ids.duplicate()


func count() -> int:
	return _ids.size()


func _insert_id(assembly_id: int) -> void:
	for i in _ids.size():
		if _ids[i] > assembly_id:
			_ids.insert(i, assembly_id)
			return
	_ids.append(assembly_id)
