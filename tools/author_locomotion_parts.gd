extends SceneTree
## Authoring script for the seven parts that give the motion layer real users.
##
## [codeblock]
## godot --headless --path . --script tools/author_locomotion_parts.gd
## [/codeblock]
##
## Every number here is quoted from the tables in document 01. Where §10 leaves a
## field open — build costs, motive armour and load capacity — the choice is
## commented where it is made rather than left to look like a quotation.
##
## The set is deliberately one part per thing the motion layer needs to be
## exercised by something real: an AXLE station to resolve §4.2, one Motive
## Assembly of each of the four locomotion families, a Prime Mover so drive
## torque has a source, and a powered edge so melee has one. Together they take
## the shipping registry from two definitions to nine.
##
## Re-running rewrites the same bytes. Committed rather than discarded so the
## derivation of the data is reviewable next to the data itself.

const FACE_XP: Vector3i = Vector3i(1, 0, 0)
const FACE_XN: Vector3i = Vector3i(-1, 0, 0)
const FACE_YP: Vector3i = Vector3i(0, 1, 0)
const FACE_YN: Vector3i = Vector3i(0, -1, 0)
const FACE_ZN: Vector3i = Vector3i(0, 0, -1)

var _done: bool = false


## The `accepts_classes` restriction an AXLE [i]station[/i] carries: a drive
## station takes a Motive Assembly and nothing else (§14 rule 18).
##
## A function rather than a `const`, because a `Packed*Array` constructor is not
## a constant expression in GDScript — the same rule that already forbids
## `const X: PackedStringArray = PackedStringArray([...])`.
static func motive_only() -> PackedInt32Array:
	return PackedInt32Array([PartEnums.PartClass.MOTIVE_ASSEMBLY])


## The restriction a Motive Assembly's own drive face carries: §4.2's other half.
##
## The two halves are not the same list and putting the station's list on both
## sides is the defect this function exists to name. `_check_mating` tests
## `accepts_class` in [i]both[/i] directions, so a drive face keyed to
## MOTIVE_ASSEMBLY rejects the very station §4.2 requires it to mate with — and
## the part is then unmountable on anything, which is exactly what four of the
## nine shipped parts were until the first placement test tried it.
static func structural_only() -> PackedInt32Array:
	return PackedInt32Array([PartEnums.PartClass.STRUCTURAL_COMPONENT])


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(0 if _run() else 1)
	return true


func _run() -> bool:
	var keys := PackedStringArray()
	keys.append(_author_hub_axle_station())
	keys.append(_author_wheeled_allroad())
	keys.append(_author_wheeled_fixed_rear())
	keys.append(_author_tracked_short_bogie())
	keys.append(_author_rotor_coaxial_mid())
	keys.append(_author_limb_strider())
	keys.append(_author_prime_mover_combustion_standard())
	keys.append(_author_energy_cell_static_standard())
	keys.append(_author_melee_beam_edge())
	for key: String in keys:
		if key.is_empty():
			return false
	return PartAuthoring.append_to_manifest(keys)


## §10.2: `str.hub.axle_station.t2`, 2x2x2, 90 kg, 340 integrity, 16 armour,
## 2400 kg load capacity. §11: the `str.hub.*` row.
##
## The AXLE station of §4.2, and the only shipping part carrying AXLE nodes. Its
## +/-X faces are AXLE and restricted to MOTIVE_ASSEMBLY; +/-Y and +/-Z are
## neutral so it builds into a chassis from four sides. The 24-orientation group
## points the drive axis anywhere, which is why one station serves a wheel, a
## track, a rotor mast, and a limb hip without new connector vocabulary.
func _author_hub_axle_station() -> String:
	var lo := Vector3i(-1, 0, -1)
	var hi := Vector3i(0, 1, 0)
	var def := _base(&"str.hub.axle_station.t2", PartEnums.PartClass.STRUCTURAL_COMPONENT)
	def.tier = PartEnums.TierGrade.STANDARD
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo,
		hi,
		{
			FACE_XP: PartEnums.AttachmentPolarity.AXLE,
			FACE_XN: PartEnums.AttachmentPolarity.AXLE,
		},
		{FACE_XP: motive_only(), FACE_XN: motive_only()}
	)
	def.mass_kg = 90.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 340.0
	def.resistance = PackedFloat32Array([0.26, 0.10, 0.44, 0.10, 0.06])
	def.armour_rating = 16.0
	# High for its mass because everything an Assembly's locomotion does to it
	# passes through this one joint: a 1180 kg-rated Motive Assembly under a
	# 2.4 g manoeuvre loads its station harder than any panel ever sees.
	def.load_capacity_kg = 2400.0
	# Tier-2 baseline for `str.hub.axle_station`; §12 scales other tiers from it.
	def.build_cost = 140
	def.mount_weight = 1
	return PartAuthoring.save_part(
		def, "str", PartAuthoring.single_box_collider(lo, hi), &"plate_std"
	)


## §10.3: `mot.wheeled.allroad.t2`, WHEELED_STEERED, 4x4x2, 110 kg, 340 integrity,
## 1100 kg rated, 1.05 traction, 32 degree steer, 134000 N/m, 10900 Ns/m.
## §11: the `mot.wheeled.*` row.
##
## Authored as a disc rather than a box. §7.1 of document 05 fixes the contact
## frame as x = rolling, y = normal, z = lateral, so the disc lies in XY and the
## 2-cell depth is the spin axis — which is why the AXLE face is -Z.
func _author_wheeled_allroad() -> String:
	var lo := Vector3i(-2, -2, -1)
	var hi := Vector3i(1, 1, 0)
	var cells := PartAuthoring.disc_cells(lo, hi)
	var def := _base(&"mot.wheeled.allroad.t2", PartEnums.PartClass.MOTIVE_ASSEMBLY)
	def.tier = PartEnums.TierGrade.STANDARD
	def.occupancy_cells = cells
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo,
		hi,
		{FACE_ZN: PartEnums.AttachmentPolarity.AXLE},
		{FACE_ZN: structural_only()},
		cells
	)
	def.mass_kg = 110.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 340.0
	def.resistance = PackedFloat32Array([0.08, 0.12, 0.30, 0.02, 0.00])
	# §10.3 publishes no armour or load capacity for Motive Assemblies. A wheel
	# is not structure and nothing should be built off it, so the load capacity
	# is set to little more than its own mass.
	def.armour_rating = 10.0
	def.load_capacity_kg = 200.0

	var profile := MotiveAssemblyProfile.new()
	profile.kind = PartEnums.MotiveKind.WHEELED_STEERED
	# Derived from the cell dimensions: four cells across is 1.0 m, two deep is
	# 0.5 m. Deriving rather than quoting the schema default keeps the collider,
	# the rolling radius, and the occupancy describing one object.
	profile.contact_radius_m = 0.50
	profile.contact_width_m = 0.50
	# Rolling radius plus full travel, per doc 05 §6.1. The probe sweeps from the
	# disc's centre, so a rest length below the radius can never register
	# compression; setting it to radius + travel puts full droop one travel above
	# the ground and makes the disc's own collider the bump stop.
	profile.suspension_rest_length_m = 0.74
	profile.suspension_stiffness_n_m = 134000.0
	profile.suspension_damping_ns_m = 10900.0
	profile.suspension_travel_limit_m = 0.24
	profile.max_steer_angle_deg = 32.0
	profile.steer_rate_deg_s = 140.0
	profile.rated_load_kg = 1100.0
	profile.traction_coefficient = 1.05
	profile.rolling_resistance = 0.014
	profile.brake_torque_nm = 8300.0
	profile.driven = true
	def.motive_profile = profile

	def.build_cost = 220
	def.mount_weight = 2
	return PartAuthoring.save_part(
		def, "mot", PartAuthoring.cylinder_z_collider(lo, hi), &"tread_std"
	)


## §10.3: `mot.wheeled.fixed_rear.t2`, WHEELED_FIXED, 4x4x2, 105 kg, 355
## integrity, 1200 kg rated, 1.09 traction, 0 steer, 140000 N/m, 11200 Ns/m.
##
## The unsteered half of a steering system, and it is not an optimisation. Four
## wheels that all steer the same way do not turn an Assembly — they translate
## it, because every contact patch points the same direction and there is no
## couple about the vertical axis. It crabs sideways down the road with its nose
## still pointing forward, which is exactly what the first steering test measured
## before this part existed. A yaw needs the axles to disagree, so a steering
## build is `WHEELED_STEERED` at the front and `WHEELED_FIXED` at the back, and
## the difference is one authored number rather than a line of code: the steer
## solver reads `max_steer_angle_deg`, and zero falls through it unchanged.
##
## Slightly heavier-duty than the steered row at the same tier — more rated load
## and more grip, less mass — because it carries no steering mechanism. That is
## §10.3's own trade and it makes the rear axle the one to drive.
func _author_wheeled_fixed_rear() -> String:
	var lo := Vector3i(-2, -2, -1)
	var hi := Vector3i(1, 1, 0)
	var cells := PartAuthoring.disc_cells(lo, hi)
	var def := _base(&"mot.wheeled.fixed_rear.t2", PartEnums.PartClass.MOTIVE_ASSEMBLY)
	def.tier = PartEnums.TierGrade.STANDARD
	def.occupancy_cells = cells
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo,
		hi,
		{FACE_ZN: PartEnums.AttachmentPolarity.AXLE},
		{FACE_ZN: structural_only()},
		cells
	)
	def.mass_kg = 105.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 355.0
	def.resistance = PackedFloat32Array([0.08, 0.12, 0.30, 0.02, 0.00])
	def.armour_rating = 10.0
	def.load_capacity_kg = 200.0

	var profile := MotiveAssemblyProfile.new()
	profile.kind = PartEnums.MotiveKind.WHEELED_FIXED
	profile.contact_radius_m = 0.50
	profile.contact_width_m = 0.50
	# §6.1's rule, identical to the steered row: the two share a footprint and a
	# travel, so they share a rest length.
	profile.suspension_rest_length_m = 0.74
	profile.suspension_stiffness_n_m = 140000.0
	profile.suspension_damping_ns_m = 11200.0
	profile.suspension_travel_limit_m = 0.24
	# Zero, and load-bearing: this is the whole difference between the two rows.
	profile.max_steer_angle_deg = 0.0
	profile.steer_rate_deg_s = 0.0
	profile.rated_load_kg = 1200.0
	profile.traction_coefficient = 1.09
	profile.rolling_resistance = 0.014
	profile.brake_torque_nm = 8300.0
	profile.driven = true
	def.motive_profile = profile

	def.build_cost = 205
	def.mount_weight = 2
	return PartAuthoring.save_part(
		def, "mot", PartAuthoring.cylinder_z_collider(lo, hi), &"tread_std"
	)


## §10.3: `mot.tracked.short_bogie.t2`, TRACKED_SEGMENT, 8x4x3, 672 kg,
## 900 integrity, 6700 kg rated, 1.34 traction, 0 steer, 88000 N/m, 7600 Ns/m.
## §7.2.3 and §10.3's tracked parameter table for the rest. §11: `mot.tracked.*`.
##
## The zero steer angle is required by §14 rule 22, not incidental: a track
## steers by differential drive, and one that angled its hub would be a wheel.
func _author_tracked_short_bogie() -> String:
	var lo := Vector3i(-4, -2, -1)
	var hi := Vector3i(3, 1, 1)
	var def := _base(&"mot.tracked.short_bogie.t2", PartEnums.PartClass.MOTIVE_ASSEMBLY)
	def.tier = PartEnums.TierGrade.STANDARD
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo, hi, {FACE_ZN: PartEnums.AttachmentPolarity.AXLE}, {FACE_ZN: structural_only()}
	)
	def.mass_kg = 672.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 900.0
	def.resistance = PackedFloat32Array([0.24, 0.18, 0.40, 0.08, 0.04])
	def.armour_rating = 22.0
	def.load_capacity_kg = 900.0

	var profile := MotiveAssemblyProfile.new()
	profile.kind = PartEnums.MotiveKind.TRACKED_SEGMENT
	profile.contact_radius_m = 0.50
	profile.contact_width_m = 0.75
	# Hub radius plus full travel; §6.1's rule, and the same arithmetic as the
	# wheel because a road station's spring is §6.2 unchanged.
	profile.suspension_rest_length_m = 0.74
	profile.suspension_stiffness_n_m = 88000.0
	profile.suspension_damping_ns_m = 7600.0
	profile.suspension_travel_limit_m = 0.24
	profile.max_steer_angle_deg = 0.0
	profile.steer_rate_deg_s = 0.0
	profile.rated_load_kg = 6700.0
	profile.traction_coefficient = 1.34
	profile.rolling_resistance = 0.021
	profile.brake_torque_nm = 7400.0
	profile.driven = true

	var track := TrackProfile.new()
	# 1.90 m of patch against a 2.00 m part: the patch is the ground contact,
	# not the hull, and the last half-cell at each end is idler rather than run.
	track.patch_length_m = 1.90
	track.road_stations = 4
	# Below 1/4 deliberately, so the ends of the patch are soft and the track
	# conforms to a rise instead of bridging it rigidly.
	track.station_load_share = 0.22
	track.sprocket_rad_s = 22.0
	track.differential_authority = 1.0
	track.pivot_taper_mps = 9.0
	track.slew_resistance_nm_per_n_m = 0.42
	track.lateral_grip_ratio = 1.35
	track.internal_loss = 0.08
	profile.track_profile = track
	def.motive_profile = profile

	def.build_cost = 640
	def.mount_weight = 4
	return PartAuthoring.save_part(
		def, "mot", PartAuthoring.single_box_collider(lo, hi), &"tread_std"
	)


## §10.3: `mot.rotor.coaxial_mid.t3`, ROTOR_DISC, 4x6x4, 848 kg, 690 integrity,
## 8300 kg rated, 150 PU. §10.3's rotary table for the disc parameters.
## §11: the `mot.rotor.*` row.
##
## Thrust at full collective is 81 083 N against a rated 81 395 N — 0.38% apart,
## inside the 1% §14 rule 19 requires. The coefficients are solved from that
## relationship, not chosen: a rotor that cannot lift its own rating presents as
## an Assembly that silently refuses to leave the ground.
##
## The collider is the hub housing. The 2.6 m disc is aerodynamics and carries no
## collision geometry at all, which is Invariant I-1 doing exactly its job.
func _author_rotor_coaxial_mid() -> String:
	var lo := Vector3i(-2, 0, -2)
	var hi := Vector3i(1, 5, 1)
	var def := _base(&"mot.rotor.coaxial_mid.t3", PartEnums.PartClass.MOTIVE_ASSEMBLY)
	def.tier = PartEnums.TierGrade.REFINED
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	# The mast mounts downward onto a station, so the AXLE face is -Y and the
	# disc axis is the part's local +Y that RotorSolver rotates.
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo, hi, {FACE_YN: PartEnums.AttachmentPolarity.AXLE}, {FACE_YN: structural_only()}
	)
	def.mass_kg = 848.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 690.0
	# The lowest resistance row in the schema, and deliberately so: a rotor is
	# the one Motive Assembly that cannot be armoured without destroying the
	# thing it exists to do.
	def.resistance = PackedFloat32Array([0.04, 0.08, 0.06, 0.10, 0.00])
	def.armour_rating = 8.0
	def.load_capacity_kg = 300.0
	# Full-collective shaft draw, so the garage's power budget is conservative:
	# an Assembly that balances on paper can always hover. §12.5.
	def.power_draw_pu = 150.0

	var profile := MotiveAssemblyProfile.new()
	profile.kind = PartEnums.MotiveKind.ROTOR_DISC
	# The hub's radius, not the disc's. §14 rule 19 requires every ground field
	# below to be exactly zero rather than carrying a plausible unread value.
	profile.contact_radius_m = 0.50
	profile.contact_width_m = 0.50
	profile.suspension_rest_length_m = 0.0
	profile.suspension_stiffness_n_m = 0.0
	profile.suspension_damping_ns_m = 0.0
	profile.suspension_travel_limit_m = 0.0
	profile.max_steer_angle_deg = 0.0
	profile.steer_rate_deg_s = 0.0
	profile.rated_load_kg = 8300.0
	profile.traction_coefficient = 0.0
	profile.rolling_resistance = 0.0
	profile.brake_torque_nm = 0.0
	profile.driven = true

	var rotor := RotorProfile.new()
	rotor.disc_radius_m = 2.60
	rotor.blade_count = 4
	rotor.spin_sign = 1
	rotor.nominal_rad_s = 85.0
	rotor.spool_up_tau_s = 2.40
	rotor.spool_down_tau_s = 4.80
	rotor.thrust_coefficient = 0.0638
	rotor.torque_coefficient = 0.0024
	rotor.collective_limit_deg = Vector2(-4.0, 14.0)
	rotor.collective_rate_deg_s = 22.0
	rotor.cyclic_limit_deg = 14.0
	rotor.cyclic_rate_deg_s = 48.0
	rotor.yaw_authority_nm = 9600.0
	# Coaxial: the counter-rotating half cancels the reaction inside the part, so
	# one of these flies on its own. `mot.rotor.main_single.t3` will not.
	rotor.torque_reaction_ratio = 0.0
	rotor.ground_effect_radii = 1.0
	rotor.ground_effect_gain = 0.24
	rotor.translational_lift_mps = 14.0
	rotor.translational_lift_gain = 0.18
	rotor.vortex_ring_descent_mps = 6.0
	rotor.vortex_ring_loss = 0.32
	profile.rotor_profile = rotor
	def.motive_profile = profile

	def.build_cost = 1800
	def.mount_weight = 4
	return PartAuthoring.save_part(
		def, "mot", PartAuthoring.single_box_collider(lo, hi), &"vane_std"
	)


## §10.3: `mot.limb.strider.t4`, AMBULATORY_LIMB, 3x8x3, 592 kg, 720 integrity,
## 4500 kg rated, 1.22 traction, 45 degree turn, 307000 N/m, 38400 Ns/m.
## §10.3's gait table for the rest. §11: the `mot.limb.*` row.
##
## The suspension fields are zero because a limb's compliance is commanded, not
## passive: its spring is [member LimbProfile.stance_stiffness_n_m], which is a
## controller gain. §14 rule 21 requires the distinction.
func _author_limb_strider() -> String:
	# The hip housing and thigh, not the whole extended leg. A limb's reach is
	# `leg_length_m` and its occupancy is the structure that reach hangs from —
	# exactly as `mot.rotor.*` occupies its mast and not its 2.6 m disc, and for
	# the same reason. Doc 05 §13.1 puts the visible articulation under
	# `VisualRoot` as inverse kinematics; Invariant I-1 forbids a collider that
	# follows it. A footprint spanning the fully extended leg therefore bakes a
	# 2.0 m collider around a limb that stands 1.63 m tall, and the Assembly
	# rests on its own shins with the stance spring never compressing at all —
	# measured, before this was shortened, at 0.23 m of unreachable travel.
	var lo := Vector3i(-1, -4, -1)
	var hi := Vector3i(1, 0, 1)
	var def := _base(&"mot.limb.strider.t4", PartEnums.PartClass.MOTIVE_ASSEMBLY)
	def.tier = PartEnums.TierGrade.PROTOTYPE
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	# The pivot is the top cell and the limb hangs below it, so the AXLE face is
	# +Y: a limb mounts under a chassis, where a wheel mounts beside one.
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo, hi, {FACE_YP: PartEnums.AttachmentPolarity.AXLE}, {FACE_YP: structural_only()}
	)
	def.mass_kg = 592.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 720.0
	def.resistance = PackedFloat32Array([0.16, 0.14, 0.26, 0.06, 0.02])
	def.armour_rating = 18.0
	def.load_capacity_kg = 600.0

	var profile := MotiveAssemblyProfile.new()
	profile.kind = PartEnums.MotiveKind.AMBULATORY_LIMB
	# The foot's contact sphere. §7.2 keeps this field's meaning constant across
	# all four families so the ground-clearance check need not know which it has.
	profile.contact_radius_m = 0.16
	profile.contact_width_m = 0.32
	profile.suspension_rest_length_m = 0.0
	profile.suspension_stiffness_n_m = 0.0
	profile.suspension_damping_ns_m = 0.0
	profile.suspension_travel_limit_m = 0.0
	profile.max_steer_angle_deg = 0.0
	profile.steer_rate_deg_s = 0.0
	profile.rated_load_kg = 4500.0
	profile.traction_coefficient = 1.22
	profile.rolling_resistance = 0.0
	profile.brake_torque_nm = 0.0
	profile.driven = true

	var limb := LimbProfile.new()
	limb.leg_length_m = 1.90
	# The pivot cell centre is the top of the limb, which is where the hip is.
	limb.hip_offset_m = Vector3.ZERO
	limb.foot_radius_m = 0.16
	limb.stance_height_ratio = 0.86
	limb.stance_stiffness_n_m = 307000.0
	limb.stance_damping_ns_m = 38400.0
	limb.max_foot_force_n = 42000.0
	# Above 0.5, so support is continuous and a two-limbed Assembly always has a
	# foot down. A flight phase is expressible and is outside the shipping set.
	limb.duty_factor = 0.62
	limb.nominal_cadence_hz = 1.05
	limb.max_cadence_hz = 2.20
	limb.max_step_length_m = 1.10
	limb.step_height_m = 0.34
	limb.placement_gain_s = 0.19
	limb.turn_rate_deg_s = 45.0
	profile.limb_profile = limb
	def.motive_profile = profile

	def.build_cost = 3400
	def.mount_weight = 4
	return PartAuthoring.save_part(
		def, "mot", PartAuthoring.single_box_collider(lo, hi), &"tread_std"
	)


## §10.4: `pmv.combustion.standard.t2`, 4x4x6, 620 kg, 420 integrity,
## 6400 N.m, 5200 RPM, 150 PU, 7.4 HU/s, 4.2 m blast, 380 damage.
## §11: the `pmv.combustion.*` row.
##
## 150 PU is exactly one `mot.rotor.coaxial_mid.t3` at full collective, which is
## the balance point §12.5 chose ROTOR_W_PER_PU to produce. That is a Prime
## Mover only barely covering a single disc, and it is the reason the Energy Cell
## below exists: a rotary build wants supply, not torque.
func _author_prime_mover_combustion_standard() -> String:
	var lo := Vector3i(-2, 0, -3)
	var hi := Vector3i(1, 3, 2)
	var def := _base(&"pmv.combustion.standard.t2", PartEnums.PartClass.PRIME_MOVER)
	def.tier = PartEnums.TierGrade.STANDARD
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	def.attachment_nodes = PartAuthoring.face_nodes(lo, hi, {})
	def.mass_kg = 620.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 420.0
	def.resistance = PackedFloat32Array([0.10, 0.05, 0.15, 0.30, 0.02])
	def.armour_rating = 14.0
	def.load_capacity_kg = 700.0
	def.power_supply_pu = 150.0
	def.heat_generation_hu_s = 7.4

	var mover := PrimeMoverProfile.new()
	mover.drive_torque_nm = 6400.0
	mover.peak_angular_rpm = 5200.0
	mover.throttle_response_s = 0.18
	mover.thermal_throttle_start_hu = 620.0
	mover.thermal_shutdown_hu = 900.0
	mover.detonation_blast_radius_m = 4.2
	mover.detonation_blast_damage = 380.0
	def.prime_mover_profile = mover

	def.build_cost = 480
	def.mount_weight = 3
	return PartAuthoring.save_part(
		def, "pmv", PartAuthoring.single_box_collider(lo, hi), &"plate_std"
	)


## §10.4: `cel.static.standard.t3`, 4x4x5, 450 kg, 540 integrity, no torque,
## 260 PU, 1.1 HU/s, 3.4 m blast, 300 damage. §11: the `cel.static.*` row.
##
## The other half of the §7.3 split, and the first part in the registry whose
## whole contribution is supply. It carries 260 PU against the Prime Mover's 150
## for 170 kg less, makes no torque at all, and runs cold — 1.1 HU/s against 7.4.
## A rotary Assembly built on cells flies further and cannot drive; one built on
## movers drives and cannot spin a second disc. That trade is the reason the two
## are separate classes rather than one class with a zero in the torque column.
func _author_energy_cell_static_standard() -> String:
	var lo := Vector3i(-2, 0, -2)
	var hi := Vector3i(1, 3, 2)
	var def := _base(&"cel.static.standard.t3", PartEnums.PartClass.ENERGY_CELL)
	def.tier = PartEnums.TierGrade.REFINED
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	def.attachment_nodes = PartAuthoring.face_nodes(lo, hi, {})
	def.mass_kg = 450.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 540.0
	# Softer to thermal and to corrosive than a Prime Mover, and harder to
	# kinetic: a cell is a sealed block rather than a machine with moving parts.
	def.resistance = PackedFloat32Array([0.22, 0.14, 0.06, 0.08, 0.10])
	def.armour_rating = 16.0
	def.load_capacity_kg = 800.0
	def.power_supply_pu = 260.0
	def.heat_generation_hu_s = 1.1

	var cell := EnergyCellProfile.new()
	cell.discharge_limit_pu = 260.0
	cell.capacity_pu_s = 900.0
	cell.recharge_pu_s = 45.0
	cell.thermal_throttle_start_hu = 540.0
	cell.thermal_shutdown_hu = 820.0
	cell.detonation_blast_radius_m = 3.4
	cell.detonation_blast_damage = 300.0
	def.energy_cell_profile = cell

	def.build_cost = 520
	def.mount_weight = 3
	return PartAuthoring.save_part(
		def, "cel", PartAuthoring.single_box_collider(lo, hi), &"plate_std"
	)


## §10.5: `eff.melee.beam_edge.t4`, ENERGY_MELEE, 3x3x8, 307.2 kg, 420 integrity,
## 145 PU, 11.0 HU/shot. §10.5's melee table for reach, arc, timing, and mix.
## §11: the `eff.melee.*` row.
##
## The emission fields are zero because a melee module emits nothing, which §14
## rule 20 requires rather than merely tolerates. The 145 PU of the table is the
## energised total: 20 PU of standby draw on the definition and 125 PU more while
## the edge is lit, so bringing it up genuinely browns out the rest of the
## Assembly instead of being a number in the garage.
func _author_melee_beam_edge() -> String:
	var lo := Vector3i(-1, -1, -7)
	var hi := Vector3i(1, 1, 0)
	var def := _base(&"eff.melee.beam_edge.t4", PartEnums.PartClass.EFFECTOR_MODULE)
	def.tier = PartEnums.TierGrade.PROTOTYPE
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	# Mounts downward onto a deck, so the -Y face protrudes into it. The blade
	# itself extends along -Z, matching the muzzle convention of doc 07 §7.2 so
	# an edge and a barrel agree on which way forward is.
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo, hi, {FACE_YN: PartEnums.AttachmentPolarity.FACE_MALE}
	)
	def.mass_kg = 307.2
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 420.0
	def.resistance = PackedFloat32Array([0.36, 0.20, 0.62, 0.14, 0.10])
	def.armour_rating = 12.0
	def.load_capacity_kg = 150.0
	def.power_draw_pu = 20.0
	def.heat_generation_hu_s = 11.0

	var effector := EffectorModuleProfile.new()
	effector.kind = PartEnums.EffectorKind.ENERGY_MELEE
	effector.yaw_limit_deg = Vector2(-180.0, 180.0)
	effector.pitch_limit_deg = Vector2(-20.0, 40.0)
	effector.yaw_rate_deg_s = 65.0
	effector.pitch_rate_deg_s = 48.0
	# The edge's own root, read by the firing-arc check of doc 02 §7.6. There is
	# no muzzle; this is where the blade leaves the mount.
	effector.muzzle_offsets_m = PackedVector3Array([Vector3(0.0, 0.0, -0.20)])
	effector.projectile_key = &""
	effector.muzzle_velocity_mps = 0.0
	effector.cycle_time_s = 0.0
	effector.burst_count = 0
	effector.burst_recovery_s = 0.0
	effector.magazine_rounds = 0
	effector.reload_time_s = 0.0
	effector.spread_base_deg = 0.0
	effector.spread_bloom_deg = 0.0
	effector.spread_decay_deg_s = 0.0
	effector.recoil_impulse_ns = 0.0
	effector.heat_per_shot_hu = 11.0
	effector.jam_clear_time_s = 1.6

	var melee := MeleeProfile.new()
	melee.reach_m = 2.40
	melee.edge_radius_m = 0.18
	melee.swing_arc_deg = 150.0
	# Doc 07 §15.3: 16 across the 150° arc is a 10° step, which keeps consecutive
	# capsule placements overlapping out to 2.06 m of the 2.40 m blade.
	melee.swing_samples = 16
	melee.wind_up_s = 0.28
	melee.swing_duration_s = 0.22
	melee.recovery_s = 0.46
	melee.strike_damage = 640.0
	# Overwhelmingly THERMAL: what makes the edge cut through a `str.panel.medium`
	# at 0.05 thermal resistance and struggle against a `str.panel.composite` at
	# 0.38. The kind enum picks the presentation; this does the balance work.
	melee.channel_mix = PackedFloat32Array([0.10, 0.0, 0.15, 0.75, 0.0])
	melee.strike_impulse_ns = 2800.0
	melee.reaction_ratio = 0.35
	melee.max_targets_per_swing = 3
	# Zero: a powered edge cuts from a standstill, where a ram spike needs the
	# Assembly to be driving into something.
	melee.min_closing_speed_mps = 0.0
	melee.sustained = true
	melee.sustained_damage_s = 340.0
	melee.energised_draw_pu = 125.0
	effector.melee_profile = melee
	def.effector_profile = effector

	def.build_cost = 2600
	def.mount_weight = 3
	return PartAuthoring.save_part(
		def, "eff", PartAuthoring.single_box_collider(lo, hi), &"vane_std"
	)


## Identity and the fields every part sets the same way.
func _base(key: StringName, part_class: PartEnums.PartClass) -> PartDefinition:
	var def := PartDefinition.new()
	def.part_key = key
	def.display_name_key = StringName("part.%s.name" % key)
	def.description_key = StringName("part.%s.desc" % key)
	def.part_class = part_class
	def.occlusion = PartEnums.OcclusionProfile.OPAQUE_SOLID
	# Solver derives a box tensor from bounds.
	def.inertia_box_half_extents_m = Vector3.ZERO
	return def
