class_name RbRiftRoom
extends Node2D

## Runs one room of an assembled rift: trigger, camera lock, waves, events and rewards.
##
## Created by [RbRiftStage] for each room of the plan and positioned at the room's left edge.
## When the player walks past the trigger line the camera locks to the room, the planned spawns
## walk in from off screen in waves, and [signal cleared] fires once every one of them is gone.

### Member Variables and Dependencies -------------------------------------------------------------
#--- signals --------------------------------------------------------------------------------------

signal started
signal cleared

#--- enums ----------------------------------------------------------------------------------------

enum State { WAITING, ACTIVE, CLEARED }

#--- constants ------------------------------------------------------------------------------------

const MAX_WAVE_SIZE = 4
const ENTRANCE_MARGIN = 160.0
const CAMERA_TRANSITION = 0.6
const SEATED_ENGAGE_DELAY = 1.5
## The Tax Man only listens for "engaged" once his reveal animation ends, so the signal is
## repeated until he actually stands up.
const ENGAGE_RETRY_SECONDS = 0.5
const EVENT_REWARDS = {
	"rescue": {"table": "elite", "text": "Hostage rescued! They slip you something."},
	"challenge": {"table": "miniboss", "text": "Challenge won! The crowd pays out."},
}
const SHOP_COST_PER_LEVEL = 10

#--- public variables - order: export > normal var > onready --------------------------------------

var room := {}
var segment: RbStageSegment
var state := State.WAITING
## Where the player triggers the room, relative to the room's left edge.
var trigger_x := 0.0
## Set by the stage: returns the walkable floor (top, bottom) at a global x, so enemies entering
## from a neighbouring segment start on its floor rather than inside its walls.
var floor_at := Callable()

#--- private variables - order: export > normal var > onready -------------------------------------

var _characters_parent: Node2D
var _waves: Array = []
var _wave_index := 0
var _alive := 0
var _seated_boss: QuiverEnemyCharacter = null
## Read from the segment in setup(), before the stage moves its markers into the level.
var _boss_seat = null
var _spawn_points: Array[Vector2] = []
var _has_engaged_boss := false
var _spawn_side := 0

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _ready() -> void:
	var trigger := Area2D.new()
	trigger.name = "Trigger"
	trigger.collision_layer = 0
	trigger.collision_mask = 1
	trigger.monitorable = false
	var shape := CollisionShape2D.new()
	var line := SegmentShape2D.new()
	line.a = Vector2(trigger_x, segment.camera_top)
	line.b = Vector2(trigger_x, segment.camera_bottom)
	shape.shape = line
	trigger.add_child(shape)
	add_child(trigger)
	trigger.body_entered.connect(_on_trigger_body_entered)

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

## Call before the stage spreads the segment's children over the level.
func setup(p_room: Dictionary, p_segment: RbStageSegment, characters_parent: Node2D) -> void:
	room = p_room
	segment = p_segment
	_characters_parent = characters_parent
	name = "Room%s_%s" % [room.index + 1, room.role]
	trigger_x = clampf(segment.get_walkable_end() * 0.3, 250.0, 700.0)
	_boss_seat = segment.get_boss_seat()
	_spawn_points = segment.get_spawn_points()


## Seats the boss on its throne before the player arrives, when both support it.
func prepare_seated_boss() -> void:
	var seat = _boss_seat
	if seat == null:
		return
	for spawn in room.spawns:
		if spawn.kind != "boss":
			continue
		var enemy := _instantiate(spawn)
		if enemy == null or not "should_start_seated" in enemy or not enemy.has_signal("tax_man_engaged"):
			if enemy != null:
				enemy.free()
			return
		enemy.should_start_seated = true
		enemy.position = position + seat
		_characters_parent.add_child(enemy, true)
		_seated_boss = enemy
		_track(enemy)
		return


func start() -> void:
	if state != State.WAITING:
		return
	state = State.ACTIVE
	started.emit()
	_announce()

	if room.event == "shop":
		_run_shop()

	_waves = _build_waves()
	if _waves.is_empty() and _seated_boss == null:
		_finish()
		return

	_lock_camera()
	if _seated_boss != null:
		_seated_boss.tax_man_revealed.emit()
		if _waves.is_empty():
			get_tree().create_timer(SEATED_ENGAGE_DELAY).timeout.connect(_engage_seated_boss)
	_spawn_next_wave()


## Global x of the room's left and right edges.
func get_span() -> Vector2:
	return Vector2(position.x, position.x + segment.width)

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _on_trigger_body_entered(body: Node2D) -> void:
	if body.is_in_group("players"):
		start.call_deferred()


func _announce() -> void:
	var registry: RbContentRegistry = Ragebound.registry
	for spawn in room.spawns:
		if spawn.kind == "boss":
			var boss := registry.get_entry("boss", spawn.id)
			Ragebound.post_message("BOSS: %s - \"%s\"" % [boss.name, boss.get("intro_text", "...")],
					Ragebound.COLOR_DANGER)
		elif spawn.kind == "miniboss":
			Ragebound.post_message("MINIBOSS: %s" % registry.get_entry("boss", spawn.id).name,
					Ragebound.COLOR_DANGER)
	match room.role:
		"ambush":
			Ragebound.post_message("AMBUSH!", Ragebound.COLOR_DANGER)
		"elite":
			if not room.spawns.any(func(spawn): return spawn.kind == "miniboss"):
				Ragebound.post_message("An elite pack blocks the way.", Ragebound.COLOR_DANGER)
	if room.event in EVENT_REWARDS:
		Ragebound.post_message(registry.get_entry("encounter", room.encounter).name,
				Ragebound.COLOR_GOLD)


func _run_shop() -> void:
	var cost: int = SHOP_COST_PER_LEVEL * Ragebound.plan.get("monster_level", 1)
	if Ragebound.spend_gold(cost):
		Ragebound.heal_player(1.0)
		Ragebound.post_message("Street doc patches you up for %s gold." % cost, Ragebound.COLOR_GOLD)
	else:
		Ragebound.heal_player(0.3)
		Ragebound.post_message("Street doc: \"Pay me next time.\" (needs %s gold)" % cost,
				Ragebound.COLOR_GOLD)


## The seated boss starts its own fight, so it isn't part of the waves.
func _build_waves() -> Array:
	var spawns: Array = room.spawns.filter(
			func(spawn): return _seated_boss == null or spawn.kind != "boss"
	)
	# Leaders arrive first, with the first few of their pack.
	spawns.sort_custom(func(a, b): return a.kind != "enemy" and b.kind == "enemy")
	var waves := []
	for index in spawns.size():
		if index % MAX_WAVE_SIZE == 0:
			waves.append([])
		waves.back().append(spawns[index])
	return waves


func _spawn_next_wave() -> void:
	if _wave_index >= _waves.size():
		return
	var points := _spawn_points
	var wave: Array = _waves[_wave_index]
	_wave_index += 1
	for index in wave.size():
		var enemy := _instantiate(wave[index])
		if enemy == null:
			continue
		var target: Vector2 = position + points[(index + _wave_index) % points.size()]
		enemy.position = _get_entrance(target.y)
		if floor_at.is_valid():
			var band: Vector2 = floor_at.call(enemy.position.x)
			enemy.position.y = clampf(enemy.position.y, band.x + 30.0, band.y - 30.0)
		_characters_parent.add_child(enemy, true)
		_track(enemy)
		enemy.spawn_ground_to_position(target)


func _instantiate(spawn: Dictionary) -> QuiverEnemyCharacter:
	var content_type := "enemy" if spawn.kind == "enemy" else "boss"
	var entry: Dictionary = Ragebound.registry.get_entry(content_type, spawn.id)
	if entry.is_empty() or not ResourceLoader.exists(entry.get("scene", "")):
		push_error("Room %s: can't spawn %s" % [name, spawn.id])
		return null
	var enemy := (load(entry.scene) as PackedScene).instantiate() as QuiverEnemyCharacter
	if enemy == null:
		push_error("Room %s: %s is not a QuiverEnemyCharacter scene" % [name, entry.scene])
		return null
	enemy.set_meta(Ragebound.META_SPAWN, {"spawn": spawn, "entry": entry})
	return enemy


## Enemies walk in from just outside the camera, alternating sides. Walled arenas only open on
## the left.
func _get_entrance(y: float) -> Vector2:
	var view_width := get_viewport_rect().size.x
	var span := _get_camera_span()
	var can_use_right := segment.get_walkable_end() >= segment.width
	_spawn_side += 1
	var x := span.x - ENTRANCE_MARGIN
	if can_use_right and _spawn_side % 2 == 0:
		x = span.y + ENTRANCE_MARGIN
	if view_width <= 0:
		x = position.x
	return Vector2(x, y)


func _track(enemy: QuiverEnemyCharacter) -> void:
	_alive += 1
	enemy.tree_exited.connect(_on_enemy_exited, CONNECT_ONE_SHOT)


## Waves advance when their adds are gone; a seated boss joins once the last wave is down.
func _on_enemy_exited() -> void:
	_alive -= 1
	if not is_inside_tree() or state != State.ACTIVE:
		return
	var is_boss_alive := is_instance_valid(_seated_boss) and _seated_boss.is_inside_tree()
	var adds_alive := _alive - (1 if is_boss_alive else 0)
	if adds_alive > 0:
		return
	if _wave_index < _waves.size():
		_spawn_next_wave()
	elif is_boss_alive:
		_engage_seated_boss()
	else:
		_finish()


func _engage_seated_boss() -> void:
	if _has_engaged_boss:
		return
	_has_engaged_boss = true
	while _is_boss_still_seated():
		_seated_boss.tax_man_engaged.emit()
		await get_tree().create_timer(ENGAGE_RETRY_SECONDS, false).timeout


func _is_boss_still_seated() -> bool:
	if not is_inside_tree() or not is_instance_valid(_seated_boss) or not _seated_boss.is_inside_tree():
		return false
	var state_machine := _seated_boss.get_node_or_null("StateMachine") as QuiverStateMachine
	return state_machine != null and state_machine.state != null \
			and state_machine.state.name == "Seated"


func _finish() -> void:
	if state == State.CLEARED:
		return
	state = State.CLEARED
	var reward: Dictionary = EVENT_REWARDS.get(room.event, {})
	if not reward.is_empty():
		Ragebound.award_loot(reward.table, reward.text)
	cleared.emit()


## Camera limits that keep the whole room on screen, widened when the room is narrower than the
## view.
func _get_camera_span() -> Vector2:
	var span := get_span()
	var view_width := get_viewport_rect().size.x
	if span.y - span.x < view_width:
		var center := (span.x + span.y) / 2.0
		span = Vector2(center - view_width / 2.0, center + view_width / 2.0)
	return span


func _lock_camera() -> void:
	var camera := get_viewport().get_camera_2d() as QuiverLevelCamera
	if camera == null:
		return
	var span := _get_camera_span()
	camera.delimitate_room(
			roundi(span.x), segment.camera_top, roundi(span.y), segment.camera_bottom,
			1.0, CAMERA_TRANSITION
	)

### -----------------------------------------------------------------------------------------------
