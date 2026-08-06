extends TestCase
## [PartInspector]: doc 11 §4.3's per-class description of a part.
##
## The subject is [method PartInspector.rows_for] — a static over a
## [PartDefinition] — because the mapping from a part to what a player is told
## about it is a rule, and a rule that needed a garage and a viewport to observe
## would be a rule nothing checked.
##
## [b]Every assertion here is against a shipped part's authored figures.[/b] A
## test that read the profile and compared it against the inspector's reading of
## the same profile would pass whatever either of them did with it; the numbers
## below are written out by hand from `data/parts/`.

const CORE_KEY: StringName = &"core.command.compact.t2"
const STEERED_KEY: StringName = &"mot.wheeled.allroad.t2"
const FIXED_KEY: StringName = &"mot.wheeled.fixed_rear.t2"
const PANEL_KEY: StringName = &"str.panel.medium.t2"
const AUTOCANNON_KEY: StringName = &"eff.ballistic.autocannon_30.t3"
const EDGE_KEY: StringName = &"eff.melee.beam_edge.t4"
const PRIME_MOVER_KEY: StringName = &"pmv.combustion.standard.t2"

## `mot.wheeled.allroad.t2`, by value.
const STEERED_LOCK_DEG: float = 32.0
## `eff.ballistic.autocannon_30.t3`, by value.
const AUTOCANNON_CYCLE_S: float = 0.14


func _rows(key: StringName) -> Array[PartInspector.Row]:
	var def := PartRegistry.definition_by_key(key)
	check_not_null(def, "'%s' is registered" % key)
	if def == null:
		return []
	return PartInspector.rows_for(def)


func _value_for(rows: Array[PartInspector.Row], caption_key: StringName) -> String:
	for row: PartInspector.Row in rows:
		if row.caption_key == caption_key:
			return row.value
	return ""


func _has(rows: Array[PartInspector.Row], caption_key: StringName) -> bool:
	for row: PartInspector.Row in rows:
		if row.caption_key == caption_key:
			return true
	return false


## The four every part has, in the same order for every class, so that a player
## comparing two parts of different classes is comparing the same lines.
func test_every_part_is_described_by_the_same_four_figures_first() -> void:
	for key: StringName in [CORE_KEY, PANEL_KEY, STEERED_KEY, AUTOCANNON_KEY] as Array[StringName]:
		var rows := _rows(key)
		check_true(rows.size() >= 4, "'%s' has at least the common rows" % key)
		if rows.size() < 4:
			continue
		check_eq(rows[0].caption_key, PartInspector.KEY_MASS, "'%s' row 0 is mass" % key)
		check_eq(
			rows[1].caption_key, PartInspector.KEY_INTEGRITY, "'%s' row 1 is integrity" % key
		)
		check_eq(rows[2].caption_key, PartInspector.KEY_ARMOUR, "'%s' row 2 is armour" % key)
		check_eq(rows[3].caption_key, PartInspector.KEY_COST, "'%s' row 3 is cost" % key)
		check_ne(rows[0].value, "", "'%s' mass is formatted" % key)


## A part that draws no power gets no power row. A column of zeroes is worse than
## a shorter list: it reads as a figure the part has and does not use.
func test_a_figure_a_part_does_not_have_is_not_shown() -> void:
	var panel := _rows(PANEL_KEY)
	check_false(
		_has(panel, PartInspector.KEY_POWER_DRAW), "a panel draws nothing, so no draw row"
	)
	check_false(
		_has(panel, PartInspector.KEY_POWER_SUPPLY), "and supplies nothing"
	)
	var cell := _rows(&"cel.static.standard.t3")
	check_true(
		_has(cell, PartInspector.KEY_POWER_SUPPLY), "an Energy Cell's supply is shown"
	)


## The row that answers a real question. Doc 05 ships two wheeled rows that
## differ in nothing a player can see except this, and an Assembly on which
## everything steers crabs instead of turning.
func test_a_steered_contact_and_a_fixed_one_read_differently() -> void:
	var steered := _rows(STEERED_KEY)
	var fixed := _rows(FIXED_KEY)
	var steered_value := _value_for(steered, PartInspector.KEY_STEERING)
	var fixed_value := _value_for(fixed, PartInspector.KEY_STEERING)
	check_ne(steered_value, "", "the steered row has a steering value")
	check_ne(fixed_value, "", "and so does the fixed one")
	check_ne(
		steered_value,
		fixed_value,
		"and they differ: '%s' against '%s'" % [steered_value, fixed_value]
	)
	check_true(
		steered_value.contains(str(int(STEERED_LOCK_DEG))),
		"the steered row names its %d° lock: '%s'" % [int(STEERED_LOCK_DEG), steered_value]
	)


## A melee module and a ballistic one are described by different figures.
## Showing a muzzle velocity for an edge would be showing a zero.
func test_an_edge_and_an_autocannon_are_described_differently() -> void:
	var gun := _rows(AUTOCANNON_KEY)
	var edge := _rows(EDGE_KEY)

	check_true(_has(gun, PartInspector.KEY_MUZZLE), "the autocannon names a muzzle velocity")
	check_true(_has(gun, PartInspector.KEY_TRAVERSE), "and its traverse")
	check_true(_has(gun, PartInspector.KEY_RECOIL), "and its recoil")
	check_false(_has(gun, PartInspector.KEY_REACH), "and has no reach")

	check_true(_has(edge, PartInspector.KEY_REACH), "the edge names its reach")
	check_true(_has(edge, PartInspector.KEY_STRIKE), "and its strike damage")
	check_false(_has(edge, PartInspector.KEY_MUZZLE), "and has no muzzle velocity")
	check_false(_has(edge, PartInspector.KEY_RECOIL), "and no recoil")


## An arc is shown as its two stops. A single number cannot say that the shipped
## module looks 34° up and only 8° down, which is the constraint that decides
## where on a build it can usefully go.
func test_an_arc_is_shown_as_both_of_its_stops() -> void:
	var elevation := _value_for(_rows(AUTOCANNON_KEY), PartInspector.KEY_ELEVATION)
	check_true(elevation.contains("/"), "the elevation names two stops: '%s'" % elevation)
	check_true(elevation.contains("-"), "one of which is negative: '%s'" % elevation)


func test_a_prime_mover_names_its_shaft_torque() -> void:
	check_true(
		_has(_rows(PRIME_MOVER_KEY), PartInspector.KEY_TORQUE),
		"a Prime Mover is described by what it turns"
	)


func test_a_core_module_names_the_budgets_it_sets() -> void:
	var core := _rows(CORE_KEY)
	check_true(_has(core, PartInspector.KEY_SPEED_CAP), "the speed cap")
	check_true(_has(core, PartInspector.KEY_MOUNT_BUDGET), "the mount budget")
	check_true(_has(core, PartInspector.KEY_POWER_CAPACITY), "the power capacity")
	check_true(_has(core, PartInspector.KEY_MASS_TOLERANCE), "and the mass tolerance")


## Doc 11 §4.3's first row on a chassis, and the only figure on the card that
## decides what may be bolted on.
##
## Asserted as a [i]difference[/i] between the four shipped chassis rather than
## against a string: the claim is that a player can tell them apart by reading
## the card, which a row printing one constant for every mask would satisfy on
## any single part.
func test_a_core_module_says_which_families_it_carries() -> void:
	var command := _value_for(_rows(CORE_KEY), PartInspector.KEY_CARRIES)
	var strider := _value_for(_rows(&"core.ambulatory.strider.t3"), PartInspector.KEY_CARRIES)
	var lifter := _value_for(_rows(&"core.rotary.lifter.t3"), PartInspector.KEY_CARRIES)
	var hauler := _value_for(_rows(&"core.tracked.hauler.t3"), PartInspector.KEY_CARRIES)
	check_true(command.length() > 0, "the command core names what it takes: '%s'" % command)
	check_ne(strider, lifter, "a limb chassis and a disc chassis do not read the same")
	check_ne(strider, hauler, "nor a limb chassis and a tracked one")
	check_ne(command, hauler, "nor a wheeled chassis and a tracked one")
	# [b]The command core used to be the two-family one and no longer is.[/b]
	# `CHASSIS_GROUND_TRANSITIONAL` is retired — doc 01 §7.3's Prime Mover mask is
	# what finally made a vestigial family bit cost something — so the proof that
	# this row is a *list* rather than a single name is now built from a mask
	# rather than read off a shipped part. Every shipped chassis declares one
	# family, which is the design; the row still has to handle two.
	check_true(
		PartInspector.chassis_families(
			PartEnums.CHASSIS_WHEELED | PartEnums.CHASSIS_TRACKED
		).length() > hauler.length(),
		"a two-family mask reads longer than a one-family mask: '%s' against '%s'"
			% [command, hauler]
	)


## Both directions of the join, on masks rather than on parts, because no shipped
## chassis authors an empty one and the row a player would read off it is the
## half a test can still make.
func test_the_family_list_names_every_bit_and_says_so_when_there_are_none() -> void:
	var wheeled := PartInspector.chassis_families(PartEnums.CHASSIS_WHEELED)
	var tracked := PartInspector.chassis_families(PartEnums.CHASSIS_TRACKED)
	var both := PartInspector.chassis_families(PartEnums.CHASSIS_WHEELED | PartEnums.CHASSIS_TRACKED)
	check_true(both.contains(wheeled), "the pair contains the wheeled name")
	check_true(both.contains(tracked), "and the tracked one")
	check_ne(
		PartInspector.chassis_families(0), "", "a chassis admitting nothing still reads as something"
	)


## Every caption and every family name has to exist in the string table, or the
## player reads a key. Through [method TranslationServer.translate], because the
## table the game loads is the compiled one.
func test_every_chassis_family_name_is_translated() -> void:
	for key: StringName in PartInspector.CHASSIS_MODE_KEYS:
		check_ne(InputPrompt.tr_key(key), String(key), "'%s' is in the string table" % key)
	for key: StringName in [
		PartInspector.KEY_CARRIES, PartInspector.KEY_NONE, PartInspector.KEY_LIST_SEPARATOR
	] as Array[StringName]:
		check_ne(InputPrompt.tr_key(key), String(key), "'%s' is in the string table" % key)


## The table is indexed by [enum PartEnums.MotiveKind] and has to stay in step
## with it. One entry out of order names every part after it wrongly, and it
## reads as a data error in the parts rather than as a transposition here.
func test_the_locomotion_table_is_the_length_of_the_enum() -> void:
	check_eq(
		PartInspector.MOTIVE_KIND_KEYS.size(),
		PartEnums.MOTIVE_KIND_COUNT,
		"one key per motive kind"
	)
	# Asserted through a shipped part rather than by reading the table back: the
	# claim is that the disc's row says "rotor", not that index 6 holds the rotor
	# key.
	var disc := _value_for(_rows(&"mot.rotor.coaxial_mid.t3"), PartInspector.KEY_FAMILY)
	var limb := _value_for(_rows(&"mot.limb.strider.t4"), PartInspector.KEY_FAMILY)
	var track := _value_for(_rows(&"mot.tracked.short_bogie.t2"), PartInspector.KEY_FAMILY)
	check_ne(disc, limb, "a disc and a limb do not read the same")
	check_ne(limb, track, "nor a limb and a track")
	check_ne(disc, track, "nor a disc and a track")


## Every row is bounded, because the dock lives above the stat panel and a list
## that grows without limit pushes it off the screen.
func test_no_part_produces_more_rows_than_the_dock_shows() -> void:
	for id: int in range(1, PartRegistry.part_count() + 1):
		var def := PartRegistry.definition(id)
		if def == null:
			continue
		check_true(
			PartInspector.rows_for(def).size() <= PartInspector.MAX_ROWS,
			"'%s' fits the dock: %d rows" % [def.part_key, PartInspector.rows_for(def).size()]
		)


func test_nothing_selected_produces_no_rows() -> void:
	check_eq(PartInspector.rows_for(null).size(), 0, "a null definition describes nothing")
