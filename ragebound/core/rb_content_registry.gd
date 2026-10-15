class_name RbContentRegistry
extends RefCounted

## Loads every mod, validates its content and serves it to the rest of the game.
##
## A mod is a folder containing a [code]manifest.json[/code] and one sub-folder per content type
## (see [constant RbContentSchema.FOLDERS]). Each [code].json[/code] file inside those folders
## holds either one entry or a list of entries.
## [br][br]
## [b]Ids[/b] are namespaced by mod: an entry [code]"id": "iron_butcher"[/code] in the mod
## [code]base_game[/code] is stored as [code]base_game:iron_butcher[/code]. References may use the
## short id; they resolve to the referencing mod first, then its dependencies, then any mod with a
## unique match.
## [br][br]
## [b]Overrides[/b]: an entry whose id names another mod's entry ([code]"id": "base_game:brute"[/code])
## replaces it. Adding [code]"patch": true[/code] deep merges the fields instead, so a mod can
## tweak a single number without copying the whole entry.
## [br][br]
## The base game is loaded through this same path, so anything it does a mod can do too.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const MANIFEST_FILE = "manifest.json"
const API_VERSION = 1
const DEFAULT_ROOTS = ["res://mods", "user://mods"]

const _MANIFEST_FIELDS = {
	"id": {"type": "string", "required": true},
	"name": {"type": "string", "required": true},
	"version": {"type": "string", "required": true},
	"ragebound_api": {"type": "int", "required": true, "min": 1},
	"description": {"type": "string"},
	"authors": {"type": "array", "items": {"type": "string"}},
	"license": {"type": "string"},
	"dependencies": {"type": "array", "items": {"type": "string"}},
	"load_priority": {"type": "int"},
	"enabled": {"type": "bool"},
}

#--- public variables - order: export > normal var > onready --------------------------------------

## Loaded manifests in load order. Each one also gets a [code]_root[/code] key.
var mods: Array[Dictionary] = []
var errors := PackedStringArray()
var warnings := PackedStringArray()
## Informational log of overrides and patches, useful when debugging mod conflicts.
var notes := PackedStringArray()

#--- private variables - order: export > normal var > onready -------------------------------------

## content_type -> { full_id -> entry }
var _entries := {}
var _mods_by_id := {}

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

## Discovers, orders, loads and validates mods from [param roots].
## Returns [code]true[/code] when no errors were found. Content from mods with errors is still
## loaded where possible so tools can report every problem at once.
func load_mods(roots: Array = DEFAULT_ROOTS) -> bool:
	clear()
	var manifests := _discover(roots)
	for manifest in _sort_by_dependencies(manifests):
		mods.append(manifest)
		_mods_by_id[manifest.id] = manifest

	for manifest in mods:
		_load_mod_content(manifest)

	_resolve_all_refs()
	_check_semantics()
	return errors.is_empty()


func clear() -> void:
	mods.clear()
	errors.clear()
	warnings.clear()
	notes.clear()
	_entries.clear()
	_mods_by_id.clear()
	for content_type in RbContentSchema.FOLDERS:
		_entries[content_type] = {}


func has_mod(mod_id: String) -> bool:
	return _mods_by_id.has(mod_id)


## Returns the entry, or an empty Dictionary. Accepts full ids or unambiguous short ids.
func get_entry(content_type: String, id: String) -> Dictionary:
	var full_id := resolve_id(content_type, id)
	if full_id.is_empty():
		return {}
	return _entries[content_type][full_id]


func has_entry(content_type: String, id: String) -> bool:
	return not resolve_id(content_type, id).is_empty()


## Returns all entries of a type in load order.
func get_all(content_type: String) -> Array:
	return _entries.get(content_type, {}).values()


func get_ids(content_type: String) -> Array:
	return _entries.get(content_type, {}).keys()


func count(content_type: String) -> int:
	return _entries.get(content_type, {}).size()


## Finds the entry of [param content_type] whose [code]scene[/code] is [param scene_path].
## Later mods win, so an override that reuses a scene is found before the original.
func find_by_scene(content_type: String, scene_path: String) -> Dictionary:
	var entries := get_all(content_type)
	for index in range(entries.size() - 1, -1, -1):
		if entries[index].get("scene", "") == scene_path:
			return entries[index]
	return {}


## Resolves [param id] to a full id. [param from_mod] lets short ids prefer the asking mod and
## its dependencies. Returns an empty String when there is no match or the match is ambiguous.
func resolve_id(content_type: String, id: String, from_mod := "") -> String:
	var entries: Dictionary = _entries.get(content_type, {})
	if id.contains(":"):
		return id if entries.has(id) else ""

	if not from_mod.is_empty():
		var search_order := [from_mod]
		search_order.append_array(_mods_by_id.get(from_mod, {}).get("dependencies", []))
		for mod_id in search_order:
			var candidate := "%s:%s" % [mod_id, id]
			if entries.has(candidate):
				return candidate

	var found := ""
	for full_id in entries:
		if (full_id as String).get_slice(":", 1) == id:
			if not found.is_empty():
				return ""
			found = full_id
	return found


## Human readable summary used by the CLI and the in-game debug overlay.
func get_report() -> String:
	var lines := PackedStringArray()
	lines.append("Mods (%s):" % mods.size())
	for manifest in mods:
		lines.append("  %s %s  [%s]" % [manifest.id, manifest.version, manifest._root])
	lines.append("Content:")
	for content_type in RbContentSchema.FOLDERS:
		if count(content_type) > 0:
			lines.append("  %-16s %s" % [content_type, count(content_type)])
	for note in notes:
		lines.append("note: " + note)
	for warning in warnings:
		lines.append("WARNING: " + warning)
	for error in errors:
		lines.append("ERROR: " + error)
	lines.append("%s error(s), %s warning(s)" % [errors.size(), warnings.size()])
	return "\n".join(lines)

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _discover(roots: Array) -> Array[Dictionary]:
	var manifests: Array[Dictionary] = []
	var seen := {}
	for root in roots:
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		var folders := Array(dir.get_directories())
		folders.sort()
		for folder in folders:
			var mod_root := (root as String).path_join(folder)
			var manifest_path := mod_root.path_join(MANIFEST_FILE)
			if not FileAccess.file_exists(manifest_path):
				continue

			var manifest = _read_json(manifest_path)
			if not manifest is Dictionary:
				if manifest != null:
					errors.append("%s: manifest must be a JSON object" % manifest_path)
				continue

			var problems := PackedStringArray()
			RbContentSchema._validate_fields(_MANIFEST_FIELDS, manifest, "", problems)
			if problems.is_empty():
				var id_regex := RegEx.create_from_string("^[a-z0-9_]+$")
				if id_regex.search(manifest.id) == null:
					problems.append("mod id '%s' must be lowercase snake_case" % manifest.id)
				elif int(manifest.ragebound_api) > API_VERSION:
					problems.append("needs ragebound_api %s, this build supports %s" % [
							manifest.ragebound_api, API_VERSION
					])
				elif seen.has(manifest.id):
					problems.append("duplicate mod id '%s', already loaded from %s" % [
							manifest.id, seen[manifest.id]
					])
			if not problems.is_empty():
				for problem in problems:
					errors.append("%s: %s" % [manifest_path, problem])
				continue
			if manifest.get("enabled", true) == false:
				notes.append("mod '%s' is disabled in its manifest" % manifest.id)
				continue

			seen[manifest.id] = mod_root
			manifest["_root"] = mod_root
			manifest["dependencies"] = manifest.get("dependencies", [])
			manifest["load_priority"] = int(manifest.get("load_priority", 0))
			manifests.append(manifest)
	return manifests


## Orders mods so dependencies load first; ties break by load_priority, then by id.
## Mods with missing or cyclic dependencies are reported and skipped.
func _sort_by_dependencies(manifests: Array[Dictionary]) -> Array[Dictionary]:
	var by_id := {}
	for manifest in manifests:
		by_id[manifest.id] = manifest

	var valid := {}
	for manifest in manifests:
		var missing := _find_missing_dependency(manifest, by_id, [])
		if missing.is_empty():
			valid[manifest.id] = manifest
		else:
			errors.append("mod '%s' skipped: %s" % [manifest.id, missing])

	var ordered: Array[Dictionary] = []
	var placed := {}
	while placed.size() < valid.size():
		var available := []
		for id in valid:
			if placed.has(id):
				continue
			var deps_placed: bool = valid[id].dependencies.all(func(dep): return placed.has(dep))
			if deps_placed:
				available.append(valid[id])
		available.sort_custom(func(a, b):
			if a.load_priority != b.load_priority:
				return a.load_priority < b.load_priority
			return a.id < b.id
		)
		# _find_missing_dependency already rejected cycles, so there is always a ready mod.
		var next: Dictionary = available[0]
		placed[next.id] = true
		ordered.append(next)
	return ordered


func _find_missing_dependency(manifest: Dictionary, by_id: Dictionary, chain: Array) -> String:
	if manifest.id in chain:
		return "dependency cycle %s" % " -> ".join(PackedStringArray(chain + [manifest.id]))
	for dep in manifest.dependencies:
		if not by_id.has(dep):
			return "missing dependency '%s'" % dep
		var problem := _find_missing_dependency(by_id[dep], by_id, chain + [manifest.id])
		if not problem.is_empty():
			return problem
	return ""


func _load_mod_content(manifest: Dictionary) -> void:
	for content_type in RbContentSchema.FOLDERS:
		var folder: String = manifest._root.path_join(RbContentSchema.FOLDERS[content_type])
		var dir := DirAccess.open(folder)
		if dir == null:
			continue
		var files := Array(dir.get_files())
		files.sort()
		for file_name in files:
			if (file_name as String).get_extension() != "json":
				continue
			var file_path := folder.path_join(file_name)
			var data = _read_json(file_path)
			if data == null:
				continue
			var list: Array = data if data is Array else [data]
			for index in list.size():
				var label := file_path if list.size() == 1 else "%s[%s]" % [file_path, index]
				_add_entry(content_type, list[index], manifest, label)


func _add_entry(content_type: String, entry, manifest: Dictionary, label: String) -> void:
	if not entry is Dictionary:
		errors.append("%s: each entry must be a JSON object" % label)
		return

	var problems := PackedStringArray()
	RbContentSchema.validate_entry(content_type, entry, problems)
	if not entry.get("id") is String:
		for problem in problems:
			errors.append("%s: %s" % [label, problem])
		return

	var written_id: String = entry.id
	var full_id := written_id if written_id.contains(":") else "%s:%s" % [manifest.id, written_id]
	label = "%s (%s)" % [label, full_id]
	for problem in problems:
		errors.append("%s: %s" % [label, problem])

	_resolve_paths(content_type, entry, manifest, label)

	var entries: Dictionary = _entries[content_type]
	var existing: Dictionary = entries.get(full_id, {})
	var is_patch: bool = entry.get("patch", false) == true
	if is_patch:
		if existing.is_empty():
			errors.append("%s: patch target does not exist (yet). Is '%s' a dependency?" % [
					label, full_id.get_slice(":", 0)
			])
			return
		var patch_data: Dictionary = entry.duplicate(true)
		for key in ["id", "type", "patch"]:
			patch_data.erase(key)
		_deep_merge(existing, patch_data)
		notes.append("%s patched by %s" % [full_id, manifest.id])
		return

	if not existing.is_empty():
		if existing._mod == manifest.id:
			errors.append("%s: duplicate id, already defined in %s" % [label, existing._source])
			return
		notes.append("%s overridden by %s" % [full_id, manifest.id])

	var stored: Dictionary = entry.duplicate(true)
	stored.erase("patch")
	stored["id"] = full_id
	stored["_mod"] = manifest.id
	stored["_source"] = label
	entries[full_id] = stored


## Relative paths are relative to the mod folder, so mods can live anywhere.
func _resolve_paths(content_type: String, entry: Dictionary, manifest: Dictionary, label: String) -> void:
	for field in RbContentSchema.get_path_fields(content_type):
		if not entry.get(field) is String or (entry[field] as String).is_empty():
			continue
		var path: String = entry[field]
		if not (path.begins_with("res://") or path.begins_with("user://")):
			path = (manifest._root as String).path_join(path).simplify_path()
			entry[field] = path
		if not (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
			errors.append("%s: '%s' file not found: %s" % [label, field, path])


func _resolve_all_refs() -> void:
	for content_type in _entries:
		for full_id in _entries[content_type]:
			var entry: Dictionary = _entries[content_type][full_id]
			var problems := PackedStringArray()
			var resolver := func(ref_type: String, id: String) -> String:
				return resolve_id(ref_type, id, entry._mod)
			RbContentSchema.resolve_refs(content_type, entry, resolver, problems)
			for problem in problems:
				errors.append("%s: %s" % [entry._source, problem])


## Rules that span several fields or entries and can't be expressed in the schema.
func _check_semantics() -> void:
	for entry in get_all("affix"):
		var last_ilvl := 0
		for tier in entry.tiers:
			if tier.min_ilvl < last_ilvl:
				errors.append("%s: tiers must be sorted by min_ilvl" % entry._source)
			last_ilvl = tier.min_ilvl

	for entry in get_all("boss"):
		var last_threshold := 1.0
		for phase in entry.get("phases", []):
			if phase.below_health >= last_threshold:
				errors.append("%s: phases must have decreasing below_health" % entry._source)
			last_threshold = phase.below_health

	for entry in get_all("rarity"):
		var affix_range: Dictionary = entry.get("affixes", {"min": 0, "max": 0})
		if affix_range.min > affix_range.max:
			errors.append("%s: affixes.min is greater than affixes.max" % entry._source)
		if entry.generates == "affixes" and affix_range.max > (
				entry.get("max_prefixes", 3) + entry.get("max_suffixes", 3)
		):
			errors.append("%s: affixes.max exceeds max_prefixes + max_suffixes" % entry._source)

	for entry in get_all("unique"):
		var rarity := get_entry("rarity", entry.get("rarity", "legendary"))
		if rarity.is_empty():
			errors.append("%s: no rarity '%s' to drop as" % [
					entry._source, entry.get("rarity", "legendary")
			])
		elif entry.has("set") and rarity.generates != "set":
			warnings.append("%s: belongs to a set but drops as '%s'" % [entry._source, rarity.id])

	for entry in get_all("set"):
		var pieces := get_all("unique").filter(func(unique): return unique.get("set") == entry.id)
		for bonus in entry.bonuses:
			if bonus.pieces > pieces.size():
				errors.append("%s: bonus needs %s pieces but the set has %s" % [
						entry._source, bonus.pieces, pieces.size()
				])

	for entry in get_all("skill"):
		for required in entry.get("requires", []):
			var other := get_entry("skill", required)
			if not other.is_empty() and other.get("class") != entry.get("class"):
				errors.append("%s: requires '%s' from another class" % [entry._source, required])

	if count("rarity") > 0 and get_all("rarity").filter(
			func(rarity): return rarity.generates == "affixes"
	).is_empty():
		errors.append("at least one rarity must generate affixes")


func _read_json(path: String):
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("%s: empty or unreadable file" % path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s:%s: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func _deep_merge(target: Dictionary, patch: Dictionary) -> void:
	for key in patch:
		if target.get(key) is Dictionary and patch[key] is Dictionary:
			_deep_merge(target[key], patch[key])
		else:
			target[key] = patch[key]

### -----------------------------------------------------------------------------------------------
