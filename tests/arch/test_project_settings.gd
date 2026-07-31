extends TestCase
## Pins the [code]project.godot[/code] settings that [code]CLAUDE.md[/code] §11
## marks as requiring an architecture review before they change.
##
## These are asserted through [ProjectSettings] rather than by grepping the
## file. Godot omits any setting whose value equals the engine default when it
## rewrites [code]project.godot[/code], so a setting can be absent from the file
## and still be in force — and a future engine default change would then flip
## project behaviour with an empty diff. Reading the effective value catches
## exactly that case; grepping the text would report a false failure today and a
## false pass tomorrow.


func test_physics_tick_rate_is_sixty() -> void:
	check_eq(
		int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)),
		SyndicateConstants.PHYSICS_HZ,
		"physics tick rate must match SyndicateConstants.PHYSICS_HZ"
	)


func test_physics_jitter_fix_is_disabled() -> void:
	# docs/DYNAMIC_MASS_PHYSICS.md §10.1: jitter fix re-times physics steps
	# against render frames, which desynchronises the fixed-tick simulation the
	# network layer assumes.
	check_approx(
		float(ProjectSettings.get_setting("physics/common/physics_jitter_fix", -1.0)),
		0.0,
		"physics jitter fix must be 0.0"
	)


func test_solver_iteration_count() -> void:
	check_eq(
		int(ProjectSettings.get_setting("physics/3d/solver/solver_iterations", 0)),
		12,
		"3D solver iterations must be 12"
	)


func test_stretch_configuration() -> void:
	# docs/RESPONSIVE_GARAGE_UI.md §2.1: canvas_items + expand is the only
	# correct combination. viewport mode letterboxes on ultrawide and blurs
	# text; keep crops.
	check_eq(
		String(ProjectSettings.get_setting("display/window/stretch/mode", "")),
		"canvas_items",
		"stretch mode"
	)
	check_eq(
		String(ProjectSettings.get_setting("display/window/stretch/aspect", "")),
		"expand",
		"stretch aspect"
	)
	check_eq(
		String(ProjectSettings.get_setting("display/window/stretch/scale_mode", "")),
		"fractional",
		"stretch scale mode; integer snaps at non-integer device pixel ratios"
	)


func test_physics_dt_constant_agrees_with_the_tick_rate() -> void:
	check_approx(
		SyndicateConstants.PHYSICS_DT,
		1.0 / float(SyndicateConstants.PHYSICS_HZ),
		"PHYSICS_DT must be the reciprocal of PHYSICS_HZ"
	)
