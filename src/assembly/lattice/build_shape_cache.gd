class_name BuildShapeCache
extends RefCounted
## Physics shape RIDs for [ColliderPrimitiveDef] instances, shared across every
## placement in one [BuildContext].
##
## The interpenetration query of [code]docs/GRID_SNAPPING_LOGIC.md[/code] §7.7
## needs a shape RID per candidate primitive, and the build proxies of §6.2 need
## the same RIDs again for every committed part. Creating them per query would
## allocate on the physics server on every cursor move; creating them per part
## would allocate one set per copy of a part the player places.
##
## Definitions are immutable after [code]PartRegistry._ready()[/code]
## (Architectural Invariant I-11), so a primitive's shape can never go stale and
## the cache never needs invalidating. It is keyed by the primitive resource's
## instance id, which is stable for the lifetime of the registry.
##
## Architectural Invariant I-1: every RID here comes from
## [method ColliderPrimitiveDef.build_shape] — an authored primitive. Nothing in
## this class can produce a shape from a mesh.

var _rids: Dictionary = {}  # int instance_id -> RID
## Shape resources kept alive for the cache's lifetime.
##
## A [Shape3D] owns its server RID and frees it on destruction, so caching the
## bare RID and letting the Resource fall out of scope leaves every entry
## dangling — and a query against a freed shape reports no hits, which reads
## exactly like a legal placement.
var _retained: Array[Shape3D] = []


## Shape RID for [param prim], created on first use.
func rid_for(prim: ColliderPrimitiveDef) -> RID:
	var key := prim.get_instance_id()
	var cached: RID = _rids.get(key, RID())
	if cached.is_valid():
		return cached

	var shape := prim.build_shape()
	if shape == null:
		push_error(
			"BuildShapeCache: ColliderPrimitiveDef kind %d built no shape" % int(prim.kind)
		)
		return RID()

	var rid := shape.get_rid()
	_rids[key] = rid
	_retained.append(shape)
	return rid


## Number of distinct primitives cached. Diagnostics and tests only.
func size() -> int:
	return _rids.size()


func clear() -> void:
	_rids.clear()
	_retained.clear()
