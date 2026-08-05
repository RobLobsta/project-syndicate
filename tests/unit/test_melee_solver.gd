extends TestCase
## [MeleeSolver] and [MeleeStrikeState], from
## [code]docs/WEAPON_TARGETING_LOGIC.md[/code] §15.
##
## Parameters are the shipping `eff.melee.beam_edge.t4` of document 01 §10.5.

const REACH: float = 2.40
const ARC: float = 150.0
const SAMPLES: int = 6
const WIND_UP: float = 0.28
const SWING: float = 0.22
const RECOVERY: float = 0.46
const STRIKE: float = 640.0
const IMPULSE: float = 2800.0
const REACTION: float = 0.35
const SUSTAINED_S: float = 340.0

var _melee: MeleeProfile = null


func before_all() -> void:
	_melee = MeleeProfile.new()
	_melee.reach_m = REACH
	_melee.edge_radius_m = 0.18
	_melee.swing_arc_deg = ARC
	_melee.swing_samples = SAMPLES
	_melee.wind_up_s = WIND_UP
	_melee.swing_duration_s = SWING
	_melee.recovery_s = RECOVERY
	_melee.strike_damage = STRIKE
	_melee.channel_mix = PackedFloat32Array([0.10, 0.0, 0.15, 0.75, 0.0])
	_melee.strike_impulse_ns = IMPULSE
	_melee.reaction_ratio = REACTION
	_melee.max_targets_per_swing = 3
	_melee.min_closing_speed_mps = 0.0
	_melee.sustained = true
	_melee.sustained_damage_s = SUSTAINED_S
	_melee.energised_draw_pu = 125.0


func _fresh_state() -> MeleeStrikeState:
	var s := MeleeStrikeState.new()
	s.slot = 4
	return s


## ===== STAGE MACHINE ===================================================


func test_a_ready_module_stays_ready_until_it_begins() -> void:
	var s := _fresh_state()
	check_true(s.can_start(), "a fresh module is ready")
	check_eq(
		MeleeSolver.advance(s, _melee, 1.0, 1.0, false),
		MeleeStrikeState.Stage.READY,
		"and does not advance on its own, however much time passes"
	)


func test_the_cycle_runs_wind_up_then_swing_then_recovery() -> void:
	var s := _fresh_state()
	s.begin()
	check_eq(s.stage, MeleeStrikeState.Stage.WIND_UP, "begin enters the wind-up")

	check_eq(
		MeleeSolver.advance(s, _melee, 1.0, WIND_UP * 0.5, false),
		MeleeStrikeState.Stage.WIND_UP,
		"half the wind-up is still wind-up"
	)
	check_eq(
		MeleeSolver.advance(s, _melee, 1.0, WIND_UP * 0.6, false),
		MeleeStrikeState.Stage.SWINGING,
		"past it, the swing commits"
	)
	check_eq(
		MeleeSolver.advance(s, _melee, 1.0, SWING, false),
		MeleeStrikeState.Stage.RECOVERING,
		"a full swing duration lands the strike and recovers"
	)
	check_eq(
		MeleeSolver.advance(s, _melee, 1.0, RECOVERY, false),
		MeleeStrikeState.Stage.READY,
		"and the recovery returns it to ready"
	)


func test_swing_progress_runs_from_zero_to_one() -> void:
	var s := _fresh_state()
	s.begin()
	MeleeSolver.advance(s, _melee, 1.0, WIND_UP, false)
	check_approx(s.swing_t, 0.0, "the swing starts at its first sample")
	MeleeSolver.advance(s, _melee, 1.0, SWING * 0.5, false)
	check_approx(s.swing_t, 0.5, "and tracks elapsed time through the arc")
	MeleeSolver.advance(s, _melee, 1.0, SWING, false)
	check_approx(s.swing_t, 1.0, "ending exactly at one, never past it")


## A tick that overshoots the swing must not push progress past one. Advancing by
## exactly the duration cannot distinguish a clamped value from an unclamped one,
## because the ratio is 1.0 either way — this is the fixture that can.
func test_an_overshooting_tick_does_not_push_progress_past_one() -> void:
	var s := _fresh_state()
	s.begin()
	MeleeSolver.advance(s, _melee, 1.0, WIND_UP, false)
	MeleeSolver.advance(s, _melee, 1.0, SWING * 4.0, false)
	check_approx(s.swing_t, 1.0, "a long frame lands at the end of the arc, not beyond it")


## The one substitution §15.6 makes against the ballistic degradation path: the
## cycle multiplier scales the whole cycle, wind-up included.
func test_the_cycle_multiplier_slows_every_stage() -> void:
	var critical := DegradationTable.EFF_CYCLE[PartEnums.IntegrityBand.CRITICAL]
	var s := _fresh_state()
	s.begin()
	check_eq(
		MeleeSolver.advance(s, _melee, critical, WIND_UP * 1.01, false),
		MeleeStrikeState.Stage.WIND_UP,
		"a CRITICAL module is still winding up where a NOMINAL one would have swung"
	)
	check_eq(
		MeleeSolver.advance(s, _melee, critical, WIND_UP * critical, false),
		MeleeStrikeState.Stage.SWINGING,
		"and commits only after the scaled wind-up"
	)


## A blade that has committed to a swing and delivers nothing is exactly as
## punishing as a jammed autocannon, and needed no new mechanism.
func test_a_jam_aborts_a_committed_swing_into_recovery() -> void:
	var s := _fresh_state()
	s.begin()
	MeleeSolver.advance(s, _melee, 1.0, WIND_UP, false)
	s.struck_this_swing.push_back(7)
	s.abort_to_recovery()
	check_eq(s.stage, MeleeStrikeState.Stage.RECOVERING, "the swing is dropped, not resolved")
	check_approx(s.swing_t, 0.0, "and its progress is discarded")


## ===== SUSTAINED CONTACT (§15.5) =======================================


## The stage that does not advance. A held trigger on a sustained module leaves
## the edge at the end of its arc instead of recovering, which is what makes the
## sweep run again on the next tick and is the whole of §15.5's stage rule.
func test_a_held_trigger_holds_a_sustained_edge_in_the_swing() -> void:
	var s := _fresh_state()
	s.begin()
	MeleeSolver.advance(s, _melee, 1.0, WIND_UP, true)
	check_eq(
		MeleeSolver.advance(s, _melee, 1.0, SWING, true),
		MeleeStrikeState.Stage.SWINGING,
		"the arc has run and the edge stays in contact"
	)
	check_true(s.energised, "and it is drawing power while it does")
	check_approx(s.swing_t, 1.0, "held at the end of the arc rather than part way through it")
	check_eq(
		MeleeSolver.advance(s, _melee, 1.0, SWING, true),
		MeleeStrikeState.Stage.SWINGING,
		"and stays there for as long as the trigger is held"
	)


## The other direction, and the one a fixture that only ever held the trigger
## could not make: releasing it drops the edge into recovery on the next tick.
func test_releasing_the_trigger_drops_a_sustained_edge_into_recovery() -> void:
	var s := _fresh_state()
	s.begin()
	MeleeSolver.advance(s, _melee, 1.0, WIND_UP, true)
	MeleeSolver.advance(s, _melee, 1.0, SWING, true)
	check_eq(
		MeleeSolver.advance(s, _melee, 1.0, 0.0, false),
		MeleeStrikeState.Stage.RECOVERING,
		"the tick after the release recovers, however long the edge was held"
	)
	check_false(s.energised, "and the draw goes with it")


## A module that does not author sustained contact cannot be held, whatever the
## trigger is doing. Without this the flag on the profile would be decorative and
## every melee module in the game would be a beam.
func test_a_trigger_held_on_an_unsustained_module_still_recovers() -> void:
	_melee.sustained = false
	var s := _fresh_state()
	s.begin()
	MeleeSolver.advance(s, _melee, 1.0, WIND_UP, true)
	check_eq(
		MeleeSolver.advance(s, _melee, 1.0, SWING, true),
		MeleeStrikeState.Stage.RECOVERING,
		"a discrete strike is a discrete strike with the trigger down"
	)
	check_false(s.energised, "and nothing was energised")
	_melee.sustained = true


func test_beginning_a_swing_clears_the_previous_target_set() -> void:
	var s := _fresh_state()
	s.struck_this_swing.push_back(11)
	s.begin()
	check_eq(
		s.struck_this_swing.size(),
		0,
		"or the second swing of a fight would hit nothing it hit in the first"
	)


## ===== TARGET BUDGET ===================================================


## Without this, swing_samples would silently be a damage multiplier and the
## profile field would be unauthorable.
func test_a_target_is_struck_once_per_swing() -> void:
	var s := _fresh_state()
	s.begin()
	check_false(s.already_struck(42, 3), "a fresh swing has struck nobody")
	s.struck_this_swing.push_back(42)
	check_true(s.already_struck(42, 3), "and refuses the same Assembly on a later sample")
	check_false(s.already_struck(43, 3), "while still admitting a different one")


func test_the_swing_stops_at_its_target_budget() -> void:
	var s := _fresh_state()
	s.begin()
	for id: int in [1, 2, 3]:
		s.struck_this_swing.push_back(id)
	check_true(s.already_struck(99, 3), "a fourth target is refused at a budget of three")


## ===== GEOMETRY ========================================================


func test_the_swing_sweeps_the_authored_arc() -> void:
	check_approx(
		rad_to_deg(MeleeSolver.swing_yaw_rad(_melee, 0.0)), -ARC * 0.5, "starting at one end"
	)
	check_approx(rad_to_deg(MeleeSolver.swing_yaw_rad(_melee, 0.5)), 0.0, "through the centre")
	check_approx(
		rad_to_deg(MeleeSolver.swing_yaw_rad(_melee, 1.0)), ARC * 0.5, "and ending at the other"
	)


## A ram authors a zero arc: it does not swing at all, it is a fixed edge that
## damages what the Assembly drives into. No special case in the solver.
func test_a_zero_arc_never_swings() -> void:
	_melee.swing_arc_deg = 0.0
	for t: float in [0.0, 0.5, 1.0]:
		check_approx(
			MeleeSolver.swing_yaw_rad(_melee, t), 0.0, "a fixed edge stays put at t=%.1f" % t
		)
	_melee.swing_arc_deg = ARC


func test_the_edge_transform_extends_along_local_forward() -> void:
	var mount := Transform3D.IDENTITY
	var x := MeleeSolver.edge_transform(_melee, mount, 0.5)
	check_approx(x.origin.z, -REACH * 0.5, "the capsule is centred half a reach along -Z")
	check_approx(x.origin.x, 0.0, "with the arc at its midpoint, straight ahead")


func test_the_edge_swings_to_one_side_at_the_arc_ends() -> void:
	var start := MeleeSolver.edge_transform(_melee, Transform3D.IDENTITY, 0.0)
	var finish := MeleeSolver.edge_transform(_melee, Transform3D.IDENTITY, 1.0)
	check_true(start.origin.x * finish.origin.x < 0.0, "the two ends are on opposite sides")
	check_approx(
		start.origin.length(), finish.origin.length(), "at the same distance from the mount", 1e-4
	)


func test_sample_progress_spans_the_swing_and_is_bounded() -> void:
	var s := MeleeSolver.sample_progress(_melee)
	check_eq(s.size(), SAMPLES, "one per authored sample")
	check_approx(s[0], 0.0, "starting at the beginning")
	check_approx(s[SAMPLES - 1], 1.0, "and ending at the end")

	_melee.swing_samples = 99
	check_eq(
		MeleeSolver.sample_progress(_melee).size(),
		MeleeSolver.MAX_SWING_SAMPLES,
		"an over-authored count is capped, per CLAUDE.md §6 I-12"
	)
	_melee.swing_samples = 1
	check_eq(
		MeleeSolver.sample_progress(_melee).size(), 2, "and an under-authored one floors at two"
	)
	_melee.swing_samples = SAMPLES


## ===== EFFECT ==========================================================


## One packet per non-zero share, never one packet carrying a blend: doc 08's
## resolver applies resistance per channel and has no second path.
func test_damage_splits_by_the_channel_mix() -> void:
	check_approx(
		MeleeSolver.channel_damage(_melee, PartEnums.DamageChannel.THERMAL),
		STRIKE * 0.75,
		"a powered edge is overwhelmingly thermal"
	)
	check_approx(
		MeleeSolver.channel_damage(_melee, PartEnums.DamageChannel.IMPACT), STRIKE * 0.15, "impact"
	)
	check_approx(
		MeleeSolver.channel_damage(_melee, PartEnums.DamageChannel.BLAST),
		0.0,
		"and nothing at all on a channel it does not use"
	)


func test_the_mix_accounts_for_the_whole_strike() -> void:
	var total := 0.0
	for c: int in PartEnums.DAMAGE_CHANNEL_COUNT:
		total += MeleeSolver.channel_damage(_melee, c)
	check_approx(total, STRIKE, "the channels sum to the authored strike damage")
	check_approx(_melee.channel_mix_sum(), 1.0, "because the mix sums to one")


## The sum has to be computed rather than assumed, or the validator rule that
## rejects a mis-authored mix is asserting against a constant. Only a mix that
## does not sum to one can tell the two apart.
func test_the_mix_sum_is_computed_from_the_mix() -> void:
	var bad := MeleeProfile.new()
	bad.channel_mix = PackedFloat32Array([0.5, 0.0, 0.5, 0.5, 0.0])
	check_approx(bad.channel_mix_sum(), 1.5, "an over-authored mix reports 1.5, not 1.0")
	bad.channel_mix = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	check_approx(bad.channel_mix_sum(), 0.0, "and an empty one reports nothing")


func test_sustained_damage_is_per_second_and_needs_the_flag() -> void:
	check_approx(
		MeleeSolver.sustained_channel_damage(_melee, PartEnums.DamageChannel.THERMAL, 0.5),
		SUSTAINED_S * 0.75 * 0.5,
		"half a second of contact at three quarters thermal"
	)
	_melee.sustained = false
	check_approx(
		MeleeSolver.sustained_channel_damage(_melee, PartEnums.DamageChannel.THERMAL, 0.5),
		0.0,
		"a module that is not sustained deals nothing between swings"
	)
	_melee.sustained = true


## A ram authors a positive minimum and does nothing to a target it is not
## driving into; a powered edge authors zero and cuts from a standstill.
func test_the_closing_speed_gate() -> void:
	check_true(
		MeleeSolver.closing_speed_satisfied(_melee, 0.0), "a powered edge cuts from a standstill"
	)
	_melee.min_closing_speed_mps = 4.0
	check_false(MeleeSolver.closing_speed_satisfied(_melee, 2.0), "a ram at walking pace does not")
	check_true(MeleeSolver.closing_speed_satisfied(_melee, 6.0), "but at speed it does")
	_melee.min_closing_speed_mps = 0.0


func test_the_strike_impulse_follows_the_edge_travel() -> void:
	var travel := Vector3(3.0, 0.0, 4.0)
	var impulse := MeleeSolver.strike_impulse(_melee, travel)
	check_approx(impulse.length(), IMPULSE, "the authored magnitude")
	check_approx(
		impulse.normalized().distance_to(travel.normalized()),
		0.0,
		"along the direction the edge is travelling, not along its own axis",
		1e-5
	)


## What stops melee being a free weapon, and why melee rewards mass.
func test_the_reaction_opposes_the_strike_and_is_a_fraction_of_it() -> void:
	var travel := Vector3(1.0, 0.0, 0.0)
	var strike := MeleeSolver.strike_impulse(_melee, travel)
	var reaction := MeleeSolver.reaction_impulse(_melee, travel)
	check_approx(reaction.length(), IMPULSE * REACTION, "980 N.s against a 2800 N.s strike")
	check_true(reaction.dot(strike) < 0.0, "and pointing the other way")


func test_a_stationary_edge_delivers_no_impulse() -> void:
	check_eq(
		MeleeSolver.strike_impulse(_melee, Vector3.ZERO),
		Vector3.ZERO,
		"an edge with no travel direction shoves nothing, rather than normalising zero"
	)


func test_the_energised_draw_applies_only_while_lit() -> void:
	check_approx(MeleeSolver.draw_pu(_melee, true), 125.0, "an energised edge draws")
	check_approx(MeleeSolver.draw_pu(_melee, false), 0.0, "and a dark one does not")
