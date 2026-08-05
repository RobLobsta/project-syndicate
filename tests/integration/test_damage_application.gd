extends TestCase
## [method DamageResolver.apply] against live parts — the instance path, which
## the pure-static tests cannot reach.
##
## [code]tests/unit/test_damage_resolver.gd[/code] covers doc 08 §4 to §8 as
## arithmetic over synthetic inputs, and covers it well. What it cannot cover is
## anything [method DamageResolver.apply] reads off a [PartInstanceState],
## because a static is handed its armour figure and never asks where the figure
## came from. Session 17's sweep found two rules living in exactly that gap, and
## both survived deletion against all 56 files including six engagements between
## real Assemblies:
##
## [b]§8.2's last row[/b] — armour rating degrades with the integrity band. The
## document states the consequence in prose: "a battered panel becomes
## progressively easier to penetrate ... the first hits are absorbed, later hits
## go through." The engagements do drive parts through the bands, but they assert
## kill counts and tick windows, and a fight in which armour never softens is
## still a fight somebody wins.
##
## [b]The integrity floor[/b] — [code]maxf(0.0, integrity - effective)[/code].
## Two other guards make it look redundant: [method
## PartInstanceState.integrity_fraction] clamps, and [code]_destroy_part[/code]
## assigns [code]0.0[/code] unconditionally. It is not redundant, and the window
## in which it is observable is one line wide — §8.4 emits
## [signal EventBusService.part_band_changed] [i]before[/i] the destruction path
## runs, so every subscriber to that signal sees the raw subtraction. That is
## where this file looks, and it is the only place it can be seen from.

const CORE_KEY := &"core.command.compact.t2"
const PANEL_KEY := &"str.panel.medium.t2"

const CORE_ORIGIN := Vector3i(24, 4, 24)
## Two Structural Components on the deck. The upper one is battered and later
## killed; the lower one is left fresh. Killing the upper one severs nothing, so
## no detachment chain is needed to keep the fixture honest.
const FRESH_ORIGIN := Vector3i(24, 8, 24)
const BATTERED_ORIGIN := Vector3i(24, 9, 24)

const ASSEMBLY := 7
const FRESH_SLOT := 1
const BATTERED_SLOT := 2

## ===== THE PUBLISHED FIGURES, QUOTED ===================================
## Written out by hand rather than imported. A test that reads the same constant
## its subject reads asserts nothing — change the constant and the expectation
## moves with it (§2's first lesson).

## Doc 08 §8.2's last row, "All classes — Armour rating multiplier".
const DOC_ARMOUR_NOMINAL: float = 1.00
const DOC_ARMOUR_IMPAIRED: float = 0.80

## Doc 01 §10's authored figures for [code]str.panel.medium.t2[/code].
const DOC_PANEL_ARMOUR: float = 14.0
const DOC_PANEL_INTEGRITY: float = 380.0
const DOC_PANEL_KINETIC_RESISTANCE: float = 0.18

## ===== THE PROBE PACKET ================================================

## Chosen so that both bands land inside §4.3's quadratic partial band, where the
## curve is steepest and the armour multiplier therefore has the most to say. A
## penetration comfortably above or below every shipped armour rating would put
## both readings on a flat part of the curve, and the two would differ by nothing
## a tolerance could separate.
const PROBE_PENETRATION: float = 10.5
const PROBE_RAW: float = 100.0

## Square on, so §4.1's angle term is exactly 1.0 and §4.2 cannot deflect the
## probe out of the measurement.
const PROBE_NORMAL := Vector3.UP
const PROBE_INCOMING := Vector3.DOWN

## NOMINAL. A_eff = 14.0 x 1.00 = 14.0; rho = 10.5 / 14.0 = 0.75;
## t = (0.75 - 0.55) / 0.45 = 0.444444; 0.42 x t^2 = 0.0829630;
## and 100.0 x (1 - 0.18) x 0.0829630 = 6.80297.
const EXPECTED_FRESH_DAMAGE: float = 6.80296

## IMPAIRED. A_eff = 14.0 x 0.80 = 11.2; rho = 10.5 / 11.2 = 0.9375;
## t = (0.9375 - 0.55) / 0.45 = 0.861111; 0.42 x t^2 = 0.3114352;
## and 82.0 x 0.3114352 = 25.53769.
const EXPECTED_BATTERED_DAMAGE: float = 25.53769

## The float32 round-trip on `resistance` alone is worth ~1e-7 relative (§3.16),
## and the expectations above are written to five decimals.
const DAMAGE_TOLERANCE: float = 1e-3

## Far past the panel's 380. Without the floor the subtraction leaves integrity
## at roughly -11500, which is what the §8.4 subscriber below would be handed.
const OVERKILL_RAW: float = 10000.0
const OVERKILL_PENETRATION: float = 400.0

var _ctx: BuildContext = null
var _runtime: AssemblyRuntime = null
var _registry: AssemblyRegistry = null
var _resolver: DamageResolver = null

## Captured while the fixture is built, never in a test method: the runner sorts
## method names, and the probes themselves move the integrity every later
## assertion depends on (§3.42).
var _fresh_band_at_probe: PartEnums.IntegrityBand = PartEnums.IntegrityBand.NOMINAL
var _battered_band_at_probe: PartEnums.IntegrityBand = PartEnums.IntegrityBand.NOMINAL
var _fresh_damage: float = -1.0
var _battered_damage: float = -1.0

## What a §8.4 subscriber saw at the instant the part was announced destroyed.
var _destruction_announced: bool = false
var _integrity_at_announcement: float = INF


func before_all() -> void:
	_registry = AssemblyRegistry.new()
	_ctx = BuildContext.with_physics(ASSEMBLY)
	var core := PartRegistry.definition_by_key(CORE_KEY)
	var panel := PartRegistry.definition_by_key(PANEL_KEY)
	PlacementValidator.commit(_ctx, PlacementCandidate.create(core, CORE_ORIGIN, 0))
	PlacementValidator.commit(_ctx, PlacementCandidate.create(panel, FRESH_ORIGIN, 0))
	PlacementValidator.commit(_ctx, PlacementCandidate.create(panel, BATTERED_ORIGIN, 0))

	_runtime = AssemblyRuntime.new()
	EventBus.get_tree().root.add_child(_runtime)
	_runtime.adopt(_ctx)
	_registry.register(_runtime)

	_resolver = DamageResolver.new()
	_resolver.registry = _registry
	EventBus.get_tree().root.add_child(_resolver)

	EventBus.part_band_changed.connect(_on_part_band_changed)

	# Batter one of the two down into IMPAIRED through real packets, so the band
	# is reached the way a match reaches it — the resolver computes it, notices
	# the transition, and caches it. Assigning integrity would skip all three.
	_batter(BATTERED_SLOT, PartEnums.IntegrityBand.IMPAIRED)

	# Read the bands immediately before the probes, so a failure below can say
	# whether the fixture or the rule is what went wrong.
	_fresh_band_at_probe = _runtime.states[FRESH_SLOT].integrity_band
	_battered_band_at_probe = _runtime.states[BATTERED_SLOT].integrity_band

	_fresh_damage = _probe(FRESH_SLOT)
	_battered_damage = _probe(BATTERED_SLOT)

	# Last, because it ends the part: one round worth many times what is left.
	_overkill(BATTERED_SLOT)


func after_all() -> void:
	EventBus.part_band_changed.disconnect(_on_part_band_changed)
	if _runtime != null:
		_runtime.free()
	if _resolver != null:
		_resolver.free()
	if _ctx != null:
		_ctx.dispose()


## ===== THE FIXTURE CAN ANSWER THE QUESTION =============================

## Asserted first, because every comparison below is meaningless if the two parts
## are not the same definition or are not in the two bands the arithmetic assumes.
func test_the_two_parts_are_one_definition_in_two_different_bands() -> void:
	var fresh := _runtime.definition_at(FRESH_SLOT)
	var battered := _runtime.definition_at(BATTERED_SLOT)
	if not check_not_null(fresh, "the fresh Structural Component is on the Assembly"):
		return
	if not check_not_null(battered, "and so is the battered one"):
		return
	check_eq(battered.part_key, fresh.part_key, "both probes hit the same definition")
	check_approx(
		fresh.armour_rating, DOC_PANEL_ARMOUR,
		"and it carries doc 01 §10's authored armour rating"
	)
	check_approx(fresh.integrity_max, DOC_PANEL_INTEGRITY, "and its authored integrity")
	check_approx(
		fresh.resistance[int(PartEnums.DamageChannel.KINETIC)],
		DOC_PANEL_KINETIC_RESISTANCE,
		"and its authored kinetic resistance", DAMAGE_TOLERANCE
	)
	check_eq(
		_fresh_band_at_probe, PartEnums.IntegrityBand.NOMINAL,
		"the fresh part was still NOMINAL when it was probed"
	)
	check_eq(
		_battered_band_at_probe, PartEnums.IntegrityBand.IMPAIRED,
		"and the battered one had reached IMPAIRED"
	)


## ===== §8.2's LAST ROW =================================================

## The document's prose, as an assertion. This is the direction a dropped
## multiplier cannot satisfy: with the band term gone both probes compute against
## a full 14.0 of armour and the two readings are identical.
func test_the_same_round_does_more_damage_to_the_battered_part() -> void:
	check_true(
		_battered_damage > _fresh_damage,
		"§8.2: later hits go through — %.3f into IMPAIRED against %.3f into NOMINAL"
		% [_battered_damage, _fresh_damage]
	)


## The exact figures, so the test fails on a multiplier that is present but
## wrong, not merely on one that is absent. A direction alone is satisfied by any
## band term below 1.0, including one read from the wrong row of the table.
func test_a_nominal_part_is_struck_for_the_documented_amount() -> void:
	check_approx(
		_fresh_damage, EXPECTED_FRESH_DAMAGE,
		"§4.3 against 14.0 x %.2f of armour" % DOC_ARMOUR_NOMINAL,
		DAMAGE_TOLERANCE
	)


func test_an_impaired_part_is_struck_for_the_documented_amount() -> void:
	check_approx(
		_battered_damage, EXPECTED_BATTERED_DAMAGE,
		"§4.3 against 14.0 x %.2f of armour" % DOC_ARMOUR_IMPAIRED,
		DAMAGE_TOLERANCE
	)


## ===== THE INTEGRITY FLOOR =============================================

## The fixture half again: if the announcement never fired, the assertion below
## is asserting nothing about a value nothing ever produced.
func test_the_overkilled_part_was_announced_destroyed() -> void:
	check_true(
		_destruction_announced,
		"§8.4 announced the transition to DESTROYED"
	)


## What a §8.4 subscriber is handed. With the floor removed this reads about
## -11500 — and every other assertion in the suite stays green, because
## `integrity_fraction` clamps it away one line later and `_destroy_part`
## overwrites it one line after that.
func test_a_subscriber_never_sees_negative_integrity() -> void:
	if not _destruction_announced:
		return
	check_approx(
		_integrity_at_announcement, 0.0,
		"integrity is floored at zero before §8.4 announces the band",
		DAMAGE_TOLERANCE
	)


## ===== FIXTURES ========================================================


func _on_part_band_changed(assembly_id: int, slot: int, _before: int, after: int) -> void:
	if assembly_id != ASSEMBLY or slot != BATTERED_SLOT:
		return
	if after != int(PartEnums.IntegrityBand.DESTROYED):
		return
	_destruction_announced = true
	# Read straight off the state, at the instant the signal fires. This is the
	# whole point of the test: one line later nothing can tell the difference.
	_integrity_at_announcement = _runtime.states[slot].integrity


## Applies the probe packet to [param slot] and returns the integrity it removed.
##
## The packet is identical for both slots by construction — that is the whole
## experiment, so it is built here rather than passed in.
func _probe(slot: int) -> float:
	var outcome := _resolver.apply(_packet(slot, PROBE_RAW, PROBE_PENETRATION))
	return outcome.amount if outcome.was_applied() else -1.0


## Drives [param slot] down to [param target] with rounds that are not the probe.
##
## The penetration here is far past any shipped armour rating on purpose: §4.3's
## surplus bonus is capped, so every one of these packets removes the same
## integrity whatever band it lands in, and the descent cannot be confused with
## the effect this file is measuring.
func _batter(slot: int, target: PartEnums.IntegrityBand) -> void:
	var state: PartInstanceState = _runtime.states[slot]
	for i: int in 200:
		if state.integrity_band == target:
			return
		_resolver.apply(_packet(slot, 40.0, OVERKILL_PENETRATION))


func _overkill(slot: int) -> void:
	_resolver.apply(_packet(slot, OVERKILL_RAW, OVERKILL_PENETRATION))


func _packet(slot: int, raw: float, penetration: float) -> DamagePacket:
	var packet := DamagePacket.new()
	packet.target_assembly_id = ASSEMBLY
	packet.target_slot = slot
	packet.channel = PartEnums.DamageChannel.KINETIC
	packet.raw_amount = raw
	packet.penetration = penetration
	packet.impact_normal_world = PROBE_NORMAL
	packet.incoming_direction = PROBE_INCOMING
	return packet
