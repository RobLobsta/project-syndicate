extends TestCase
## [AmmoLedger] — doc 07 §9.2's per-Assembly, per-projectile-type ammunition
## stores.
##
## The class had no test file. Session 17's sweep found it by deleting the
## subtraction out of [method AmmoLedger.consume] — leaving a store that is drawn
## from and never falls — and all 56 files stayed green.
##
## The reason is the same shape as §2.0's bound that nothing reached. Every
## engagement in [code]tests/physics/[/code] spawns with
## [constant AmmoLedger.UNLIMITED], and [method AmmoLedger.consume] returns on
## the sentinel before it reaches the line that does the work. The one fixture
## with a finite store — [code]test_duel.gd[/code], at 400 rounds — fires about
## thirty of them and never asks what is left. So the finite path, which is the
## only path the rule lives on, was never executed by anything that looked at the
## result.
##
## The distinction §9.2 draws between "never had any" and "fired them all" is
## asserted here in both directions, because it is the one that decides whether a
## module is out of ammunition or was never given a magazine, and the two are one
## integer apart in the store.

const ASSEMBLY_A := 11
const ASSEMBLY_B := 12

## Two ids standing in for two projectile types. The ledger is keyed on the id
## and never resolves a [StringName], so a registry is not needed to test it.
const ROUND_AP := 0
const ROUND_HE := 1


func _ledger() -> AmmoLedger:
	return AmmoLedger.new()


## ===== GRANTING AND HOLDING ============================================


func test_a_fresh_ledger_holds_nothing() -> void:
	var ammo := _ledger()
	check_eq(ammo.rounds_stored(ASSEMBLY_A, ROUND_AP), 0, "no store, no rounds")
	check_false(ammo.has_rounds(ASSEMBLY_A, ROUND_AP), "and nothing to fire")


func test_granting_rounds_adds_to_what_was_already_held() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_A, ROUND_AP, 30)
	check_eq(ammo.rounds_stored(ASSEMBLY_A, ROUND_AP), 30, "the first grant")
	ammo.add(ASSEMBLY_A, ROUND_AP, 12)
	check_eq(ammo.rounds_stored(ASSEMBLY_A, ROUND_AP), 42, "adds rather than replaces")


## §9.2: the store is per projectile type. Two modules firing the same round draw
## from one store; two firing different rounds do not.
func test_stores_are_kept_per_projectile_type() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_A, ROUND_AP, 30)
	ammo.add(ASSEMBLY_A, ROUND_HE, 5)
	check_eq(ammo.rounds_stored(ASSEMBLY_A, ROUND_AP), 30, "the armour-piercing store")
	check_eq(ammo.rounds_stored(ASSEMBLY_A, ROUND_HE), 5, "and the other one, independently")


## And per Assembly. A shared ledger is what the match scene hands to every
## Effector Module in the game, so a leak between two Assemblies here would be a
## build resupplying itself by standing next to an enemy.
func test_stores_are_kept_per_assembly() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_A, ROUND_AP, 30)
	check_eq(ammo.rounds_stored(ASSEMBLY_B, ROUND_AP), 0, "the other Assembly has its own store")
	check_false(ammo.has_rounds(ASSEMBLY_B, ROUND_AP), "and cannot fire from this one")


## ===== CONSUMPTION =====================================================


## The rule the sweep deleted. A store that is drawn from falls by what was
## taken — with the subtraction removed this reads 30 and nothing else in the
## suite changes.
func test_consuming_reduces_a_finite_store() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_A, ROUND_AP, 30)
	check_eq(ammo.consume(ASSEMBLY_A, ROUND_AP, 4), 4, "four rounds were taken")
	check_eq(ammo.rounds_stored(ASSEMBLY_A, ROUND_AP), 26, "and four fewer remain")


## §9.2 returns the shortfall rather than refusing outright, so a burst that runs
## the store dry mid-way fires what is there instead of nothing at all.
func test_a_burst_that_outruns_the_store_fires_what_is_left() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_A, ROUND_AP, 3)
	check_eq(ammo.consume(ASSEMBLY_A, ROUND_AP, 10), 3, "only three were there to take")
	check_eq(ammo.rounds_stored(ASSEMBLY_A, ROUND_AP), 0, "and the store is empty, not negative")


## The distinction §9.2 exists to draw, asserted from both sides. An Assembly
## that has fired everything and one that was never issued anything are one
## integer apart, and only one of them should ever be resupplied.
func test_an_emptied_store_is_distinguishable_from_no_store() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_A, ROUND_AP, 2)
	ammo.consume(ASSEMBLY_A, ROUND_AP, 2)
	check_false(ammo.has_rounds(ASSEMBLY_A, ROUND_AP), "an emptied store cannot fire")
	check_eq(ammo.rounds_stored(ASSEMBLY_A, ROUND_AP), 0, "and reads zero")
	check_eq(
		ammo.consume(ASSEMBLY_A, ROUND_AP, 1), 0,
		"and yields nothing when drawn from again"
	)
	check_eq(
		ammo.rounds_stored(ASSEMBLY_B, ROUND_AP), 0,
		"which is the same number an Assembly that was never issued any reads"
	)


## ===== THE UNLIMITED SENTINEL ==========================================


func test_an_unlimited_store_always_has_rounds() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_A, ROUND_AP, AmmoLedger.UNLIMITED)
	check_true(ammo.has_rounds(ASSEMBLY_A, ROUND_AP), "an unlimited store is never dry")
	check_eq(ammo.consume(ASSEMBLY_A, ROUND_AP, 50), 50, "and yields whatever is asked of it")
	check_true(ammo.has_rounds(ASSEMBLY_A, ROUND_AP), "however much is taken")


## The comment on [method AmmoLedger.add] states the trap: adding to the sentinel
## would quietly turn an unlimited store into a finite one of nineteen.
func test_granting_to_an_unlimited_store_leaves_it_unlimited() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_A, ROUND_AP, AmmoLedger.UNLIMITED)
	ammo.add(ASSEMBLY_A, ROUND_AP, 20)
	check_eq(
		ammo.rounds_stored(ASSEMBLY_A, ROUND_AP), AmmoLedger.UNLIMITED,
		"twenty rounds on top of an unlimited store is still unlimited"
	)


func test_declaring_a_finite_store_unlimited_replaces_it() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_A, ROUND_AP, 20)
	ammo.add(ASSEMBLY_A, ROUND_AP, AmmoLedger.UNLIMITED)
	check_eq(
		ammo.rounds_stored(ASSEMBLY_A, ROUND_AP), AmmoLedger.UNLIMITED,
		"the sentinel replaces rather than adding to twenty"
	)


## ===== HOUSEKEEPING ====================================================


## Without this the ledger is the one structure in the combat layer that grows
## for the life of the process: assembly ids are never reused.
func test_forgetting_an_assembly_drops_its_stores() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_A, ROUND_AP, 30)
	ammo.add(ASSEMBLY_A, ROUND_HE, 5)
	ammo.add(ASSEMBLY_B, ROUND_AP, 7)
	ammo.forget(ASSEMBLY_A)
	check_eq(ammo.rounds_stored(ASSEMBLY_A, ROUND_AP), 0, "every store the Assembly held is gone")
	check_eq(ammo.rounds_stored(ASSEMBLY_A, ROUND_HE), 0, "on every projectile type")
	check_eq(ammo.rounds_stored(ASSEMBLY_B, ROUND_AP), 7, "and nobody else's was touched")


## Invariant I-9. Nothing in the firing path iterates this, but a diagnostic that
## does must see the same order on the server and on a client.
func test_assembly_ids_come_back_ascending() -> void:
	var ammo := _ledger()
	ammo.add(ASSEMBLY_B, ROUND_AP, 1)
	ammo.add(ASSEMBLY_A, ROUND_AP, 1)
	check_eq(
		ammo.assembly_ids(), PackedInt32Array([ASSEMBLY_A, ASSEMBLY_B]),
		"ascending, whatever order the stores were created in"
	)
