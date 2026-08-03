extends TestCase
## The reticle's five states, [code]docs/RESPONSIVE_GARAGE_UI.md[/code] §14.3.
##
## The reticle is the one element a player looks at continuously, and its whole
## job is to be unambiguous. Two states that render alike are worse than one
## state, because the player believes they are being told something.
##
## §10 rule 5 is asserted here as well as §14.3's table: colour is never the only
## carrier of meaning, so every state must also differ in shape. That half cannot
## be checked by reading a colour, so it is checked against the drawing branches
## the state selects.

## §8.3's tokens, by value, so a token that drifts names itself here rather than
## in a screenshot. Handoff §2.1: a test that imports the constant it checks
## asserts nothing.
const TOKEN_TEXT_MUTED := "8d97a5"
const TOKEN_TEXT_PRIMARY := "e6eaf0"
const TOKEN_WARN := "f2c14e"
const TOKEN_ACCENT_SECONDARY := "39d98a"
const TOKEN_DANGER := "e0554e"

const ALL_STATES: Array[HudFrame.ReticleState] = [
	HudFrame.ReticleState.NO_EFFECTOR,
	HudFrame.ReticleState.SEEKING,
	HudFrame.ReticleState.TRACKING,
	HudFrame.ReticleState.ON_TARGET,
	HudFrame.ReticleState.NO_AMMO,
]


func test_every_state_has_its_documented_token() -> void:
	check_eq(Reticle.colour_for(HudFrame.ReticleState.NO_EFFECTOR).to_html(false),
		TOKEN_TEXT_MUTED, "NO_EFFECTOR is text_muted")
	check_eq(Reticle.colour_for(HudFrame.ReticleState.SEEKING).to_html(false),
		TOKEN_TEXT_PRIMARY, "SEEKING is text_primary")
	check_eq(Reticle.colour_for(HudFrame.ReticleState.TRACKING).to_html(false),
		TOKEN_WARN, "TRACKING is warn")
	check_eq(Reticle.colour_for(HudFrame.ReticleState.ON_TARGET).to_html(false),
		TOKEN_ACCENT_SECONDARY, "ON_TARGET is accent_secondary")
	check_eq(Reticle.colour_for(HudFrame.ReticleState.NO_AMMO).to_html(false),
		TOKEN_DANGER, "NO_AMMO is danger")


func test_no_two_states_share_a_colour() -> void:
	var seen: Array[Color] = []
	for s: HudFrame.ReticleState in ALL_STATES:
		var c := Reticle.colour_for(s)
		for other: Color in seen:
			check_false(c.is_equal_approx(other), "state %d has a colour of its own" % s)
		seen.append(c)
	check_eq(seen.size(), ALL_STATES.size(), "all five states were compared")


func test_on_target_reuses_the_garage_s_valid_green() -> void:
	# §14.3's deliberate reuse: in the garage accent_secondary means "this will
	# work", and on the reticle it means "this shot will land". A player learns
	# one colour rather than two, and doc 02 §8's placement ghost is the third
	# consumer of the same token.
	check_true(
		Reticle.colour_for(HudFrame.ReticleState.ON_TARGET).is_equal_approx(
			UiTokens.ACCENT_SECONDARY
		),
		"the reticle's on-target green is the placement-valid green"
	)


func test_seeking_and_tracking_are_distinguishable() -> void:
	# The distinction doc 07 §4.3.1 pays for. A mount outside its arc is a
	# driving problem — turn the hull — and a mount still slewing is a waiting
	# problem. Collapsing the two would tell a player to do nothing in exactly
	# the case where they must do something.
	check_false(
		Reticle.colour_for(HudFrame.ReticleState.SEEKING).is_equal_approx(
			Reticle.colour_for(HudFrame.ReticleState.TRACKING)
		),
		"an out-of-arc mount does not look like a converging one"
	)


func test_the_bracket_spread_separates_converged_from_unconverged() -> void:
	# §10 rule 5's half that a colour comparison cannot reach. The open states
	# must draw wide and the closed ones narrow, or the reticle carries its
	# meaning in hue alone.
	var reticle := Reticle.new()

	reticle.state = HudFrame.ReticleState.SEEKING
	check_true(reticle._is_open(), "SEEKING draws wide")
	reticle.state = HudFrame.ReticleState.NO_EFFECTOR
	check_true(reticle._is_open(), "so does an Assembly with nothing to aim")

	for s: HudFrame.ReticleState in [
		HudFrame.ReticleState.TRACKING,
		HudFrame.ReticleState.ON_TARGET,
		HudFrame.ReticleState.NO_AMMO,
	] as Array[HudFrame.ReticleState]:
		reticle.state = s
		check_false(reticle._is_open(), "state %d draws its brackets in" % s)

	check_true(
		Reticle.SPREAD_MAX_PX > Reticle.SPREAD_MIN_PX,
		"and wide is actually wider than narrow"
	)
	reticle.free()


func test_the_frame_defaults_to_the_state_that_promises_nothing() -> void:
	# A HudFrame that has never been filled must not render as a firing solution.
	var frame := HudFrame.new()
	check_eq(
		frame.reticle_state, HudFrame.ReticleState.NO_EFFECTOR,
		"an unfilled frame claims no Effector Module rather than a solution"
	)
