class_name RbHero
extends RefCounted

## The persistent player character: class, level, gear, skills and stash.
##
## Pure data and rules, no nodes, so it can be saved, tested and shown in any UI.

### Member Variables and Dependencies -------------------------------------------------------------
#--- signals --------------------------------------------------------------------------------------

signal changed

#--- constants ------------------------------------------------------------------------------------

const MAX_INVENTORY = 60
## A skill tier unlocks every this many levels (tier 1 at level 1, tier 2 at 4, tier 3 at 7...).
const LEVELS_PER_SKILL_TIER = 3

#--- public variables - order: export > normal var > onready --------------------------------------

var character_id := ""
var class_id := ""
var level := 1
var xp := 0
var gold := 0
var skill_points := 0
## skill_id -> rank
var skill_ranks := {}
## slot -> RbItem
var equipment := {}
var inventory: Array[RbItem] = []

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

func build_stats(registry: RbContentRegistry, extra: Array = []) -> RbStatBlock:
	return RbStatBlock.for_player(registry, class_id, level, equipment, skill_ranks, extra)


## Returns how many levels were gained.
func add_xp(amount: int) -> int:
	var result := RbProgression.add_xp(level, xp, amount)
	level = result.level
	xp = result.xp
	skill_points += result.levels_gained * RbProgression.SKILL_POINTS_PER_LEVEL
	changed.emit()
	return result.levels_gained


func can_equip(item: RbItem) -> bool:
	return item != null and item.level_req <= level and item.slot in RbContentSchema.SLOTS


## Equips [param item], moving whatever was in its slot to the inventory. Returns that item.
func equip(item: RbItem) -> RbItem:
	if not can_equip(item):
		return null
	var previous: RbItem = equipment.get(item.slot)
	inventory.erase(item)
	equipment[item.slot] = item
	if previous != null:
		inventory.append(previous)
	changed.emit()
	return previous


func unequip(slot: String) -> RbItem:
	var item: RbItem = equipment.get(slot)
	if item != null:
		equipment.erase(slot)
		inventory.append(item)
		changed.emit()
	return item


## Picks up an item, auto-equipping it when the slot is empty or it is clearly better.
## Returns [code]"equipped"[/code], [code]"stashed"[/code] or [code]"full"[/code].
func receive_item(item: RbItem) -> String:
	if should_auto_equip(item):
		equip(item)
		return "equipped"
	if inventory.size() >= MAX_INVENTORY:
		return "full"
	inventory.append(item)
	changed.emit()
	return "stashed"


func should_auto_equip(item: RbItem) -> bool:
	if not can_equip(item):
		return false
	var current: RbItem = equipment.get(item.slot)
	# Never silently break up an equipped set.
	if current != null and not current.set_id.is_empty() and current.set_id != item.set_id:
		return false
	return current == null or item.get_power_score() > current.get_power_score()


func get_skill_tier_unlocked() -> int:
	return 1 + (level - 1) / LEVELS_PER_SKILL_TIER


func can_allocate(registry: RbContentRegistry, skill_id: String) -> bool:
	var skill := registry.get_entry("skill", skill_id)
	if skill.is_empty() or skill_points <= 0:
		return false
	if skill["class"] != registry.resolve_id("class", class_id):
		return false
	if skill.tier > get_skill_tier_unlocked():
		return false
	if skill_ranks.get(skill.id, 0) >= skill.max_rank:
		return false
	return skill.get("requires", []).all(func(required): return skill_ranks.get(required, 0) > 0)


func allocate_skill(registry: RbContentRegistry, skill_id: String) -> bool:
	if not can_allocate(registry, skill_id):
		return false
	var full_id := registry.resolve_id("skill", skill_id)
	skill_ranks[full_id] = skill_ranks.get(full_id, 0) + 1
	skill_points -= 1
	changed.emit()
	return true


## Spends points on the lowest tier skills first, used until there's a skill tree screen.
func auto_allocate(registry: RbContentRegistry) -> Array:
	var spent := []
	var skills := registry.get_all("skill").filter(
			func(skill): return skill["class"] == registry.resolve_id("class", class_id)
	)
	skills.sort_custom(func(a, b): return a.tier < b.tier)
	var progress := true
	while skill_points > 0 and progress:
		progress = false
		for skill in skills:
			if allocate_skill(registry, skill.id):
				spent.append(skill.id)
				progress = true
				break
	return spent


func to_dict() -> Dictionary:
	var equipped := {}
	for slot in equipment:
		equipped[slot] = equipment[slot].to_dict()
	return {
		"character_id": character_id, "class_id": class_id, "level": level, "xp": xp,
		"gold": gold, "skill_points": skill_points, "skill_ranks": skill_ranks,
		"equipment": equipped,
		"inventory": inventory.map(func(item): return item.to_dict()),
	}


static func from_dict(data: Dictionary) -> RbHero:
	var hero := RbHero.new()
	hero.character_id = data.get("character_id", "")
	hero.class_id = data.get("class_id", "")
	hero.level = int(data.get("level", 1))
	hero.xp = int(data.get("xp", 0))
	hero.gold = int(data.get("gold", 0))
	hero.skill_points = int(data.get("skill_points", 0))
	for skill_id in data.get("skill_ranks", {}):
		hero.skill_ranks[skill_id] = int(data.skill_ranks[skill_id])
	for slot in data.get("equipment", {}):
		hero.equipment[slot] = RbItem.from_dict(data.equipment[slot])
	for item_data in data.get("inventory", []):
		hero.inventory.append(RbItem.from_dict(item_data))
	return hero

### -----------------------------------------------------------------------------------------------
