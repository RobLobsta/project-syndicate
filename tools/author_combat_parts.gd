extends SceneTree
## Authoring script for the parts and projectiles that give the combat layer a
## real user.
##
## [codeblock]
## godot --headless --path . --script tools/author_combat_parts.gd
## [/codeblock]
##
## Two things ship here: `eff.ballistic.autocannon_30.t3`, quoted from document
## 01 §10.5, and the round it fires. Until now the only Effector Module in the
## registry was a melee edge, so the ballistic path — hardpoint slew, the fire
## gate, emission, spread, recoil, the swept ray, and the whole of document 08 —
## had no authored user at all and could only be exercised against synthetic
## definitions.
##
## Re-running rewrites the same bytes; see the caveat about `[sub_resource]` ids
## in the handoff before concluding a re-run changed anything.

const FACE_YN: Vector3i = Vector3i(0, -1, 0)

const PROJECTILES_DIR: String = "res://data/projectiles"

var _done: bool = false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(0 if _run() else 1)
	return true


func _run() -> bool:
	if not _author_projectiles():
		return false
	var keys := PackedStringArray()
	keys.append(_author_autocannon_30())
	for key: String in keys:
		if key.is_empty():
			return false
	return PartAuthoring.append_to_manifest(keys)


## §10.5's `eff.ballistic.autocannon_30.t3` row, in full: `BALLISTIC_DIRECT`,
## 5x4x9 cells, 196 kg, 480 integrity, 68 PU, 0.14 s cycle, 940 m/s muzzle,
## 1450 N·s recoil, 7.5 HU per shot. §11's `eff.ballistic.*` resistance row.
##
## The fields §10.5 leaves open — armour, load capacity, magazine, spread — are
## chosen here and commented where they are chosen. A rapid-fire module carries
## light armour by design: it is the part a build puts forward, and it should be
## the part a build loses.
func _author_autocannon_30() -> String:
	# Nine cells along -Z, which is the barrel. §7.2 fixes -Z as the direction a
	# round leaves along and `eff.melee.beam_edge` already puts its blade there,
	# so an edge and a barrel agree on which way forward is.
	var lo := Vector3i(-2, 0, -8)
	var hi := Vector3i(2, 3, 0)
	var def := _base(&"eff.ballistic.autocannon_30.t3", PartEnums.PartClass.EFFECTOR_MODULE)
	def.tier = PartEnums.TierGrade.REFINED
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	# Mounts downward onto a deck, like the beam edge. A turret that had to bolt
	# on through its own barrel face would be unmountable, which is exactly the
	# §4.2 shape of defect the locomotion set was fixed for.
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo, hi, {FACE_YN: PartEnums.AttachmentPolarity.FACE_MALE}
	)
	def.mass_kg = 196.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 480.0
	# §11's `eff.ballistic.*` row: kinetic, blast, impact, thermal, corrosive.
	def.resistance = PackedFloat32Array([0.12, 0.10, 0.18, 0.14, 0.06])
	# Deliberately thin. §8.2's last row degrades armour with integrity on every
	# class, so a module this lightly protected escalates quickly once it starts
	# taking hits — which is the trade for putting the gun at the front.
	def.armour_rating = 16.0
	def.load_capacity_kg = 180.0
	def.power_draw_pu = 68.0
	def.heat_generation_hu_s = 7.5

	var effector := EffectorModuleProfile.new()
	effector.kind = PartEnums.EffectorKind.BALLISTIC_DIRECT
	# Full traverse. §3.1's limit frame is the part's own rest orientation, and
	# AimSolver.clamp_yaw leaves a 360-degree mount unclamped rather than seaming
	# it at whichever angle the limits happen to start.
	effector.yaw_limit_deg = Vector2(-180.0, 180.0)
	effector.pitch_limit_deg = Vector2(-8.0, 34.0)
	effector.yaw_rate_deg_s = 65.0
	effector.pitch_rate_deg_s = 48.0
	# One barrel, at the muzzle end of the nine-cell occupancy. Half a cell past
	# the last occupied cell, so a round is born outside the part's own collider
	# and §12.3's self-immunity window is belt and braces rather than the only
	# thing keeping a build from shooting itself.
	effector.muzzle_offsets_m = PackedVector3Array([
		Vector3(0.0, 0.0, (float(lo.z) - 0.5) * SyndicateConstants.LATTICE_UNIT_M)
	])
	effector.projectile_key = &"proj.kinetic.ap_30"
	effector.muzzle_velocity_mps = 940.0
	effector.cycle_time_s = 0.14
	effector.burst_count = 0
	effector.burst_recovery_s = 0.0
	# No magazine model. §10.5 leaves it open and the ledger already holds the
	# Assembly's rounds; a per-module magazine on top would be two owners of one
	# quantity, and the second one is the one that has no consumer yet.
	effector.magazine_rounds = 0
	effector.reload_time_s = 0.0
	effector.spread_base_deg = 0.25
	effector.spread_bloom_deg = 0.09
	effector.spread_decay_deg_s = 0.55
	effector.recoil_impulse_ns = 1450.0
	effector.heat_per_shot_hu = 7.5
	effector.jam_clear_time_s = 1.6
	effector.melee_profile = null
	def.effector_profile = effector

	# §10.5 leaves both open. A turret is expensive and takes one mount, which is
	# what makes carrying two of them a real decision against the Core Module's
	# budget of 28 rather than an obvious one.
	def.build_cost = 760
	def.mount_weight = 3

	var collider := PartAuthoring.single_box_collider(lo, hi)
	return PartAuthoring.save_part(def, "eff", collider, &"barrel_std")


## The round the autocannon fires. §12's flight fields and §4's damage fields.
##
## Penetration is set against the shipped armour ratings rather than in the
## abstract: `str.panel.medium.t2` rates 14 and `core.command.compact.t2` rates
## more, so 95 defeats a panel struck square (§4.3's ratio is 6.8, which is well
## past full) and is progressively defeated as the angle steepens. That is the
## behaviour §4.1 exists to produce and it is only legible once a real round
## meets a real plate.
func _author_projectiles() -> bool:
	var round_def := ProjectileDefinition.new()
	round_def.projectile_key = &"proj.kinetic.ap_30"
	round_def.channel = PartEnums.DamageChannel.KINETIC
	round_def.damage = 120.0
	round_def.penetration = 95.0
	round_def.blast_radius_m = 0.0
	# Four seconds at 940 m/s is 3.7 km, which is far past any arena. The life is
	# a bound on the pool, not a range limit.
	round_def.life_s = 4.0
	round_def.gravity_scale = 1.0
	# A fifth of a percent of speed lost per metre at muzzle velocity, which is
	# about 90 m/s over the first hundred metres.
	round_def.drag_coefficient_per_m = 0.00002
	round_def.penetrates_after_hit = true

	if DirAccess.make_dir_recursive_absolute(PROJECTILES_DIR) != OK:
		printerr("author_combat_parts: cannot create %s" % PROJECTILES_DIR)
		return false
	var path := "%s/%s.tres" % [PROJECTILES_DIR, round_def.projectile_key]
	if not PartAuthoring.save(round_def, path):
		return false
	print("author_combat_parts: wrote %s" % round_def.projectile_key)
	return true


func _base(key: StringName, part_class: PartEnums.PartClass) -> PartDefinition:
	var def := PartDefinition.new()
	def.part_key = key
	def.display_name_key = StringName("part.%s.name" % key)
	def.description_key = StringName("part.%s.desc" % key)
	def.part_class = part_class
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID
	def.inertia_box_half_extents_m = Vector3.ZERO
	return def
