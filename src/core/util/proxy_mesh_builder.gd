class_name ProxyMeshBuilder
extends RefCounted
## Builds a stage-PROXY display mesh from a part's primitive list, owned by
## [code]docs/EXTENSION_PIPELINE.md[/code] §2.1.
##
## Architectural Invariant I-1: this produces a [Mesh] and never a [Shape3D]. It
## is the mirror image of [method ColliderPrimitiveDef.build_shape] and shares no
## code with it, deliberately — §2.1 keeps [ProxyPrimitiveDef] and
## [ColliderPrimitiveDef] as separate types so that an art edit can never move a
## hitbox, and merging the two builders would put back exactly the coupling that
## separation exists to prevent.
##
## [b]Three sources, in order: authored, family, mirrored.[/b] No shipped part
## authors [member PartVisualProfile.proxy_primitives] — `test_part_registry_data`
## asserts that — so what runs is the middle one where a class has a family shape
## and the collider mirror everywhere else.
##
## The mirror was the whole story until session 43, and "the greybox is the
## collider, so what a player sees is what a round hits" was a property worth
## keeping. It is given up here deliberately and only where the collider is a
## bounding box rather than a likeness: see [method family_primitives]. Where the
## collider already [i]is[/i] the shape — a contact, a panel — the mirror stands.

## Radial resolution of the round primitives, §2.1's figure.
##
## Godot's own defaults are 64 radial segments on a [CylinderMesh], which is
## five times the triangles for geometry that exists to be replaced. At this
## count a 0.5 m contact disc is still round at the distance §13 of doc 11 puts
## the camera at.
const RADIAL_SEGMENTS: int = 12
const SPHERE_RINGS: int = 6

## ===== FAMILY PROXIES (§2.1) ===========================================
## Cross-sections and thicknesses for the family-derived proxies below. Every
## [i]length[/i] in those proxies is read from the part's own profile — a rotor's
## `disc_radius_m`, a limb's `leg_length_m`, a track's `patch_length_m`, a
## module's `muzzle_offsets_m` — so the only thing authored here is how thick to
## draw it. That split is the whole point: a proxy that disagrees with the
## simulation about how big something is becomes visible, and one that disagrees
## about how chunky it looks is a matter of taste.

## Rotor: the mast that carries the disc, the hub at the top of it, and one blade
## per [member RotorProfile.blade_count] out to [member RotorProfile.disc_radius_m].
const ROTOR_MAST_RADIUS_M: float = 0.16
const ROTOR_HUB_RADIUS_M: float = 0.30
const ROTOR_HUB_HEIGHT_M: float = 0.14
const ROTOR_BLADE_CHORD_M: float = 0.24
const ROTOR_BLADE_THICKNESS_M: float = 0.05

## Limb: hip, thigh, shin and foot along the leg axis. The thigh takes the upper
## share of [member LimbProfile.leg_length_m] and tapers into the shin, which is
## what makes a limb read as a leg rather than as a pole.
const LIMB_HIP_RADIUS_M: float = 0.26
const LIMB_THIGH_RADIUS_M: float = 0.21
const LIMB_SHIN_RADIUS_M: float = 0.16
const LIMB_THIGH_FRACTION: float = 0.52
## How thick the foot is drawn, when it is drawn as a support polygon rather than
## as a ball. The plan dimensions are [member LimbProfile.foot_length_m] and
## [member LimbProfile.foot_width_m] and are not authored here — they are the
## polygon doc 05 §13.10 bounds the ankle torque by, so a limb whose drawn foot
## and whose balance model disagreed about how big a foot is would now disagree
## visibly.
const LIMB_FOOT_THICKNESS_M: float = 0.12

## Track: two runs top and bottom, [member TrackProfile.road_stations] road
## wheels between them, and a larger wheel at each end for the sprocket and the
## idler.
const TRACK_RUN_THICKNESS_M: float = 0.08
const TRACK_RUN_HALF_WIDTH_M: float = 0.30
const TRACK_ROAD_WHEEL_RADIUS_M: float = 0.26
const TRACK_END_WHEEL_RADIUS_M: float = 0.38
const TRACK_WHEEL_WIDTH_M: float = 0.44

## Rolling contact: the tyre at [member MotiveAssemblyProfile.contact_radius_m]
## and a hub standing proud of it.
##
## [b]Only the kinds that actually roll.[/b] A repulsor pad is a
## [constant PartEnums.MotiveKind] on the same profile with no wheel anywhere in
## it, and drawing one as a tyre would be the picture inventing a mechanism the
## simulation does not have.
const ROLLING_KINDS: Array[int] = [
	PartEnums.MotiveKind.WHEELED_STEERED,
	PartEnums.MotiveKind.WHEELED_FIXED,
	PartEnums.MotiveKind.OMNI_ROLLER,
]
## The tread's share of the authored contact width, and the hub's share of the
## tyre's radius. The hub takes the full width and the tread a little less, so the
## hub stands proud of the tread — which is what makes a wheel read as a wheel
## from the front three quarters rather than as a disc lying against the hull —
## without the drawn contact ever being wider than the one it collides as.
const CONTACT_TREAD_WIDTH_FRACTION: float = 0.78
const CONTACT_HUB_RADIUS_FRACTION: float = 0.52

## Direct fire: a breech at the mount and a barrel out to the muzzle. The breech
## keeps the collider's own cross-section so the module still reads as the thing
## that occupies those cells.
const BARREL_RADIUS_M: float = 0.10
const BREECH_LENGTH_FRACTION: float = 0.45

## Melee: a blade of [member MeleeProfile.reach_m], drawn as an edge rather than
## as the block its collider is.
const EDGE_HALF_THICKNESS_M: float = 0.035
const EDGE_HALF_WIDTH_M: float = 0.11
const HILT_HALF_M: float = 0.09

## ===== CHASSIS PROXIES =================================================
## A Core Module's collider is one box around the whole hull, so the mirror draws
## every chassis in the registry as a rectangular block — which is what made five
## differently proportioned vehicles read as five differently proportioned
## blocks. The three families below carve that block into the shape the vehicle
## it was derived from actually has.
##
## [b]Every fraction is of the chassis's own collider half-extents, and the union
## of the pieces fills that box exactly.[/b] That is the constraint the rotor and
## the limb do not have to meet and this one does: a hull is the thing a player
## aims at, so a chassis whose drawn silhouette were narrower than its collider
## would be showing a target smaller than the one rounds actually stop on. One
## piece therefore spans the full plan and reaches the floor, and another reaches
## the roof — `tests/integration/test_part_visuals.gd` asserts the envelope by
## value.

## Road vehicle: a floor pan over the contacts, a body with a waistline, and a
## greenhouse set back from the nose. Three steps of tumblehome is the least that
## reads as a vehicle rather than as a crate.
const ROAD_PAN_TOP: float = -0.56
const ROAD_BODY_TOP: float = 0.20
const ROAD_BODY_HALF_WIDTH: float = 0.92
const ROAD_CABIN_HALF_WIDTH: float = 0.78
## The greenhouse's share of the hull's length, and how far aft of centre it
## sits. A cabin centred on the hull is a van; set back by a tenth of the length
## it leaves a bonnet in front of the screen, which is the single feature that
## makes a road vehicle read as one at greybox fidelity.
const ROAD_CABIN_HALF_LENGTH: float = 0.66
const ROAD_CABIN_SETBACK: float = 0.10

## Walking torso: a waist, a chest, a shoulder yoke and a head.
##
## Four pieces rather than three, because three gave a drawn-in waist under a
## uniform box and the box read as a crate with a knob on top. The widest part of
## a person is the shoulder line and it is at the *top* of the chest, so the
## torso has to widen as it rises and then stop — which is the one silhouette cue
## that separates a body from a container, and it is where the arms hang from.
## The chest is the widest and deepest part and the shoulder yoke above it is
## drawn in, which is the opposite of the first attempt: a yoke wider than the
## chest reads as a coat hanger, and a chest wider than the yoke reads as a torso
## with something in it. The waist is drawn in under both.
const TORSO_WAIST_TOP: float = -0.42
const TORSO_WAIST_HALF_WIDTH: float = 0.58
const TORSO_WAIST_HALF_DEPTH: float = 0.74
const TORSO_CHEST_TOP: float = 0.54
const TORSO_YOKE_TOP: float = 0.76
const TORSO_YOKE_HALF_WIDTH: float = 0.86
const TORSO_YOKE_HALF_DEPTH: float = 0.80
const TORSO_HEAD_HALF_WIDTH: float = 0.34
const TORSO_HEAD_HALF_DEPTH: float = 0.46

## ===== APPENDAGE PROXY =================================================
## An arm's collider is one box eight cells long, and the mirror draws it as a
## post. These are fractions of [member AppendageProfile.reach_m] — the distance
## from the shoulder pivot to the palm, which is the figure the melee sweep and
## the held module's mount both already read — so a drawn elbow cannot end up
## somewhere the hand is not.
const ARM_PAULDRON_END: float = 0.26
const ARM_UPPER_END: float = 0.56
const ARM_FOREARM_START: float = 0.62
const ARM_WRIST: float = 0.90
## The pauldron's width as a multiple of the arm's own collider cross-section.
##
## [b]Over one, which the rest of the table is not.[/b] §2.1 allows a family shape
## to draw outside a collider where the collider is a bounding box rather than a
## likeness, and an arm's is a post; a shoulder that is exactly as wide as the
## limb below it is a pipe with a cap on, and the shoulder is the one feature that
## says "this is an arm and not a strut" at a glance.
const ARM_PAULDRON_WIDTH_RATIO: float = 1.12
const ARM_UPPER_RADIUS_M: float = 0.17
const ARM_ELBOW_RADIUS_M: float = 0.19
const ARM_FOREARM_HALF_M: float = 0.21
const ARM_HAND_HALF_M: float = 0.15


## The display mesh for [param def], or null if it has neither proxy primitives
## nor a collider to mirror.
##
## Callers should go through [ProxyMeshCache] rather than here: forty panels on
## one Assembly are one mesh, and this function builds a new one every call.
static func build(def: PartDefinition) -> ArrayMesh:
	if def == null:
		return null
	var prims: Array[ProxyPrimitiveDef] = []
	if def.visual_profile != null:
		prims = def.visual_profile.proxy_primitives
	if prims.is_empty():
		prims = family_primitives(def)
	if prims.is_empty():
		prims = mirror_collider(def.collider_profile)
	if prims.is_empty():
		push_warning(
			"ProxyMeshBuilder: '%s' has no proxy primitives and no collider to mirror"
			% def.part_key
		)
		return null

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var appended := 0
	for p: ProxyPrimitiveDef in prims:
		var sub := primitive_mesh(p)
		if sub == null:
			push_error(
				"ProxyMeshBuilder: primitive of '%s' built no mesh" % def.part_key
			)
			continue
		st.append_from(sub, 0, p.local_transform())
		appended += 1
	if appended == 0:
		return null
	st.generate_normals()
	st.index()
	return st.commit()


## §2.1's family proxies: the shape a part's [i]own profile[/i] already describes,
## for the classes whose collider is a bounding box rather than a likeness.
##
## [b]The collider mirror is a good default and a bad drawing.[/b] Invariant I-1
## caps a part at three authored primitives and they exist to be cheap and stable,
## so a rotor disc collides as a 1 m box, a limb as a 1.25 m box and an autocannon
## as a 1.75 m box. Mirrored, that is what the player sees — and in the rotor's
## case it under-draws the machine by a factor of five, because
## [member RotorProfile.disc_radius_m] is 2.60 m and nothing on screen was 2.60 m
## of anything. A capture of the shipped rotary build is three grey boxes with
## nothing to say it flies.
##
## Every length below is read from the profile the simulation reads, so these are
## not decoration: a proxy and a solver that disagree about how long a leg is now
## disagree visibly. The thicknesses are authored above and are the only taste in
## it.
##
## [b]This is the first place a visual deliberately differs from its collider,
## and that is a real cost.[/b] Until now the greybox [i]was[/i] the collider, so
## what a player saw was exactly what a round hit. A rotor's blades are now drawn
## where nothing collides — which is correct, because doc 05 §12 makes a disc a
## thrust vector and never a body, and a round passing through a blade is the
## simulation being honest rather than the picture lying. §7's validator measures
## the divergence; what it must never do is silently allow it on a class where the
## collider is the likeness.
##
## Returns an empty array for any part this does not know how to draw, which
## falls through to [method mirror_collider] exactly as before.
static func family_primitives(def: PartDefinition) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	if def == null:
		return out
	var anchor := _collider_anchor(def)
	var mp := def.motive_profile
	if mp != null:
		if mp.rotor_profile != null:
			return _rotor_primitives(mp.rotor_profile, anchor)
		if mp.limb_profile != null:
			return _limb_primitives(mp.limb_profile, anchor)
		if mp.track_profile != null:
			return _track_primitives(mp.track_profile, anchor)
		if ROLLING_KINDS.has(mp.kind):
			return _contact_primitives(mp, anchor)
		return out
	var ep := def.effector_profile
	if ep != null:
		if ep.melee_profile != null:
			return _edge_primitives(ep.melee_profile, anchor)
		return _barrel_primitives(ep, def, anchor)
	if def.core_profile != null:
		return _chassis_primitives(def.core_profile, def, anchor)
	if def.appendage_profile != null:
		return _arm_primitives(def.appendage_profile, def, anchor)
	return out


## The hull shape a Core Module's own locomotion family implies, carved out of
## its collider box.
##
## [b]Which family a chassis declares is the only thing in the data that says
## what shape it is.[/b] Doc 01 §7.1's `locomotion_mask` exists so a limb cannot
## be bolted to a road car, and the same statement answers this question: a hull
## built to stand on contacts is a road vehicle and one built to carry limbs is a
## torso. Nothing else on a [CoreModuleProfile] distinguishes them — the road car
## and the utility truck are within four hundredths of each other on every
## dimensionless ratio §10.1 publishes, so a rule keyed on proportion would be
## reading noise.
##
## The tracked and rotary chassis return an empty array and keep the mirror. A
## long low hull already reads as a tracked platform once the bogies and the gun
## are on it, and a 7.00 m fuselage reads as an airframe; neither is the shape
## this session found wanting.
static func _chassis_primitives(
	core: CoreModuleProfile, def: PartDefinition, anchor: Vector3
) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	var box := _collider_extents(def)
	if box == Vector3.ZERO:
		return out
	if core.carries(PartEnums.LocomotionMode.AMBULATORY):
		return _torso_primitives(box, anchor)
	if core.carries(PartEnums.LocomotionMode.GROUND):
		return _road_body_primitives(box, anchor)
	return out


## A floor pan, a body drawn in at the waist, and a greenhouse set back from the
## nose. Forward is `-Z`, which is the muzzle convention every part in this
## project is authored against.
static func _road_body_primitives(box: Vector3, anchor: Vector3) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	out.append(_slab(
		Vector3(box.x, box.y, box.z), -1.0, ROAD_PAN_TOP, 0.0, anchor
	))
	out.append(_slab(
		Vector3(box.x * ROAD_BODY_HALF_WIDTH, box.y, box.z),
		ROAD_PAN_TOP, ROAD_BODY_TOP, 0.0, anchor
	))
	out.append(_slab(
		Vector3(box.x * ROAD_CABIN_HALF_WIDTH, box.y, box.z * ROAD_CABIN_HALF_LENGTH),
		ROAD_BODY_TOP, 1.0, box.z * ROAD_CABIN_SETBACK, anchor
	))
	return out


## A waist, a chest, and a head. See [constant TORSO_WAIST_TOP].
static func _torso_primitives(box: Vector3, anchor: Vector3) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	out.append(_slab(
		Vector3(box.x * TORSO_WAIST_HALF_WIDTH, box.y, box.z * TORSO_WAIST_HALF_DEPTH),
		-1.0, TORSO_WAIST_TOP, 0.0, anchor
	))
	out.append(_slab(
		Vector3(box.x, box.y, box.z), TORSO_WAIST_TOP, TORSO_CHEST_TOP, 0.0, anchor
	))
	out.append(_slab(
		Vector3(box.x * TORSO_YOKE_HALF_WIDTH, box.y, box.z * TORSO_YOKE_HALF_DEPTH),
		TORSO_CHEST_TOP, TORSO_YOKE_TOP, 0.0, anchor
	))
	out.append(_slab(
		Vector3(box.x * TORSO_HEAD_HALF_WIDTH, box.y, box.z * TORSO_HEAD_HALF_DEPTH),
		TORSO_YOKE_TOP, 1.0, 0.0, anchor
	))
	return out


## A box spanning [param from] to [param to] of the collider's height, in units
## where -1 is its floor and +1 its roof, with [param half]'s `x` and `z` as its
## own half-extents and [param z_offset] shifting it along the hull.
##
## The height arithmetic is here rather than at each call site because getting it
## wrong is invisible — a slab that stops short of the roof leaves a chassis whose
## drawn envelope is smaller than the box rounds stop on, and that reads as a
## rendering glitch rather than as an arithmetic slip.
static func _slab(
	half: Vector3, from: float, to: float, z_offset: float, anchor: Vector3
) -> ProxyPrimitiveDef:
	var d := ProxyPrimitiveDef.new()
	d.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	d.half_extents_m = Vector3(half.x, half.y * (to - from) * 0.5, half.z)
	d.local_offset_m = Vector3(
		anchor.x, anchor.y + half.y * (from + to) * 0.5, anchor.z + z_offset
	)
	return d


## §2.1's Appendage proxy: a pauldron, an upper arm, an elbow, a boxed forearm
## and a hand, down the arm's own `-Y`.
##
## [b]The arm is authored along `-Y` and hangs, which is why this is drawn down
## rather than forward.[/b] Doc 01 §10.6 puts the shoulder on the part's top face
## and the single GRIP hand on its bottom one, so an unrotated Appendage is a
## limb hanging beside a torso and the module it holds continues below the palm
## (LEARNED_FACTS.md fact 104).
##
## The elbow is drawn and is not a joint. Invariant I-3 admits none, and doc 05
## §13.1's reading applies unchanged: the visible articulation is presentation
## under `VisualRoot`, the collider is the authored box from placement to
## destruction, and nothing here is read back by anything.
static func _arm_primitives(
	arm: AppendageProfile, def: PartDefinition, anchor: Vector3
) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	var box := _collider_extents(def)
	if box == Vector3.ZERO:
		return out
	# The shoulder face rather than the pivot cell's centre: the plate the arm
	# bolts to is above that face, and a pauldron that started half a cell below
	# it would leave a visible gap at every shoulder in the game. The span runs
	# from there to the far face, so the drawn arm is exactly the arm the
	# occupancy claims — and `reach_m`, the pivot-to-palm distance the melee sweep
	# reads, lands inside the hand block below rather than beside it.
	var top := anchor.y + box.y
	var span := maxf(box.y * 2.0, arm.reach_m)

	var pauldron := ProxyPrimitiveDef.new()
	pauldron.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	# The collider's own cross-section, so the shoulder is where the widest part
	# of the arm is and the envelope still matches what a round stops on.
	pauldron.half_extents_m = Vector3(
		box.x * ARM_PAULDRON_WIDTH_RATIO,
		span * ARM_PAULDRON_END * 0.5,
		box.z * ARM_PAULDRON_WIDTH_RATIO
	)
	pauldron.local_offset_m = Vector3(anchor.x, top - span * ARM_PAULDRON_END * 0.5, anchor.z)
	out.append(pauldron)

	out.append(_cylinder(
		ARM_UPPER_RADIUS_M,
		span * (ARM_UPPER_END - ARM_PAULDRON_END),
		Vector3(anchor.x, top - span * (ARM_PAULDRON_END + ARM_UPPER_END) * 0.5, anchor.z)
	))

	var elbow := ProxyPrimitiveDef.new()
	elbow.kind = ColliderPrimitiveDef.PrimitiveKind.SPHERE
	elbow.radius_m = ARM_ELBOW_RADIUS_M
	elbow.local_offset_m = Vector3(
		anchor.x, top - span * (ARM_UPPER_END + ARM_FOREARM_START) * 0.5, anchor.z
	)
	out.append(elbow)

	var forearm := ProxyPrimitiveDef.new()
	forearm.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	forearm.half_extents_m = Vector3(
		ARM_FOREARM_HALF_M, span * (ARM_WRIST - ARM_FOREARM_START) * 0.5, ARM_FOREARM_HALF_M
	)
	forearm.local_offset_m = Vector3(
		anchor.x, top - span * (ARM_FOREARM_START + ARM_WRIST) * 0.5, anchor.z
	)
	out.append(forearm)

	# The hand fills the last tenth, so the drawn arm reaches the far face of its
	# own occupancy and the palm is where the held module's frame starts.
	var hand := ProxyPrimitiveDef.new()
	hand.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	hand.half_extents_m = Vector3(
		ARM_HAND_HALF_M, span * (1.0 - ARM_WRIST) * 0.5, ARM_HAND_HALF_M
	)
	hand.local_offset_m = Vector3(
		anchor.x, top - span * (1.0 + ARM_WRIST) * 0.5, anchor.z
	)
	out.append(hand)
	return out


## Where the part's collider sits, which is where its proxy is centred.
##
## Taken from the collider rather than from the occupancy so that a family proxy
## cannot drift sideways off the thing it is drawing: the two are anchored to one
## point, and only the shape between them differs.
static func _collider_anchor(def: PartDefinition) -> Vector3:
	if def.collider_profile == null or def.collider_profile.primitives.is_empty():
		return Vector3.ZERO
	return def.collider_profile.primitives[0].local_offset_m


## A mast, a hub, and one blade per authored blade out to the authored radius.
##
## One disc and not two. `mot.rotor.coaxial_mid.t3` is a coaxial pair by name and
## [RotorProfile] carries one `blade_count` and one `disc_radius_m`, so drawing a
## second ring would be the picture claiming lift the solver does not compute.
static func _rotor_primitives(rotor: RotorProfile, anchor: Vector3) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	var mast_height := maxf(anchor.y * 2.0, ROTOR_HUB_HEIGHT_M)
	out.append(_cylinder(ROTOR_MAST_RADIUS_M, mast_height, Vector3(anchor.x, anchor.y, anchor.z)))
	var hub_y := anchor.y + mast_height * 0.5
	out.append(_cylinder(ROTOR_HUB_RADIUS_M, ROTOR_HUB_HEIGHT_M, Vector3(anchor.x, hub_y, anchor.z)))

	var blades := maxi(rotor.blade_count, 1)
	var span := maxf(rotor.disc_radius_m - ROTOR_HUB_RADIUS_M, ROTOR_BLADE_CHORD_M)
	var mid := ROTOR_HUB_RADIUS_M + span * 0.5
	for i: int in blades:
		var angle := TAU * float(i) / float(blades)
		var blade := ProxyPrimitiveDef.new()
		blade.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
		# Long along the blade's own +Z before the spin about +Y carries it round.
		blade.half_extents_m = Vector3(
			ROTOR_BLADE_CHORD_M * 0.5, ROTOR_BLADE_THICKNESS_M * 0.5, span * 0.5
		)
		blade.local_basis_euler_deg = Vector3(0.0, rad_to_deg(angle), 0.0)
		# The offset is the transform's origin and is not turned by the basis, so
		# the radial position is rotated here rather than left to the transform.
		blade.local_offset_m = Vector3(
			anchor.x + sin(angle) * mid, hub_y, anchor.z + cos(angle) * mid
		)
		out.append(blade)
	return out


## Hip, thigh, shin and foot along the leg axis, which is the part's own local
## down — the axis [method PartMeshFactory.limb_pose] swings about the hip.
##
## Drawn from [member LimbProfile.hip_offset_m] downward over
## [member LimbProfile.leg_length_m], so the geometry on screen is the virtual leg
## doc 05 §13.1 solves rather than a box near it. It does not bend: Invariant I-3
## has one rigid body per Assembly and §13.1 makes the visible articulation an
## inverse-kinematics question §13.8 deliberately leaves open. A segmented leg
## that swings as one piece is what this stage can honestly draw.
static func _limb_primitives(limb: LimbProfile, anchor: Vector3) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	var hip_y := limb.hip_offset_m.y
	var length := maxf(limb.leg_length_m, LIMB_HIP_RADIUS_M * 2.0)
	var thigh := length * LIMB_THIGH_FRACTION
	var shin := length - thigh
	var x := anchor.x
	var z := anchor.z

	out.append(_cylinder(LIMB_HIP_RADIUS_M, LIMB_HIP_RADIUS_M * 2.0, Vector3(x, hip_y, z)))
	out.append(_cylinder(LIMB_THIGH_RADIUS_M, thigh, Vector3(x, hip_y - thigh * 0.5, z)))
	out.append(
		_cylinder(LIMB_SHIN_RADIUS_M, shin, Vector3(x, hip_y - thigh - shin * 0.5, z))
	)
	# The foot is the authored support polygon where there is one, and the contact
	# ball where there is not. Doc 05 §13.10 clamps pitch by `foot_length_m` along
	# the machine's fore-aft and roll by `foot_width_m` across it, and with the leg
	# axis on the part's own `-Y` those are its local `Z` and `X`. A limb with no
	# polygon behaves exactly as it did before §13.10 existed and is drawn the same
	# way, which keeps the drawing honest about which limbs can hold an attitude.
	var foot := ProxyPrimitiveDef.new()
	if limb.foot_length_m > 0.0 and limb.foot_width_m > 0.0:
		foot.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
		foot.half_extents_m = Vector3(
			limb.foot_width_m * 0.5, LIMB_FOOT_THICKNESS_M * 0.5, limb.foot_length_m * 0.5
		)
		foot.local_offset_m = Vector3(
			x, hip_y - length + LIMB_FOOT_THICKNESS_M * 0.5, z
		)
	else:
		foot.kind = ColliderPrimitiveDef.PrimitiveKind.SPHERE
		foot.radius_m = maxf(limb.foot_radius_m, LIMB_SHIN_RADIUS_M)
		foot.local_offset_m = Vector3(x, hip_y - length, z)
	out.append(foot)
	return out


## Two runs, the authored number of road wheels between them, and a larger wheel
## at each end.
##
## The patch runs along the part's own local `X` — its occupancy is eight cells
## that way and three across — and the wheels turn about local `Z`, which is the
## axis a contact's own drive face lies on.
static func _track_primitives(track: TrackProfile, anchor: Vector3) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	var half := maxf(track.patch_length_m, TRACK_END_WHEEL_RADIUS_M * 2.0) * 0.5
	var top := anchor.y + TRACK_END_WHEEL_RADIUS_M
	var bottom := anchor.y - TRACK_END_WHEEL_RADIUS_M

	for y: float in [top, bottom] as Array[float]:
		var run := ProxyPrimitiveDef.new()
		run.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
		run.half_extents_m = Vector3(half, TRACK_RUN_THICKNESS_M, TRACK_RUN_HALF_WIDTH_M)
		run.local_offset_m = Vector3(anchor.x, y, anchor.z)
		out.append(run)

	for sign: float in [-1.0, 1.0] as Array[float]:
		out.append(
			_wheel(
				TRACK_END_WHEEL_RADIUS_M,
				Vector3(anchor.x + sign * half, anchor.y, anchor.z)
			)
		)

	var stations := maxi(track.road_stations, 1)
	# Spaced across the patch with a half-step inset at each end, so the road
	# wheels sit between the sprocket and the idler rather than on top of them.
	for i: int in stations:
		var t := (float(i) + 0.5) / float(stations)
		out.append(
			_wheel(
				TRACK_ROAD_WHEEL_RADIUS_M,
				Vector3(anchor.x + (t * 2.0 - 1.0) * half, anchor.y, anchor.z)
			)
		)
	return out


## A tyre of the profile's own rolling radius, and a hub inside it.
##
## [b]This is the one family proxy that exists because a collider had to be the
## wrong shape.[/b] LEARNED_FACTS.md fact 105: a cylinder inscribed in a square is
## 78.5% of it, which is outside doc 01 §6.2's coverage band, so a three-cell
## contact has no cell list a `CYLINDER` collider fits and
## `mot.wheeled.light_road.t1` carries a `BOX` over a box. Mirrored, the road
## car's contacts are four cubes — and the reference the chassis was derived from
## is a vehicle with small round wheels.
##
## The axis is the part's local `Z`, which doc 05 §7.1 fixes as the contact
## frame's lateral axis and is therefore the axle every wheel in this project
## rolls on.
static func _contact_primitives(
	mp: MotiveAssemblyProfile, anchor: Vector3
) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	var radius := mp.contact_radius_m
	var width := mp.contact_width_m
	if radius <= 0.0 or width <= 0.0:
		return out
	out.append(_axle_cylinder(radius, width * CONTACT_TREAD_WIDTH_FRACTION, anchor))
	out.append(_axle_cylinder(radius * CONTACT_HUB_RADIUS_FRACTION, width, anchor))
	return out


## A breech at the mount and a barrel out to the muzzle doc 07 §7.2 fires from.
##
## The muzzle offset is the one the emission loop uses, so a barrel that stops
## short of where the round appears is a visible disagreement rather than an
## invisible one.
static func _barrel_primitives(
	ep: EffectorModuleProfile, def: PartDefinition, anchor: Vector3
) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	if ep.muzzle_offsets_m.is_empty():
		return out
	var muzzle: Vector3 = ep.muzzle_offsets_m[0]
	var box := _collider_extents(def)
	if box == Vector3.ZERO:
		return out

	var breech_len := box.z * 2.0 * BREECH_LENGTH_FRACTION
	var breech := ProxyPrimitiveDef.new()
	breech.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	breech.half_extents_m = Vector3(box.x, box.y, breech_len * 0.5)
	breech.local_offset_m = Vector3(anchor.x, anchor.y, anchor.z + box.z - breech_len * 0.5)
	out.append(breech)

	# From the front of the breech to the muzzle, along the part's own -Z.
	var from_z := breech.local_offset_m.z - breech_len * 0.5
	var barrel_len := maxf(from_z - muzzle.z, BARREL_RADIUS_M * 2.0)
	var barrel := _cylinder(
		BARREL_RADIUS_M, barrel_len, Vector3(muzzle.x, anchor.y, from_z - barrel_len * 0.5)
	)
	barrel.local_basis_euler_deg = Vector3(90.0, 0.0, 0.0)
	out.append(barrel)
	return out


## A hilt and a blade of [member MeleeProfile.reach_m], along the same `-Z` the
## muzzle convention gives every other module.
static func _edge_primitives(melee: MeleeProfile, anchor: Vector3) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	var hilt := ProxyPrimitiveDef.new()
	hilt.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	hilt.half_extents_m = Vector3(HILT_HALF_M, HILT_HALF_M, HILT_HALF_M)
	hilt.local_offset_m = Vector3(anchor.x, anchor.y, HILT_HALF_M)
	out.append(hilt)

	var reach := maxf(melee.reach_m, HILT_HALF_M * 2.0)
	var blade := ProxyPrimitiveDef.new()
	blade.kind = ColliderPrimitiveDef.PrimitiveKind.BOX
	blade.half_extents_m = Vector3(EDGE_HALF_THICKNESS_M, EDGE_HALF_WIDTH_M, reach * 0.5)
	blade.local_offset_m = Vector3(anchor.x, anchor.y, -reach * 0.5)
	out.append(blade)
	return out


## Half-extents of the part's first collider primitive, or zero when it has none.
static func _collider_extents(def: PartDefinition) -> Vector3:
	if def.collider_profile == null or def.collider_profile.primitives.is_empty():
		return Vector3.ZERO
	var p := def.collider_profile.primitives[0]
	if p.kind == ColliderPrimitiveDef.PrimitiveKind.BOX:
		return p.half_extents_m
	return Vector3(p.radius_m, p.height_m * 0.5, p.radius_m)


## An upright cylinder — [CylinderMesh] runs along its own `+Y`.
static func _cylinder(radius: float, height: float, at: Vector3) -> ProxyPrimitiveDef:
	var d := ProxyPrimitiveDef.new()
	d.kind = ColliderPrimitiveDef.PrimitiveKind.CYLINDER
	d.radius_m = radius
	d.height_m = maxf(height, radius * 0.5)
	d.local_offset_m = at
	return d


## A cylinder laid on its side to turn about the part's local `Z`, which is the
## axle every contact in this project rolls on.
static func _wheel(radius: float, at: Vector3) -> ProxyPrimitiveDef:
	return _axle_cylinder(radius, TRACK_WHEEL_WIDTH_M, at)


## [method _wheel] with the width given rather than assumed, for the parts that
## author one.
static func _axle_cylinder(radius: float, width: float, at: Vector3) -> ProxyPrimitiveDef:
	var d := _cylinder(radius, width, at)
	d.local_basis_euler_deg = Vector3(90.0, 0.0, 0.0)
	return d


## §2.1's fallback: a proxy primitive per collider primitive, field for field.
##
## Returns new resources rather than the collider's own, because a
## [ColliderPrimitiveDef] is shared immutable data (Invariant I-11) and handing
## it to the visual path would be one edit away from an art change moving a
## hitbox.
static func mirror_collider(cp: ColliderProfile) -> Array[ProxyPrimitiveDef]:
	var out: Array[ProxyPrimitiveDef] = []
	if cp == null:
		return out
	for prim: ColliderPrimitiveDef in cp.primitives:
		var d := ProxyPrimitiveDef.new()
		d.kind = prim.kind
		d.half_extents_m = prim.half_extents_m
		d.radius_m = prim.radius_m
		d.height_m = prim.height_m
		d.local_offset_m = prim.local_offset_m
		d.local_basis_euler_deg = prim.local_basis_euler_deg
		out.append(d)
	return out


## One primitive as a mesh, at §2.1's radial resolution.
##
## [method ProxyPrimitiveDef.build_mesh] builds the same shapes at Godot's
## defaults and is what a caller outside the proxy pipeline should use. This
## applies the segment counts because the count is a property of the greybox
## stage rather than of the primitive.
static func primitive_mesh(p: ProxyPrimitiveDef) -> Mesh:
	var mesh := p.build_mesh()
	if mesh is CylinderMesh:
		var cyl := mesh as CylinderMesh
		cyl.radial_segments = RADIAL_SEGMENTS
		cyl.rings = 0
	elif mesh is CapsuleMesh:
		var cap := mesh as CapsuleMesh
		cap.radial_segments = RADIAL_SEGMENTS
		cap.rings = SPHERE_RINGS
	elif mesh is SphereMesh:
		var sph := mesh as SphereMesh
		sph.radial_segments = RADIAL_SEGMENTS
		sph.rings = SPHERE_RINGS
	return mesh
