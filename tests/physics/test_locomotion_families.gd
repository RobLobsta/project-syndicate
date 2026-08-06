extends TestCase
## The four locomotion families, asserted against the [b]shipped[/b] part
## definitions rather than against synthetic profiles.
##
## The unit tests under [code]tests/unit/[/code] prove each solver computes what
## document 05 says it computes. This proves the data the game actually loads
## produces an Assembly that can hold itself up, lift itself off, and walk —
## which is a different claim, and the one a synthetic fixture cannot make.

const CORE: StringName = &"core.command.compact.t2"
const HUB: StringName = &"str.hub.axle_station.t2"
const WHEEL: StringName = &"mot.wheeled.allroad.t2"
const TRACK: StringName = &"mot.tracked.short_bogie.t2"
const ROTOR: StringName = &"mot.rotor.coaxial_mid.t3"
const LIMB: StringName = &"mot.limb.strider.t4"
const PLANT: StringName = &"pmv.combustion.standard.t2"
## Doc 01 §7.1: a disc goes on a rotary chassis and the validator refuses it
## anywhere else, so the minimal flying Assembly is rooted on this and not on
## [constant CORE]. It mattered the moment §10.3 took the disc's radius from
## 2.60 m to 2.00 and its rating from 8300 kg to 2893: the same four parts on the
## 1800 kg ground hull come to a thrust-to-weight of 0.96 and do not leave the
## ground, which is a true statement about a build nobody may make.
const ROTARY_CORE: StringName = &"core.rotary.lifter.t3"
## Doc 01 §10.3's disc draw at full collective, quoted. Re-asserted here so a
## radius change names itself rather than surfacing as a power budget that
## silently stopped binding.
const DISC_DRAW_PU: float = 40.0
const EDGE: StringName = &"eff.melee.beam_edge.t4"


func _def(key: StringName) -> PartDefinition:
	return PartRegistry.definition_by_key(key)


func _weight_n(keys: Array[StringName], counts: Array[int]) -> float:
	var kg := 0.0
	for i: int in keys.size():
		kg += _def(keys[i]).mass_kg * float(counts[i])
	return kg * SyndicateConstants.GRAVITY_MPS2


## ===== DISPATCH ========================================================


## No subsystem outside [MotiveSystem] branches on [enum PartEnums.MotiveKind],
## so the mapping is the whole dispatch and every shipped part must land in the
## family its document section describes.
func test_every_shipped_motive_part_maps_to_its_documented_family() -> void:
	var expected := {
		WHEEL: PartEnums.LocomotionMode.GROUND,
		TRACK: PartEnums.LocomotionMode.TRACKED,
		ROTOR: PartEnums.LocomotionMode.ROTARY,
		LIMB: PartEnums.LocomotionMode.AMBULATORY,
	}
	for key: StringName in expected:
		var profile := _def(key).motive_profile
		check_eq(profile.locomotion_mode(), expected[key], "%s dispatches correctly" % key)


func test_the_locomotion_map_covers_every_motive_kind() -> void:
	check_eq(
		PartEnums.LOCOMOTION_OF_MOTIVE_KIND.size(),
		PartEnums.MOTIVE_KIND_COUNT,
		"an unmapped kind would read GROUND off the end of the array"
	)


func test_each_family_carries_exactly_the_payload_its_kind_needs() -> void:
	check_not_null(_def(ROTOR).motive_profile.rotor_profile, "a disc carries a RotorProfile")
	check_not_null(_def(LIMB).motive_profile.limb_profile, "a limb carries a LimbProfile")
	check_not_null(_def(TRACK).motive_profile.track_profile, "a track carries a TrackProfile")
	check_null(_def(WHEEL).motive_profile.family_payload(), "and a wheel carries none")


## ===== ROTARY: CAN IT FLY ==============================================


## The relationship the shipped coefficients were solved from. A disc that
## cannot lift its own rating presents as an Assembly that silently refuses to
## leave the ground, with nothing in the logs.
func test_the_shipped_disc_lifts_its_rated_load() -> void:
	var profile := _def(ROTOR).motive_profile
	check_approx(
		profile.rotor_profile.max_thrust_n() / (profile.rated_load_kg * SyndicateConstants.GRAVITY_MPS2),
		1.0,
		"maximum thrust is the rated load within 1%",
		0.01
	)


## A minimal rotary Assembly: the rotary chassis, one AXLE station, one disc, one
## Prime Mover. If this cannot hover, the shipping data cannot produce a flying
## build at all.
func test_a_minimal_rotary_assembly_hovers_with_margin() -> void:
	var weight := _weight_n(
		[ROTARY_CORE, HUB, ROTOR, PLANT] as Array[StringName], [1, 1, 1, 1]
	)
	var thrust := _def(ROTOR).motive_profile.rotor_profile.max_thrust_n()
	check_true(thrust > weight, "one disc lifts the smallest Assembly that can carry it")
	check_true(
		thrust / weight > 1.15,
		"with at least the 15%% margin the rotorcraft archetype requires (%.2f)" % (thrust / weight)
	)


## Ground effect must actually help on the deck and be gone by altitude, or the
## player never learns that the disc is working.
func test_ground_effect_changes_the_hover_margin() -> void:
	var rotor := _def(ROTOR).motive_profile.rotor_profile
	var on_deck := RotorSolver.ground_effect(rotor, 0.0)
	var high := RotorSolver.ground_effect(rotor, rotor.disc_radius_m * 2.0)
	check_true(on_deck > high, "a disc works less hard near the ground")
	check_approx(high, 1.0, "and gains nothing at two radii up")


## [b]It used to be one plant per disc, and the radius change made it three.[/b]
## §12.5 chose `ROTOR_W_PER_PU` so that `pmv.combustion.standard.t2`'s 150 PU was
## exactly one `mot.rotor.coaxial_mid.t3` at full collective, and that equality
## was the reason the constant is 4500 rather than a round number.
##
## Doc 01 §10.3 took the disc from 2.60 m of radius to 2.00 for the rotorcraft
## reference's proportion, and shaft power goes as `R⁴` exactly as thrust does:
## the draw fell from 150 PU to 40. The constant is untouched — what moved is the
## part — so the assertion is now the *ratio*, which is the thing §12.5 was
## really about. A rotary build's Prime Mover covers its discs with room over,
## which is a change in what the family can carry and is recorded as one.
func test_one_power_plant_runs_three_discs() -> void:
	var rotor := _def(ROTOR).motive_profile.rotor_profile
	var draw := RotorSolver.draw_pu(rotor, rotor.nominal_rad_s)
	check_approx(draw, DISC_DRAW_PU, "the mid disc draws 40 PU at full collective", 1.0)
	check_approx(
		_def(ROTOR).power_draw_pu,
		DISC_DRAW_PU,
		"and the definition budgets the full-collective figure, so the garage is conservative"
	)
	check_true(
		_def(PLANT).power_supply_pu > DISC_DRAW_PU * 3.0,
		(
			"one standard plant covers three discs (%.0f PU against %.0f), where it "
			+ "used to cover exactly one"
		) % [_def(PLANT).power_supply_pu, DISC_DRAW_PU]
	)


## A coaxial disc cancels its own reaction inside the part, so one of them flies
## alone. This is the property that makes it the forgiving option, and it costs
## mass for the privilege.
func test_the_coaxial_disc_needs_no_anti_torque() -> void:
	check_approx(
		_def(ROTOR).motive_profile.rotor_profile.torque_reaction_ratio,
		0.0,
		"a contra-rotating pair cancels the reaction torque internally"
	)
	var disc := RotorDiscState.new()
	disc.omega_rad_s = _def(ROTOR).motive_profile.rotor_profile.nominal_rad_s
	check_approx(
		disc.reaction_torque_nm(_def(ROTOR).motive_profile.rotor_profile),
		0.0,
		"so a lone disc at full rate transmits no yaw to the Assembly"
	)


## ===== AMBULATORY: CAN IT STAND ========================================


## Stance force must hold the Assembly up with only the duty-factor share of
## limbs planted, which is the hard constraint the strider archetype checks.
func test_four_shipped_limbs_hold_a_walking_assembly_up() -> void:
	var limb := _def(LIMB).motive_profile.limb_profile
	var weight := _weight_n([CORE, HUB, LIMB] as Array[StringName], [1, 4, 4])
	var planted := 4.0 * limb.duty_factor
	var available := planted * limb.max_foot_force_n
	check_true(
		available > weight * 1.30,
		(
			"stance capacity %.0f N covers 1.3x the %.0f N weight with only the duty share down"
			% [available, weight]
		)
	)


## The body settles by whatever compression its share of the weight demands.
## A sag of a whole leg length would mean the Assembly is sitting down.
func test_the_stance_spring_sags_by_a_sane_amount_under_its_own_weight() -> void:
	var limb := _def(LIMB).motive_profile.limb_profile
	var weight := _weight_n([CORE, HUB, LIMB] as Array[StringName], [1, 4, 4])
	var per_limb := weight / (4.0 * limb.duty_factor)
	var sag := per_limb / limb.stance_stiffness_n_m
	check_true(sag < 0.10, "the hip settles less than 10 cm (%.3f m)" % sag)
	check_true(
		sag < limb.stance_rest_length_m() * 0.1, "which is well inside the leg's rest length"
	)


## An even limb count is what makes the phase assignment balanced. The shipped
## limb has to work at two and at four, because both are legal builds.
func test_the_shipped_limb_phases_correctly_at_two_and_four() -> void:
	var two := GaitSolver.assign_phase_offsets(
		PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0)]), PackedInt32Array([1, 2])
	)
	check_approx(absf(two[0] - two[1]), 0.5, "a two-limbed Assembly alternates")

	var four := GaitSolver.assign_phase_offsets(
		PackedVector3Array(
			[
				Vector3(-0.5, 0, -1),
				Vector3(-0.5, 0, 1),
				Vector3(0.5, 0, -1),
				Vector3(0.5, 0, 1),
			]
		),
		PackedInt32Array([1, 2, 3, 4])
	)
	check_approx(absf(four[0] - four[3]), 0.25, "and a four-limbed one swings diagonals together")


## Support is continuous above a duty factor of 0.5, which is what makes a
## walking Assembly tractable under Invariant I-3: there is never a tick with no
## foot down.
func test_the_shipped_gait_never_leaves_the_ground() -> void:
	check_true(
		_def(LIMB).motive_profile.limb_profile.duty_factor > 0.5,
		"a duty factor above 0.5 means at least one foot is always planted"
	)


## ===== TRACKED: CAN IT CARRY ===========================================


func test_two_shipped_tracks_carry_a_heavy_assembly() -> void:
	var profile := _def(TRACK).motive_profile
	var track := profile.track_profile
	var per_station := TrackSolver.station_static_load_n(profile, track)
	var capacity := per_station * float(track.road_stations) * 2.0
	var weight := _weight_n([CORE, HUB, TRACK] as Array[StringName], [1, 2, 2])
	check_true(capacity > weight, "eight stations across two bogies carry the hull they are on")


func test_the_shipped_track_pivots_at_rest_and_commits_at_speed() -> void:
	var track := _def(TRACK).motive_profile.track_profile
	check_approx(
		TrackSolver.drive_bias(track, 1.0, 0.0), 1.0, "full steer at rest counter-rotates the sides"
	)
	check_approx(
		TrackSolver.drive_bias(track, 1.0, track.pivot_taper_mps),
		0.0,
		"and at the taper speed there is no differential left at all"
	)


## The steer angle being zero is required, not incidental: a track that angled
## its hub would be a wheel.
func test_the_shipped_track_has_no_steer_angle() -> void:
	check_approx(
		_def(TRACK).motive_profile.max_steer_angle_deg,
		0.0,
		"§14 rule 22: a track steers by differential drive alone"
	)


## ===== GROUND: CAN IT ROLL =============================================


func test_four_shipped_wheels_carry_their_assembly() -> void:
	var profile := _def(WHEEL).motive_profile
	var capacity := profile.rated_load_kg * SyndicateConstants.GRAVITY_MPS2 * 4.0
	var weight := _weight_n([CORE, HUB, WHEEL] as Array[StringName], [1, 4, 4])
	check_true(capacity > weight, "four wheels carry the smallest Assembly that mounts them")


## The suspension has to have somewhere to travel, or the ground-clearance check
## of doc 02 §7.5 rejects every placement of this part.
func test_the_shipped_wheel_has_usable_suspension_travel() -> void:
	var profile := _def(WHEEL).motive_profile
	check_true(profile.suspension_travel_limit_m > 0.0, "there is travel to consume")
	check_true(
		profile.suspension_rest_length_m > profile.suspension_travel_limit_m,
		"and the rest length leaves room above the bump stop"
	)


## ===== MELEE ===========================================================


## The mix is what does the balance work; the kind enum only picks the
## presentation and the power model.
func test_the_shipped_edge_is_a_thermal_weapon() -> void:
	var melee := _def(EDGE).effector_profile.melee_profile
	check_approx(melee.channel_mix_sum(), 1.0, "the mix accounts for the whole strike")
	check_true(
		melee.channel_mix[PartEnums.DamageChannel.THERMAL] > 0.5,
		"and is majority thermal, which is what makes it cut"
	)


## A powered edge draws continuously, which is the trade that distinguishes it
## from a ram spike. §10.5's 145 PU is the energised total.
func test_the_shipped_edge_costs_power_to_hold_lit() -> void:
	var def := _def(EDGE)
	var melee := def.effector_profile.melee_profile
	check_true(melee.energised_draw_pu > 0.0, "lighting it costs power")
	check_approx(
		def.power_draw_pu + melee.energised_draw_pu,
		145.0,
		"and standby plus energised is the §10.5 draw"
	)
	# 145 PU against a 150 PU plant: one plant covers an edge and nothing else,
	# so an Assembly that both cuts and drives needs a second one. That is the
	# trade, and it only reads as a trade because the number is just under rather
	# than comfortably under.
	var supply := _def(PLANT).power_supply_pu
	var lit := def.power_draw_pu + melee.energised_draw_pu
	check_true(lit < supply, "one standard Prime Mover can just cover a lit edge")
	check_true(
		lit > supply * 0.8,
		"but only just: %.0f PU of a %.0f PU plant leaves nothing for a disc" % [lit, supply]
	)


## §14 rule 20: a melee module emits nothing, and the emission fields are
## required to be zero rather than merely ignored.
func test_the_shipped_edge_emits_nothing() -> void:
	var profile := _def(EDGE).effector_profile
	check_true(profile.is_melee(), "it is a melee module")
	check_approx(profile.muzzle_velocity_mps, 0.0, "no muzzle velocity")
	check_approx(profile.cycle_time_s, 0.0, "no cycle time; the stage machine times it")
	check_approx(profile.recoil_impulse_ns, 0.0, "and no recoil; the reaction impulse is its own")
