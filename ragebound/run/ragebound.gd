extends Node

## Autoload that layers Ragebound's ARPG systems over the beat-em-up template.
##
## It loads all mods, keeps the persistent [RbHero], generates a rift plan per run, and hooks
## into gameplay without the stage scenes knowing about it:
## [br]- Characters are detected as they enter the tree. Players get their class/level/gear stats,
## enemies get monster level scaling, their variant from the rift plan, elite modifiers and tints.
## [br]- [member CombatSystem.damage_modifiers] and [member CombatSystem.knockback_modifiers]
## route every hit through [RbCombatMath].
## [br]- Kills grant experience and roll loot tables.
## [br][br]
## The template's hand-made stage is still the level; the rift plan decides which variant, elite
## or boss each spawned body becomes, until segment scenes are cut for the stage assembler.

### Member Variables and Dependencies -------------------------------------------------------------
#--- signals --------------------------------------------------------------------------------------

signal run_started(plan: Dictionary)
signal run_ended(victory: bool)
signal hero_changed
signal message_posted(text: String, color: Color)
signal hit_resolved(target: QuiverAttributes, damage: int, is_crit: bool)
signal loot_dropped(drops: Array)

#--- constants ------------------------------------------------------------------------------------

const SAVE_PATH = "user://ragebound_save.json"
const DEFAULT_CHARACTER = "chad"
const META_BASE_VALUES = &"rb_base_values"

const COLOR_INFO = Color("#e8e8e8")
const COLOR_XP = Color("#9fe870")
const COLOR_GOLD = Color("#ffd84a")
const COLOR_DANGER = Color("#ff6b6b")

#--- public variables - order: export > normal var > onready --------------------------------------

var registry := RbContentRegistry.new()
var loot: RbLootGenerator
var director: RbRiftDirector
var hero: RbHero = null
var plan := {}
var is_run_active := false
## Set to false to play the template without ARPG modifiers (useful for comparing balance).
var enabled := true

#--- private variables - order: export > normal var > onready -------------------------------------

var _player_attributes: QuiverAttributes = null
var _player_stats := RbStatBlock.new()
## QuiverAttributes -> {entry, kind, elite, stats, name, phase}
var _monsters := {}
var _spawn_queue: Array[Dictionary] = []
var _combat_rng := RbRng.new()
var _loot_rng := RbRng.new()
var _neutral_stats := RbStatBlock.new()

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _ready() -> void:
	reload_content()
	load_game()

	CombatSystem.damage_modifiers.append(_modify_damage)
	CombatSystem.knockback_modifiers.append(_modify_knockback)
	get_tree().node_added.connect(_on_node_added)
	Events.player_died.connect(_on_player_died)

	var hud := preload("res://ragebound/ui/rb_hud.gd").new()
	add_child(hud)

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

func reload_content() -> void:
	var is_valid := registry.load_mods()
	if not is_valid:
		push_warning("Ragebound content has %s error(s):\n%s" % [
				registry.errors.size(), "\n".join(registry.errors)
		])
	loot = RbLootGenerator.new(registry)
	director = RbRiftDirector.new(registry)


## Starts a new rift. [param options] may contain [code]seed[/code], [code]rift[/code],
## [code]level[/code] and [code]mutators[/code] (see [method RbRiftDirector.generate]).
func start_run(options := {}) -> Dictionary:
	if hero == null:
		new_hero(DEFAULT_CHARACTER)

	var seed_value: int = options.get("seed", randi())
	var plan_options := options.duplicate()
	plan_options["level"] = options.get("level", hero.level)
	plan = director.generate(seed_value, plan_options)
	if not plan.errors.is_empty():
		push_error("Rift generation failed:\n%s" % RbRiftDirector.describe_plan(plan))

	_combat_rng = RbRng.new(seed_value).fork("combat")
	_loot_rng = RbRng.new(seed_value).fork("loot")
	_build_spawn_queue()
	is_run_active = true
	_refresh_player()
	run_started.emit(plan)
	post_message("%s - rift level %s" % [plan.name, plan.level], COLOR_INFO)
	for mutator_id in plan.mutators:
		var mutator := registry.get_entry("mutator", mutator_id)
		post_message("Mutator: %s" % mutator.name, COLOR_DANGER)
	print_verbose(RbRiftDirector.describe_plan(plan))
	return plan


func end_run(victory: bool) -> void:
	if not is_run_active:
		return
	is_run_active = false
	save_game()
	run_ended.emit(victory)


func new_hero(character_id: String, class_id := "") -> RbHero:
	var character := registry.get_entry("character", character_id)
	hero = RbHero.new()
	hero.character_id = character.get("id", character_id)
	hero.class_id = class_id if not class_id.is_empty() else character.get("default_class", "")
	hero.class_id = registry.resolve_id("class", hero.class_id)

	var class_entry := registry.get_entry("class", hero.class_id)
	var rng := RbRng.new(randi())
	for base_id in class_entry.get("starting_items", []):
		var item := loot.generate_item(1, rng, {"base": base_id, "rarity": "common"})
		if item != null:
			hero.equip(item)
	_connect_hero()
	save_game()
	return hero


func get_player_stats() -> RbStatBlock:
	return _player_stats


func get_monster_info(attributes: QuiverAttributes) -> Dictionary:
	return _monsters.get(attributes, {})


func post_message(text: String, color := COLOR_INFO) -> void:
	message_posted.emit(text, color)


func save_game() -> void:
	if hero == null:
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save Ragebound progress: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify({"version": 1, "hero": hero.to_dict()}, "\t"))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary or not data.get("hero") is Dictionary:
		push_warning("Ignoring unreadable save at %s" % SAVE_PATH)
		return false
	hero = RbHero.from_dict(data.hero)
	if registry.get_entry("class", hero.class_id).is_empty():
		push_warning("Saved class '%s' no longer exists, starting a new hero" % hero.class_id)
		hero = null
		return false
	_connect_hero()
	return true

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _connect_hero() -> void:
	hero.changed.connect(_on_hero_changed)
	_refresh_player()


func _on_hero_changed() -> void:
	_refresh_player()
	hero_changed.emit()


func _get_mutator_stats(key: String) -> Array:
	var value := []
	for mutator_id in plan.get("mutators", []):
		var stats: Dictionary = registry.get_entry("mutator", mutator_id).get(key, {})
		if not stats.is_empty():
			value.append(stats)
	return value


func _get_mutator_bonus(key: String) -> float:
	var value := 0.0
	for mutator_id in plan.get("mutators", []):
		value += registry.get_entry("mutator", mutator_id).get(key, 0.0)
	return value


## Turns the plan's rooms into a queue of bodies to hand out as enemies spawn.
func _build_spawn_queue() -> void:
	_spawn_queue.clear()
	for room in plan.get("rooms", []):
		for spawn in room.spawns:
			var spawn_type := "enemy" if spawn.kind == "enemy" else "boss"
			var entry := registry.get_entry(spawn_type, spawn.id)
			if not entry.is_empty():
				_spawn_queue.append({"spawn": spawn, "entry": entry, "type": spawn_type})


func _on_node_added(node: Node) -> void:
	if not enabled or not node is QuiverCharacter or Engine.is_editor_hint():
		return
	if node.scene_file_path.is_empty():
		return
	node.ready.connect(_on_character_ready.bind(node), CONNECT_ONE_SHOT)


func _on_character_ready(character: QuiverCharacter) -> void:
	if character.attributes == null:
		return
	if not is_run_active:
		start_run()
	if character is QuiverEnemyCharacter:
		_setup_monster(character)
	else:
		_setup_player(character)


func _setup_player(character: QuiverCharacter) -> void:
	_player_attributes = character.attributes
	_store_base_values(_player_attributes)
	_refresh_player(true)


func _refresh_player(heal_fully := false) -> void:
	if hero == null:
		return
	_player_stats = hero.build_stats(registry, _get_mutator_stats("player_stats"))
	if _player_attributes == null:
		return

	var base: Dictionary = _player_attributes.get_meta(META_BASE_VALUES)
	var ratio := _player_attributes.get_health_as_percentage()
	_player_attributes.health_max = _player_stats.get_max_life(base.health_max)
	_player_attributes.speed_max = _player_stats.get_speed(base.speed_max)
	if heal_fully:
		ratio = 1.0
	_player_attributes.health_current = maxi(1, roundi(_player_attributes.health_max * ratio))


## Attribute resources can be shared between instances, so the original values are stored once
## and every recalculation starts from them.
func _store_base_values(attributes: QuiverAttributes) -> void:
	if not attributes.has_meta(META_BASE_VALUES):
		attributes.set_meta(META_BASE_VALUES, {
			"health_max": attributes.health_max,
			"speed_max": attributes.speed_max,
			"display_name": attributes.display_name,
		})


func _setup_monster(character: QuiverEnemyCharacter) -> void:
	var attributes := character.attributes
	_store_base_values(attributes)
	var assignment := _take_spawn_for_scene(character.scene_file_path)
	if assignment.is_empty():
		return

	var entry: Dictionary = assignment.entry
	var elite_ids: Array = assignment.spawn.elite
	var elite_entries := elite_ids.map(func(id): return registry.get_entry("elite_modifier", id))
	var stats := RbStatBlock.for_monster(
			plan.get("monster_level", 1), entry, elite_entries, _get_mutator_stats("enemy_stats")
	)
	var base: Dictionary = attributes.get_meta(META_BASE_VALUES)
	attributes.health_max = stats.get_max_life(base.health_max)
	attributes.health_current = attributes.health_max
	attributes.speed_max = stats.get_speed(base.speed_max)

	var names := elite_entries.map(func(modifier): return modifier.name)
	names.append(entry.name)
	attributes.display_name = " ".join(PackedStringArray(names))

	var tint: String = entry.get("tint", "")
	if not elite_entries.is_empty():
		tint = elite_entries[0].get("tint", tint)
	if not tint.is_empty():
		character.modulate = Color(tint)

	_monsters[attributes] = {
		"entry": entry,
		"kind": assignment.spawn.kind,
		"is_elite": not elite_ids.is_empty(),
		"is_boss": assignment.spawn.kind != "enemy",
		"stats": stats,
		"phase": 0,
	}
	attributes.health_depleted.connect(_on_monster_killed.bind(attributes), CONNECT_ONE_SHOT)
	attributes.health_changed.connect(_on_monster_health_changed.bind(attributes))
	character.tree_exited.connect(func(): _monsters.erase(attributes), CONNECT_ONE_SHOT)

	if assignment.spawn.kind != "enemy":
		post_message("%s: \"%s\"" % [entry.name, entry.get("intro_text", "...")], COLOR_DANGER)


## Hands out the next planned spawn whose body matches [param scene_path]. When the plan has none
## left (the hand-made stage spawns more than the plan), the first entry using that scene is used
## with the run's usual elite chance.
func _take_spawn_for_scene(scene_path: String) -> Dictionary:
	for index in _spawn_queue.size():
		if _spawn_queue[index].entry.scene == scene_path:
			var assignment: Dictionary = _spawn_queue[index]
			_spawn_queue.remove_at(index)
			return assignment

	for spawn_type in ["enemy", "boss"]:
		var entries := registry.get_all(spawn_type).filter(
				func(entry): return entry.scene == scene_path
		)
		if entries.is_empty():
			continue
		var entry: Dictionary = entries[0]
		var elite := []
		if spawn_type == "enemy" and _combat_rng.chance(plan.get("elite_chance", 0.0)):
			var template := registry.get_entry("rift", plan.get("rift", ""))
			elite = director.roll_elite_modifiers(template, plan, _combat_rng, true)
		var kind: String = "enemy" if spawn_type == "enemy" else entry.tier
		return {"spawn": {"id": entry.id, "kind": kind, "elite": elite}, "entry": entry}
	return {}


func _stats_for(attributes: QuiverAttributes) -> RbStatBlock:
	if attributes == null:
		return _neutral_stats
	if attributes == _player_attributes:
		return _player_stats
	if _monsters.has(attributes):
		return _monsters[attributes].stats
	return _neutral_stats


func _modify_damage(
		damage: int, _attack: QuiverAttackData, target: QuiverAttributes,
		attacker: QuiverAttributes
) -> int:
	if not enabled:
		return damage
	var target_info: Dictionary = _monsters.get(target, {})
	var attacker_stats := _stats_for(attacker)
	var target_stats := _stats_for(target)
	var result := RbCombatMath.resolve_hit(damage, attacker_stats, target_stats, _combat_rng, {
		"is_elite": target_info.get("is_elite", false),
		"is_boss": target_info.get("is_boss", false),
	})
	var final_damage: int = result.damage

	if attacker != null and final_damage > 0:
		var heal := roundi(attacker_stats.get_value("life_on_hit"))
		if heal > 0 and attacker.is_alive():
			attacker.health_current += heal

		var remaining := float(target.health_current - final_damage) / float(target.health_max)
		if RbCombatMath.should_execute(remaining, attacker_stats, target_info.get("is_boss", false)):
			final_damage = target.health_current
			post_message("EXECUTED", COLOR_DANGER)

		var thorns := roundi(target_stats.get_value("thorns"))
		if thorns > 0 and attacker.is_alive() and not attacker.is_invulnerable:
			_apply_thorns.call_deferred(attacker, thorns)

	hit_resolved.emit(target, final_damage, result.is_crit)
	return final_damage


func _apply_thorns(attacker: QuiverAttributes, amount: int) -> void:
	if is_instance_valid(attacker) and attacker.is_alive():
		attacker.health_current -= amount
		hit_resolved.emit(attacker, amount, false)


func _modify_knockback(
		knockback: QuiverKnockbackData, _target: QuiverAttributes, attacker: QuiverAttributes
) -> QuiverKnockbackData:
	if not enabled or knockback.strength == CombatSystem.KnockbackStrength.NONE:
		return knockback
	var tiers := roundi(_stats_for(attacker).get_value("knockback_tier"))
	if tiers > 0:
		knockback.strength = mini(
				knockback.strength + tiers, CombatSystem.KnockbackStrength.MASSIVE
		) as CombatSystem.KnockbackStrength
	return knockback


func _on_monster_health_changed(attributes: QuiverAttributes) -> void:
	var info: Dictionary = _monsters.get(attributes, {})
	var phases: Array = info.get("entry", {}).get("phases", [])
	while info.get("phase", 0) < phases.size():
		var phase: Dictionary = phases[info.phase]
		if attributes.get_health_as_percentage() >= phase.below_health:
			break
		info.phase += 1
		info.stats.add(phase.get("stats", {}))
		post_message("%s grows desperate!" % info.entry.name, COLOR_DANGER)


func _on_monster_killed(attributes: QuiverAttributes) -> void:
	var info: Dictionary = _monsters.get(attributes, {})
	if info.is_empty() or hero == null:
		return
	var entry: Dictionary = info.entry
	var monster_level: int = plan.get("monster_level", 1)

	var xp_bonus := _player_stats.get_value("xp_gain_pct") + _get_mutator_bonus("xp_bonus_pct")
	var xp_mult := 2.0 if info.is_elite else 1.0
	var xp := RbProgression.scale_xp(
			roundi(entry.xp * xp_mult), monster_level, hero.level, xp_bonus
	)
	var heal := roundi(_player_stats.get_value("life_on_kill"))
	if heal > 0 and _player_attributes != null and _player_attributes.is_alive():
		_player_attributes.health_current += heal

	var table: String = entry.get("loot_table", "trash")
	if info.is_elite and info.kind == "enemy":
		table = "elite"
	var drops := loot.roll_table(table, monster_level, _loot_rng, {
		"magic_find_pct": _player_stats.get_value("magic_find_pct"),
		"gold_find_pct": _player_stats.get_value("gold_find_pct"),
		"loot_bonus_pct": _get_mutator_bonus("loot_bonus_pct"),
	})
	_grant_drops(drops)

	post_message("+%s XP" % xp, COLOR_XP)
	var levels := hero.add_xp(xp)
	if levels > 0:
		var spent := hero.auto_allocate(registry)
		post_message("LEVEL UP! Level %s" % hero.level, COLOR_XP)
		for skill_id in spent:
			post_message("Skill: %s" % registry.get_entry("skill", skill_id).name, COLOR_XP)
		_refresh_player(true)

	if entry.get("tier", "") == "boss":
		post_message("%s defeated! Rift cleared." % entry.name, COLOR_GOLD)
		end_run(true)
	save_game()


func _grant_drops(drops: Array) -> void:
	for drop in drops:
		if drop.kind == "gold":
			hero.gold += drop.amount
			post_message("+%s gold" % drop.amount, COLOR_GOLD)
		elif drop.kind == "item":
			var item: RbItem = drop.item
			var rarity := registry.get_entry("rarity", item.rarity_id)
			var outcome := hero.receive_item(item)
			var verb: String = {"equipped": "Equipped", "stashed": "Found", "full": "Stash full:"}[outcome]
			post_message("%s %s" % [verb, item.name], Color(rarity.get("color", "#ffffff")))
	loot_dropped.emit(drops)


func _on_player_died() -> void:
	post_message("You were beaten. The rift collapses.", COLOR_DANGER)
	end_run(false)

### -----------------------------------------------------------------------------------------------
