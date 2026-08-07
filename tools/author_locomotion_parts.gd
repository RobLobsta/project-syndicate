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
	keys.append(_author_outrigger_pylon())
	keys.append(_author_wheeled_allroad())
	keys.append(_author_wheeled_fixed_rear())
	keys.append(_author_wheeled_light_road())
	keys.append(_author_wheeled_light_fixed())
	keys.append(_author_tracked_short_bogie())
	keys.append(_author_tracked_long_bogie())
	keys.append(_author_prime_mover_combustion_flat())
	keys.append(_author_rotor_coaxial_mid())
	keys.append(_author_limb_strider())
	keys.append(_author_limb_broad_foot())
	keys.append(_author_prime_mover_combustion_standard())
	keys.append(_author_prime_mover_turbine_tracked())
	keys.append(_author_prime_mover_combustion_strider())
	keys.append(_author_prime_mover_turboshaft_rotary())
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


## §10.2: `str.outrigger.pylon.t2`, 3x2x2, 85 kg, 410 integrity, 15 armour,
## 3500 kg load capacity. §11: the `str.hub.*` row, which it shares — it is the
## same load path in a different shape.
##
## [b]It exists because a fuselage can be too narrow for its own rotors.[/b] §4.2
## makes an AXLE station attach through a neutral flank so that both of its drive
## faces stay free, which means a mast station sits directly against the hull it
## mounts on — and `core.rotary.lifter.t3` is 1.00 m wide, because the reference
## rotorcraft seats one abreast. Two stations on its flanks put their disc centres
## 2.00 m apart under 4.00 m discs: half a diameter of overlap, which reads as one
## blurred rotor and not as two.
##
## Three cells between the flank and the station takes the separation to 3.00 m
## and the overlap to a quarter of a diameter. The reference overlaps by about a
## third, so this is very slightly the wider of the two and is the nearest an
## integer lattice gets.
##
## [b]A stub and not a wing, deliberately.[/b] An outrigger long enough to
## separate the discs completely would put them 4.50 m apart on a 7.00 m
## fuselage, which is a wider span than the reference carries and would make the
## machine read as a flying trestle. Every face is neutral so it mates on both
## sides, and it takes one mount.
func _author_outrigger_pylon() -> String:
	var lo := Vector3i(-1, 0, -1)
	var hi := Vector3i(1, 1, 0)
	var def := _base(&"str.outrigger.pylon.t2", PartEnums.PartClass.STRUCTURAL_COMPONENT)
	def.tier = PartEnums.TierGrade.STANDARD
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	# Every face neutral. A pylon exists to be built through from both ends, and a
	# DECK or a polarity on either flank would refuse one of the two joints it is
	# entirely for.
	def.attachment_nodes = PartAuthoring.face_nodes(lo, hi, {})
	def.mass_kg = 85.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 410.0
	def.resistance = PackedFloat32Array([0.26, 0.10, 0.44, 0.10, 0.06])
	def.armour_rating = 15.0
	# High for its mass, and for the same reason the AXLE station's is: everything
	# a disc does to the airframe — 28 kN of thrust and the reaction that comes
	# with it — passes through this one spar.
	def.load_capacity_kg = 3500.0
	def.build_cost = 160
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
	profile.traction_coefficient = 0.78
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
	profile.traction_coefficient = 0.80
	profile.rolling_resistance = 0.014
	profile.brake_torque_nm = 8300.0
	profile.driven = true
	def.motive_profile = profile

	def.build_cost = 205
	def.mount_weight = 2
	return PartAuthoring.save_part(
		def, "mot", PartAuthoring.cylinder_z_collider(lo, hi), &"tread_std"
	)


## §10.3: `mot.wheeled.light_road.t1`, WHEELED_STEERED, 3x3x2, 78 kg,
## 240 integrity, 950 kg rated, 0.78 traction, 34 degree steer, 116000 N/m,
## 9400 Ns/m. §11: the `mot.wheeled.*` row.
##
## [b]0.75 m across, and that is the whole reason it exists.[/b] The reference
## road car measures its wheel at 0.15 of its own length; `mot.wheeled.allroad.t2`
## is 1.00 m against a 5.00 m machine, which is 0.20 — a rally contact under a
## supercar. Three cells is 0.75 m and lands on 0.15 exactly.
##
## Everything else is `allroad` scaled by the load it carries rather than
## re-derived. Rated load is 950 kg against 1100 because a smaller contact patch
## carries less, and the spring rate follows it: `allroad` is 134000 N/m at
## 1100 kg, so 950 kg wants 116000 to sit at the same static fraction of travel.
## Traction is the shipped ground basis of 0.78 unchanged — §10.3's session-38
## review caps every ground row there against the hull's own rollover threshold,
## and a road tyre does not get an exemption from arithmetic.
##
## Travel is 0.18 m against `allroad`'s 0.24, which is not a scaling. It is
## `suspension_rest_length_m` being `contact_radius_m + travel` (doc 05 §6.1)
## against a radius of 0.375: keeping 0.24 would put the rest length at 0.615 and
## stand the hull higher on the smaller wheel than on the larger one, which is
## the opposite of what a low car is for.
func _author_wheeled_light_road() -> String:
	var lo := Vector3i(-1, -1, -1)
	var hi := Vector3i(1, 1, 0)
	var cells := PartAuthoring.box_cells(lo, hi)
	var def := _base(&"mot.wheeled.light_road.t1", PartEnums.PartClass.MOTIVE_ASSEMBLY)
	def.tier = PartEnums.TierGrade.SALVAGE
	def.occupancy_cells = cells
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo,
		hi,
		{FACE_ZN: PartEnums.AttachmentPolarity.AXLE},
		{FACE_ZN: structural_only()},
		cells
	)
	def.mass_kg = 78.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 240.0
	def.resistance = PackedFloat32Array([0.08, 0.12, 0.30, 0.02, 0.00])
	def.armour_rating = 8.0
	def.load_capacity_kg = 160.0

	var profile := MotiveAssemblyProfile.new()
	profile.kind = PartEnums.MotiveKind.WHEELED_STEERED
	# Three cells across is 0.75 m, two deep is 0.5 m — derived from the cells
	# rather than quoted, so the collider, the rolling radius and the occupancy
	# keep describing one object.
	profile.contact_radius_m = 0.375
	profile.contact_width_m = 0.50
	profile.suspension_rest_length_m = 0.555
	profile.suspension_stiffness_n_m = 116000.0
	profile.suspension_damping_ns_m = 9400.0
	profile.suspension_travel_limit_m = 0.18
	# Wider lock than `allroad`'s 32: a road car steers harder than a utility
	# vehicle because it has less to roll over.
	profile.max_steer_angle_deg = 34.0
	profile.steer_rate_deg_s = 160.0
	profile.rated_load_kg = 950.0
	profile.traction_coefficient = 0.78
	profile.rolling_resistance = 0.011
	# Brake torque scales with radius, not with load: the same friction at a
	# shorter arm is less torque, and 8300 x (0.375 / 0.50) is 6200.
	profile.brake_torque_nm = 6200.0
	profile.driven = true
	def.motive_profile = profile

	def.build_cost = 190
	def.mount_weight = 2
	# A BOX where the four-cell rows carry a CYLINDER, and the arithmetic forces
	# it. §6.2 wants a collider covering 82%-118% of the occupancy; a cylinder
	# inscribed in a square is π/4 = 78.5% of it, always, at every radius. The
	# four-cell wheels get away with a cylinder because `disc_cells` takes their
	# four corners off, which drops the occupancy to 75% of the box and puts the
	# ratio at 105%. At three cells a corner-cut leaves a plus of five cells —
	# 55.6% — and the same cylinder is then 141% of it.
	#
	# So a three-cell disc has no cell list a cylinder fits: the box is 78.5% and
	# the plus is 141%, with nothing between them. The box occupancy with a box
	# collider is exactly 100%, and on a 0.75 m contact the corner it adds is
	# 0.11 m of hull that never touches anything the suspension cares about —
	# doc 05 §6.1 shape-casts from the probe, not from this shape, so what the
	# collider decides is ramming and hit registration.
	return PartAuthoring.save_part(
		def, "mot", PartAuthoring.single_box_collider(lo, hi), &"tread_std"
	)


## §10.3: `mot.wheeled.light_fixed.t1`, WHEELED_FIXED, 3x3x2, 74 kg,
## 250 integrity, 1000 kg rated, 0.80 traction, 0 steer, 121000 N/m, 9700 Ns/m.
##
## The unsteered half of the road-car axle pair, and it exists for the reason
## [method _author_wheeled_fixed_rear] gives at length: four contacts that all
## steer the same way translate an Assembly instead of turning it. The trade is
## the same one §10.3 makes at the larger size — slightly more rated load and
## more grip for slightly less mass, because there is no steering mechanism in it
## — so the rear axle is again the one worth driving.
func _author_wheeled_light_fixed() -> String:
	var lo := Vector3i(-1, -1, -1)
	var hi := Vector3i(1, 1, 0)
	var cells := PartAuthoring.box_cells(lo, hi)
	var def := _base(&"mot.wheeled.light_fixed.t1", PartEnums.PartClass.MOTIVE_ASSEMBLY)
	def.tier = PartEnums.TierGrade.SALVAGE
	def.occupancy_cells = cells
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo,
		hi,
		{FACE_ZN: PartEnums.AttachmentPolarity.AXLE},
		{FACE_ZN: structural_only()},
		cells
	)
	def.mass_kg = 74.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 250.0
	def.resistance = PackedFloat32Array([0.08, 0.12, 0.30, 0.02, 0.00])
	def.armour_rating = 8.0
	def.load_capacity_kg = 160.0

	var profile := MotiveAssemblyProfile.new()
	profile.kind = PartEnums.MotiveKind.WHEELED_FIXED
	profile.contact_radius_m = 0.375
	profile.contact_width_m = 0.50
	# Shares a footprint and a travel with the steered row, so it shares §6.1's
	# rest length.
	profile.suspension_rest_length_m = 0.555
	profile.suspension_stiffness_n_m = 121000.0
	profile.suspension_damping_ns_m = 9700.0
	profile.suspension_travel_limit_m = 0.18
	# Zero, and load-bearing: this is the whole difference between the two rows.
	profile.max_steer_angle_deg = 0.0
	profile.steer_rate_deg_s = 0.0
	profile.rated_load_kg = 1000.0
	profile.traction_coefficient = 0.80
	profile.rolling_resistance = 0.011
	profile.brake_torque_nm = 6200.0
	profile.driven = true
	def.motive_profile = profile

	def.build_cost = 175
	def.mount_weight = 2
	# A BOX, for the reason [method _author_wheeled_light_road] sets out: no cell
	# list for a three-cell disc puts a cylinder inside §6.2's coverage band.
	return PartAuthoring.save_part(
		def, "mot", PartAuthoring.single_box_collider(lo, hi), &"tread_std"
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
	profile.traction_coefficient = 0.95
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


## §10.3: `mot.tracked.long_bogie.t3`, TRACKED_SEGMENT, 24x4x3, 1450 kg,
## 1420 integrity, 11000 kg rated, 0.95 traction, 0 steer, 132000 N/m,
## 11400 Ns/m. §10.3's tracked parameter table for the rest.
##
## [b]The part `HANDOFF.md` §3.1.2 asked for: a contact base longer than the hull
## it carries.[/b] `mot.tracked.short_bogie.t2` runs eight cells — 1.90 m of
## patch — and one per flank is the design, so a tracked Assembly was a hull
## see-sawing on a base shorter than itself. Measured at rest on the old 2.25 m
## hull it sat 8.1 degrees nose-up with both forward road stations carrying
## nothing and spiked a single station to 35 kN as the bogie bottomed out. Nothing
## downstream of that is worth tuning: a suspension that is not in contact has no
## rate.
##
## Twenty-four cells is 6.00 m against `core.tracked.hauler.t3`'s 6.00 m hull,
## with 5.60 m of it patch and the last two cells idler and sprocket. The
## reference photograph is where the number comes from — six road wheels running
## the full length of the hull with a drive sprocket and an idler at the two ends
## — and it is also the only arrangement in which six road stations are evenly
## spaced under a hull rather than clustered under its middle.
##
## [b]Two figures here are repairs and not trades, and §10.3 records why.[/b]
## `pivot_taper_mps` is 16.0 against the short bogie's 9.0, because at 9.0 the
## differential was down to a third by 6 m/s and full lock yawed a tracked build
## 0.03 rad/s — it could not turn at any speed a player drives at, and a longer
## patch resists a pivot harder. `lateral_grip_ratio` is 0.85, below 1.0, where
## the short bogie carries 1.35: a tracked vehicle steers by breaking its patch
## loose sideways, so a patch that grips laterally harder than it drives forward
## is the wrong way round for the mechanism, and the longer the run the more
## wrong it is.
func _author_tracked_long_bogie() -> String:
	var lo := Vector3i(-12, -2, -1)
	var hi := Vector3i(11, 1, 1)
	var def := _base(&"mot.tracked.long_bogie.t3", PartEnums.PartClass.MOTIVE_ASSEMBLY)
	def.tier = PartEnums.TierGrade.REFINED
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo, hi, {FACE_ZN: PartEnums.AttachmentPolarity.AXLE}, {FACE_ZN: structural_only()}
	)
	# 1450 kg is the short bogie's 672 scaled by run length rather than by volume:
	# a track is its shoes and its return run, both of which go as the length, and
	# the two idlers do not triple because there are still only two of them.
	def.mass_kg = 1450.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 1420.0
	def.resistance = PackedFloat32Array([0.24, 0.18, 0.40, 0.08, 0.04])
	def.armour_rating = 24.0
	def.load_capacity_kg = 1600.0

	var profile := MotiveAssemblyProfile.new()
	profile.kind = PartEnums.MotiveKind.TRACKED_SEGMENT
	profile.contact_radius_m = 0.50
	profile.contact_width_m = 0.75
	# §6.1's rule, unchanged from the short bogie: a road station's spring is §6.2
	# whatever the run above it is doing.
	profile.suspension_rest_length_m = 0.74
	profile.suspension_stiffness_n_m = 132000.0
	profile.suspension_damping_ns_m = 11400.0
	profile.suspension_travel_limit_m = 0.24
	# §14 rule 22: a track that steered by angling its hub would be a wheel.
	profile.max_steer_angle_deg = 0.0
	profile.steer_rate_deg_s = 0.0
	profile.rated_load_kg = 11000.0
	profile.traction_coefficient = 0.95
	profile.rolling_resistance = 0.024
	profile.brake_torque_nm = 14800.0
	profile.driven = true

	var track := TrackProfile.new()
	# 5.60 m of patch against a 6.00 m part, for the same reason the short bogie
	# runs 1.90 under 2.00: the patch is the ground contact and the last half-cell
	# at each end is idler rather than run.
	track.patch_length_m = 5.60
	track.road_stations = 6
	# Below 1/6 deliberately, so the ends of the patch are soft and the track
	# conforms to a rise instead of bridging it rigidly. The short bogie's 0.22
	# sits the same distance below its own 1/4.
	track.station_load_share = 0.15
	track.sprocket_rad_s = 19.0
	track.differential_authority = 0.85
	track.pivot_taper_mps = 16.0
	track.slew_resistance_nm_per_n_m = 0.51
	track.lateral_grip_ratio = 0.85
	track.internal_loss = 0.10
	profile.track_profile = track
	def.motive_profile = profile

	def.build_cost = 1420
	def.mount_weight = 5
	return PartAuthoring.save_part(
		def, "mot", PartAuthoring.single_box_collider(lo, hi), &"tread_std"
	)


## §10.3: `mot.rotor.coaxial_mid.t3`, ROTOR_DISC, 4x6x4, 500 kg, 690 integrity,
## 2893 kg rated, 40 PU. §10.3's rotary table for the disc parameters.
## §11: the `mot.rotor.*` row.
##
## Thrust at full collective is 28 383 N against a rated 28 380 N — 0.01% apart,
## inside the 1% §14 rule 19 requires. The coefficients are solved from that
## relationship, not chosen: a rotor that cannot lift its own rating presents as
## an Assembly that silently refuses to leave the ground.
##
## [b]The radius went 2.60 -> 2.00 m for a proportion, and thrust goes as the
## fourth power of it.[/b] `A` carries `R²` and `(ΩR)²` carries another two, so a
## 23% cut in radius is a 65% cut in lift: 8300 kg of rating down to 2893, and
## the draw down from 150 PU to 40 with it. The reference rotorcraft carries two
## discs of about 0.45 of its own length each; 2.60 m discs on the 7.00 m fuselage
## of `core.rotary.lifter.t3` are 0.74 of it, which reads as two rotors with a
## stick between them rather than as an aircraft.
##
## The lift that buys back is why the rotary chassis is an 1100 kg airframe: a
## pair of these lifts 5786 kg and the recipe masses about 3800. Ω is held at
## 85 rad/s rather than raised to recover the rating, because the disc loading
## falls with it — 2258 N/m² against the old 3818 — and a lightly loaded disc is
## the one that hovers stably on a small airframe.
##
## The collider is the hub housing. The 2.0 m disc is aerodynamics and carries no
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
	def.mass_kg = 500.0
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
	def.power_draw_pu = 40.0

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
	profile.rated_load_kg = 2893.0
	profile.traction_coefficient = 0.0
	profile.rolling_resistance = 0.0
	profile.brake_torque_nm = 0.0
	profile.driven = true

	var rotor := RotorProfile.new()
	rotor.disc_radius_m = 2.00
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


## §10.3: `mot.limb.strider.t4`, AMBULATORY_LIMB, 3x7x3, 700 kg, 720 integrity,
## 4500 kg rated, 1.22 traction, 45 degree turn, 340000 N/m, 42500 Ns/m.
## §10.3's gait table for the rest. §11: the `mot.limb.*` row.
##
## [b]The reach went 1.90 -> 2.60 m, which puts the hip at 2.24 m under a 2.50 m
## torso.[/b] The humanoid reference is half legs — hip-to-sole is 0.50 of overall
## height off the artwork and the torso a further 0.24 — and the shipped limb
## stood a 1.00 m hull 1.63 m off the ground, which is a body slung between legs
## the way a car body is slung between wheels.
##
## 2.60 m rather than the 3.10 the reference's ratio asks for, and the ceiling is
## the stance base rather than the part. `core.ambulatory.strider.t3` records the
## whole argument: doc 05 §13's virtual leg has a point foot, so fore-and-aft foot
## separation is the only pitch stability the family has, and a taller hip over
## the same 1.50 m stance is a longer lever on the same base. 2.24 m of hip over
## 1.50 m of stance is 0.67, against the 0.92 the family was measured at; below
## that the machine is being asked to balance rather than to walk.
##
## `max_step_length_m` and `step_height_m` are not free of the reach and are
## carried across at the shipped `t4` ratios — 0.58 and 0.177 of `leg_length_m` —
## because a leg that reaches 2.60 m and steps 1.10 is mincing, and the swing has
## to clear its own arc.
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
	# collider around a limb that stands two thirds of its length, and the
	# Assembly rests on its own shins with the stance spring never compressing at
	# all — measured, before this was shortened, at 0.23 m of unreachable travel.
	#
	# Seven cells rather than five now that the reach is 2.60 m: the housing is
	# held at the same fraction of stance height it had at 1.90 m, so the hip
	# structure grows with the leg and the ratio the paragraph above records is
	# unchanged.
	var lo := Vector3i(-1, -6, -1)
	var hi := Vector3i(1, 0, 1)
	var def := _base(&"mot.limb.strider.t4", PartEnums.PartClass.MOTIVE_ASSEMBLY)
	def.tier = PartEnums.TierGrade.PROTOTYPE
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	# The pivot is the top cell and the limb hangs below it, so the AXLE face is
	# +Y: a limb mounts under a chassis, where a wheel mounts beside one.
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo, hi, {FACE_YP: PartEnums.AttachmentPolarity.AXLE}, {FACE_YP: structural_only()}
	)
	def.mass_kg = 700.0
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
	limb.leg_length_m = 2.60
	# The pivot cell centre is the top of the limb, which is where the hip is.
	limb.hip_offset_m = Vector3.ZERO
	limb.foot_radius_m = 0.22
	# §13.10's support polygon. Measured off the humanoid reference, whose foot is
	# about 0.13 of its overall height long and half that wide; on a machine
	# standing 4.75 m that is 0.60 m by 0.34. It is the first authored foot in the
	# project — every limb before this one was a point, which is why every walking
	# Assembly was a quadruped.
	limb.foot_length_m = 0.60
	limb.foot_width_m = 0.34
	limb.stance_height_ratio = 0.86
	# Scaled with the mass the stance carries, not with the reach: the rebuilt
	# ambulatory recipe puts about 700 kg more on four limbs, and a stance spring
	# that did not follow it sags a machine that is already tall.
	limb.stance_stiffness_n_m = 340000.0
	limb.stance_damping_ns_m = 42500.0
	limb.max_foot_force_n = 52000.0
	# Above 0.5, so support is continuous and a two-limbed Assembly always has a
	# foot down. A flight phase is expressible and is outside the shipping set.
	limb.duty_factor = 0.62
	limb.nominal_cadence_hz = 1.05
	limb.max_cadence_hz = 2.20
	# 0.58 and 0.177 of `leg_length_m`, which are the ratios the 1.90 m row
	# carried. See the docstring: neither is free of the reach.
	limb.max_step_length_m = 1.50
	limb.step_height_m = 0.46
	limb.placement_gain_s = 0.19
	limb.turn_rate_deg_s = 45.0
	profile.limb_profile = limb
	def.motive_profile = profile

	def.build_cost = 3400
	def.mount_weight = 4
	return PartAuthoring.save_part(
		def, "mot", PartAuthoring.single_box_collider(lo, hi), &"tread_std"
	)


## §10.3: `mot.limb.broad_foot.t4`, AMBULATORY_LIMB, 3x7x3, 700 kg, 720 integrity,
## 4500 kg rated, 1.22 traction, 45 degree turn, 340000 N/m, 42500 Ns/m.
## §11: the `mot.limb.*` row. [method _author_limb_strider] for everything else,
## because this row differs from it in exactly one place and the whole design is
## in which place that is.
##
## [b]The support polygon is 1.10 x 0.62 m, and it is the difference between a
## machine that stands on two feet and one that stands on four.[/b]
##
## Doc 05 §13.10 bounds a limb's ankle torque at `N x half-extent`, so the
## steepest tilt a stance can hold is where that bound equals the pendulum moment
## it is holding: `N · L/2 = m · g · h · sin θ`. A limb in single support carries
## the whole Assembly, which puts `N` at `m · g` and reduces the whole thing to
## `sin θ_max = L / (2h)` — the static-stability condition, the same one a foot
## has to satisfy for a machine to stand on it at all.
##
## A quadruped never meets that condition, because it never stands on one foot: a
## duty factor of 0.62 over four limbs keeps two or three planted at all times and
## the pendulum is shared. A biped meets it for `2 · duty − 1 = 24%` of its gait
## cycle and misses it for the other **76%**. So the same foot that is generous on
## four limbs is the binding constraint on two, and this row is the four-limbed
## foot resized for a two-limbed machine.
##
## Worked on `CombatArena.Recipe.BIPED` — 5380 kg with its centre of mass 2.55 m
## over the feet:
##
## [codeblock]
## 0.60 m foot:  asin(0.60 / 5.10) =  6.8 deg of recoverable tilt
## 1.10 m foot:  asin(1.10 / 5.10) = 12.5 deg
## [/codeblock]
##
## and the gait itself produces eight degrees of pitch inside a commanded turn.
## Measured over 600 ticks of throttle 0.8 at full right lock:
##
## [codeblock]
## 0.60 x 0.34   worst tilt 97.7 deg — face down from t=390, and it stays there
## 1.10 x 0.62   worst tilt 13.6 deg — a banked turn held for the whole ten seconds
## [/codeblock]
##
## [b]It is a separate row rather than a change to the strider, and the reason is
## measured too.[/b] The polygon also bounds §13.4's standing re-plant — a standing
## Assembly steps when its hip leaves half a foot — so a longer foot lets a
## standing machine creep further before it takes the step that arrests it. On the
## quadruped that took `tests/physics/test_ambulatory_drift.gd`'s standing travel
## from 0.21 m to 0.79 m against a 0.50 m ceiling. The four-limbed family is
## already correct with the foot it has; giving it a foot it does not need in
## order to fix a machine it is not costs it the one thing it does well.
##
## The trade against the strider is mount weight and cost. A foot at 1.83x the
## length is a heavier ankle to hang off a station, and a builder who wants to
## stand on two of these pays five mounts each for the privilege where four buys
## a limb that has to work in a set of four.
func _author_limb_broad_foot() -> String:
	var lo := Vector3i(-1, -6, -1)
	var hi := Vector3i(1, 0, 1)
	var def := _base(&"mot.limb.broad_foot.t4", PartEnums.PartClass.MOTIVE_ASSEMBLY)
	def.tier = PartEnums.TierGrade.PROTOTYPE
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	def.attachment_nodes = PartAuthoring.face_nodes(
		lo, hi, {FACE_YP: PartEnums.AttachmentPolarity.AXLE}, {FACE_YP: structural_only()}
	)
	def.mass_kg = 700.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 720.0
	def.resistance = PackedFloat32Array([0.16, 0.14, 0.26, 0.06, 0.02])
	def.armour_rating = 18.0
	def.load_capacity_kg = 600.0

	var profile := MotiveAssemblyProfile.new()
	profile.kind = PartEnums.MotiveKind.AMBULATORY_LIMB
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
	limb.leg_length_m = 2.60
	limb.hip_offset_m = Vector3.ZERO
	# The contact sphere grows with the foot it sits under, at the ratio the
	# strider row carries: 0.22 under a 0.60 m foot is 0.37 of its length.
	limb.foot_radius_m = 0.40
	# The whole of this row. See the docstring for the derivation and the two
	# measurements it rests on.
	limb.foot_length_m = 1.10
	limb.foot_width_m = 0.62
	limb.stance_height_ratio = 0.86
	limb.stance_stiffness_n_m = 340000.0
	limb.stance_damping_ns_m = 42500.0
	limb.max_foot_force_n = 52000.0
	limb.duty_factor = 0.62
	limb.nominal_cadence_hz = 1.05
	limb.max_cadence_hz = 2.20
	limb.max_step_length_m = 1.50
	limb.step_height_m = 0.46
	limb.placement_gain_s = 0.19
	limb.turn_rate_deg_s = 45.0
	profile.limb_profile = limb
	def.motive_profile = profile

	def.build_cost = 4100
	def.mount_weight = 5
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
	# §7.3's family half. The wheeled pair, and the one place a mask legitimately
	# covers two shipped machines: the road car mounts the flat slab as an engine
	# bay and the utility truck mounts this block as a bonnet, which is two
	# sections of one family's mover rather than two families.
	mover.locomotion_mask = PartEnums.CHASSIS_WHEELED
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


## §10.4: `pmv.turbine.tracked.t3`, 4x4x6, 620 kg, 420 integrity, **13 000 N.m**,
## 5200 RPM, 150 PU, 7.4 HU/s. §11: the `pmv.turbine.*` row.
##
## [b]The tank's own mover, and the reason the family gets one is that it had
## been sharing a car's.[/b] `pmv.combustion.standard.t2` drove the tracked
## hauler, the quadruped, the biped and the rotorcraft on 6400 N.m, so a torque
## correct for a 3.5 t road car was also the torque a 10.5 t tracked hauler ran.
## `HANDOFF.md` §3.1.1 measured the raise four sessions ago and could not apply it,
## because applying it moved every locomotion family in the suite at once. A mask
## on [PrimeMoverProfile] is what makes it applicable.
##
## [b]13 000 N.m is measured rather than chosen.[/b] The published ceiling was
## 6400 because a tracked build at 9600 "cannot stop without pitching past
## vertical" — taken on `mot.tracked.short_bogie.t2`, 1.90 m of patch under a
## 2.25 m hull with its two forward road stations carrying nothing. Session 44
## shipped the 5.60 m bogie and 12 of 12 stations now load at 1.4 deg of pitch, so
## re-taken on the shipped recipe over 420 ticks:
##
## [codeblock]
## N.m      6400    9600   13000   18000   26000
## m/s      3.34    5.48    7.77   11.13   13.20
## tilt    1.36    1.41    1.41    1.41    1.41   degrees
## [/codeblock]
##
## The tilt does not move at all across a fourfold raise; the old objection is
## void. 13 000 is taken because 7.77 m/s is a heavy tracked vehicle's speed and
## because it clears both bounds the family was failing — a 3.0 m/s run-up floor
## and a 3.0 m reverse. It is deliberately short of 18 000, which is 11 m/s and
## reads as a light tank rather than a hauler.
##
## Every other figure is `pmv.combustion.standard.t2`'s, unchanged and
## deliberately so: the section, the mass and the blast are identical, so the
## only thing this row moves is the torque and any measurement that shifts is
## attributable to it.
func _author_prime_mover_turbine_tracked() -> String:
	var lo := Vector3i(-2, 0, -3)
	var hi := Vector3i(1, 3, 2)
	var def := _base(&"pmv.turbine.tracked.t3", PartEnums.PartClass.PRIME_MOVER)
	def.tier = PartEnums.TierGrade.REFINED
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
	mover.locomotion_mask = PartEnums.CHASSIS_TRACKED
	mover.drive_torque_nm = 13000.0
	mover.peak_angular_rpm = 5200.0
	mover.throttle_response_s = 0.18
	mover.thermal_throttle_start_hu = 620.0
	mover.thermal_shutdown_hu = 900.0
	mover.detonation_blast_radius_m = 4.2
	mover.detonation_blast_damage = 380.0
	def.prime_mover_profile = mover

	def.build_cost = 760
	def.mount_weight = 3
	return PartAuthoring.save_part(
		def, "pmv", PartAuthoring.single_box_collider(lo, hi), &"plate_std"
	)


## §10.4: `pmv.combustion.strider.t3`, 4x4x6, 620 kg, 420 integrity, 6400 N.m,
## 5200 RPM, 150 PU, 7.4 HU/s. §11: the `pmv.combustion.*` row.
##
## [b]The walking family's own mover, and every published figure is deliberately
## `pmv.combustion.standard.t2`'s.[/b] A clone with one field changed looks like
## duplication and is the point: the quadruped and the biped were sharing a mover
## with the truck, so tuning either meant tuning both, and the walking family's
## numbers were freshly measured the session this row was added. Keeping every
## figure identical is what makes that measurement survive the split — the gait,
## the reach, the stance and the standing drift are all byte-identical across it.
##
## What it buys is the next change rather than this one. A limb is driven by
## §13.6's stance spring rather than by shaft torque, so `drive_torque_nm` reaches
## nothing on this family at all and the knob that matters is `power_supply_pu`;
## having a row of its own is what lets somebody discover that without moving a
## truck.
func _author_prime_mover_combustion_strider() -> String:
	var lo := Vector3i(-2, 0, -3)
	var hi := Vector3i(1, 3, 2)
	var def := _base(&"pmv.combustion.strider.t3", PartEnums.PartClass.PRIME_MOVER)
	def.tier = PartEnums.TierGrade.REFINED
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
	mover.locomotion_mask = PartEnums.CHASSIS_AMBULATORY
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


## §10.4: `pmv.turboshaft.rotary.t3`, 4x4x6, 620 kg, 420 integrity, 2400 N.m,
## **320 PU**, 7.4 HU/s. §11: the `pmv.turboshaft.*` row.
##
## [b]The rotorcraft's own mover, and the two figures that differ from the block
## it replaces are the two a rotary build actually reads.[/b] Shaft torque drives
## a ground contact and a rotary Assembly has none — §12 turns supply into disc
## speed and disc speed into thrust — so `drive_torque_nm` comes down to 2400,
## which is what a turboshaft has after the reduction gearing, and the figure that
## goes up is the one that matters.
##
## 320 PU against 150. The standard block's 150 is "exactly one
## `mot.rotor.coaxial_mid.t3` at full collective", which the row it replaces says
## outright — a mover barely covering a single disc, on a family whose shipped
## recipe carries **two**. That is why the rotary recipe has to carry an Energy
## Cell to fly at all, and why a rotary build that loses either sinks. 320 covers
## both discs with margin for the spool transient.
func _author_prime_mover_turboshaft_rotary() -> String:
	var lo := Vector3i(-2, 0, -3)
	var hi := Vector3i(1, 3, 2)
	var def := _base(&"pmv.turboshaft.rotary.t3", PartEnums.PartClass.PRIME_MOVER)
	def.tier = PartEnums.TierGrade.REFINED
	def.occupancy_cells = PartAuthoring.box_cells(lo, hi)
	def.attachment_nodes = PartAuthoring.face_nodes(lo, hi, {})
	def.mass_kg = 620.0
	def.com_offset_m = PartAuthoring.box_centre_m(lo, hi)
	def.integrity_max = 420.0
	def.resistance = PackedFloat32Array([0.10, 0.05, 0.15, 0.30, 0.02])
	def.armour_rating = 14.0
	def.load_capacity_kg = 700.0
	def.power_supply_pu = 320.0
	def.heat_generation_hu_s = 7.4

	var mover := PrimeMoverProfile.new()
	mover.locomotion_mask = PartEnums.CHASSIS_ROTARY
	mover.drive_torque_nm = 2400.0
	mover.peak_angular_rpm = 5200.0
	mover.throttle_response_s = 0.18
	mover.thermal_throttle_start_hu = 620.0
	mover.thermal_shutdown_hu = 900.0
	mover.detonation_blast_radius_m = 4.2
	mover.detonation_blast_damage = 380.0
	def.prime_mover_profile = mover

	def.build_cost = 620
	def.mount_weight = 3
	return PartAuthoring.save_part(
		def, "pmv", PartAuthoring.single_box_collider(lo, hi), &"plate_std"
	)


## §10.4: `pmv.combustion.flat.t2`, 8x4x6, 620 kg, 420 integrity, 6400 N.m,
## 5200 RPM, 150 PU, 7.4 HU/s, 4.2 m blast, 380 damage.
##
## [b]`pmv.combustion.standard.t2` laid on its side, and every published figure is
## identical.[/b] The same twenty-four cells of section rearranged from a 1.00 m
## square into a 2.00 x 1.00 m slab; a table that charged differently for the two
## would be pricing the orientation rather than the machine.
##
## It exists because of what a mount does to a silhouette. Every Prime Mover in
## the set is placed on a deck, so its height adds to the hull's, and
## `core.command.compact.t2` is 1.00 m tall — a 1.00 m mover on its roof doubles
## the height of the vehicle and turns a mid-engine road car into a pickup. Mated
## instead to the hull's `+Z` face at deck level, this row is the engine bay
## behind the cabin: 1.50 m of length and no height at all, which is what the
## reference does with the same volume.
##
## Eight cells is even, so it centres on an even-width hull exactly — §14 rule
## 27's parity argument, which is normally a constraint and here is a gift.
func _author_prime_mover_combustion_flat() -> String:
	var lo := Vector3i(-4, 0, -3)
	var hi := Vector3i(3, 3, 2)
	var def := _base(&"pmv.combustion.flat.t2", PartEnums.PartClass.PRIME_MOVER)
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
	mover.locomotion_mask = PartEnums.CHASSIS_WHEELED
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
