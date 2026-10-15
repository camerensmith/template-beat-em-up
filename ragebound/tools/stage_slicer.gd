extends Node

## Cuts a hand-made stage into [RbStageSegment] scenes the rift assembler can chain.
##
## Run the scene [code]res://ragebound/tools/stage_slicer.tscn[/code] (F6 in the editor, or
## [code]godot --headless res://ragebound/tools/stage_slicer.tscn[/code]). For each slice it:
## [br]- copies every Background/Foreground node that overlaps the slice, moved so the slice
## starts at x = 0 (the assembler clips the overhang),
## [br]- moves props from Level/Objects whose center is inside the slice,
## [br]- cuts the stage's ceiling and floor collision polygons to the slice,
## [br]- adds boss markers (AI positions and a [code]rb_boss_seat[/code] for seated intros), and
## saves [code]res://stages/segments/<id>.tscn[/code].
## [br]It also saves the stage's sky and day cycle as [code]<sky_scene>[/code].
## [br][br]
## Re-running overwrites the generated scenes, so make hand edits after slicing (or in the source
## stage, then slice again).

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const SOURCE_STAGE = "res://stages/stage_01/stage_01.tscn"
const OUTPUT_DIR = "res://stages/segments"
const SKY_SCENE = "res://stages/segments/street_sky.tscn"

const STREET_FLOOR_TOP = 653.0
const STREET_FLOOR_BOTTOM = 1107.0

## x ranges are in the source stage's coordinates. Cuts sit on building edges where possible.
const SLICES = [
	{"id": "storefront_corner", "x0": 0, "x1": 2045},
	{"id": "chicken_king", "x0": 2045, "x1": 4060},
	{"id": "fence_skyline", "x0": 4060, "x1": 6300, "camera_top": -320},
	{"id": "foster_mart", "x0": 6300, "x1": 8180, "camera_top": -320},
	{"id": "java_tiger_strip", "x0": 8180, "x1": 9900, "camera_top": -320},
	{"id": "torii_gate", "x0": 9900, "x1": 12300, "camera_top": -320},
	{
		"id": "tax_man_penthouse", "x0": 12300, "x1": 16070, "camera_top": -320,
		"floor_top": 480.0, "walkable_end": 15285.0,
		"marker_sources": "FightRooms/FightRoom5",
		"boss_seat": "Level/Characters/TaxMan",
	},
]

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _ready() -> void:
	var stage: Node = load(SOURCE_STAGE).instantiate()
	add_child(stage)
	await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	var failures := 0
	for slice in SLICES:
		var segment := _build_segment(stage, slice)
		failures += _save(segment, OUTPUT_DIR.path_join("%s.tscn" % slice.id))
		segment.free()

	var sky := _build_sky(stage)
	failures += _save(sky, SKY_SCENE)
	sky.free()

	print("Sliced %s segments from %s, %s failure(s)" % [SLICES.size(), SOURCE_STAGE, failures])
	# Quitting with the stage loaded can hang on its background loader, so free it first.
	stage.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if failures > 0 else 0)

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _build_segment(stage: Node, slice: Dictionary) -> RbStageSegment:
	var x0 := float(slice.x0)
	var x1 := float(slice.x1)
	var segment := RbStageSegment.new()
	segment.name = (slice.id as String).to_pascal_case()
	segment.width = roundi(x1 - x0)
	segment.floor_top = slice.get("floor_top", STREET_FLOOR_TOP)
	segment.floor_bottom = slice.get("floor_bottom", STREET_FLOOR_BOTTOM)
	segment.camera_top = slice.get("camera_top", -280)
	if slice.has("walkable_end"):
		segment.walkable_end = slice.walkable_end - x0

	var offset := Vector2(-x0, 0)
	for layer in ["Background", "Foreground"]:
		var target := _add_child_node(segment, Node2D.new(), layer)
		for child in stage.get_node(layer).get_children():
			if child is CanvasLayer:
				continue
			var bounds := _get_bounds(child)
			if bounds.end.x > x0 and bounds.position.x < x1:
				_copy_into(child, target, segment, offset, stage)

	var objects := _add_child_node(segment, Node2D.new(), "Objects")
	for child in stage.get_node("Level/Objects").get_children():
		var center := _get_bounds(child).get_center().x
		if center >= x0 and center < x1:
			_copy_into(child, objects, segment, offset, stage)

	var collisions := _add_child_node(segment, Node2D.new(), "Collisions")
	var clip := PackedVector2Array([
		Vector2(x0, -5000), Vector2(x1, -5000), Vector2(x1, 5000), Vector2(x0, 5000),
	])
	for body_path in ["Level/Collisions/CeilingLimits", "Level/Collisions/BottomLimit"]:
		_cut_body(stage.get_node(body_path), collisions, segment, clip, offset)
	for child in stage.get_node("Level/Collisions").get_children():
		if child is Area2D and child.global_position.x >= x0 and child.global_position.x < x1:
			_copy_into(child, collisions, segment, offset, stage)

	var markers := _add_child_node(segment, Node2D.new(), "Markers")
	if slice.has("marker_sources"):
		for source in stage.get_node(slice.marker_sources).get_children():
			if source is Marker2D:
				var marker := Marker2D.new()
				marker.name = source.name
				marker.position = source.global_position + offset
				for group in source.get_groups():
					marker.add_to_group(group, true)
				markers.add_child(marker)
				marker.owner = segment
	if slice.has("boss_seat"):
		var seat := Marker2D.new()
		seat.name = "BossSeat"
		seat.position = stage.get_node(slice.boss_seat).global_position + offset
		seat.add_to_group(RbStageSegment.BOSS_SEAT_GROUP, true)
		markers.add_child(seat)
		seat.owner = segment
	return segment


func _build_sky(stage: Node) -> Node2D:
	var sky := Node2D.new()
	sky.name = "StreetSky"
	_copy_into(stage.get_node("DayCycleModulate"), sky, sky, Vector2.ZERO, stage)
	var layer: ParallaxBackground = _copy_into(
			stage.get_node("Background/SkyboxLayer"), sky, sky, Vector2.ZERO, stage
	)
	# The skyline is one sprite; mirroring repeats it so any segment order still shows a city.
	for parallax in layer.get_children():
		for sprite in parallax.get_children():
			if sprite is Sprite2D and sprite.texture != null and parallax.motion_scale.x > 0:
				parallax.motion_mirroring.x = sprite.texture.get_width() * absf(sprite.scale.x)
	return sky


## Duplicates [param source] under [param parent], keeping instanced sub-scenes as instances and
## giving every node that the source stage owned to [param new_owner].
func _copy_into(source: Node, parent: Node, new_owner: Node, offset: Vector2, stage: Node) -> Node:
	var copy := source.duplicate()
	parent.add_child(copy)
	if copy is Node2D:
		copy.position = (source as Node2D).global_position + offset
	elif copy is Control:
		copy.position = (source as Control).global_position + offset
	_assign_owners(source, copy, new_owner, stage)
	return copy


func _assign_owners(source: Node, copy: Node, new_owner: Node, stage: Node) -> void:
	if source.owner == stage or source == stage:
		copy.owner = new_owner
	if source.scene_file_path.is_empty() or source.owner == stage:
		var source_children := source.get_children()
		var copy_children := copy.get_children()
		for index in mini(source_children.size(), copy_children.size()):
			_assign_owners(source_children[index], copy_children[index], new_owner, stage)


func _cut_body(
		body: CollisionObject2D, collisions: Node2D, segment: Node, clip: PackedVector2Array,
		offset: Vector2
) -> void:
	var copy := StaticBody2D.new()
	copy.name = body.name
	copy.collision_layer = body.collision_layer
	copy.collision_mask = body.collision_mask
	for shape_node in body.get_children():
		for polygon in _get_world_polygons(shape_node):
			for piece in Geometry2D.intersect_polygons(polygon, clip):
				var collision := CollisionPolygon2D.new()
				var local := PackedVector2Array()
				for point in piece:
					local.append(point + offset)
				collision.polygon = local
				copy.add_child(collision)
	if copy.get_child_count() == 0:
		copy.free()
		return
	collisions.add_child(copy)
	copy.owner = segment
	for collision in copy.get_children():
		collision.name = "Shape%s" % collision.get_index()
		collision.owner = segment


func _get_world_polygons(shape_node: Node) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	if shape_node is CollisionPolygon2D:
		polygons.append(shape_node.global_transform * (shape_node as CollisionPolygon2D).polygon)
	elif shape_node is CollisionShape2D and shape_node.shape is RectangleShape2D:
		var half: Vector2 = shape_node.shape.size / 2.0
		polygons.append(shape_node.global_transform * PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		]))
	return polygons


## Global bounds of everything [param node] draws, or its position when it draws nothing.
func _get_bounds(node: Node) -> Rect2:
	var bounds := Rect2()
	var has_bounds := false
	for item in [node] + _get_descendants(node):
		var rect := Rect2()
		if item is Sprite2D and item.texture != null:
			rect = item.get_global_transform() * item.get_rect()
		elif item is QuiverSpriteRepeater:
			rect = item.get_global_rect()
		elif item is Control:
			rect = item.get_global_rect()
		else:
			continue
		bounds = rect if not has_bounds else bounds.merge(rect)
		has_bounds = true
	if not has_bounds and node is Node2D:
		bounds = Rect2(node.global_position, Vector2.ZERO)
	return bounds


## find_children() skips nodes inside instanced sub-scenes in Godot 4.0, so walk the tree.
func _get_descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_get_descendants(child))
	return found


func _add_child_node(parent: Node, child: Node, child_name: String) -> Node:
	child.name = child_name
	parent.add_child(child)
	child.owner = parent if parent.owner == null else parent.owner
	return child


func _save(root: Node, path: String) -> int:
	var packed := PackedScene.new()
	var error := packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, path)
	if error != OK:
		push_error("Failed to save %s: %s" % [path, error_string(error)])
		return 1
	print("saved %s" % path)
	return 0

### -----------------------------------------------------------------------------------------------
