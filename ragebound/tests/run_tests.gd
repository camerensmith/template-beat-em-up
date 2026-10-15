extends SceneTree

## Headless test runner for Ragebound's systems.
##
## Run from the project folder:
## [codeblock]
## godot --headless -s res://ragebound/tests/run_tests.gd
## [/codeblock]
## Every method starting with [code]test_[/code] runs and must end with [code]return true[/code],
## so a test aborted by a script error is reported as a failure. The process exits with code 1
## on any failure.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const BASE_ROOTS = ["res://mods"]
const EXAMPLE_ROOTS = ["res://mods", "res://examples/mods"]
const BROKEN_ROOTS = ["res://mods", "res://ragebound/tests/fixtures/broken_mods"]
const TEMP_DIR = "user://ragebound_tests"

#--- private variables - order: export > normal var > onready -------------------------------------

var _failures := PackedStringArray()
var _checks := 0
var _current_test := ""
var _base: RbContentRegistry

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _init() -> void:
	_base = _load(BASE_ROOTS)
	var tests := get_method_list().map(func(method): return method.name).filter(
			func(method_name): return method_name.begins_with("test_")
	)
	for test in tests:
		_current_test = test
		var failures_before := _failures.size()
		# A script error aborts the test and makes call() return null instead of true.
		if call(test) != true:
			_failures.append("%s: crashed before finishing (see SCRIPT ERROR above)" % test)
		print("%s %s" % ["PASS" if _failures.size() == failures_before else "FAIL", test])

	_cleanup_temp()
	print("\n%s checks, %s tests, %s failure(s)" % [_checks, tests.size(), _failures.size()])
	for failure in _failures:
		print("  - " + failure)
	quit(1 if not _failures.is_empty() else 0)

### -----------------------------------------------------------------------------------------------


### Tests: content registry -----------------------------------------------------------------------

func test_base_content_is_valid() -> bool:
	_check(_base.errors.is_empty(), "base content errors:\n%s" % "\n".join(_base.errors))
	_check(_base.warnings.is_empty(), "base content warnings: %s" % [_base.warnings])
	for content_type in ["class", "enemy", "boss", "item_base", "affix", "rarity", "unique",
			"stage_segment", "encounter", "rift", "elite_modifier", "skill"]:
		_check(_base.count(content_type) > 0, "no %s content" % content_type)
	_check_equal(_base.count("class"), 10, "all ten classes ship")
	return true


func test_ids_are_namespaced_and_short_ids_resolve() -> bool:
	_check(_base.get_ids("enemy").has("base_game:street_thug"), "ids get the mod namespace")
	_check_equal(_base.resolve_id("enemy", "street_thug"), "base_game:street_thug", "short id")
	_check_equal(_base.resolve_id("enemy", "nope"), "", "unknown id")
	var unique := _base.get_entry("unique", "pile_drivers")
	_check_equal(unique.base, "base_game:fingerless_gloves", "references are rewritten to full ids")
	var table := _base.get_entry("loot_table", "boss")
	_check_equal(table.entries[0].kind, "item", "nested dicts survive resolution")
	return true


func test_example_pack_extends_patches_and_overrides() -> bool:
	var registry := _load(EXAMPLE_ROOTS)
	_check(registry.errors.is_empty(), "example pack errors:\n%s" % "\n".join(registry.errors))
	_check_equal(registry.mods[0].id, "base_game", "dependencies load first")
	_check(registry.has_entry("boss", "example_community_pack:chrome_reaper"), "new boss added")

	var thug := registry.get_entry("enemy", "base_game:street_thug")
	_check_equal(thug.stats.get("life_pct"), 15.0, "patch changed one stat")
	_check_equal(thug.archetype, "grunt", "patch kept untouched fields")
	_check_equal(thug.weight, 4.0, "patch changed weight")

	var mutator := registry.get_entry("mutator", "base_game:glass_cannon")
	_check_equal(mutator.name, "Glass Cannon+", "override replaced the entry")
	_check_equal(mutator._mod, "example_community_pack", "override is owned by the mod")

	var spoils := registry.get_entry("loot_table", "reaper_spoils")
	_check_equal(spoils.entries[1].table, "base_game:boss", "explicit namespaced ref")
	var grip := registry.get_entry("unique", "reapers_grip")
	_check_equal(grip.base, "base_game:mma_gloves", "short ref resolves through dependencies")
	var plated := registry.get_entry("elite_modifier", "chrome_plated")
	_check_equal(plated.incompatible, ["base_game:armored"], "refs inside arrays resolve")
	_check(registry.notes.size() >= 2, "patches and overrides are logged")
	return true


func test_broken_mods_are_reported() -> bool:
	var registry := _load(BROKEN_ROOTS)
	var all_errors := "\n".join(registry.errors)
	for expected in [
		"lowercase snake_case",
		"expected one of",
		"must be at least 1",
		"must be a whole number",
		"is not a known stat",
		"unknown field 'colour'",
		"file not found",
		"points to unknown loot_table 'does_not_exist'",
		"missing required field 'slot'",
		"range has min greater than max",
		"tiers must be sorted",
		"patch target does not exist",
		"broken.json",
		"missing dependency 'not_installed'",
		"dependency cycle",
		"needs ragebound_api 99",
	]:
		_check(all_errors.contains(expected), "expected an error containing '%s'" % expected)
	_check(registry.has_mod("base_game"), "good mods still load next to broken ones")
	_check(not registry.has_mod("cycle_a"), "mods in a cycle are skipped")
	_check(registry.count("rift") == _base.count("rift"), "unparseable files add nothing")
	return true

### -----------------------------------------------------------------------------------------------


### Tests: random, loot and stats ---------------------------------------------------------------

func test_rng_is_deterministic_and_forks_are_independent() -> bool:
	var first := RbRng.new(99)
	var second := RbRng.new(99)
	var same := true
	for _index in 50:
		same = same and first.int_range(0, 1000) == second.int_range(0, 1000)
	_check(same, "same seed gives same sequence")
	_check(RbRng.new(99).fork("a").roll() != RbRng.new(99).fork("b").roll(), "forks differ")
	_check_equal(RbRng.new(99).fork("a").roll(), RbRng.new(99).fork("a").roll(), "forks repeat")
	var weighted := RbRng.new(5)
	var picks := {}
	for _index in 2000:
		var pick = weighted.pick_weighted([{"id": "a", "weight": 9}, {"id": "b", "weight": 1}])
		picks[pick.id] = picks.get(pick.id, 0) + 1
	_check(picks.a > picks.b * 5, "weights are respected: %s" % [picks])
	return true


func test_loot_is_deterministic() -> bool:
	var generator := RbLootGenerator.new(_base)
	_check_equal(_roll_items(generator, 42, 40), _roll_items(generator, 42, 40), "same seed, same loot")
	_check(_roll_items(generator, 42, 40) != _roll_items(generator, 43, 40), "seeds change loot")
	return true


func test_affixes_follow_rarity_level_slot_and_group_rules() -> bool:
	var generator := RbLootGenerator.new(_base)
	var rng := RbRng.new(7)
	for item_level in [1, 5, 12, 20]:
		for _index in 300:
			var item := generator.generate_item(item_level, rng, {"rarity_bonus": 20})
			var rarity := _base.get_entry("rarity", item.rarity_id)
			_check(rarity.get("min_ilvl", 1) <= item_level, "%s dropped below its min ilvl" % rarity.id)
			_check(item.level_req <= item_level, "%s base above item level" % item.base_id)
			if rarity.generates != "affixes":
				continue
			_check(item.affixes.size() <= rarity.affixes.max, "too many affixes on %s" % item.name)
			var kinds := {"prefix": 0, "suffix": 0}
			var groups := {}
			for rolled in item.affixes:
				var affix := _base.get_entry("affix", rolled.id)
				kinds[rolled.kind] += 1
				var group: String = affix.get("group", affix.id)
				_check(not groups.has(group), "duplicate affix group %s" % group)
				groups[group] = true
				var tier: Dictionary = affix.tiers[rolled.tier - 1]
				_check(tier.min_ilvl <= item_level, "tier above item level on %s" % item.name)
				_check(affix.get("slots", []).is_empty() or item.slot in affix.slots,
						"%s on wrong slot %s" % [affix.id, item.slot])
				for stat_id in rolled.stats:
					var bounds: Array = tier.stats[stat_id]
					_check(rolled.stats[stat_id] >= bounds[0] and rolled.stats[stat_id] <= bounds[1],
							"%s rolled outside %s" % [stat_id, bounds])
			_check(kinds.prefix <= rarity.max_prefixes, "too many prefixes")
			_check(kinds.suffix <= rarity.max_suffixes, "too many suffixes")
	return true


func test_rarity_gates_and_magic_find() -> bool:
	var generator := RbLootGenerator.new(_base)
	var rng := RbRng.new(11)
	var low_level := {}
	for _index in 1000:
		var rarity := generator.roll_rarity(1, rng, 50.0)
		low_level[rarity.id] = true
	_check(not low_level.has("base_game:rare"), "no rares at item level 1")
	_check(not low_level.has("base_game:legendary"), "no legendaries at item level 1")

	var plain := 0
	var lucky := 0
	for _index in 3000:
		if generator.roll_rarity(20, rng).order > 0:
			plain += 1
		if generator.roll_rarity(20, rng, 1.0, 300.0).order > 0:
			lucky += 1
	_check(lucky > plain * 1.5, "magic find raises quality (%s vs %s)" % [lucky, plain])
	return true


func test_uniques_roll_inside_their_ranges() -> bool:
	var generator := RbLootGenerator.new(_base)
	var rng := RbRng.new(3)
	var seen := {}
	for _index in 200:
		var item := generator.generate_item(20, rng, {"rarity": "legendary"})
		_check(not item.unique_id.is_empty(), "legendary rarity produces a unique")
		seen[item.unique_id] = true
		var unique := _base.get_entry("unique", item.unique_id)
		for stat_id in unique.stats:
			var bounds = unique.stats[stat_id]
			var value = item.unique_stats[stat_id]
			if bounds is Array:
				_check(value >= bounds[0] and value <= bounds[1], "%s out of range" % stat_id)
	_check(seen.size() >= 4, "different legendaries drop: %s" % [seen.keys()])

	var fallback := generator.generate_item(1, rng, {"rarity": "legendary"})
	_check(fallback.unique_id.is_empty(), "no unique fits ilvl 1, so it falls back to affixes")
	return true


func test_loot_tables_drop_items_and_gold() -> bool:
	var generator := RbLootGenerator.new(_base)
	var rng := RbRng.new(21)
	var kinds := {}
	for _index in 100:
		var drops := generator.roll_table("boss", 10, rng)
		_check(drops.size() >= 3 and drops.size() <= 5, "boss rolls 3-5 times, got %s" % drops.size())
		for drop in drops:
			kinds[drop.kind] = true
	_check(kinds.has("item") and kinds.has("gold"), "boss drops items and gold")

	var example := _load(EXAMPLE_ROOTS)
	var nested := RbLootGenerator.new(example).roll_table("reaper_spoils", 10, RbRng.new(1))
	_check(nested.size() >= 3, "nested tables roll")
	return true


func test_set_bonuses_and_player_stats() -> bool:
	var generator := RbLootGenerator.new(_base)
	var rng := RbRng.new(8)
	var equipment := {}
	for unique_id in ["syndicate_knuckles", "syndicate_jacket"]:
		var unique := _base.get_entry("unique", unique_id)
		var item := generator.generate_item(10, rng, {"rarity": "set", "base": unique.base})
		_check_equal(item.unique_id, unique.id, "set piece rolled from its base")
		equipment[item.slot] = item

	var two_pieces := RbStatBlock.for_player(_base, "grappler", 1, equipment)
	_check_equal(two_pieces.get_value("knockback_tier"), 0.0, "3 piece bonus inactive at 2")
	var unique_boots := _base.get_entry("unique", "syndicate_boots")
	var boots := generator.generate_item(10, rng, {"rarity": "set", "base": unique_boots.base})
	equipment[boots.slot] = boots
	var three_pieces := RbStatBlock.for_player(_base, "grappler", 1, equipment)
	_check_equal(three_pieces.get_value("knockback_tier"), 1.0, "3 piece bonus active")

	var grappler := RbStatBlock.for_player(_base, "grappler", 5)
	_check_equal(grappler.get_value("life"), 62.0, "class base + 4 levels of growth")
	_check_equal(grappler.get_max_life(100), 162, "life adds to the body's base health")
	_check_equal(grappler.get_value("crit_chance"), 5.0, "global defaults apply")

	var capped := RbStatBlock.new({"crit_chance": 500})
	_check_equal(capped.get_value("crit_chance"), 75.0, "caps apply")
	return true


func test_combat_math() -> bool:
	var attacker := RbStatBlock.new({"damage_flat": 5, "damage_pct": 100})
	var defender := RbStatBlock.new({"armor": 100})
	var hit := RbCombatMath.resolve_hit(10, attacker, defender, RbRng.new(1))
	_check_equal(hit.damage, 15, "(10 + 5) * 2 halved by 100 armor")
	_check(not hit.is_crit, "no crit chance, no crit")

	var elemental := RbStatBlock.new({"fire_damage": 10})
	var resistant := RbStatBlock.new({"resist_all": 50, "damage_reduction_pct": 50})
	_check_equal(RbCombatMath.resolve_hit(10, elemental, resistant, RbRng.new(1)).damage, 8,
			"(10 physical + 10 fire * 0.5 resist) * 0.5 reduction = 7.5, rounded")

	var critter := RbStatBlock.new({"crit_chance": 75, "crit_damage_pct": 100})
	var crits := 0
	var rng := RbRng.new(2)
	for _index in 400:
		var result := RbCombatMath.resolve_hit(10, critter, RbStatBlock.new(), rng)
		if result.is_crit:
			crits += 1
			_check_equal(result.damage, 20, "crit doubles")
	_check(crits > 250 and crits < 350, "crit rate near 75%%, got %s/400" % crits)

	var slayer := RbStatBlock.new({"damage_vs_bosses_pct": 50})
	_check_equal(RbCombatMath.resolve_hit(10, slayer, RbStatBlock.new(), rng, {"is_boss": true}).damage,
			15, "boss damage bonus")
	_check_equal(RbCombatMath.resolve_hit(0, slayer, RbStatBlock.new(), rng).damage, 0,
			"zero damage hits stay zero")

	var executioner := RbStatBlock.new({"execute_threshold_pct": 10})
	_check(RbCombatMath.should_execute(0.05, executioner, false), "executes below threshold")
	_check(not RbCombatMath.should_execute(0.05, executioner, true), "never executes bosses")
	_check(not RbCombatMath.should_execute(0.2, executioner, false), "not above threshold")
	return true


func test_monster_scaling() -> bool:
	var thug := _base.get_entry("enemy", "street_thug")
	var level_one := RbStatBlock.for_monster(1, thug)
	var level_six := RbStatBlock.for_monster(6, thug)
	_check_equal(level_one.get_max_life(50), 50, "level 1 monsters use their body's health")
	_check_equal(level_six.get_max_life(50), 80, "+12% life per level")
	var berserker := _base.get_entry("elite_modifier", "berserker")
	var elite := RbStatBlock.for_monster(1, thug, [berserker])
	_check_equal(elite.get_value("damage_pct"), 50.0, "elite modifiers add stats")
	return true


func test_progression() -> bool:
	_check_equal(RbProgression.xp_to_next(1), 100, "level 1 needs 100 xp")
	var result := RbProgression.add_xp(1, 0, 350)
	_check_equal(result.level, 2, "350 xp reaches level 2")
	_check_equal(result.xp, 250, "remainder carries over")
	_check_equal(RbProgression.add_xp(49, 0, 99999999).level, RbProgression.MAX_LEVEL, "cap")
	_check(RbProgression.scale_xp(10, 1, 20) < RbProgression.scale_xp(10, 1, 1), "low monsters give less")
	return true


func test_hero_equipment_skills_and_saves() -> bool:
	var hero := RbHero.new()
	hero.class_id = "base_game:brawler"
	_check(not hero.allocate_skill(_base, "brawler_iron_fists"), "no points at level 1")
	hero.add_xp(100 + 283 + 520)
	_check_equal(hero.level, 4, "level 4")
	_check_equal(hero.skill_points, 3, "a point per level")
	_check(not hero.allocate_skill(_base, "brawler_combo_flow"), "prerequisite enforced")
	_check(not hero.allocate_skill(_base, "grappler_grip"), "other class skills refused")
	_check(hero.allocate_skill(_base, "brawler_iron_fists"), "tier 1 skill")
	_check(hero.allocate_skill(_base, "brawler_combo_flow"), "tier 2 unlocked at level 4")
	_check(not hero.allocate_skill(_base, "brawler_finisher"), "tier 3 locked until level 7")
	_check_equal(hero.auto_allocate(_base).size(), 1, "auto allocation spends the rest")
	_check_equal(hero.skill_points, 0, "no points left")

	var generator := RbLootGenerator.new(_base)
	var rng := RbRng.new(4)
	var weak := generator.generate_item(1, rng, {"base": "brass_knuckles", "rarity": "common"})
	var strong := generator.generate_item(1, rng, {"base": "brass_knuckles", "rarity": "common"})
	strong.implicit["damage_flat"] = 50
	_check_equal(hero.receive_item(weak), "equipped", "empty slot auto-equips")
	_check_equal(hero.receive_item(strong), "equipped", "better item auto-equips")
	_check(hero.inventory.has(weak), "replaced item goes to the stash")
	var heavy := generator.generate_item(30, rng, {"base": "katana", "rarity": "common"})
	_check_equal(hero.receive_item(heavy), "stashed", "items above your level are stashed")

	var saved := JSON.stringify(hero.to_dict())
	var restored := RbHero.from_dict(JSON.parse_string(saved))
	_check_equal(JSON.stringify(restored.to_dict()), saved, "save round trip")
	_check_equal(
			JSON.stringify(restored.build_stats(_base).to_dict()),
			JSON.stringify(hero.build_stats(_base).to_dict()),
			"restored hero has the same stats"
	)
	return true

### -----------------------------------------------------------------------------------------------


### Tests: rift director --------------------------------------------------------------------------

func test_rift_generation_is_deterministic() -> bool:
	var director := RbRiftDirector.new(_base)
	var first := JSON.stringify(director.generate(1234, {"rift": "downtown_rift", "level": 3}))
	var second := JSON.stringify(director.generate(1234, {"rift": "downtown_rift", "level": 3}))
	_check_equal(first, second, "same seed, same rift")
	var different := false
	for seed_value in range(1, 10):
		if JSON.stringify(director.generate(seed_value, {"rift": "downtown_rift"})) != first:
			different = true
	_check(different, "seeds change the rift")
	return true


func test_rifts_are_always_legal() -> bool:
	for roots in [BASE_ROOTS, EXAMPLE_ROOTS]:
		var registry := _load(roots)
		var director := RbRiftDirector.new(registry)
		for template in registry.get_all("rift"):
			for level in range(1, 7):
				for sample in 40:
					var plan := director.generate(sample * 7919 + level, {
						"rift": template.id, "level": level,
					})
					_check_plan(registry, template, plan)
	return true


func test_bosses_respect_arena_requirements() -> bool:
	var director := RbRiftDirector.new(_base)
	var butcher_rooms := {}
	for sample in 300:
		var plan := director.generate(sample, {"rift": "industrial_rift", "level": 5})
		if plan.boss == "base_game:iron_butcher":
			butcher_rooms[plan.rooms.back().segment] = true
	_check_equal(butcher_rooms.keys(), ["base_game:slaughterhouse_floor"],
			"the Butcher only fits the slaughterhouse")

	var low := director.generate(1, {"rift": "industrial_rift", "level": 1})
	_check(low.boss != "base_game:iron_butcher", "the Butcher needs rift level 3")
	return true


func test_template_validation_passes() -> bool:
	_check_equal(RbRiftDirector.new(_base).check_templates(10, 6), PackedStringArray(),
			"base templates validate")
	_check_equal(RbRiftDirector.new(_load(EXAMPLE_ROOTS)).check_templates(10, 6),
			PackedStringArray(), "example templates validate")
	return true

### -----------------------------------------------------------------------------------------------


### Tests: sprite packs ---------------------------------------------------------------------------

func test_sprite_pack_qualification_and_import() -> bool:
	var pack := _make_sprite_pack()
	var qualified := RbSpritePackImporter.qualify(pack)
	_check_equal(qualified.problems, [], "complete pack has no problems")
	for role in ["playable", "enemy", "miniboss", "boss"]:
		_check(role in qualified.roles, "complete pack qualifies as %s" % role)

	var enemy_only := _make_sprite_pack()
	for animation_name in ["punch_2", "punch_3", "air_attack", "jump_impulse"]:
		enemy_only.animations.erase(animation_name)
	var enemy_result := RbSpritePackImporter.qualify(enemy_only)
	_check_equal(enemy_result.roles, ["enemy"], "one attack and no jumps: enemy only")
	_check(enemy_result.missing.playable.has("jump_impulse"), "reports what's missing")

	var broken := _make_sprite_pack()
	broken.animations.punch_1.erase("hit_frames")
	broken.animations.erase("die")
	var broken_result := RbSpritePackImporter.qualify(broken)
	_check(broken_result.roles.is_empty(), "missing core animation blocks every role")
	_check(str(broken_result.problems).contains("hit_frames"), "attacks need hit frames")

	var sheet_path := _write_sheet(pack, 12, 10)
	pack.sheet = sheet_path
	var imported := RbSpritePackImporter.import_pack(pack)
	_check_equal(imported.problems, [], "import succeeds")
	var frames: SpriteFrames = imported.frames
	_check_equal(frames.get_frame_count("walk"), 6, "frames per animation")
	var atlas: AtlasTexture = frames.get_frame_texture("walk", 2)
	_check_equal(atlas.region, Rect2(64, 32, 32, 32), "frames cut on the grid")

	var too_small := _make_sprite_pack()
	too_small.sheet = _write_sheet(too_small, 4, 10)
	_check(not RbSpritePackImporter.import_pack(too_small).problems.is_empty(), "bounds checked")
	return true


func test_sprite_pack_loads_from_a_user_mod() -> bool:
	var mod_root := TEMP_DIR.path_join("mods/sprite_mod")
	DirAccess.make_dir_recursive_absolute(mod_root.path_join("sprite_packs"))
	_write_json(mod_root.path_join("manifest.json"), {
		"id": "sprite_mod", "name": "Sprites", "version": "1", "ragebound_api": 1,
	})
	var pack := _make_sprite_pack()
	pack.erase("sheet")
	pack.id = "test_fighter"
	pack.name = "Test Fighter"
	var sheet := _write_sheet(pack, 12, 10)
	DirAccess.copy_absolute(sheet, mod_root.path_join("sprite_packs/test_fighter.png"))
	pack.sheet = "sprite_packs/test_fighter.png"
	_write_json(mod_root.path_join("sprite_packs/test_fighter.json"), pack)

	var registry := _load(["res://mods", TEMP_DIR.path_join("mods")])
	_check(registry.errors.is_empty(), "user mod errors: %s" % [registry.errors])
	var entry := registry.get_entry("sprite_pack", "test_fighter")
	_check_equal(entry.get("sheet"), mod_root.path_join("sprite_packs/test_fighter.png"),
			"relative paths resolve inside the mod")
	_check_equal(RbSpritePackImporter.import_pack(entry).roles.size(), 4, "imported from user://")
	return true

### -----------------------------------------------------------------------------------------------


### Helpers ---------------------------------------------------------------------------------------

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("%s: %s" % [_current_test, message])


func _check_equal(actual, expected, message: String) -> void:
	_checks += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		_failures.append("%s: %s (expected %s, got %s)" % [
				_current_test, message, var_to_str(expected), var_to_str(actual)
		])


func _load(roots: Array) -> RbContentRegistry:
	var registry := RbContentRegistry.new()
	registry.load_mods(roots)
	return registry


func _roll_items(generator: RbLootGenerator, seed_value: int, amount: int) -> String:
	var rng := RbRng.new(seed_value)
	var items := []
	for _index in amount:
		items.append(generator.generate_item(1 + _index % 20, rng, {"rarity_bonus": 5}).to_dict())
	return JSON.stringify(items)


func _check_plan(registry: RbContentRegistry, template: Dictionary, plan: Dictionary) -> void:
	var label := "%s seed %s level %s" % [template.id, plan.seed, plan.level]
	if not plan.errors.is_empty():
		_check(false, "%s failed: %s" % [label, plan.errors])
		return
	var previous := {}
	for room in plan.rooms:
		var segment := registry.get_entry("stage_segment", room.segment)
		_check(room.role in segment.roles, "%s: segment can't host %s" % [label, room.role])
		_check(segment.theme in template.themes, "%s: theme %s off template" % [label, segment.theme])
		_check(segment.get("min_depth", 0) <= plan.level, "%s: segment too deep" % label)
		if not previous.is_empty():
			var connects: bool = previous.get("exit", []).any(
					func(tag): return tag in segment.get("entry", [])
			)
			_check(connects, "%s: %s does not connect to %s" % [label, previous.id, segment.id])
		previous = segment

		var leader_found := false
		for spawn in room.spawns:
			if spawn.kind == "enemy":
				var enemy := registry.get_entry("enemy", spawn.id)
				_check(enemy.get("min_depth", 0) <= plan.level, "%s: enemy too deep" % label)
				_check(enemy.get("themes", []).is_empty() or room.theme in enemy.themes,
						"%s: %s outside its themes" % [label, enemy.id])
				for elite_id in spawn.elite:
					var modifier := registry.get_entry("elite_modifier", elite_id)
					for other_id in spawn.elite:
						_check(not other_id in modifier.get("incompatible", []),
								"%s: incompatible elites %s + %s" % [label, elite_id, other_id])
				leader_found = leader_found or not spawn.elite.is_empty()
			else:
				var boss := registry.get_entry("boss", spawn.id)
				_check(room.theme in boss.themes, "%s: %s outside its themes" % [label, boss.id])
				_check(segment.width >= boss.arena.min_width and segment.depth >= boss.arena.min_depth,
						"%s: %s arena too small" % [label, boss.id])
				leader_found = true
		if room.role == "elite":
			_check(leader_found, "%s: elite room without an elite or miniboss" % label)
		if room.role == "boss":
			_check(room.spawns[0].id == plan.boss and room.spawns[0].kind == "boss",
					"%s: boss room must open with the boss" % label)

	if template.steps.back().role == "boss":
		_check_equal(plan.rooms.back().role, "boss", "%s: ends with the boss" % label)


func _make_sprite_pack() -> Dictionary:
	var names := RbSpritePackImporter.CORE_ANIMATIONS + [
		"punch_1", "punch_2", "punch_3", "jump_impulse", "jump_rising", "jump_falling",
		"jump_landing", "air_attack",
	]
	var animations := {}
	for index in names.size():
		var animation := {"row": index % 10, "column": 6 * (index / 10), "frames": 6, "fps": 12}
		if RbSpritePackImporter.is_attack(names[index]):
			animation["hit_frames"] = [3]
		animations[names[index]] = animation
	return {
		"id": "test_pack", "name": "Test Pack", "sheet": "",
		"cell": {"width": 32, "height": 32}, "animations": animations,
	}


func _write_sheet(pack: Dictionary, columns: int, rows: int) -> String:
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	var image := Image.create(columns * pack.cell.width, rows * pack.cell.height, false,
			Image.FORMAT_RGBA8)
	image.fill(Color.MAGENTA)
	var path := TEMP_DIR.path_join("sheet_%sx%s.png" % [columns, rows])
	image.save_png(path)
	return path


func _write_json(path: String, data) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))


func _cleanup_temp() -> void:
	_remove_recursive(ProjectSettings.globalize_path(TEMP_DIR))


func _remove_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for folder in dir.get_directories():
		_remove_recursive(path.path_join(folder))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)

### -----------------------------------------------------------------------------------------------
