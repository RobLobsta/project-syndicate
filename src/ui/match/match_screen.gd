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
## [b]The player drives what they built.[/b] [member player_blueprint] arrives
## from the garage as a list of integer placements and every one of them goes
## back through [PlacementValidator] here — the same chain the garage used and
## the same chain doc 12 §4.3 makes a server run on a blueprint a client sent.
## Re-validating a build that was legal ten seconds ago in the same process looks
## redundant and is the point: this is the path a build will take across a
## network, and a shortcut in it now is a hole in it then.
##
## The opponents are spawned from [method StarterBlueprint.skirmisher] rather
## than from the player's build. A test run against three copies of whatever the
## player just made is a different game every time and is not a measurement of
## anything; doc 06's generator is what eventually varies them.
##
## Each opponent carries an [AiDriver] — doc 05 §15.7 — on the other side of a
## roster this class owns and every driver shares. They close, aim through the
## identical [EffectorSystem] the player's trigger reaches, and shoot back with a
## finite store. Nothing about them is privileged: the same eight numbers, the
## same aim point, the same jam chance, and a miss that puts a real round into
## the terrain.

## Raised when the player asks to go back and change the build. [ShellRoot] frees
## this screen and opens the garage on the blueprint they arrived with.
signal garage_requested
## Raised when the player asks to fight the same build again.
signal rematch_requested

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

## What the player drives. Assigned by [ShellRoot] before this node enters the
## tree; a match that was handed nothing spawns the shipped starter, which is
## what makes the arena scene runnable on its own.
var player_blueprint: Blueprint = null

## Every projectile type a match may need, in registration order.
##
## [b]Append only.[/b] [ProjectileRegistry] assigns ids by registration order and
## doc 12 §6 puts those ids on the wire, so reordering this array renames every
## round in flight between a server and a client that disagree about it — the
## same rule, and the same reason, as the part manifest of doc 01 §5.2.
##
## A match registers all of them rather than the one the shipped starter happens
## to chamber: a player's blueprint may carry any Effector Module in the
## catalogue, and a round the registry has never heard of is an Effector Module
## that silently declines to fire.
const ROUND_KEYS: Array[StringName] = [
	&"proj.kinetic.ap_30",
	&"proj.kinetic.ap_12",
]

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
## Doc 11 §16. Counts the teams out and says once that the match is over.
var match_state: MatchState = null

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
## The player's record. Held here as well as on [member _controls] because §16.2
## takes the controls off the Assembly when the match ends and the HUD still has
## to read what the last tick demanded.
var _player_input: ControlInput = null
## Doc 11 §16.2. Set once, in [method _on_match_concluded].
var _concluded: bool = false
var _gun_slot: int = SyndicateConstants.INVALID_SLOT
## The projectile the [b]player's[/b] Effector Module chambers, resolved from
## their build rather than assumed. §14.3's ammunition state and §14.1's round
## counter both read this, and a HUD that counted a store the player's module
## does not draw from would report "no ammunition" over a full magazine.
var _round_id: int = -1

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
	_build_match_state()

	# Collision has to exist before anything is dropped onto it. The streamer
	# normally anchors on the Assemblies, so the first evaluation is seeded with
	# the spawn points instead — there is nothing else to be near yet.
	_build_ground_streaming()
	ground_streamer.extra_anchors = _spawn_anchors()
	# prime() rather than evaluate(): the per-evaluation cap exists to spread
	# instantiation across ticks, and there are no ticks yet. Four chunks would
	# leave the spawns hanging over unstreamed ground.
	ground_streamer.prime()

	if player_blueprint == null:
		player_blueprint = StarterBlueprint.skirmisher()
	_player = _spawn(
		player_blueprint, PLAYER_SPAWN_XZ, 0.0, PLAYER_ROUNDS, PLAYER_TEAM, true
	)
	var opponent := StarterBlueprint.skirmisher()
	for xz: Vector2 in TARGET_SPAWN_XZ:
		_spawn(
			opponent,
			xz,
			_yaw_towards(xz, PLAYER_SPAWN_XZ),
			TARGET_ROUNDS,
			OPPONENT_TEAM,
			false
		)
	# The Assemblies now anchor it themselves.
	ground_streamer.extra_anchors = PackedVector3Array()

	_build_camera()
	_build_hud()

	EventBus.part_damaged.connect(_on_part_damaged)
	EventBus.part_destroyed.connect(_on_part_destroyed)
	MatchClock.tick_started.connect(_on_tick_started)
	InputMethod.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


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


## Two meanings for one key, decided by whether the match is over.
##
## [b]During the match[/b] [code]build_cancel[/code] releases the mouse, because
## a captured mouse with no way out is the oldest bad manner a 3D game has, and a
## click takes it back.
##
## [b]After the conclusion[/b] it leaves for the garage, and
## [code]ui_accept[/code] fights the same build again. §16.2 keeps the mouse
## captured at the conclusion on purpose — §13.6 reads mouse motion for the look,
## so a released mouse is an orbit camera that cannot orbit — which means the two
## ways out of a finished match have to be keys, and the end card names them.
func _unhandled_input(event: InputEvent) -> void:
	if _concluded:
		if event.is_action_pressed(&"build_cancel"):
			garage_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"ui_accept"):
			rematch_requested.emit()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"build_cancel"):
		InputMethod.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if InputMethod.mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			InputMethod.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


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
	for key: StringName in ROUND_KEYS:
		projectile_registry.register(load("res://data/projectiles/%s.tres" % key))
	projectile_registry.seal()

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


## Doc 11 §16.1. Built before the spawns, because every spawn registers with it
## and an Assembly that reached the arena unregistered is one whose destruction
## cannot end the match.
func _build_match_state() -> void:
	match_state = MatchState.new()
	match_state.name = "MatchState"
	match_state.local_team = PLAYER_TEAM
	match_state.match_concluded.connect(_on_match_concluded)
	add_child(match_state)


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
	blueprint: Blueprint,
	ground_xz: Vector2,
	yaw_rad: float,
	rounds: int,
	team: int,
	is_player: bool
) -> AssemblyRuntime:
	var assembly_id := _next_assembly_id
	_next_assembly_id += 1
	_roster[assembly_id] = team
	match_state.register(assembly_id, team)

	var ctx := BuildContext.with_physics(assembly_id)
	_contexts.append(ctx)
	_lay_out(ctx, blueprint)

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
		# Stocked per projectile type (doc 07 §13), so an Assembly is given a
		# store of whatever its own modules chamber and nothing else. A build
		# carrying two modules that share a round draws both from one store,
		# which is what makes a second one a trade against the Support Modules
		# holding the rounds rather than a free doubling of output.
		for id: int in _round_ids_of(runtime):
			ammo.add(assembly_id, id, rounds)

	if is_player:
		_player_guns = guns
		_player_power = motion.power
		_gun_slot = gun_slot
		_round_id = _round_id_at(runtime, gun_slot)
		_player_input = motion.input
		_controls = ControlSystem.new()
		# Must be set before it enters the tree: a ControlSystem with no record
		# samples the input map sixty times a second and discards all of it.
		_controls.input = motion.input
		runtime.add_child(_controls)
		_capture_condition_baseline(runtime)
	else:
		_attach_driver(runtime, motion, guns, gun_slot)

	return runtime


## Rounds the player's own Effector Module has left in store.
##
## Public so that `tests/integration/test_screen_flow.gd` can assert the join
## between three things that are each correct on their own and are easy to wire
## together wrongly: which projectile a module chambers, which stores an Assembly
## is granted at spawn, and which store §14.1's counter reads. A build whose
## module draws a round the ledger never stocked declines to fire for the whole
## match and reports itself out of ammunition from the first frame — and every
## step of that is a silent success in isolation.
func player_rounds_remaining() -> int:
	if _player == null or ammo == null or _round_id < 0:
		return 0
	return ammo.rounds_stored(_player.assembly_id, _round_id)


## The projectile id [param slot]'s Effector Module chambers, or -1.
##
## Resolved through [ProjectileRegistry] from the key the profile authors, which
## is the same lookup [EffectorSystem.register] makes — asking the registry twice
## is cheaper than a second owner of the mapping, and this one runs once per
## spawn rather than per shot.
##
## A melee module authors an empty key and answers -1, which is the correct
## answer rather than a failure: doc 07 §15 resolves by swept volume and there is
## no round to count.
func _round_id_at(runtime: AssemblyRuntime, slot: int) -> int:
	if slot == SyndicateConstants.INVALID_SLOT:
		return -1
	var def := runtime.definition_at(slot)
	if def == null or def.effector_profile == null:
		return -1
	return projectile_registry.id_of(def.effector_profile.projectile_key)


## Every distinct projectile id [param runtime]'s Effector Modules chamber,
## ascending.
##
## Ascending and deduplicated so that the stores an Assembly is granted are a
## function of its build and not of the order its slots happened to be walked in
## — Invariant I-9, and the ledger is replicated.
func _round_ids_of(runtime: AssemblyRuntime) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var def := runtime.definition_at(slot)
		if def == null or def.part_class != PartEnums.PartClass.EFFECTOR_MODULE:
			continue
		var id := _round_id_at(runtime, slot)
		if id >= 0 and not ids.has(id):
			ids.push_back(id)
	ids.sort()
	return ids


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


## Rebuilds [param bp] into [param ctx] through the ordinary validation chain.
##
## CLAUDE.md §10 rule 9: the garage, the auto-assembler, blueprint loading and
## server-side re-validation all go through this identical chain, and so does
## this. A scene that placed parts by writing state directly would be the one
## build in the project that had never been validated.
##
## A refusal is reported and the Assembly is spawned with what was committed
## before it. Dropping the whole build would take a player who edited one part
## too many from "that part is not there" to "the match did not start", and the
## first of those is the one they can act on.
static func _lay_out(ctx: BuildContext, bp: Blueprint) -> void:
	bp.apply(ctx, _on_placement_refused)


static func _on_placement_refused(index: int, reason_key: StringName) -> void:
	push_error("MatchScreen: blueprint placement %d refused: %s" % [index, reason_key])


## ===== PER TICK ========================================================


## §14.1's producer. Everything continuous the HUD shows is written here, once,
## from state this class already holds.
func _on_tick_started(tick: int) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if camera != null and _player_guns != null and not _concluded:
		_player_guns.aim_point_world = camera.aim_point()
		_player_guns.set_trigger(0, Input.is_action_pressed(&"effector_fire_primary"))
	_frame.target_acquired = camera != null and camera.aim_on_hull() and not _concluded

	var input := _player_input
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
	# A module that chambers nothing is not a module that is out of ammunition.
	# Doc 07 §15's melee path resolves by swept volume and never touches the
	# ledger, so counting its rounds would report `NO_AMMO` over an edge that is
	# perfectly ready to swing.
	if _round_id >= 0 and not ammo.has_rounds(_player.assembly_id, _round_id):
		return HudFrame.ReticleState.NO_AMMO
	return HudFrame.ReticleState.ON_TARGET


## ===== THE END OF THE MATCH ============================================


## Doc 11 §16.2. The one thing that happens when a side is gone.
##
## Three effects and each one answers something a player would otherwise read as
## a fault. The controls come off the Assembly, because a [ControlSystem] left
## sampling the input map writes a throttle demand into a wreck sixty times a
## second and a build that still has its Motive Assemblies drives itself off into
## the terrain with nobody at the controls. The camera goes to
## [constant ChaseCamera.Mode.ORBIT], because §13.3's chase mode chases a heading
## that no longer changes and the last thing a player sees should be something
## they chose to look at. And the card says so.
##
## [b]The mouse stays captured.[/b] Releasing it here was the obvious courtesy
## and it is the wrong one: §13.6 reads mouse motion for the look, so a released
## mouse is an orbit camera that cannot orbit. The card names the binding that
## releases it, which is the same answer §14.6 gives for every other control
## nobody can guess.
func _on_match_concluded(outcome: int, _winning_team: int) -> void:
	_concluded = true
	if _player_guns != null:
		_player_guns.set_trigger(0, false)
	if _controls != null:
		# Removed before it is freed. The node disconnects from the clock in
		# `_exit_tree`, and `queue_free` alone would leave it sampling for the rest
		# of the frame — LEARNED_FACTS.md §1 fact 53's ordering, for a different reason.
		_controls.get_parent().remove_child(_controls)
		_controls.queue_free()
		_controls = null
	if _player_input != null:
		_player_input.throttle = 0.0
		_player_input.steer = 0.0
		_player_input.brake = 0.0
		_player_input.collective = 0.0
		_player_input.cyclic = Vector2.ZERO
		_player_input.yaw = 0.0
	if camera != null and camera.mode == ChaseCamera.Mode.CHASE:
		# Through the toggle, so the picture does not cut: §13.3 rebases the look
		# offset across the switch and assigning the mode directly would not.
		camera.toggle_mode()
	if hud != null:
		hud.present_outcome(outcome)


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
