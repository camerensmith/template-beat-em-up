class_name RbContentSchema
extends RefCounted

## Declarative schemas for every content type a mod can provide, plus the validator for them.
##
## Each content type maps to a folder inside a mod (see [constant FOLDERS]) and to a field
## specification in [constant TYPES]. A field spec is a Dictionary with:
## [br]- [code]type[/code]: string, int, number, bool, color, path, ref, stats, array, dict
## [br]- [code]required[/code]: whether the field must be present
## [br]- [code]enum[/code]: allowed values for strings
## [br]- [code]min[/code] / [code]max[/code]: numeric bounds
## [br]- [code]ref[/code]: content type that a [code]ref[/code] field points to
## [br]- [code]items[/code]: spec for each element of an array
## [br]- [code]fields[/code]: specs for a dict with known keys
## [br]- [code]ranges[/code]: for [code]stats[/code], allows [code][min, max][/code] rolls
## [br][br]
## Validation happens in two passes: [method validate_entry] checks shapes while loading, and
## [method resolve_refs] rewrites references to fully namespaced ids once every mod is loaded.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const ID_PATTERN = "^([a-z0-9_]+:)?[a-z0-9_]+$"

const SLOTS = ["weapon", "head", "chest", "gloves", "belt", "boots", "ring", "amulet"]
const ROOM_ROLES = ["entry", "combat", "ambush", "elite", "event", "shop", "boss"]
const ARCHETYPES = ["grunt", "brute", "runner", "ranged", "grappler", "support"]

## Content type -> folder name inside a mod.
const FOLDERS = {
	"class": "classes",
	"character": "characters",
	"skill": "skills",
	"enemy": "enemies",
	"boss": "bosses",
	"elite_modifier": "elite_modifiers",
	"item_base": "items",
	"affix": "affixes",
	"rarity": "rarities",
	"unique": "uniques",
	"set": "sets",
	"loot_table": "loot_tables",
	"stage_segment": "stages",
	"encounter": "encounters",
	"rift": "rifts",
	"mutator": "mutators",
	"sprite_pack": "sprite_packs",
}

const _MIN_MAX = {
	"min": {"type": "int", "required": true, "min": 0},
	"max": {"type": "int", "required": true, "min": 0},
}

const _COMMON = {
	"id": {"type": "string", "required": true},
	"type": {"type": "string"},
	"patch": {"type": "bool"},
	"name": {"type": "string"},
	"description": {"type": "string"},
	"tags": {"type": "array", "items": {"type": "string"}},
}

const TYPES = {
	"class": {
		"name": {"type": "string", "required": true},
		"identity": {"type": "string"},
		"specializations": {"type": "array", "items": {"type": "dict", "fields": {
			"id": {"type": "string", "required": true},
			"name": {"type": "string", "required": true},
			"description": {"type": "string"},
		}}},
		"base_stats": {"type": "stats"},
		"per_level": {"type": "stats"},
		"starting_items": {"type": "array", "items": {"type": "ref", "ref": "item_base"}},
	},
	"character": {
		"name": {"type": "string", "required": true},
		"default_class": {"type": "ref", "ref": "class", "required": true},
		"scene": {"type": "path", "required": true},
		"sprite_pack": {"type": "ref", "ref": "sprite_pack"},
	},
	"skill": {
		"name": {"type": "string", "required": true},
		"class": {"type": "ref", "ref": "class", "required": true},
		"specialization": {"type": "string"},
		"tier": {"type": "int", "min": 1, "required": true},
		"max_rank": {"type": "int", "min": 1, "required": true},
		"stats_per_rank": {"type": "stats", "required": true},
		"requires": {"type": "array", "items": {"type": "ref", "ref": "skill"}},
	},
	"enemy": {
		"name": {"type": "string", "required": true},
		"scene": {"type": "path", "required": true},
		"archetype": {"type": "string", "enum": ARCHETYPES, "required": true},
		"threat": {"type": "int", "min": 1, "required": true},
		"xp": {"type": "int", "min": 0, "required": true},
		"loot_table": {"type": "ref", "ref": "loot_table"},
		"themes": {"type": "array", "items": {"type": "string"}},
		"can_be_elite": {"type": "bool"},
		"tint": {"type": "color"},
		"min_depth": {"type": "int", "min": 0},
		"stats": {"type": "stats"},
		"weight": {"type": "number", "min": 0},
	},
	"boss": {
		"name": {"type": "string", "required": true},
		"tier": {"type": "string", "enum": ["miniboss", "boss"], "required": true},
		"scene": {"type": "path", "required": true},
		"placeholder": {"type": "bool"},
		"tint": {"type": "color"},
		"xp": {"type": "int", "min": 0, "required": true},
		"loot_table": {"type": "ref", "ref": "loot_table"},
		"themes": {"type": "array", "items": {"type": "string"}, "required": true},
		"arena": {"type": "dict", "required": true, "fields": {
			"min_width": {"type": "int", "min": 0, "required": true},
			"min_depth": {"type": "int", "min": 0, "required": true},
			"features": {"type": "array", "items": {"type": "string"}},
		}},
		"moves": {"type": "array", "items": {"type": "string"}},
		"phases": {"type": "array", "items": {"type": "dict", "fields": {
			"below_health": {"type": "number", "min": 0, "max": 1, "required": true},
			"unlock": {"type": "array", "items": {"type": "string"}},
			"stats": {"type": "stats"},
		}}},
		"stats": {"type": "stats"},
		"intro_text": {"type": "string"},
		"min_depth": {"type": "int", "min": 0},
		"weight": {"type": "number", "min": 0},
	},
	"elite_modifier": {
		"name": {"type": "string", "required": true},
		"stats": {"type": "stats", "required": true},
		"tint": {"type": "color"},
		"incompatible": {"type": "array", "items": {"type": "ref", "ref": "elite_modifier"}},
		"min_depth": {"type": "int", "min": 0},
		"weight": {"type": "number", "min": 0},
	},
	"item_base": {
		"name": {"type": "string", "required": true},
		"slot": {"type": "string", "enum": SLOTS, "required": true},
		"item_type": {"type": "string", "required": true},
		"level_req": {"type": "int", "min": 1},
		"implicit": {"type": "stats", "ranges": true},
		"weight": {"type": "number", "min": 0},
	},
	"affix": {
		"kind": {"type": "string", "enum": ["prefix", "suffix"], "required": true},
		"name": {"type": "string", "required": true},
		"group": {"type": "string"},
		"slots": {"type": "array", "items": {"type": "string", "enum": SLOTS}},
		"weight": {"type": "number", "min": 0},
		"tiers": {"type": "array", "required": true, "min": 1, "items": {"type": "dict", "fields": {
			"min_ilvl": {"type": "int", "min": 1, "required": true},
			"weight": {"type": "number", "min": 0},
			"stats": {"type": "stats", "ranges": true, "required": true},
		}}},
	},
	"rarity": {
		"name": {"type": "string", "required": true},
		"order": {"type": "int", "min": 0, "required": true},
		"color": {"type": "color", "required": true},
		"weight": {"type": "number", "min": 0, "required": true},
		"min_ilvl": {"type": "int", "min": 1},
		"generates": {"type": "string", "enum": ["affixes", "unique", "set"], "required": true},
		"affixes": {"type": "dict", "fields": _MIN_MAX},
		"max_prefixes": {"type": "int", "min": 0},
		"max_suffixes": {"type": "int", "min": 0},
		"magic_find_scaling": {"type": "bool"},
	},
	"unique": {
		"name": {"type": "string", "required": true},
		"base": {"type": "ref", "ref": "item_base", "required": true},
		"rarity": {"type": "ref", "ref": "rarity"},
		"set": {"type": "ref", "ref": "set"},
		"min_ilvl": {"type": "int", "min": 1},
		"weight": {"type": "number", "min": 0},
		"stats": {"type": "stats", "ranges": true, "required": true},
		"flavor": {"type": "string"},
	},
	"set": {
		"name": {"type": "string", "required": true},
		"bonuses": {"type": "array", "required": true, "min": 1, "items": {"type": "dict", "fields": {
			"pieces": {"type": "int", "min": 2, "required": true},
			"stats": {"type": "stats", "required": true},
		}}},
	},
	"loot_table": {
		"rolls": {"type": "dict", "fields": _MIN_MAX},
		"no_drop_weight": {"type": "number", "min": 0},
		"rarity_bonus": {"type": "number", "min": 0},
		"entries": {"type": "array", "required": true, "items": {"type": "dict", "fields": {
			"kind": {"type": "string", "enum": ["item", "gold", "table"], "required": true},
			"weight": {"type": "number", "min": 0},
			"base": {"type": "ref", "ref": "item_base"},
			"slot": {"type": "string", "enum": SLOTS},
			"table": {"type": "ref", "ref": "loot_table"},
			"gold": {"type": "dict", "fields": _MIN_MAX},
		}}},
	},
	"stage_segment": {
		"name": {"type": "string", "required": true},
		"theme": {"type": "string", "required": true},
		"scene": {"type": "path"},
		"width": {"type": "int", "min": 1, "required": true},
		"depth": {"type": "int", "min": 1, "required": true},
		"roles": {"type": "array", "required": true, "min": 1, "items": {
			"type": "string", "enum": ROOM_ROLES,
		}},
		"entry": {"type": "array", "items": {"type": "string"}},
		"exit": {"type": "array", "items": {"type": "string"}},
		"features": {"type": "array", "items": {"type": "string"}},
		"min_depth": {"type": "int", "min": 0},
		"weight": {"type": "number", "min": 0},
	},
	"encounter": {
		"name": {"type": "string", "required": true},
		"role": {"type": "string", "enum": ROOM_ROLES, "required": true},
		"themes": {"type": "array", "items": {"type": "string"}},
		"enemy_tags": {"type": "array", "items": {"type": "string"}},
		"archetypes": {"type": "array", "items": {"type": "string", "enum": ARCHETYPES}},
		"budget_mult": {"type": "number", "min": 0},
		"max_enemies": {"type": "int", "min": 0},
		"event": {"type": "string"},
		"miniboss_chance": {"type": "number", "min": 0, "max": 1},
		"min_depth": {"type": "int", "min": 0},
		"weight": {"type": "number", "min": 0},
	},
	"rift": {
		"name": {"type": "string", "required": true},
		"themes": {"type": "array", "required": true, "min": 1, "items": {"type": "string"}},
		"monster_level_offset": {"type": "int"},
		"base_budget": {"type": "number", "min": 1, "required": true},
		"budget_per_room": {"type": "number", "min": 0},
		"elite_modifiers": {"type": "dict", "fields": _MIN_MAX},
		"mutators": {"type": "dict", "fields": _MIN_MAX},
		"weight": {"type": "number", "min": 0},
		"steps": {"type": "array", "required": true, "min": 1, "items": {"type": "dict", "fields": {
			"role": {"type": "string", "enum": ROOM_ROLES, "required": true},
			"repeat": {"type": "dict", "fields": _MIN_MAX},
			"chance": {"type": "number", "min": 0, "max": 1},
		}}},
	},
	"mutator": {
		"name": {"type": "string", "required": true},
		"enemy_stats": {"type": "stats"},
		"player_stats": {"type": "stats"},
		"elite_chance_bonus": {"type": "number", "min": 0, "max": 1},
		"loot_bonus_pct": {"type": "number", "min": 0},
		"xp_bonus_pct": {"type": "number", "min": 0},
		"weight": {"type": "number", "min": 0},
	},
	"sprite_pack": {
		"name": {"type": "string", "required": true},
		"sheet": {"type": "path", "required": true},
		"cell": {"type": "dict", "required": true, "fields": {
			"width": {"type": "int", "min": 1, "required": true},
			"height": {"type": "int", "min": 1, "required": true},
		}},
		"origin": {"type": "dict", "fields": {
			"x": {"type": "int", "required": true},
			"y": {"type": "int", "required": true},
		}},
		"animations": {"type": "dict", "required": true, "values": {"type": "dict", "fields": {
			"row": {"type": "int", "min": 0, "required": true},
			"column": {"type": "int", "min": 0},
			"frames": {"type": "int", "min": 1, "required": true},
			"fps": {"type": "number", "min": 0},
			"loop": {"type": "bool"},
			"hit_frames": {"type": "array", "items": {"type": "int", "min": 0}},
		}}},
	},
}

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

static func has_type(content_type: String) -> bool:
	return TYPES.has(content_type)


static func get_fields(content_type: String) -> Dictionary:
	var fields := _COMMON.duplicate()
	fields.merge(TYPES[content_type], true)
	return fields


## Validates [param entry] against its type's schema, appending human readable problems
## to [param errors].
static func validate_entry(
		content_type: String, entry: Dictionary, errors: PackedStringArray
) -> void:
	if not has_type(content_type):
		errors.append("unknown content type '%s'" % content_type)
		return

	var regex := RegEx.create_from_string(ID_PATTERN)
	if entry.get("id") is String and regex.search(entry.id) == null:
		errors.append("id '%s' must be lowercase snake_case, optionally 'mod:id'" % entry.id)

	if entry.get("type") is String and entry.type != content_type:
		errors.append("declares type '%s' but is in the '%s' folder" % [
				entry.type, FOLDERS[content_type]
		])

	# Patches only carry the fields they change, so required fields aren't enforced on them.
	var is_patch: bool = entry.get("patch", false) == true
	_validate_fields(get_fields(content_type), entry, "", errors, is_patch)


## Replaces every reference in [param entry] with the id returned by [param resolver], called as
## [code]resolver.call(ref_type, written_id)[/code]. An empty result is reported as an error.
static func resolve_refs(
		content_type: String, entry: Dictionary, resolver: Callable, errors: PackedStringArray
) -> void:
	_resolve_fields(get_fields(content_type), entry, "", resolver, errors)


## Returns the names of top level [code]path[/code] fields, which are resolved per mod.
static func get_path_fields(content_type: String) -> PackedStringArray:
	var value := PackedStringArray()
	var fields := get_fields(content_type)
	for key in fields:
		if fields[key].type == "path":
			value.append(key)
	return value

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

static func _validate_fields(
		fields: Dictionary, data: Dictionary, prefix: String,
		errors: PackedStringArray, is_patch := false
) -> void:
	for key in fields:
		var spec: Dictionary = fields[key]
		if not data.has(key):
			if spec.get("required", false) and not is_patch:
				errors.append("missing required field '%s%s'" % [prefix, key])
			continue
		_validate_value(spec, data[key], prefix + key, errors)

	for key in data:
		if not fields.has(key):
			errors.append("unknown field '%s%s'" % [prefix, key])


static func _validate_value(
		spec: Dictionary, value, path: String, errors: PackedStringArray
) -> void:
	match spec.type:
		"string":
			if not value is String:
				errors.append("'%s' must be a string" % path)
			elif spec.has("enum") and not value in spec["enum"]:
				errors.append("'%s' is '%s', expected one of %s" % [path, value, spec["enum"]])
		"int":
			if not _is_number(value) or not is_equal_approx(float(value), roundf(float(value))):
				errors.append("'%s' must be a whole number" % path)
			else:
				_validate_bounds(spec, float(value), path, errors)
		"number":
			if not _is_number(value):
				errors.append("'%s' must be a number" % path)
			else:
				_validate_bounds(spec, float(value), path, errors)
		"bool":
			if not value is bool:
				errors.append("'%s' must be true or false" % path)
		"color":
			if not value is String or not Color.html_is_valid(value):
				errors.append("'%s' must be an html color like '#ff8800'" % path)
		"path":
			if not value is String or (value as String).is_empty():
				errors.append("'%s' must be a file path" % path)
		"ref":
			if not value is String:
				errors.append("'%s' must be the id of a %s" % [path, spec.ref])
		"stats":
			_validate_stats(spec, value, path, errors)
		"array":
			if not value is Array:
				errors.append("'%s' must be a list" % path)
				return
			if spec.has("min") and value.size() < spec.min:
				errors.append("'%s' needs at least %s element(s)" % [path, spec.min])
			if spec.has("items"):
				for index in value.size():
					_validate_value(spec.items, value[index], "%s[%s]" % [path, index], errors)
		"dict":
			if not value is Dictionary:
				errors.append("'%s' must be an object" % path)
				return
			if spec.has("fields"):
				_validate_fields(spec.fields, value, path + ".", errors)
			if spec.has("values"):
				for key in value:
					_validate_value(spec["values"], value[key], "%s.%s" % [path, key], errors)
		_:
			errors.append("schema bug: '%s' has unknown type '%s'" % [path, spec.type])


static func _resolve_fields(
		fields: Dictionary, data: Dictionary, prefix: String,
		resolver: Callable, errors: PackedStringArray
) -> void:
	for key in fields:
		if data.has(key):
			data[key] = _resolve_value(fields[key], data[key], prefix + key, resolver, errors)


static func _resolve_value(
		spec: Dictionary, value, path: String, resolver: Callable, errors: PackedStringArray
):
	match spec.type:
		"ref":
			if value is String:
				var resolved: String = resolver.call(spec.ref, value)
				if resolved.is_empty():
					errors.append("'%s' points to unknown %s '%s'" % [path, spec.ref, value])
				else:
					return resolved
		"array":
			if value is Array and spec.has("items"):
				for index in value.size():
					value[index] = _resolve_value(
							spec.items, value[index], "%s[%s]" % [path, index], resolver, errors
					)
		"dict":
			if value is Dictionary:
				if spec.has("fields"):
					_resolve_fields(spec.fields, value, path + ".", resolver, errors)
				if spec.has("values"):
					for key in value:
						value[key] = _resolve_value(
								spec["values"], value[key], "%s.%s" % [path, key], resolver, errors
						)
	return value


static func _validate_stats(spec: Dictionary, value, path: String, errors: PackedStringArray) -> void:
	if not value is Dictionary:
		errors.append("'%s' must be an object of stat_id: value" % path)
		return

	for stat_id in value:
		var stat_path := "%s.%s" % [path, stat_id]
		if not RbStats.is_valid(stat_id):
			errors.append("'%s' is not a known stat" % stat_path)
			continue

		var stat_value = value[stat_id]
		if _is_number(stat_value):
			continue
		var is_range: bool = (
				stat_value is Array and stat_value.size() == 2
				and _is_number(stat_value[0]) and _is_number(stat_value[1])
		)
		if not spec.get("ranges", false) or not is_range:
			var expected := "a number or [min, max]" if spec.get("ranges", false) else "a number"
			errors.append("'%s' must be %s" % [stat_path, expected])
		elif float(stat_value[0]) > float(stat_value[1]):
			errors.append("'%s' range has min greater than max" % stat_path)


static func _validate_bounds(spec: Dictionary, value: float, path: String, errors: PackedStringArray) -> void:
	if spec.has("min") and value < spec.min:
		errors.append("'%s' is %s, must be at least %s" % [path, value, spec.min])
	if spec.has("max") and value > spec.max:
		errors.append("'%s' is %s, must be at most %s" % [path, value, spec.max])


static func _is_number(value) -> bool:
	return value is float or value is int

### -----------------------------------------------------------------------------------------------
