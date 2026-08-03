extends TestCase
## Enforces Architectural Invariant I-4: structural evaluation is event-driven.
##
## [ChassisGraph] and the detachment solver recompute connectivity, mass
## properties, strain, and functional degradation only in response to discrete
## events. A per-frame loop over parts reading integrity or attachment is the
## single change most likely to destroy this architecture's performance
## characteristics, because it turns a match with no destruction from zero graph
## CPU time into a fixed per-tick cost that scales with part count.
##
## The rule is enforced by declaration, not by inspection of loop bodies: no
## file in the listed directories may declare a per-frame callback at all.

## Directories where a per-frame callback is a defect by definition.
const EVENT_DRIVEN_DIRS: Array[String] = [
	"res://src/assembly/graph",
	"res://src/assembly/mass",
]

## Files permitted to declare a per-frame callback anywhere in src/, with the
## reason. [code]MatchClock[/code] defines what a tick is, so it cannot react to
## one; [code]InputMethodService[/code] uses [code]_input[/code], which is
## event-driven despite living on the same virtual-method list.
const PER_FRAME_ALLOWLIST: Dictionary = {
	"res://src/autoload/match_clock.gd": "defines the tick that everything else reacts to",
	"res://src/assembly/runtime/assembly_interpolator.gd":
	(
		"doc 05 §10.2: physics_jitter_fix is 0, so the visual transform is "
		+ "genuinely per-render-frame work"
	),
	"res://src/combat/effectors/effector_system.gd":
	(
		"doc 07 §7: the emission loop is per-tick by definition — mounts slew, "
		+ "timers run down, and spread decays every tick. It reads cached band "
		+ "multipliers and never integrity"
	),
	"res://src/combat/projectiles/projectile_system.gd":
	(
		"doc 07 §12.2: integrates flight and sweeps for hits every tick. A "
		+ "round covers 15.7 m per tick at muzzle velocity, so there is no "
		+ "event to react to instead"
	),
	"res://src/ui/match/chase_camera.gd":
	(
		"doc 11 §13.2: follows the interpolated VisualRoot, which is written per "
		+ "render frame. It reads a transform and never integrity, connectivity, "
		+ "or attachment, so I-4's subject is untouched"
	),
	"res://src/ui/hud/reticle.gd":
	(
		"doc 11 §14.3: the brackets draw in and out over real time, which is a "
		+ "continuous value with no event behind it. It redraws only while they "
		+ "are moving and reads nothing but its own state"
	),
	"res://src/ui/hud/match_hud.gd":
	(
		"doc 11 §14.4: decays the damage flash and the event feed against real "
		+ "time. Every value it displays is pushed to it — it holds no Assembly "
		+ "reference and iterates no parts"
	),
	"res://src/motion/motive_system.gd":
	(
		"doc 05 §6.0: a force integrator, not a reactor to structural events. "
		+ "It reads cached band multipliers and never structural state, and "
		+ "§9's dynamic factor is explicitly per-tick work"
	),
}


func test_event_driven_directories_declare_no_per_frame_callback() -> void:
	var pattern := SourceScanner.compile("^\\s*func\\s+_(physics_)?process\\s*\\(")
	for dir: String in EVENT_DRIVEN_DIRS:
		for path in SourceScanner.gd_files(dir):
			var hits := SourceScanner.match_lines(path, pattern)
			for line in hits:
				fail(
					"%s:%d declares a per-frame callback; %s must be event-driven (I-4)"
					% [SourceScanner.short(path), line, SourceScanner.short(dir)]
				)
	# Records that the scan ran even when the directories are still empty, so a
	# vacuous pass is visible in the check count rather than indistinguishable
	# from a real one.
	check_true(true, "event-driven directories scanned")


func test_per_frame_callbacks_in_src_are_accounted_for() -> void:
	var pattern := SourceScanner.compile("^\\s*func\\s+_(physics_)?process\\s*\\(")
	for path in SourceScanner.gd_files(SourceScanner.SRC_ROOT):
		var hits := SourceScanner.match_lines(path, pattern)
		if hits.is_empty():
			continue
		check_true(
			PER_FRAME_ALLOWLIST.has(path),
			(
				"%s declares a per-frame callback at line %d. If this is genuinely "
				+ "per-frame work, add it to PER_FRAME_ALLOWLIST with a reason; "
				+ "otherwise connect to EventBus instead (I-4)."
			) % [SourceScanner.short(path), hits[0]]
		)


func test_allowlist_has_no_stale_entries() -> void:
	var pattern := SourceScanner.compile("^\\s*func\\s+_(physics_)?process\\s*\\(")
	for path: String in PER_FRAME_ALLOWLIST:
		check_true(
			FileAccess.file_exists(path),
			"PER_FRAME_ALLOWLIST names a file that no longer exists: %s" % path
		)
		if not FileAccess.file_exists(path):
			continue
		check_false(
			SourceScanner.match_lines(path, pattern).is_empty(),
			"%s is allowlisted but no longer declares a per-frame callback" % path
		)
