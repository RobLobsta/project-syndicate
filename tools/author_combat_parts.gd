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
	keys.append(_author_repeater_12())
	for key: String in keys:
		if key.is_empty():
			return false
	return PartAuthoring.append_to_manifest(keys)


## §10.5's `eff.ballistic.autocannon_30.t3` row, in full: `BALLISTIC_DIRECT`,
## 4x3x7 cells, 420 kg, 480 integrity, 68 PU, 0.14 s cycle, 940 m/s muzzle,
## 1450 N·s recoil, 7.5 HU per shot. §11's `eff.ballistic.*` resistance row.
##
## The fields §10.5 leaves open — armour, load capacity, magazine, spread — are
## chosen here and commented where they are chosen. A rapid-fire module carries
## light armour by design: it is the part a build puts forward, and it should be
## the part a build loses.
func _author_autocannon_30() -> String:
	# Seven cells along -Z, which is the barrel. §7.2 fixes -Z as the direction a
	# round leaves along and `eff.melee.beam_edge` already puts its blade there,
	# so an edge and a barrel agree on which way forward is.
	#
	# Four cells wide, and the width is §14 rule 25 rather than a styling choice.
	# A Core Module is even-width, so its centreline falls on a cell boundary; an
	# odd-width module's own centreline falls on a cell centre, and the two can
	# never coincide. This module was authored five wide and its bore therefore
	# sat half a cell off the hull's centreline, which at 1450 N·s every 0.14 s is
	# about a kilonewton-metre of steady yaw — more than the wheeled family's
	# entire steering authority, and the reason no Assembly could drive and shoot
	# at the same time. The other three `BALLISTIC_DIRECT` rows of §10.5 were
	# even-width already; this one was the outlier.
	var lo := Vector3i(-2, 0, -6)
	var hi := Vector3i(1, 2, 0)
	var def := _base(&"eff.ballistic.autocannon_30.t3", PartEnums.PartClass.EFFECTOR_MODULE)
	def.tier = PartEnums.TierGrade.REFINED
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	# Mounts downward onto a deck, like the beam edge. A turret that had to bolt
	# on through its own barrel face would be unmountable, which is exactly the
	# §4.2 shape of defect the locomotion set was fixed for.
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo, hi, {FACE_YN: PartEnums.AttachmentPolarity.FACE_MALE}
	)
	def.mass_kg = 420.0
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
	# One barrel, at the muzzle end of the seven-cell occupancy. Half a cell past
	# the last occupied cell, so a round is born outside the part's own collider
	# and §12.3's self-immunity window is belt and braces rather than the only
	# thing keeping a build from shooting itself.
	#
	# Laterally the bore sits on the footprint's own centre, which for an
	# even-width part is a quarter-cell off the pivot cell rather than on it. §14
	# rule 25 requires exactly this equality, and it is not cosmetic: the recoil
	# impulse is applied at the muzzle (doc 07 §8), so the bore's lateral distance
	# from the centre of mass is the moment arm of every round fired.
	var bore := PartAuthoring.box_centre_m(lo, hi)
	effector.muzzle_offsets_m = PackedVector3Array([
		Vector3(bore.x, 0.0, (float(lo.z) - 0.5) * SyndicateConstants.LATTICE_UNIT_M)
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


## §10.5's `eff.ballistic.repeater_12.t2` row: `BALLISTIC_DIRECT`, 4x2x5 cells,
## 150 kg, 260 integrity, 26 PU, 0.075 s cycle, 860 m/s muzzle, 26 N·s recoil,
## 1.9 HU per shot. §11's `eff.ballistic.*` resistance row, same as the
## autocannon.
##
## [b]The row exists to make a build able to drive and shoot at the same time.[/b]
## Doc 07 §8 applies the recoil at the muzzle, so a traversed mount's yaw is the
## per-round impulse times a lever the mount's placement fixes; rule 27 and the
## build's geometry own the lever and this row owns the impulse. At 26 N·s every
## 0.075 s the sustained torque through the reference build's 2.25 m traversed
## lever is 780 N·m, against 23 300 for the `autocannon_30` — and 780 N·m is
## inside what four contacts can hold. `tests/physics/test_drive_and_shoot.gd`
## measures it rather than trusting this comment.
##
## The trade is penetration, not a uniform taper. See `_author_projectiles`.
func _author_repeater_12() -> String:
	# Five cells along -Z rather than the autocannon's seven: a shorter barrel, and
	# a mount that reaches half a metre less past the hull it is bolted to. Four
	# wide for §14 rule 27's parity, which is not a styling choice — an odd-width
	# BALLISTIC_DIRECT module cannot be centred on an even-width Core Module at
	# any placement, and its bore's half-cell offset is a moment arm on every
	# round.
	var lo := Vector3i(-2, 0, -4)
	var hi := Vector3i(1, 1, 0)
	var def := _base(&"eff.ballistic.repeater_12.t2", PartEnums.PartClass.EFFECTOR_MODULE)
	def.tier = PartEnums.TierGrade.STANDARD
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo, hi, {FACE_YN: PartEnums.AttachmentPolarity.FACE_MALE}
	)
	def.mass_kg = 150.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 260.0
	def.resistance = PackedFloat32Array([0.12, 0.10, 0.18, 0.14, 0.06])
	# Thinner than the autocannon's 16 and for the same reason one step further:
	# this is the cheap module a build puts forward, and §8.2's last row degrades
	# armour with integrity, so it escalates fast once it starts taking hits.
	def.armour_rating = 12.0
	def.load_capacity_kg = 120.0
	def.power_draw_pu = 26.0
	def.heat_generation_hu_s = 3.0

	var effector := EffectorModuleProfile.new()
	effector.kind = PartEnums.EffectorKind.BALLISTIC_DIRECT
	effector.yaw_limit_deg = Vector2(-180.0, 180.0)
	effector.pitch_limit_deg = Vector2(-8.0, 34.0)
	# Faster on both axes than the autocannon's 65 and 48. A light mount slews
	# quickly, and a module meant to be fired while moving has to be able to hold
	# a bearing the hull is changing under it.
	effector.yaw_rate_deg_s = 95.0
	effector.pitch_rate_deg_s = 70.0
	# One barrel on the footprint's own lateral centre, half a cell past the last
	# occupied cell. Rule 27, and the same reasoning as the autocannon's bore.
	var bore := PartAuthoring.box_centre_m(lo, hi)
	effector.muzzle_offsets_m = PackedVector3Array([
		Vector3(bore.x, 0.0, (float(lo.z) - 0.5) * SyndicateConstants.LATTICE_UNIT_M)
	])
	effector.projectile_key = &"proj.kinetic.ap_12"
	effector.muzzle_velocity_mps = 860.0
	effector.cycle_time_s = 0.075
	effector.burst_count = 0
	effector.burst_recovery_s = 0.0
	effector.magazine_rounds = 0
	effector.reload_time_s = 0.0
	# Twice the autocannon's resting spread and a third of its bloom, decaying
	# slower than it blooms at this cadence: held down, the group opens from 0.55
	# degrees to the 1.75 the ceiling allows over about three seconds, which is a
	# metre and a quarter of dispersion at forty metres. That is the second trade
	# after penetration — sustained fire from this module is suppression, and
	# tapping it is aimed fire.
	effector.spread_base_deg = 0.55
	effector.spread_bloom_deg = 0.10
	effector.spread_decay_deg_s = 0.90
	effector.recoil_impulse_ns = 26.0
	# 1.9 HU a shot against 22 HU/s of dissipation and a ceiling of 14 shots'
	# worth: at 13.3 rounds a second the module gains 3.3 HU/s net and stops
	# after about eight seconds of continuous fire. Long enough to be a machine
	# rather than a burst weapon, bounded enough that holding the trigger down
	# for a whole engagement is not free.
	effector.heat_per_shot_hu = 1.9
	effector.jam_clear_time_s = 1.1
	effector.melee_profile = null
	def.effector_profile = effector

	# Well under half the autocannon's 760, and two mount weights against three,
	# so a Core Module's budget of 28 can carry a pair of these where it could
	# not carry a pair of those.
	def.build_cost = 340
	def.mount_weight = 2

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

	# The repeater's round, and the whole of what it gives up for being drivable.
	#
	# 46 penetration against the autocannon's 95, read against the shipped armour
	# ratings rather than chosen in the abstract. §4.3's ratio against
	# `str.panel.medium.t2` at 14 is 3.3, so it overpenetrates structure freely;
	# against `core.command.compact.t2` at 18 it is 2.6 square on and drops under
	# §4.4's 1.85 overpenetration ratio at about 40 degrees of obliquity. So this
	# round works through a hull's outside and stops at what it is protecting,
	# where `ap_30` at 95 goes the whole way through — which is the difference
	# between the two modules and is meant to be visible in a fight rather than
	# only in a table.
	#
	# 46 damage at a 0.075 s cycle is 613 a second against `ap_30`'s 857, so the
	# lighter module is not simply worse: it trades a third of its throughput and
	# half its penetration for thirty times less recoil.
	var light := ProjectileDefinition.new()
	light.projectile_key = &"proj.kinetic.ap_12"
	light.channel = PartEnums.DamageChannel.KINETIC
	light.damage = 46.0
	light.penetration = 46.0
	light.blast_radius_m = 0.0
	# Three seconds at 860 m/s is 2.5 km, past any arena. A bound on the pool.
	light.life_s = 3.0
	light.gravity_scale = 1.0
	# Lighter for its calibre than the 30 mm, so it sheds speed faster: a little
	# over half a percent of speed per hundred metres more than `ap_30`.
	light.drag_coefficient_per_m = 0.000035
	light.penetrates_after_hit = true

	if DirAccess.make_dir_recursive_absolute(PROJECTILES_DIR) != OK:
		printerr("author_combat_parts: cannot create %s" % PROJECTILES_DIR)
		return false
	for r: ProjectileDefinition in [round_def, light] as Array[ProjectileDefinition]:
		var path := "%s/%s.tres" % [PROJECTILES_DIR, r.projectile_key]
		if not PartAuthoring.save(r, path):
			return false
		print("author_combat_parts: wrote %s" % r.projectile_key)
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
