extends TestCase
## [TrackSolver], from [code]docs/DYNAMIC_MASS_PHYSICS.md[/code] §14.
##
## Parameters are the shipping `mot.tracked.short_bogie.t2` of document 01 §10.3.

const PATCH: float = 1.90
const STATIONS: int = 4
const SPROCKET: float = 22.0
const AUTHORITY: float = 1.0
const TAPER: float = 9.0
const SLEW: float = 0.42
const LOSS: float = 0.08

var _track: TrackProfile = null
var _motive: MotiveAssemblyProfile = null


func before_all() -> void:
	_track = TrackProfile.new()
	_track.patch_length_m = PATCH
	_track.road_stations = STATIONS
	_track.station_load_share = 0.22
	_track.sprocket_rad_s = SPROCKET
	_track.differential_authority = AUTHORITY
	_track.pivot_taper_mps = TAPER
	_track.slew_resistance_nm_per_n_m = SLEW
	_track.lateral_grip_ratio = 1.35
	_track.internal_loss = LOSS

	_motive = MotiveAssemblyProfile.new()
	_motive.contact_radius_m = 0.50
	_motive.rated_load_kg = 2100.0


## ===== ROAD STATIONS ===================================================


func test_stations_are_evenly_spaced_and_symmetric() -> void:
	var offsets := _track.station_offsets_m()
	check_eq(offsets.size(), STATIONS, "one offset per station")
	# spacing = 1.90 / 4 = 0.475; first = -0.95 + 0.2375
	check_approx(offsets[0], -0.7125, "the leading station")
	check_approx(offsets[1], -0.2375, "then inboard")
	check_approx(offsets[2], 0.2375, "mirrored")
	check_approx(offsets[3], 0.7125, "and the trailing one")


## An asymmetric station list would move the part's effective contact centre away
## from its collider with nothing reporting it, which is why the offsets are
## derived rather than authored.
func test_the_station_set_is_centred_on_the_part() -> void:
	var total := 0.0
	for o: float in _track.station_offsets_m():
		total += o
	check_approx(total, 0.0, "the offsets sum to zero about the pivot")


func test_a_single_station_sits_at_the_pivot() -> void:
	_track.road_stations = 1
	var offsets := _track.station_offsets_m()
	_track.road_stations = STATIONS
	check_eq(offsets.size(), 1, "one station")
	check_approx(offsets[0], 0.0, "at the centre of the patch, not at one end")


func test_station_positions_follow_the_rolling_axis() -> void:
	var positions := TrackSolver.station_positions(_track, Vector3(0, 0, 5), Vector3.RIGHT)
	check_eq(positions.size(), STATIONS, "one position per station")
	check_approx(positions[0].x, -0.7125, "the patch runs along the given axis")
	check_approx(positions[0].z, 5.0, "and stays at the part's own position otherwise")


## ===== DIFFERENTIAL DRIVE ==============================================


func test_authority_is_full_at_rest_and_gone_at_the_taper_speed() -> void:
	check_approx(_track.authority_at_speed(0.0), AUTHORITY, "a stationary track pivots freely")
	check_approx(_track.authority_at_speed(TAPER * 0.5), AUTHORITY * 0.5, "and tapers linearly")
	check_approx(_track.authority_at_speed(TAPER), 0.0, "to nothing at the taper speed")
	check_approx(_track.authority_at_speed(50.0), 0.0, "and stays there beyond it")


func test_authority_is_symmetric_in_direction_of_travel() -> void:
	check_approx(
		_track.authority_at_speed(-TAPER * 0.5),
		_track.authority_at_speed(TAPER * 0.5),
		"reversing steers exactly as well as going forward"
	)


func test_drive_bias_clamps_the_steer_command() -> void:
	check_approx(TrackSolver.drive_bias(_track, 2.0, 0.0), 1.0, "a command past full is full")
	check_approx(TrackSolver.drive_bias(_track, -2.0, 0.0), -1.0, "in both directions")
	check_approx(TrackSolver.drive_bias(_track, 1.0, TAPER * 0.5), 0.5, "and scales by authority")


## ===== SIDE TORQUES ====================================================


func test_a_neutral_bias_drives_both_sides_equally() -> void:
	var t := TrackSolver.side_torques(_track, 1000.0, 0.0)
	check_approx(t.x, 460.0, "half of 920 usable after the 8% internal loss")
	check_approx(t.y, 460.0, "on each side")


## A full bias at rest counter-rotates the sides, which is the pivot.
func test_a_full_bias_counter_rotates_the_sides() -> void:
	var t := TrackSolver.side_torques(_track, 1000.0, 1.0)
	check_approx(t.x, 920.0, "the outside track takes everything")
	check_approx(t.y, 0.0, "and the inside stops")


## Internal loss is charged before the torque reaches the ground, not afterwards.
## Charged after, the total would depend on the bias.
func test_internal_loss_is_charged_once_regardless_of_bias() -> void:
	for bias: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var t := TrackSolver.side_torques(_track, 1000.0, bias)
		check_approx(t.x + t.y, 1000.0 * (1.0 - LOSS), "bias %.1f loses the same 8%%" % bias)


## ===== SLEW RESISTANCE =================================================


func test_slew_resistance_opposes_the_yaw() -> void:
	var t := TrackSolver.slew_torque_nm(_track, 10000.0, TrackSolver.SLEW_REFERENCE_RAD_S)
	check_approx(t, -SLEW * PATCH * 10000.0, "0.42 per newton-metre of patch, at full scale")
	check_true(t < 0.0, "against a positive yaw rate")
	check_true(
		TrackSolver.slew_torque_nm(_track, 10000.0, -TrackSolver.SLEW_REFERENCE_RAD_S) > 0.0,
		"and positive against a negative one"
	)


func test_slew_resistance_scales_in_below_the_reference_rate() -> void:
	check_approx(
		TrackSolver.slew_torque_nm(_track, 10000.0, TrackSolver.SLEW_REFERENCE_RAD_S * 0.5),
		-SLEW * PATCH * 10000.0 * 0.5,
		"half the reference rate, half the resistance"
	)


## The cap is what keeps it a resistance rather than a brake. Uncapped, a fast
## spin would generate unbounded counter-torque and the Assembly would snap to a
## stop, which reads as hitting a wall.
func test_slew_resistance_is_capped_above_the_reference_rate() -> void:
	var at_reference := TrackSolver.slew_torque_nm(
		_track, 10000.0, TrackSolver.SLEW_REFERENCE_RAD_S
	)
	check_approx(
		TrackSolver.slew_torque_nm(_track, 10000.0, 20.0),
		at_reference,
		"a violent spin resists no harder than the reference rate does"
	)


func test_a_stationary_hull_slews_against_nothing() -> void:
	check_approx(
		TrackSolver.slew_torque_nm(_track, 10000.0, 0.0),
		0.0,
		"no yaw rate, no resistance; it may only oppose, never initiate"
	)
	check_approx(
		TrackSolver.slew_torque_nm(_track, 0.0, 1.0),
		0.0,
		"and an airborne track shears no ground"
	)


## The length-times-load product is the design statement: a heavy tracked
## Assembly is committed, and no steering input overcomes it.
func test_resistance_rises_with_both_patch_length_and_load() -> void:
	var base := TrackSolver.slew_torque_nm(_track, 10000.0, 1.0)
	var heavier := TrackSolver.slew_torque_nm(_track, 20000.0, 1.0)
	check_approx(heavier, base * 2.0, "twice the armour is twice the torque to turn")
	_track.patch_length_m = PATCH * 2.0
	var longer := TrackSolver.slew_torque_nm(_track, 10000.0, 1.0)
	_track.patch_length_m = PATCH
	check_approx(longer, base * 2.0, "and twice the patch is too")


## ===== HELPERS =========================================================


func test_side_assignment_is_deterministic_on_the_centreline() -> void:
	check_eq(TrackSolver.side_of(Vector3(0.6, 0, 0)), 1, "positive x is the right side")
	check_eq(TrackSolver.side_of(Vector3(-0.6, 0, 0)), -1, "negative x is the left")
	check_eq(
		TrackSolver.side_of(Vector3(0.0, 0, 0)),
		-1,
		"and the centreline counts as left rather than depending on a float comparison"
	)


func test_patch_speed_follows_the_sprocket() -> void:
	check_approx(
		TrackSolver.patch_speed_mps(_motive, SPROCKET),
		SPROCKET * 0.50,
		"22 rad/s at a 0.5 m sprocket is 11 m/s of patch"
	)


func test_station_static_load_is_the_authored_share() -> void:
	check_approx(
		TrackSolver.station_static_load_n(_motive, _track),
		2100.0 * SyndicateConstants.GRAVITY_MPS2 * 0.22,
		"the rating times the share, not divided by the station count"
	)


## Authored below 1/n deliberately, so the ends of the patch are soft and the
## track conforms to a rise instead of bridging it rigidly.
func test_the_station_share_is_softer_than_an_even_split() -> void:
	check_true(
		_track.station_load_share < 1.0 / float(STATIONS),
		"0.22 is below the 0.25 an even split would give"
	)
