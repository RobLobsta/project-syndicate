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
## [b]A body has two lives, not one.[/b] It is [i]simulated[/i] until
## [member expires_at_tick] — an obstacle, on [constant CollisionLayers.LAYER_DEBRIS],
## for exactly the number of ticks §6 scheduled and no more. It is then
## [member retired]: out of the simulation entirely, and kept only so that a
## player watching it does not see it blink out of the world. See
## [DebrisReaper] for why that split is the only way to have both.
##
## [b]Shapes are reused, never freed.[/b] A body returning to the pool disables
## its shapes and rewinds [method reset_shapes]; the next island overwrites them
## in place. Freeing them instead would mean removing [CollisionShape3D] nodes
## from a body inside a physics callback — the reaper runs on
## [signal MatchClockService.tick_started] — and would leave the recycling path
## of §6.2 handing out a body whose old geometry is still on it for the rest of
## the frame.
##
## The tick fields are the reaper's whole state, and they live here rather than
## in a parallel list on [DebrisReaper] so that recycling a body cannot leave a
## timer pointing at the one that replaced it.

const INVALID_TICK: int = -1

## Subsystem tag gating the visibility notifier. A dedicated server disables it,
## no notifier is constructed, and a retired body is recycled at once — there is
## nobody to see it go. Doc 12 §9.2 gates at construction, not per frame.
const TAG_DEBRIS_VISIBILITY: StringName = &"debris_visibility"

## Assembly this island came off, for [signal EventBusService.island_detached]
## consumers and for diagnostics. Debris takes no further part in that Assembly.
var source_assembly_id: int = 0
## Slots this body carries, ascending. Replicated with the detachment event.
var slots: PackedByteArray = PackedByteArray()

## Tick at which this body stops being an obstacle.
##
## A tick rather than a float countdown: 22 s is 1320 subtractions of
## [constant SyndicateConstants.PHYSICS_DT], which does not land on zero, and the
## tick a body leaves the simulation is replicated. Integers cannot drift.
var expires_at_tick: int = INVALID_TICK

## True once the body has left the simulation and exists only to be looked at.
var retired: bool = false
## Tick at which a retired body is recycled whether or not anyone is watching.
## Written by [method DebrisPool.retire]; the bound Architectural Invariant I-12
## wants on the lingering set.
var linger_deadline_tick: int = INVALID_TICK
## First tick a retired body was observed off every screen, or
## [constant INVALID_TICK] while it is still visible somewhere.
##
## Owned by the on-screen branch of [method DebrisReaper._sweep_retired] and
## reset nowhere else — not on acquire, not on retire. A value left over from a
## previous life can only be read by a body that retires off every screen, and
## the difference it makes there is that an unwatched wreck goes half a second
## early. Clearing it as well would mean two owners of one reset, of which only
## one can ever be the load-bearing half.
var offscreen_since_tick: int = INVALID_TICK

## First tick this body was observed asleep, or [constant INVALID_TICK] while it
## is awake.
var asleep_since_tick: int = INVALID_TICK

## Culling volume used to answer [method is_on_screen], or [code]null[/code] in a
## build with no viewers.
##
## It is a [VisualInstance3D] under a [PhysicsBody3D], which everywhere else in
## this project would be an Architectural Invariant I-1 violation. It is not one
## here: a notifier draws nothing and owns no geometry, it is a query volume the
## renderer already evaluates during culling, and nothing it reports is ever fed
## back into the simulation — [DebrisReaper] consults it only after the body has
## stopped being an obstacle.
var notifier: VisibleOnScreenNotifier3D = null

## Whether any camera currently sees [member notifier]'s bounds.
##
## Driven by the notifier's own enter/exit signals rather than read back from it
## each sweep. The renderer already knows the answer as a side effect of culling
## and says so twice per wreck — once when it appears and once when it goes —
## where polling would ask ninety-six times a tick for a value that changes
## perhaps twice in a body's whole life.
##
## Nothing resets it on recycle, deliberately: it is the notifier's to write, and
## a body is not read for visibility until it retires, twenty-two seconds and
## some thousands of rendered frames after it was acquired.
var _on_screen: bool = false

## Every [CollisionShape3D] ever built on this body, in assignment order.
var _shapes: Array[CollisionShape3D] = []
## How many of them the current island uses. Entries at or above it are disabled.
var _used: int = 0
## Bounds of the current island in body-local space, driving [member notifier].
var _bounds: AABB = AABB()
var _has_bounds: bool = false


func _init() -> void:
	if not SubsystemGate.is_enabled(TAG_DEBRIS_VISIBILITY):
		return
	notifier = VisibleOnScreenNotifier3D.new()
	notifier.name = "ScreenBounds"
	notifier.screen_entered.connect(_on_screen_entered)
	notifier.screen_exited.connect(_on_screen_exited)
	add_child(notifier)


## Disables every shape and rewinds the write cursor, so the next island starts
## from an empty body without a single node being removed from it.
func reset_shapes() -> void:
	for node in _shapes:
		node.disabled = true
	_used = 0
	_bounds = AABB()
	_has_bounds = false
	if notifier != null:
		notifier.aabb = AABB()


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
	_grow_bounds(shape, local)


## True in a build that can tell whether anything is looking at this body. False
## on a dedicated server, where the whole linger phase is skipped.
func tracks_visibility() -> bool:
	return notifier != null


## True while any camera in the world can see this body's bounds.
##
## False in a build with no notifier, which is the answer that matters: a
## dedicated server has no viewers, so nothing is ever kept alive for one.
func is_on_screen() -> bool:
	return _on_screen


func _on_screen_entered() -> void:
	_on_screen = true


func _on_screen_exited() -> void:
	_on_screen = false


## Bounds of the current island in body-local space. Diagnostics and tests.
func island_bounds() -> AABB:
	return _bounds


## Shapes the current island occupies. Diagnostics and tests.
func active_shape_count() -> int:
	return _used


## Shapes ever built on this body, disabled or not. Diagnostics and tests; it
## only ever grows, which is what makes the reuse above safe.
func allocated_shape_count() -> int:
	return _shapes.size()


## Expands [member _bounds] to contain [param shape] placed at [param local].
##
## The primitive is bounded by a sphere rather than by its own oriented box. For
## the axis-aligned box that most parts carry the two are the same thing — the
## radius below [i]is[/i] the box's half-diagonal — and for a rotated one the
## sphere is the tighter thing to compute, since the alternative is the absolute
## of a basis. Erring large is also the safe direction: it reports a wreck as
## visible slightly before it is, never slightly after.
func _grow_bounds(shape: Shape3D, local: Transform3D) -> void:
	var r := _bounding_radius(shape)
	var extent := Vector3(r, r, r)
	if not _has_bounds:
		_bounds = AABB(local.origin - extent, extent * 2.0)
		_has_bounds = true
	else:
		_bounds = _bounds.expand(local.origin - extent).expand(local.origin + extent)
	if notifier != null:
		notifier.aabb = _bounds


static func _bounding_radius(shape: Shape3D) -> float:
	if shape is BoxShape3D:
		return ((shape as BoxShape3D).size * 0.5).length()
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		# Godot's capsule height spans both caps, so half of it already reaches
		# the far pole and is never shorter than the radius.
		return maxf(cap.height * 0.5, cap.radius)
	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		return Vector2(cyl.radius, cyl.height * 0.5).length()
	push_error("DebrisBodyRef: unbounded shape type %s" % shape.get_class())
	return 0.0
