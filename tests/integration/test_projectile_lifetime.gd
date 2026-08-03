extends TestCase
## Doc 07 §12's round lifetime: a projectile that hits nothing is retired when
## [code]life_s[/code] runs out.
##
## Session 17's sweep deleted the expiry outright — rounds flying forever — and
## all 56 files stayed green, including [code]test_duel[/code]'s "the rounds that
## missed did not leak". The reason is §2.0's lesson about bounds, one level
## along: [b]every round in every engagement hits something.[/b] The arena's
## ground slab is 200 m across and the fights are fought over 26 m of it, so a
## round that misses a hull still lands, and the release that retires it is the
## impact path. The expiry branch is never the mechanism, so removing it changes
## no observable in the suite.
##
## The fixture that reaches it therefore has to be one where there is nothing to
## hit at all. This file builds its own empty physics space rather than borrowing
## the world every other test shares — an empty space is the whole experiment,
## and a stray body from a neighbouring fixture would silently turn this back
## into the impact path (§3.45 is the same hazard from the other side).
##
## No physics frames are awaited. [method ProjectileSystem.step] is public and is
## the entire tick, so the round is flown by calling it — which makes this an
## integration test that costs microseconds rather than four seconds of wall
## clock (§3.50 is why that distinction is worth caring about).

const ROUND_PATH := "res://data/projectiles/proj.kinetic.ap_30.tres"

## Doc 07 §12 / [ProjectileDefinition]'s authored default, quoted rather than
## imported so a change to the round names itself here.
const DOC_LIFE_S: float = 4.0

const DT: float = 1.0 / 60.0

## Either side of the 240-tick boundary, never on it. A float accumulated from
## [constant DT] never lands on a round threshold (§3.17), so a test that
## asserted the exact tick would be asserting a rounding mode.
const TICKS_WELL_BEFORE_EXPIRY := 200
const TICKS_WELL_AFTER_EXPIRY := 280

## High enough that the round's own ballistic arc cannot bring it back through
## the origin of a space that is empty anyway. Belt and braces: if this file ever
## stops building its own space, the altitude is what keeps it honest.
const MUZZLE := Vector3(0.0, 2000.0, 0.0)
const MUZZLE_VELOCITY := Vector3(0.0, 0.0, -940.0)

var _registry: ProjectileRegistry = null
var _projectiles: ProjectileSystem = null
var _space: RID = RID()
var _round_id: int = -1

## Captured as the round is flown, because the runner sorts method names and the
## flight cannot be repeated from a method that happens to run later (§3.43).
var _index: int = -1
var _active_at_spawn: int = -1
var _active_before_expiry: int = -1
var _active_after_expiry: int = -1
var _strikes: int = -1


func before_all() -> void:
	_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(_space, true)

	_registry = ProjectileRegistry.new()
	_registry.register(load(ROUND_PATH))
	_registry.seal()
	_round_id = _registry.id_of(&"proj.kinetic.ap_30")

	# Deliberately not added to the tree. `ProjectileSystem` declares
	# `_physics_process`, and a node in the tree would be stepped by the engine
	# as well as by this file — two ticks per tick, and an expiry at half the
	# authored life.
	_projectiles = ProjectileSystem.new()
	_projectiles.registry = _registry
	_projectiles.space = PhysicsServer3D.space_get_direct_state(_space)

	_fly()


func after_all() -> void:
	if _projectiles != null:
		_projectiles.free()
	if _space.is_valid():
		PhysicsServer3D.free_rid(_space)


## ===== THE FIXTURE CAN ANSWER THE QUESTION =============================

## Asserted first: if the round never launched, "no rounds in flight" at the end
## is true for a reason that has nothing to do with the expiry.
func test_the_round_launched() -> void:
	check_true(_index >= 0, "the round was allocated a pool slot")
	check_eq(_active_at_spawn, 1, "and reported itself in flight")


## The other half of the fixture's honesty. A round retired by hitting something
## leaves the same [method ProjectileSystem.active_count] as one retired by the
## clock, so without this the assertion below cannot say which happened.
func test_the_round_never_hit_anything() -> void:
	check_eq(_strikes, 0, "the space was empty, so nothing was struck")


## ===== THE EXPIRY ======================================================

## Still flying well short of its authored life, so the release below is the
## clock running out rather than the round never having existed.
func test_the_round_is_still_in_flight_before_its_life_runs_out() -> void:
	check_eq(
		_active_before_expiry, 1,
		"in flight after %d of the %d ticks doc 07 gives it"
		% [TICKS_WELL_BEFORE_EXPIRY, int(DOC_LIFE_S * 60.0)]
	)


## The assertion the file exists for. With the expiry removed this reads 1 and
## nothing else in the suite changes.
func test_a_round_that_hits_nothing_is_retired_when_its_life_runs_out() -> void:
	check_eq(
		_active_after_expiry, 0,
		"retired by %.1f s of flight, with nothing to hit" % DOC_LIFE_S
	)


## ===== FIXTURES ========================================================


## Fires one round into an empty space and records what the pool reports at three
## points along its flight.
func _fly() -> void:
	_index = _projectiles.spawn(MUZZLE, MUZZLE_VELOCITY, _round_id, 0, 0, RID())
	if _index < 0:
		return
	_active_at_spawn = _projectiles.active_count()

	for i: int in TICKS_WELL_BEFORE_EXPIRY:
		_projectiles.step(DT)
	_active_before_expiry = _projectiles.active_count()

	for i: int in TICKS_WELL_AFTER_EXPIRY - TICKS_WELL_BEFORE_EXPIRY:
		_projectiles.step(DT)
	_active_after_expiry = _projectiles.active_count()

	# Survives release, which is what lets it be read after the round is spent.
	_strikes = _projectiles.strikes_of(_index)
