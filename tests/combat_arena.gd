class_name CombatArena
extends RefCounted
## A match, minus the match scene: ground, the combat systems, and any number of
## Assemblies built from shipped data that drive at each other and shoot.
##
## [code]tests/physics/test_duel.gd[/code] wired one engagement by hand and is
## still the reference for what the wiring [i]is[/i]. This is the same wiring
## made reusable, because the interesting questions stopped being "does a round
## reach a Core Module" and became "what happens when the two builds move
## differently" — which needs several engagements between several kinds of
## Assembly and cannot be answered by copying four hundred lines per fight.
##
## [b]It is a fixture, not architecture.[/b] Two things here are standing in for
## systems that do not exist yet and are named so that nobody mistakes them for
## a design:
##
## [enum]
## [*] [b]The ground is a [StaticBody3D] slab.[/b] Document 09 owns Dynamic
##     Ground Arrays and nothing here pre-empts it.
## [*] [b]The tactics in [method command] are a test pilot, not
##     [code]src/ai/[/code].[/b] They read the world and write a [ControlInput],
##     which is exactly the contract doc 05 §6.0 gives the AI driver, and they
##     make no decision the motion layer could not be given by a person holding
##     a key. The rotary attitude controller is the one place that goes further
##     — see [method _fly] — and it is there because an Assembly that only flies
##     when a human is flying it cannot be put in a test at all.
## [/enum]
##
## Every fight is decided by the simulation. Nothing scripts a hit, a winner, or
## a death; the recipes differ in mass, footprint, and how they get around, and
## the outcome falls out of that.

## ===== RECIPES =========================================================

## The shipped builds these fights are fought with. A recipe is a layout, not a
## class: every one of them is an Assembly with a Core Module at slot 0, and
## what separates them is the locomotion family under it and what it carries.
enum Recipe {
	## Four wheeled contacts, a Prime Mover, one Effector Module. Roughly 1.1 t
	## and the lightest thing here that can shoot back.
	WHEELED_LIGHT,
	## The same, with an Energy Cell in the tail. Heavier, longer, and it takes
	## more rounds to put down because there is one more part to eat them.
	WHEELED_HEAVY,
	## Two tracked bogies on stations under the flanks. Skid-steered, heaviest
	## contact patch, no steering geometry to lose.
	TRACKED,
	## Four ambulatory limbs. Stands tall, walks at about 1.5 m/s, and carries
	## its Core Module a metre and a half further off the ground than anything
	## else here.
	AMBULATORY,
	## A pair of coaxial rotor discs on outboard stations, an Energy Cell to
	## cover their draw, and an Effector Module. It hovers, which means nothing
	## but thrust holds it up and every newton of recoil goes straight into its
	## flight path.
	ROTARY,
}

const CORE_KEY := &"core.command.compact.t2"
const HUB_KEY := &"str.hub.axle_station.t2"
const WHEEL_KEY := &"mot.wheeled.allroad.t2"
const REAR_KEY := &"mot.wheeled.fixed_rear.t2"
const TRACK_KEY := &"mot.tracked.short_bogie.t2"
const LIMB_KEY := &"mot.limb.strider.t4"
const ROTOR_KEY := &"mot.rotor.coaxial_mid.t3"
const POWER_KEY := &"pmv.combustion.standard.t2"
const CELL_KEY := &"cel.static.standard.t3"
const GUN_KEY := &"eff.ballistic.autocannon_30.t3"
const ROUND_KEY := &"proj.kinetic.ap_30"

## ===== LAYOUTS =========================================================
## Cell origins, per recipe. Integer lattice coordinates throughout (Invariant
## I-6); the only floats in this file are world poses and the pilot's arithmetic.

const GROUND_CORE := Vector3i(24, 4, 24)
const GROUND_POWER := Vector3i(24, 7, 24)
const GROUND_CELL := Vector3i(24, 4, 29)

## The Effector Module goes on the [b]nose[/b], at the Core Module's own height,
## and that is the one deliberate departure from [code]test_duel.gd[/code]'s
## build. §10.5 authors 1450 N·s of recoil per round and doc 07 §8 applies it at
## the muzzle: what decides whether that flips the Assembly is not the impulse
## but the [i]height of the muzzle above the centre of mass[/i], because the
## fore-aft offset is parallel to the recoil and contributes no moment at all.
##
## On the roof the muzzle sits two metres up and one round is 3.6 rad/s of pitch
## (handoff §4.11). Here it sits about a quarter of a metre above the centre of
## mass on every ground recipe and within a hand's breadth of it on the rotary
## one, so the same round is a rock rather than a backflip and the fight lasts
## long enough to be a fight. The rearward push is untouched and is meant to be:
## it is what the recoil actually does to a vehicle this size.
const GROUND_GUN := Vector3i(24, 6, 21)

const WHEEL_HUBS: Array[Vector3i] = [
	Vector3i(22, 2, 23), Vector3i(26, 2, 23), Vector3i(22, 2, 27), Vector3i(26, 2, 27)
]
const WHEEL_ORIGINS: Array[Vector3i] = [
	Vector3i(19, 3, 22), Vector3i(19, 3, 28), Vector3i(28, 3, 21), Vector3i(28, 3, 27)
]
## Contacts forward of this row steer; the pair behind it is fixed. An Assembly
## on which every contact steers crabs instead of turning (handoff §4.4).
const FRONT_AXLE_Z: int = 24

const TRACK_HUBS: Array[Vector3i] = [Vector3i(22, 2, 24), Vector3i(26, 2, 24)]
const TRACK_ORIGINS: Array[Vector3i] = [Vector3i(19, 3, 24), Vector3i(28, 3, 23)]

## The ambulatory build sits high in the lattice because a limb hangs below its
## station and the lattice floor is at y = 0.
const AMBULATORY_CORE := Vector3i(24, 14, 24)
const AMBULATORY_POWER := Vector3i(24, 17, 24)
const AMBULATORY_GUN := Vector3i(24, 14, 21)
## Station, then the limb hanging off it, four times. A station at orientation 8
## puts its AXLE faces on ±Y, so it bolts to the Core Module's flank through a
## neutral face and offers a downward drive station.
const AMBULATORY_LEGS: Array[Vector3i] = [
	Vector3i(20, 14, 23), Vector3i(20, 13, 22),
	Vector3i(26, 14, 23), Vector3i(27, 13, 22),
	Vector3i(20, 14, 26), Vector3i(20, 13, 26),
	Vector3i(26, 14, 26), Vector3i(27, 13, 26),
]
const HUB_AXLE_DOWN_ORIENTATION: int = 8

## A disc's own AXLE face is its [b]underside[/b], where a wheel's and a track's
## is their `-Z` flank and a limb's is its top, so a mast needs a station under
## it exactly as a limb needs one over it. And an AXLE station's two drive faces
## are opposite each other, so a station cannot bolt on through one and offer
## the other — it attaches through a neutral flank and both drive faces stay
## free (doc 01 §4.2). That is why the stations here go on the Core Module's
## [i]sides[/i] at orientation 8, which puts their AXLE faces on ±Y, and not on
## its roof where the underside would be a drive face with nothing to drive.
##
## Two discs, not one, and that falls straight out of the geometry: a station on
## a flank carries its mast three quarters of a metre off the centreline, and a
## single disc there rolls the Assembly over. The pair is symmetric, doubles the
## lift, and costs a second 150 PU draw — which is what the Energy Cell is for.
const ROTARY_CORE := Vector3i(24, 4, 24)
const ROTARY_MAST_HUBS: Array[Vector3i] = [Vector3i(20, 5, 24), Vector3i(26, 5, 24)]
const ROTARY_DISCS: Array[Vector3i] = [Vector3i(21, 7, 24), Vector3i(27, 7, 24)]
const ROTARY_POWER := Vector3i(24, 4, 29)
## Slung under the belly rather than in the tail, and that is arithmetic rather
## than taste. The Effector Module puts 196 kg two metres ahead of the Core
## Module; a 175 kg Energy Cell behind it drags the centre of mass a third of a
## metre [i]aft of the disc[/i], and trimming that offset out costs 15° of
## swashplate against a 14° cone — so the Assembly would hover with no cyclic
## authority left to fly with. Underneath, it balances the nose in the vertical
## and contributes nothing fore or aft.
const ROTARY_CELL := Vector3i(24, 1, 24)
const ROTARY_GUN := Vector3i(24, 6, 21)

## ===== FIXTURE =========================================================

const GROUND_HALF_HEIGHT: float = 2.0
const GROUND_SPAN_M: float = 900.0
## Height a ground recipe is dropped from, above the slab surface.
const DROP_HEIGHT_M: float = 2.0
## Height the ambulatory recipe is dropped from. Its Core Module rides higher, so
## the same drop would leave it standing on its hull.
const AMBULATORY_DROP_HEIGHT_M: float = 4.0

## ===== PILOT ===========================================================
## Doc 05 §6.0's [ControlInput] is the whole interface. Every gain below turns
## world state into one of its eight numbers and nothing else.

## Heading error, in radians, at which the steering demand saturates.
const STEER_SATURATION_RAD: float = 0.35
## The same, for the ambulatory family, which turns far more slowly.
const AMBULATORY_TURN_SATURATION_RAD: float = 0.60
## Steering demand per radian per second of hull yaw, opposing it.
const AMBULATORY_YAW_DAMPING: float = 0.55
## Degrees within an authored pitch limit that count as sitting on the stop.
const ELEVATION_STOP_EPSILON_DEG: float = 0.05
## Ceiling on an ambulatory steering demand. Below one, because §13.5 spends the
## same number on the lateral half of the desired velocity: a saturated demand
## walks the Assembly 45° off its own nose, which is a circle rather than an
## approach.
const AMBULATORY_STEER_AUTHORITY: float = 0.5
## Metres from the target a ground recipe stops closing at.
const GROUND_STAND_OFF_M: float = 6.0
## Metres from the target a rotary recipe holds station at. Further out than the
## ground families because its muzzle is above theirs and the module can only
## depress 8° (§10.5) — closing further would put the target under the gun.
const ROTARY_STAND_OFF_M: float = 22.0
## Metres per second a rotary recipe closes at.
const ROTARY_APPROACH_MPS: float = 8.0
## Height above the slab a rotary recipe holds.
const HOVER_HEIGHT_M: float = 4.0
## Collective demand per metre of altitude error, and per metre per second of
## climb rate. The second term is the damper; without it the disc chases the
## altitude and the Assembly porpoises.
const HOVER_HEIGHT_GAIN: float = 0.55
const HOVER_CLIMB_GAIN: float = 0.45
## Horizontal acceleration demanded per metre per second of velocity error.
const CYCLIC_VELOCITY_GAIN: float = 1.2
## Ceiling on that demand. `g · tan(12°)` — inside the 14° swashplate cone, so
## the controller never asks for a tilt [RotorSolver] will clamp away underneath
## it and then integrate a demand it never met.
const CYCLIC_ACCEL_LIMIT_MPS2: float = 2.08
## Pedal demand per radian of heading error, and per radian per second of yaw.
const YAW_HEADING_GAIN: float = 0.6
const YAW_RATE_GAIN: float = 0.5

var registry: AssemblyRegistry = null
var resolver: DamageResolver = null
var projectiles: ProjectileSystem = null
var projectile_registry: ProjectileRegistry = null
var ammo: AmmoLedger = null
var combatants: Array[Combatant] = []

## Every `part_destroyed` seen, in order, as (assembly_id, slot).
var destroyed: Array[Vector2i] = []
## Assembly ids that lost slot 0, in the order they fell. Invariant I-2 makes
## that the end of an Assembly; the match layer that should say so does not
## exist yet, so the arena reads the raw signal and calls it a kill.
var terminated: PackedInt32Array = PackedInt32Array()
## Every band transition seen, in order, as (assembly_id, slot, band after).
## Invariant I-5's five bands are only observable through this signal; a Core
## Module that went from NOMINAL to DESTROYED in one packet would satisfy every
## other assertion in a fight and would mean the band machinery never ran.
var band_events: Array[Vector3i] = []
## Rounds emitted across the whole engagement.
var shots_fired: int = 0
## assembly_id -> rounds it emitted.
var shots_by: Dictionary = {}
## Damage packets that landed, and assembly_id -> total integrity taken off it.
## A fight can be lost by every round missing, and shots alone cannot tell that
## apart from a fight where every round landed on armour that soaked it.
var hits_landed: int = 0
var damage_by_target: Dictionary = {}
## Ticks the last call to [method engage] actually ran for.
var ticks_engaged: int = 0

var _ground: StaticBody3D = null
var _contexts: Array[BuildContext] = []
var _next_assembly_id: int = 1
var _round_id: int = -1


## ===== SETUP ===========================================================


## Builds the slab and the four systems every Assembly in the arena shares.
func open() -> void:
	registry = AssemblyRegistry.new()
	ammo = AmmoLedger.new()
	projectile_registry = ProjectileRegistry.new()
	projectile_registry.register(load("res://data/projectiles/%s.tres" % ROUND_KEY))
	projectile_registry.seal()
	_round_id = projectile_registry.id_of(ROUND_KEY)

	_ground = StaticBody3D.new()
	_ground.name = "GroundFixture"
	_ground.collision_layer = CollisionLayers.LAYER_GROUND
	_ground.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SPAN_M, GROUND_HALF_HEIGHT * 2.0, GROUND_SPAN_M)
	shape.shape = box
	_ground.add_child(shape)
	EventBus.get_tree().root.add_child(_ground)
	_ground.global_position = Vector3(0.0, -GROUND_HALF_HEIGHT, 0.0)

	var world := _ground.get_world_3d()

	resolver = DamageResolver.new()
	resolver.registry = registry
	resolver.space = world.direct_space_state
	EventBus.get_tree().root.add_child(resolver)

	projectiles = ProjectileSystem.new()
	projectiles.registry = projectile_registry
	projectiles.resolver = resolver
	projectiles.space = world.direct_space_state
	EventBus.get_tree().root.add_child(projectiles)

	EventBus.part_destroyed.connect(_on_part_destroyed)
	EventBus.effector_fired.connect(_on_effector_fired)
	EventBus.part_band_changed.connect(_on_part_band_changed)
	EventBus.part_damaged.connect(_on_part_damaged)


## Frees everything the arena put in the tree. Call from `after_all`; a leaked
## runtime stays connected to the bus and resolves the next file's fixture
## underneath it.
func close() -> void:
	if EventBus.part_destroyed.is_connected(_on_part_destroyed):
		EventBus.part_destroyed.disconnect(_on_part_destroyed)
	if EventBus.effector_fired.is_connected(_on_effector_fired):
		EventBus.effector_fired.disconnect(_on_effector_fired)
	if EventBus.part_band_changed.is_connected(_on_part_band_changed):
		EventBus.part_band_changed.disconnect(_on_part_band_changed)
	if EventBus.part_damaged.is_connected(_on_part_damaged):
		EventBus.part_damaged.disconnect(_on_part_damaged)
	for c: Combatant in combatants:
		if c.runtime != null and is_instance_valid(c.runtime):
			c.runtime.free()
	combatants.clear()
	for node: Node in [projectiles, resolver, _ground] as Array[Node]:
		if node != null and is_instance_valid(node):
			node.free()
	for ctx: BuildContext in _contexts:
		ctx.dispose()
	_contexts.clear()


## Builds one Assembly of [param recipe] on [param team], facing [param yaw_rad]
## about the world up, at [param ground_xz] on the slab.
##
## [param rounds] is the store it is given; [constant AmmoLedger.UNLIMITED] is
## accepted and 0 makes an Assembly that aims, tracks, and cannot shoot — the
## asymmetry [code]test_duel.gd[/code] uses to get a decided outcome out of two
## identical builds.
func spawn(
	recipe: int, team: int, ground_xz: Vector2, yaw_rad: float, rounds: int
) -> Combatant:
	var assembly_id := _next_assembly_id
	_next_assembly_id += 1

	var ctx := BuildContext.with_physics(assembly_id)
	_contexts.append(ctx)
	match recipe:
		Recipe.WHEELED_LIGHT:
			_lay_out_wheeled(ctx, false)
		Recipe.WHEELED_HEAVY:
			_lay_out_wheeled(ctx, true)
		Recipe.TRACKED:
			_lay_out_tracked(ctx)
		Recipe.AMBULATORY:
			_lay_out_ambulatory(ctx)
		Recipe.ROTARY:
			_lay_out_rotary(ctx)
		_:
			push_error("CombatArena: unknown recipe %d" % recipe)

	var runtime := AssemblyRuntime.new()
	runtime.name = "Assembly%d" % assembly_id
	EventBus.get_tree().root.add_child(runtime)
	runtime.adopt(ctx)
	runtime.apply_mass_properties(MassSolver.compute(runtime.states, runtime.graph))
	registry.register(runtime)

	var motion := MotiveSystem.new()
	motion.runtime = runtime
	motion.input = ControlInput.new()
	motion.power = PowerSystem.new()
	motion.power.recompute(runtime.states, runtime.graph.alive)
	runtime.add_child(motion)

	var guns := EffectorSystem.new()
	guns.runtime = runtime
	guns.projectiles = projectiles
	guns.registry = projectile_registry
	guns.ammo = ammo
	# Invariant I-9. Two Assemblies in one match must not roll their spread and
	# jam in lockstep, and the same match must replay identically.
	guns.seed_rng(assembly_id)
	runtime.add_child(guns)

	var c := Combatant.new()
	c.recipe = recipe
	c.team = team
	c.runtime = runtime
	c.motion = motion
	c.guns = guns
	c.stand_off_m = ROTARY_STAND_OFF_M if recipe == Recipe.ROTARY else GROUND_STAND_OFF_M

	for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
		var def := runtime.definition_at(slot)
		if def == null:
			continue
		if def.part_class == PartEnums.PartClass.MOTIVE_ASSEMBLY:
			motion.register(slot, def, runtime.states[slot])
		elif def.part_class == PartEnums.PartClass.EFFECTOR_MODULE:
			guns.register(slot, def)
			c.gun_slot = slot
	motion.reassign_gait_phases()

	var height := DROP_HEIGHT_M
	if recipe == Recipe.AMBULATORY:
		height = AMBULATORY_DROP_HEIGHT_M
	elif recipe == Recipe.ROTARY:
		height = HOVER_HEIGHT_M
	runtime.body.global_transform = Transform3D(
		Basis.from_euler(Vector3(0.0, yaw_rad, 0.0)),
		Vector3(ground_xz.x, height, ground_xz.y)
	)
	if recipe == Recipe.ROTARY:
		# §9's convention: set the state, do not wait for it. Spooling a disc to
		# 85 rad/s through a 2.4 s time constant is ten simulated seconds of
		# nothing happening, and the spool is [RotorSolver]'s to assert.
		for slot: int in motion.motive_slots():
			var disc := motion.disc_state(slot)
			if disc != null:
				disc.omega_rad_s = _definition(runtime, slot).motive_profile \
					.rotor_profile.nominal_rad_s

	if rounds != 0:
		ammo.add(assembly_id, _round_id, rounds)
	combatants.append(c)
	return c


## ===== RUNNING =========================================================


## Lets everything fall onto its contacts, or a rotary Assembly find its hover,
## with the triggers cold. Physics tests cost real wall time at 60 Hz, so this
## is the shortest settle that leaves nothing still moving.
func settle(ticks: int) -> void:
	for c: Combatant in combatants:
		if c.recipe == Recipe.ROTARY:
			# A hovering Assembly has to be flown even while it settles, or it
			# is a 1.2 t brick falling five metres onto the slab.
			continue
		c.motion.input.throttle = 0.0
		c.motion.input.steer = 0.0
	for i: int in ticks:
		for c: Combatant in combatants:
			if c.recipe == Recipe.ROTARY:
				_fly(c, c.runtime.body.global_position)
		await _tick()


## Runs the engagement for at most [param max_ticks], commanding every live
## combatant once per tick and stopping early when only one team is left
## standing.
##
## Returns when the fight is over. [member ticks_engaged] is how long it took.
func engage(max_ticks: int) -> void:
	ticks_engaged = 0
	for i: int in max_ticks:
		for c: Combatant in combatants:
			command(c)
		await _tick()
		ticks_engaged += 1
		if teams_standing().size() <= 1:
			break
	for c: Combatant in combatants:
		c.guns.set_trigger(0, false)
		c.motion.input.throttle = 0.0
		c.motion.input.steer = 0.0
		c.motion.input.collective = 0.0
		c.motion.input.cyclic = Vector2.ZERO
		c.motion.input.yaw = 0.0


## One combatant's tick: pick a target, point the gun at it, hold the trigger,
## and drive.
##
## The target is the nearest live enemy, which is the whole of the tactics. A
## cleverer rule would be making claims about a target selector doc 07 §10 has
## not been written yet, and the point of these fights is the physics under the
## decision rather than the decision.
func command(c: Combatant) -> void:
	if not c.is_alive():
		c.retire()
		return
	var target := nearest_enemy(c)
	if target == null:
		c.retire()
		return

	var aim := target.runtime.part_world_position(SyndicateConstants.CORE_SLOT)
	c.guns.aim_point_world = aim
	c.guns.set_trigger(0, true)
	c.sample_gunnery()
	if c.recipe == Recipe.ROTARY:
		_fly(c, aim)
	else:
		_drive(c, aim)


## The nearest live enemy of [param c], or null when none is left.
func nearest_enemy(c: Combatant) -> Combatant:
	var best: Combatant = null
	var best_d := INF
	var from := c.runtime.body.global_position
	for other: Combatant in combatants:
		if other.team == c.team or not other.is_alive():
			continue
		var d := from.distance_squared_to(other.runtime.body.global_position)
		if d < best_d:
			best_d = d
			best = other
	return best


## Teams with at least one live Assembly, ascending.
func teams_standing() -> PackedInt32Array:
	var out := PackedInt32Array()
	for c: Combatant in combatants:
		if c.is_alive() and not out.has(c.team):
			out.append(c.team)
	out.sort()
	return out


## Live combatants on [param team].
func survivors(team: int) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for c: Combatant in combatants:
		if c.team == team and c.is_alive():
			out.append(c)
	return out


## ===== PRIVATE =========================================================


func _tick() -> void:
	await (Engine.get_main_loop() as SceneTree).physics_frame


## Ground families: close on the target and, for anything that steers, turn onto
## the bearing first.
func _drive(c: Combatant, aim: Vector3) -> void:
	var body := c.runtime.body
	var flat := aim - body.global_position
	flat.y = 0.0
	var input := c.motion.input
	input.brake = 0.0
	if flat.length_squared() < SyndicateConstants.EPSILON_LINEAR:
		input.throttle = 0.0
		input.steer = 0.0
		return

	var basis := body.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var closing := flat.length() > c.stand_off_m
	# Positive steer is right, and a right turn is a negative rotation about the
	# world up — so every demand below is the negated bearing error.
	var bearing := forward.signed_angle_to(flat.normalized(), Vector3.UP)
	if c.recipe == Recipe.AMBULATORY:
		# An ambulatory Assembly is flown on a [i]yaw rate[/i], not onto a
		# heading, and the reason is a hard number rather than a preference. Doc
		# 07 §4.3 converges a mount at half a degree and slews it at 65°/s, so a
		# hull turning faster than about 30°/s can never be tracked: the mount
		# closes 1.08° a tick and the demand moves further than that. An
		# ambulatory Assembly steered like a wheeled build turns at exactly that
		# rate and spends the engagement one step behind its own target.
		#
		# The damping term is what holds it under the limit. It is also the only
		# yaw authority the family has: doc 05 §6.0 gives [ControlInput] one
		# steering number, §13.5 spends it on both the turn command and the
		# lateral half of the desired velocity, and there is no third field that
		# would let one turn on the spot while walking somewhere else.
		input.throttle = 1.0 if closing else 0.0
		input.steer = clampf(
			-bearing / AMBULATORY_TURN_SATURATION_RAD
			+ body.angular_velocity.y * AMBULATORY_YAW_DAMPING,
			-1.0,
			1.0
		) * AMBULATORY_STEER_AUTHORITY
		return

	input.steer = clampf(-bearing / STEER_SATURATION_RAD, -1.0, 1.0)
	input.throttle = 1.0 if closing else 0.0


## The rotary family, and the one piece of this fixture that is a controller
## rather than a stand-in for a key.
##
## An Assembly held up by thrust alone cannot be driven by a throttle and a
## steer: the disc is not attached to anything, so a demand has to be resolved
## into a [i]world-space thrust direction[/i] and then back out into the swash
## angles that produce it from whatever attitude the body happens to be in. That
## last step is what makes it stable — the cyclic demand carries the body's own
## tilt in it, so a gust, a recoil impulse, or a shot-off part is corrected by
## the same arithmetic that holds the hover.
##
## Three loops, all through [ControlInput] and none of them applying a force:
## collective on altitude, cyclic on horizontal velocity, pedal on heading.
func _fly(c: Combatant, aim: Vector3) -> void:
	var body := c.runtime.body
	var input := c.motion.input
	# A disc only turns under throttle (doc 05 §12.2), so the rotary family flies
	# with the throttle open and modulates lift with the collective.
	input.throttle = 1.0

	var velocity := body.linear_velocity
	var altitude_error := (HOVER_HEIGHT_M - body.global_position.y)
	input.collective = clampf(
		altitude_error * HOVER_HEIGHT_GAIN - velocity.y * HOVER_CLIMB_GAIN, -1.0, 1.0
	)

	# Station-keeping rather than a one-way approach, and the module's 8° of
	# depression is the whole reason. A rotary Assembly that only ever closes
	# ends up directly over a ground target with its gun on the stop, unable to
	# point at the thing underneath it — so it backs off as readily as it closes.
	var flat := Vector3(aim.x - body.global_position.x, 0.0, aim.z - body.global_position.z)
	var wanted := Vector3.ZERO
	if flat.length() > SyndicateConstants.EPSILON_LINEAR:
		wanted = flat.normalized() * clampf(
			flat.length() - c.stand_off_m, -ROTARY_APPROACH_MPS, ROTARY_APPROACH_MPS
		)
	var accel := (wanted - Vector3(velocity.x, 0.0, velocity.z)) * CYCLIC_VELOCITY_GAIN
	accel = accel.limit_length(CYCLIC_ACCEL_LIMIT_MPS2)
	input.cyclic = _cyclic_for(c, Vector3(accel.x, SyndicateConstants.GRAVITY_MPS2, accel.z))

	if flat.length_squared() > SyndicateConstants.EPSILON_LINEAR:
		var forward := -body.global_transform.basis.z
		forward.y = 0.0
		var bearing := forward.normalized().signed_angle_to(flat.normalized(), Vector3.UP)
		input.yaw = clampf(
			bearing * YAW_HEADING_GAIN - body.angular_velocity.y * YAW_RATE_GAIN, -1.0, 1.0
		)


## The normalised cyclic demand that points this Assembly's disc along
## [param thrust_world].
##
## [method RotorSolver.thrust_direction] tilts the disc's rest-frame up about
## `+X` by the first swash angle and about `+Z` by the second, then carries the
## result through the part's placement orientation and the chassis basis. This
## inverts that composition exactly, which is why the controller can ask for a
## world direction and get a demand that produces it rather than one that
## approaches it.
func _cyclic_for(c: Combatant, thrust_world: Vector3) -> Vector2:
	var slots := c.motion.motive_slots()
	if slots.is_empty():
		return Vector2.ZERO
	var slot := slots[0]
	var st: PartInstanceState = c.runtime.states[slot]
	var rotor := _definition(c.runtime, slot).motive_profile.rotor_profile
	if st == null or rotor == null:
		return Vector2.ZERO

	var body_dir := c.runtime.body.global_transform.basis.inverse() * thrust_world.normalized()
	var rest := (OrientationTable.basis_for(st.orientation_index).inverse() * body_dir).normalized()
	# `up.rotated(RIGHT, a).rotated(BACK, b)` is `(-cos a·sin b, cos a·cos b, sin a)`.
	var pitch := asin(clampf(rest.z, -1.0, 1.0))
	var roll := atan2(-rest.x, rest.y)
	var limit := maxf(rotor.cyclic_limit_deg, SyndicateConstants.EPSILON_LINEAR)
	return Vector2(rad_to_deg(pitch), rad_to_deg(roll)).limit_length(limit) / limit


func _on_part_destroyed(assembly_id: int, slot: int, _cause: int) -> void:
	destroyed.append(Vector2i(assembly_id, slot))
	if slot == SyndicateConstants.CORE_SLOT:
		terminated.append(assembly_id)


func _on_effector_fired(assembly_id: int, _slot: int, _tick: int) -> void:
	shots_fired += 1
	shots_by[assembly_id] = int(shots_by.get(assembly_id, 0)) + 1


func _on_part_band_changed(assembly_id: int, slot: int, _before: int, after: int) -> void:
	band_events.append(Vector3i(assembly_id, slot, after))


func _on_part_damaged(assembly_id: int, _slot: int, amount: float, _channel: int) -> void:
	hits_landed += 1
	damage_by_target[assembly_id] = float(damage_by_target.get(assembly_id, 0.0)) + amount


## Bands [param slot] of [param assembly_id] was observed in, in order.
func bands_seen(assembly_id: int, slot: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for e: Vector3i in band_events:
		if e.x == assembly_id and e.y == slot:
			out.append(e.z)
	return out


## The yaw about the world up that points an Assembly's `-Z` — which doc 07 §7.2
## fixes as forward, and which is where every barrel here points — from
## [param from] at [param to].
static func yaw_towards(from: Vector2, to: Vector2) -> float:
	var d := (to - from).normalized()
	return atan2(-d.x, -d.y)


static func _definition(runtime: AssemblyRuntime, slot: int) -> PartDefinition:
	return runtime.definition_at(slot)


## ===== LAYOUTS =========================================================


static func _place(ctx: BuildContext, key: StringName, cell: Vector3i, orientation: int) -> void:
	var def := PartRegistry.definition_by_key(key)
	var candidate := PlacementCandidate.create(def, cell, orientation)
	var reject := PlacementValidator.validate(ctx, candidate)
	if reject != PlacementValidator.Reject.NONE:
		push_error(
			"CombatArena: '%s' at %s rejected (%d): %s"
			% [key, cell, reject, PlacementValidator.REJECT_KEYS[reject]]
		)
		return
	PlacementValidator.commit(ctx, candidate)


func _lay_out_wheeled(ctx: BuildContext, with_cell: bool) -> void:
	_place(ctx, CORE_KEY, GROUND_CORE, 0)
	_place(ctx, POWER_KEY, GROUND_POWER, 0)
	_place(ctx, GUN_KEY, GROUND_GUN, 0)
	if with_cell:
		_place(ctx, CELL_KEY, GROUND_CELL, 0)
	for cell: Vector3i in WHEEL_HUBS:
		_place(ctx, HUB_KEY, cell, 0)
	for cell: Vector3i in WHEEL_ORIGINS:
		var key := WHEEL_KEY if cell.z < FRONT_AXLE_Z else REAR_KEY
		var inboard := Vector3.RIGHT if cell.x < GROUND_CORE.x else Vector3.LEFT
		_place(ctx, key, cell, drive_face_orientation(inboard))


func _lay_out_tracked(ctx: BuildContext) -> void:
	_place(ctx, CORE_KEY, GROUND_CORE, 0)
	_place(ctx, POWER_KEY, GROUND_POWER, 0)
	_place(ctx, GUN_KEY, GROUND_GUN, 0)
	for cell: Vector3i in TRACK_HUBS:
		_place(ctx, HUB_KEY, cell, 0)
	for cell: Vector3i in TRACK_ORIGINS:
		var inboard := Vector3.RIGHT if cell.x < GROUND_CORE.x else Vector3.LEFT
		_place(ctx, TRACK_KEY, cell, drive_face_orientation(inboard))


func _lay_out_ambulatory(ctx: BuildContext) -> void:
	_place(ctx, CORE_KEY, AMBULATORY_CORE, 0)
	_place(ctx, POWER_KEY, AMBULATORY_POWER, 0)
	_place(ctx, GUN_KEY, AMBULATORY_GUN, 0)
	for i: int in AMBULATORY_LEGS.size() / 2:
		_place(ctx, HUB_KEY, AMBULATORY_LEGS[i * 2], HUB_AXLE_DOWN_ORIENTATION)
		_place(ctx, LIMB_KEY, AMBULATORY_LEGS[i * 2 + 1], 0)


func _lay_out_rotary(ctx: BuildContext) -> void:
	# Supply before draw. §7.4's power budget is checked against what the context
	# holds at the moment of the placement, so the second disc is refused if the
	# Energy Cell that covers it has not been bolted on yet — the same rule a
	# player meets in the garage, and the same order they have to build in.
	_place(ctx, CORE_KEY, ROTARY_CORE, 0)
	_place(ctx, POWER_KEY, ROTARY_POWER, 0)
	_place(ctx, CELL_KEY, ROTARY_CELL, 0)
	for cell: Vector3i in ROTARY_MAST_HUBS:
		_place(ctx, HUB_KEY, cell, HUB_AXLE_DOWN_ORIENTATION)
	for cell: Vector3i in ROTARY_DISCS:
		_place(ctx, ROTOR_KEY, cell, 0)
	_place(ctx, GUN_KEY, ROTARY_GUN, 0)


## The orientation carrying a part's own `-Z` drive face onto [param face],
## upright. Derived from the 24-orientation group rather than written down:
## which index does it is a property of [OrientationTable], and the integer does
## not survive a change to the table (handoff §9, and watch §3.39).
static func drive_face_orientation(face: Vector3) -> int:
	for i: int in SyndicateConstants.ORIENTATION_COUNT:
		var basis := OrientationTable.basis_for(i)
		if not (basis * Vector3.FORWARD).is_equal_approx(face):
			continue
		if (basis * Vector3.UP).is_equal_approx(Vector3.UP):
			return i
	return 0


## ===== COMBATANT =======================================================


## One Assembly in the arena, with the two systems that drive it and the record
## of what it did.
class Combatant:
	extends RefCounted

	var recipe: int = Recipe.WHEELED_LIGHT
	var team: int = 0
	var runtime: AssemblyRuntime = null
	var motion: MotiveSystem = null
	var guns: EffectorSystem = null
	var gun_slot: int = SyndicateConstants.INVALID_SLOT
	## Metres from its target this Assembly stops closing at.
	var stand_off_m: float = 0.0
	## Ticks this Assembly was commanded for, and how many of them its mount
	## spent converged and pinned against an elevation stop.
	##
	## The two are not exclusive, and that is the point of recording both. Doc 07
	## §4.3 tests convergence against the [i]clamped[/i] target angles, so a mount
	## asked for more depression than it has reads as on target while it sits on
	## its stop pointing over the enemy — and §7.1's gate opens on exactly that
	## flag. An Assembly can therefore hold a perfect firing solution, fire, and
	## miss by a hull height, for as long as the geometry stays outside its arc.
	var ticks_commanded: int = 0
	var ticks_on_target: int = 0
	var ticks_on_elevation_stop: int = 0
	## Steepest nose-down attitude the hull reached, in degrees.
	var worst_nose_down_deg: float = 0.0

	## One tick of gunnery telemetry. Called by [method CombatArena.command].
	func sample_gunnery() -> void:
		ticks_commanded += 1
		var hp := guns.hardpoint(gun_slot)
		if hp == null:
			return
		if hp.on_target:
			ticks_on_target += 1
		var def := runtime.definition_at(gun_slot)
		if def != null:
			var limits := def.effector_profile.pitch_limit_deg
			var pitch := rad_to_deg(hp.pitch_target_rad)
			if (
				absf(pitch - limits.x) < ELEVATION_STOP_EPSILON_DEG
				or absf(pitch - limits.y) < ELEVATION_STOP_EPSILON_DEG
			):
				ticks_on_elevation_stop += 1
		var nose := -runtime.body.global_transform.basis.z
		worst_nose_down_deg = maxf(
			worst_nose_down_deg, rad_to_deg(asin(clampf(-nose.y, -1.0, 1.0)))
		)

	## Invariant I-2: the Core Module is the root and losing it ends the
	## Assembly. Read from the part rather than from a flag the arena keeps, so
	## that nothing here can disagree with [DamageResolver].
	func is_alive() -> bool:
		var core: PartInstanceState = runtime.states[SyndicateConstants.CORE_SLOT]
		return core != null and not core.has_flag(PartFlags.FLAG_DESTROYED)

	## Drops the trigger and the controls. A wreck stops shooting; what else it
	## does is the match layer's decision and there is not one yet (§8 item 12a).
	func retire() -> void:
		guns.set_trigger(0, false)
		motion.input.throttle = 0.0
		motion.input.steer = 0.0
		motion.input.collective = 0.0
		motion.input.cyclic = Vector2.ZERO
		motion.input.yaw = 0.0

	func assembly_id() -> int:
		return runtime.assembly_id

	func core_integrity() -> float:
		return runtime.states[SyndicateConstants.CORE_SLOT].integrity

	## Live parts still on the Assembly, Core Module included.
	func parts_remaining() -> int:
		var n := 0
		for slot: int in SyndicateConstants.MAX_PARTS_PER_ASSEMBLY:
			var st: PartInstanceState = runtime.states[slot]
			if st != null and not st.has_flag(PartFlags.FLAG_DESTROYED):
				n += 1
		return n
