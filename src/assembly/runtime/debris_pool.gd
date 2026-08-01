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

## Resolves the assembly id [DetachmentScheduler] announces an island with.
## Assigned by the match scene before this node enters the tree.
var registry: AssemblyRegistry = null

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
		_quiesce(body)
		_free.append(body)

	reaper = DebrisReaper.new()
	reaper.name = "DebrisReaper"
	reaper.pool = self
	add_child(reaper)


## [member DetachmentScheduler.island_sink] in its production form.
##
## The seam §6 leaves open is exactly one lookup wide: the scheduler knows which
## Assembly shed the island and [IslandDetacher] needs the runtime that owns it.
## Assign this as the sink and the two halves of detachment are connected.
func on_island_severed(assembly_id: int, island: PackedByteArray) -> void:
	var runtime := registry.get_runtime(assembly_id)
	if runtime == null:
		# Structural loss is authoritative and has already happened; the debris is
		# what is missing. Worth an error, not worth failing the tick over.
		push_error("DebrisPool: island from unregistered assembly %d" % assembly_id)
		return
	IslandDetacher.detach(runtime, island, self)


## Hands out a body ready to take an island's geometry, per §6.2.
##
## When the pool is exhausted the oldest body in flight is recycled immediately
## rather than the new island being refused. Losing the oldest wreck is a visual
## regression; refusing the newest is a part of an Assembly that visibly ceases
## to exist at the moment it is destroyed.
func acquire() -> DebrisBodyRef:
	if _free.is_empty():
		release(_oldest_evictable())
	var body: DebrisBodyRef = _free.pop_front()
	_in_use.append(body)

	# [method release] makes a body inert; this is where it is given a fresh life,
	# and the split is one owner each. A body carrying the last island's deadline
	# would be retired by the reaper's very next sweep, in the middle of §6
	# loading colliders onto it, and one still marked retired would never be an
	# obstacle at all — the island it carries would be geometry the world drives
	# straight through.
	body.expires_at_tick = DebrisBodyRef.INVALID_TICK
	body.linger_deadline_tick = DebrisBodyRef.INVALID_TICK
	body.retired = false
	# The other two tick fields are not cleared here, and neither is redundant for
	# it: [member DebrisBodyRef.asleep_since_tick] is reset by the first sweep
	# that sees the body awake, and [member DebrisBodyRef.offscreen_since_tick] by
	# the first that sees it on a screen. See both declarations.
	body.freeze = false
	body.sleeping = false
	body.can_sleep = true
	body.linear_damp = DEBRIS_LINEAR_DAMP
	body.angular_damp = DEBRIS_ANGULAR_DAMP
	body.collision_layer = CollisionLayers.LAYER_DEBRIS
	body.collision_mask = CollisionLayers.MASK_DEBRIS
	return body


## Ends [param body]'s simulated life while keeping it in the world to be looked
## at, per §6.2's amendment. It stops being an obstacle here and nowhere else.
##
## This is the tick §6 scheduled, and it is deterministic: the body leaves the
## simulation on the same tick on the server and on every client, whatever any
## camera happens to be pointing at. Everything after it is presentation.
func retire(body: DebrisBodyRef, linger_deadline_tick: int) -> void:
	if body.retired:
		return
	_quiesce(body)
	body.retired = true
	body.linger_deadline_tick = linger_deadline_tick


## Returns [param body] to the pool, inert and carrying nothing. Safe to call on
## a body already free.
##
## This makes the body harmless where it stands; [method acquire] is what gives
## the next one a clean life. Resetting the tick fields here as well would leave
## neither place load-bearing.
func release(body: DebrisBodyRef) -> void:
	var at := _in_use.find(body)
	if at == -1:
		return
	_in_use.remove_at(at)
	body.reset_shapes()
	body.slots = PackedByteArray()
	body.source_assembly_id = 0
	_quiesce(body)
	_free.push_front(body)


## Bodies currently in flight, oldest first, simulated and retired alike. A copy,
## because [DebrisReaper] releases while it iterates.
func in_flight_bodies() -> Array[DebrisBodyRef]:
	return _in_use.duplicate()


func in_flight_count() -> int:
	return _in_use.size()


## Bodies that are still obstacles. This is the count that is identical on the
## server and on every client; [method retired_count] is not, and nothing
## simulated may depend on it.
func simulated_count() -> int:
	var n := 0
	for body in _in_use:
		if not body.retired:
			n += 1
	return n


func retired_count() -> int:
	return _in_use.size() - simulated_count()


func free_count() -> int:
	return _free.size()


## The body to sacrifice when the pool is exhausted.
##
## A retired body is presentation with no simulated consequence, so it always
## goes before one that is still an obstacle. That ordering is what keeps the
## simulated set — which is deterministic, and which the server and every client
## agree on — from being squeezed by how long one player happened to look at a
## wreck. Only when all ninety-six are still obstacles is a live one taken, and
## that condition is reached at the same moment everywhere.
func _oldest_evictable() -> DebrisBodyRef:
	for body in _in_use:
		if body.retired:
			return body
	return _in_use[0]


## Takes a body out of the simulation without freeing it or returning it to the
## pool. Shared by retirement and release, so "out of the simulation" has exactly
## one definition.
##
## Layer and mask are cleared as well as the freeze: a frozen body is still a
## static obstacle, and ninety-six invisible walls stacked at the origin would
## be a very hard collision bug to find.
func _quiesce(body: DebrisBodyRef) -> void:
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
