class_name RbStatBlock
extends RefCounted

## Sums stat Dictionaries from every source and answers derived questions about them.
##
## Players are built with [method for_player] (class + level + skills + gear + set bonuses +
## mutators), monsters with [method for_monster] (monster level + enemy entry + elite modifiers +
## mutators). Both use the same stat ids from [RbStats].

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

## Monster scaling per monster level above 1.
const MONSTER_LIFE_PCT_PER_LEVEL = 12.0
const MONSTER_DAMAGE_PCT_PER_LEVEL = 8.0

#--- private variables - order: export > normal var > onready -------------------------------------

var _stats := {}

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _init(initial := {}) -> void:
	add(initial)

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

func add(stats: Dictionary, multiplier := 1.0) -> void:
	for stat_id in stats:
		var value = stats[stat_id]
		# Unrolled ranges, e.g. when previewing an affix, count as their average.
		if value is Array:
			value = (float(value[0]) + float(value[1])) / 2.0
		_stats[stat_id] = _stats.get(stat_id, 0.0) + float(value) * multiplier


## Capped value, which is what combat should use.
func get_value(stat_id: String) -> float:
	return RbStats.cap(stat_id, _stats.get(stat_id, 0.0))


func get_raw(stat_id: String) -> float:
	return _stats.get(stat_id, 0.0)


func to_dict() -> Dictionary:
	var value := {}
	for stat_id in _stats:
		value[stat_id] = get_value(stat_id)
	return value


func get_max_life(base_life: float) -> int:
	var life := (base_life + get_value("life")) * (1.0 + get_value("life_pct") / 100.0)
	return maxi(1, roundi(life))


func get_speed(base_speed: float) -> float:
	return maxf(base_speed * 0.25, base_speed * (1.0 + get_value("move_speed_pct") / 100.0))


func describe() -> PackedStringArray:
	return RbStats.describe_all(to_dict())


static func for_player(
		registry: RbContentRegistry, class_id: String, level: int,
		equipment: Dictionary = {}, skill_ranks: Dictionary = {}, extra: Array = []
) -> RbStatBlock:
	var block := RbStatBlock.new(RbStats.DEFAULTS)
	var class_entry := registry.get_entry("class", class_id)
	block.add(class_entry.get("base_stats", {}))
	block.add(class_entry.get("per_level", {}), maxi(0, level - 1))

	for skill_id in skill_ranks:
		var skill := registry.get_entry("skill", skill_id)
		if not skill.is_empty():
			block.add(skill.stats_per_rank, mini(skill_ranks[skill_id], skill.max_rank))

	var set_pieces := {}
	for slot in equipment:
		var item: RbItem = equipment[slot]
		if item == null:
			continue
		block.add(item.get_stats())
		if not item.set_id.is_empty():
			set_pieces[item.set_id] = set_pieces.get(item.set_id, 0) + 1

	for set_id in set_pieces:
		for bonus in get_active_set_bonuses(registry, set_id, set_pieces[set_id]):
			block.add(bonus.stats)

	for stats in extra:
		block.add(stats)
	return block


static func for_monster(
		monster_level: int, entry: Dictionary, elite_modifiers: Array = [], extra: Array = []
) -> RbStatBlock:
	var block := RbStatBlock.new()
	block.add({
		"life_pct": MONSTER_LIFE_PCT_PER_LEVEL * maxi(0, monster_level - 1),
		"damage_pct": MONSTER_DAMAGE_PCT_PER_LEVEL * maxi(0, monster_level - 1),
	})
	block.add(entry.get("stats", {}))
	for modifier in elite_modifiers:
		block.add(modifier.stats)
	for stats in extra:
		block.add(stats)
	return block


static func get_active_set_bonuses(
		registry: RbContentRegistry, set_id: String, pieces: int
) -> Array:
	var set_entry := registry.get_entry("set", set_id)
	return set_entry.get("bonuses", []).filter(func(bonus): return bonus.pieces <= pieces)

### -----------------------------------------------------------------------------------------------
