class_name DebrisPool
extends Node
## The fixed pool of debris bodies of
## [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §6.2, and the bound Architectural
## Invariant I-12 puts on it.
##
## Ninety-six bodies are allocated once and never freed. A destruction event
## cannot therefore allocate: [method acquire] either hands back a free body or
## recycles the oldest one in flight, and both are constant time. That matters
## because the worst case for this pool — a multi-Assembly detonation shedding
## dozens of islands in one tick — is exactly the tick with the least budget to
## spare.
##
## [b]Amendment to §6.2.[/b] The document calls [code]DebrisPool.acquire()[/code]
## as though the pool were a global. CLAUDE.md §4 freezes the autoload list at
## eight, so this is an ordinary [Node] owned by the match scene and passed to
## [code]IslandDetacher.detach[/code]. §6.2 records the signature.
##
## Architectural Invariant I-4: nothing here polls. The pool is woken by
## [method acquire] and by [DebrisReaper], which it owns and which is itself
## driven by the tick.

## §6.2, and Architectural Invariant I-12's debris bound. Frozen: the contact
## pair count during a large destruction event is what it protects.
const POOL_SIZE: int = 96

## §6.2's sleep settings. Debris exists to be seen coming to rest, not to roll
## for a minute, so it is damped hard and allowed to sleep aggressively.
const DEBRIS_LINEAR_DAMP: float = 0.35
const DEBRIS_ANGULAR_DAMP: float = 0.55

## Reaps expired bodies and freezes settled ones. Owned here rather than by the
## match scene because its whole job is the other half of this pool's lifecycle,
## and a reaper pointed at no pool is not a meaningful object.
var reaper: DebrisReaper = null

## Every body, in construction order. Never resized after [method _ready].
var _bodies: Array[DebrisBodyRef] = []
## Available bodies, most recently released first. A stack rather than a queue:
## the body that just came back already carries shape nodes sized for an island
## of roughly the same shape, so reusing it immediately is the one ordering that
## costs nothing.
var _free: Array[DebrisBodyRef] = []
## Bodies in flight, in acquisition order — so element 0 is the oldest, which is
## the one §6.2 recycles when the pool is exhausted.
var _in_use: Array[DebrisBodyRef] = []


func _ready() -> void:
	for i in POOL_SIZE:
		var body := DebrisBodyRef.new()
		body.name = "Debris%03d" % i
		add_child(body)
		_bodies.append(body)
		_park(body)
		_free.append(body)

	reaper = DebrisReaper.new()
	reaper.name = "DebrisReaper"
	reaper.pool = self
	add_child(reaper)


## Hands out a body ready to take an island's geometry, per §6.2.
##
## When the pool is exhausted the oldest body in flight is recycled immediately
## rather than the new island being refused. Losing the oldest wreck is a visual
## regression; refusing the newest is a part of an Assembly that visibly ceases
## to exist at the moment it is destroyed.
func acquire() -> DebrisBodyRef:
	if _free.is_empty():
		release(_in_use[0])
	var body: DebrisBodyRef = _free.pop_front()
	_in_use.append(body)

	# The deadline is cleared here and nowhere else. A body carrying the last
	# island's deadline would be released by the reaper's very next sweep, in the
	# middle of §6 loading colliders onto it.
	body.expires_at_tick = DebrisBodyRef.INVALID_TICK
	# [member DebrisBodyRef.asleep_since_tick] deliberately is not: waking the
	# body is what resets it, and [method DebrisReaper.sweep] does that on the
	# first tick after acquisition, before anything can read the stale value.
	body.freeze = false
	body.sleeping = false
	body.can_sleep = true
	body.linear_damp = DEBRIS_LINEAR_DAMP
	body.angular_damp = DEBRIS_ANGULAR_DAMP
	body.collision_layer = CollisionLayers.LAYER_DEBRIS
	body.collision_mask = CollisionLayers.MASK_DEBRIS
	return body


## Returns [param body] to the pool. Safe to call on a body already free.
func release(body: DebrisBodyRef) -> void:
	var at := _in_use.find(body)
	if at == -1:
		return
	_in_use.remove_at(at)
	body.reset_shapes()
	body.slots = PackedByteArray()
	body.source_assembly_id = 0
	_park(body)
	_free.push_front(body)


## Bodies currently in flight, oldest first. A copy, because [DebrisReaper]
## releases while it iterates.
func active_bodies() -> Array[DebrisBodyRef]:
	return _in_use.duplicate()


func active_count() -> int:
	return _in_use.size()


func free_count() -> int:
	return _free.size()


## Takes a body out of the simulation entirely without freeing it.
##
## Layer and mask are cleared as well as the freeze: a frozen body is still a
## static obstacle, and ninety-six invisible walls stacked at the origin would
## be a very hard collision bug to find.
func _park(body: DebrisBodyRef) -> void:
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
