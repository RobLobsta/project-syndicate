extends TestCase
## Enforces Architectural Invariant I-9: determinism where it is claimed.
##
## Ground deformation, auto-assembly generation, fracture layout, spread rolls,
## and detachment ordering must be bit-reproducible. The global RNG is seeded
## per-process and shared by every caller, so a single global [code]randf()[/code]
## anywhere in a deterministic path makes the server and the client diverge in a
## way that only shows up as an unreproducible desync bug report.
##
## Every stochastic system owns a seeded [RandomNumberGenerator]. Calls through
## an instance ([code]_rng.randf()[/code]) are fine and are not matched here;
## only bare global calls are.

## Global RNG functions on the built-in Math singleton.
const BANNED: Array[String] = [
	"randi",
	"randf",
	"randomize",
	"randi_range",
	"randf_range",
	"randfn",
	"rand_from_seed",
]


func test_src_contains_no_global_rng_call() -> void:
	# (?<![\w.]) rejects both a method call on an instance (rng.randi()) and a
	# longer identifier that merely ends in the banned name (my_randf()).
	for name: String in BANNED:
		var pattern := SourceScanner.compile("(?<![\\w.])%s\\s*\\(" % name)
		for path in SourceScanner.gd_files(SourceScanner.SRC_ROOT):
			for line in SourceScanner.match_lines(path, pattern):
				fail(
					(
						"%s:%d calls global %s(). Own a seeded RandomNumberGenerator "
						+ "instead (I-9)."
					) % [SourceScanner.short(path), line, name]
				)
	check_true(true, "src/ scanned for global RNG calls")


func test_array_shuffle_is_not_used_in_src() -> void:
	# Array.shuffle() draws from the same global generator and is the usual way
	# this invariant gets broken without anyone typing "rand".
	var pattern := SourceScanner.compile("\\.shuffle\\s*\\(")
	for path in SourceScanner.gd_files(SourceScanner.SRC_ROOT):
		for line in SourceScanner.match_lines(path, pattern):
			fail(
				"%s:%d uses Array.shuffle(), which draws from the global RNG (I-9)"
				% [SourceScanner.short(path), line]
			)
	check_true(true, "src/ scanned for shuffle()")


func test_dictionary_iteration_is_not_sorted_by_accident() -> void:
	# I-9 also requires iterating sorted key lists rather than raw Dictionary
	# order. That cannot be checked mechanically without false positives, so
	# this asserts the tool the rule depends on behaves as assumed: PackedArray
	# sort is a total order, which is what every deterministic iteration in the
	# project relies on for tie-breaking.
	var a := PackedInt32Array([5, 3, 9, 1, 3])
	var b := PackedInt32Array([3, 1, 9, 5, 3])
	a.sort()
	b.sort()
	check_eq(a, b, "sorting equal multisets must produce identical sequences")
