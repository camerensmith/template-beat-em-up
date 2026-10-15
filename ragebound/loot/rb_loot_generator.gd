class_name RbLootGenerator
extends RefCounted

## Rolls loot tables and items from registry content.
##
## Item generation follows the familiar ARPG flow:
## [br]1. Roll a rarity. Better rarities scale with the table's [code]rarity_bonus[/code] and
## the player's magic find.
## [br]2. Legendary/set rarities pick a unique whose level fits; when none fits they fall back
## to the best affix rarity.
## [br]3. Otherwise pick a base, then roll prefixes/suffixes. Each affix picks one of its tiers
## unlocked at this item level, respecting slot restrictions and exclusive groups.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const MAX_TABLE_DEPTH = 4

const RARE_NAME_FIRST = [
	"Grim", "Blood", "Iron", "Neon", "Rust", "Night", "Storm", "Brick", "Chrome", "Rage", "Gutter",
	"Riot", "Hollow", "Ember", "Vice",
]
const RARE_NAME_SECOND = {
	"weapon": ["Breaker", "Knuckle", "Crusher", "Bite", "Sermon", "Verdict"],
	"head": ["Crown", "Halo", "Visor", "Brow"],
	"chest": ["Hide", "Shell", "Coat", "Mantle"],
	"gloves": ["Grip", "Fist", "Claws", "Hands"],
	"belt": ["Cinch", "Strap", "Girdle"],
	"boots": ["Stride", "Stompers", "Treads"],
	"ring": ["Loop", "Knot", "Band", "Coil"],
	"amulet": ["Charm", "Tag", "Pendant", "Chain"],
}

#--- private variables - order: export > normal var > onready -------------------------------------

var _registry: RbContentRegistry

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _init(registry: RbContentRegistry) -> void:
	_registry = registry

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

## Rolls [param table_id] and returns drops shaped as [code]{kind = "item", item = RbItem}[/code]
## or [code]{kind = "gold", amount = int}[/code].
## [br][param bonuses] may contain [code]magic_find_pct[/code], [code]gold_find_pct[/code] and
## [code]loot_bonus_pct[/code] (more rolls-worth of quality from rift mutators).
func roll_table(table_id: String, item_level: int, rng: RbRng, bonuses := {}) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	_roll_table_into(drops, table_id, item_level, rng, bonuses, 0)
	return drops


## Generates one item. [param options] may contain [code]base[/code], [code]slot[/code],
## [code]rarity[/code], [code]rarity_bonus[/code] and [code]magic_find_pct[/code].
func generate_item(item_level: int, rng: RbRng, options := {}) -> RbItem:
	item_level = maxi(1, item_level)
	var rarity: Dictionary
	if options.has("rarity"):
		rarity = _registry.get_entry("rarity", options.rarity)
	else:
		rarity = roll_rarity(
				item_level, rng, options.get("rarity_bonus", 1.0), options.get("magic_find_pct", 0.0)
		)

	if rarity.generates in ["unique", "set"]:
		var unique := _pick_unique(rarity, item_level, rng, options)
		if not unique.is_empty():
			return _build_unique(unique, rarity, item_level, rng)
		rarity = _best_affix_rarity(item_level)

	var base := _pick_base(item_level, rng, options)
	if base.is_empty():
		push_error("No item base fits item level %s with options %s" % [item_level, options])
		return null
	return _build_affixed(base, rarity, item_level, rng)


func roll_rarity(item_level: int, rng: RbRng, rarity_bonus := 1.0, magic_find_pct := 0.0) -> Dictionary:
	var candidates := _registry.get_all("rarity").filter(
			func(rarity): return rarity.get("min_ilvl", 1) <= item_level
	)
	var weights := []
	var factor := maxf(0.0, rarity_bonus) * (1.0 + magic_find_pct / 100.0)
	for rarity in candidates:
		var weight: float = rarity.weight
		if rarity.get("magic_find_scaling", false):
			weight *= factor
		weights.append(weight)
	return rng.pick_weighted(candidates, "", weights)

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _roll_table_into(
		drops: Array[Dictionary], table_id: String, item_level: int, rng: RbRng,
		bonuses: Dictionary, depth: int
) -> void:
	var table := _registry.get_entry("loot_table", table_id)
	if table.is_empty() or depth > MAX_TABLE_DEPTH:
		return

	var rolls: Dictionary = table.get("rolls", {"min": 1, "max": 1})
	var choices: Array = table.entries.duplicate()
	choices.append({"kind": "nothing", "weight": table.get("no_drop_weight", 0.0)})
	var loot_bonus: float = 1.0 + bonuses.get("loot_bonus_pct", 0.0) / 100.0

	for _roll in rng.int_range(rolls.min, rolls.max):
		var choice: Dictionary = rng.pick_weighted(choices)
		match choice.kind:
			"item":
				var item := generate_item(item_level, rng, {
					"base": choice.get("base", ""),
					"slot": choice.get("slot", ""),
					"rarity_bonus": table.get("rarity_bonus", 1.0) * loot_bonus,
					"magic_find_pct": bonuses.get("magic_find_pct", 0.0),
				})
				if item != null:
					drops.append({"kind": "item", "item": item})
			"gold":
				var gold: Dictionary = choice.get("gold", {"min": 1, "max": 1})
				var amount := rng.int_range(gold.min, gold.max)
				amount = roundi(amount * (1.0 + bonuses.get("gold_find_pct", 0.0) / 100.0))
				drops.append({"kind": "gold", "amount": amount})
			"table":
				_roll_table_into(drops, choice.table, item_level, rng, bonuses, depth + 1)


func _pick_base(item_level: int, rng: RbRng, options: Dictionary) -> Dictionary:
	if not (options.get("base", "") as String).is_empty():
		return _registry.get_entry("item_base", options.base)

	var slot: String = options.get("slot", "")
	var candidates := _registry.get_all("item_base").filter(func(base):
		return base.get("level_req", 1) <= item_level and (slot.is_empty() or base.slot == slot)
	)
	var picked = rng.pick_weighted(candidates)
	return picked if picked != null else {}


func _pick_unique(rarity: Dictionary, item_level: int, rng: RbRng, options: Dictionary) -> Dictionary:
	var slot: String = options.get("slot", "")
	var base_id: String = options.get("base", "")
	var candidates := _registry.get_all("unique").filter(func(unique):
		if _registry.resolve_id("rarity", unique.get("rarity", "legendary")) != rarity.id:
			return false
		if unique.get("min_ilvl", 1) > item_level:
			return false
		if not base_id.is_empty() and unique.base != _registry.resolve_id("item_base", base_id):
			return false
		if not slot.is_empty() and _registry.get_entry("item_base", unique.base).slot != slot:
			return false
		return true
	)
	var picked = rng.pick_weighted(candidates)
	return picked if picked != null else {}


func _best_affix_rarity(item_level: int) -> Dictionary:
	var best := {}
	for rarity in _registry.get_all("rarity"):
		if rarity.generates != "affixes" or rarity.get("min_ilvl", 1) > item_level:
			continue
		if best.is_empty() or rarity.order > best.order:
			best = rarity
	return best


func _build_unique(unique: Dictionary, rarity: Dictionary, item_level: int, rng: RbRng) -> RbItem:
	var base := _registry.get_entry("item_base", unique.base)
	var item := _new_item(base, rarity, item_level, rng)
	item.name = unique.name
	item.unique_id = unique.id
	item.set_id = unique.get("set", "")
	item.flavor = unique.get("flavor", "")
	item.unique_stats = _roll_stats(unique.stats, rng)
	return item


func _build_affixed(base: Dictionary, rarity: Dictionary, item_level: int, rng: RbRng) -> RbItem:
	var item := _new_item(base, rarity, item_level, rng)
	var affix_range: Dictionary = rarity.get("affixes", {"min": 0, "max": 0})
	var wanted := rng.int_range(affix_range.min, affix_range.max)
	var limits := {
		"prefix": int(rarity.get("max_prefixes", 0)),
		"suffix": int(rarity.get("max_suffixes", 0)),
	}
	var used_groups := {}

	for _index in wanted:
		var candidates := _registry.get_all("affix").filter(func(affix):
			if limits[affix.kind] <= 0:
				return false
			if used_groups.has(affix.get("group", affix.id)):
				return false
			if not affix.get("slots", []).is_empty() and not item.slot in affix.slots:
				return false
			return affix.tiers.any(func(tier): return tier.min_ilvl <= item_level)
		)
		var affix = rng.pick_weighted(candidates)
		if affix == null:
			break

		var tiers := (affix.tiers as Array).filter(func(tier): return tier.min_ilvl <= item_level)
		var tier: Dictionary = rng.pick_weighted(tiers)
		item.affixes.append({
			"id": affix.id,
			"kind": affix.kind,
			"name": affix.name,
			"tier": (affix.tiers as Array).find(tier) + 1,
			"stats": _roll_stats(tier.stats, rng),
		})
		limits[affix.kind] -= 1
		used_groups[affix.get("group", affix.id)] = true

	item.name = _make_affixed_name(item, base, rarity, rng)
	return item


func _new_item(base: Dictionary, rarity: Dictionary, item_level: int, rng: RbRng) -> RbItem:
	var item := RbItem.new()
	item.uid = rng.int_range(1, 0x7FFFFFFF)
	item.base_id = base.id
	item.slot = base.slot
	item.item_type = base.item_type
	item.rarity_id = rarity.id
	item.item_level = item_level
	item.level_req = int(base.get("level_req", 1))
	item.implicit = _roll_stats(base.get("implicit", {}), rng)
	return item


func _make_affixed_name(item: RbItem, base: Dictionary, rarity: Dictionary, rng: RbRng) -> String:
	var max_affixes: int = rarity.get("affixes", {"max": 0}).max
	if max_affixes > 2:
		var second: Array = RARE_NAME_SECOND.get(item.slot, ["Relic"])
		return "%s %s" % [rng.pick(RARE_NAME_FIRST), rng.pick(second)]

	var prefix := ""
	var suffix := ""
	for affix in item.affixes:
		if affix.kind == "prefix":
			prefix = affix.name + " "
		else:
			suffix = " " + affix.name
	return "%s%s%s" % [prefix, base.name, suffix]


## Rolls [code][min, max][/code] ranges; whole-number ranges roll whole numbers.
static func _roll_stats(stats: Dictionary, rng: RbRng) -> Dictionary:
	var rolled := {}
	for stat_id in stats:
		var value = stats[stat_id]
		if value is Array:
			var low := float(value[0])
			var high := float(value[1])
			if is_equal_approx(low, roundf(low)) and is_equal_approx(high, roundf(high)):
				rolled[stat_id] = rng.int_range(roundi(low), roundi(high))
			else:
				rolled[stat_id] = snappedf(rng.float_range(low, high), 0.1)
		else:
			rolled[stat_id] = value
	return rolled

### -----------------------------------------------------------------------------------------------
