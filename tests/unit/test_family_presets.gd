extends TestCase
## One reference build per locomotion family, and the assertion that each of them
## is a build a player could actually make.
##
## [b]This file exists so that a physics change has five known machines to be
## measured against rather than one.[/b] Until now `StarterBlueprint` offered the
## wheeled skirmisher and nothing else, so every other family's reference layout
## lived only in `tests/combat_arena.gd` — reachable from the suite and from
## nothing a player ever touches.
##
## Two things are asserted and the second is what keeps the first honest.
##
## [enum]
## [*] Every preset [b]validates[/b], placement by placement, through the same
##     [PlacementValidator] chain the garage uses. A preset that has drifted out
##     of legality is not a preset, and the failure names the part and the reject
##     code rather than reporting a blueprint that "did not apply".
## [*] Every preset agrees [b]part for part[/b] with the arena recipe of the same
##     name. CLAUDE.md §1.1 tolerates exactly two copies of a shipped build —
##     this one, which is what a player gets, and the arena, which is what the
##     suite measures — and two copies with nothing comparing them are two
##     different machines within a session.
## [/enum]

## Preset name -> the arena recipe that must contain the same parts.
##
## [b]`skirmisher` is deliberately not in this table.[/b] It is the historical
## shipped starter and no recipe matches it: it carries an Energy Cell that
## [constant CombatArena.Recipe.WHEELED_REPEATER] does not and a repeater where
## [constant CombatArena.Recipe.WHEELED_LIGHT] carries an autocannon. That is
## worth knowing rather than worth forcing — the build a player opens the garage
## on has never been one of the builds the suite fights with — and it is recorded
## in `HANDOFF.md` rather than papered over by pairing it with the nearest recipe.
static func pairs() -> Dictionary:
	return {
		&"utility": CombatArena.Recipe.WHEELED_UTILITY,
		&"tracked": CombatArena.Recipe.TRACKED,
		&"ambulatory": CombatArena.Recipe.AMBULATORY,
		&"biped": CombatArena.Recipe.BIPED,
		&"rotary": CombatArena.Recipe.ROTARY,
	}

var _contexts: Array[BuildContext] = []


func after_all() -> void:
	# Physics server RIDs are not reference counted (LEARNED_FACTS.md §1 fact 21):
	# a context dropped without this leaks a space that keeps stepping for the
	# life of the process.
	for ctx: BuildContext in _contexts:
		ctx.dispose()
	_contexts.clear()


## Every preset builds, and the reject names the placement that did not.
func test_every_preset_is_a_build_a_player_could_make() -> void:
	var presets := StarterBlueprint.presets()
	check_eq(presets.size(), pairs().size() + 1, "one preset per family, and the starter")
	for name: StringName in presets:
		var bp: Blueprint = presets[name]
		var ctx := _context()
		# A recorder rather than a captured local: a GDScript lambda captures by
		# value, so a closure writing to a `var` outside it writes to its own copy
		# and the assertion reads the value it started with (fact 68).
		var reasons := PackedStringArray()
		var stopped := bp.apply(ctx, func(i: int, key: StringName) -> void:
			reasons.append("placement %d (%s): %s" % [i, bp.placements[i].part_key, key])
		)
		check_eq(
			stopped, Blueprint.APPLIED_CLEANLY,
			"the %s preset applies cleanly%s"
				% [name, "" if reasons.is_empty() else " — " + ", ".join(reasons)]
		)
		check_true(
			ctx.committed_definitions().size() > 1,
			"and it is a machine rather than a lone Core Module: %d parts"
				% ctx.committed_definitions().size()
		)


## The presets and the arena are the same machines. A layout that moves in one
## and not the other fails here rather than becoming two builds with one name.
func test_each_preset_is_the_machine_the_arena_fights_with() -> void:
	var arena := CombatArena.new()
	for name: StringName in pairs():
		var preset_parts := _census(_applied(StarterBlueprint.presets()[name]))
		var arena_ctx := _context()
		arena.lay_out(arena_ctx, int(pairs()[name]))
		var arena_parts := _census(arena_ctx)
		check_eq(
			preset_parts.size(), arena_parts.size(),
			"the %s preset uses the same part keys as its recipe" % name
		)
		for key: StringName in arena_parts:
			check_eq(
				int(preset_parts.get(key, 0)), int(arena_parts[key]),
				"%s: %d of %s, as the arena places" % [name, arena_parts[key], key]
			)


func _context() -> BuildContext:
	var ctx := BuildContext.with_physics(1)
	_contexts.append(ctx)
	return ctx


func _applied(bp: Blueprint) -> BuildContext:
	var ctx := _context()
	bp.apply(ctx)
	return ctx


## Part key -> how many of it [param ctx] holds.
func _census(ctx: BuildContext) -> Dictionary:
	var out: Dictionary = {}
	for def: PartDefinition in ctx.committed_definitions():
		out[def.part_key] = int(out.get(def.part_key, 0)) + 1
	return out
