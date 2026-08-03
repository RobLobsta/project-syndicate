class_name MatchScreen
extends Node3D
## The composition root of a playable match, owned by
## [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §15.3.
##
## It constructs the shared systems, spawns the Assemblies, attaches the camera
## to the local one, fills a [HudFrame] every tick, and tears the whole thing
## down on exit. It is the [b]only[/b] class permitted to hold both an
## [AssemblyRuntime] and a HUD, and that is exactly why §14.1's rule can be
## enforced everywhere else: there is one place where the two worlds meet, and it
## is a class whose entire job is to be that place.
##
## §15.2: this shares [code]tests/combat_arena.gd[/code]'s [i]wiring[/i] and
## replaces its [i]driver[/i]. The arena counts ticks to a verdict; this draws.
## Keeping both is the point — the fixture asserts, the scene is played.
##
## [b]One thing here is standing in for a system that does not exist yet[/b], and
## it is named so nobody mistakes it for a design:
##
## [enum]
## [*] [b]The builds are laid out in code.[/b] They should come from a blueprint
##     in [code]data/[/code] through the identical [PlacementValidator] chain
##     (CLAUDE.md §10 rule 9) — which they already do, part by part; what is
##     missing is the serialised form, not the validation. Doc 02 §9.3's
##     [code]BuildCommand[/code] and the blueprint codec are where that lands.
## [/enum]
##
## Each opponent carries an [AiDriver] — doc 05 §15.7 — on the other side of a
## roster this class owns and every driver shares. They close, aim through the
## identical [EffectorSystem] the player's trigger reaches, and shoot back with a
## finite store. Nothing about them is privileged: the same eight numbers, the
## same aim point, the same jam chance, and a miss that puts a real round into
## the terrain.

## ===== ARENA ===========================================================

## Seed for the arena's terrain. Fixed rather than drawn, so the basin is the
## same basin every launch — Invariant I-9, and also the difference between a
## map and a lottery.
const GROUND_SEED: int = 20260803
## Peak-to-trough relief of the arena floor, in metres.
##
## Raised from 6.5 after looking at it: at that amplitude the noise's 110 m
## wavelength produces about 3 degrees of slope, which is drivable but reads as a
## flat plane from the chase camera and made the whole Ground Array look like the
## slab it replaced. Terrain nobody can see is terrain nobody fights over.
const GROUND_AMPLITUDE_M: float = 15.0
## Height above the ground the builds are dropped from, so they settle onto
## their own contacts rather than being placed at a pose somebody guessed.
const DROP_HEIGHT_M: float = 1.4

const PLAYER_SPAWN_XZ := Vector2(0.0, 0.0)
const TARGET_SPAWN_XZ: Array[Vector2] = [
	Vector2(0.0, -34.0), Vector2(-22.0, -46.0), Vector2(21.0, -44.0)
]

const PLAYER_ROUNDS: int = 600
## What each opponent is given. Finite, and a third of the player's, because the
## asymmetry is the difficulty setting nobody has built a screen for yet: three
## Assemblies firing seven rounds a second at one is an unwinnable first minute
## if all three can do it indefinitely, and a store that runs out is a fight that
## turns rather than a wall that does not.
const TARGET_ROUNDS: int = 200

## Which side each spawn is on. Doc 07 §10.1: the roster is the match layer's,
## because nothing in [code]src/combat/[/code] knows what a team is and the AI
## layer is the first system that needs to.
const PLAYER_TEAM: int = 0
const OPPONENT_TEAM: int = 1

## §10's difficulty for the opponents, in [code][0, 1][/code]. An aim-point
## offset and nothing else — an AI miss here is a real round going somewhere
## real, which can hit the terrain, a wreck, or another opponent.
##
## 0.55 is about half a metre of spread at forty metres, which is a hit on a hull
## and a miss on a Motive Assembly. It was picked by watching the fight rather
## than by arithmetic: at 0.9 the three of them converge on the same Core Module
## and the match is over before a player has turned round.
const OPPONENT_DIFFICULTY: float = 0.55

## ===== BUILD ===========================================================
## The wheeled recipe, on the lattice. Integer coordinates throughout
## (Invariant I-6).

const CORE_KEY: StringName = &"core.command.compact.t2"
const HUB_KEY: StringName = &"str.hub.axle_station.t2"
const WHEEL_KEY: StringName = &"mot.wheeled.allroad.t2"
const REAR_KEY: StringName = &"mot.wheeled.fixed_rear.t2"
const POWER_KEY: StringName = &"pmv.combustion.standard.t2"
const CELL_KEY: StringName = &"cel.static.standard.t3"
const GUN_KEY: StringName = &"eff.ballistic.autocannon_30.t3"
const ROUND_KEY: StringName = &"proj.kinetic.ap_30"

const BUILD_CORE := Vector3i(24, 4, 24)
const BUILD_POWER := Vector3i(24, 7, 24)
const BUILD_CELL := Vector3i(24, 4, 29)
## On the nose, at the Core Module's own height. Handoff §4.11 and §4.14: what
## decides whether a round of the shipped autocannon flips the shipped chassis is
## not the impulse but the height of the muzzle above the centre of mass, because
## the fore-aft offset is parallel to the recoil and contributes no moment at
## all. On the roof one round is 3.6 rad/s of pitch. Here it is a shove.
const BUILD_GUN := Vector3i(24, 6, 21)

const BUILD_HUBS: Array[Vector3i] = [
	Vector3i(22, 2, 23), Vector3i(26, 2, 23), Vector3i(22, 2, 27), Vector3i(26, 2, 27)
]
const BUILD_WHEELS: Array[Vector3i] = [
	Vector3i(19, 3, 22), Vector3i(19, 3, 28), Vector3i(28, 3, 21), Vector3i(28, 3, 27)
]
## Contacts forward of this row steer; the pair behind it is fixed. An Assembly
## on which every contact steers crabs instead of turning; see CHANGE_LOG.md, session 12.
const FRONT_AXLE_Z: int = 24

## ===== PRESENTATION ====================================================

const SUN_EULER_DEG := Vector3(-52.0, -38.0, 0.0)
const SUN_ENERGY: float = 1.15
const SKY_HORIZON := Color("#3A4652")
const SKY_TOP := Color("#1E2A38")
const GROUND_ALBEDO := Color("#4A4F49")
const AMBIENT_ENERGY: float = 0.42

## Fallback bounding radius before mass properties have been solved.
const DEFAULT_BOUNDING_RADIUS_M: float = 2.4

## ===== STATE ===========================================================

var registry: AssemblyRegistry = null
var ammo: AmmoLedger = null
var projectile_registry: ProjectileRegistry = null
var projectiles: ProjectileSystem = null
var resolver: DamageResolver = null
var camera: ChaseCamera = null
var hud: MatchHud = null

var _detachment: DetachmentScheduler = null
var _mass: MassRecomputeScheduler = null
var _debris: DebrisPool = null
var ground: GroundArray = null
var ground_deform: GroundDeformSystem = null
var ground_streamer: GroundCollisionStreamer = null

var _player: AssemblyRuntime = null
var _player_guns: EffectorSystem = null
var _player_power: PowerSystem = null
var _controls: ControlSystem = null
var _gun_slot: int = SyndicateConstants.INVALID_SLOT
var _round_id: int = 0

var _runtimes: Array[AssemblyRuntime] = []
var _contexts: Array[BuildContext] = []
var _next_assembly_id: int = 1
## Assembly id -> team, handed to every [AiDriver] and shared with all of them.
## One dictionary rather than a copy each: a driver spawned before its opponents
## has to see them when it first scans.
var _roster: Dictionary = {}

var _frame: HudFrame = null
var _integrity_total: float = 0.0
var _integrity_now: float = 0.0
var _parts_total: int = 0
var _parts_alive: int = 0


func _ready() -> void:
	_frame = HudFrame.new()
	_build_environment()
	_build_ground()
	_build_systems()

	# Collision has to exist before anything is dropped onto it. The streamer
	# normally anchors on the Assemblies, so the first evaluation is seeded with
	# the spawn points instead — there is nothing else to be near yet.
	_build_ground_streaming()
	ground_streamer.extra_anchors = _spawn_anchors()
	# prime() rather than evaluate(): the per-evaluation cap exists to spread
	# instantiation across ticks, and there are no ticks yet. Four chunks would
	# leave the spawns hanging over unstreamed ground.
	ground_streamer.prime()

	_player = _spawn(PLAYER_SPAWN_XZ, 0.0, PLAYER_ROUNDS, PLAYER_TEAM, true)
	for xz: Vector2 in TARGET_SPAWN_XZ:
		_spawn(
			xz, _yaw_towards(xz, PLAYER_SPAWN_XZ), TARGET_ROUNDS, OPPONENT_TEAM, false
		)
	# The Assemblies now anchor it themselves.
	ground_streamer.extra_anchors = PackedVector3Array()

	_build_camera()
	_build_hud()

	EventBus.part_damaged.connect(_on_part_damaged)
	EventBus.part_destroyed.connect(_on_part_destroyed)
	MatchClock.tick_started.connect(_on_tick_started)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	if EventBus.part_damaged.is_connected(_on_part_damaged):
		EventBus.part_damaged.disconnect(_on_part_damaged)
	if EventBus.part_destroyed.is_connected(_on_part_destroyed):
		EventBus.part_destroyed.disconnect(_on_part_destroyed)
	if MatchClock.tick_started.is_connected(_on_tick_started):
		MatchClock.tick_started.disconnect(_on_tick_started)
	for ctx: BuildContext in _contexts:
		ctx.dispose()
	_contexts.clear()


## Releases the mouse so the player can reach the window controls. A captured
## mouse with no way out is the oldest bad manner a 3D game has.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"build_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## ===== CONSTRUCTION ====================================================


## A sky and one directional light. Without them every mesh in the scene renders
## black, which is the single most likely way "the camera works" and "you can see
## anything" come apart.
func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	sky_material.ground_bottom_color = GROUND_ALBEDO
	sky_material.ground_horizon_color = SKY_HORIZON

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(
		deg_to_rad(SUN_EULER_DEG.x), deg_to_rad(SUN_EULER_DEG.y), deg_to_rad(SUN_EULER_DEG.z)
	)
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	# Doc 09. The Dynamic Ground Array replaced the flat slab this scene used to
	# stand on; the basin is what makes the arena read as a place rather than a
	# plane, and the craters that appear in it are the reason it is a heightfield
	# rather than a mesh.
	ground = GroundArray.new()
	ground.name = "GroundArray"
	ground.source = GroundSource.basin(GROUND_SEED, GROUND_AMPLITUDE_M)
	ground.present_visuals = SubsystemGate.is_enabled(&"ground_height_texture")
	add_child(ground)

	ground_deform = GroundDeformSystem.new()
	ground_deform.name = "GroundDeform"
	ground_deform.array = ground
	add_child(ground_deform)


## Streams collision in around the spawned Assemblies.
##
## Separate from [method _build_ground] and called after the spawns, because the
## streamer's resident set is a function of where things are and there is
## nothing to be near until they exist. Doc 09 §5.
func _build_ground_streaming() -> void:
	ground_streamer = GroundCollisionStreamer.new()
	ground_streamer.name = "GroundStreaming"
	ground_streamer.array = ground
	ground_streamer.registry = registry
	add_child(ground_streamer)


## Ground height at [param xz], for placing a spawn on the terrain rather than
## at a fixed altitude.
func _ground_height_at(xz: Vector2) -> float:
	if ground == null:
		return 0.0
	return ground.height_at_world(Vector3(xz.x, 0.0, xz.y))


## Every spawn point, as collision-streaming anchors for the first evaluation.
func _spawn_anchors() -> PackedVector3Array:
	var out := PackedVector3Array()
	out.push_back(Vector3(PLAYER_SPAWN_XZ.x, 0.0, PLAYER_SPAWN_XZ.y))
	for xz: Vector2 in TARGET_SPAWN_XZ:
		out.push_back(Vector3(xz.x, 0.0, xz.y))
	return out


## Doc 12's construction order, and the order matters: the debris pool must have
## the registry before the detachment scheduler can sink an island into it.
func _build_systems() -> void:
	registry = AssemblyRegistry.new()
	ammo = AmmoLedger.new()

	projectile_registry = ProjectileRegistry.new()
	projectile_registry.register(load("res://data/projectiles/%s.tres" % ROUND_KEY))
	projectile_registry.seal()
	_round_id = projectile_registry.id_of(ROUND_KEY)

	_detachment = DetachmentScheduler.new()
	_detachment.registry = registry
	add_child(_detachment)

	_mass = MassRecomputeScheduler.new()
	_mass.registry = registry
	add_child(_mass)

	_debris = DebrisPool.new()
	_debris.registry = registry
	_detachment.island_sink = _debris.on_island_severed
	add_child(_debris)

	var world := get_world_3d()

	resolver = DamageResolver.new()
	resolver.registry = registry
	resolver.space = world.direct_space_state
	# Doc 09 §4.1. Every blast this resolver handles now leaves a hole, whether
	# or not it found anything to damage.
	resolver.ground_deform = ground_deform
	add_child(resolver)

	projectiles = ProjectileSystem.new()
	projectiles.registry = projectile_registry
	projectiles.resolver = resolver
	projectiles.space = world.direct_space_state
	add_child(projectiles)


func _build_camera() -> void:
	camera = ChaseCamera.new()
	camera.name = "ChaseCamera"
	# §13.2: the interpolated node, never the body.
	camera.target = _player.visual_root
	camera.bounding_radius_m = _bounding_radius(_player)
	camera.own_body_rid = _player.body.get_rid()
	camera.current = true
	add_child(camera)


func _build_hud() -> void:
	hud = MatchHud.new()
	hud.name = "MatchHud"
	hud.local_assembly_id = _player.assembly_id
	add_child(hud)


## ===== SPAWNING ========================================================


func _spawn(
	ground_xz: Vector2, yaw_rad: float, rounds: int, team: int, is_player: bool
) -> AssemblyRuntime:
	var assembly_id := _next_assembly_id
	_next_assembly_id += 1
	_roster[assembly_id] = team

	var ctx := BuildContext.with_physics(assembly_id)
	_contexts.append(ctx)
	_lay_out(ctx)

	var runtime := AssemblyRuntime.new()
	runtime.name = "Assembly%d" % assembly_id
	add_child(runtime)
	runtime.adopt(ctx)
	runtime.apply_mass_properties(MassSolver.compute(runtime.states, runtime.graph))
	registry.register(runtime)
	_runtimes.append(runtime)

	var motion := MotiveSystem.new()
	motion.runtime = runtime
	motion.input = ControlInput.new()
	# Doc 09 §7.3 and §6: contacts resolve their surface against the Array, and
	# a loaded contact on ruttable ground deposits into the batch.
	motion.ground = ground
	motion.ground_deform = ground_deform
	motion.power = PowerSystem.new()
	motion.power.recompute(runtime.states, runtime.graph.alive)
	runtime.add_child(motion)

	var guns := EffectorSystem.new()
	guns.runtime = runtime
	guns.projectiles = projectiles
	guns.registry = projectile_registry
	guns.ammo = ammo
	guns.resolver = resolver
	guns.space = resolver.space
	# Invariant I-9. Two Assemblies must not roll their spread and jam in
	# lockstep, and the same match must replay identically.
	guns.seed_rng(assembly_id)
	runtime.add_child(guns)

	var gun_slot := SyndicateConstants.INVALID_SLOT
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var def := runtime.definition_at(slot)
		if def == null:
			continue
		if def.part_class == PartEnums.PartClass.MOTIVE_ASSEMBLY:
			motion.register(slot, def, runtime.states[slot])
		elif def.part_class == PartEnums.PartClass.EFFECTOR_MODULE:
			guns.register(slot, def)
			gun_slot = slot
	motion.reassign_gait_phases()

	# Dropped relative to the terrain under the spawn, not to y = 0: the arena
	# floor is a basin now and a fixed altitude would bury the builds on the
	# rises and drop them from a height into the hollows.
	runtime.body.global_transform = Transform3D(
		Basis.from_euler(Vector3(0.0, yaw_rad, 0.0)),
		Vector3(ground_xz.x, _ground_height_at(ground_xz) + DROP_HEIGHT_M, ground_xz.y)
	)

	if rounds != 0:
		ammo.add(assembly_id, _round_id, rounds)

	if is_player:
		_player_guns = guns
		_player_power = motion.power
		_gun_slot = gun_slot
		_controls = ControlSystem.new()
		# Must be set before it enters the tree: a ControlSystem with no record
		# samples the input map sixty times a second and discards all of it.
		_controls.input = motion.input
		runtime.add_child(_controls)
		_capture_condition_baseline(runtime)
	else:
		_attach_driver(runtime, motion, guns, gun_slot)

	return runtime


## Doc 05 §15.7's producer, on an Assembly with nobody in it.
##
## Every field is set before the node enters the tree, because [AiDriver] caches
## its locomotion family, its stand-off, its RNG seed and its scan phase there —
## a driver configured afterwards has already chosen how it drives.
func _attach_driver(
	runtime: AssemblyRuntime, motion: MotiveSystem, guns: EffectorSystem, gun_slot: int
) -> void:
	var driver := AiDriver.new()
	driver.name = "AiDriver"
	driver.runtime = runtime
	driver.input = motion.input
	driver.motion = motion
	driver.guns = guns
	driver.effector_slot = gun_slot
	driver.registry = registry
	driver.roster = _roster
	driver.difficulty = OPPONENT_DIFFICULTY
	runtime.add_child(driver)


func _lay_out(ctx: BuildContext) -> void:
	_place(ctx, CORE_KEY, BUILD_CORE, OrientationTable.IDENTITY_INDEX)
	_place(ctx, POWER_KEY, BUILD_POWER, OrientationTable.IDENTITY_INDEX)
	_place(ctx, CELL_KEY, BUILD_CELL, OrientationTable.IDENTITY_INDEX)
	_place(ctx, GUN_KEY, BUILD_GUN, OrientationTable.IDENTITY_INDEX)
	for cell: Vector3i in BUILD_HUBS:
		_place(ctx, HUB_KEY, cell, OrientationTable.IDENTITY_INDEX)
	for cell: Vector3i in BUILD_WHEELS:
		var key := WHEEL_KEY if cell.z < FRONT_AXLE_Z else REAR_KEY
		var inboard := Vector3.RIGHT if cell.x < BUILD_CORE.x else Vector3.LEFT
		_place(ctx, key, cell, OrientationTable.upright_facing(inboard))


## CLAUDE.md §10 rule 9: the garage, the auto-assembler, blueprint loading and
## server-side re-validation all go through this identical chain, and so does
## this. A scene that placed parts by writing state directly would be the one
## build in the project that had never been validated.
static func _place(
	ctx: BuildContext, key: StringName, cell: Vector3i, orientation: int
) -> void:
	var def := PartRegistry.definition_by_key(key)
	if def == null:
		push_error("MatchScreen: unknown part key '%s'" % key)
		return
	var candidate := PlacementCandidate.create(def, cell, orientation)
	var reject := PlacementValidator.validate(ctx, candidate)
	if reject != PlacementValidator.Reject.NONE:
		push_error(
			"MatchScreen: '%s' at %s rejected (%d): %s"
			% [key, cell, reject, PlacementValidator.REJECT_KEYS[reject]]
		)
		return
	PlacementValidator.commit(ctx, candidate)


## ===== PER TICK ========================================================


## §14.1's producer. Everything continuous the HUD shows is written here, once,
## from state this class already holds.
func _on_tick_started(tick: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if camera != null and _player_guns != null:
		_player_guns.aim_point_world = camera.aim_point()
		_player_guns.set_trigger(0, Input.is_action_pressed(&"effector_fire_primary"))

	var input := _controls.input
	_frame.tick = tick
	_frame.speed_mps = _player.body.linear_velocity.length()
	_frame.throttle = input.throttle
	_frame.steer = input.steer
	_frame.brake = input.brake
	_frame.integrity_fraction = (
		_integrity_now / maxf(_integrity_total, SyndicateConstants.EPSILON_LINEAR)
	)
	_frame.parts_alive = _parts_alive
	_frame.parts_total = _parts_total
	# Doc 05 §7.4's budget, re-solved only on structural events. Read here rather
	# than recomputed: MotiveSystem owns when it is solved, and a HUD that
	# re-solved it per tick would be a second owner of the answer.
	if _player_power != null:
		_frame.power_draw_pu = _player_power.draw_pu
		_frame.power_capacity_pu = _player_power.supply_pu
	_frame.rounds_remaining = ammo.rounds_stored(_player.assembly_id, _round_id)
	_frame.reticle_state = _reticle_state()
	_frame.assemblies_standing = registry.ids().size()
	if hud != null:
		hud.present(_frame)


## §14.3's five states, read from the mount rather than re-derived.
func _reticle_state() -> HudFrame.ReticleState:
	if _player_guns == null or _gun_slot == SyndicateConstants.INVALID_SLOT:
		return HudFrame.ReticleState.NO_EFFECTOR
	var hp := _player_guns.hardpoint(_gun_slot)
	if hp == null:
		return HudFrame.ReticleState.NO_EFFECTOR
	if not hp.solution_in_arc:
		# Doc 07 §4.3.1. A mount that cannot physically reach the target is a
		# driving problem, and §14.3 keeps it distinct from a mount that is
		# merely still slewing so the player is told which one they have.
		return HudFrame.ReticleState.SEEKING
	if not hp.on_target:
		return HudFrame.ReticleState.TRACKING
	if not ammo.has_rounds(_player.assembly_id, _round_id):
		return HudFrame.ReticleState.NO_AMMO
	return HudFrame.ReticleState.ON_TARGET


## ===== CONDITION =======================================================


func _capture_condition_baseline(runtime: AssemblyRuntime) -> void:
	_integrity_total = 0.0
	_parts_total = 0
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var st := runtime.state(slot)
		if st == null:
			continue
		_integrity_total += st.integrity
		_parts_total += 1
	_integrity_now = _integrity_total
	_parts_alive = _parts_total


func _on_part_damaged(assembly_id: int, _slot: int, amount: float, _channel: int) -> void:
	if _player == null or assembly_id != _player.assembly_id:
		return
	_integrity_now = maxf(0.0, _integrity_now - amount)


func _on_part_destroyed(assembly_id: int, _slot: int, _cause: int) -> void:
	if _player == null or assembly_id != _player.assembly_id:
		return
	_parts_alive = maxi(0, _parts_alive - 1)


## Half the diagonal of the Assembly's occupied extent, for §13.5's follow
## distance. Derived from the lattice rather than from a rendered bound, because
## a visual bound would make the camera depend on the asset maturity stage — the
## camera would move when an artist promoted a part, which is exactly the
## coupling Invariant I-1 exists to prevent.
static func _bounding_radius(runtime: AssemblyRuntime) -> float:
	var lo := Vector3i(2147483647, 2147483647, 2147483647)
	var hi := Vector3i(-2147483647, -2147483647, -2147483647)
	var seen := false
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var st := runtime.state(slot)
		if st == null:
			continue
		seen = true
		var cell := st.origin_cell
		lo = Vector3i(mini(lo.x, cell.x), mini(lo.y, cell.y), mini(lo.z, cell.z))
		hi = Vector3i(maxi(hi.x, cell.x), maxi(hi.y, cell.y), maxi(hi.z, cell.z))
	if not seen:
		return DEFAULT_BOUNDING_RADIUS_M
	var extent := Vector3(hi - lo) * SyndicateConstants.LATTICE_UNIT_M
	return maxf(DEFAULT_BOUNDING_RADIUS_M, extent.length() * 0.5)


## The yaw about world up that points an Assembly's [code]-Z[/code] — doc 07
## §7.2's forward — from [param from] at [param to].
static func _yaw_towards(from: Vector2, to: Vector2) -> float:
	var d := (to - from).normalized()
	return atan2(-d.x, -d.y)
