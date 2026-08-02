class_name DamageResolver
extends Node
## The single entry point for damage, owned by
## [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code].
##
## Nothing else in the project writes [member PartInstanceState.integrity].
## Repair routes through the same band-transition path, which is what makes
## Architectural Invariant I-5 enforceable rather than aspirational: there is one
## function that can change a part's band, and every subsystem that cares learns
## about it from one signal.
##
## [b]It is not an autoload.[/b] CLAUDE.md §4 freezes the autoload list at eight,
## and doc 08 §3.1's amendment records why: the resolver needs an
## [AssemblyRegistry], which is an ordinary object owned by the match scene, so
## the resolver is one too. The match scene hands it out.
##
## Reactions are batched, never recursive. A Prime Mover destroyed by a hit
## queues its detonation rather than resolving it inline, because a blast applied
## in the middle of resolving the packet that caused it would re-enter this class
## while it was iterating — and §12's chain-reaction depth bound would be
## measuring the wrong thing.

## ===== CHAIN BOUND =====================================================

## Architectural Invariant I-12. A magazine detonating a Prime Mover detonating
## a second magazine is three deep and is where it stops.
const MAX_CHAIN_DEPTH: int = 3

## ===== KINETIC (§4) ====================================================

## Floor on cos(theta), capping the benefit of sloped armour at 5x. Without it a
## grazing hit produces unbounded effective armour and a guaranteed ricochet,
## which reads to a player as broken rather than as clever.
const COS_FLOOR: float = 0.20
## cos(72 degrees). Below this angle a hit may deflect entirely.
const RICOCHET_COS: float = 0.309
## Penetration must be under this multiple of effective armour to deflect.
const RICOCHET_PEN_FACTOR: float = 1.15
## Damage a deflection still deals, so an oblique hit is not entirely free.
const RICOCHET_DAMAGE_FRACTION: float = 0.10
## Penetration ratio below which the round is defeated outright.
const PEN_DEFEAT: float = 0.55
## Partial-penetration ceiling: at the threshold itself a round deals 42%.
const PEN_PARTIAL_SCALE: float = 0.42
## Bonus per unit of surplus penetration past full, and the cap on it.
const PEN_SURPLUS_GAIN: float = 0.30
const PEN_SURPLUS_CAP: float = 1.5
## Ratio at and above which the round passes through and spalls.
const OVERPEN_RATIO: float = 1.85

## ===== SPALL (§4.4) ====================================================

const SPALL_FRACTION: float = 0.28
const SPALL_CONE_DEG: float = 34.0
const SPALL_RANGE_M: float = 2.4
## Ceiling on how many parts one overpenetration sprays. Architectural Invariant
## I-12: every repeatable reaction carries an explicit bound.
const SPALL_MAX_SLOTS: int = 6

## Armour rating at which a non-kinetic packet loses half its damage. Blast,
## impact and thermal carry no penetration figure to compare against, so armour
## absorbs on a curve rather than gating on a threshold.
const ARMOUR_HALF_ABSORPTION: float = 40.0

## ===== BLAST (§5) ======================================================

## Falloff exponent. Above 1.0, so damage concentrates near the epicentre and
## accurate placement beats volume of fire.
const BLAST_EXPONENT: float = 1.85
## Attenuation contributed by one intervening solid cell.
const OCCLUSION_PER_CELL: float = 0.22
## Ceiling on total occlusion. A deeply buried part still takes 12% of the
## falloff-adjusted blast; full immunity through burial would make a
## well-protected Core Module invulnerable to explosives, which is not intended.
const OCCLUSION_MAX: float = 0.88
## Bodies one blast query may return.
const BLAST_QUERY_LIMIT: int = 96

## ===== IMPACT (§6) =====================================================

const IMPACT_K: float = 2.4
## Below this effective speed nothing happens. Essential: without it an Assembly
## resting on the ground takes continuous micro-damage from contact noise.
const IMPACT_THRESHOLD_MPS: float = 3.5
const IMPACT_EXPONENT: float = 1.15
const IMPACT_MAX_PER_CONTACT: float = 900.0
## A sustained scrape produces a contact every tick; without this, dragging along
## a wall would destroy an Assembly in seconds.
const IMPACT_COOLDOWN_S: float = 0.22

## ===== THERMAL AND CORROSIVE (§7) ======================================

const THERMAL_HEAT_RATIO: float = 0.55
const THERMAL_IGNITION_HU: float = 480.0
## Hysteresis: ignition at 480, extinction at 320, so a part on the boundary does
## not flicker between burning and not.
const THERMAL_EXTINCTION_HU: float = 320.0
const THERMAL_SELF_DAMAGE_PER_S: float = 4.0
const CORROSIVE_ARMOUR_BYPASS: float = 0.40
const CORROSIVE_RESIST_DECAY: float = 0.035

## ===== WIRING ==========================================================

## Assemblies this resolver may reach. Supplied by the match scene.
var registry: AssemblyRegistry = null
## Space blast queries run in. Null on a resolver that never resolves a blast —
## a unit test over direct packets does not need one, and §5.3 is the only
## consumer.
var space: PhysicsDirectSpaceState3D = null
## Sink for a destroyed part's island work. The scheduler already listens to
## [signal EventBusService.part_destroyed]; this is here so a test can observe
## the resolver without one.
var _detonations: Array[Dictionary] = []
## `assembly_id * 256 + slot` -> match time of the last impact packet, for §6.2.
var _last_impact_time: Dictionary = {}


func _ready() -> void:
	EventBus.connect_tick_resolved(_flush_detonations, EventBus.PRIORITY_DAMAGE)


func _exit_tree() -> void:
	EventBus.disconnect_tick_resolved(_flush_detonations)


## Resolves [param packet] against its target. §3.1.
##
## The only function in the project that may reduce a part's integrity.
func apply(packet: DamagePacket) -> DamageOutcome:
	if not NetAuthority.can_resolve_damage():
		return DamageOutcome.rejected("client cannot author damage")
	if registry == null:
		return DamageOutcome.rejected("no registry")
	var runtime := registry.get_runtime(packet.target_assembly_id)
	if runtime == null:
		return DamageOutcome.rejected("no assembly")
	if packet.target_slot < 0 or packet.target_slot >= runtime.states.size():
		return DamageOutcome.rejected("slot out of range")
	var st: PartInstanceState = runtime.states[packet.target_slot]
	if st == null or st.has_flag(PartFlags.FLAG_DESTROYED | PartFlags.FLAG_DETACHED):
		return DamageOutcome.rejected("part not live")
	var def := PartRegistry.definition(st.part_def_id)
	if def == null:
		return DamageOutcome.rejected("no definition")

	var effective := _compute_effective(packet, st, def)
	if packet.channel == PartEnums.DamageChannel.THERMAL:
		_accumulate_heat(st, def, packet)
	elif packet.channel == PartEnums.DamageChannel.CORROSIVE:
		st.decay_resistance(def, CORROSIVE_RESIST_DECAY * packet.interval_s)

	if effective <= 0.0:
		EventBus.damage_negated.emit(
			packet.target_assembly_id, packet.target_slot, int(packet.channel)
		)
		return DamageOutcome.negated()

	var band_before := st.integrity_band
	st.integrity = maxf(0.0, st.integrity - effective)
	var band_after := band_for(st.integrity_fraction(def))
	var destroyed := false
	if band_after != band_before:
		st.integrity_band = band_after
		destroyed = _on_band_transition(runtime, st, def, band_before, band_after, packet)

	st.flags |= PartFlags.FLAG_NET_DIRTY
	EventBus.part_damaged.emit(
		packet.target_assembly_id, packet.target_slot, effective, int(packet.channel)
	)
	if packet.channel == PartEnums.DamageChannel.KINETIC:
		_generate_spall(packet, effective, runtime, st, def)
	return DamageOutcome.applied(effective, band_after, destroyed)


## Applies a blast at [param centre], to every part of every Assembly the query
## reaches. §5.3.
##
## One physics query for the whole blast, not one per part. Assembly ids and
## slots are both resolved in ascending order, which Architectural Invariant I-9
## requires: a blast frequently destroys parts across several Assemblies, and the
## order they die in is the order [signal EventBusService.part_destroyed] fires,
## which is the order debris bodies are allocated on the network.
func resolve_blast(
	centre: Vector3,
	radius_m: float,
	damage: float,
	source_assembly_id: int,
	source_slot: int,
	chain_depth: int
) -> void:
	if space == null or registry == null or radius_m <= 0.0:
		return
	var sphere := SphereShape3D.new()
	sphere.radius = radius_m
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis(), centre)
	params.collision_mask = CollisionLayers.MASK_BLAST_QUERY
	var hits := space.intersect_shape(params, BLAST_QUERY_LIMIT)

	var touched: Dictionary = {}
	for hit: Dictionary in hits:
		var body: Object = hit.get("collider")
		if not (body is ChassisBodyRef):
			continue
		var chassis := body as ChassisBodyRef
		var slot := chassis.slot_for_shape_index(int(hit.get("shape", -1)))
		if slot == SyndicateConstants.INVALID_SLOT:
			continue
		var slots: Dictionary = touched.get(chassis.assembly_id, {})
		slots[slot] = true
		touched[chassis.assembly_id] = slots

	var assembly_ids: Array = touched.keys()
	assembly_ids.sort()
	for aid: int in assembly_ids:
		var runtime := registry.get_runtime(aid)
		if runtime == null:
			continue
		var slots: Array = (touched[aid] as Dictionary).keys()
		slots.sort()
		for slot: int in slots:
			_apply_blast_to_slot(
				runtime, slot, centre, radius_m, damage,
				source_assembly_id, source_slot, chain_depth
			)


## Submits an IMPACT packet for a contact, rate limited per part. §6.
##
## Returns the outcome so a caller can tell a swallowed contact from a resolved
## one; the rate limiter rejects rather than negating, because a scrape that is
## being ignored is not a hit the player should see a marker for.
func submit_impact(
	assembly_id: int,
	slot: int,
	damage: float,
	point_world: Vector3,
	normal_world: Vector3,
	source_assembly_id: int
) -> DamageOutcome:
	var key := assembly_id * (SyndicateConstants.INVALID_SLOT + 1) + slot
	var now := MatchClock.time_s
	if now - float(_last_impact_time.get(key, -1.0e9)) < IMPACT_COOLDOWN_S:
		return DamageOutcome.rejected("impact cooldown")
	_last_impact_time[key] = now

	var packet := DamagePacket.new()
	packet.target_assembly_id = assembly_id
	packet.target_slot = slot
	packet.channel = PartEnums.DamageChannel.IMPACT
	packet.raw_amount = damage
	packet.impact_point_world = point_world
	packet.impact_normal_world = normal_world
	packet.incoming_direction = -normal_world
	packet.source_assembly_id = source_assembly_id
	packet.source_tick = MatchClock.tick
	return apply(packet)


## Damage from a collision impulse, in integrity points. §6.1.
##
## [param impulse_ns] is the normal impulse exchanged at the contact and the two
## masses are the colliding bodies'; a static body passes a very large mass,
## which drives the reduced mass to the moving body's own.
static func impact_damage(impulse_ns: float, mass_a_kg: float, mass_b_kg: float) -> float:
	var m_rel := (mass_a_kg * mass_b_kg) / maxf(mass_a_kg + mass_b_kg, SyndicateConstants.EPSILON_LINEAR)
	var v_eff := absf(impulse_ns) / maxf(m_rel, 0.001)
	if v_eff <= IMPACT_THRESHOLD_MPS:
		return 0.0
	return minf(IMPACT_K * pow(v_eff - IMPACT_THRESHOLD_MPS, IMPACT_EXPONENT), IMPACT_MAX_PER_CONTACT)


## §4.3's penetration curve: the fraction of raw damage a round of [param pen]
## delivers through [param armour] struck at [param cos_theta].
##
## The quadratic ramp in the partial band is deliberate game feel. It makes the
## region just under the threshold sharply unrewarding, so "my gun works against
## this" and "it doesn't" is legible to a player rather than a gentle gradient.
static func kinetic_multiplier(pen: float, armour: float, cos_theta: float) -> float:
	var a_eff := effective_armour(armour, cos_theta)
	var rho := pen / maxf(a_eff, 0.01)
	if rho < PEN_DEFEAT:
		return 0.0
	if rho < 1.0:
		var t := (rho - PEN_DEFEAT) / (1.0 - PEN_DEFEAT)
		return PEN_PARTIAL_SCALE * t * t
	return 1.0 + PEN_SURPLUS_GAIN * minf(rho - 1.0, PEN_SURPLUS_CAP)


## Armour rating as seen along the incoming direction. §4.1.
static func effective_armour(armour: float, cos_theta: float) -> float:
	return armour / maxf(cos_theta, COS_FLOOR)


## True when a hit deflects entirely rather than resolving. §4.2.
static func is_ricochet(pen: float, armour: float, cos_theta: float) -> bool:
	if cos_theta >= RICOCHET_COS:
		return false
	return pen < effective_armour(armour, cos_theta) * RICOCHET_PEN_FACTOR


## True when the round passes through and continues. §4.4.
static func is_overpenetration(pen: float, armour: float, cos_theta: float) -> bool:
	return pen / maxf(effective_armour(armour, cos_theta), 0.01) >= OVERPEN_RATIO


## Blast falloff at [param distance_m] from a blast of [param radius_m]. §5.1.
static func blast_falloff(distance_m: float, radius_m: float) -> float:
	if radius_m <= 0.0:
		return 0.0
	return pow(1.0 - clampf(distance_m / radius_m, 0.0, 1.0), BLAST_EXPONENT)


## The band a part is in at [param fraction] of its maximum integrity. §8.1.
static func band_for(fraction: float) -> PartEnums.IntegrityBand:
	if fraction <= 0.0:
		return PartEnums.IntegrityBand.DESTROYED
	if fraction < SyndicateConstants.BAND_CRITICAL:
		return PartEnums.IntegrityBand.CRITICAL
	if fraction < SyndicateConstants.BAND_IMPAIRED:
		return PartEnums.IntegrityBand.IMPAIRED
	if fraction < SyndicateConstants.BAND_STRESSED:
		return PartEnums.IntegrityBand.STRESSED
	return PartEnums.IntegrityBand.NOMINAL


## Detonations awaiting the end of the tick. Diagnostics and tests.
func pending_detonations() -> int:
	return _detonations.size()


## ===== PRIVATE =========================================================


## Integrity to remove, after resistance, armour, angle, and the band's armour
## multiplier. §3.1's `_compute_effective`.
func _compute_effective(packet: DamagePacket, st: PartInstanceState, def: PartDefinition) -> float:
	var resisted := packet.raw_amount * (
		1.0 - st.effective_resistance(def, int(packet.channel))
	)
	if resisted <= 0.0:
		return 0.0
	# §8.2's last row: armour degrades with integrity on every class, so the
	# first hits are absorbed and later ones go through. Read from the cached
	# band rather than recomputed from integrity — Invariant I-5.
	var armour := def.armour_rating * DegradationTable.ARMOUR_RATING[int(st.integrity_band)]

	match packet.channel:
		PartEnums.DamageChannel.KINETIC:
			var cos_theta := packet.cos_incidence()
			if is_ricochet(packet.penetration, armour, cos_theta):
				return resisted * RICOCHET_DAMAGE_FRACTION
			return resisted * kinetic_multiplier(packet.penetration, armour, cos_theta)
		PartEnums.DamageChannel.CORROSIVE:
			# §7.2: corrosive bypasses a flat fraction of armour outright rather
			# than being compared against it, which is what makes it the answer
			# to a build that has simply bolted on more plate.
			return resisted * (1.0 - (1.0 - CORROSIVE_ARMOUR_BYPASS) * _armour_absorption(armour))
		_:
			return resisted * (1.0 - _armour_absorption(armour))


## The fraction of a non-kinetic packet armour soaks, in [code][0, 1)[/code].
##
## Blast, impact and thermal have no penetration figure to compare against, so
## armour acts as diminishing absorption rather than as a threshold. The
## half-absorption point is one armour rating; the curve never reaches 1.0, which
## is what stops a heavily armoured part being immune to fire.
func _armour_absorption(armour: float) -> float:
	if armour <= 0.0:
		return 0.0
	return armour / (armour + ARMOUR_HALF_ABSORPTION)


func _accumulate_heat(st: PartInstanceState, def: PartDefinition, packet: DamagePacket) -> void:
	st.accumulated_heat_hu += packet.raw_amount * THERMAL_HEAT_RATIO * maxf(packet.interval_s, 1.0)
	if st.accumulated_heat_hu >= THERMAL_IGNITION_HU:
		st.flags |= PartFlags.FLAG_OVERHEATED
	elif st.accumulated_heat_hu < THERMAL_EXTINCTION_HU:
		st.flags &= ~PartFlags.FLAG_OVERHEATED
	# Between the two thresholds the flag keeps whatever it had, which is the
	# hysteresis: a part hovering on the ignition point does not flicker.
	if def.part_class == PartEnums.PartClass.PRIME_MOVER and def.prime_mover_profile != null:
		if st.accumulated_heat_hu >= def.prime_mover_profile.thermal_shutdown_hu:
			st.flags |= PartFlags.FLAG_OVERHEATED


## §8.4. Returns true when the transition destroyed the part.
func _on_band_transition(
	runtime: AssemblyRuntime,
	st: PartInstanceState,
	def: PartDefinition,
	before: PartEnums.IntegrityBand,
	after: PartEnums.IntegrityBand,
	packet: DamagePacket
) -> bool:
	st.flags |= PartFlags.FLAG_VISUAL_DIRTY | PartFlags.FLAG_NET_DIRTY
	EventBus.part_band_changed.emit(runtime.assembly_id, st.slot, int(before), int(after))
	if after == PartEnums.IntegrityBand.DESTROYED:
		_destroy_part(runtime, st, def, packet)
		return true
	return false


## §8.5.
func _destroy_part(
	runtime: AssemblyRuntime, st: PartInstanceState, def: PartDefinition, packet: DamagePacket
) -> void:
	st.flags |= PartFlags.FLAG_DESTROYED
	st.integrity = 0.0

	if def.part_class == PartEnums.PartClass.PRIME_MOVER and def.prime_mover_profile != null:
		var mover := def.prime_mover_profile
		_queue_detonation(
			runtime, st, mover.detonation_blast_radius_m, mover.detonation_blast_damage,
			packet.chain_depth + 1
		)
	elif def.part_class == PartEnums.PartClass.ENERGY_CELL and def.energy_cell_profile != null:
		# A cell is a tank of energy with nowhere to go, and §7.7 gives it the
		# harder failure of the two for exactly that reason.
		var cell := def.energy_cell_profile
		_queue_detonation(
			runtime, st, cell.detonation_blast_radius_m, cell.detonation_blast_damage,
			packet.chain_depth + 1
		)

	EventBus.part_destroyed.emit(runtime.assembly_id, st.slot, int(packet.channel))

	# Architectural Invariant I-2: the Core Module is the root and losing it ends
	# the Assembly. `DEPENDENCY_TREE_GRAPH.md` §8.2 puts the announcement here and
	# nowhere else — "only the damage layer knows who fired the packet that
	# reached zero; the graph sees a `part_destroyed` carrying a damage channel,
	# not an attacker" — and until this existed every consumer of the match-level
	# event had to read the raw signal and re-derive I-2 for itself.
	#
	# `killer_id` is the packet's source Assembly, which §8.2 allows to be 0 for
	# an unattributed termination: a blast queued by a detonation two chain steps
	# back carries the Assembly that started the chain, and a part that died to
	# something with no author carries nothing.
	if st.slot == SyndicateConstants.CORE_SLOT:
		EventBus.assembly_terminated.emit(runtime.assembly_id, packet.source_assembly_id)


func _queue_detonation(
	runtime: AssemblyRuntime, st: PartInstanceState, radius_m: float, damage: float, depth: int
) -> void:
	if depth > MAX_CHAIN_DEPTH:
		return
	_detonations.push_back({
		"centre": runtime.part_world_position(st.slot),
		"radius": radius_m,
		"damage": damage,
		"assembly": runtime.assembly_id,
		"slot": st.slot,
		"depth": depth,
	})


## Drains the detonation queue at [constant EventBusService.PRIORITY_DAMAGE], so
## every blast has landed before detachment runs.
func _flush_detonations() -> void:
	while not _detonations.is_empty():
		var d: Dictionary = _detonations.pop_front()
		resolve_blast(
			d["centre"], d["radius"], d["damage"], d["assembly"], d["slot"], d["depth"]
		)


func _apply_blast_to_slot(
	runtime: AssemblyRuntime,
	slot: int,
	centre: Vector3,
	radius_m: float,
	damage: float,
	source_assembly_id: int,
	source_slot: int,
	chain_depth: int
) -> void:
	var part_pos := runtime.part_world_position(slot)
	var falloff := blast_falloff(part_pos.distance_to(centre), radius_m)
	if falloff <= 0.0:
		return
	var occlusion := _occlusion_between(runtime, centre, slot)
	var packet := DamagePacket.new()
	packet.target_assembly_id = runtime.assembly_id
	packet.target_slot = slot
	packet.channel = PartEnums.DamageChannel.BLAST
	packet.raw_amount = damage * falloff * (1.0 - occlusion)
	packet.impact_point_world = centre
	packet.impact_normal_world = (part_pos - centre).normalized()
	packet.incoming_direction = (part_pos - centre).normalized()
	packet.source_assembly_id = source_assembly_id
	packet.source_slot = source_slot
	packet.source_tick = MatchClock.tick
	packet.chain_depth = chain_depth
	apply(packet)


## §5.2. Attenuation accumulated along the line from the blast centre to the
## part, from the parts it passes through.
##
## Walked over the Assembly's live parts rather than over lattice cells: the
## occupancy array belongs to the [BuildContext] the Assembly was adopted from
## and does not survive into the match, and a part-level walk gives the same
## answer at the resolution that matters — what is being asked is "how much metal
## is in the way", and a part is the unit metal comes in.
func _occlusion_between(runtime: AssemblyRuntime, centre: Vector3, target_slot: int) -> float:
	var target := runtime.part_world_position(target_slot)
	var segment := target - centre
	var length := segment.length()
	if length < SyndicateConstants.EPSILON_LINEAR:
		return 0.0
	var dir := segment / length
	var blockers := 0
	for slot: int in runtime.graph.alive.size():
		if slot == target_slot or runtime.graph.alive[slot] == 0:
			continue
		var st: PartInstanceState = runtime.states[slot]
		if st == null or st.is_inactive():
			continue
		var to_part := runtime.part_world_position(slot) - centre
		var along := to_part.dot(dir)
		if along <= 0.0 or along >= length:
			continue
		if (to_part - dir * along).length() > SyndicateConstants.LATTICE_UNIT_M:
			continue
		blockers += 1
	return minf(float(blockers) * OCCLUSION_PER_CELL, OCCLUSION_MAX)


## §4.4. A round that overpenetrates sprays the parts behind the one it went
## through.
##
## Spall is what makes interior layout meaningful: a Prime Mover tucked directly
## behind thin frontal armour takes damage from hits that never reach it.
func _generate_spall(
	packet: DamagePacket,
	effective: float,
	runtime: AssemblyRuntime,
	st: PartInstanceState,
	def: PartDefinition
) -> void:
	if packet.chain_depth >= MAX_CHAIN_DEPTH or packet.has_flag(PacketFlags.PACKET_SPALL):
		return
	var armour := def.armour_rating * DegradationTable.ARMOUR_RATING[int(st.integrity_band)]
	if not is_overpenetration(packet.penetration, armour, packet.cos_incidence()):
		return
	var behind := _slots_behind(runtime, packet, st.slot)
	if behind.is_empty():
		return
	var share := effective * SPALL_FRACTION / float(behind.size())
	for slot: int in behind:
		var p := DamagePacket.new()
		p.target_assembly_id = packet.target_assembly_id
		p.target_slot = slot
		p.channel = PartEnums.DamageChannel.BLAST
		p.raw_amount = share
		p.impact_point_world = packet.impact_point_world
		p.impact_normal_world = -packet.incoming_direction
		p.incoming_direction = packet.incoming_direction
		p.source_assembly_id = packet.source_assembly_id
		p.source_slot = packet.source_slot
		p.source_tick = packet.source_tick
		p.chain_depth = packet.chain_depth + 1
		p.flags = packet.flags | PacketFlags.PACKET_SPALL | PacketFlags.PACKET_OVERPEN
		apply(p)


## Live slots inside the spall cone behind [param struck_slot], ascending and
## capped at [constant SPALL_MAX_SLOTS].
##
## Ascending order is Invariant I-9: spall can destroy several parts at once and
## the order they die in is replicated.
func _slots_behind(
	runtime: AssemblyRuntime, packet: DamagePacket, struck_slot: int
) -> PackedInt32Array:
	var out := PackedInt32Array()
	if packet.incoming_direction.is_zero_approx():
		return out
	var dir := packet.incoming_direction.normalized()
	var cone_cos := cos(deg_to_rad(SPALL_CONE_DEG))
	for slot: int in runtime.graph.alive.size():
		if slot == struck_slot or runtime.graph.alive[slot] == 0:
			continue
		if out.size() >= SPALL_MAX_SLOTS:
			break
		var candidate: PartInstanceState = runtime.states[slot]
		if candidate == null or candidate.is_inactive():
			continue
		var offset := runtime.part_world_position(slot) - packet.impact_point_world
		var distance := offset.length()
		if distance < SyndicateConstants.EPSILON_LINEAR or distance > SPALL_RANGE_M:
			continue
		if offset.dot(dir) / distance < cone_cos:
			continue
		out.append(slot)
	return out
