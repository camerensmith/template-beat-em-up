class_name RbRiftStage
extends BaseStage

## Builds a playable level from the current rift plan.
##
## Each room's stage segment is instanced (or blocked out with [RbGreyboxSegment] when it has no
## scene yet) and placed left to right. Segment art is clipped to its own width, props join the
## level's y-sorted layer, and every room gets an [RbRiftRoom] that locks the camera and runs
## its planned spawns. Clearing a room opens the way forward; beating the boss wins the rift.
## [br][br]
## Reloading the scene after a rift ends (victory or defeat) starts a new rift.

### Member Variables and Dependencies -------------------------------------------------------------
#--- signals --------------------------------------------------------------------------------------

signal level_built(rooms: Array)

#--- constants ------------------------------------------------------------------------------------

const SKY_SCENE = "res://stages/segments/street_sky.tscn"
const PLAYER_START_X = 300.0
const CLIP_MARGIN = 4000.0
const COLLISION_THICKNESS = 300.0
const CEILING_LAYER = 4
const CEILING_MASK = 17
const FLOOR_LAYER = 4
## Boss AI (the Tax Man body) dashes between and engages from markers in these groups.
const BOSS_DASH_GROUP = &"tax_man_dash_positions"
const BOSS_ENGAGE_GROUP = &"tax_man_engage_position"

#--- public variables - order: export > normal var > onready --------------------------------------

var plan := {}
var rooms: Array[RbRiftRoom] = []
var segments: Array[RbStageSegment] = []
var level_width := 0.0

#--- private variables - order: export > normal var > onready -------------------------------------

@onready var _background := $Background as Node2D
@onready var _foreground := $Foreground as Node2D
@onready var _characters := $Level/Characters as Node2D
@onready var _objects := $Level/Objects as Node2D
@onready var _collisions := $Level/Collisions as Node2D
@onready var _fight_rooms := $FightRooms as Node2D

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _enter_tree() -> void:
	# Before the player's ready, so their stats come from this run.
	if not Ragebound.is_run_active:
		Ragebound.start_run()
	plan = Ragebound.plan


func _ready() -> void:
	_build_level()
	super()
	_place_player()

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

## Walkable floor (top, bottom) at a global x; outside the level, the nearest segment's.
func get_floor_at(global_x: float) -> Vector2:
	if segments.is_empty():
		return Vector2(0, 0)
	var segment := segments[0]
	for candidate in segments:
		if global_x >= candidate.position.x:
			segment = candidate
	return Vector2(segment.floor_top, segment.floor_bottom)


func get_room_at(global_x: float) -> RbRiftRoom:
	for room in rooms:
		var span := room.get_span()
		if global_x >= span.x and global_x < span.y:
			return room
	return null

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _build_level() -> void:
	if ResourceLoader.exists(SKY_SCENE):
		add_child((load(SKY_SCENE) as PackedScene).instantiate())

	var registry: RbContentRegistry = Ragebound.registry
	var x := 0.0
	for room_data in plan.get("rooms", []):
		var entry := registry.get_entry("stage_segment", room_data.segment)
		var segment := _instance_segment(entry)
		segment.name = "Segment%s_%s" % [room_data.index + 1, segment.name]
		segment.position.x = x
		if room_data.role == "boss":
			_ensure_boss_markers(segment)

		var room := RbRiftRoom.new()
		room.setup(room_data, segment, _characters)
		room.floor_at = get_floor_at
		_attach_segment(segment)
		room.position = Vector2(x, 0)
		_fight_rooms.add_child(room)
		room.cleared.connect(_on_room_cleared.bind(room))
		room.prepare_seated_boss()
		rooms.append(room)
		segments.append(segment)
		x += segment.width
	level_width = x
	level_built.emit(rooms)


func _instance_segment(entry: Dictionary) -> RbStageSegment:
	var scene_path: String = entry.get("scene", "")
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var segment := (load(scene_path) as PackedScene).instantiate() as RbStageSegment
		if segment != null:
			if segment.width != int(entry.width):
				push_warning("%s: scene width %s differs from content width %s" % [
						entry.id, segment.width, entry.width
				])
			return segment
		push_error("%s does not have an RbStageSegment root, using a greybox" % scene_path)
	return RbGreyboxSegment.build(entry)


## Spreads a segment's layers over the stage's layers so z-order and y-sorting work across
## segments. The segment node itself stays under the stage as a record of the room's data.
func _attach_segment(segment: RbStageSegment) -> void:
	var offset := segment.position
	add_child(segment)

	for layer_name in ["Background", "Foreground"]:
		var layer := segment.get_node_or_null(layer_name) as Node2D
		if layer == null:
			continue
		var clip := _make_clip(segment, layer_name)
		(_background if layer_name == "Background" else _foreground).add_child(clip)
		_move(layer, clip, Vector2.ZERO)
		_flatten_z_index(clip)

	var objects := segment.get_node_or_null("Objects")
	if objects != null:
		for prop in objects.get_children():
			_move(prop, _objects, offset)

	if segment.has_custom_collisions():
		_move(segment.get_node("Collisions"), _collisions, offset)
	else:
		_add_band_collisions(segment)

	var markers := segment.get_node_or_null("Markers")
	if markers != null:
		_move(markers, _fight_rooms, offset)


## A Polygon2D covering the segment that only lets its children draw inside it.
func _make_clip(segment: RbStageSegment, layer_name: String) -> Polygon2D:
	var clip := Polygon2D.new()
	clip.name = "%s_%s" % [segment.name, layer_name]
	clip.position = segment.position
	clip.polygon = PackedVector2Array([
		Vector2(0, -CLIP_MARGIN), Vector2(segment.width, -CLIP_MARGIN),
		Vector2(segment.width, CLIP_MARGIN), Vector2(0, CLIP_MARGIN),
	])
	clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	return clip


## Segments without art have no boss AI markers, so place them across the arena.
func _ensure_boss_markers(segment: RbStageSegment) -> void:
	var markers := segment.get_node_or_null("Markers")
	if markers == null:
		markers = Node2D.new()
		markers.name = "Markers"
		segment.add_child(markers)
	var has_dash := markers.get_children().any(func(marker): return marker.is_in_group(BOSS_DASH_GROUP))
	if has_dash:
		return
	var walk_end := segment.get_walkable_end()
	var y := segment.get_floor_middle()
	for spot in [[0.15, BOSS_DASH_GROUP], [0.85, BOSS_DASH_GROUP], [0.75, BOSS_ENGAGE_GROUP]]:
		var marker := Marker2D.new()
		marker.position = Vector2(walk_end * spot[0], y)
		marker.add_to_group(spot[1])
		markers.add_child(marker)


## Nodes with their own z_index draw outside a clipping parent, so they're moved into ordered
## sub-layers at z 0 instead. Draw order stays the same: lower z first, then tree order.
func _flatten_z_index(clip: Node2D) -> void:
	var by_z := {}
	for node in clip.find_children("*", "Node2D", true, false):
		var item := node as Node2D
		if item.z_index == 0:
			continue
		var z := _get_z_relative_to(item, clip)
		if not by_z.has(z):
			by_z[z] = []
		by_z[z].append(item)
	
	var levels := by_z.keys()
	levels.sort()
	for z in levels:
		var group := Node2D.new()
		group.name = "Z%s" % z
		clip.add_child(group)
		if z < 0:
			clip.move_child(group, levels.find(z))
		for item in by_z[z]:
			var item_transform: Transform2D = item.global_transform
			item.get_parent().remove_child(item)
			group.add_child(item)
			item.z_index = 0
			item.global_transform = item_transform


func _get_z_relative_to(item: Node2D, ancestor: Node) -> int:
	var z := 0
	var node: Node = item
	while node != ancestor and node is Node2D:
		z += node.z_index
		if not node.z_as_relative:
			break
		node = node.get_parent()
	return z


func _add_band_collisions(segment: RbStageSegment) -> void:
	var width := float(segment.width)
	var ceiling := _make_body("Ceiling_%s" % segment.name, CEILING_LAYER, CEILING_MASK,
			Rect2(0, segment.floor_top - COLLISION_THICKNESS, width, COLLISION_THICKNESS))
	var ground := _make_body("Floor_%s" % segment.name, FLOOR_LAYER, 1,
			Rect2(0, segment.floor_bottom, width, COLLISION_THICKNESS))
	if segment.get_walkable_end() < width:
		var wall := Rect2(segment.get_walkable_end(), segment.camera_top,
				width - segment.get_walkable_end(), segment.camera_bottom - segment.camera_top)
		_add_shape(ground, wall)
	for body in [ceiling, ground]:
		body.position = segment.position
		_collisions.add_child(body)


func _make_body(body_name: String, layer: int, mask: int, rect: Rect2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = mask
	_add_shape(body, rect)
	return body


func _add_shape(body: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	shape.position = rect.get_center()
	body.add_child(shape)


func _move(node: Node, new_parent: Node, offset: Vector2) -> void:
	node.get_parent().remove_child(node)
	new_parent.add_child(node)
	if node is Node2D:
		node.position += offset
	elif node is Control:
		node.position += offset


func _place_player() -> void:
	if segments.is_empty():
		return
	var first := segments[0]
	_main_player.global_position = Vector2(PLAYER_START_X, first.get_floor_middle())
	var camera := _main_player.get_node_or_null("LevelCamera") as Camera2D
	if camera != null:
		camera.limit_left = 0
		camera.limit_right = roundi(level_width)
		camera.limit_top = first.camera_top
		camera.limit_bottom = first.camera_bottom
		camera.reset_smoothing()


func _on_room_cleared(room: RbRiftRoom) -> void:
	if room.room.role == "boss":
		if not room.room.spawns.is_empty():
			_end_screen.open_end_screen(true)
		return

	var camera := get_viewport().get_camera_2d() as QuiverLevelCamera
	if camera != null:
		var span := room.get_span()
		camera.delimitate_room(roundi(span.x), room.segment.camera_top, roundi(level_width),
				room.segment.camera_bottom, 1.0, 0.8)
	if room != rooms.back():
		Ragebound.post_message("GO!  >>>", Ragebound.COLOR_GOLD)

### -----------------------------------------------------------------------------------------------
