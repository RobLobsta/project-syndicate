extends TestCase
## Two Assemblies, built from shipped data, driven at each other on real ground,
## firing real rounds, until one of them loses its Core Module and the match
## declares the other the winner.
##
## This is the first test in the project's history that runs the whole chain end
## to end: the garage's [PlacementValidator] builds them, [MotiveSystem] drives
## them, [EffectorSystem] aims and emits, [ProjectileSystem] sweeps, and
## [DamageResolver] resolves — through band transitions, functional degradation,
## and destruction — into [signal EventBusService.part_destroyed] and
## Architectural Invariant I-2's rule that losing the Core Module ends the
## Assembly.
##
## [b]Everything that decides the fight is emergent.[/b] Nothing here scripts a
## winner, a hit, or a death. The two builds are identical apart from where they
## start and which way they face; the asymmetry is that one is given ammunition
## and the other is not, which is the smallest intervention that produces a
## decided outcome. A fixture where both fired would settle on whichever
## Assembly's slots happened to resolve first, and would be asserting a
## dictionary's iteration order rather than anything about combat.
##
## [b]Two fixture simplifications, both named.[/b] The ground is a
## [StaticBody3D] slab — document 09 owns Dynamic Ground Arrays and nothing here
## pre-empts it. And [b]the shooter is frozen[/b], for a reason worth writing
## down, because it is a finding rather than a convenience:
##
## §10.5 authors this autocannon at 1450 N·s of recoil per round on a 0.14 s
## cycle. §8 applies that as an impulse at the muzzle, which is where it belongs
## — and on this chassis the muzzle is two metres above the centre of mass and
## two metres forward of it. The first round pitches the nose up through 70
## degrees and the Assembly never fires a second aimed shot. That is not a bug in
## anything: an eleven-hundred-kilogram wheeled build genuinely cannot carry a
## thirty-millimetre autocannon, and the arithmetic says so before the simulation
## does — 1450 N·s on a two-metre lever against roughly 800 kg·m² of pitch
## inertia is 3.6 rad/s from one round.
##
## Freezing the shooter removes recoil from this test so that everything after
## the muzzle can be asserted. What it costs is recorded in the handoff as the
## first real balance finding the combat layer has produced: the shipped Core
## Module wants either a much heavier hull under it or a much smaller gun on it,
## and which of those the game wants is a design decision rather than a defect.

const CORE_KEY := &"core.command.compact.t2"
const HUB_KEY := &"str.hub.axle_station.t2"
const WHEEL_KEY := &"mot.wheeled.light_road.t1"
const REAR_KEY := &"mot.wheeled.light_fixed.t1"
const POWER_KEY := &"pmv.combustion.flat.t2"
const GUN_KEY := &"eff.ballistic.autocannon_30.t3"
const ROUND_KEY := &"proj.kinetic.ap_30"

const CORE_ORIGIN := Vector3i(24, 4, 24)
const POWER_ORIGIN := Vector3i(24, 4, 34)
## On the front of the Core Module's deck — and it was on the Prime Mover's roof
## until session 16 measured what that costs.
##
## A roof mount puts this muzzle about four metres above the Core Module of
## something standing on the same ground. The module authors 8° of depression
## (doc 01 §10.5); at the 26 m this duel is fought over, the solution is 9.5°,
## which is **outside its own arc**. It fired anyway, because doc 07 §4.3 tested
## convergence against the *clamped* angles: the mount sat on its stop, reported
## itself on target, and put thirty rounds over the enemy's roof. The fight still
## resolved, because the unbounded overpenetration of doc 07 §12.2 made any round
## that did connect lethal on its own. Two defects cancelling, and fixing either
## one exposes the geometry.
##
## Both are fixed now (§4.3.1 and §12.2.2), so the geometry has to be right. On
## the deck the muzzle sits about half a metre above this Assembly's centre of
## mass and the solution onto a target at 26 m is a degree or so — the middle of
## the arc rather than two degrees off a stop, which is what a fixture whose
## subject is *everything downstream of the muzzle* needs it to be.
##
## The barrel runs along the Assembly's -Z, which doc 07 §7.2 fixes as forward.
const GUN_ORIGIN := Vector3i(24, 8, 24)
const HUB_ORIGINS: Array[Vector3i] = [
	Vector3i(21, 2, 19), Vector3i(27, 2, 19), Vector3i(21, 2, 29), Vector3i(27, 2, 29)
]
const WHEEL_ORIGINS: Array[Vector3i] = [
	Vector3i(18, 3, 19), Vector3i(18, 3, 29), Vector3i(29, 3, 19), Vector3i(29, 3, 29)
]
const FRONT_AXLE_Z: int = 24

## Metres apart the two start. Close enough that a 940 m/s round crosses in a
## single tick and the fight is decided in seconds of simulated time; far enough
## that they are unambiguously separate Assemblies and the shooter's rounds have
## to travel.
const SEPARATION_M: float = 26.0

const GROUND_HALF_HEIGHT: float = 2.0
const GROUND_SPAN_M: float = 400.0
const SPAWN_HEIGHT_M: float = 2.0

## Ticks to fall onto the contacts and settle.
const SETTLE_TICKS: int = 260
## Ticks of the engagement itself. Four seconds: the autocannon cycles at 0.14 s,
## so this is about thirty rounds, and a Core Module rated 2400 does not survive
## thirty rounds of a 120-damage penetrator.
const ENGAGE_TICKS: int = 420
## Throttle both drive at. Modest deliberately — the point of the closing run is
## that the fight happens while they are moving, not that they reach a top speed.
const CLOSE_THROTTLE: float = 0.30

## Rounds the armed Assembly starts with. Generous: this test asserts that a
## fight resolves, not that a magazine is the constraint.
const LOADED_ROUNDS: int = 400

var _ctx_a: BuildContext = null
var _ctx_b: BuildContext = null
var _a: AssemblyRuntime = null
var _b: AssemblyRuntime = null
var _motion_a: MotiveSystem = null
var _motion_b: MotiveSystem = null
var _guns_a: EffectorSystem = null
var _guns_b: EffectorSystem = null
var _registry: AssemblyRegistry = null
var _resolver: DamageResolver = null
var _projectiles: ProjectileSystem = null
var _projectile_registry: ProjectileRegistry = null
var _ammo: AmmoLedger = null
var _ground: StaticBody3D = null

## Every `part_destroyed` seen, in order. The record the winner is read from.
var _destroyed: Array[Vector2i] = []
## Assembly ids terminated by losing slot 0, in the order they fell.
var _terminated: PackedInt32Array = PackedInt32Array()
var _shots_seen: int = 0
## Shots attributed to A alone, which is what its store is asserted against.
var _shots_by_a: int = 0
var _fought: bool = false
## Distance between the two at spawn, before anything moved.
var _initial_separation_m: float = 0.0


func before_all() -> void:
	_registry = AssemblyRegistry.new()
	_ammo = AmmoLedger.new()
	_projectile_registry = ProjectileRegistry.new()
	_projectile_registry.register(load("res://data/projectiles/%s.tres" % ROUND_KEY))
	_projectile_registry.seal()

	_ground = _make_ground()

	_resolver = DamageResolver.new()
	_resolver.registry = _registry
	EventBus.get_tree().root.add_child(_resolver)

	_projectiles = ProjectileSystem.new()
	_projectiles.registry = _projectile_registry
	_projectiles.resolver = _resolver
	EventBus.get_tree().root.add_child(_projectiles)

	_ctx_a = BuildContext.with_physics(1)
	_ctx_b = BuildContext.with_physics(2)
	_a = _build(_ctx_a, 1)
	_b = _build(_ctx_b, 2)

	# Facing each other along Z, both on the slab. A's own -Z — which is the way
	# its barrel points — is aimed down the line between them.
	_a.body.global_transform = Transform3D(Basis(), Vector3(0.0, SPAWN_HEIGHT_M, SEPARATION_M * 0.5))
	_b.body.global_transform = Transform3D(
		Basis.from_euler(Vector3(0.0, PI, 0.0)), Vector3(0.0, SPAWN_HEIGHT_M, -SEPARATION_M * 0.5)
	)

	# The space is taken from the ground fixture rather than from a runtime,
	# because it is the world every body in this test shares and the ground is
	# the one thing here that is unambiguously in it.
	var world := _ground.get_world_3d()
	_projectiles.space = world.direct_space_state
	_resolver.space = world.direct_space_state

	# Captured here, not asserted in a test method: the runner sorts methods, and
	# by the time an alphabetically later name runs, the fight has happened and
	# one of these two has driven several metres. A property of the fixture is
	# recorded when the fixture is built.
	_initial_separation_m = _a.body.global_position.distance_to(_b.body.global_position)

	EventBus.part_destroyed.connect(_on_part_destroyed)
	EventBus.effector_fired.connect(_on_effector_fired)


func after_all() -> void:
	if EventBus.part_destroyed.is_connected(_on_part_destroyed):
		EventBus.part_destroyed.disconnect(_on_part_destroyed)
	if EventBus.effector_fired.is_connected(_on_effector_fired):
		EventBus.effector_fired.disconnect(_on_effector_fired)
	for node: Node in [_a, _b, _projectiles, _resolver, _ground] as Array[Node]:
		if node != null and is_instance_valid(node):
			node.free()
	for ctx: BuildContext in [_ctx_a, _ctx_b] as Array[BuildContext]:
		if ctx != null:
			ctx.dispose()


## ===== THE FIGHT =======================================================


func test_the_two_assemblies_are_built_and_separate() -> void:
	# Asserted before the fight so that a failure here reads as "the fixture is
	# wrong" rather than as "combat is broken". Every assertion below depends on
	# these two being real, distinct, and armed as described.
	check_eq(_registry.count(), 2, "two Assemblies are in the match")
	check_true(_a.assembly_id != _b.assembly_id, "with distinct ids")
	check_approx(
		_initial_separation_m, SEPARATION_M, "and they start the documented distance apart", 0.01
	)
	check_eq(_guns_a.slots().size(), 1, "each carries one Effector Module")
	check_eq(_guns_b.slots().size(), 1, "each carries one Effector Module")
	check_true(
		_ammo.has_rounds(_a.assembly_id, 0), "A is loaded"
	)
	check_false(
		_ammo.has_rounds(_b.assembly_id, 0),
		"and B is not, which is the only asymmetry in the fixture"
	)


func test_they_close_shoot_and_one_of_them_wins() -> void:
	await _fight()

	check_true(_shots_seen > 0, "the armed Assembly fired: %d rounds" % _shots_seen)
	check_true(
		_destroyed.size() > 0,
		"and something on the other Assembly came apart: %d parts" % _destroyed.size()
	)
	for hit: Vector2i in _destroyed:
		check_eq(
			hit.x, _b.assembly_id, "every part destroyed belongs to the Assembly being shot at"
		)
	check_eq(_terminated.size(), 1, "exactly one Assembly lost its Core Module")
	check_eq(
		_terminated[0], _b.assembly_id, "and it is the unarmed one, so the winner is A"
	)


func test_the_winner_is_still_a_going_concern() -> void:
	await _fight()
	var core: PartInstanceState = _a.states[SyndicateConstants.CORE_SLOT]

	check_false(core.has_flag(PartFlags.FLAG_DESTROYED), "the winner still has its Core Module")
	check_approx(
		core.integrity,
		_a.definition_at(SyndicateConstants.CORE_SLOT).integrity_max,
		"at full integrity, because nothing shot back"
	)
	check_eq(
		core.integrity_band,
		PartEnums.IntegrityBand.NOMINAL,
		"and in the NOMINAL band"
	)


func test_the_loser_degraded_through_the_bands_before_it_died() -> void:
	# I-5's whole point, observed on a real part rather than asserted against a
	# table. A Core Module that went from NOMINAL to DESTROYED in one packet
	# would satisfy every other assertion in this file and would mean the band
	# machinery had never run.
	await _fight()
	var core: PartInstanceState = _b.states[SyndicateConstants.CORE_SLOT]

	check_true(core.has_flag(PartFlags.FLAG_DESTROYED), "the loser's Core Module is destroyed")
	check_eq(core.integrity_band, PartEnums.IntegrityBand.DESTROYED, "and reads DESTROYED")
	check_approx(core.integrity, 0.0, "with nothing left")
	check_true(
		_bands_seen.size() >= 3,
		"and it passed through the intermediate bands on the way: %s" % [_bands_seen]
	)


func test_the_rounds_that_missed_did_not_leak() -> void:
	# §12's pool is bounded and every round has a life. A sweep that never
	# expired a miss would fill 2048 slots and start recycling live rounds, which
	# presents as shots vanishing in mid-air much later and is close to
	# undiagnosable after the fact.
	await _fight()
	check_true(
		_projectiles.active_count() < ProjectileSystem.POOL_SIZE,
		"the pool did not fill: %d in flight" % _projectiles.active_count()
	)
	check_true(_shots_seen > _projectiles.active_count(), "most of what was fired has landed")


## §9.2's ledger, asserted against the rounds that actually left the barrel.
##
## This fixture is the only one in the suite with a [i]finite[/i] store — every
## engagement in [code]test_family_duels[/code] and [code]test_team_engagement[/code]
## spawns with [constant AmmoLedger.UNLIMITED], and [method AmmoLedger.consume]
## returns on that sentinel before it reaches the subtraction. So this is the
## only place the ledger can be caught not doing its job, and until session 17 it
## was not looking: both "the fire path never calls consume" and "consume never
## subtracts" left the whole suite green.
##
## Asserted as an equality against the shot count rather than as "it went down".
## A store that fell by some amount is satisfied by a module that double-charges
## or forgets every other round, and an Assembly that quietly gets two shots per
## round is a balance defect nothing else here would notice.
func test_every_round_fired_came_out_of_the_store() -> void:
	await _fight()
	var round_id := _projectile_registry.id_of(ROUND_KEY)
	check_true(_shots_by_a > 0, "the armed Assembly fired at all: %d rounds" % _shots_by_a)
	check_eq(
		_ammo.rounds_stored(_a.assembly_id, round_id),
		LOADED_ROUNDS - _shots_by_a,
		"%d of %d rounds left after firing %d" % [
			_ammo.rounds_stored(_a.assembly_id, round_id), LOADED_ROUNDS, _shots_by_a
		]
	)


## ===== FIXTURES ========================================================


## Bands the loser's Core Module was observed in, in order. Populated by the
## band-changed handler during the fight.
var _bands_seen: PackedInt32Array = PackedInt32Array()


## Runs the engagement exactly once, however many test methods ask for it.
##
## The fight is destructive and cannot be repeated: an Assembly whose Core Module
## has gone cannot be put back. Caching it here is what lets five test methods
## each assert one thing about the same run, instead of one method asserting five
## things and reporting only the first failure.
func _fight() -> void:
	if _fought:
		return
	_fought = true
	EventBus.part_band_changed.connect(_on_band_changed)

	await physics_frames(SETTLE_TICKS)

	# The shooter is braced; see the class docstring for what that costs and why.
	# It is frozen after the settle rather than before, so it settles onto its own
	# suspension first and fires from the pose a real build would be in.
	_a.body.freeze = true

	# B closes on A. A aims at B's Core Module and holds the trigger; B has a gun,
	# aims it, and has nothing to put through it.
	_motion_b.input.throttle = CLOSE_THROTTLE
	_guns_a.set_trigger(0, true)
	_guns_b.set_trigger(0, true)

	for i: int in ENGAGE_TICKS:
		_guns_a.aim_point_world = _b.part_world_position(SyndicateConstants.CORE_SLOT)
		_guns_b.aim_point_world = _a.part_world_position(SyndicateConstants.CORE_SLOT)
		await physics_frames(1)
		if _terminated.size() > 0:
			break

	_guns_a.set_trigger(0, false)
	_guns_b.set_trigger(0, false)
	_motion_b.input.throttle = 0.0
	EventBus.part_band_changed.disconnect(_on_band_changed)


## One Assembly: the four-contact wheeled build the physics suite already uses,
## with an autocannon on the roof.
func _build(ctx: BuildContext, assembly_id: int) -> AssemblyRuntime:
	var core := PartRegistry.definition_by_key(CORE_KEY)
	var hub := PartRegistry.definition_by_key(HUB_KEY)
	var wheel := PartRegistry.definition_by_key(WHEEL_KEY)
	var rear := PartRegistry.definition_by_key(REAR_KEY)

	PlacementValidator.commit(ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))
	PlacementValidator.commit(
		ctx, PlacementCandidate.create(PartRegistry.definition_by_key(POWER_KEY), POWER_ORIGIN, 0)
	)
	PlacementValidator.commit(
		ctx, PlacementCandidate.create(PartRegistry.definition_by_key(GUN_KEY), GUN_ORIGIN, 0)
	)
	for cell: Vector3i in HUB_ORIGINS:
		PlacementValidator.commit(ctx, PlacementCandidate.create(hub, cell, 0))
	for cell: Vector3i in WHEEL_ORIGINS:
		var def := wheel if cell.z < FRONT_AXLE_Z else rear
		PlacementValidator.commit(
			ctx, PlacementCandidate.create(def, cell, _wheel_orientation_for(cell))
		)

	var runtime := AssemblyRuntime.new()
	EventBus.get_tree().root.add_child(runtime)
	runtime.adopt(ctx)
	runtime.apply_mass_properties(MassSolver.compute(runtime.states, runtime.graph))
	_registry.register(runtime)

	var motion := MotiveSystem.new()
	motion.runtime = runtime
	motion.input = ControlInput.new()
	motion.power = PowerSystem.new()
	motion.power.recompute(runtime.states, runtime.graph.alive)
	runtime.add_child(motion)

	var guns := EffectorSystem.new()
	guns.runtime = runtime
	guns.projectiles = _projectiles
	guns.registry = _projectile_registry
	guns.ammo = _ammo
	# Seeded from the Assembly id. Invariant I-9: the spread and jam rolls are
	# replayed by the network layer, so they may not come from the global
	# generator, and two Assemblies in one match must not roll in lockstep.
	guns.seed_rng(assembly_id)
	runtime.add_child(guns)

	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var def := runtime.definition_at(slot)
		if def == null:
			continue
		if def.part_class == PartEnums.PartClass.MOTIVE_ASSEMBLY:
			motion.register(slot, def, runtime.states[slot])
		elif def.part_class == PartEnums.PartClass.EFFECTOR_MODULE:
			guns.register(slot, def)

	if assembly_id == 1:
		_motion_a = motion
		_guns_a = guns
		_ammo.add(runtime.assembly_id, _projectile_registry.id_of(ROUND_KEY), LOADED_ROUNDS)
	else:
		_motion_b = motion
		_guns_b = guns
	return runtime


func _on_part_destroyed(assembly_id: int, slot: int, _cause: int) -> void:
	_destroyed.append(Vector2i(assembly_id, slot))
	# I-2: slot 0 is the Core Module and losing it terminates the Assembly. The
	# match layer is what will act on that; here it is what "wins" means.
	if slot == SyndicateConstants.CORE_SLOT:
		_terminated.append(assembly_id)


func _on_band_changed(assembly_id: int, slot: int, _before: int, after: int) -> void:
	if assembly_id == _b.assembly_id and slot == SyndicateConstants.CORE_SLOT:
		_bands_seen.append(after)


func _on_effector_fired(assembly_id: int, _slot: int, _tick: int) -> void:
	_shots_seen += 1
	# Attributed rather than assumed. B carries an identical module and no
	# rounds, so today every shot is A's — but an assertion that silently depends
	# on that is one the next change to the fixture breaks without saying so.
	if _a != null and assembly_id == _a.assembly_id:
		_shots_by_a += 1


## The orientation that points a disc's AXLE face inboard. Derived from the
## 24-orientation group rather than written down: which index carries the wheel's
## own -Z drive face onto the Assembly's +X is a property of [OrientationTable].
func _wheel_orientation_for(cell: Vector3i) -> int:
	return _wheel_orientation(1.0 if cell.x < CORE_ORIGIN.x else -1.0)


func _wheel_orientation(face_sign: float) -> int:
	for i: int in SyndicateConstants.ORIENTATION_COUNT:
		var basis := OrientationTable.basis_for(i)
		if not (basis * Vector3.FORWARD).is_equal_approx(Vector3(face_sign, 0.0, 0.0)):
			continue
		if (basis * Vector3.UP).is_equal_approx(Vector3.UP):
			return i
	return 0


## A static slab on the ground layer. Not a Dynamic Ground Array — doc 09 owns
## that and nothing here pre-empts it.
func _make_ground() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = CollisionLayers.LAYER_GROUND
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SPAN_M, GROUND_HALF_HEIGHT * 2.0, GROUND_SPAN_M)
	shape.shape = box
	body.add_child(shape)
	EventBus.get_tree().root.add_child(body)
	body.global_position = Vector3(0.0, -GROUND_HALF_HEIGHT, 0.0)
	return body
