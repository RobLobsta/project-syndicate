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
const WHEEL_KEY := &"mot.wheeled.allroad.t2"
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


## The mirror is still the default, and the two classes that were already right
## must not have been given a family shape they do not need.
##
## A wheel's collider is already a cylinder on the correct axis and a panel's is
## already the panel. §2.1's default is the right answer for both, and the point
## of asserting it is that a family path which claimed [i]every[/i] part would be
## invisible in a capture — everything would still look like something.
func test_a_part_whose_collider_is_its_likeness_still_mirrors_it() -> void:
	for key: StringName in [WHEEL_KEY, PANEL_KEY] as Array[StringName]:
		var def := PartRegistry.definition_by_key(key)
		if not check_not_null(def, "%s is registered" % key):
			continue
		check_eq(
			ProxyMeshBuilder.family_primitives(def).size(), 0,
			"%s has no family shape and falls through to the collider mirror" % key
		)
		var mirrored := ProxyMeshBuilder.mirror_collider(def.collider_profile)
		check_eq(
			mirrored.size(), def.collider_profile.primitives.size(),
			"and the mirror is one primitive per collider primitive"
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
