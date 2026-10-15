class_name RbProgression
extends RefCounted

## Experience curve and level rules.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const MAX_LEVEL = 50
const SKILL_POINTS_PER_LEVEL = 1

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

## Experience needed to go from [param level] to the next one.
static func xp_to_next(level: int) -> int:
	if level >= MAX_LEVEL:
		return 0
	return roundi(100.0 * pow(level, 1.5))


## Applies [param amount] of experience. Returns [code]{level, xp, levels_gained}[/code].
static func add_xp(level: int, xp: int, amount: int) -> Dictionary:
	xp += maxi(0, amount)
	var levels_gained := 0
	while level < MAX_LEVEL and xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		levels_gained += 1
	if level >= MAX_LEVEL:
		xp = 0
	return {"level": level, "xp": xp, "levels_gained": levels_gained}


## Experience falls off when the monster is far below the player, so farming stays in the rift.
static func scale_xp(base_xp: int, monster_level: int, player_level: int, bonus_pct := 0.0) -> int:
	var gap := player_level - monster_level
	var penalty := 1.0 if gap <= 3 else maxf(0.1, 1.0 - 0.15 * (gap - 3))
	var level_mult := 1.0 + 0.1 * maxi(0, monster_level - 1)
	return roundi(base_xp * level_mult * penalty * (1.0 + bonus_pct / 100.0))

### -----------------------------------------------------------------------------------------------
