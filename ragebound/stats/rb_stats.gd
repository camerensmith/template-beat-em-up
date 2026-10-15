class_name RbStats
extends RefCounted

## The shared stat vocabulary for Ragebound.
##
## Classes, levels, skills, items, affixes, elite modifiers and rift mutators all describe their
## effect as a Dictionary of [code]stat_id -> value[/code] using the ids below, so one
## [RbStatBlock] can aggregate any combination of them for players and monsters alike.
## [br][br]
## Percent stats use whole numbers ([code]25[/code] means 25%).

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const DEFINITIONS = {
	# Defense
	"life": {"name": "Life", "format": "+%d Life"},
	"life_pct": {"name": "Life %", "format": "+%d%% Life"},
	"armor": {"name": "Armor", "format": "+%d Armor"},
	"resist_all": {"name": "All Resist", "format": "+%d%% Elemental Resistance"},
	"damage_reduction_pct": {"name": "Damage Reduction", "format": "%d%% Damage Reduction"},
	"thorns": {"name": "Thorns", "format": "Attackers take %d damage"},
	# Offense
	"damage_flat": {"name": "Damage", "format": "+%d Damage"},
	"damage_pct": {"name": "Damage %", "format": "+%d%% Damage"},
	"fire_damage": {"name": "Fire Damage", "format": "+%d Fire Damage"},
	"shock_damage": {"name": "Shock Damage", "format": "+%d Shock Damage"},
	"poison_damage": {"name": "Poison Damage", "format": "+%d Poison Damage"},
	"crit_chance": {"name": "Critical Chance", "format": "+%d%% Critical Hit Chance"},
	"crit_damage_pct": {"name": "Critical Damage", "format": "+%d%% Critical Hit Damage"},
	"damage_vs_elites_pct": {"name": "Damage vs Elites", "format": "+%d%% Damage to Elites"},
	"damage_vs_bosses_pct": {"name": "Damage vs Bosses", "format": "+%d%% Damage to Bosses"},
	"knockback_tier": {"name": "Knockback", "format": "Hits knock back %d tier(s) harder"},
	"execute_threshold_pct": {
		"name": "Execute",
		"format": "Finish off non-boss enemies below %d%% Life",
	},
	# Sustain
	"life_on_hit": {"name": "Life on Hit", "format": "+%d Life per Hit"},
	"life_on_kill": {"name": "Life on Kill", "format": "+%d Life per Kill"},
	# Utility
	"move_speed_pct": {"name": "Movement Speed", "format": "+%d%% Movement Speed"},
	"xp_gain_pct": {"name": "Experience", "format": "+%d%% Experience Gained"},
	"magic_find_pct": {"name": "Magic Find", "format": "+%d%% Better Chance of Magic Items"},
	"gold_find_pct": {"name": "Gold Find", "format": "+%d%% Extra Gold"},
}

## Every fighter starts from these before class, level and gear are applied.
const DEFAULTS = {
	"crit_chance": 5,
	"crit_damage_pct": 50,
}

## Caps keep stacked gear from trivializing the combat.
const CAPS = {
	"crit_chance": 75,
	"resist_all": 75,
	"damage_reduction_pct": 60,
	"execute_threshold_pct": 30,
	"knockback_tier": 3,
	"move_speed_pct": 60,
}

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

static func is_valid(stat_id: String) -> bool:
	return DEFINITIONS.has(stat_id)


static func display_name(stat_id: String) -> String:
	return DEFINITIONS.get(stat_id, {}).get("name", stat_id)


static func describe(stat_id: String, value: float) -> String:
	var definition: Dictionary = DEFINITIONS.get(stat_id, {})
	if definition.is_empty():
		return "%s: %s" % [stat_id, value]
	return definition["format"] % [roundi(value)]


## Describes a whole stat Dictionary as a list of lines, in [constant DEFINITIONS] order.
static func describe_all(stats: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for stat_id in DEFINITIONS:
		if stats.has(stat_id) and not is_zero_approx(float(stats[stat_id])):
			lines.append(describe(stat_id, float(stats[stat_id])))
	return lines


static func cap(stat_id: String, value: float) -> float:
	if CAPS.has(stat_id):
		return minf(value, CAPS[stat_id])
	return value

### -----------------------------------------------------------------------------------------------
