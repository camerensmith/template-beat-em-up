@tool
class_name RbStageSegment
extends Node2D

## One reusable slice of a level that the rift assembler chains with others.
##
## A segment spans x = 0 to [member width]. Its children follow a convention the assembler reads:
## [br]- [code]Background[/code] and [code]Foreground[/code]: art, clipped to the segment's width,
## so pieces that overhang the edges never bleed into the neighbouring segment.
## [br]- [code]Objects[/code]: props that must y-sort with characters (gates, thrones). They move
## into the level's y-sorted layer when assembled.
## [br]- [code]Collisions[/code]: optional exact ceiling/floor bodies. Without it, the assembler
## builds a flat walkable band from [member floor_top] to [member floor_bottom].
## [br]- [code]Markers[/code]: optional [Marker2D]s. Markers in the group
## [code]rb_spawn_point[/code] are where enemies walk to; any other groups (for example
## [code]tax_man_dash_positions[/code]) are kept as they are for boss AI. A marker in
## [code]rb_boss_seat[/code] seats bosses that support it (the Tax Man) before the fight.
## [br][br]
## The segment's content entry ([code]stages/*.json[/code]) points at the scene with
## [code]scene[/code]. Its [code]width[/code] there must match [member width] here.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const SPAWN_POINT_GROUP = &"rb_spawn_point"
## A boss whose body supports a seated intro (like the Tax Man) waits here for the player.
const BOSS_SEAT_GROUP = &"rb_boss_seat"

#--- public variables - order: export > normal var > onready --------------------------------------

@export var width := 1920:
	set(value):
		width = value
		queue_redraw()

## Upper edge of the walkable floor (characters' feet can't go above it).
@export var floor_top := 653.0:
	set(value):
		floor_top = value
		queue_redraw()

## Lower edge of the walkable floor.
@export var floor_bottom := 1107.0:
	set(value):
		floor_bottom = value
		queue_redraw()

## Rightmost x characters can reach, when a wall stops them before [member width].
## Negative means the whole width is walkable.
@export var walkable_end := -1.0:
	set(value):
		walkable_end = value
		queue_redraw()

@export var camera_top := -280
@export var camera_bottom := 1195

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_rect(Rect2(0, camera_top, width, camera_bottom - camera_top), Color(0.3, 0.6, 1.0), false, 8)
	var walk_end := get_walkable_end()
	draw_rect(Rect2(0, floor_top, walk_end, floor_bottom - floor_top), Color(0.3, 1.0, 0.4, 0.15))

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

func get_walkable_end() -> float:
	return walkable_end if walkable_end > 0 else float(width)


func get_floor_middle() -> float:
	return (floor_top + floor_bottom) / 2.0


func has_custom_collisions() -> bool:
	var collisions := get_node_or_null("Collisions")
	return collisions != null and collisions.get_child_count() > 0


## Local positions enemies walk to. Falls back to an even spread over the floor.
func get_spawn_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	var markers := get_node_or_null("Markers")
	if markers != null:
		for marker in markers.get_children():
			if marker is Marker2D and marker.is_in_group(SPAWN_POINT_GROUP):
				points.append(marker.position)
	if points.is_empty():
		var walk_end := get_walkable_end()
		var depth := floor_bottom - floor_top
		for index in 6:
			var x := lerpf(walk_end * 0.3, walk_end * 0.85, index / 5.0)
			var y := floor_top + depth * (0.25 + 0.5 * float(index % 3) / 2.0)
			points.append(Vector2(x, y))
	return points


## Local position of the boss seat marker, or null when the segment has none.
func get_boss_seat():
	var markers := get_node_or_null("Markers")
	if markers == null:
		return null
	for marker in markers.get_children():
		if marker is Marker2D and marker.is_in_group(BOSS_SEAT_GROUP):
			return marker.position
	return null

### -----------------------------------------------------------------------------------------------
