extends TestCase
## [DebrisPool] and [DebrisReaper] — the debris budget of doc 04 §6.2 and the
## bound Architectural Invariant I-12 puts on it.
##
## Both classes exist to make destruction cost a fixed amount. A pool that
## allocated on demand, or a reaper that let bodies accumulate, would turn the
## worst tick in a match — a multi-Assembly detonation shedding dozens of islands
## at once — into the tick that also allocates and also grows the contact set.
## The assertions here are therefore about counts and identity rather than about
## the debris looking right.
##
## The reaper is driven through [method DebrisReaper.sweep] with an explicit tick
## rather than by waiting on the clock. That is not a shortcut around the event
## contract — [method DebrisReaper._on_tick_started] does nothing else — it is the
## only way to observe a 22 s lifetime without a 22 s test.

const LIFETIME_S := IslandDetacher.DEBRIS_LIFETIME_S
const FREEZE_TICKS := 240  # 4.0 s at 60 Hz; DebrisReaper.FREEZE_AFTER_ASLEEP_S

var _pools: Array[DebrisPool] = []


func after_all() -> void:
	# A pool left in the tree keeps ninety-six bodies alive and its reaper
	# connected to the clock, and the next file's sweep would then run over them.
	for pool in _pools:
		pool.free()
	_pools.clear()


## ===== §6.2 BUDGET =====================================================


func test_the_pool_allocates_its_whole_budget_up_front() -> void:
	# Ninety-six is Architectural Invariant I-12's number. Allocating them at
	# construction is what makes acquire() constant time on the worst tick.
	var pool := _pool()
	check_eq(pool.free_count(), DebrisPool.POOL_SIZE, "every body exists before the first island")
	check_eq(pool.active_count(), 0, "and none of them is in flight")
	check_eq(DebrisPool.POOL_SIZE, 96, "the budget is I-12's ninety-six")


func test_an_acquired_body_is_configured_for_the_debris_layer() -> void:
	var pool := _pool()
	var body := pool.acquire()

	check_eq(pool.active_count(), 1, "the body is in flight")
	check_eq(pool.free_count(), DebrisPool.POOL_SIZE - 1, "and out of the free list")
	check_eq(body.collision_layer, CollisionLayers.LAYER_DEBRIS, "debris occupies its own layer")
	check_eq(
		body.collision_mask & CollisionLayers.LAYER_DEBRIS, 0,
		"and never collides with debris — §6.1's contact-pair simplification"
	)
	check_true(
		(body.collision_mask & CollisionLayers.LAYER_GROUND) != 0, "it does collide with the ground"
	)
	check_false(body.freeze, "it is simulated")
	check_true(body.can_sleep, "and allowed to settle")
	check_approx(body.linear_damp, DebrisPool.DEBRIS_LINEAR_DAMP, "§6.2's linear damping")
	check_approx(body.angular_damp, DebrisPool.DEBRIS_ANGULAR_DAMP, "§6.2's angular damping")


func test_a_released_body_is_out_of_the_simulation_entirely() -> void:
	# Freezing alone is not enough: a frozen body is a static obstacle, and
	# ninety-six invisible walls at the origin is a collision bug nobody would
	# think to look for in a pool.
	var pool := _pool()
	var body := pool.acquire()
	body.adopt_shape(BoxShape3D.new(), Transform3D())
	pool.release(body)

	check_eq(pool.active_count(), 0, "the body left the in-flight list")
	check_eq(pool.free_count(), DebrisPool.POOL_SIZE, "and rejoined the free one")
	check_eq(body.collision_layer, 0, "it occupies no layer")
	check_eq(body.collision_mask, 0, "and queries nothing")
	check_true(body.freeze, "it is out of the solver")
	check_eq(body.active_shape_count(), 0, "its geometry is gone")
	check_eq(body.slots, PackedByteArray(), "and so is its slot list")


func test_releasing_a_free_body_is_not_an_error() -> void:
	# The reaper and the recycling path can both reach the same body in one
	# sweep. A double release that corrupted the free list would hand the same
	# body out twice, which is two islands sharing one set of colliders.
	var pool := _pool()
	var body := pool.acquire()
	pool.release(body)
	pool.release(body)
	check_eq(pool.free_count(), DebrisPool.POOL_SIZE, "the free list did not gain a duplicate")
	check_eq(pool.active_count(), 0, "and the in-flight list is still empty")


func test_exhausting_the_pool_recycles_the_oldest_body() -> void:
	# §6.2. Losing the oldest wreck is a visual regression; refusing the newest
	# island is a part of an Assembly that visibly ceases to exist at the instant
	# it is destroyed, which is far worse.
	var pool := _pool()
	var first: DebrisBodyRef = null
	var second: DebrisBodyRef = null
	for i in DebrisPool.POOL_SIZE:
		var body := pool.acquire()
		if i == 0:
			first = body
		elif i == 1:
			second = body
	check_eq(pool.free_count(), 0, "the pool is exhausted")

	var recycled := pool.acquire()
	check_eq(recycled, first, "the oldest body in flight is the one reused")
	check_eq(pool.active_count(), DebrisPool.POOL_SIZE, "the budget is still the budget")
	check_eq(pool.free_count(), 0, "and nothing was allocated to serve the request")

	var next := pool.acquire()
	check_eq(next, second, "the next request takes the next oldest, not the same one again")


func test_shape_nodes_are_reused_rather_than_reallocated() -> void:
	# Freeing a CollisionShape3D would mean removing a node from a body inside a
	# physics callback, and would leave the recycling path above handing out a
	# body still carrying the last island's geometry for the rest of the frame.
	var pool := _pool()
	var body := pool.acquire()
	body.adopt_shape(BoxShape3D.new(), Transform3D())
	body.adopt_shape(BoxShape3D.new(), Transform3D())
	body.adopt_shape(BoxShape3D.new(), Transform3D())
	check_eq(body.allocated_shape_count(), 3, "three nodes were built for a three-part island")
	check_eq(
		PhysicsServer3D.body_get_shape_count(body.get_rid()), 3, "and the server holds all three"
	)

	pool.release(body)
	var again := pool.acquire()
	check_eq(again, body, "the same body comes back")
	again.adopt_shape(BoxShape3D.new(), Transform3D())

	check_eq(again.allocated_shape_count(), 3, "no node was freed and none was added")
	check_eq(again.active_shape_count(), 1, "but only the new island's shape is live")
	var live := 0
	for child in again.get_children():
		var cs := child as CollisionShape3D
		if cs != null and not cs.disabled:
			live += 1
	check_eq(live, 1, "the other two are disabled, not merely forgotten")


## ===== §6.2 REAPING ====================================================


func test_a_body_is_released_when_its_lifetime_expires() -> void:
	var pool := _pool()
	var body := pool.acquire()
	var start := MatchClock.tick
	pool.reaper.schedule(body, LIFETIME_S)

	var expected := start + MatchClockService.ticks_for_seconds(LIFETIME_S)
	check_eq(body.expires_at_tick, expected, "22 s is 1320 ticks, counted rather than accumulated")

	pool.reaper.sweep(expected - 1)
	check_eq(pool.active_count(), 1, "the tick before, the body is still there")
	pool.reaper.sweep(expected)
	check_eq(pool.active_count(), 0, "and on the deadline it goes back to the pool")
	check_eq(pool.free_count(), DebrisPool.POOL_SIZE, "the budget is whole again")


func test_a_recycled_body_does_not_inherit_the_last_islands_deadline() -> void:
	# A body between acquisition and scheduling must not be swept away by a tick
	# landing in between, and the deadline it carried last time round is exactly
	# the value that would do it — the reaper would release a body §6 is still in
	# the middle of loading colliders onto.
	var pool := _pool()
	var used := pool.acquire()
	pool.reaper.schedule(used, LIFETIME_S)
	var stale := used.expires_at_tick
	pool.release(used)

	var body := pool.acquire()
	check_eq(body, used, "the same body comes back")
	check_eq(body.expires_at_tick, DebrisBodyRef.INVALID_TICK, "with no deadline on it")
	pool.reaper.sweep(stale)
	check_eq(pool.active_count(), 1, "so the old deadline passing does not reap it")
	pool.reaper.sweep(MatchClock.tick + 100000)
	check_eq(pool.active_count(), 1, "and no deadline at all means no reaping, ever")


func test_a_body_asleep_for_four_seconds_is_frozen_out_of_the_solver() -> void:
	var pool := _pool()
	var body := pool.acquire()
	var start := MatchClock.tick
	pool.reaper.schedule(body, LIFETIME_S)

	body.sleeping = true
	pool.reaper.sweep(start)
	check_eq(body.asleep_since_tick, start, "the first sleeping tick is recorded")
	pool.reaper.sweep(start + FREEZE_TICKS - 1)
	check_false(body.freeze, "a tick short of four seconds, it is still simulated")
	pool.reaper.sweep(start + FREEZE_TICKS)
	check_true(body.freeze, "at four seconds it leaves the solver")
	check_eq(
		body.freeze_mode, RigidBody3D.FREEZE_MODE_STATIC,
		"as a static body, so it stays exactly where it came to rest"
	)
	check_eq(pool.active_count(), 1, "frozen is not reaped; it stays visible until its lifetime")


func test_waking_restarts_the_sleep_accumulator() -> void:
	# Without the reset a body nudged awake at 3.9 s would freeze mid-roll on its
	# next sleeping tick, which reads as debris hitting an invisible wall.
	var pool := _pool()
	var body := pool.acquire()
	var start := MatchClock.tick
	pool.reaper.schedule(body, LIFETIME_S)

	body.sleeping = true
	pool.reaper.sweep(start)
	body.sleeping = false
	pool.reaper.sweep(start + 1)
	check_eq(body.asleep_since_tick, DebrisBodyRef.INVALID_TICK, "the accumulator is cleared")

	body.sleeping = true
	pool.reaper.sweep(start + 2)
	pool.reaper.sweep(start + FREEZE_TICKS)
	check_false(body.freeze, "the four seconds are counted from the second time it settled")
	pool.reaper.sweep(start + 2 + FREEZE_TICKS)
	check_true(body.freeze, "and it freezes four seconds after that")


func test_an_idle_reaper_touches_nothing() -> void:
	# The overwhelmingly common path: a match in which nothing has been destroyed
	# has no debris, and this must cost one emptiness test per tick.
	var pool := _pool()
	pool.reaper.sweep(MatchClock.tick)
	check_eq(pool.active_count(), 0, "no bodies in flight")
	check_eq(pool.free_count(), DebrisPool.POOL_SIZE, "and none disturbed")


func test_the_freeze_constant_matches_the_tick_count_asserted_above() -> void:
	# FREEZE_TICKS is written out as a number so the tests above read as tick
	# arithmetic. This is what keeps it honest if §6.2's four seconds ever change.
	check_eq(
		MatchClockService.ticks_for_seconds(DebrisReaper.FREEZE_AFTER_ASLEEP_S), FREEZE_TICKS,
		"§6.2's four-second freeze delay in ticks"
	)


## ===== FIXTURES ========================================================


func _pool() -> DebrisPool:
	var pool := DebrisPool.new()
	_pools.append(pool)
	# Shapes register with the server only once the body is really in a tree, and
	# the reaper's clock connection is made in _ready.
	EventBus.get_tree().root.add_child(pool)
	return pool
