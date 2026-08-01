extends TestCase
## [BuildBudgetLedger] — the incremental totals §7.4 checks against.
##
## Every counter here is maintained by add/remove pairs, so the only failure
## mode that matters is asymmetry: a remove that subtracts less than its add
## contributed leaves budget permanently consumed by a part that is no longer in
## the Assembly. Nothing reports this. The player sees a placement they can see
## is legal being refused, and there is no way to tell from the symptom which
## edit caused it.
##
## The defence is [method BuildBudgetLedger.recompute_from]: after an arbitrary
## sequence of edits, the incremental totals must equal a full re-sum.

const MOUNT_BUDGET := 28
const POWER_CAPACITY := 240.0


func test_starts_at_zero() -> void:
	var led := BuildBudgetLedger.new()
	check_eq(led.mount_used, 0, "no mounts used")
	check_approx(led.power_draw_pu, 0.0, "no power drawn")
	check_approx(led.total_mass_kg, 0.0, "no mass")
	check_eq(led.class_counts.size(), PartEnums.PART_CLASS_COUNT, "one counter per class")
	check_null(led.core_profile, "no Core Module yet")


func test_ceilings_are_zero_before_a_core_is_placed() -> void:
	# Correct rather than merely convenient: nothing but a Core Module may be
	# placed first, so every budget a non-core part could consume is genuinely
	# zero until one exists.
	var led := BuildBudgetLedger.new()
	check_eq(led.mount_budget(), 0, "no mount budget without a Core Module")
	check_approx(led.power_available_pu(), 0.0, "no power available either")


func test_core_publishes_the_ceilings() -> void:
	var led := BuildBudgetLedger.new()
	led.add(_core())
	check_eq(led.mount_budget(), MOUNT_BUDGET, "the Core Module's mount budget is in force")
	check_approx(led.power_available_pu(), POWER_CAPACITY, "and its power capacity")
	check_eq(led.count_of_class(int(PartEnums.PartClass.CORE_MODULE)), 1, "one Core Module")


func test_power_plants_add_to_available_supply() -> void:
	# §7.4's inequality is draw <= core capacity + Σ supply, so a Power Plant
	# raises the ceiling rather than lowering the draw.
	var led := BuildBudgetLedger.new()
	led.add(_core())
	led.add(_part(PartEnums.PartClass.POWER_PLANT, 0, 0.0, 120.0))
	check_approx(
		led.power_available_pu(), POWER_CAPACITY + 120.0, "supply adds to the core capacity"
	)
	check_approx(led.power_draw_pu, 0.0, "and does not draw")


func test_add_and_remove_are_symmetric() -> void:
	var led := BuildBudgetLedger.new()
	var part := _part(PartEnums.PartClass.EFFECTOR_MODULE, 3, 45.0, 0.0)
	led.add(_core())
	var before := _snapshot(led)
	led.add(part)
	check_ne(_snapshot(led), before, "adding a part changes the totals")
	led.remove(part)
	check_eq(_snapshot(led), before, "removing it restores them exactly")


func test_incremental_totals_match_a_full_resum() -> void:
	# The real guard. An arbitrary edit sequence, then the incremental answer
	# compared against the O(n) re-sum of what is actually left.
	var led := BuildBudgetLedger.new()
	var live: Array[PartDefinition] = []

	var core := _core()
	led.add(core)
	live.append(core)

	var parts: Array[PartDefinition] = []
	for i in 12:
		parts.append(_part(PartEnums.PartClass.STRUCTURAL_COMPONENT, 1 + i % 3, float(i), 0.0))

	for p: PartDefinition in parts:
		led.add(p)
		live.append(p)
	# Remove every third, in the order a player would have clicked them.
	var removed: Array[int] = [9, 6, 3, 0]
	for i: int in removed:
		led.remove(parts[i])
		live.remove_at(live.find(parts[i]))

	var expected := BuildBudgetLedger.new()
	expected.recompute_from(live)
	check_eq(
		_snapshot(led), _snapshot(expected),
		"incremental totals equal a full re-sum after 12 adds and 4 removes"
	)


func test_removing_the_core_withdraws_its_ceilings() -> void:
	var led := BuildBudgetLedger.new()
	var core := _core()
	led.add(core)
	led.remove(core)
	check_null(led.core_profile, "the profile is released")
	check_eq(led.mount_budget(), 0, "the mount budget goes with it")
	check_approx(led.power_available_pu(), 0.0, "so does the power capacity")


func test_clear_resets_everything() -> void:
	var led := BuildBudgetLedger.new()
	led.add(_core())
	led.add(_part(PartEnums.PartClass.MOTIVE_ASSEMBLY, 2, 30.0, 0.0))
	led.clear()
	check_eq(_snapshot(led), _snapshot(BuildBudgetLedger.new()), "a cleared ledger is a new one")


## ===== HELPERS =========================================================
## Synthetic definitions rather than the shipped parts: a ledger test that loads
## real data fails for reasons unrelated to the arithmetic it is checking, and
## the arithmetic is the whole subject.


func _core() -> PartDefinition:
	var def := _part(PartEnums.PartClass.CORE_MODULE, 0, 0.0, 0.0)
	var profile := CoreModuleProfile.new()
	profile.mount_budget = MOUNT_BUDGET
	profile.power_capacity_pu = POWER_CAPACITY
	def.core_profile = profile
	def.mass_kg = 380.0
	return def


func _part(
	part_class: PartEnums.PartClass, mount: int, draw: float, supply: float
) -> PartDefinition:
	var def := PartDefinition.new()
	def.part_class = part_class
	def.mount_weight = mount
	def.power_draw_pu = draw
	def.power_supply_pu = supply
	def.mass_kg = 34.0
	def.build_cost = 60
	return def


## Every total in one comparable value, so an assertion covers the fields a
## future counter is added to as well as the ones present today.
func _snapshot(led: BuildBudgetLedger) -> Array:
	return [
		led.class_counts,
		led.mount_used,
		snappedf(led.power_draw_pu, 0.0001),
		snappedf(led.power_supply_pu, 0.0001),
		snappedf(led.total_mass_kg, 0.0001),
		led.total_build_cost,
	]
