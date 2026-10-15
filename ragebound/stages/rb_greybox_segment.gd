class_name RbGreyboxSegment
extends RefCounted

## Builds a blockout [RbStageSegment] for stage segments that don't have art yet.
##
## Every segment entry is playable from day one: the greybox uses the entry's width, depth and
## features, a palette per theme, and a sign with the segment's name. When the art exists, set
## the entry's [code]scene[/code] and the greybox is no longer used.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const FLOOR_BOTTOM = 1107.0
const CAMERA_TOP = -280
const CAMERA_BOTTOM = 1195
const PANEL_WIDTH = 320.0

const PALETTES = {
	"street": {"wall": "#4b5563", "wall_dark": "#374151", "floor": "#4a4a4f", "line": "#5c5c63", "accent": "#e5e7eb"},
	"alley": {"wall": "#5b3a32", "wall_dark": "#472c26", "floor": "#3b3735", "line": "#4a4542", "accent": "#d97757"},
	"club": {"wall": "#2e1a47", "wall_dark": "#221236", "floor": "#1c1626", "line": "#3a2a52", "accent": "#ff4fd8"},
	"factory": {"wall": "#4a4f55", "wall_dark": "#3a3e44", "floor": "#3d3a36", "line": "#57524b", "accent": "#f5b82e"},
}

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

static func build(entry: Dictionary) -> RbStageSegment:
	var segment := RbStageSegment.new()
	segment.name = "Greybox_%s" % (entry.id as String).get_slice(":", 1)
	segment.width = int(entry.width)
	segment.floor_bottom = FLOOR_BOTTOM
	segment.floor_top = FLOOR_BOTTOM - float(entry.depth)
	segment.camera_top = CAMERA_TOP
	segment.camera_bottom = CAMERA_BOTTOM

	var palette := get_palette(entry.theme)
	var features: Array = entry.get("features", [])
	var rng := RbRng.new(hash(entry.id))
	var background := Node2D.new()
	background.name = "Background"
	segment.add_child(background)
	var foreground := Node2D.new()
	foreground.name = "Foreground"
	segment.add_child(foreground)

	var width := float(segment.width)
	var wall_bottom := segment.floor_top
	_rect(background, Rect2(0, CAMERA_TOP, width, wall_bottom - CAMERA_TOP), palette.wall)
	for index in ceili(width / PANEL_WIDTH):
		if index % 2 == 1:
			var x := index * PANEL_WIDTH
			_rect(background, Rect2(x, CAMERA_TOP, minf(PANEL_WIDTH, width - x),
					wall_bottom - CAMERA_TOP), palette.wall_dark)
	_rect(background, Rect2(0, CAMERA_TOP, width, 60), palette.wall_dark.darkened(0.3))

	_add_theme_props(background, entry.theme, segment, palette, rng)

	_rect(background, Rect2(0, wall_bottom - 28, width, 28), palette.wall_dark.darkened(0.4))
	_rect(background, Rect2(0, wall_bottom, width, CAMERA_BOTTOM - wall_bottom), palette.floor)
	var depth := FLOOR_BOTTOM - wall_bottom
	for row in 5:
		var y := wall_bottom + depth * pow(float(row + 1) / 5.0, 1.4)
		_line(background, [Vector2(0, y), Vector2(width, y)], palette.line, 4)
	for index in ceili(width / 240.0) + 4:
		var x := index * 240.0
		_line(background, [Vector2(x, wall_bottom), Vector2(x - 180, CAMERA_BOTTOM)], palette.line, 3)

	if "hazards" in features:
		_hazard_stripes(background, Rect2(0, wall_bottom - 28, width, 28))
	if "walls" in features:
		for x in [0.0, width - 70.0]:
			_rect(foreground, Rect2(x, CAMERA_TOP, 70, CAMERA_BOTTOM - CAMERA_TOP),
					palette.wall_dark.darkened(0.5))
	if "hooks" in features:
		for index in int(width / 400.0):
			var x := 200.0 + index * 400.0 + rng.float_range(-60, 60)
			var length := rng.float_range(180, 360)
			_line(foreground, [Vector2(x, CAMERA_TOP), Vector2(x, CAMERA_TOP + length)],
					Color("#8a8f96"), 6)
			_line(foreground, [Vector2(x, CAMERA_TOP + length), Vector2(x + 24, CAMERA_TOP + length + 30),
					Vector2(x, CAMERA_TOP + length + 50)], Color("#b0b5bb"), 8)
	if "lights" in features:
		for index in int(width / 500.0) + 1:
			var light := Polygon2D.new()
			var x := 250.0 + index * 500.0
			light.polygon = PackedVector2Array([
				Vector2(x - 30, CAMERA_TOP + 60), Vector2(x + 30, CAMERA_TOP + 60),
				Vector2(x + 220, FLOOR_BOTTOM), Vector2(x - 220, FLOOR_BOTTOM),
			])
			light.color = Color(palette.accent, 0.12)
			foreground.add_child(light)

	var sign_label := Label.new()
	sign_label.text = entry.get("name", entry.id).to_upper()
	sign_label.position = Vector2(80, segment.floor_top - 420)
	sign_label.add_theme_font_size_override("font_size", 64)
	sign_label.add_theme_color_override("font_color", palette.accent)
	sign_label.add_theme_color_override("font_outline_color", Color.BLACK)
	sign_label.add_theme_constant_override("outline_size", 12)
	background.add_child(sign_label)
	return segment


static func get_palette(theme: String) -> Dictionary:
	var raw: Dictionary = PALETTES.get(theme, {})
	if raw.is_empty():
		var hue := float(hash(theme) % 360) / 360.0
		raw = {
			"wall": Color.from_hsv(hue, 0.35, 0.35).to_html(),
			"wall_dark": Color.from_hsv(hue, 0.35, 0.27).to_html(),
			"floor": Color.from_hsv(hue, 0.15, 0.25).to_html(),
			"line": Color.from_hsv(hue, 0.15, 0.32).to_html(),
			"accent": Color.from_hsv(hue, 0.6, 0.95).to_html(),
		}
	var palette := {}
	for key in raw:
		palette[key] = Color(raw[key])
	return palette

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

static func _add_theme_props(
		parent: Node2D, theme: String, segment: RbStageSegment, palette: Dictionary, rng: RbRng
) -> void:
	var width := float(segment.width)
	var base := segment.floor_top
	match theme:
		"alley":
			for index in int(width / 600.0):
				var x := 150.0 + index * 600.0 + rng.float_range(0, 200)
				_rect(parent, Rect2(x, base - 170, 240, 170), Color("#2f4a3a"))
				_rect(parent, Rect2(x - 10, base - 190, 260, 26), Color("#22362a"))
			for index in int(width / 900.0) + 1:
				var x := 300.0 + index * 900.0
				for step in 6:
					_line(parent, [Vector2(x, base - 260 - step * 110), Vector2(x + 220, base - 260 - step * 110)],
							Color("#1f1a18"), 8)
				_line(parent, [Vector2(x, base - 260), Vector2(x, CAMERA_TOP + 60)], Color("#1f1a18"), 8)
				_line(parent, [Vector2(x + 220, base - 260), Vector2(x + 220, CAMERA_TOP + 60)], Color("#1f1a18"), 8)
		"club":
			for y in [CAMERA_TOP + 90.0, base - 120.0]:
				_line(parent, [Vector2(0, y), Vector2(width, y)], palette.accent, 10)
			for index in int(width / 450.0):
				var x := 200.0 + index * 450.0
				var speaker := Rect2(x, base - 300, 140, 300)
				_rect(parent, speaker, Color("#0e0a14"))
				for cone in 2:
					var circle := Polygon2D.new()
					var center := speaker.position + Vector2(70, 80 + cone * 130)
					var points := PackedVector2Array()
					for step in 16:
						points.append(center + Vector2.from_angle(TAU * step / 16.0) * 46)
					circle.polygon = points
					circle.color = Color("#2b2236")
					parent.add_child(circle)
		"factory":
			for y in [CAMERA_TOP + 120.0, CAMERA_TOP + 170.0]:
				_line(parent, [Vector2(0, y), Vector2(width, y)], Color("#6b7178"), 22)
			for index in int(width / 700.0) + 1:
				var x := 250.0 + index * 700.0 + rng.float_range(-80, 80)
				_rect(parent, Rect2(x, base - 220, 180, 220), Color("#5b4636"))
				_rect(parent, Rect2(x + 200, base - 140, 180, 140), Color("#4d3b2e"))
		_:
			for index in int(width / 500.0):
				var x := 120.0 + index * 500.0
				_rect(parent, Rect2(x, base - 420, 260, 300), palette.wall_dark.darkened(0.25))


static func _rect(parent: Node2D, rect: Rect2, color: Color) -> Polygon2D:
	var polygon := Polygon2D.new()
	polygon.polygon = PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
	])
	polygon.color = color
	parent.add_child(polygon)
	return polygon


static func _line(parent: Node2D, points: Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = PackedVector2Array(points)
	line.default_color = color
	line.width = width
	parent.add_child(line)
	return line


static func _hazard_stripes(parent: Node2D, rect: Rect2) -> void:
	_rect(parent, rect, Color("#f5b82e"))
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		var stripe := Polygon2D.new()
		stripe.polygon = PackedVector2Array([
			Vector2(x, rect.end.y), Vector2(x + 30, rect.end.y),
			Vector2(x + 30 + rect.size.y, rect.position.y), Vector2(x + rect.size.y, rect.position.y),
		])
		stripe.color = Color("#1a1a1a")
		parent.add_child(stripe)
		x += 60


### -----------------------------------------------------------------------------------------------
