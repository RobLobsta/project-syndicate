extends TestCase
## [Breakpoint]: doc 11 §3's layout tiers.
##
## Every threshold below is written out by hand from §3.1 rather than imported
## from the class under test. A test that read `Breakpoint.COMPACT_MAX_W` would
## pass just as happily with the constant set to 90 as to 900 — the published
## number is asserted against the document once, by value, and everything else is
## asserted against those.

const COMPACT_MAX_W: float = 900.0
const MEDIUM_MAX_W: float = 1400.0
const EXPANDED_MAX_W: float = 2100.0
const SHORT_MAX_H: float = 620.0

## Window sizes a player is actually in, so that a change to the thresholds is
## reported as "the commonest window changed tier" rather than as a float moving.
const LAPTOP := Vector2(1366.0, 768.0)
const DESKTOP_HD := Vector2(1920.0, 1080.0)
const PHONE_LANDSCAPE := Vector2(960.0, 440.0)
const ULTRAWIDE := Vector2(3440.0, 1440.0)


func test_the_thresholds_are_the_documented_ones() -> void:
	check_eq(Breakpoint.COMPACT_MAX_W, COMPACT_MAX_W, "§3.1's compact width")
	check_eq(Breakpoint.MEDIUM_MAX_W, MEDIUM_MAX_W, "§3.1's medium width")
	check_eq(Breakpoint.EXPANDED_MAX_W, EXPANDED_MAX_W, "§3.1's expanded width")
	check_eq(Breakpoint.SHORT_MAX_H, SHORT_MAX_H, "§3.1's short height")


func test_each_band_answers_its_own_tier() -> void:
	check_eq(
		Breakpoint.tier_for(Vector2(COMPACT_MAX_W - 1.0, 1000.0)),
		Breakpoint.Tier.COMPACT,
		"just under the compact width"
	)
	check_eq(
		Breakpoint.tier_for(Vector2(COMPACT_MAX_W, 1000.0)),
		Breakpoint.Tier.MEDIUM,
		"exactly the compact width is already medium — the test is a strict less-than"
	)
	check_eq(
		Breakpoint.tier_for(Vector2(MEDIUM_MAX_W - 1.0, 1000.0)),
		Breakpoint.Tier.MEDIUM,
		"just under the medium width"
	)
	check_eq(
		Breakpoint.tier_for(Vector2(EXPANDED_MAX_W - 1.0, 1000.0)),
		Breakpoint.Tier.EXPANDED,
		"just under the expanded width"
	)
	check_eq(
		Breakpoint.tier_for(Vector2(EXPANDED_MAX_W, 1000.0)),
		Breakpoint.Tier.ULTRAWIDE,
		"at the expanded width and above"
	)


## §3.1's reason for taking a [Vector2]: a phone in landscape has ample width and
## very little height, and a rule that only looked at width would give it a
## catalogue two rows tall.
##
## The assertion that matters is the [i]pair[/i]: the same width answers a
## different tier depending on the height, which no test of the width alone can
## show.
func test_height_can_demote_a_wide_window() -> void:
	var wide_and_short := Vector2(DESKTOP_HD.x, SHORT_MAX_H - 1.0)
	var wide_and_tall := Vector2(DESKTOP_HD.x, SHORT_MAX_H + 1.0)
	check_eq(
		Breakpoint.tier_for(wide_and_short),
		Breakpoint.Tier.COMPACT,
		"1920 units wide and 619 tall is a compact layout"
	)
	check_eq(
		Breakpoint.tier_for(wide_and_tall),
		Breakpoint.Tier.EXPANDED,
		"the same width one unit taller is not"
	)
	check_eq(
		Breakpoint.tier_for(PHONE_LANDSCAPE),
		Breakpoint.Tier.COMPACT,
		"a phone in landscape is compact on its height, not its width"
	)


func test_the_windows_players_are_actually_in() -> void:
	check_eq(Breakpoint.tier_for(LAPTOP), Breakpoint.Tier.MEDIUM, "1366×768 is medium")
	check_eq(
		Breakpoint.tier_for(DESKTOP_HD), Breakpoint.Tier.EXPANDED, "1920×1080 is expanded"
	)
	check_eq(
		Breakpoint.tier_for(ULTRAWIDE), Breakpoint.Tier.ULTRAWIDE, "3440×1440 is ultrawide"
	)
	check_eq(
		Breakpoint.tier_for(UiScaleService.HEADLESS_LOGICAL_SIZE),
		Breakpoint.Tier.EXPANDED,
		"and a headless run reports a fixed size, so layout tests are reproducible"
	)


## The stat dock is visible from the medium tier up, which is a correction to
## §3.3's snippet rather than a restatement of it: the table beside that snippet
## gives the medium tier a stat panel and the code hid it, and a 1366×768 window
## is the commonest window there is.
func test_the_stat_dock_survives_the_medium_tier() -> void:
	check_false(
		Breakpoint.shows_stat_dock(Breakpoint.Tier.COMPACT),
		"the compact tier collapses the stats into a sheet"
	)
	check_true(
		Breakpoint.shows_stat_dock(Breakpoint.Tier.MEDIUM),
		"a laptop shows mass, power and rollover"
	)
	check_true(
		Breakpoint.shows_stat_dock(Breakpoint.Tier.EXPANDED), "and so does everything above"
	)


func test_only_the_compact_tier_undocks() -> void:
	check_false(Breakpoint.is_docked(Breakpoint.Tier.COMPACT), "compact uses a bottom sheet")
	for tier: int in [
		Breakpoint.Tier.MEDIUM, Breakpoint.Tier.EXPANDED, Breakpoint.Tier.ULTRAWIDE
	] as Array[int]:
		check_true(Breakpoint.is_docked(tier as Breakpoint.Tier), "tier %d docks" % tier)


## Columns are monotonic in the tier. Not a restatement of the table: it is the
## property that survives the table changing, and the one that would be violated
## by a transposition nobody noticed.
func test_a_wider_tier_never_shows_fewer_columns() -> void:
	var previous := 0
	for tier: int in Breakpoint.Tier.size():
		var columns := Breakpoint.catalogue_columns(tier as Breakpoint.Tier)
		check_true(columns >= 1, "tier %d shows at least one column" % tier)
		check_true(columns >= previous, "tier %d shows no fewer columns than tier %d" % [
			tier, tier - 1
		])
		previous = columns


func test_a_wider_tier_never_gives_the_docks_less_room() -> void:
	var previous := 0.0
	for tier: int in range(Breakpoint.Tier.MEDIUM, Breakpoint.Tier.size()):
		var width := Breakpoint.catalogue_dock_width(tier as Breakpoint.Tier)
		check_true(width > 0.0, "docked tier %d has a catalogue width" % tier)
		check_true(width >= previous, "tier %d is no narrower than tier %d" % [tier, tier - 1])
		previous = width
