extends TestCase
## The family-derived greybox of [code]docs/EXTENSION_PIPELINE.md[/code] §2.1:
## the shape a part's own profile already describes.
##
## [b]This is the one property of the part table no test could see.[/b]
## LEARNED_FACTS.md fact 75 records it — the registry has no check that compares
## one part against another, so proportion is invisible to every validator and
## obvious in a single frame of capture. A rotor whose authored disc is 2.60 m and
## whose greybox was a 1.0 m box is exactly that failure, and it survived every
## check in the suite because nothing anywhere asked how big the picture was.
##
## So the assertions here are all of one shape: **the drawing is the size the
## simulation thinks the thing is.** Each is written against the profile figure
## rather than against the builder, so a proxy that silently stops reading the
## profile fails here rather than in a capture six sessions later.
##
## No tree and no viewport. [method ProxyMeshBuilder.build] returns an
## [ArrayMesh] and `get_aabb()` answers on a mesh that has never been in a scene.

const ROTOR_KEY := &"mot.rotor.coaxial_mid.t3"
const LIMB_KEY := &"mot.limb.strider.t4"
const TRACK_KEY := &"mot.tracked.short_bogie.t2"
const GUN_KEY := &"eff.ballistic.autocannon_30.t3"
const EDGE_KEY := &"eff.melee.beam_edge.t4"
## Both authored contact sizes, and they disagree about their own colliders: the
## truck's is a cylinder over a disc footprint and the road car's is a box, for
## the reason LEARNED_FACTS.md fact 105 gives.
const WHEEL_KEY := &"mot.wheeled.allroad.t2"
const ROAD_WHEEL_KEY := &"mot.wheeled.light_road.t1"
const CHASSIS_KEYS: Array[StringName] = [
	&"core.command.compact.t2",
	&"core.utility.hauler.t2",
	&"core.biped.humanoid.t3",
	&"core.ambulatory.strider.t3",
]
const ARM_KEY := &"apx.arm.manipulator.t3"
const PANEL_KEY := &"str.panel.medium.t2"

## Tolerance on a span that is the sum of a profile figure and an authored
## thickness. The blade chord and the run thickness both add to an extent, so an
## equality here would be asserting the decoration rather than the dimension.
const SPAN_TOLERANCE_M: float = 0.35


## ===== THE ROTOR =======================================================


## The one that was wrong by a factor of five.
func test_a_rotor_is_drawn_at_the_disc_the_solver_lifts_with() -> void:
	var def := PartRegistry.definition_by_key(ROTOR_KEY)
	if not check_not_null(def, "the rotor disc is registered"):
		return
	var rotor: RotorProfile = def.motive_profile.rotor_profile
	var mesh := ProxyMeshBuilder.build(def)
	if not check_not_null(mesh, "it builds a proxy mesh"):
		return
	var size := mesh.get_aabb().size
	var wanted := rotor.disc_radius_m * 2.0
	check_approx(
		size.x, wanted,
		"the proxy spans the authored disc across x: %.2f m against %.2f" % [size.x, wanted],
		SPAN_TOLERANCE_M
	)
	check_approx(
		size.z, wanted,
		"and across z: %.2f m against %.2f" % [size.z, wanted],
		SPAN_TOLERANCE_M
	)
	# The assertion that carries the finding, and it is deliberately crude: the
	# collider is a 1 m box, so anything near a metre means the mirror is back.
	var collider: ColliderPrimitiveDef = def.collider_profile.primitives[0]
	check_true(
		size.x > collider.half_extents_m.x * 4.0,
		"and is not the collider box it used to mirror (%.2f m)"
			% (collider.half_extents_m.x * 2.0)
	)


## One blade per authored blade, and no more. A picture that drew two discs would
## be claiming lift the solver does not compute.
func test_a_rotor_draws_one_blade_per_authored_blade() -> void:
	var def := PartRegistry.definition_by_key(ROTOR_KEY)
	if not check_not_null(def, "the rotor disc is registered"):
		return
	var rotor: RotorProfile = def.motive_profile.rotor_profile
	var prims := ProxyMeshBuilder.family_primitives(def)
	# A mast, a hub, and the blades.
	check_eq(
		prims.size(), rotor.blade_count + 2,
		"a mast, a hub and %d blades" % rotor.blade_count
	)


## ===== THE LIMB ========================================================


func test_a_limb_is_drawn_at_the_leg_the_gait_solver_swings() -> void:
	var def := PartRegistry.definition_by_key(LIMB_KEY)
	if not check_not_null(def, "the limb is registered"):
		return
	var limb: LimbProfile = def.motive_profile.limb_profile
	var mesh := ProxyMeshBuilder.build(def)
	if not check_not_null(mesh, "it builds a proxy mesh"):
		return
	var aabb := mesh.get_aabb()
	# From the hip down the whole leg, plus the foot below it.
	var wanted := limb.hip_offset_m.y + limb.leg_length_m + limb.foot_radius_m
	check_approx(
		aabb.size.y, wanted,
		"hip to foot is %.2f m against an authored %.2f" % [aabb.size.y, wanted],
		SPAN_TOLERANCE_M
	)
	# The foot ends where the solver puts it, which is what makes a limb drawn
	# along its own axis line up with the contact it is standing on.
	var foot_y := limb.hip_offset_m.y - limb.leg_length_m
	check_approx(
		aabb.position.y, foot_y - limb.foot_radius_m,
		"and the foot is at the end of the leg, not somewhere near it",
		SPAN_TOLERANCE_M
	)


## ===== THE TRACK =======================================================


func test_a_track_is_drawn_at_the_patch_it_puts_on_the_ground() -> void:
	var def := PartRegistry.definition_by_key(TRACK_KEY)
	if not check_not_null(def, "the bogie is registered"):
		return
	var track: TrackProfile = def.motive_profile.track_profile
	var mesh := ProxyMeshBuilder.build(def)
	if not check_not_null(mesh, "it builds a proxy mesh"):
		return
	# The patch runs along the part's own x — its occupancy is eight cells that
	# way and three across.
	var size := mesh.get_aabb().size
	check_true(
		size.x >= track.patch_length_m,
		"the run covers the authored patch: %.2f m against %.2f"
			% [size.x, track.patch_length_m]
	)
	check_true(
		size.x < track.patch_length_m * 2.0,
		"and does not overrun it, which would be a track longer than its own bogie"
	)


## The road wheels are the authored ones, because the number of places a track
## carries load is a figure doc 05 §14 solves against.
func test_a_track_draws_its_authored_road_stations() -> void:
	var def := PartRegistry.definition_by_key(TRACK_KEY)
	if not check_not_null(def, "the bogie is registered"):
		return
	var track: TrackProfile = def.motive_profile.track_profile
	var prims := ProxyMeshBuilder.family_primitives(def)
	# Two runs, two end wheels, and one wheel per station.
	check_eq(
		prims.size(), track.road_stations + 4,
		"two runs, a sprocket, an idler and %d road wheels" % track.road_stations
	)


## ===== THE MODULES =====================================================


## A barrel that stops short of the muzzle is a round appearing out of thin air,
## and it is the kind of thing only a picture catches.
func test_a_barrel_reaches_the_muzzle_it_fires_from() -> void:
	var def := PartRegistry.definition_by_key(GUN_KEY)
	if not check_not_null(def, "the autocannon is registered"):
		return
	var muzzle: Vector3 = def.effector_profile.muzzle_offsets_m[0]
	var mesh := ProxyMeshBuilder.build(def)
	if not check_not_null(mesh, "it builds a proxy mesh"):
		return
	# Doc 07 §7.2 fires along -Z, so the muzzle is the mesh's minimum z.
	check_approx(
		mesh.get_aabb().position.z, muzzle.z,
		"the barrel ends at the muzzle offset the emission loop uses",
		0.05
	)


func test_an_edge_is_drawn_at_the_reach_it_cuts_with() -> void:
	var def := PartRegistry.definition_by_key(EDGE_KEY)
	if not check_not_null(def, "the edge is registered"):
		return
	var melee: MeleeProfile = def.effector_profile.melee_profile
	var mesh := ProxyMeshBuilder.build(def)
	if not check_not_null(mesh, "it builds a proxy mesh"):
		return
	var aabb := mesh.get_aabb()
	check_approx(
		-aabb.position.z, melee.reach_m,
		"the blade is %.2f m long against an authored reach of %.2f"
			% [-aabb.position.z, melee.reach_m],
		SPAN_TOLERANCE_M
	)
	# And it is an edge rather than the block it collides as. The collider is
	# 0.75 m across; anything near that means the mirror is back.
	check_true(
		aabb.size.x < 0.4,
		"and it is thin: %.2f m across against a 0.75 m collider" % aabb.size.x
	)


## ===== THE FALLBACK ====================================================


## The mirror is still the default, and a class that was already right must not be
## given a family shape it does not need.
##
## A panel's collider is already the panel. §2.1's default is the right answer for
## it, and the point of asserting it is that a family path which claimed
## [i]every[/i] part would be invisible in a capture — everything would still look
## like something.
##
## [b]The rolling contact came off this list, and the reason is worth the line.[/b]
## It was here beside the panel on the reading that a wheel's collider is already
## a cylinder on the correct axis — which is true of `mot.wheeled.allroad.t2` and
## false of `mot.wheeled.light_road.t1`, whose collider is a **box**, because
## LEARNED_FACTS.md fact 105 leaves a three-cell disc with no cell list a cylinder
## fits. So half the wheeled contacts in the registry drew as cubes and the
## assertion that they were fine was reading the other half.
func test_a_part_whose_collider_is_its_likeness_still_mirrors_it() -> void:
	var def := PartRegistry.definition_by_key(PANEL_KEY)
	if not check_not_null(def, "%s is registered" % PANEL_KEY):
		return
	check_eq(
		ProxyMeshBuilder.family_primitives(def).size(), 0,
		"%s has no family shape and falls through to the collider mirror" % PANEL_KEY
	)
	var mirrored := ProxyMeshBuilder.mirror_collider(def.collider_profile)
	check_eq(
		mirrored.size(), def.collider_profile.primitives.size(),
		"and the mirror is one primitive per collider primitive"
	)


## A rolling contact is drawn round whatever its collider is, at the profile's own
## rolling radius, about the axis doc 05 §7.1 fixes as the contact frame's lateral
## one.
##
## Asserted over both authored contact sizes, because the two disagree about
## whether their collider is already round and the whole point of the family shape
## is that the drawing no longer depends on that.
func test_a_rolling_contact_is_drawn_round_whatever_it_collides_as() -> void:
	for key: StringName in [WHEEL_KEY, ROAD_WHEEL_KEY] as Array[StringName]:
		var def := PartRegistry.definition_by_key(key)
		if not check_not_null(def, "%s is registered" % key):
			continue
		var prims := ProxyMeshBuilder.family_primitives(def)
		if not check_eq(prims.size(), 2, "%s draws a tyre and a hub" % key):
			continue
		var profile := def.motive_profile
		var mesh := ProxyMeshBuilder.build(def)
		if not check_not_null(mesh, "%s built a proxy" % key):
			continue
		var aabb := mesh.get_aabb()
		check_approx(
			aabb.size.x, profile.contact_radius_m * 2.0,
			(
				"%s is %.2f m across the tread against an authored radius of %.2f"
				% [key, aabb.size.x, profile.contact_radius_m]
			),
			SPAN_TOLERANCE_M
		)
		check_approx(
			aabb.size.y, profile.contact_radius_m * 2.0,
			"and the same over its diameter, so it is a disc and not a slab",
			SPAN_TOLERANCE_M
		)


## Architectural Invariant I-1, stated as the thing that must remain true now that
## a visual differs from its collider for the first time.
##
## [b]The "never a `Shape3D`" half cannot be asserted here and that is the strongest
## possible outcome.[/b] Writing `check_false(mesh is Shape3D, …)` is a **parse
## error** — "Expression is of type ArrayMesh so it can't be of type Shape3D" —
## because [method ProxyMeshBuilder.build] is statically typed to `ArrayMesh` and
## the compiler refuses the comparison. A guarantee the type system enforces at
## build time does not need a runtime check, and a test asserting it would only be
## asserting that GDScript still has types.
##
## What is left needing an assertion is the half a reader actually doubts: that
## drawing the rotor bigger did not quietly grow what it collides as.
func test_the_family_shape_leaves_the_collider_alone() -> void:
	var def := PartRegistry.definition_by_key(ROTOR_KEY)
	if not check_not_null(def, "the rotor disc is registered"):
		return
	check_eq(
		def.collider_profile.primitives.size(), 1,
		"the rotor still collides as the one authored primitive it always did"
	)
	var collider: ColliderPrimitiveDef = def.collider_profile.primitives[0]
	check_approx(
		collider.half_extents_m.x, 0.5,
		"at its authored half-metre, while the drawing spans 5.2 m"
	)


## ===== THE CHASSIS =====================================================


## [b]A chassis may be carved but it may never shrink.[/b]
##
## §2.1's family shapes are allowed to draw outside a collider — a rotor's blades
## do — and a Core Module is the one class where the opposite error matters, because
## a hull is what a player aims at. A drawn silhouette narrower than the collider
## is a target smaller than the one rounds actually stop on, so the union of the
## pieces has to fill the box exactly on all three axes.
##
## Asserted over every chassis in the registry rather than over the two that get a
## family shape, because the assertion has to hold for the ones that fall through
## to the mirror as well — and a mask that started matching a chassis nobody meant
## it to would show up here first.
func test_a_chassis_proxy_fills_the_collider_it_is_carved_out_of() -> void:
	for key: StringName in CHASSIS_KEYS:
		var def := PartRegistry.definition_by_key(key)
		if not check_not_null(def, "%s is registered" % key):
			continue
		var prim: ColliderPrimitiveDef = def.collider_profile.primitives[0]
		var mesh := ProxyMeshBuilder.build(def)
		if not check_not_null(mesh, "%s builds a proxy mesh" % key):
			continue
		var size := mesh.get_aabb().size
		var wanted := prim.half_extents_m * 2.0
		check_approx(size.x, wanted.x, "%s fills its collider across x" % key, 1e-3)
		check_approx(size.y, wanted.y, "%s fills its collider across y" % key, 1e-3)
		check_approx(size.z, wanted.z, "%s fills its collider across z" % key, 1e-3)


## The two families are told apart by the locomotion mask and by nothing else, so
## the assertion is that they are actually told apart: a hull that carries limbs
## is drawn with a head above its widest part and a hull that stands on contacts
## is drawn with a greenhouse over its rear, and those are different piece counts
## only by accident. What is not an accident is that both differ from the mirror.
func test_the_two_chassis_families_are_drawn_differently_from_each_other() -> void:
	var road := PartRegistry.definition_by_key(&"core.command.compact.t2")
	var torso := PartRegistry.definition_by_key(&"core.biped.humanoid.t3")
	var tracked := PartRegistry.definition_by_key(&"core.tracked.hauler.t3")
	if not check_not_null(road, "the road chassis is registered"):
		return
	if not check_not_null(torso, "the biped torso is registered"):
		return
	if not check_not_null(tracked, "the tracked hull is registered"):
		return
	check_true(
		ProxyMeshBuilder.family_primitives(road).size() > 1,
		"a wheeled chassis is carved rather than mirrored"
	)
	check_true(
		ProxyMeshBuilder.family_primitives(torso).size() > 1,
		"and so is an ambulatory one"
	)
	# The waist is drawn in and the cabin is not, so the two rules disagree about
	# the widest thing at the bottom of the hull. Compared through the pieces
	# rather than the mesh, because the meshes have the same bounding box by
	# construction — that is the point of the test above.
	var road_bottom: ProxyPrimitiveDef = ProxyMeshBuilder.family_primitives(road)[0]
	var torso_bottom: ProxyPrimitiveDef = ProxyMeshBuilder.family_primitives(torso)[0]
	var road_box: ColliderPrimitiveDef = road.collider_profile.primitives[0]
	var torso_box: ColliderPrimitiveDef = torso.collider_profile.primitives[0]
	check_approx(
		road_bottom.half_extents_m.x, road_box.half_extents_m.x,
		"a road vehicle's floor pan is as wide as the hull, because it covers the contacts",
		1e-3
	)
	check_true(
		torso_bottom.half_extents_m.x < torso_box.half_extents_m.x,
		"and a torso's waist is drawn in under its chest"
	)
	check_eq(
		ProxyMeshBuilder.family_primitives(tracked).size(), 0,
		"while a tracked hull keeps the mirror, which already reads as what it is"
	)


## ===== THE APPENDAGE ===================================================


## An arm is drawn down its own axis to the palm the melee sweep starts at, and
## it is drawn as an arm rather than as the post it collides as.
##
## [b]The span matters more than the articulation.[/b] Doc 01 §10.6 puts the
## shoulder on the part's `+Y` face and the single GRIP hand on its `-Y` one, so a
## held Effector Module continues below the palm — a drawn hand that stopped short
## of it would leave every held blade floating clear of the fist holding it.
func test_an_arm_reaches_the_palm_the_hand_mates_at() -> void:
	var def := PartRegistry.definition_by_key(ARM_KEY)
	if not check_not_null(def, "the arm is registered"):
		return
	var arm: AppendageProfile = def.appendage_profile
	var prim: ColliderPrimitiveDef = def.collider_profile.primitives[0]
	var mesh := ProxyMeshBuilder.build(def)
	if not check_not_null(mesh, "it builds a proxy mesh"):
		return
	var aabb := mesh.get_aabb()
	check_approx(
		aabb.size.y, prim.half_extents_m.y * 2.0,
		"the drawn arm is the length of the arm: %.2f m against %.2f"
			% [aabb.size.y, prim.half_extents_m.y * 2.0],
		1e-3
	)
	# The pivot cell's centre is the part's own origin, so the palm is `-reach_m`
	# from it and the hand block has to contain that point.
	check_true(
		aabb.position.y <= -arm.reach_m and aabb.position.y + aabb.size.y > -arm.reach_m,
		"and the hand contains the palm at -%.2f m, where the held module starts"
			% arm.reach_m
	)
	# Pauldron, upper arm, elbow, forearm, hand — and not the one box it collides
	# as, which is what made a Gundam's arm a post.
	check_eq(
		ProxyMeshBuilder.family_primitives(def).size(), 5,
		"a pauldron, an upper arm, an elbow, a forearm and a hand"
	)
