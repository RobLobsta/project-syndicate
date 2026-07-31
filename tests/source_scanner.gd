class_name SourceScanner
extends RefCounted
## Source-tree reading helpers shared by the [code]tests/arch/[/code] suite.
##
## The architectural conformance tests parse the tree as text rather than
## reflecting over loaded classes, because most of what they forbid (a
## [code]_process[/code] declaration, a mesh-derived collider, a global RNG call)
## is invisible once a script has been compiled.
##
## Text matching has one classic failure mode: a rule that fires on its own name
## appearing in a comment or a docstring. [method strip_noise] removes comments
## and string literals before any pattern runs, so a file may discuss
## [code]randi()[/code] in prose without failing the test that bans it.

const SRC_ROOT: String = "res://src"
const SCENES_ROOT: String = "res://scenes"
const TOOLS_ROOT: String = "res://tools"
const TESTS_ROOT: String = "res://tests"


## Every file under [param root] with one of [param extensions], sorted, so that
## a failure list is reproducible between runs.
static func files_under(root: String, extensions: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	_walk(root, extensions, out)
	out.sort()
	return out


static func gd_files(root: String) -> PackedStringArray:
	return files_under(root, PackedStringArray([".gd"]))


static func scene_files(root: String) -> PackedStringArray:
	return files_under(root, PackedStringArray([".tscn", ".scn"]))


static func read(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		push_error("SourceScanner: could not read %s" % path)
	return text


## Source with comments and string literals blanked out, line structure and line
## count preserved so that reported line numbers still match the real file.
static func strip_noise(source: String) -> String:
	var out := ""
	for line in source.split("\n"):
		out += _strip_line(line) + "\n"
	return out


## 1-indexed line numbers in [param path] where [param pattern] matches, ignoring
## comments and string literals.
static func match_lines(path: String, pattern: RegEx) -> PackedInt32Array:
	var hits := PackedInt32Array()
	var lines := strip_noise(read(path)).split("\n")
	for i in lines.size():
		if pattern.search(lines[i]) != null:
			hits.append(i + 1)
	return hits


static func compile(pattern: String) -> RegEx:
	var re := RegEx.new()
	var err := re.compile(pattern)
	assert(err == OK, "SourceScanner: bad pattern '%s'" % pattern)
	return re


## Path relative to res://, for readable failure messages.
static func short(path: String) -> String:
	return path.trim_prefix("res://")


static func _walk(dir_path: String, extensions: PackedStringArray, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_walk(full, extensions, out)
		else:
			for ext in extensions:
				if entry.ends_with(ext):
					out.append(full)
					break
		entry = dir.get_next()
	dir.list_dir_end()


## Blanks string literals and any trailing comment on one line. Not a full
## GDScript lexer: multi-line strings are not tracked across lines, which is
## acceptable because the patterns these tests run are single-token and a
## multi-line string containing one would be extraordinary.
static func _strip_line(line: String) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				i += 2
				continue
			out += " "
			if c == quote:
				quote = ""
				out = out.substr(0, out.length() - 1) + c
			i += 1
			continue
		if c == '"' or c == "'":
			quote = c
			out += c
			i += 1
			continue
		if c == "#":
			break
		out += c
		i += 1
	return out
