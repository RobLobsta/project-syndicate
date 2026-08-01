extends TestCase
## [DebrisPool] and [DebrisReaper] — the debris budget of doc 04 §6.2, the bound
## Architectural Invariant I-12 puts on it, and the two-phase life §6.2's
## amendment gives every wreck.
##
## Both classes exist to make destruction cost a fixed amount. A pool that
## allocated on demand, or a reaper that let bodies accumulate, would turn the
## worst tick in a match — a multi-Assembly detonation shedding dozens of islands
## at once — into the tick that also allocates and also grows the contact set.
## The assertions here are therefore about counts and identity rather than about
## the debris looking right.
##
## The one place looks do matter is retirement. A wreck must stop being an
## obstacle on a tick every machine agrees on, and must not blink out of the
## world while somebody is watching it, and those two requirements are only
## compatible because they are two different events. Every test below that
## mentions a screen is testing that split.
##
## The reaper is driven through [method DebrisReaper.sweep] with an explicit tick
## rather than by waiting on the clock. That is not a shortcut around the event
## contract — [method DebrisReaper._on_tick_started] does nothing else — it is the
## only way to observe a 22 s lifetime without a 22 s test. Visibility is driven
## by emitting the notifier's own [signal VisibleOnScreenNotifier3D.screen_entered]
## and [signal VisibleOnScreenNotifier3D.screen_exited], which is the identical
## path the renderer uses; nothing renders under `--headless`, so there is no
## other way to put a wreck on a screen.

const LIFETIME_S := IslandDetacher.DEBRIS_LIFETIME_S
const FREEZE_TICKS := 240  # 4.0 s at 60 Hz; DebrisReaper.FREEZE_AFTER_ASLEEP_S
const DWELL_TICKS := 30  # 0.5 s; DebrisReaper.OFFSCREEN_DWELL_S
const LINGER_TICKS := 1800  # 30.0 s; DebrisReaper.LINGER_MAX_S

var _pools: Array[DebrisPool] = []


func after_all() -> void:
	# A pool left in the tree keeps ninety-six bodies alive and its reaper
	# connected to the clock, and the next file's sweep would then run over them.
	for pool in _pools:
		pool.free()
	_pools.clear()
	# Every test here builds a pool while the tag is enabled except one, which
	# restores it; this is the belt in case that one failed early.
	SubsystemGate.enable([DebrisBodyRef.TAG_DEBRIS_VISIBILITY])


func test_the_durations_below_are_written_out_in_ticks() -> void:
	# The tests read as tick arithmetic, which is only honest if the numbers
	# still match §6.2's seconds.
	check_eq(
		MatchClockService.ticks_for_seconds(DebrisReaper.FREEZE_AFTER_ASLEEP_S), FREEZE_TICKS,
		"the four-second settling freeze"
	)
	check_eq(
		MatchClockService.ticks_for_seconds(DebrisReaper.OFFSCREEN_DWELL_S), DWELL_TICKS,
		"the half-second off-screen dwell"
	)
	check_eq(
		MatchClockService.ticks_for_seconds(DebrisReaper.LINGER_MAX_S), LINGER_TICKS,
		"and the thirty-second linger cap"
	)


## ===== §6.2 BUDGET =====================================================


func test_the_pool_allocates_its_whole_budget_up_front() -> void:
	# Ninety-six is Architectural Invariant I-12's number. Allocating them at
	# construction is what makes acquire() constant time on the worst tick.
	var pool := _pool()
	check_eq(pool.free_count(), DebrisPool.POOL_SIZE, "every body exists before the first island")
	check_eq(pool.in_flight_count(), 0, "and none of them is in flight")
	check_eq(DebrisPool.POOL_SIZE, 96, "the budget is I-12's ninety-six")


func test_an_acquired_body_is_configured_for_the_debris_layer() -> void:
	var pool := _pool()
	var body := pool.acquire()

	check_eq(pool.in_flight_count(), 1, "the body is in flight")
	check_eq(pool.simulated_count(), 1, "and it is an obstacle")
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

	check_eq(pool.in_flight_count(), 0, "the body left the in-flight list")
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
	check_eq(pool.in_flight_count(), 0, "and the in-flight list is still empty")


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
	check_eq(pool.in_flight_count(), DebrisPool.POOL_SIZE, "the budget is still the budget")
	check_eq(pool.free_count(), 0, "and nothing was allocated to serve the request")

	var next := pool.acquire()
	check_eq(next, second, "the next request takes the next oldest, not the same one again")


func test_exhaustion_takes_a_retired_body_before_a_simulated_one() -> void:
	# The eviction order is what keeps a client's cameras out of the simulation.
	# A retired body is presentation with no simulated consequence; a simulated
	# one is an obstacle every machine agrees about. Taking the newest retired
	# wreck ahead of the oldest live one costs a wreck nobody was told to expect
	# and keeps the deterministic set intact.
	var pool := _pool()
	var oldest := pool.acquire()
	for _i in DebrisPool.POOL_SIZE - 2:
		pool.acquire()
	var newest := pool.acquire()
	pool.retire(newest, MatchClock.tick + LINGER_TICKS)
	check_eq(pool.free_count(), 0, "the pool is exhausted")
	check_eq(pool.retired_count(), 1, "with exactly one retired body in it")

	var recycled := pool.acquire()
	check_eq(recycled, newest, "the retired body goes first, though it is the youngest")
	check_ne(recycled, oldest, "rather than the oldest, which is still an obstacle")
	check_eq(
		pool.simulated_count(), DebrisPool.POOL_SIZE,
		"so the simulated set is never squeezed by how long anyone looked at a wreck"
	)


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


## ===== §6.2 RETIREMENT =================================================


func test_the_lifetime_retires_a_body_rather_than_deleting_it() -> void:
	# The whole amendment in one test. On the scheduled tick the wreck stops
	# being an obstacle — that is the deterministic half — and it is still there
	# to be looked at, which is the half a camera influences.
	var pool := _pool()
	var body := _spawned(pool)
	var expected := body.expires_at_tick

	pool.reaper.sweep(expected - 1)
	check_eq(pool.simulated_count(), 1, "the tick before, it is still an obstacle")
	pool.reaper.sweep(expected)

	check_eq(pool.in_flight_count(), 1, "on the deadline the body is still in the world")
	check_true(body.retired, "but retired")
	check_eq(pool.simulated_count(), 0, "and out of the simulated set")
	check_eq(body.collision_layer, 0, "it occupies no layer")
	check_eq(body.collision_mask, 0, "and queries nothing")
	check_true(body.freeze, "so it is not an obstacle by any route")
	check_eq(
		body.active_shape_count(), 1, "its geometry stays, because there is still something to see"
	)


func test_a_wreck_being_watched_is_not_recycled() -> void:
	# The requirement, stated as an assertion: a player keeping a wreck on screen
	# never sees it blink out of the world.
	var pool := _pool()
	var body := _spawned(pool)
	_look_at(body)
	var retire_tick := body.expires_at_tick
	pool.reaper.sweep(retire_tick)

	for i in 10:
		pool.reaper.sweep(retire_tick + (i + 1) * DWELL_TICKS)
	check_eq(pool.in_flight_count(), 1, "ten dwell windows of being watched, and it is still there")
	check_eq(
		body.offscreen_since_tick, DebrisBodyRef.INVALID_TICK, "with no off-screen dwell accrued"
	)


func test_a_wreck_nobody_is_watching_goes_after_the_dwell() -> void:
	var pool := _pool()
	var body := _spawned(pool)
	_look_at(body)
	var retire_tick := body.expires_at_tick
	pool.reaper.sweep(retire_tick)

	_look_away(body)
	pool.reaper.sweep(retire_tick + 1)
	check_eq(body.offscreen_since_tick, retire_tick + 1, "the first unwatched tick is recorded")
	pool.reaper.sweep(retire_tick + DWELL_TICKS)
	check_eq(pool.in_flight_count(), 1, "a tick short of the dwell, it is still there")
	pool.reaper.sweep(retire_tick + 1 + DWELL_TICKS)
	check_eq(pool.in_flight_count(), 0, "and once the dwell is out it goes back to the pool")
	check_eq(pool.free_count(), DebrisPool.POOL_SIZE, "the budget is whole again")


func test_looking_back_before_the_dwell_is_out_keeps_the_wreck() -> void:
	# Without the reset, a camera shake that clipped a wreck out of frame for two
	# frames would recycle it, and the player who panned back would find it gone
	# — the same pop this mechanism exists to prevent, only harder to reproduce.
	var pool := _pool()
	var body := _spawned(pool)
	_look_at(body)
	var retire_tick := body.expires_at_tick
	pool.reaper.sweep(retire_tick)

	_look_away(body)
	pool.reaper.sweep(retire_tick + 1)
	_look_at(body)
	pool.reaper.sweep(retire_tick + 2)
	check_eq(body.offscreen_since_tick, DebrisBodyRef.INVALID_TICK, "the dwell is discarded")

	pool.reaper.sweep(retire_tick + DWELL_TICKS + 2)
	check_eq(pool.in_flight_count(), 1, "and the wreck outlives the window it half-served")


func test_the_linger_cap_recycles_a_wreck_that_is_never_looked_away_from() -> void:
	# Architectural Invariant I-12 bounds debris in count; without this it would
	# not bound it in time, and a player parked in front of a wreck would hold a
	# pool slot for the rest of the match.
	var pool := _pool()
	var body := _spawned(pool)
	_look_at(body)
	var retire_tick := body.expires_at_tick
	pool.reaper.sweep(retire_tick)
	check_eq(
		body.linger_deadline_tick, retire_tick + LINGER_TICKS, "the cap is set at retirement"
	)

	pool.reaper.sweep(retire_tick + LINGER_TICKS - 1)
	check_eq(pool.in_flight_count(), 1, "a tick short of the cap it is still watched and still there")
	pool.reaper.sweep(retire_tick + LINGER_TICKS)
	check_eq(pool.in_flight_count(), 0, "and at the cap it goes regardless")


func test_a_build_with_no_viewers_never_retires_anything() -> void:
	# Doc 12 §9.2's gate at its cheapest point. A dedicated server has nobody to
	# keep a wreck alive for, so it carries no lingering bodies at all and the
	# 22 s lifetime means exactly what §6.2 originally said it did.
	SubsystemGate.disable([DebrisBodyRef.TAG_DEBRIS_VISIBILITY])
	var pool := _pool()
	SubsystemGate.enable([DebrisBodyRef.TAG_DEBRIS_VISIBILITY])

	var body := _spawned(pool)
	check_false(body.tracks_visibility(), "no notifier was constructed")
	check_null(body.notifier, "and nothing was allocated for one")

	pool.reaper.sweep(body.expires_at_tick)
	check_eq(pool.in_flight_count(), 0, "the deadline recycles it outright")
	check_eq(pool.retired_count(), 0, "with no linger phase to hold the slot")


func test_the_notifier_is_fitted_to_the_islands_geometry() -> void:
	# A notifier left at its default bounds reports on the wrong volume, which
	# means a wreck kept alive by a camera pointed near it and recycled under one
	# pointed at it. The bounds come from the shapes actually registered.
	var pool := _pool()
	var body := pool.acquire()
	if not check_not_null(body.notifier, "a client build has a notifier"):
		return
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.25, 1.0)
	body.adopt_shape(box, Transform3D(Basis(), Vector3(0.0, -0.125, 0.0)))
	body.adopt_shape(box, Transform3D(Basis(), Vector3(0.0, 0.125, 0.0)))

	# The bounding radius of a 1.0 x 0.25 x 1.0 box is its half-diagonal.
	var r := Vector3(0.5, 0.125, 0.5).length()
	var expected := AABB(
		Vector3(-r, -0.125 - r, -r), Vector3(2.0 * r, 0.25 + 2.0 * r, 2.0 * r)
	)
	check_true(
		body.island_bounds().is_equal_approx(expected), "the bounds contain both primitives"
	)
	check_true(body.notifier.aabb.is_equal_approx(expected), "and the notifier is given them")

	pool.release(body)
	check_eq(body.island_bounds(), AABB(), "release clears them for the next island")


func test_a_recycled_body_is_simulated_again() -> void:
	# A body handed out still marked retired would never be an obstacle at all,
	# and the island it carries would be geometry the world drives straight
	# through.
	var pool := _pool()
	var body := _spawned(pool)
	pool.retire(body, MatchClock.tick + LINGER_TICKS)
	pool.release(body)

	var again := pool.acquire()
	check_eq(again, body, "the same body comes back")
	check_false(again.retired, "no longer retired")
	check_eq(pool.simulated_count(), 1, "and counted as an obstacle again")
	check_eq(
		again.linger_deadline_tick, DebrisBodyRef.INVALID_TICK, "with no linger deadline on it"
	)
	check_eq(again.expires_at_tick, DebrisBodyRef.INVALID_TICK, "and no lifetime deadline either")

	# The linger deadline in particular: left over, the reaper would recycle this
	# body the instant it retires — a wreck that vanishes on the tick it settles.
	pool.reaper.schedule(again, LIFETIME_S)
	pool.reaper.sweep(again.expires_at_tick)
	check_eq(pool.in_flight_count(), 1, "and its second life retires like any other")


## ===== §6.2 REAPING ====================================================


func test_a_recycled_body_does_not_inherit_the_last_islands_deadline() -> void:
	# A body between acquisition and scheduling must not be swept away by a tick
	# landing in between, and the deadline it carried last time round is exactly
	# the value that would do it — the reaper would retire a body §6 is still in
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
	check_eq(pool.simulated_count(), 1, "so the old deadline passing does not retire it")
	pool.reaper.sweep(MatchClock.tick + 100000)
	check_eq(pool.simulated_count(), 1, "and no deadline at all means no reaping, ever")


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
	check_eq(pool.in_flight_count(), 1, "frozen is not reaped; it stays until its lifetime")
	check_false(body.retired, "and it is still an obstacle")


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
	check_eq(pool.in_flight_count(), 0, "no bodies in flight")
	check_eq(pool.free_count(), DebrisPool.POOL_SIZE, "and none disturbed")


## ===== FIXTURES ========================================================


func _pool() -> DebrisPool:
	var pool := DebrisPool.new()
	_pools.append(pool)
	# Shapes register with the server only once the body is really in a tree, and
	# the reaper's clock connection is made in _ready.
	EventBus.get_tree().root.add_child(pool)
	return pool


## A body as §6 leaves it: geometry on it and a lifetime running.
func _spawned(pool: DebrisPool) -> DebrisBodyRef:
	var body := pool.acquire()
	body.adopt_shape(BoxShape3D.new(), Transform3D())
	pool.reaper.schedule(body, LIFETIME_S)
	return body


## Puts [param body] on a screen, through the notifier's own signal.
##
## Nothing renders under [code]--headless[/code], so the renderer never raises
## these itself. Emitting them is the same path it would take and reaches the
## same handler; the alternative is a test-only hook in production code.
func _look_at(body: DebrisBodyRef) -> void:
	body.notifier.screen_entered.emit()


func _look_away(body: DebrisBodyRef) -> void:
	body.notifier.screen_exited.emit()
