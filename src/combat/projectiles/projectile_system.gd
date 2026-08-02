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

## Architectural Invariant I-12, and doc 07 §12.2.2. Parts one round may resolve
## damage against before it is spent, and queries one round may spend in a tick.
##
## They bound different things. The first bounds how much [i]damage[/i] a round
## may do; the second bounds how much [i]work[/i] it may cost, including the
## segments spent skipping a part it has already struck. A round that exhausts
## its segments while still inside geometry is expired, because a projectile that
## has queried eight times in one tick without leaving is in a state no
## legitimate trajectory produces.
const MAX_PENETRATIONS: int = 4
const MAX_SWEEP_SEGMENTS: int = 8

## Sentinel in the strike record for a slot no round has struck.
const NO_STRIKE: int = -1
## Slots per Assembly, for packing `(assembly_id, slot)` into one int32. Assembly
## ids are allocated upward from 1 and slots are `[0, 255)`, so the pair fits.
const STRIKE_SLOT_STRIDE: int = 256

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
## §12.2.1's strike record: [constant MAX_PENETRATIONS] packed `(assembly, slot)`
## keys per round, flat and indexed by `index * MAX_PENETRATIONS + n`. A round
## never resolves twice against the same part, and this is what remembers.
var _struck: PackedInt32Array = PackedInt32Array()
## How many parts each round has resolved against [b]since it was fired[/b], not
## since the tick began. §12.2.2 spends a round's budget over its life, and both
## the budget test and the strike record above index off this; a counter that
## restarted every tick would let a round crossing two hulls on two consecutive
## ticks resolve eight packets against a bound of four, and would let the record
## forget the first hull entirely.
var _strikes: PackedInt32Array = PackedInt32Array()


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
	_struck.resize(POOL_SIZE * MAX_PENETRATIONS)
	_struck.fill(NO_STRIKE)
	_strikes.resize(POOL_SIZE)
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
	_clear_strikes(index)
	_active_count += 1
	return index


## Rounds currently in flight.
func active_count() -> int:
	return _active_count


func position_of(index: int) -> Vector3:
	return _position[index]


func velocity_of(index: int) -> Vector3:
	return _velocity[index]


## Parts [param index] has resolved a packet against since it was fired, against
## a ceiling of [constant MAX_PENETRATIONS].
##
## Survives release, so the final count of a spent round can still be read on the
## tick after it went inactive; [method spawn] is what resets it. Diagnostics
## only — nothing in the simulation reads it, and the sweep keeps its own copy in
## a local.
func strikes_of(index: int) -> int:
	return _strikes[index]


## §12.2.1's strike record for [param index]: the packed `(assembly, slot)` keys
## it has resolved against, in the order it struck them, [constant NO_STRIKE]
## trimmed. Diagnostics only, on the same terms as [method strikes_of].
func struck_keys_of(index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var base := index * MAX_PENETRATIONS
	for n: int in MAX_PENETRATIONS:
		if _struck[base + n] != NO_STRIKE:
			out.append(_struck[base + n])
	return out


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


## §12.2 and §12.3. Sweeps [b]the whole tick's travel[/b], not the first hit in
## it, and resolves every distinct part along the way up to the budget.
##
## The within-tick continuation is the whole shape of this function and it is
## worth stating why. A 940 m/s round covers 15.7 m in a tick and a hull is three
## metres thick, so a round that penetrates has to carry on inside the same tick
## or it does not travel: repositioning to the impact point and returning
## advances it two centimetres and throws the remaining 15.7 m away. Doing that
## once per tick is a round grinding through an Assembly at a metre a second,
## resolving its full damage against the same part sixty times a second.
##
## Two bounds, both Invariant I-12 and both doing different jobs — see
## [constant MAX_PENETRATIONS] — and one rule, §12.2.1: never twice on one part.
func _sweep_and_resolve(index: int, def: ProjectileDefinition) -> void:
	if space == null:
		return
	var from := _prev_position[index]
	var to := _position[index]
	var direction := _velocity[index].normalized()
	var excluded := _self_exclusion(index)
	var budget := _penetration_budget(def)
	var resolved := _strikes[index]

	for segment: int in MAX_SWEEP_SEGMENTS:
		var params := PhysicsRayQueryParameters3D.create(from, to)
		params.collision_mask = CollisionLayers.MASK_PROJECTILE_TARGET
		params.hit_from_inside = false
		if not excluded.is_empty():
			params.exclude = excluded
		var hit := space.intersect_ray(params)
		if hit.is_empty():
			# Out the far side, or it never reached anything. Either way the round
			# is where its velocity put it and it is still flying — and whatever it
			# got through on the way carries into the next tick.
			return

		# Advanced before the strike test, so a part already struck costs one
		# segment and then the sweep moves on rather than querying it forever.
		from = Vector3(hit["position"]) + direction * PENETRATION_STEP_M
		if _already_struck(index, hit):
			continue

		if not _report_hit(index, def, hit):
			_release(index)
			return
		_record_strike(index, hit, resolved)
		resolved += 1
		# Written through on every strike rather than on the way out, because
		# three of this loop's four exits are a release and the count has to
		# survive all of them — the next tick reads it, and so does
		# [method strikes_of] once the round is spent.
		_strikes[index] = resolved
		if resolved >= budget:
			_release(index)
			return
	_release(index)


## §12.2.2. Parts this round may damage before it is spent.
static func _penetration_budget(def: ProjectileDefinition) -> int:
	return MAX_PENETRATIONS if def.penetrates_after_hit else 1


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


## §12.2.1. The `(assembly_id, slot)` this hit names, or [constant NO_STRIKE] for
## anything that is not a part of an Assembly.
##
## Ground and Static Volumes are deliberately not recorded: neither can be struck
## twice, because [method _report_hit] refuses to continue through either.
static func _strike_key(hit: Dictionary) -> int:
	var body: Object = hit.get("collider")
	if not (body is ChassisBodyRef):
		return NO_STRIKE
	var chassis := body as ChassisBodyRef
	var slot := chassis.slot_for_shape_index(int(hit.get("shape", -1)))
	if slot == SyndicateConstants.INVALID_SLOT:
		return NO_STRIKE
	return chassis.assembly_id * STRIKE_SLOT_STRIDE + slot


## True when this round has already resolved a packet against what [param hit]
## names. §12.2.1: every multiplier in doc 08 §4 is written for a single impact.
func _already_struck(index: int, hit: Dictionary) -> bool:
	var key := _strike_key(hit)
	if key == NO_STRIKE:
		return false
	var base := index * MAX_PENETRATIONS
	for n: int in MAX_PENETRATIONS:
		if _struck[base + n] == key:
			return true
	return false


func _record_strike(index: int, hit: Dictionary, slot_in_record: int) -> void:
	if slot_in_record < 0 or slot_in_record >= MAX_PENETRATIONS:
		return
	_struck[index * MAX_PENETRATIONS + slot_in_record] = _strike_key(hit)


func _clear_strikes(index: int) -> void:
	var base := index * MAX_PENETRATIONS
	for n: int in MAX_PENETRATIONS:
		_struck[base + n] = NO_STRIKE
	_strikes[index] = 0


func _self_exclusion(index: int) -> Array[RID]:
	var age := float(MatchClock.tick - _spawn_tick[index]) * SyndicateConstants.PHYSICS_DT
	if age >= SELF_IMMUNITY_S or not _owner_rid[index].is_valid():
		return []
	return [_owner_rid[index]] as Array[RID]
