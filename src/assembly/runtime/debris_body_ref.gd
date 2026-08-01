class_name DebrisBodyRef
extends RigidBody3D
## One pooled debris body: a severed island living on as an independent
## [RigidBody3D], per [code]docs/DEPENDENCY_TREE_GRAPH.md[/code] §6.
##
## Architectural Invariant I-1 survives detachment. Every shape below is one of
## the parent Assembly's authored [ColliderPrimitiveDef] primitives, re-registered
## here with its transform rebased onto the island's centre of mass. Nothing is
## generated from a mesh, nothing is convex-decomposed, and the [Shape3D]
## resources are shared with the Assembly rather than rebuilt — §6.1's "the same
## authored primitives", taken literally.
##
## [b]Shapes are reused, never freed.[/b] A body returning to the pool disables
## its shapes and rewinds [method reset_shapes]; the next island overwrites them
## in place. Freeing them instead would mean removing [CollisionShape3D] nodes
## from a body inside a physics callback — the reaper runs on
## [signal MatchClockService.tick_started] — and would leave the recycling path
## of §6.2 handing out a body whose old geometry is still on it for the rest of
## the frame.
##
## The two tick fields are the reaper's whole state, and they live here rather
## than in a parallel list on [DebrisReaper] so that recycling a body cannot
## leave a timer pointing at the one that replaced it.

const INVALID_TICK: int = -1

## Assembly this island came off, for [signal EventBusService.island_detached]
## consumers and for diagnostics. Debris takes no further part in that Assembly.
var source_assembly_id: int = 0
## Slots this body carries, ascending. Replicated with the detachment event.
var slots: PackedByteArray = PackedByteArray()

## Tick at which [DebrisReaper] returns this body to the pool.
##
## A tick rather than a float countdown: 22 s is 1320 subtractions of
## [constant SyndicateConstants.PHYSICS_DT], which does not land on zero, and the
## tick a body disappears on is replicated. Integers cannot drift.
var expires_at_tick: int = INVALID_TICK
## First tick this body was observed asleep, or [constant INVALID_TICK] while it
## is awake.
var asleep_since_tick: int = INVALID_TICK

## Every [CollisionShape3D] ever built on this body, in assignment order.
var _shapes: Array[CollisionShape3D] = []
## How many of them the current island uses. Entries at or above it are disabled.
var _used: int = 0


## Disables every shape and rewinds the write cursor, so the next island starts
## from an empty body without a single node being removed from it.
func reset_shapes() -> void:
	for node in _shapes:
		node.disabled = true
	_used = 0


## Registers [param shape] at [param local] on this body.
##
## The shape resource is shared with the Assembly that authored it, not copied:
## a [Shape3D] is immutable in practice here — it comes from an authored
## primitive and nothing writes to it — and building a second one per detachment
## would allocate on the destruction path §6 is meant to keep cheap.
func adopt_shape(shape: Shape3D, local: Transform3D) -> void:
	if shape == null:
		push_error("DebrisBodyRef: adopt of a null shape on assembly %d" % source_assembly_id)
		return
	var node: CollisionShape3D = null
	if _used < _shapes.size():
		node = _shapes[_used]
	else:
		node = CollisionShape3D.new()
		node.name = "debris_shape_%03d" % _shapes.size()
		_shapes.append(node)
		add_child(node)
	node.shape = shape
	node.transform = local
	node.disabled = false
	_used += 1


## Shapes the current island occupies. Diagnostics and tests.
func active_shape_count() -> int:
	return _used


## Shapes ever built on this body, disabled or not. Diagnostics and tests; it
## only ever grows, which is what makes the reuse above safe.
func allocated_shape_count() -> int:
	return _shapes.size()
