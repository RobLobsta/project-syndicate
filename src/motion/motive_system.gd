class_name MotiveSystem
extends Node
## Locomotion dispatch for one Assembly, owned by
## [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §6.0.
##
## The single place in the project that branches on locomotion family, and it
## does so by array index rather than by [enum PartEnums.MotiveKind] — one
## [constant PartEnums.LOCOMOTION_OF_MOTIVE_KIND] lookup per part, cached at
## registration. Adding a fifth family is an append to that array plus one
## solver, not a new branch in every consumer.
##
## This node declares [code]_physics_process[/code], which Architectural
## Invariant I-4 permits: it is a force integrator, not a reactor to structural
## events, and §9's dynamic amplification factor is explicitly per-tick work.
## What it must never do is recompute structural state — mass, connectivity, and
## bands all arrive as cached values written by their owners on their own events.
##
## [method step] is the whole tick and [method _physics_process] does nothing but
## call it. That split is not decoration: it lets a unit test drive one tick with
## contacts it constructed itself, through the identical path the engine uses,
## and it lets a [code]tests/physics/[/code] test let the engine drive it instead
## and assert what the body did.

## Rate at which the strain model's dynamic amplification factor is refreshed.
## §9: 10 Hz, not per tick, because the graph re-evaluates strain against it and
## a per-tick update would cost more than the factor is worth.
const KAPPA_INTERVAL_S: float = 0.1

## Weight on the angular term of the dynamic factor. Captures the centripetal
## load on a part at the end of a long boom, which pure linear acceleration
## misses.
const KAPPA_ANGULAR_WEIGHT: float = 0.35

## Ceiling on the §3.4 coupling torque, in N·m. §11 invariant 10: the correction
## omits the `(I_diag − I_full) ω̇` term, and this clamp is what guarantees the
## omission can never inject energy faster than the solver removes it.
const COUPLING_TORQUE_LIMIT_NM: float = 24000.0

## Assembly this system moves. Set once, before the node enters the tree.
var runtime: AssemblyRuntime = null
## Aggregated Prime Mover and Energy Cell totals. Recomputed on structural and
## band events by the owner, never here.
var power: PowerSystem = null
## This tick's intent. Written by the control system, the AI driver, or the
## network input channel; read by every family.
var input: ControlInput = null

## The terrain contacts are resolved against, for doc 09 §7.3's surface lookup.
## Null on a fixture with no Ground Array, which reads the reference surface —
## see [method _surface_multiplier].
var ground: GroundArray = null
## Where doc 09 §6's rut deposits go. Null disables rut accumulation entirely,
## which is correct for the garage and for every solver test.
var ground_deform: GroundDeformSystem = null

## Slot -> locomotion family, cached at registration. The dispatch table.
var _family: PackedByteArray = PackedByteArray()
## Slot -> traction/thrust multiplier from the part's band. Written only by
## [method on_band_changed]; read every tick by every family.
var _traction_mult: PackedFloat32Array = PackedFloat32Array()
var _rolling_mult: PackedFloat32Array = PackedFloat32Array()
var _steer_mult: PackedFloat32Array = PackedFloat32Array()
var _damp_mult: PackedFloat32Array = PackedFloat32Array()

## Slots registered with this system, ascending. Iterated instead of the full
## 255-slot array so that an Assembly with four Motive Assemblies costs four
## iterations, not two hundred and fifty-five.
var _motive_slots: PackedInt32Array = PackedInt32Array()

## Per-family state, keyed by slot. Only the family that owns a slot ever reads
## its entry.
var _contacts: Dictionary = {}  # slot -> Array[MotiveContact]
var _discs: Dictionary = {}  # slot -> RotorDiscState
var _limbs: Dictionary = {}  # slot -> LimbState

## Shared gait clock. One per Assembly, not one per limb: the limbs' phases are
## offsets into this, which is what keeps them in a fixed relationship no matter
## how the cadence changes.
var _gait_clock: float = 0.0

## Contacts forming an axle pair, left at even indices and right at odd (§6.5).
## Rebuilt on every registration change, never per tick: pairing is a function of
## where the builder put the Motive Assemblies, and they do not move.
var _axle_pairs: Array[MotiveContact] = []

## Slot -> current steer angle in degrees, positive to the right (§7.1). Carried
## between ticks because a wheel takes time to turn: the authored
## `steer_rate_deg_s` is what stops an Assembly changing direction instantly, and
## it is what a damaged Motive Assembly loses through
## [constant DegradationTable.MOTIVE_STEER].
var _steer_deg: PackedFloat32Array = PackedFloat32Array()

## Longitudinal spread of the ground contacts, in metres. §7.6's yaw target is a
## bicycle model and needs a wheelbase; it is where the builder put the Motive
## Assemblies, so it is derived on registration and never per tick.
var _wheelbase_m: float = 0.0

var _kappa_accum: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	_family.resize(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY)
	_traction_mult.resize(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY)
	_rolling_mult.resize(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY)
	_steer_mult.resize(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY)
	_damp_mult.resize(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY)
	_steer_deg.resize(SyndicateConstants.MAX_PARTS_PER_ASSEMBLY)
	_traction_mult.fill(1.0)
	_rolling_mult.fill(1.0)
	_steer_mult.fill(1.0)
	_damp_mult.fill(1.0)


func _physics_process(dt: float) -> void:
	step(dt)


func _enter_tree() -> void:
	EventBus.part_band_changed.connect(_on_part_band_changed)
	EventBus.part_destroyed.connect(_on_part_destroyed)


func _exit_tree() -> void:
	EventBus.part_band_changed.disconnect(_on_part_band_changed)
	EventBus.part_destroyed.disconnect(_on_part_destroyed)


## A destroyed part changes what this Assembly can supply and what it draws, so
## the power budget is re-solved — once, on the event, never per tick.
##
## This is [PowerSystem]'s only production caller. Doc 05 §7.5 makes the supply a
## property of the surviving Prime Movers and Energy Cells and the draw a
## property of the surviving consumers, and until something recomputed it on a
## structural event an Assembly kept the budget it spawned with: shoot the Prime
## Mover off a rotorcraft and its discs went on turning at full rate, indefinitely,
## on power that no longer existed.
##
## Band changes deliberately do [i]not[/i] trigger it. A degraded Prime Mover
## still supplies its rated figure — doc 08's tables scale traction, slew, cycle
## and spread, and none of them scales supply — so recomputing on every band
## transition would be work with no result.
func _on_part_destroyed(assembly_id: int, _slot: int, _cause: int) -> void:
	if runtime == null or power == null or assembly_id != runtime.assembly_id:
		return
	power.recompute(runtime.states, runtime.graph.alive)


## Doc 08 §8.4's dispatch, arriving as a signal rather than as a direct call.
##
## The document writes `assembly.motive_system.on_band_changed(slot, after)`,
## which would need [DamageResolver] to hold a reference to every per-Assembly
## system in the match. It already declined that shape once — §3.1's amendment
## is why the registry is an object rather than an autoload — and the same answer
## applies here: the resolver announces, and whoever caches the consequence
## subscribes. Invariant I-4, and the signal exists for exactly this.
##
## The id filter is what keeps one Assembly's damage out of another's arrays.
func _on_part_band_changed(assembly_id: int, slot: int, _before: int, after: int) -> void:
	if runtime == null or assembly_id != runtime.assembly_id:
		return
	if _motive_slots.has(slot):
		on_band_changed(slot, after)


## Registers a Motive Assembly and builds its family state.
##
## Called on [signal EventBusService.part_attached] and on adoption of a build
## context. A part registered twice would be solved twice and contribute double
## force, so re-registration replaces rather than appends.
##
## [param state] supplies the lattice placement an ambulatory limb's hip is
## derived from. It is optional because the garage registers a part before the
## Assembly runtime exists; a limb registered without one keeps its hip at the
## origin and is phased by slot order alone, which is still deterministic.
func register(slot: int, def: PartDefinition, state: PartInstanceState = null) -> void:
	if def == null or def.part_class != PartEnums.PartClass.MOTIVE_ASSEMBLY:
		return
	# The class test above is the sole guard, and registry validator rule 6 is
	# what makes that safe: it rejects a Motive Assembly with a null payload at
	# build time, so a definition reaching here without one has bypassed the
	# validator. A second check here would leave neither load-bearing — both
	# return without registering, and nothing could tell them apart.
	var mode := def.motive_profile.locomotion_mode()
	var profile := def.motive_profile
	_family[slot] = mode
	if not _motive_slots.has(slot):
		_motive_slots.push_back(slot)
		_motive_slots.sort()

	match mode:
		PartEnums.LocomotionMode.ROTARY:
			var disc := RotorDiscState.new()
			disc.slot = slot
			_discs[slot] = disc
		PartEnums.LocomotionMode.AMBULATORY:
			var limb := LimbState.new()
			limb.slot = slot
			limb.hip_local = hip_local_of(def, state)
			_limbs[slot] = limb
			_contacts[slot] = [_new_contact(slot, 0)]
		PartEnums.LocomotionMode.TRACKED:
			var stations: Array[MotiveContact] = []
			var count := 1
			if profile.track_profile != null:
				count = maxi(profile.track_profile.road_stations, 1)
			for i: int in count:
				stations.append(_new_contact(slot, i))
			_contacts[slot] = stations
		_:
			_contacts[slot] = [_new_contact(slot, 0)]

	_write_band_multipliers(slot, PartEnums.IntegrityBand.NOMINAL)
	_bind_probes(slot)
	_rebuild_axle_pairs()
	_rebuild_wheelbase()


## Drops a Motive Assembly that has been destroyed or detached.
func unregister(slot: int) -> void:
	var index := _motive_slots.find(slot)
	if index >= 0:
		_motive_slots.remove_at(index)
	_contacts.erase(slot)
	_discs.erase(slot)
	_limbs.erase(slot)
	# Anti-roll couples two surviving probes. Losing one end of an axle leaves
	# the other unpaired rather than pushing against a probe that has left.
	_rebuild_axle_pairs()
	_rebuild_wheelbase()
	# Phases are a function of the surviving limb set, so losing one re-phases
	# the rest. A walker that loses a limb changes its gait; leaving the others
	# on their old offsets would leave a hole in the cycle.
	reassign_gait_phases()


## Caches the band multipliers for [param slot].
##
## The whole of Architectural Invariant I-5 in this layer: the per-tick path
## reads these four arrays and never touches integrity.
func on_band_changed(slot: int, band: int) -> void:
	_write_band_multipliers(slot, band)


## Recomputes every limb's gait phase offset from the current limb set.
##
## Deterministic and identical on every machine (§11 invariant 16). Called on
## structural change, never per tick.
func reassign_gait_phases() -> void:
	var slots := PackedInt32Array()
	var hips := PackedVector3Array()
	for slot: int in _motive_slots:
		var limb: LimbState = _limbs.get(slot)
		if limb == null:
			continue
		slots.push_back(slot)
		hips.push_back(limb.hip_local)
	var offsets := GaitSolver.assign_phase_offsets(hips, slots)
	for i: int in slots.size():
		var limb: LimbState = _limbs[slots[i]]
		limb.phase_offset = offsets[i]


## One tick of locomotion.
##
## Gathers contacts, dispatches each Motive Assembly to its family, and refreshes
## the dynamic amplification factor. Every force reaches the body through
## [member AssemblyRuntime.body], and no family touches anything else (§11
## invariant 11).
##
## [b]§3.6: a terminated Assembly gets the coupling torque and nothing else.[/b]
## The torque is a property of the mass distribution and a tumbling hulk is where
## it is most visible, which is why §3.4 keeps it. The families are a different
## question and the answer is no: losing slot 0 orphans every part, the islands
## detach, and §3.5's floor leaves the body at one kilogramme still carrying
## every contact the intact build had. Solving springs sized for 1107 kg against
## that is what took a wreck from 17.3 m/s to 92.0 m/s in fifty frames, climbing,
## as the last thing a player saw.
func step(dt: float) -> void:
	if runtime == null or runtime.body == null:
		return
	# Before the input guard, and before any family runs. The coupling torque is
	# a property of the Assembly's mass distribution, not of what it is being
	# asked to do: an Assembly tumbling with nobody at the controls still has an
	# asymmetric tensor, and a wreck spinning through the air is exactly where
	# the correction is most visible.
	_apply_coupling_torque(dt)
	if input == null or not _is_alive():
		return
	_gather_contacts()

	var speed := runtime.body.linear_velocity.length()
	_gait_clock = GaitSolver.advance_clock(_gait_clock, _assembly_cadence_hz(), dt)

	for slot: int in _motive_slots:
		match _family[slot]:
			PartEnums.LocomotionMode.GROUND:
				_solve_ground(slot, dt, speed)
			PartEnums.LocomotionMode.TRACKED:
				_solve_tracked(slot, dt, speed)
			PartEnums.LocomotionMode.ROTARY:
				_solve_rotary(slot, dt)
			PartEnums.LocomotionMode.AMBULATORY:
				_solve_ambulatory(slot, dt)

	# After the families, because it differentiates the compressions they wrote
	# this tick. Running it first would couple last tick's roll into this one.
	_apply_anti_roll()
	_update_kappa(dt)
	_deposit_ruts()
	_drive_visuals()


## ===== INSPECTION ======================================================
## Read-only accessors over the flat state above. They exist so that tests, the
## garage stat panel, and the diagnostics overlay can read this system without
## any of them reaching into its arrays — which would make every one of them
## break the next time the layout changes.


## The locomotion family solving [param slot].
func family_of(slot: int) -> int:
	return _family[slot]


## Slots this system solves, ascending.
##
## Returned directly rather than duplicated. A `Packed*Array` copies on
## assignment (HANDOFF §3.9), so a caller writing `var slots := sys.motive_slots()`
## already has its own; the `duplicate()` this used to carry was dead, and fault
## injection said so. Note that the same is [i]not[/i] true of a plain `Array` —
## `AssemblyRegistry.ids()` does need its copy.
func motive_slots() -> PackedInt32Array:
	return _motive_slots


func motive_slot_count() -> int:
	return _motive_slots.size()


## Ground contacts belonging to [param slot]. One for most families, one per road
## station for a track, and none at all for a disc.
func contact_count(slot: int) -> int:
	var contacts: Array = _contacts.get(slot, [])
	return contacts.size()


func contact_at(slot: int, index: int) -> MotiveContact:
	var contacts: Array = _contacts.get(slot, [])
	if index < 0 or index >= contacts.size():
		return null
	return contacts[index]


func disc_state(slot: int) -> RotorDiscState:
	return _discs.get(slot)


func limb_state(slot: int) -> LimbState:
	return _limbs.get(slot)


func traction_multiplier(slot: int) -> float:
	return _traction_mult[slot]


func rolling_multiplier(slot: int) -> float:
	return _rolling_mult[slot]


func steer_multiplier(slot: int) -> float:
	return _steer_mult[slot]


func damp_multiplier(slot: int) -> float:
	return _damp_mult[slot]


## ===== LIVENESS ========================================================


## §3.6. Invariant I-2: an Assembly is over when slot 0 is destroyed.
##
## Read from the part rather than from a flag this system keeps, so that nothing
## here can disagree with [DamageResolver] — the same reading, for the same
## reason, that [method AiDriver._is_alive] makes.
func _is_alive() -> bool:
	var core: PartInstanceState = runtime.states[SyndicateConstants.CORE_SLOT]
	return core != null and not core.has_flag(PartFlags.FLAG_DESTROYED)


## ===== FAMILY SOLVERS ==================================================


func _solve_ground(slot: int, dt: float, chassis_speed: float) -> void:
	var def := _definition(slot)
	if def == null:
		return
	var profile := def.motive_profile
	var contacts: Array = _contacts.get(slot, [])
	# §7.6. One yaw error for the whole Assembly, evaluated before any contact is
	# solved, so every wheel this tick is corrected against the same heading.
	var yaw_error := _yaw_error(profile, chassis_speed)
	for c: MotiveContact in contacts:
		if not c.grounded:
			c.prev_compression_m = 0.0
			continue
		var x := SuspensionSolver.compression(profile, c)
		var rate := SuspensionSolver.compression_rate(c, x, dt)
		c.prev_compression_m = x
		var tuned := SuspensionSolver.retune(profile, _static_load_n(slot))
		c.normal_force_n = SuspensionSolver.force(
			tuned.x, tuned.y, profile.suspension_travel_limit_m, x, rate, _damp_mult[slot], chassis_speed
		)
		_apply_at(c.point_world, c.normal_world * c.normal_force_n)
		_steer_contact(slot, profile, c)
		_apply_traction(
			slot,
			profile,
			c,
			dt,
			1.0,
			_ground_drive_share(profile) * TractionControl.drive_scale(
				c.contact_omega * profile.contact_radius_m,
				c.velocity_world.dot(c.forward),
				input.traction_control
			),
			_yaw_brake_nm(slot, profile, yaw_error)
		)


func _solve_tracked(slot: int, dt: float, chassis_speed: float) -> void:
	var def := _definition(slot)
	if def == null:
		return
	var profile := def.motive_profile
	var track := profile.track_profile
	if track == null:
		return
	var contacts: Array = _contacts.get(slot, [])
	var normal_total := 0.0

	# §14.2's differential drive, and the whole of how a track steers. The bias
	# tapers to nothing at `pivot_taper_mps`, so the same expression pivots the
	# Assembly on the spot when it is stopped and commits it to a long arc at
	# speed, with nothing switching between the two.
	var bias := TrackSolver.drive_bias(track, input.steer, chassis_speed)
	var sides := TrackSolver.side_torques(
		track, 0.0 if power == null else power.drive_torque_nm, input.throttle, bias
	)
	var side := TrackSolver.side_of(_part_local_position(slot))
	var per_side := sides.y if side > 0 else sides.x
	# Shared across this part's road stations and across the parts on its side,
	# so adding a second bogie to a flank does not double that flank's torque.
	var share := per_side / maxf(float(_tracked_count_on_side(side) * contacts.size()), 1.0)

	for c: MotiveContact in contacts:
		if not c.grounded:
			c.prev_compression_m = 0.0
			continue
		var x := SuspensionSolver.compression(profile, c)
		var rate := SuspensionSolver.compression_rate(c, x, dt)
		c.prev_compression_m = x
		var tuned := SuspensionSolver.retune(
			profile, TrackSolver.station_static_load_n(profile, track)
		)
		c.normal_force_n = SuspensionSolver.force(
			tuned.x, tuned.y, profile.suspension_travel_limit_m, x, rate, _damp_mult[slot], chassis_speed
		)
		normal_total += c.normal_force_n
		_apply_at(c.point_world, c.normal_world * c.normal_force_n)
		_apply_traction(slot, profile, c, dt, track.lateral_grip_ratio, share)

	var yaw_rate := runtime.body.angular_velocity.dot(runtime.body.global_transform.basis.y)
	var slew := TrackSolver.slew_torque_nm(track, normal_total, yaw_rate)
	if not is_zero_approx(slew):
		runtime.body.apply_torque(runtime.body.global_transform.basis.y * slew)


func _solve_rotary(slot: int, dt: float) -> void:
	var def := _definition(slot)
	if def == null:
		return
	var rotor := def.motive_profile.rotor_profile
	var disc: RotorDiscState = _discs.get(slot)
	if rotor == null or disc == null:
		return

	var fraction := 1.0 if power == null else power.available_fraction()
	var command := RotorSolver.commanded_omega(rotor, absf(input.throttle), fraction)
	disc.omega_rad_s = RotorSolver.spool(
		disc.omega_rad_s, command, RotorSolver.spool_tau_s(rotor, disc.omega_rad_s, command), dt
	)
	disc.collective_deg = RotorSolver.step_collective(
		rotor, disc.collective_deg, _collective_command_deg(rotor), dt
	)
	disc.cyclic_deg = RotorSolver.step_cyclic(
		rotor, disc.cyclic_deg, input.cyclic * rotor.cyclic_limit_deg, dt
	)

	var st: PartInstanceState = runtime.states[slot]
	var band := 0 if st == null else int(st.integrity_band)
	var velocity := runtime.body.linear_velocity
	disc.last_thrust_n = RotorSolver.effective_thrust_n(
		rotor,
		disc.omega_rad_s,
		disc.collective_deg,
		_height_above_ground_m(),
		Vector2(velocity.x, velocity.z).length(),
		maxf(0.0, -velocity.y),
		band
	)
	disc.last_shaft_w = RotorSolver.shaft_power_w(rotor, disc.omega_rad_s)

	var axis_local := RotorSolver.thrust_direction(
		st.orientation_index if st != null else 0, disc.cyclic_deg, rotor.cyclic_limit_deg
	)
	var basis := runtime.body.global_transform.basis
	var axis_world := basis * axis_local
	_apply_at(_part_world_position(slot), axis_world * disc.last_thrust_n)

	var spin_axis := basis * (OrientationTable.basis_for(
		st.orientation_index if st != null else 0
	) * Vector3.UP)
	var torque := disc.reaction_torque_nm(rotor) + input.yaw * rotor.yaw_authority_nm
	if not is_zero_approx(torque):
		runtime.body.apply_torque(spin_axis * torque)


func _solve_ambulatory(slot: int, dt: float) -> void:
	var def := _definition(slot)
	if def == null:
		return
	var profile := def.motive_profile
	var limb_profile := profile.limb_profile
	var limb: LimbState = _limbs.get(slot)
	var contacts: Array = _contacts.get(slot, [])
	if limb_profile == null or limb == null or contacts.is_empty():
		return
	var contact: MotiveContact = contacts[0]

	var basis := runtime.body.global_transform.basis
	# The gait's own ceiling, not the chassis's. See [method GaitSolver.top_speed_mps].
	var gait_cap := _ambulatory_speed_cap_mps(limb_profile)
	var cadence := GaitSolver.cadence_hz(limb_profile, absf(input.throttle) * gait_cap)
	var was_planted := limb.planted
	limb.phase = GaitSolver.phase_of(_gait_clock, limb.phase_offset)

	# §13.4: "gait is frozen, every foot planted". Every foot — not the 62% of
	# the cycle that happened to be in stance when the clock stopped. The
	# document calls the standing state "the only state in which every limb
	# contributes stance force simultaneously, which is what makes a stationary
	# walker rock-solid", and that is only true if the limbs frozen mid-swing are
	# put down.
	#
	# Reading the previous tick's [member LimbState.planted] rather than
	# recomputing last tick's stance is what makes the transition work in both
	# directions, and it closes a second hole on the way: a limb that has never
	# been in stance has never run the placement law, so its `foot_world` is
	# whatever it was constructed with. An Assembly commanded to stand from spawn
	# never planted a foot at all — it sank until its own thigh colliders reached
	# the ground and sat there with a perfectly healthy gait clock running.
	var standing := is_zero_approx(cadence)
	var now_stance := true if standing else limb.in_stance(limb_profile)

	var hip_world := runtime.body.global_transform * limb.hip_local

	# Touchdown: the one moment the placement law runs [i]while walking[/i].
	# Planting every tick would make the foot chase the body and the Assembly
	# would never take a step.
	#
	# Standing needs one exception, and exactly one. A single plant on entry
	# cannot do the job: the Assembly is usually still falling onto its feet at
	# that moment, the probe has not found ground, and the foot is planted at
	# full extension in mid-air. §13.6's spring cannot pull, so that leg then
	# carries nothing for as long as the Assembly stands there — it settles onto
	# its own thigh colliders and stays down, which is where a walker commanded
	# to stand from spawn spent every engagement before this.
	#
	# The exception is bounded by [b]slack[/b] rather than by the standing state
	# alone. A planted foot is a fixed world anchor and that is most of what it
	# is for: it is what the friction cone in §13.6 acts through, and a foot
	# re-planted under the hip every tick anchors nothing, so the Assembly slides
	# on a frictionless stand and tips over the first time anything nudges it. A
	# leg longer than its rest length is producing no force and anchoring nothing
	# either, so re-planting that one costs nothing and is the only case that
	# needs it.
	var ground_y := (
		contact.point_world.y
		if contact.grounded
		else hip_world.y - limb_profile.leg_length_m
	)
	var slack := (hip_world - limb.foot_world).length() >= limb_profile.stance_rest_length_m()
	if now_stance and (not was_planted or (standing and slack)):
		limb.foot_world = _foot_target(limb_profile, hip_world, ground_y, gait_cap, cadence, basis)
		limb.prev_length_m = (hip_world - limb.foot_world).length()
	limb.planted = now_stance
	# §16.3. The foot the presentation layer draws is the plant point wherever
	# there is one, and the swing branch below replaces it with the arc. Written
	# on every path out of this function so that a limb returning early still
	# leaves it current rather than a tick stale.
	limb.foot_visual_world = limb.foot_world

	if not now_stance:
		limb.slipping = false
		# The arc reaches for the target the placement law would choose *now*
		# rather than one frozen at lift-off. That is only safe because §13.7
		# applies no force during swing: nothing drawn here can reach the physics,
		# so a target that tracks the body as it moves is honest rather than a
		# feedback path, and the foot lands where the next touchdown puts it
		# instead of jumping there.
		limb.foot_visual_world = GaitSolver.swing_foot_world(
			limb_profile,
			limb.foot_world,
			_foot_target(limb_profile, hip_world, ground_y, gait_cap, cadence, basis),
			GaitSolver.swing_progress(limb.phase, limb_profile.duty_factor)
		)
		return

	var to_hip := hip_world - limb.foot_world
	var length := to_hip.length()
	if length < SyndicateConstants.EPSILON_LINEAR:
		return
	var axial := GaitSolver.stance_axial_force_n(limb_profile, length, limb.prev_length_m, dt)
	limb.prev_length_m = length

	var st: PartInstanceState = runtime.states[slot]
	var band := 0 if st == null else int(st.integrity_band)
	var mu := GaitSolver.foot_mu(profile, band, _surface_multiplier(contact))
	var raw := to_hip.normalized() * axial
	var normal := contact.normal_world if contact.grounded else Vector3.UP
	limb.slipping = GaitSolver.would_slip(raw, normal, mu)
	var force := GaitSolver.limit_by_friction(raw, normal, mu)

	# A slipping foot slides by the shear it could not hold, which is what makes
	# a walker lose its footing progressively rather than in one frame.
	if limb.slipping:
		limb.foot_world += (raw - force) / maxf(limb_profile.stance_stiffness_n_m, 1.0)
		limb.foot_visual_world = limb.foot_world
	_apply_at(hip_world, force)


## §13.5's placement law with this tick's Assembly state filled in.
##
## Extracted because two callers need the identical answer: the touchdown that
## plants the foot, and §16.3's swing arc, which reaches for the point the next
## touchdown will choose. Two derivations of one target would let the drawn foot
## arc towards somewhere the simulation was never going to put it, and the limb
## would snap on every plant.
func _foot_target(
	profile: LimbProfile,
	hip_world: Vector3,
	ground_y: float,
	gait_cap: float,
	cadence_hz_value: float,
	basis: Basis
) -> Vector3:
	return GaitSolver.foot_target(
		profile,
		hip_world,
		ground_y,
		runtime.body.linear_velocity,
		input.desired_velocity(-basis.z, basis.x, gait_cap),
		cadence_hz_value,
		input.steer
	)


## ===== PRESENTATION ====================================================


## Writes this tick's contact geometry onto the part meshes. Doc 05 §16.
##
## [b]Presentation following the simulation, which is the direction
## Architectural Invariant I-1 permits.[/b] What the invariant forbids is the
## reverse — a collider derived from a mesh, or a visual transform that a
## physics query can see. Nothing here is read back: every quantity was produced
## by a family solver earlier in this same tick, the colliders stay exactly where
## the part was placed, and a build with the meshes switched off simulates
## identically.
##
## It runs here rather than inside the families because §6.0 rule 1 says a family
## contributes forces and nothing else, and that rule is worth keeping literally
## true. The branch below is the same [member _family] dispatch §11 invariant 12
## sanctions, asking a different question of the same array.
##
## A dedicated server has no meshes at all — the [code]part_visual[/code] tag is
## off, [method AssemblyRuntime.visual_of] answers null for every slot, and this
## costs one dictionary lookup per Motive Assembly and nothing else.
func _drive_visuals() -> void:
	for slot: int in _motive_slots:
		var node := runtime.visual_of(slot)
		if node == null:
			continue
		var def := _definition(slot)
		if def == null or def.visual_profile == null:
			continue
		var st: PartInstanceState = runtime.states[slot]
		match _family[slot]:
			PartEnums.LocomotionMode.ROTARY:
				# A disc has no ground contact and no suspension to show. Spinning
				# it is doc 13's, not this system's.
				pass
			PartEnums.LocomotionMode.AMBULATORY:
				var limb: LimbState = _limbs.get(slot)
				if limb == null:
					continue
				node.transform = PartMeshFactory.limb_pose(
					def.visual_profile,
					st.origin_cell,
					st.orientation_index,
					limb.hip_local,
					# Into the chassis frame the mesh's transform lives in. The
					# body's pose rather than `VisualRoot`'s: the interpolator
					# writes the latter on render frames, so reading it inside a
					# physics tick would resolve the foot against a transform from
					# part-way through the previous one.
					runtime.body.global_transform.affine_inverse() * limb.foot_visual_world
				)
			_:
				node.transform = PartMeshFactory.contact_pose(
					def.visual_profile,
					st.origin_cell,
					st.orientation_index,
					_mean_droop_m(slot, def.motive_profile)
				)


## Mean unconsumed suspension travel across [param slot]'s contacts, in metres.
##
## One mesh and, for a tracked patch, several road stations, so the part is drawn
## at the average of its stations rather than at whichever one happens to be
## first. Every other family carries a single contact and the mean is that
## contact.
func _mean_droop_m(slot: int, profile: MotiveAssemblyProfile) -> float:
	var contacts: Array = _contacts.get(slot, [])
	if contacts.is_empty():
		return 0.0
	var total := 0.0
	for c: MotiveContact in contacts:
		total += SuspensionSolver.droop_m(profile, c)
	return total / float(contacts.size())


## ===== SHARED ==========================================================


## §7.1. Advances [param slot]'s steer angle toward the commanded one and turns
## the contact frame to match.
##
## The contact frame is the [i]wheel's[/i], not the chassis's: §7.1 fixes x as
## the rolling direction, and a steered wheel's rolling direction is not the hull
## centreline. Rotating the frame here rather than steering with a yaw torque is
## what makes the lateral force a genuine slip-angle force — the wheel is pointed
## somewhere, the contact patch slides, and the Assembly turns because of the
## force that slide produces. A steering model that applied yaw directly would
## turn just as well on ice.
##
## A `WHEELED_FIXED` row authors `max_steer_angle_deg = 0` and falls through this
## unchanged, which is why there is no second code path for an unsteered wheel.
## The rate limit is scaled by the band multiplier, which is the only consumer
## [constant DegradationTable.MOTIVE_STEER] has: a Motive Assembly at `CRITICAL`
## turns at half rate and the Assembly understeers rather than failing outright.
func _steer_contact(slot: int, profile: MotiveAssemblyProfile, c: MotiveContact) -> void:
	var target := clampf(input.steer, -1.0, 1.0) * profile.max_steer_angle_deg
	var step := profile.steer_rate_deg_s * _steer_mult[slot] * SyndicateConstants.PHYSICS_DT
	_steer_deg[slot] = move_toward(_steer_deg[slot], target, step)
	if is_zero_approx(_steer_deg[slot]):
		return
	# About the contact normal rather than the chassis up, so a wheel on a camber
	# steers in the plane it is actually standing on. Negated because a positive
	# rotation about the surface normal carries the forward axis to the left,
	# and §7.2 of doc 11 fixes positive steer as right on every input device.
	var turn := Basis(c.normal_world, -deg_to_rad(_steer_deg[slot]))
	c.forward = turn * c.forward
	c.lateral = turn * c.lateral


## §7.6's yaw error for this tick, in rad/s, or zero when the aid is off, the
## Assembly is too slow for the model to mean anything, or it is already going
## where it was pointed.
func _yaw_error(profile: MotiveAssemblyProfile, chassis_speed: float) -> float:
	if input.traction_control <= 0.0 or chassis_speed < TractionControl.MIN_YAW_CONTROL_SPEED_MPS:
		return 0.0
	var forward := -runtime.body.global_transform.basis.z
	var along := runtime.body.linear_velocity.dot(forward)
	var target := TractionControl.target_yaw_rate_rad_s(
		along, deg_to_rad(_commanded_steer_deg()), _wheelbase_m
	)
	return TractionControl.yaw_error_rad_s(
		runtime.body.angular_velocity.dot(runtime.body.global_transform.basis.y),
		target,
		TractionControl.grip_limited_yaw_rate_rad_s(chassis_speed, profile.traction_coefficient)
	)


## The corrective brake for [param slot], applied only to the flank that opposes
## the error. Braking both flanks would slow the Assembly and turn it nowhere.
func _yaw_brake_nm(slot: int, profile: MotiveAssemblyProfile, yaw_error: float) -> float:
	if is_zero_approx(yaw_error):
		return 0.0
	if TrackSolver.side_of(_part_local_position(slot)) != TractionControl.brake_side(yaw_error):
		return 0.0
	return TractionControl.yaw_brake_nm(
		yaw_error, profile.brake_torque_nm, input.traction_control
	)


## The steer angle the driver is asking for, in degrees, taken from the widest
## authored lock on the Assembly. The yaw target is a property of the build, not
## of one wheel, and a build with no steered axle asks for no yaw at all.
func _commanded_steer_deg() -> float:
	var widest := 0.0
	for slot: int in _motive_slots:
		if _family[slot] != PartEnums.LocomotionMode.GROUND:
			continue
		var def := _definition(slot)
		if def != null:
			widest = maxf(widest, def.motive_profile.max_steer_angle_deg)
	return clampf(input.steer, -1.0, 1.0) * widest


## Longitudinal spread of the ground contacts, in metres.
func _rebuild_wheelbase() -> void:
	var lo := INF
	var hi := -INF
	for slot: int in _motive_slots:
		if _family[slot] != PartEnums.LocomotionMode.GROUND:
			continue
		for c: MotiveContact in _contacts.get(slot, []):
			if c.probe == null:
				continue
			lo = minf(lo, c.probe.position.z)
			hi = maxf(hi, c.probe.position.z)
	_wheelbase_m = 0.0 if lo > hi else hi - lo


## The wheelbase §7.6's yaw target is taken against. Diagnostics and tests.
func wheelbase_m() -> float:
	return _wheelbase_m


## Current steer angle at [param slot], in degrees, positive to the right.
func steer_angle_deg(slot: int) -> float:
	return _steer_deg[slot]


func _apply_traction(
	slot: int,
	profile: MotiveAssemblyProfile,
	c: MotiveContact,
	dt: float,
	lateral_ratio: float,
	drive_nm: float,
	extra_brake_nm: float = 0.0
) -> void:
	if c.normal_force_n <= 0.0:
		return
	var st: PartInstanceState = runtime.states[slot]
	var band := 0 if st == null else int(st.integrity_band)
	var v_long := c.velocity_world.dot(c.forward)
	var v_lat := c.velocity_world.dot(c.lateral)
	var kappa := TractionSolver.slip_ratio(c.contact_omega, profile.contact_radius_m, v_long)
	var tan_alpha := TractionSolver.slip_angle_tan(v_lat, v_long)
	var mu := TractionSolver.effective_mu(
		profile, c.normal_force_n, band, _surface_multiplier(c)
	)
	var forces := TractionSolver.combined_forces(
		kappa, tan_alpha, mu, c.normal_force_n, lateral_ratio
	)
	_apply_at(c.point_world, c.forward * forces.x + c.lateral * forces.y)

	var drive := drive_nm
	var brake := profile.brake_torque_nm * clampf(input.brake, 0.0, 1.0) + extra_brake_nm
	c.contact_omega = TractionSolver.integrate_contact(
		c.contact_omega,
		TractionSolver.contact_inertia(_definition(slot).mass_kg, profile.contact_radius_m),
		drive,
		brake,
		forces.x,
		profile.contact_radius_m,
		dt
	)


## §6.5. Couples paired probes so that an axle resists roll rather than letting
## each corner rise and fall alone.
##
## Reads the compression each family already wrote onto its contact this tick, so
## an anti-roll bar costs one subtraction per axle and no second probe sweep. The
## force is equal and opposite by construction: it transfers load across the
## axle, and can never change the Assembly's total normal force.
##
## An airborne pair contributes nothing, because an ungrounded contact has zero
## compression and both ends of the subtraction come from the same solver.
func _apply_anti_roll() -> void:
	for i: int in _axle_pairs.size() / 2:
		var left := _axle_pairs[i * 2]
		var right := _axle_pairs[i * 2 + 1]
		if not left.grounded and not right.grounded:
			continue
		var profile := _definition(left.slot).motive_profile
		var k_eff := SuspensionSolver.retune(profile, _static_load_n(left.slot)).x
		var f := SuspensionSolver.anti_roll_force(
			k_eff,
			left.prev_compression_m,
			right.prev_compression_m,
			SuspensionSolver.ANTI_ROLL_RATIO
		)
		if is_zero_approx(f):
			continue
		# Along each contact's own normal rather than a shared one, so a pair
		# straddling a camber transfers load along the surface it is standing on.
		_apply_at(left.probe.global_position, left.normal_world * -f)
		_apply_at(right.probe.global_position, right.normal_world * f)


## §3.4. Supplies the gyroscopic term the physics server does not integrate, so
## that an Assembly rotates about its true inertia tensor rather than about the
## diagonal one [member RigidBody3D.inertia] can hold.
##
## Euler's equation in the body frame is `I ω̇ + ω × (I ω) = τ`. **The server
## integrates `I_diag ω̇ = τ` and no gyroscopic term at all** — measured, in
## `tests/physics/test_inertia_coupling.gd`, by spinning a body whose three
## principal moments differ by 15% about its intermediate axis and watching the
## angular velocity not move for five seconds. §3.4 originally derived this
## correction as the *difference* between the diagonal and full gyroscopic terms,
## on the premise that the server applied the first of them. It does not, so the
## whole of `ω × (I_full ω)` is what has to be supplied, and the diagonal half of
## the old expression was cancelling a term nothing produced.
##
## Evaluated at the midpoint rather than at the start of the tick. The continuous
## torque is perpendicular to `ω` and therefore does no work, but sampling it at
## the tick boundary and holding it constant across the step does: explicit Euler
## on a 6 rad/s spin added about 16% of the rotational energy over five seconds,
## which §11 invariant 10 forbids outright. One extra evaluation at the half-step
## brings that under a tenth of a percent for the cost of one cross product, and
## the invariant becomes something the code can be held to rather than an
## aspiration.
##
## Without any of this a lopsided Assembly — one heavy Effector Module on the
## left flank — rotates as though it were symmetric: no precession, no yaw
## coupling under roll input, and no tumble about the intermediate axis. It reads
## as a vehicle that is subtly weightless rather than as a missing term.
func _apply_coupling_torque(dt: float) -> void:
	var mp := runtime.mass_properties
	if mp == null:
		return
	var basis := runtime.body.global_transform.basis
	var w := basis.inverse() * runtime.body.angular_velocity
	# Half a step of the correction's own effect, then the correction again from
	# there. `ω̇ = I_diag⁻¹ τ` is how the server will apply whatever is returned,
	# so that is the derivative the midpoint has to be taken along.
	var half := w + _angular_accel(mp, w) * (dt * 0.5)
	var tau := _gyroscopic_torque(mp, half).limit_length(COUPLING_TORQUE_LIMIT_NM)
	if tau.is_zero_approx():
		return
	runtime.body.apply_torque(basis * tau)


## `−ω × (I_full ω)`, in body space: the torque that makes a diagonal-tensor
## integrator reproduce the full tensor's free rotation.
static func _gyroscopic_torque(mp: MassSolver.MassProperties, w: Vector3) -> Vector3:
	return -w.cross(mp.inertia_full * w)


## The angular acceleration the server will produce from that torque, used only
## to step the midpoint. Divided by the diagonal because that is the tensor the
## server divides by, floored because §3.5 floors what it writes to the body.
static func _angular_accel(mp: MassSolver.MassProperties, w: Vector3) -> Vector3:
	var tau := _gyroscopic_torque(mp, w)
	return Vector3(
		tau.x / maxf(mp.inertia_diag.x, MassSolver.MIN_BODY_INERTIA),
		tau.y / maxf(mp.inertia_diag.y, MassSolver.MIN_BODY_INERTIA),
		tau.z / maxf(mp.inertia_diag.z, MassSolver.MIN_BODY_INERTIA)
	)


func _apply_at(point_world: Vector3, force: Vector3) -> void:
	if force.is_zero_approx():
		return
	runtime.body.apply_force(force, point_world - runtime.body.global_position)


## §9's dynamic amplification factor, refreshed at 10 Hz.
##
## The angular term captures the centripetal load on a part at the end of a long
## boom, proportional to omega squared times r, which pure linear acceleration
## misses entirely.
func _update_kappa(dt: float) -> void:
	var velocity := runtime.body.linear_velocity
	var accel := Vector3.ZERO
	if dt > 0.0:
		accel = (velocity - _prev_velocity) / dt
	_prev_velocity = velocity
	_kappa_accum += dt
	if _kappa_accum < KAPPA_INTERVAL_S:
		return
	_kappa_accum = 0.0
	var a := (
		accel.length()
		+ runtime.body.angular_velocity.length_squared() * KAPPA_ANGULAR_WEIGHT
	)
	if runtime.graph != null:
		runtime.graph.update_dynamic_factor(a)


func _write_band_multipliers(slot: int, band: int) -> void:
	_traction_mult[slot] = DegradationTable.multiplier(DegradationTable.MOTIVE_TRACTION, band)
	_rolling_mult[slot] = DegradationTable.multiplier(DegradationTable.MOTIVE_ROLLING, band)
	_steer_mult[slot] = DegradationTable.multiplier(DegradationTable.MOTIVE_STEER, band)
	_damp_mult[slot] = DegradationTable.multiplier(DegradationTable.MOTIVE_SUSP_DAMP, band)


func _new_contact(slot: int, station_index: int) -> MotiveContact:
	var c := MotiveContact.new()
	c.slot = slot
	c.station_index = station_index
	return c


## Populates this tick's probe results.
##
## A loop over already-built [ShapeCast3D] nodes copying four fields, with every
## derived quantity computed by a pure solver a test can reach directly. It is
## kept that thin deliberately, and now that `tests/physics/` can step the engine
## it is also exercised end to end rather than only by inspection.
func _gather_contacts() -> void:
	var xform := runtime.body.global_transform
	for slot: int in _motive_slots:
		var contacts: Array = _contacts.get(slot, [])
		for c: MotiveContact in contacts:
			var probe := c.probe
			c.clear_probe()
			if probe == null or not probe.is_colliding():
				continue
			c.grounded = true
			c.point_world = probe.get_collision_point(0)
			c.normal_world = probe.get_collision_normal(0)
			c.distance_m = probe.global_position.distance_to(c.point_world)
			c.forward = -xform.basis.z
			c.lateral = xform.basis.x
			c.velocity_world = _point_velocity(c.point_world)
			# Doc 09 §7.3. The classification is a property of the ground, so it
			# is read where the contact is resolved rather than derived later
			# from a position the solvers would have to keep hold of.
			if ground != null:
				c.surface_id = ground.surface_at_world(c.point_world)


## Doc 09 §6. Offers each loaded contact to the rut accumulator.
##
## Runs after the families, so [member MotiveContact.normal_force_n] is this
## tick's suspension result rather than last tick's. The accumulator does its
## own filtering — load floor, surface gate, and one deposit per sample per
## contact — and batches to a single request per second, so this loop is a
## handful of comparisons and never a deformation request.
func _deposit_ruts() -> void:
	if ground_deform == null:
		return
	for slot: int in _motive_slots:
		var contacts: Array = _contacts.get(slot, [])
		for c: MotiveContact in contacts:
			if not c.grounded:
				continue
			# The track key has to distinguish contacts across the whole match,
			# not just within this Assembly, or two Assemblies parked on the
			# same sample would suppress each other's deposits.
			var key := (runtime.assembly_id * 256 + slot) * 16 + c.station_index
			ground_deform.accumulate_rut(c.point_world, c.normal_force_n, c.surface_id, key)


func _point_velocity(point_world: Vector3) -> Vector3:
	var r := point_world - runtime.body.global_position
	return runtime.body.linear_velocity + runtime.body.angular_velocity.cross(r)


## Binds [param slot]'s contacts to the probes [AssemblyRuntime] built for them.
##
## Runs once per registration, which fixes the ordering the §6 wiring already
## has: [method AssemblyRuntime.adopt] builds the physics geometry, and only then
## is a Motive Assembly registered here. A part registered before its runtime
## exists — which the garage does — simply keeps a null probe and contributes no
## contact, because there is no world for it to sweep yet.
func _bind_probes(slot: int) -> void:
	if runtime == null:
		return
	var probes := runtime.motive_probes_of(slot)
	var contacts: Array = _contacts.get(slot, [])
	for i: int in mini(probes.size(), contacts.size()):
		var c: MotiveContact = contacts[i]
		c.probe = probes[i]


## Recomputes the §6.5 axle pairs across every registered contact.
##
## Ascending slot then station on both sides of the comparison, and each contact
## taken at most once, so the pair set is a deterministic function of the build
## (Invariant I-9). Left is the negative-x end of each pair, which is what makes
## the sign of [method SuspensionSolver.anti_roll_force] mean what its
## documentation says it means.
func _rebuild_axle_pairs() -> void:
	_axle_pairs.clear()
	var flat: Array[MotiveContact] = []
	for slot: int in _motive_slots:
		if _family[slot] == PartEnums.LocomotionMode.ROTARY:
			continue
		for c: MotiveContact in _contacts.get(slot, []):
			if c.probe != null:
				flat.append(c)

	# Only the far end of a pair is marked. Marking the near end as well reads as
	# symmetry and is dead: the outer loop visits each index once and ascending,
	# so an index can only be claimed by an earlier one — which is the `taken[j]`
	# write — and never revisits itself. Fault injection removed the second write
	# without a single test noticing, which is what dead code looks like here.
	var taken := PackedByteArray()
	taken.resize(flat.size())
	for i: int in flat.size():
		if taken[i] != 0:
			continue
		for j: int in range(i + 1, flat.size()):
			if taken[j] != 0:
				continue
			var a := flat[i].probe.position
			var b := flat[j].probe.position
			if not SuspensionSolver.is_axle_pair(a, b):
				continue
			taken[j] = 1
			if a.x < b.x:
				_axle_pairs.append(flat[i])
				_axle_pairs.append(flat[j])
			else:
				_axle_pairs.append(flat[j])
				_axle_pairs.append(flat[i])
			break


## Axle pairs found across this Assembly's probes. Diagnostics and tests.
func axle_pair_count() -> int:
	return _axle_pairs.size() / 2


## One end of axle pair [param index]: [param right] false for the negative-x
## end, true for the positive-x one.
##
## The side matters and a count does not. Four probes make two pairs whether they
## were matched across the Assembly or down one flank, so a test that counts them
## passes against pairing that ignores §6.5's sign test entirely — which is the
## one thing the pairing exists to do, because two probes on the same side have
## no roll couple between them to resist.
func axle_pair_end(index: int, right: bool) -> MotiveContact:
	var at := index * 2 + (1 if right else 0)
	if at < 0 or at >= _axle_pairs.size():
		return null
	return _axle_pairs[at]


## The definition at [param slot], or null when there is nothing there.
##
## Null-safe on [member runtime] because registration happens before the system
## is wired to an Assembly: the garage registers parts as they are placed, and
## [method reassign_gait_phases] runs on that path. [method step] guards
## separately and earlier, so nothing per-tick reaches here unwired.
func _definition(slot: int) -> PartDefinition:
	if runtime == null:
		return null
	var st: PartInstanceState = runtime.states[slot]
	if st == null:
		return null
	return PartRegistry.definition(st.part_def_id)


## The hip's position in assembly-local space, from the part's placement.
##
## The pivot cell's centre plus the authored offset under the part's orientation
## basis — the pivot rather than the centre of mass, because §7.2.2 defines
## [member LimbProfile.hip_offset_m] relative to the pivot cell and a limb's
## pivot is the cell it mounts through.
##
## Public because [AssemblyRuntime] needs the same answer when it builds the
## limb's probe: the sweep starts at the hip and runs the length of the leg, and
## two derivations of one hip position is exactly the "two owners of one
## invariant" this project keeps deleting.
static func hip_local_of(def: PartDefinition, state: PartInstanceState) -> Vector3:
	if state == null:
		return Vector3.ZERO
	var offset := def.motive_profile.limb_profile.hip_offset_m
	return (
		LatticeMath.cell_to_local(state.origin_cell)
		+ OrientationTable.basis_for(state.orientation_index) * offset
	)


func _part_world_position(slot: int) -> Vector3:
	return runtime.part_world_position(slot)


func _static_load_n(slot: int) -> float:
	var def := _definition(slot)
	if def == null:
		return 0.0
	return def.motive_profile.rated_load_kg * SyndicateConstants.GRAVITY_MPS2


## A GROUND contact's share of the Assembly's drive torque. Split evenly across
## the driven Motive Assemblies, which is an open differential and is why a
## wheeled Assembly with one wheel in the air spins it and goes nowhere.
func _ground_drive_share(profile: MotiveAssemblyProfile) -> float:
	if not profile.driven or power == null:
		return 0.0
	return power.throttle_torque_nm(input.throttle) / maxf(float(_driven_count()), 1.0)


## The part's pivot in assembly-local metres. §14.2 partitions the sides by the
## sign of this, so a bogie's side is where the builder put it and not a flag.
func _part_local_position(slot: int) -> Vector3:
	var st: PartInstanceState = runtime.states[slot]
	if st == null:
		return Vector3.ZERO
	return LatticeMath.cell_to_local(st.origin_cell)


## Tracked Motive Assemblies on [param side], for the torque split.
func _tracked_count_on_side(side: int) -> int:
	var count := 0
	for slot: int in _motive_slots:
		if _family[slot] != PartEnums.LocomotionMode.TRACKED:
			continue
		if TrackSolver.side_of(_part_local_position(slot)) == side:
			count += 1
	return count


func _driven_count() -> int:
	var count := 0
	for slot: int in _motive_slots:
		var def := _definition(slot)
		if def != null and def.motive_profile.driven:
			count += 1
	return count


func _assembly_cadence_hz() -> float:
	var best := 0.0
	for slot: int in _motive_slots:
		if _family[slot] != PartEnums.LocomotionMode.AMBULATORY:
			continue
		var def := _definition(slot)
		if def == null or def.motive_profile.limb_profile == null:
			continue
		var limb_profile := def.motive_profile.limb_profile
		best = maxf(
			best,
			GaitSolver.cadence_hz(
				limb_profile, absf(input.throttle) * _ambulatory_speed_cap_mps(limb_profile)
			)
		)
	return best


## The speed an ambulatory demand is measured against: the lesser of the Core
## Module's chassis cap and what this gait can actually deliver.
func _ambulatory_speed_cap_mps(profile: LimbProfile) -> float:
	return minf(_speed_cap_mps(), GaitSolver.top_speed_mps(profile))


func _commanded_speed_mps() -> float:
	return absf(input.throttle) * _speed_cap_mps()


func _speed_cap_mps() -> float:
	var core: PartInstanceState = runtime.states[SyndicateConstants.CORE_SLOT]
	if core == null:
		return 0.0
	var def := PartRegistry.definition(core.part_def_id)
	if def == null or def.core_profile == null:
		return 0.0
	return def.core_profile.speed_cap_mps


func _collective_command_deg(rotor: RotorProfile) -> float:
	var t := clampf(input.collective, -1.0, 1.0)
	if t >= 0.0:
		return rotor.collective_limit_deg.y * t
	return -rotor.collective_limit_deg.x * t


## Height of the lowest rotary contribution above the surface.
##
## Ground effect needs a height and a rotary Assembly runs no probe, so this is
## the one place the family reaches outside itself. Returns a height beyond any
## profile's ground-effect span when nothing is known, which makes the
## multiplier exactly 1.0 rather than an arbitrary boost.
func _height_above_ground_m() -> float:
	for slot: int in _motive_slots:
		var contacts: Array = _contacts.get(slot, [])
		for c: MotiveContact in contacts:
			if c.grounded:
				return maxf(0.0, runtime.body.global_position.y - c.point_world.y)
	return INF


## Surface friction multiplier for a contact.
##
## Answered by [SurfaceTable], whose [constant SurfaceTable.TRACTION] array doc
## 09 §9.1 owns and doc 05 §7.3 indexes. There is one definition of that table
## and this is its only consumer.
##
## An Assembly on an Array-less fixture — a unit test over the solvers, or the
## garage — reads the reference surface, which is what every measurement in
## `tests/physics/` was taken against.
func _surface_multiplier(contact: MotiveContact) -> float:
	if ground == null:
		return 1.0
	return SurfaceTable.multiplier(contact.surface_id)
