class_name RbCombatMath
extends RefCounted

## Pure damage formulas, kept free of nodes so they can be unit tested and tuned in one place.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const ELEMENTS = ["fire_damage", "shock_damage", "poison_damage"]
## Armor needed to halve physical damage.
const ARMOR_HALF_POINT = 100.0

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

## Resolves one hit. [param context] may set [code]is_elite[/code] and [code]is_boss[/code] for
## the defender. Returns [code]{damage: int, is_crit: bool, physical: float, elemental: float}[/code].
static func resolve_hit(
		base_damage: float, attacker: RbStatBlock, defender: RbStatBlock, rng: RbRng,
		context := {}
) -> Dictionary:
	var damage_mult := 1.0 + attacker.get_value("damage_pct") / 100.0
	if context.get("is_elite", false):
		damage_mult *= 1.0 + attacker.get_value("damage_vs_elites_pct") / 100.0
	if context.get("is_boss", false):
		damage_mult *= 1.0 + attacker.get_value("damage_vs_bosses_pct") / 100.0
	damage_mult = maxf(0.1, damage_mult)

	var physical := (base_damage + attacker.get_value("damage_flat")) * damage_mult
	var is_crit := rng.chance(attacker.get_value("crit_chance") / 100.0)
	if is_crit:
		physical *= 1.0 + attacker.get_value("crit_damage_pct") / 100.0
	physical *= get_armor_multiplier(defender.get_value("armor"))

	var elemental := 0.0
	for element in ELEMENTS:
		elemental += attacker.get_value(element)
	elemental *= damage_mult * (1.0 - clampf(defender.get_value("resist_all"), 0.0, 100.0) / 100.0)

	var total := (physical + elemental) * (
			1.0 - clampf(defender.get_value("damage_reduction_pct"), 0.0, 100.0) / 100.0
	)
	return {
		"damage": maxi(1, roundi(total)) if base_damage > 0 else 0,
		"is_crit": is_crit,
		"physical": physical,
		"elemental": elemental,
	}


static func get_armor_multiplier(armor: float) -> float:
	return ARMOR_HALF_POINT / (ARMOR_HALF_POINT + maxf(0.0, armor))


## Whether a hit that left the target at [param health_ratio] should finish it off.
static func should_execute(health_ratio: float, attacker: RbStatBlock, is_boss: bool) -> bool:
	if is_boss or health_ratio <= 0.0:
		return false
	return health_ratio * 100.0 < attacker.get_value("execute_threshold_pct")

### -----------------------------------------------------------------------------------------------
