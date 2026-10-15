extends Node

## Resolves damage and knockback between characters.
##
## Game layers built on top of the template (for example, RPG stats or equipment) can change
## combat without editing this file by adding Callables to [member damage_modifiers] and
## [member knockback_modifiers]. They are called in order, each receiving the previous result.

### Member Variables and Dependencies -------------------------------------------------------------
#--- signals --------------------------------------------------------------------------------------

## Emitted after damage is subtracted. [param attacker] is null for environmental damage.
signal damage_applied(damage: int, target: QuiverAttributes, attacker: QuiverAttributes)

#--- enums ----------------------------------------------------------------------------------------

enum CharacterTypes {
	PLAYERS,
	ENEMIES,
	BOUNCE_OBSTACLE,
}

enum HurtTypes {
	MID,
	HIGH
}

enum KnockbackStrength { 
	NONE, 
	WEAK, 
	MEDIUM, 
	STRONG, 
	MASSIVE 
}

#--- constants ------------------------------------------------------------------------------------

#--- public variables - order: export > normal var > onready --------------------------------------

## Called as [code]modifier.call(damage: int, attack: QuiverAttackData,
## target: QuiverAttributes, attacker: QuiverAttributes) -> int[/code].
var damage_modifiers: Array[Callable] = []

## Called as [code]modifier.call(knockback: QuiverKnockbackData, target: QuiverAttributes,
## attacker: QuiverAttributes) -> QuiverKnockbackData[/code].
var knockback_modifiers: Array[Callable] = []

#--- private variables - order: export > normal var > onready -------------------------------------

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

func is_in_same_lane_as(defender: QuiverAttributes, attacker: QuiverAttributes) -> bool:
	var lane_limits := defender.get_hit_lane_limits()
	var value := lane_limits.is_value_inside_lane(attacker.ground_level)
	return value


func apply_damage(
		attack: QuiverAttackData, target: QuiverAttributes, attacker: QuiverAttributes = null
) -> void:
	if target.is_invulnerable:
		return
	
	var damage := int(attack.attack_damage)
	for modifier in damage_modifiers:
		damage = modifier.call(damage, attack, target, attacker)
	
	target.health_current -= damage
	damage_applied.emit(damage, target, attacker)
	HitFreeze.start()


func apply_knockback(
		knockback: QuiverKnockbackData, 
		target: QuiverAttributes,
		attacker: QuiverAttributes = null
) -> void:
	if target.is_invulnerable:
		return
	
	for modifier in knockback_modifiers:
		knockback = modifier.call(knockback, target, attacker)
	
	target.add_knockback(knockback.strength)
	if target.should_knockout():
		if not target.is_alive():
			target.add_death_knockback()
		target.knockout_requested.emit(knockback)
	elif not target.has_superarmor:
		target.hurt_requested.emit(knockback)

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

### -----------------------------------------------------------------------------------------------

