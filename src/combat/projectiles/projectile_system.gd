class_name ProjectileSystem
extends Node
## Pooled, node-free projectile simulation, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §12.
##
## Projectiles are not scene-tree nodes. Sixty [RigidBody3D] spawns a second
## across sixteen players would dominate the frame on their own, so a projectile
## is an index into flat arrays and the whole population is integrated by one
## loop.
##
## Hit detection is a [b]swept ray[/b] from the previous position to the current
## one, never a point test. At 940 m/s a round covers 15.7 m in a tick; a point
## test would tunnel through every Assembly in the match and land in the terrain
## behind it.
##
## This node declares [code]_physics_process[/code] and is on the
## [code]test_no_polling[/code] allowlist for the same reason [MotiveSystem] is:
## it integrates state that changes every tick by definition, and it reads no
## structural state at all.

## Architectural Invariant I-12. Exhaustion recycles the [b]oldest[/b] round
## rather than dropping the newest: a dropped shot is one a player fired that
## silently never existed, where a recycled one is at worst a distant tracer
## vanishing early.
const POOL_SIZE: int = 2048

## Seconds a round cannot hit the Assembly that fired it. A mortar landing on
## your own roof is legitimate; a muzzle inside your own collider is not.
const SELF_IMMUNITY_S: float = 0.06

## Nudge past a penetrated surface, in metres, so a round that continues does not
## immediately re-hit the shape it just left.
const PENETRATION_STEP_M: float = 0.02

const FLAG_ACTIVE: int = 1 << 0

## Where damage goes. Without one the system still flies and expires rounds,
## which is what a client-side visual-only instance does.
var resolver: DamageResolver = null
## Projectile table. Required; a round with no definition cannot be integrated.
var registry: ProjectileRegistry = null
## Space the sweep queries run in. Set by the match scene from the world the
## Assemblies are in.
var space: PhysicsDirectSpaceState3D = null

var _position: PackedVector3Array = PackedVector3Array()
var _prev_position: PackedVector3Array = PackedVector3Array()
var _velocity: PackedVector3Array = PackedVector3Array()
var _def_id: PackedInt32Array = PackedInt32Array()
var _owner_assembly: PackedInt32Array = PackedInt32Array()
var _owner_slot: PackedByteArray = PackedByteArray()
var _spawn_tick: PackedInt32Array = PackedInt32Array()
var _life_s: PackedFloat32Array = PackedFloat32Array()
var _flags: PackedByteArray = PackedByteArray()
## Free indices, highest last so allocation is a pop rather than a scan.
var _free_list: PackedInt32Array = PackedInt32Array()
var _active_count: int = 0
## Ring cursor for §12.4's oldest-first recycling.
var _recycle_cursor: int = 0
## Owner body RIDs, for §12.3's self-exclusion.
var _owner_rid: Array[RID] = []


func _init() -> void:
	_position.resize(POOL_SIZE)
	_prev_position.resize(POOL_SIZE)
	_velocity.resize(POOL_SIZE)
	_def_id.resize(POOL_SIZE)
	_owner_assembly.resize(POOL_SIZE)
	_owner_slot.resize(POOL_SIZE)
	_spawn_tick.resize(POOL_SIZE)
	_life_s.resize(POOL_SIZE)
	_flags.resize(POOL_SIZE)
	_owner_rid.resize(POOL_SIZE)
	_free_list.resize(POOL_SIZE)
	for i: int in POOL_SIZE:
		# Descending, so the first allocation takes index 0 and a test reading
		# the pool in order sees the shots in the order they were fired.
		_free_list[i] = POOL_SIZE - 1 - i


func _physics_process(dt: float) -> void:
	step(dt)


## One tick of flight for every live round.
##
## Separate from [method _physics_process] for the reason [method
## MotiveSystem.step] is: a unit test drives this directly with a synthetic dt
## and asserts exactly where a round ended up, through the identical path the
## engine uses.
func step(dt: float) -> void:
	if _active_count == 0:
		return
	for i: int in POOL_SIZE:
		if (_flags[i] & FLAG_ACTIVE) == 0:
			continue
		var def := registry.definition(_def_id[i]) if registry != null else null
		if def == null:
			_release(i)
			continue
		_prev_position[i] = _position[i]

		var v := _velocity[i]
		var speed := v.length()
		var drag := def.drag_delta_mps(speed, dt)
		if drag > 0.0:
			v -= v / speed * drag
		v.y -= SyndicateConstants.GRAVITY_MPS2 * def.gravity_scale * dt
		_velocity[i] = v
		_position[i] += v * dt

		_life_s[i] -= dt
		if _life_s[i] <= 0.0:
			_release(i)
			continue
		_sweep_and_resolve(i, def)


## Launches a round and returns its pool index, or -1 when it could not be
## created at all.
func spawn(
	origin: Vector3,
	velocity: Vector3,
	projectile_id: int,
	owner_assembly_id: int,
	owner_slot: int,
	owner_body: RID
) -> int:
	var def := registry.definition(projectile_id) if registry != null else null
	if def == null:
		push_error("ProjectileSystem: no definition for projectile id %d" % projectile_id)
		return -1
	var index := _allocate()
	_position[index] = origin
	_prev_position[index] = origin
	_velocity[index] = velocity
	_def_id[index] = projectile_id
	_owner_assembly[index] = owner_assembly_id
	_owner_slot[index] = owner_slot
	_owner_rid[index] = owner_body
	_spawn_tick[index] = MatchClock.tick
	_life_s[index] = def.life_s
	_flags[index] = FLAG_ACTIVE
	_active_count += 1
	return index


## Rounds currently in flight.
func active_count() -> int:
	return _active_count


func position_of(index: int) -> Vector3:
	return _position[index]


func velocity_of(index: int) -> Vector3:
	return _velocity[index]


func is_active(index: int) -> bool:
	return index >= 0 and index < POOL_SIZE and (_flags[index] & FLAG_ACTIVE) != 0


## Retires every live round. The match scene calls this between rounds; a shot
## fired before a reset must not land after one.
func clear() -> void:
	for i: int in POOL_SIZE:
		if (_flags[i] & FLAG_ACTIVE) != 0:
			_release(i)


## ===== PRIVATE =========================================================


func _allocate() -> int:
	if not _free_list.is_empty():
		var index := _free_list[_free_list.size() - 1]
		_free_list.remove_at(_free_list.size() - 1)
		return index
	# §12.4. The pool is full: take a live round rather than refusing the new
	# one. An empty free list means every index is active, so the cursor always
	# lands on something to recycle. It makes the victim O(1) and deterministic,
	# which Invariant I-9 needs — a server and a predicting client must recycle
	# the same slot or their pools diverge for the rest of the match.
	var victim := _recycle_cursor
	_recycle_cursor = (_recycle_cursor + 1) % POOL_SIZE
	_flags[victim] = 0
	_active_count -= 1
	return victim


func _release(index: int) -> void:
	if (_flags[index] & FLAG_ACTIVE) == 0:
		return
	_flags[index] = 0
	_active_count -= 1
	_free_list.append(index)


## §12.2 and §12.3.
func _sweep_and_resolve(index: int, def: ProjectileDefinition) -> void:
	if space == null:
		return
	var params := PhysicsRayQueryParameters3D.create(_prev_position[index], _position[index])
	params.collision_mask = CollisionLayers.MASK_PROJECTILE_TARGET
	params.hit_from_inside = false
	var excluded := _self_exclusion(index)
	if not excluded.is_empty():
		params.exclude = excluded
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return

	var continued := _report_hit(index, def, hit)
	if continued:
		_position[index] = (
			Vector3(hit["position"])
			+ _velocity[index].normalized() * PENETRATION_STEP_M
		)
		return
	_release(index)


## Turns a raycast hit into damage. Returns true when the round carries on.
func _report_hit(index: int, def: ProjectileDefinition, hit: Dictionary) -> bool:
	if resolver == null:
		return false
	var point := Vector3(hit["position"])
	if def.blast_radius_m > 0.0:
		resolver.resolve_blast(
			point, def.blast_radius_m, def.damage,
			_owner_assembly[index], _owner_slot[index], 0
		)
		return false

	var body: Object = hit.get("collider")
	if not (body is ChassisBodyRef):
		# Ground, a Static Volume, or anything else that is not an Assembly. The
		# round is spent; what it did to the world is doc 09's and doc 10's, and
		# neither exists yet.
		return false
	var chassis := body as ChassisBodyRef
	var slot := chassis.slot_for_shape_index(int(hit.get("shape", -1)))
	if slot == SyndicateConstants.INVALID_SLOT:
		return false

	var packet := DamagePacket.new()
	packet.target_assembly_id = chassis.assembly_id
	packet.target_slot = slot
	packet.channel = def.channel
	packet.raw_amount = def.damage
	packet.penetration = def.penetration
	packet.impact_point_world = point
	packet.impact_normal_world = Vector3(hit["normal"])
	packet.incoming_direction = _velocity[index].normalized()
	packet.source_assembly_id = _owner_assembly[index]
	packet.source_slot = _owner_slot[index]
	packet.source_tick = _spawn_tick[index]
	var outcome := resolver.apply(packet)
	if not def.penetrates_after_hit:
		return false
	# A round only carries on through something it actually defeated. One that
	# was stopped by the armour is stopped by the armour.
	return outcome.was_applied()


func _self_exclusion(index: int) -> Array[RID]:
	var age := float(MatchClock.tick - _spawn_tick[index]) * SyndicateConstants.PHYSICS_DT
	if age >= SELF_IMMUNITY_S or not _owner_rid[index].is_valid():
		return []
	return [_owner_rid[index]] as Array[RID]
