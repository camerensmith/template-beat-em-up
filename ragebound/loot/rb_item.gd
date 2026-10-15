class_name RbItem
extends RefCounted

## A rolled piece of equipment.
##
## Items only store ids and rolled numbers, never references to content entries, so they can be
## saved with [method to_dict] and still load if a mod later rebalances the ranges.

### Member Variables and Dependencies -------------------------------------------------------------
#--- public variables - order: export > normal var > onready --------------------------------------

var uid := 0
var base_id := ""
var name := ""
var slot := ""
var item_type := ""
var rarity_id := ""
var item_level := 1
var level_req := 1
## For legendary and set items.
var unique_id := ""
var set_id := ""
var flavor := ""
## Rolled base stats.
var implicit := {}
## Array of [code]{id, kind, name, tier, stats}[/code].
var affixes: Array[Dictionary] = []
## Rolled unique stats.
var unique_stats := {}

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

## All stats this item grants, summed.
func get_stats() -> Dictionary:
	var total := {}
	_sum_into(total, implicit)
	_sum_into(total, unique_stats)
	for affix in affixes:
		_sum_into(total, affix.stats)
	return total


## A rough single number for "is this better?" decisions, such as auto-equipping drops.
func get_power_score() -> float:
	const WEIGHTS = {
		"damage_flat": 4.0, "damage_pct": 1.0, "fire_damage": 3.0, "shock_damage": 3.0,
		"poison_damage": 3.0, "crit_chance": 2.0, "crit_damage_pct": 0.5, "life": 0.8,
		"life_pct": 1.5, "armor": 0.4, "resist_all": 0.5, "knockback_tier": 15.0,
		"execute_threshold_pct": 2.5, "life_on_hit": 3.0, "life_on_kill": 1.5,
		"move_speed_pct": 0.6, "damage_reduction_pct": 2.0, "thorns": 1.5,
	}
	var score := 0.0
	var stats := get_stats()
	for stat_id in stats:
		score += float(stats[stat_id]) * WEIGHTS.get(stat_id, 0.3)
	return score


func describe() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(name)
	lines.append("%s %s  (item level %s)" % [rarity_id.get_slice(":", 1).capitalize(),
			slot.capitalize(), item_level])
	lines.append_array(RbStats.describe_all(get_stats()))
	if not flavor.is_empty():
		lines.append('"%s"' % flavor)
	return lines


func to_dict() -> Dictionary:
	return {
		"uid": uid, "base_id": base_id, "name": name, "slot": slot, "item_type": item_type,
		"rarity_id": rarity_id, "item_level": item_level, "level_req": level_req,
		"unique_id": unique_id, "set_id": set_id, "flavor": flavor,
		"implicit": implicit, "affixes": affixes, "unique_stats": unique_stats,
	}


static func from_dict(data: Dictionary) -> RbItem:
	const INT_KEYS = ["uid", "item_level", "level_req"]
	var item := RbItem.new()
	for key in data:
		if key == "affixes":
			for affix in data.affixes:
				item.affixes.append(affix)
		elif key in INT_KEYS:
			item.set(key, int(data[key]))
		elif key in item:
			item.set(key, data[key])
	return item

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

static func _sum_into(total: Dictionary, stats: Dictionary) -> void:
	for stat_id in stats:
		total[stat_id] = total.get(stat_id, 0) + stats[stat_id]

### -----------------------------------------------------------------------------------------------
