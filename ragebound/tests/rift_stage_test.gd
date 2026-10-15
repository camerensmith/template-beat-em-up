extends Node

## Plays assembled rifts end to end, headless.
##
## [codeblock]
## godot --headless --fixed-fps 60 res://ragebound/tests/rift_stage_test.tscn
## [/codeblock]
## For each case it builds [code]rift_stage.tscn[/code] from a seeded plan, walks the player
## through every room's trigger, defeats what spawns, and checks that rooms clear, the camera
## unlocks, the boss fight ends the rift and the victory screen opens. Exits with code 1 on any
## failure.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const STAGE = "res://ragebound/stages/rift_stage.tscn"
const CASES = [
	{"seed": 4, "rift": "short_rift", "level": 1, "expect_boss": "base_game:tax_man", "expect_seated": true},
	# More guards than one wave holds, so the seated boss must wait for two waves.
	{"seed": 4, "rift": "short_rift", "level": 1, "extra_boss_adds": 6},
	{"seed": 1, "rift": "short_rift", "level": 1},
	{"seed": 7, "rift": "industrial_rift", "level": 4},
	{"seed": 7, "rift": "downtown_rift", "level": 2},
]
const ROOM_TIMEOUT_FRAMES = 60 * 90

#--- private variables - order: export > normal var > onready -------------------------------------

var _failures := PackedStringArray()
var _case_label := ""

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _ready() -> void:
	_case_label = "segments"
	_check_segment_scenes()
	for test_case in CASES:
		_case_label = "%s seed %s%s" % [test_case.rift, test_case.seed,
				" +%s adds" % test_case.extra_boss_adds if test_case.has("extra_boss_adds") else ""]
		await _play_case(test_case)

	print("\nrift stage test: %s case(s), %s failure(s)" % [CASES.size(), _failures.size()])
	for failure in _failures:
		print("  - " + failure)
	get_tree().quit(1 if not _failures.is_empty() else 0)

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _play_case(test_case: Dictionary) -> void:
	# The previous case's victory screen pauses the game, like the real end screen does.
	get_tree().paused = false
	Ragebound.end_run(false)
	var plan: Dictionary = Ragebound.start_run({
		"seed": test_case.seed, "rift": test_case.rift, "level": test_case.level,
	})
	_check(plan.errors.is_empty(), "plan errors %s" % [plan.errors])
	if test_case.has("expect_boss"):
		_check(plan.boss == test_case.expect_boss, "expected boss %s, got %s" % [
				test_case.expect_boss, plan.boss
		])

	for _index in test_case.get("extra_boss_adds", 0):
		plan.rooms.back().spawns.append({"id": "base_game:street_thug", "kind": "enemy", "elite": []})
	
	var stage: RbRiftStage = load(STAGE).instantiate()
	# The pause menu starts a threaded load that never finishes headless and blocks quitting.
	stage.get_node("HudLayer/PauseMenu").free()
	add_child(stage)
	await _frames(3)

	_check_layout(stage, plan)
	if test_case.get("expect_seated", false):
		var seated := stage.get_node("Level/Characters").get_children().filter(
				func(node): return "should_start_seated" in node and node.should_start_seated
		)
		_check(seated.size() == 1, "the boss should wait seated on the throne")
	var player := stage.get_node("Level/Characters/Chad") as QuiverCharacter
	player.attributes.is_invulnerable = true
	await _check_walkable(stage, player)

	for room in stage.rooms:
		await _play_room(stage, player, room)
		if room.state != RbRiftRoom.State.CLEARED:
			break

	var end_screen := stage.get_node("HudLayer/EndScreen") as CanvasItem
	await _frames(30)
	_check(end_screen.visible, "victory screen didn't open")
	_check(not Ragebound.is_run_active, "run still active after the boss died")
	print("%s: %s rooms, level width %s" % [_case_label, stage.rooms.size(), stage.level_width])

	stage.queue_free()
	await _frames(3)


## Every segment either has a scene with an RbStageSegment root matching its content, or can be
## blocked out.
func _check_segment_scenes() -> void:
	for entry in Ragebound.registry.get_all("stage_segment"):
		var segment: RbStageSegment = null
		if entry.has("scene"):
			var node: Node = load(entry.scene).instantiate()
			segment = node as RbStageSegment
			_check(segment != null, "%s scene root is not an RbStageSegment" % entry.id)
			if segment == null:
				node.free()
				continue
			_check(segment.has_node("Background"), "%s has no Background" % entry.id)
		else:
			segment = RbGreyboxSegment.build(entry)
		_check(segment.width == int(entry.width), "%s width %s differs from content %s" % [
				entry.id, segment.width, entry.width
		])
		var depth := segment.floor_bottom - segment.floor_top
		_check(is_equal_approx(depth, float(entry.depth)), "%s depth %s differs from content %s" % [
				entry.id, depth, entry.depth
		])
		segment.free()


func _check_layout(stage: RbRiftStage, plan: Dictionary) -> void:
	_check(stage.rooms.size() == plan.rooms.size(), "room count differs from the plan")
	var x := 0.0
	for index in stage.segments.size():
		var segment := stage.segments[index]
		var entry: Dictionary = Ragebound.registry.get_entry("stage_segment", plan.rooms[index].segment)
		_check(is_equal_approx(segment.position.x, x), "%s isn't placed after the previous segment" % segment.name)
		_check(segment.width == int(entry.width), "%s width %s differs from content %s" % [
				segment.name, segment.width, entry.width
		])
		x += segment.width
	_check(is_equal_approx(stage.level_width, x), "level width")
	if plan.boss != "":
		_check(not get_tree().get_nodes_in_group("tax_man_dash_positions").is_empty(),
				"boss room has no AI markers")


## Searches a grid over the floor with the player's own collision shape to prove they can walk
## from the start to the boss across every seam, without teleporting.
func _check_walkable(stage: RbRiftStage, player: CharacterBody2D) -> void:
	var screen_limits := player.get_node("LevelCamera/ScreenLimits") as StaticBody2D
	var saved_layer := screen_limits.collision_layer
	screen_limits.collision_layer = 0
	# Gates open when the player walks up to them (stage_01's brick gate), so search with them open.
	var gates := _find_named(stage.get_node("Level/Objects"), "CollisionEntrance")
	for gate in gates:
		gate.disabled = true
	await _frames(2)
	
	var top := INF
	var bottom := -INF
	for segment in stage.segments:
		top = minf(top, segment.floor_top)
		bottom = maxf(bottom, segment.floor_bottom)
	var last := stage.segments.back() as RbStageSegment
	var goal_x := last.position.x + last.get_walkable_end() * 0.5
	var start := player.global_position
	var step := Vector2(60, 30)
	var rows_up := ceili((start.y - top + 40) / step.y)
	var rows_down := ceili((bottom + 40 - start.y) / step.y)
	
	var visited := {Vector2i(0, 0): true}
	var queue: Array[Vector2i] = [Vector2i(0, 0)]
	var furthest := start.x
	var reached := false
	while not queue.is_empty() and not reached:
		var cell: Vector2i = queue.pop_front()
		var from := start + Vector2(cell) * step
		for direction in [Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT]:
			var next: Vector2i = cell + direction
			if visited.has(next) or next.y < -rows_up or next.y > rows_down or next.x < -5:
				continue
			if player.test_move(Transform2D(0, from), Vector2(direction) * step):
				continue
			visited[next] = true
			queue.append(next)
			var x := start.x + next.x * step.x
			furthest = maxf(furthest, x)
			if x >= goal_x:
				reached = true
	
	screen_limits.collision_layer = saved_layer
	for gate in gates:
		gate.disabled = false
	var blocked_at := stage.get_room_at(furthest)
	_check(reached, "the player can't walk to the boss; stuck at x %s (%s)" % [
			roundi(furthest), blocked_at.segment.name if blocked_at != null else "?"
	])


func _play_room(stage: RbRiftStage, player: QuiverCharacter, room: RbRiftRoom) -> void:
	var label := "%s room %s (%s)" % [_case_label, room.room.index + 1, room.room.role]
	player.global_position = Vector2(
			room.position.x + room.trigger_x + 60, room.segment.get_floor_middle()
	)
	await _frames(10)
	_check(room.state != RbRiftRoom.State.WAITING, "%s never started" % label)

	var killer := QuiverAttackData.new()
	killer.attack_damage = 999999
	var frames := 0
	while room.state == RbRiftRoom.State.ACTIVE and frames < ROOM_TIMEOUT_FRAMES:
		for node in stage.get_node("Level/Characters").get_children():
			var enemy := node as QuiverEnemyCharacter
			if enemy == null or not enemy.is_inside_tree() or not enemy.attributes.is_alive():
				continue
			if enemy.attributes.is_invulnerable:
				continue
			# A real hit: damage, then the knockback that sends a defeated body into its death.
			CombatSystem.apply_damage(killer, enemy.attributes, player.attributes)
			CombatSystem.apply_knockback(QuiverKnockbackData.new(
					CombatSystem.KnockbackStrength.STRONG, CombatSystem.HurtTypes.HIGH, Vector2.RIGHT
			), enemy.attributes, player.attributes)
		await _frames(10)
		frames += 10
	if room.state != RbRiftRoom.State.CLEARED:
		for node in stage.get_node("Level/Characters").get_children():
			if node is QuiverEnemyCharacter:
				print("  left alive: %s hp %s/%s invulnerable %s pos %s" % [
						node.name, node.attributes.health_current, node.attributes.health_max,
						node.attributes.is_invulnerable, node.global_position,
				])
		print("  room alive count %s, wave %s/%s" % [room._alive, room._wave_index, room._waves.size()])
	_check(room.state == RbRiftRoom.State.CLEARED, "%s didn't clear in time" % label)

	if room.room.role != "boss" and room != stage.rooms.back():
		await _frames(60)
		var camera := get_viewport().get_camera_2d() as QuiverLevelCamera
		_check(camera.limit_right == roundi(stage.level_width), "%s didn't unlock the camera" % label)


## find_children() skips nodes inside instanced sub-scenes in Godot 4.0, so search manually.
func _find_named(root: Node, node_name: String) -> Array[Node]:
	var found: Array[Node] = []
	for child in root.get_children():
		if child.name == node_name:
			found.append(child)
		found.append_array(_find_named(child, node_name))
	return found


func _frames(amount: int) -> void:
	for _index in amount:
		await get_tree().physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append("%s: %s" % [_case_label, message])
		push_error(message)

### -----------------------------------------------------------------------------------------------
