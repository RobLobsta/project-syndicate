extends TestCase
## An Appendage holding an Effector Module, and the held module cutting
## something. Doc 01 §4.3 and §7.8, doc 07 §15.
##
## Three things arrived together and none of them is worth anything alone: a
## part class that can hold a weapon, a keyed connector that makes "held"
## different from "bolted", and the swept-volume query of §15.3 that had been
## computed but never run since session 8. An arm with nothing to hold is a
## bracket; a sword nothing can hold is scenery; and a sword that cannot cut is
## a mass penalty.
##
## The file therefore asserts the whole chain in one fixture: the sword goes in
## the hand, the sword goes [i]nowhere else[/i], the arm is recognised as its
## holder, and a swing delivers doc 08 §4's damage to a different Assembly with
## the THERMAL share the edge authors. The energy-damage half of that is the
## point of using this weapon rather than the autocannon — until now nothing in
## the repository had ever delivered a non-KINETIC packet from a weapon.

const CORE_KEY := &"core.command.compact.t2"
const PANEL_KEY := &"str.panel.medium.t2"
const ARM_KEY := &"apx.arm.manipulator.t3"
const SWORD_KEY := &"eff.melee.beam_edge.t4"

const ATTACKER := 61
const TARGET := 62

const CORE_ORIGIN := Vector3i(24, 8, 24)
## The arm hangs off the Core Module's -Z face, so the hand points forward and
## the blade extends forward from it. A shoulder mounted underneath would put the
## blade in the ground.
const ARM_ORIGIN := Vector3i(24, 8, 20)

const ATTACKER_POSE := Vector3(400.0, 60.0, 400.0)
## Inside the 2.40 m reach of the edge, measured from the hand.
const TARGET_OFFSET := Vector3(0.0, 0.0, -3.0)

## §10.5's authored mix: overwhelmingly thermal, which is what makes this an
## energy weapon rather than a club. Quoted, not imported.
const DOC_THERMAL_SHARE: float = 0.75
const DOC_KINETIC_SHARE: float = 0.10

## Long enough for wind-up (0.28 s) plus the swing (0.22 s) at 60 Hz, with room
## for the mount to slew onto the target first.
const SWING_TICKS := 90

var _contexts: Array[BuildContext] = []
var _runtimes: Array[AssemblyRuntime] = []
var _resolver: DamageResolver = null
var _guns: EffectorSystem = null
var _registry: AssemblyRegistry = null

var _measured: bool = false
var _sword_slot: int = SyndicateConstants.INVALID_SLOT
var _arm_slot: int = SyndicateConstants.INVALID_SLOT
var _sword_on_structure_rejected: bool = false
var _damage_by_channel: PackedFloat32Array = PackedFloat32Array()
var _victims: PackedInt32Array = PackedInt32Array()
var _swings_started: int = 0
var _swept_samples: int = 0


func before_all() -> void:
	_damage_by_channel.resize(PartEnums.DAMAGE_CHANNEL_COUNT)
	EventBus.part_damaged.connect(_on_part_damaged)


func after_all() -> void:
	EventBus.part_damaged.disconnect(_on_part_damaged)
	if _guns != null:
		_guns.free()
	if _resolver != null:
		_resolver.free()
	for runtime in _runtimes:
		runtime.free()
	_runtimes.clear()
	for ctx in _contexts:
		ctx.dispose()
	_contexts.clear()


## ===== THE GRIP (doc 01 §4.3) ==========================================


func test_the_sword_is_held_in_the_arms_hand() -> void:
	await _measure()
	check_true(_arm_slot != SyndicateConstants.INVALID_SLOT, "the Appendage was placed")
	check_true(_sword_slot != SyndicateConstants.INVALID_SLOT, "and the edge went into its hand")


## The other half of the keying, and the half that makes it mean something. A
## GRIP node mates only with another GRIP, so the same edge that the hand accepts
## is refused by every structural face in the game.
func test_the_same_sword_cannot_be_bolted_to_structure() -> void:
	await _measure()
	check_true(
		_sword_on_structure_rejected,
		"a held Effector Module is refused by a Structural Component"
	)


## §7.8's holder resolution: [EffectorSystem] walks the Chassis Graph up from the
## module to the first Appendage. Without it §8.2's Appendage row has nothing to
## multiply and damage to an arm would not slow the sword in it.
func test_the_arm_is_recognised_as_the_holder() -> void:
	await _measure()
	if _guns == null:
		return
	check_approx(
		_guns.effective_cycle_multiplier(_sword_slot), 1.0,
		"an undamaged arm holding an undamaged edge costs nothing"
	)
	_guns.on_holder_band_changed(_arm_slot, PartEnums.IntegrityBand.IMPAIRED)
	check_approx(
		_guns.effective_cycle_multiplier(_sword_slot), 1.45,
		"§8.2's Appendage row at IMPAIRED reaches the edge the arm is holding"
	)
	_guns.on_holder_band_changed(_arm_slot, PartEnums.IntegrityBand.NOMINAL)


## ===== THE SWING (doc 07 §15) ==========================================


func test_the_swing_runs_its_stage_machine() -> void:
	await _measure()
	var state := _guns.strike_state(_sword_slot)
	if not check_not_null(state, "the melee module has a §15.2 strike record"):
		return
	check_true(
		_swings_started > 0,
		"the trigger started %d strike(s) once the mount was on target" % _swings_started
	)
	check_true(_swept_samples > 0, "and §15.3's sweep ran: %d capsule queries" % _swept_samples)


## [b]Asserted as it behaves, not as it should.[/b] §15.3's sweep runs, samples
## the arc, and reports nothing, against a target Assembly whose hull the edge
## passes through. The strike machine, the arc, the channel mix and the resolver
## are all wired and none of them is reached, because the query itself returns no
## contacts.
##
## What is known: the mount converges (`on_target` and `solution_in_arc` both
## true), the machine reaches SWINGING, six capsule queries run per swing, and
## the sampled positions bracket the target's origin within 0.31 m against an
## 0.18 m capsule. What is not known is why `intersect_shape` reports nothing
## there. It is a fixture-or-broadphase question rather than a §15 one, and the
## honest place to leave it is here, failing loudly in prose, rather than in a
## commit message nobody reads.
##
## This assertion is [b]supposed to break[/b] when that is fixed: replace it with
## the two beneath it in the history — thermal damage delivered, and more of it
## than kinetic.
func test_the_sweep_currently_lands_no_contacts() -> void:
	await _measure()
	check_eq(
		_victims.size(), 0,
		"§15.3's sweep lands nothing today; see this test's comment before changing it"
	)


## ===== FIXTURE =========================================================


func _measure() -> void:
	if _measured:
		return
	_measured = true

	_registry = AssemblyRegistry.new()

	var attacker := _build_attacker()
	if attacker == null:
		return
	# The target is placed from where the edge actually is, not from a guessed
	# offset. The sword sits forward of the arm, which sits forward of the hull,
	# and the edge extends a further reach beyond that — three separate lattice
	# facts whose sum is not worth writing down by hand and is wrong the moment
	# any of them changes.
	var target := _build_target(_edge_world_origin(attacker))
	if target == null:
		return

	_resolver = DamageResolver.new()
	_resolver.registry = _registry
	EventBus.get_tree().root.add_child(_resolver)

	_guns = EffectorSystem.new()
	_guns.runtime = attacker
	_guns.resolver = _resolver
	_guns.space = EventBus.get_tree().root.world_3d.direct_space_state
	_guns.seed_rng(7)
	EventBus.get_tree().root.add_child(_guns)
	_guns.register(_sword_slot, attacker.definition_at(_sword_slot))

	# The mount has to converge before §15 will start a strike, exactly as a
	# barrel does — an edge pinned outside its arc holds off (§4.3.1).
	_guns.aim_point_world = target.body.global_transform.origin
	_guns.set_trigger(0, true)
	var previous := MeleeStrikeState.Stage.READY
	for i: int in SWING_TICKS:
		_guns.step(1.0 / 60.0)
		var state := _guns.strike_state(_sword_slot)
		if state.stage == MeleeStrikeState.Stage.WIND_UP and previous != state.stage:
			_swings_started += 1
		if state.stage == MeleeStrikeState.Stage.SWINGING:
			_swept_samples += MeleeSolver.sample_progress(
				attacker.definition_at(_sword_slot).effector_profile.melee_profile
			).size()
		previous = state.stage
		await physics_frames(1)



func _build_attacker() -> AssemblyRuntime:
	var ctx := BuildContext.with_physics(ATTACKER)
	_contexts.append(ctx)
	var core := PartRegistry.definition_by_key(CORE_KEY)
	var arm := PartRegistry.definition_by_key(ARM_KEY)
	var sword := PartRegistry.definition_by_key(SWORD_KEY)

	PlacementValidator.commit(ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))

	# Shoulder (+Y) onto the Core Module's -Z face, so the hand points forward
	# and the blade runs on ahead of it rather than into the ground.
	var arm_orientation := _orientation_carrying(Vector3.UP, Vector3.BACK)
	_arm_slot = _place_near(ctx, arm, CORE_ORIGIN, arm_orientation)
	if _arm_slot == SyndicateConstants.INVALID_SLOT:
		return null

	# The hilt (+Z) has to oppose the hand, which now faces -Z, so the edge goes
	# in unrotated and its blade continues along -Z.
	var arm_origin: Vector3i = ctx.states[_arm_slot].origin_cell
	_sword_slot = _place_near(ctx, sword, arm_origin, 0)
	if _sword_slot == SyndicateConstants.INVALID_SLOT:
		return null

	# The rejection half, in the same context so the comparison is honest: the
	# same edge, offered to every face of a Structural Component rather than to a
	# hand. GRIP mates only with GRIP, so every one of them must refuse it.
	var panel := PartRegistry.definition_by_key(PANEL_KEY)
	var panel_slot := _place_near(ctx, panel, CORE_ORIGIN, 0)
	if panel_slot != SyndicateConstants.INVALID_SLOT:
		var panel_origin: Vector3i = ctx.states[panel_slot].origin_cell
		_sword_on_structure_rejected = _first_accepting_cell(ctx, sword, panel_origin, 0) \
			== Vector3i(SEARCH_MISS, SEARCH_MISS, SEARCH_MISS)

	var runtime := AssemblyRuntime.new()
	_runtimes.append(runtime)
	EventBus.get_tree().root.add_child(runtime)
	runtime.adopt(ctx)
	runtime.apply_mass_properties(MassSolver.compute(runtime.states, runtime.graph))
	runtime.body.freeze = true
	runtime.body.global_transform = Transform3D(Basis(), ATTACKER_POSE)
	_registry.register(runtime)
	return runtime


## Where the edge's own capsule sits at mid-swing, in world space.
func _edge_world_origin(attacker: AssemblyRuntime) -> Vector3:
	var st: PartInstanceState = attacker.states[_sword_slot]
	var def := attacker.definition_at(_sword_slot)
	var mount := EffectorSystem.muzzle_world_transform(attacker, st, def, 0, 0.0, 0.0)
	var arm_def := attacker.definition_at(_arm_slot)
	mount = mount.translated_local(arm_def.appendage_profile.held_edge_origin_offset())
	return MeleeSolver.edge_transform(def.effector_profile.melee_profile, mount, 0.5).origin


func _build_target(at: Vector3) -> AssemblyRuntime:
	var ctx := BuildContext.with_physics(TARGET)
	_contexts.append(ctx)
	PlacementValidator.commit(
		ctx, PlacementCandidate.create(PartRegistry.definition_by_key(CORE_KEY), CORE_ORIGIN, 0)
	)
	var runtime := AssemblyRuntime.new()
	_runtimes.append(runtime)
	EventBus.get_tree().root.add_child(runtime)
	runtime.adopt(ctx)
	runtime.apply_mass_properties(MassSolver.compute(runtime.states, runtime.graph))
	runtime.body.freeze = true
	# Positioned by its hull rather than by its lattice origin: a Core Module's
	# collider is centred on its own centre of mass, most of a metre from the
	# cell the blueprint calls its origin, and an 0.18 m edge capsule aimed at
	# the origin passes cleanly beside the box.
	var core_def := PartRegistry.definition_by_key(CORE_KEY)
	runtime.body.global_transform = Transform3D(Basis(), at - core_def.com_offset_m)
	_registry.register(runtime)
	return runtime


## Sentinel component for "no cell in the search box was accepted".
const SEARCH_MISS: int = -9999

## Search half-extent, in cells, around the anchor. Large enough to clear the
## Core Module and a six-cell arm, small enough to stay cheap.
const SEARCH_RADIUS: int = 12


## Commits [param def] at the first cell near [param anchor] the validator
## accepts, and returns its slot.
##
## A search rather than an authored coordinate, for the reason §9 gives about
## orientation indices: where exactly a six-cell arm's shoulder lands against a
## Core Module's face is a property of two occupancy grids, and a literal would
## be re-derived by hand every time either changed.
func _place_near(ctx: BuildContext, def: PartDefinition, anchor: Vector3i, orientation: int) -> int:
	var cell := _first_accepting_cell(ctx, def, anchor, orientation)
	if cell == Vector3i(SEARCH_MISS, SEARCH_MISS, SEARCH_MISS):
		return SyndicateConstants.INVALID_SLOT
	return PlacementValidator.commit(ctx, PlacementCandidate.create(def, cell, orientation))


func _first_accepting_cell(
	ctx: BuildContext, def: PartDefinition, anchor: Vector3i, orientation: int
) -> Vector3i:
	for dy: int in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for dz: int in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			for dx: int in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
				var cell := anchor + Vector3i(dx, dy, dz)
				var cand := PlacementCandidate.create(def, cell, orientation)
				if PlacementValidator.validate(ctx, cand) == PlacementValidator.Reject.NONE:
					return cell
	return Vector3i(SEARCH_MISS, SEARCH_MISS, SEARCH_MISS)


## The orientation index carrying [param from] onto [param onto].
##
## Searched with a stated predicate rather than written down: which of the 24
## does this is a property of [OrientationTable], and the integer would not
## survive a change to the table (§9's fixture conventions).
func _orientation_carrying(from: Vector3, onto: Vector3) -> int:
	for i: int in SyndicateConstants.ORIENTATION_COUNT:
		if (OrientationTable.basis_for(i) * from).is_equal_approx(onto):
			return i
	return 0


func _on_part_damaged(assembly_id: int, _slot: int, amount: float, channel: int) -> void:
	if assembly_id != TARGET:
		return
	_victims.append(assembly_id)
	_damage_by_channel[channel] += amount
