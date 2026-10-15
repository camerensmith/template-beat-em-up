class_name RbRiftDirector
extends RefCounted

## Assembles a rift (one procedural run) from hand-made content.
##
## Nothing here generates art. The director picks [b]stage segments[/b] that connect to each other,
## puts an [b]encounter[/b] in each one, spends a threat budget on enemies, promotes some of them to
## elites or minibosses, and places a boss in an arena that can legally hold it.
## [br][br]
## Output is a plain Dictionary (the "rift plan"), so it can be saved, diffed, shown in tools, and
## fed to whatever instantiates the level. The same seed and content always give the same plan.
## [br][br]
## "Depth" in content ([code]min_depth[/code]) means the rift level: higher levels unlock
## tougher enemies, segments, bosses and elite modifiers.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const DEFAULT_MAX_ENEMIES = 8
const SEARCH_BUDGET = 20000
## Segments of the same theme as the previous room are this much more likely, so districts
## feel coherent instead of flickering between themes every room.
const SAME_THEME_BIAS = 3.0

const BASE_ELITE_CHANCE = 0.04
const ELITE_CHANCE_PER_LEVEL = 0.01
const MAX_ELITE_CHANCE = 0.2

#--- private variables - order: export > normal var > onready -------------------------------------

var _registry: RbContentRegistry
var _search_steps := 0

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _init(registry: RbContentRegistry) -> void:
	_registry = registry

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

## Builds a rift plan. [param options]:
## [br]- [code]rift[/code]: rift template id (random weighted pick when missing)
## [br]- [code]level[/code]: rift level, default 1. Monster level is level + template offset.
## [br]- [code]mutators[/code]: forced mutator ids, replacing the random roll
## [br]On failure the plan has a non-empty [code]errors[/code] array.
func generate(seed_value: int, options := {}) -> Dictionary:
	var rng := RbRng.new(seed_value)
	var plan := {
		"seed": seed_value,
		"rift": "",
		"name": "",
		"level": maxi(1, int(options.get("level", 1))),
		"monster_level": 1,
		"mutators": [],
		"elite_chance": 0.0,
		"boss": "",
		"rooms": [],
		"errors": [],
	}

	var template := _pick_template(options, rng.fork("template"))
	if template.is_empty():
		plan.errors.append("no rift template '%s'" % options.get("rift", "<any>"))
		return plan
	plan.rift = template.id
	plan.name = template.name
	plan.monster_level = maxi(1, plan.level + int(template.get("monster_level_offset", 0)))

	plan.mutators = _pick_mutators(template, options, rng.fork("mutators"))
	plan.elite_chance = _get_elite_chance(plan)

	var roles := _expand_steps(template, rng.fork("structure"))
	var boss := {}
	if "boss" in roles:
		boss = _pick_boss(template, plan.level, rng.fork("boss"))
		if boss.is_empty():
			plan.errors.append("no boss can appear in '%s' at level %s" % [template.id, plan.level])
			return plan
		plan.boss = boss.id

	var segments := _layout(roles, template, plan.level, boss, rng.fork("layout"))
	if segments.is_empty():
		plan.errors.append("could not connect segments for roles %s in '%s'" % [roles, template.id])
		return plan

	var spawn_rng := rng.fork("spawns")
	for index in roles.size():
		var room := _build_room(index, roles[index], segments[index], template, plan, boss, spawn_rng)
		if room.has("error"):
			plan.errors.append(room.error)
		plan.rooms.append(room)
	return plan


## Generates [param samples] plans per template and reports any that fail, plus roles whose
## content is missing. This is the "encounter validation" used by the CLI and tests.
func check_templates(samples := 25, max_level := 5) -> PackedStringArray:
	var problems := PackedStringArray()
	for template in _registry.get_all("rift"):
		for step in template.steps:
			var has_segment := _registry.get_all("stage_segment").any(func(segment):
				return step.role in segment.roles and segment.theme in template.themes
			)
			if not has_segment:
				problems.append("%s: no stage segment for role '%s' in themes %s" % [
						template.id, step.role, template.themes
				])
			var has_encounter := _registry.get_all("encounter").any(func(encounter):
				return encounter.role == step.role and _theme_allowed(encounter, template.themes)
			)
			if not has_encounter:
				problems.append("%s: no encounter for role '%s'" % [template.id, step.role])

		for level in range(1, max_level + 1):
			for sample in samples:
				var plan := generate(hash("%s/%s/%s" % [template.id, level, sample]), {
					"rift": template.id, "level": level,
				})
				for error in plan.errors:
					problems.append("%s level %s seed %s: %s" % [template.id, level, plan.seed, error])
				if not plan.errors.is_empty():
					break
	return problems


static func describe_plan(plan: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("%s  (seed %s, rift level %s, monster level %s)" % [
			plan.name, plan.seed, plan.level, plan.monster_level
	])
	if not plan.mutators.is_empty():
		lines.append("  mutators: %s" % ", ".join(PackedStringArray(plan.mutators)))
	for room in plan.rooms:
		var spawns := PackedStringArray()
		for spawn in room.spawns:
			var label: String = spawn.id.get_slice(":", 1)
			if not spawn.elite.is_empty():
				label = "ELITE[%s] %s" % [
						"+".join(PackedStringArray(spawn.elite.map(func(id): return id.get_slice(":", 1)))),
						label,
				]
			if spawn.kind != "enemy":
				label = "%s %s" % [spawn.kind.to_upper(), label]
			spawns.append(label)
		lines.append("  %s. %-7s %-22s %-20s %s%s" % [
				room.index + 1, room.role, room.segment.get_slice(":", 1),
				room.encounter.get_slice(":", 1),
				("[%s] " % room.event) if not room.event.is_empty() else "",
				", ".join(spawns),
		])
	for error in plan.errors:
		lines.append("  ERROR: %s" % error)
	return "\n".join(lines)

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _pick_template(options: Dictionary, rng: RbRng) -> Dictionary:
	if options.has("rift"):
		return _registry.get_entry("rift", options.rift)
	var picked = rng.pick_weighted(_registry.get_all("rift"))
	return picked if picked != null else {}


func _pick_mutators(template: Dictionary, options: Dictionary, rng: RbRng) -> Array:
	if options.has("mutators"):
		return options.mutators.map(func(id): return _registry.resolve_id("mutator", id)).filter(
				func(id): return not id.is_empty()
		)
	var amount: Dictionary = template.get("mutators", {"min": 0, "max": 0})
	var pool := _registry.get_all("mutator")
	var picked := []
	for _index in rng.int_range(amount.min, amount.max):
		var mutator = rng.pick_weighted(pool)
		if mutator == null:
			break
		picked.append(mutator.id)
		pool.erase(mutator)
	return picked


func _get_elite_chance(plan: Dictionary) -> float:
	var value := minf(MAX_ELITE_CHANCE, BASE_ELITE_CHANCE + ELITE_CHANCE_PER_LEVEL * plan.level)
	for mutator_id in plan.mutators:
		value += _registry.get_entry("mutator", mutator_id).get("elite_chance_bonus", 0.0)
	return minf(1.0, value)


func _expand_steps(template: Dictionary, rng: RbRng) -> Array:
	var roles := []
	for step in template.steps:
		if step.has("chance") and not rng.chance(step.chance):
			continue
		var repeat: Dictionary = step.get("repeat", {"min": 1, "max": 1})
		for _index in rng.int_range(repeat.min, repeat.max):
			roles.append(step.role)
	return roles


func _pick_boss(template: Dictionary, level: int, rng: RbRng) -> Dictionary:
	var candidates := _registry.get_all("boss").filter(func(boss):
		if boss.tier != "boss" or boss.get("min_depth", 0) > level:
			return false
		return _registry.get_all("stage_segment").any(func(segment):
			return (
					"boss" in segment.roles
					and segment.theme in template.themes
					and segment.get("min_depth", 0) <= level
					and _segment_fits_boss(segment, boss)
			)
		)
	)
	var picked = rng.pick_weighted(candidates)
	return picked if picked != null else {}


func _segment_fits_boss(segment: Dictionary, boss: Dictionary) -> bool:
	return segment.theme in boss.themes and _arena_fits(segment, boss)


## Whether the segment is big enough and has every feature the boss's moves rely on.
func _arena_fits(segment: Dictionary, boss: Dictionary) -> bool:
	var arena: Dictionary = boss.arena
	var features: Array = segment.get("features", [])
	return (
			segment.width >= arena.min_width and segment.depth >= arena.min_depth
			and arena.get("features", []).all(func(feature): return feature in features)
	)


## Depth-first search for a chain of segments. Candidates are tried in a weighted random order,
## unused segments first, so results vary by seed but always connect when a chain exists.
func _layout(roles: Array, template: Dictionary, level: int, boss: Dictionary, rng: RbRng) -> Array:
	_search_steps = 0
	var chain := []
	if _extend_layout(chain, roles, template, level, boss, rng):
		return chain
	return []


func _extend_layout(
		chain: Array, roles: Array, template: Dictionary, level: int, boss: Dictionary, rng: RbRng
) -> bool:
	if chain.size() == roles.size():
		return true
	_search_steps += 1
	if _search_steps > SEARCH_BUDGET:
		return false

	var role: String = roles[chain.size()]
	var previous: Dictionary = chain.back() if not chain.is_empty() else {}
	var is_last := chain.size() == roles.size() - 1
	var candidates := _registry.get_all("stage_segment").filter(func(segment):
		if not role in segment.roles or not segment.theme in template.themes:
			return false
		if segment.get("min_depth", 0) > level:
			return false
		if role == "boss" and not _segment_fits_boss(segment, boss):
			return false
		if not is_last and segment.get("exit", []).is_empty():
			return false
		if previous.is_empty():
			return true
		return previous.get("exit", []).any(func(tag): return tag in segment.get("entry", []))
	)

	for segment in _weighted_order(candidates, chain, previous, rng):
		chain.append(segment)
		if _extend_layout(chain, roles, template, level, boss, rng):
			return true
		chain.pop_back()
	return false


func _weighted_order(candidates: Array, chain: Array, previous: Dictionary, rng: RbRng) -> Array:
	var unused := []
	var used := []
	for segment in candidates:
		if segment in chain:
			used.append(segment)
		else:
			unused.append(segment)
	return _weighted_shuffle(unused, previous, rng) + _weighted_shuffle(used, previous, rng)


func _weighted_shuffle(segments: Array, previous: Dictionary, rng: RbRng) -> Array:
	var pool := segments.duplicate()
	var ordered := []
	while not pool.is_empty():
		var weights := pool.map(func(segment):
			var weight: float = segment.get("weight", 1.0)
			if not previous.is_empty() and segment.theme == previous.theme:
				weight *= SAME_THEME_BIAS
			return weight
		)
		var picked = rng.pick_weighted(pool, "", weights)
		if picked == null:
			picked = pool[0]
		ordered.append(picked)
		pool.erase(picked)
	return ordered


func _build_room(
		index: int, role: String, segment: Dictionary, template: Dictionary, plan: Dictionary,
		boss: Dictionary, rng: RbRng
) -> Dictionary:
	var room := {
		"index": index,
		"role": role,
		"segment": segment.id,
		"theme": segment.theme,
		"encounter": "",
		"event": "",
		"budget": 0.0,
		"spawns": [],
	}

	var encounters := _registry.get_all("encounter").filter(func(encounter):
		return (
				encounter.role == role
				and _theme_allowed(encounter, [segment.theme])
				and encounter.get("min_depth", 0) <= plan.level
		)
	)
	var encounter = rng.pick_weighted(encounters)
	if encounter == null:
		room["error"] = "room %s: no '%s' encounter for theme '%s'" % [index + 1, role, segment.theme]
		return room
	room.encounter = encounter.id
	room.event = encounter.get("event", "")

	var budget: float = (
			(template.base_budget + template.get("budget_per_room", 0.0) * index)
			* encounter.get("budget_mult", 1.0)
	)
	room.budget = snappedf(budget, 0.01)
	var max_enemies: int = encounter.get("max_enemies", 0)
	if max_enemies <= 0:
		max_enemies = DEFAULT_MAX_ENEMIES

	var pool := _registry.get_all("enemy").filter(func(enemy):
		return (
				_theme_allowed(enemy, [segment.theme])
				and enemy.get("min_depth", 0) <= plan.level
				and (
						encounter.get("archetypes", []).is_empty()
						or enemy.archetype in encounter.archetypes
				)
		)
	)

	if role == "boss":
		room.spawns.append(_make_spawn(boss.id, "boss", []))
	elif role == "elite":
		var leader := _pick_elite_leader(encounter, segment, pool, plan, rng)
		if not leader.is_empty():
			room.spawns.append(leader)
			budget -= _spawn_threat(leader)

	while room.spawns.size() < max_enemies:
		var affordable := pool.filter(func(enemy): return enemy.threat <= budget)
		var enemy = rng.pick_weighted(affordable)
		if enemy == null:
			break
		var elite := []
		if role != "boss" and enemy.get("can_be_elite", true) and rng.chance(plan.elite_chance):
			elite = roll_elite_modifiers(template, plan, rng)
		room.spawns.append(_make_spawn(enemy.id, "enemy", elite))
		budget -= enemy.threat
	return room


func _pick_elite_leader(
		encounter: Dictionary, segment: Dictionary, pool: Array, plan: Dictionary, rng: RbRng
) -> Dictionary:
	if rng.chance(encounter.get("miniboss_chance", 0.0)):
		var minibosses := _registry.get_all("boss").filter(func(boss):
			return (
					boss.tier == "miniboss"
					and segment.theme in boss.themes
					and boss.get("min_depth", 0) <= plan.level
					and _arena_fits(segment, boss)
			)
		)
		var miniboss = rng.pick_weighted(minibosses)
		if miniboss != null:
			return _make_spawn(miniboss.id, "miniboss", [])

	var candidates := pool.filter(func(enemy): return enemy.get("can_be_elite", true))
	var leader = rng.pick_weighted(candidates)
	if leader == null:
		return {}
	var template := _registry.get_entry("rift", plan.rift)
	return _make_spawn(leader.id, "enemy", roll_elite_modifiers(template, plan, rng, true))


## Rolls compatible elite modifier ids for [param plan]. Public so runtime spawns that the plan
## didn't foresee can still become elites.
func roll_elite_modifiers(
		template: Dictionary, plan: Dictionary, rng: RbRng, at_least_one := false
) -> Array:
	var amount: Dictionary = template.get("elite_modifiers", {"min": 1, "max": 1})
	var wanted := rng.int_range(amount.min, amount.max)
	if at_least_one:
		wanted = maxi(1, wanted)
	var chosen := []
	for _index in wanted:
		var candidates := _registry.get_all("elite_modifier").filter(func(modifier):
			if modifier.id in chosen or modifier.get("min_depth", 0) > plan.level:
				return false
			for other_id in chosen:
				var other := _registry.get_entry("elite_modifier", other_id)
				if modifier.id in other.get("incompatible", []):
					return false
				if other_id in modifier.get("incompatible", []):
					return false
			return true
		)
		var modifier = rng.pick_weighted(candidates)
		if modifier == null:
			break
		chosen.append(modifier.id)
	return chosen


func _spawn_threat(spawn: Dictionary) -> float:
	if spawn.kind == "miniboss":
		return 4.0
	var enemy := _registry.get_entry("enemy", spawn.id)
	return enemy.get("threat", 1) * (1.0 + 0.5 * spawn.elite.size())


func _theme_allowed(entry: Dictionary, themes: Array) -> bool:
	var entry_themes: Array = entry.get("themes", [])
	return entry_themes.is_empty() or entry_themes.any(func(theme): return theme in themes)


static func _make_spawn(id: String, kind: String, elite: Array) -> Dictionary:
	return {"id": id, "kind": kind, "elite": elite}

### -----------------------------------------------------------------------------------------------
