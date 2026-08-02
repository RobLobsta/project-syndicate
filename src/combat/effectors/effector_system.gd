class_name EffectorSystem
extends Node
## Aim and emission for one Assembly's Effector Modules, owned by
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §7.
##
## The counterpart of [MotiveSystem]: one per Assembly, holding flat per-slot
## state, reading cached band multipliers and never integrity (Invariant I-5),
## and doing all of its work in [method step] so that a unit test can drive one
## tick with a synthetic dt through the identical path the engine uses.
##
## [b]This system does not decide what it hit.[/b] It emits a projectile with an
## origin and a velocity and stops; [ProjectileSystem] sweeps it and
## [DamageResolver] resolves it. That split is Invariant I-8 — a client reports
## intent to fire and never what it struck — and it is why the fire gate here has
## no line of sight test in it.
##
## Only direct-fire emission is implemented. §5.3's arced solve, §5.4's guided
## ordnance and §10's AI target acquisition are not, and a module of a kind that
## needs one of them will aim correctly and refuse to fire rather than firing
## something wrong.

## Cone half-angle a module blooms to at most, as a multiple of its bloom step.
## §7.2: without a ceiling, a continuous-fire module's cone grows without bound
## and a held trigger eventually sprays a hemisphere.
const SPREAD_BLOOM_CEILING_STEPS: float = 12.0

## Heat at which a module stops firing until it cools, as a multiple of the
## per-shot figure. A module may fire this many rounds from cold before it has
## to stop, which is the number that decides whether a weapon is burst or
## sustained without a second authored field.
const HEAT_CEILING_SHOTS: float = 14.0

## Heat shed per second while not firing.
const HEAT_DISSIPATION_HU_S: float = 22.0

## §6's three groups: primary, secondary, tertiary. The count lives here rather
## than in [SyndicateConstants] because CLAUDE.md §1.1 makes doc 07 the owner of
## effector timing and grouping, and it is exactly one more than the number of
## `effector_fire_*` actions doc 11 §7.1 declares — which is the constraint, not
## a coincidence.
const FIRING_GROUP_COUNT: int = 3

## Assembly these modules are bolted to. Set once, before entering the tree.
var runtime: AssemblyRuntime = null
## Where emitted rounds go. Null on a client that only draws them.
var projectiles: ProjectileSystem = null
## Projectile table, for resolving an [EffectorModuleProfile]'s key to an id.
var registry: ProjectileRegistry = null
## Shared store. One ledger serves every Assembly in the match.
var ammo: AmmoLedger = null
## World-space point every hardpoint converges on. §4.2: the same point, not a
## shared direction, so two spaced modules toe in on a near target rather than
## firing parallel lines that never meet.
var aim_point_world: Vector3 = Vector3.ZERO
## Per firing group, whether the trigger is held. §6.
var triggers: PackedByteArray = PackedByteArray()

## Slot -> hardpoint state, for registered Effector Modules only.
var _hardpoints: Dictionary = {}
## Registered slots, ascending. Invariant I-9: emission order is replicated.
var _slots: PackedInt32Array = PackedInt32Array()
## Slot -> firing group. Every module starts in group 0.
var _group: PackedByteArray = PackedByteArray()
## Slot -> resolved projectile id, cached at registration so the tick loop never
## resolves a [StringName].
var _projectile_id: PackedInt32Array = PackedInt32Array()
## Slot -> cached band multipliers, written only by [method on_band_changed].
var _slew_mult: PackedFloat32Array = PackedFloat32Array()
var _cycle_mult: PackedFloat32Array = PackedFloat32Array()
var _spread_mult: PackedFloat32Array = PackedFloat32Array()
var _jam_chance: PackedFloat32Array = PackedFloat32Array()

## Seeded per Assembly. Invariant I-9 and doc 07 §11.2: spread and jam rolls are
## replayed by the network layer and must not come from the global generator.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	var count := SyndicateConstants.MAX_PARTS_PER_ASSEMBLY
	_group.resize(count)
	_projectile_id.resize(count)
	_slew_mult.resize(count)
	_cycle_mult.resize(count)
	_spread_mult.resize(count)
	_jam_chance.resize(count)
	_slew_mult.fill(1.0)
	_cycle_mult.fill(1.0)
	_spread_mult.fill(1.0)
	triggers.resize(FIRING_GROUP_COUNT)


func _physics_process(dt: float) -> void:
	step(dt)


func _enter_tree() -> void:
	EventBus.part_band_changed.connect(_on_part_band_changed)


func _exit_tree() -> void:
	EventBus.part_band_changed.disconnect(_on_part_band_changed)


## Doc 08 §8.4's dispatch. See [method MotiveSystem._on_part_band_changed] for
## why it arrives as a signal rather than as the direct call the document writes.
##
## This is the path that gives §8.2's jam chance a producer: a module below 30%
## integrity gets [constant DegradationTable.EFF_JAM]'s 0.18 written into its
## slot here, and §7.2's roll reads it there. Without the subscription the
## multipliers are written once at registration and never again, so a module
## could be shot to pieces and still fire like new.
func _on_part_band_changed(assembly_id: int, slot: int, _before: int, after: int) -> void:
	if runtime == null or assembly_id != runtime.assembly_id:
		return
	if _hardpoints.has(slot):
		on_band_changed(slot, after)


## Seeds this Assembly's combat generator.
##
## Called by the match scene from the match seed and the Assembly id, so two
## Assemblies in one match roll differently and the same match replays
## identically.
func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value


## Registers an Effector Module.
##
## Melee modules are accepted and tracked but never emit: §15 resolves them by
## swept volume through [MeleeSolver], and a module that tried both would strike
## twice for one swing.
func register(slot: int, def: PartDefinition) -> void:
	if def == null or def.part_class != PartEnums.PartClass.EFFECTOR_MODULE:
		return
	var profile := def.effector_profile
	var hp: HardpointState = _hardpoints.get(slot)
	if hp == null:
		hp = HardpointState.new()
		hp.slot = slot
		_hardpoints[slot] = hp
		_slots.push_back(slot)
		_slots.sort()
	hp.reset(profile)
	_projectile_id[slot] = -1
	if registry != null and not profile.is_melee():
		_projectile_id[slot] = registry.id_of(profile.projectile_key)
		if _projectile_id[slot] < 0:
			push_error(
				"EffectorSystem: '%s' names projectile '%s', which is not registered"
				% [def.part_key, profile.projectile_key]
			)
	on_band_changed(slot, PartEnums.IntegrityBand.NOMINAL)


## Drops a module that has been destroyed or detached.
func unregister(slot: int) -> void:
	var index := _slots.find(slot)
	if index >= 0:
		_slots.remove_at(index)
	_hardpoints.erase(slot)
	_projectile_id[slot] = -1


## §8.4's handler. Writes this band's multipliers into the flat arrays the tick
## loop reads, and reads integrity nowhere.
func on_band_changed(slot: int, band: int) -> void:
	_slew_mult[slot] = DegradationTable.EFF_SLEW[band]
	_cycle_mult[slot] = DegradationTable.EFF_CYCLE[band]
	_spread_mult[slot] = DegradationTable.EFF_SPREAD[band]
	_jam_chance[slot] = DegradationTable.EFF_JAM[band]


## Assigns [param slot] to a firing group. §6.
func set_group(slot: int, group_index: int) -> void:
	_group[slot] = clampi(group_index, 0, FIRING_GROUP_COUNT - 1)


## Holds or releases a group's trigger.
func set_trigger(group_index: int, held: bool) -> void:
	if group_index < 0 or group_index >= triggers.size():
		return
	triggers[group_index] = 1 if held else 0


## One tick: slew every mount, run its timers, and emit for any module whose
## trigger is held and whose gate is open. §7.
func step(dt: float) -> void:
	if runtime == null:
		return
	for slot: int in _slots:
		var st: PartInstanceState = runtime.states[slot]
		if st == null or st.has_flag(
			PartFlags.FLAG_DESTROYED | PartFlags.FLAG_DETACHED | PartFlags.FLAG_POWER_STARVED
		):
			continue
		var def := PartRegistry.definition(st.part_def_id)
		if def == null or def.effector_profile == null:
			continue
		var hp: HardpointState = _hardpoints[slot]
		var profile := def.effector_profile

		_solve_aim(hp, st, def)
		_slew(hp, profile, slot, dt)
		hp.tick_timers(dt)
		if hp.jam_timer_s <= 0.0:
			st.flags &= ~PartFlags.FLAG_JAMMED
		_decay_spread(hp, profile, dt)
		_dissipate_heat(hp, dt)
		hp.on_target = hp.solution_in_arc and AimSolver.is_converged(
			hp.yaw_rad, hp.yaw_target_rad, hp.pitch_rad, hp.pitch_target_rad
		)

		if triggers[_group[slot]] == 0:
			continue
		if not can_fire(slot, def):
			continue
		_emit(hp, st, def, slot)


## §7.1's fire gate, cheapest test first and short-circuiting, so the common
## "trigger held, module still cycling" case exits after two comparisons.
func can_fire(slot: int, def: PartDefinition) -> bool:
	var hp: HardpointState = _hardpoints.get(slot)
	if hp == null:
		return false
	if not hp.on_target:
		return false
	if not hp.timers_clear():
		return false
	var profile := def.effector_profile
	if profile.is_melee():
		return false
	if profile.magazine_rounds > 0 and hp.rounds_in_magazine <= 0:
		return false
	if hp.heat_hu >= heat_ceiling(profile):
		return false
	if ammo != null and not ammo.has_rounds(runtime.assembly_id, _projectile_id[slot]):
		return false
	return _projectile_id[slot] >= 0


## Heat at which [param profile] stops firing.
static func heat_ceiling(profile: EffectorModuleProfile) -> float:
	return maxf(profile.heat_per_shot_hu, 1.0) * HEAT_CEILING_SHOTS


## The hardpoint at [param slot], or null. Diagnostics and tests.
func hardpoint(slot: int) -> HardpointState:
	return _hardpoints.get(slot)


## Registered Effector Module slots, ascending.
func slots() -> PackedInt32Array:
	return _slots.duplicate()


## ===== INSPECTION ======================================================
## Read-only views of the cached band multipliers. They exist so that a test, the
## garage's stat panel, and the diagnostics overlay can read this system without
## any of them reaching into its arrays — which would break all three the next
## time the layout changes.


func slew_multiplier(slot: int) -> float:
	return _slew_mult[slot]


func cycle_multiplier(slot: int) -> float:
	return _cycle_mult[slot]


func spread_multiplier(slot: int) -> float:
	return _spread_mult[slot]


## §7.2's per-shot jam probability at this module's cached band. Zero above
## CRITICAL, by §8.2.
func jam_chance(slot: int) -> float:
	return _jam_chance[slot]


## ===== PRIVATE =========================================================


## §4.2. Every mount converges on [member aim_point_world].
func _solve_aim(hp: HardpointState, st: PartInstanceState, def: PartDefinition) -> void:
	var muzzle := muzzle_world_transform(runtime, st, def, 0, hp.yaw_rad, hp.pitch_rad)
	var to_target := aim_point_world - muzzle.origin
	if to_target.length_squared() < 0.01:
		return
	# Into the module's own rest frame: out of the world, out of the chassis, and
	# out of the lattice orientation the builder placed it at. A module mounted
	# facing backwards has to arrive at the same answer as one facing forwards.
	var dir_chassis := runtime.body.global_transform.basis.inverse() * to_target.normalized()
	var dir_rest := OrientationTable.basis_for(st.orientation_index).inverse() * dir_chassis
	var angles := AimSolver.angles_for(dir_rest)
	var profile := def.effector_profile
	hp.yaw_target_rad = AimSolver.clamp_yaw(angles.x, profile.yaw_limit_deg)
	hp.pitch_target_rad = AimSolver.clamp_pitch(angles.y, profile.pitch_limit_deg)
	# §4.3.1. The targets above are clamped, so convergence against them says only
	# that the mount arrived where it was told — not that where it was told is
	# where the enemy is. This is the difference, and the fire gate needs it.
	hp.solution_in_arc = (
		is_equal_approx(hp.yaw_target_rad, angles.x)
		and is_equal_approx(hp.pitch_target_rad, angles.y)
	)


func _slew(hp: HardpointState, profile: EffectorModuleProfile, slot: int, dt: float) -> void:
	hp.yaw_rad = AimSolver.slew(
		hp.yaw_rad, hp.yaw_target_rad, profile.yaw_rate_deg_s, _slew_mult[slot], dt
	)
	hp.pitch_rad = AimSolver.slew(
		hp.pitch_rad, hp.pitch_target_rad, profile.pitch_rate_deg_s, _slew_mult[slot], dt
	)


func _decay_spread(hp: HardpointState, profile: EffectorModuleProfile, dt: float) -> void:
	hp.spread_current_deg = maxf(
		profile.spread_base_deg, hp.spread_current_deg - profile.spread_decay_deg_s * dt
	)


func _dissipate_heat(hp: HardpointState, dt: float) -> void:
	hp.heat_hu = maxf(0.0, hp.heat_hu - HEAT_DISSIPATION_HU_S * dt)


## §7.2.
func _emit(hp: HardpointState, st: PartInstanceState, def: PartDefinition, slot: int) -> void:
	var profile := def.effector_profile

	# The jam roll comes first, before a round is spent or a muzzle advanced. A
	# jam is a shot that did not happen, and Invariant I-8 forbids a client
	# predicting one at all.
	if _jam_chance[slot] > 0.0 and _rng.randf() < _jam_chance[slot]:
		hp.jam_timer_s = profile.jam_clear_time_s
		st.flags |= PartFlags.FLAG_JAMMED
		EventBus.effector_jammed.emit(runtime.assembly_id, slot)
		return

	var muzzle_index := hp.next_muzzle_index
	hp.next_muzzle_index = (hp.next_muzzle_index + 1) % maxi(profile.muzzle_offsets_m.size(), 1)
	var muzzle := muzzle_world_transform(
		runtime, st, def, muzzle_index, hp.yaw_rad, hp.pitch_rad
	)
	var spread_rad := deg_to_rad(hp.spread_current_deg * _spread_mult[slot])
	var direction := AimSolver.cone_sample(-muzzle.basis.z, spread_rad, _rng)

	if projectiles != null:
		# §7.3. A round fired from a vehicle moving at 20 m/s inherits that
		# velocity. Without inheritance, shooting sideways while driving produces
		# a systematic aim bias that players learn to compensate for — an
		# artefact of the code, not a skill.
		projectiles.spawn(
			muzzle.origin,
			direction * profile.muzzle_velocity_mps + runtime.body.linear_velocity,
			_projectile_id[slot],
			runtime.assembly_id,
			slot,
			runtime.body.get_rid()
		)

	_apply_recoil(profile, muzzle, direction)
	hp.shots_fired += 1
	hp.heat_hu += profile.heat_per_shot_hu
	hp.spread_current_deg = minf(
		hp.spread_current_deg + profile.spread_bloom_deg,
		profile.spread_base_deg + profile.spread_bloom_deg * SPREAD_BLOOM_CEILING_STEPS
	)
	hp.cycle_timer_s = profile.cycle_time_s * _cycle_mult[slot]
	if profile.magazine_rounds > 0:
		hp.rounds_in_magazine -= 1
		if hp.rounds_in_magazine <= 0:
			hp.rounds_in_magazine = profile.magazine_rounds
			hp.reload_timer_s = profile.reload_time_s
	if profile.burst_count > 0:
		hp.burst_remaining -= 1
		if hp.burst_remaining <= 0:
			hp.burst_remaining = profile.burst_count
			hp.burst_recovery_s = profile.burst_recovery_s
	if ammo != null:
		ammo.consume(runtime.assembly_id, _projectile_id[slot], 1)
	EventBus.effector_fired.emit(runtime.assembly_id, slot, MatchClock.tick)


## §8. Recoil is an impulse at the muzzle, not at the centre of mass, which is
## what makes a heavy weapon mounted high and forward pitch the nose on firing.
func _apply_recoil(profile: EffectorModuleProfile, muzzle: Transform3D, direction: Vector3) -> void:
	if is_zero_approx(profile.recoil_impulse_ns):
		return
	runtime.body.apply_impulse(
		-direction * profile.recoil_impulse_ns,
		muzzle.origin - runtime.body.global_transform.origin
	)


## World transform of muzzle [param muzzle_index] with the mount pointed at
## [param yaw_rad] / [param pitch_rad].
##
## The composition is chassis, then the part's lattice orientation, then the
## hardpoint rotation, then the authored muzzle offset — in that order, and the
## order is the whole function. A muzzle offset applied before the mount rotation
## puts the barrel tip where the barrel would be if it had never traversed, which
## is a round leaving from inside the turret and a self-hit on the first tick.
##
## Its [code]-Z[/code] is the direction a round leaves along, which is why the
## emission path takes the direction from this basis rather than recomputing it
## from the angles.
static func muzzle_world_transform(
	assembly: AssemblyRuntime,
	st: PartInstanceState,
	def: PartDefinition,
	muzzle_index: int,
	yaw_rad: float,
	pitch_rad: float
) -> Transform3D:
	var offsets := def.effector_profile.muzzle_offsets_m
	var offset := Vector3.ZERO
	if not offsets.is_empty():
		offset = offsets[clampi(muzzle_index, 0, offsets.size() - 1)]
	var part := Transform3D(
		OrientationTable.basis_for(st.orientation_index),
		LatticeMath.cell_to_local(st.origin_cell)
	)
	var mount := Transform3D(Basis.from_euler(Vector3(pitch_rad, yaw_rad, 0.0)), Vector3.ZERO)
	return assembly.body.global_transform * part * mount * Transform3D(Basis(), offset)
