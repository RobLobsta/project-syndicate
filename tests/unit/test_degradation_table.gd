extends TestCase
## [DegradationTable] structural conformance, from
## [code]docs/COMPONENT_HEALTH_DAMAGE.md[/code] §8.3.
##
## This is the table Architectural Invariant I-5 makes every subsystem index. A
## row of the wrong length reads past its end at DESTROYED; a row that is not
## monotonic makes a part better at something for having been damaged; a row that
## does not terminate at zero leaves a destroyed part still contributing. None of
## the three announces itself at runtime, which is why they are checked here.


func test_every_table_is_registered() -> void:
	var tables := DegradationTable.all_tables()
	check_eq(
		tables.size(),
		DegradationTable.TABLE_COUNT,
		"all_tables() lists every table; an unlisted one is checked by nothing"
	)


func test_every_table_has_one_entry_per_band() -> void:
	for name: StringName in DegradationTable.all_tables():
		var table: Array[float] = DegradationTable.all_tables()[name]
		check_eq(
			table.size(),
			PartEnums.INTEGRITY_BAND_COUNT,
			"%s has one entry per integrity band" % name
		)


func test_every_table_terminates_at_zero() -> void:
	for name: StringName in DegradationTable.all_tables():
		var table: Array[float] = DegradationTable.all_tables()[name]
		check_approx(
			table[PartEnums.IntegrityBand.DESTROYED],
			0.0,
			"%s is zero at DESTROYED, so a destroyed part contributes nothing" % name
		)


## Monotonic across the four live bands, in the direction the table's meaning
## demands. The DESTROYED entry is excluded: it is a terminator, and on a
## non-decreasing table like EFF_JAM it drops back to zero by design.
func test_every_table_is_monotonic_in_its_own_direction() -> void:
	for name: StringName in DegradationTable.all_tables():
		var table: Array[float] = DegradationTable.all_tables()[name]
		var rising := DegradationTable.NON_DECREASING.has(name)
		for band: int in PartEnums.IntegrityBand.DESTROYED - 1:
			var a: float = table[band]
			var b: float = table[band + 1]
			if rising:
				check_true(b >= a, "%s rises with damage: [%d]=%f, [%d]=%f" % [name, band, a, band + 1, b])
			else:
				check_true(b <= a, "%s falls with damage: [%d]=%f, [%d]=%f" % [name, band, a, band + 1, b])


## A rising table must actually rise somewhere, and a falling one must actually
## fall. Without this, a table of all 1.0 would satisfy monotonicity in both
## directions and degrade nothing.
func test_every_table_actually_changes() -> void:
	for name: StringName in DegradationTable.all_tables():
		var table: Array[float] = DegradationTable.all_tables()[name]
		check_ne(
			table[PartEnums.IntegrityBand.CRITICAL],
			table[PartEnums.IntegrityBand.NOMINAL],
			"%s differs between NOMINAL and CRITICAL, or it degrades nothing" % name
		)


## The two behaviours the design brief mandates, quoted verbatim from §8.2.
func test_the_two_mandated_behaviours() -> void:
	check_approx(
		DegradationTable.MOTIVE_TRACTION[PartEnums.IntegrityBand.IMPAIRED],
		0.60,
		"a Motive Assembly below 50% integrity loses 40% of its traction"
	)
	check_approx(
		DegradationTable.EFF_JAM[PartEnums.IntegrityBand.CRITICAL],
		0.18,
		"an Effector Module below 30% integrity has an 18% per-shot jam chance"
	)
	check_approx(
		DegradationTable.EFF_JAM[PartEnums.IntegrityBand.IMPAIRED],
		0.0,
		"IMPAIRED never jams; the progression is telegraphed before jams start"
	)


func test_nominal_is_the_identity_except_for_jam() -> void:
	for name: StringName in DegradationTable.all_tables():
		if name == &"EFF_JAM":
			continue
		var table: Array[float] = DegradationTable.all_tables()[name]
		check_approx(
			table[PartEnums.IntegrityBand.NOMINAL],
			1.0,
			"%s at NOMINAL is 1.0, so an undamaged part is unmodified" % name
		)


## The clamp exists for a band arriving from the network as a 3-bit field: a
## corrupt packet must degrade a part rather than crash a server.
func test_multiplier_clamps_out_of_range_bands() -> void:
	check_approx(
		DegradationTable.multiplier(DegradationTable.MOTIVE_TRACTION, -1),
		1.00,
		"a negative band clamps to NOMINAL"
	)
	check_approx(
		DegradationTable.multiplier(DegradationTable.MOTIVE_TRACTION, 99),
		0.00,
		"a band past the end clamps to DESTROYED"
	)
	check_approx(
		DegradationTable.multiplier(DegradationTable.MOTIVE_TRACTION, 2),
		0.60,
		"an in-range band indexes directly"
	)
