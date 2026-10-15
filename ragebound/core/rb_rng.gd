class_name RbRng
extends RefCounted

## Deterministic random source used by every Ragebound generator.
##
## Every procedural system (rift director, loot, elite rolls) receives an [RbRng] instead of
## calling the global random functions, so that the same seed always reproduces the same run.
## Use [method fork] to derive independent sub-streams: adding a roll in one system then won't
## shift the results of another.

### Member Variables and Dependencies -------------------------------------------------------------
#--- public variables - order: export > normal var > onready --------------------------------------

var seed_value := 0

#--- private variables - order: export > normal var > onready -------------------------------------

var _rng := RandomNumberGenerator.new()

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _init(p_seed: int = 0) -> void:
	seed_value = p_seed
	_rng.seed = p_seed

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

## Returns a new independent stream derived from this stream's seed and [param label].
func fork(label: String) -> RbRng:
	return RbRng.new(hash("%s/%s" % [seed_value, label]))


func roll() -> float:
	return _rng.randf()


func float_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


## Inclusive on both ends.
func int_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func chance(probability: float) -> bool:
	return _rng.randf() < probability


func pick(array: Array):
	if array.is_empty():
		return null
	return array[_rng.randi_range(0, array.size() - 1)]


## Picks an element using the numeric [param weight_key] of each Dictionary element,
## or a parallel [param weights] array when elements aren't dictionaries.
func pick_weighted(array: Array, weight_key := "weight", weights := []):
	var total := 0.0
	for index in array.size():
		total += _weight_of(array, index, weight_key, weights)
	if total <= 0.0:
		return null

	var roll := _rng.randf() * total
	for index in array.size():
		roll -= _weight_of(array, index, weight_key, weights)
		if roll < 0.0:
			return array[index]
	return array[array.size() - 1]


func shuffle(array: Array) -> void:
	for index in range(array.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var temp = array[index]
		array[index] = array[other]
		array[other] = temp

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _weight_of(array: Array, index: int, weight_key: String, weights: Array) -> float:
	if not weights.is_empty():
		return maxf(0.0, float(weights[index]))
	var element = array[index]
	if element is Dictionary:
		return maxf(0.0, float(element.get(weight_key, 1.0)))
	return 1.0

### -----------------------------------------------------------------------------------------------
