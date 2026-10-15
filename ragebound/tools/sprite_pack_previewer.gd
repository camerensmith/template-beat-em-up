extends Control

## Previews every sprite pack the loaded mods provide.
##
## Run [code]res://ragebound/tools/sprite_pack_previewer.tscn[/code] (F6 in the editor). Pick a pack
## and an animation to play it; hit frames flash red, and the panel lists which roles the pack
## qualifies for and what is still missing for the others.

### Member Variables and Dependencies -------------------------------------------------------------
#--- private variables - order: export > normal var > onready -------------------------------------

var _registry := RbContentRegistry.new()
var _packs: Array = []
var _current := {}

var _pack_list := OptionButton.new()
var _animation_list := OptionButton.new()
var _report := RichTextLabel.new()
var _sprite := AnimatedSprite2D.new()

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_registry.load_mods()
	_packs = _registry.get_all("sprite_pack")
	for pack in _packs:
		_pack_list.add_item(pack.name)
	if _packs.is_empty():
		_report.text = (
				"No sprite packs found in %s.\nAdd a sprite_packs/ folder to a mod."
				% [RbContentRegistry.DEFAULT_ROOTS]
		)
	else:
		_select_pack(0)


func _process(_delta: float) -> void:
	if _current.is_empty() or not _sprite.is_playing():
		return
	var animation: Dictionary = _current.animations.get(String(_sprite.animation), {})
	var is_hit: bool = _sprite.frame in animation.get("hit_frames", [])
	_sprite.modulate = Color(1, 0.4, 0.4) if is_hit else Color.WHITE

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.12, 0.12, 0.15)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var column := VBoxContainer.new()
	column.position = Vector2(40, 40)
	column.custom_minimum_size = Vector2(700, 0)
	add_child(column)
	column.add_child(_pack_list)
	column.add_child(_animation_list)
	_report.bbcode_enabled = true
	_report.fit_content = true
	_report.custom_minimum_size = Vector2(700, 400)
	column.add_child(_report)

	_sprite.position = Vector2(1300, 650)
	_sprite.scale = Vector2.ONE * 3
	add_child(_sprite)

	_pack_list.item_selected.connect(_select_pack)
	_animation_list.item_selected.connect(func(index):
		_sprite.play(_animation_list.get_item_text(index))
	)


func _select_pack(index: int) -> void:
	_current = _packs[index]
	var result := RbSpritePackImporter.import_pack(_current)
	_sprite.sprite_frames = result.frames
	if _current.has("origin"):
		_sprite.centered = false
		_sprite.offset = -Vector2(_current.origin.x, _current.origin.y)

	_animation_list.clear()
	if result.frames != null:
		for animation_name in result.frames.get_animation_names():
			_animation_list.add_item(animation_name)
		if _animation_list.item_count > 0:
			var names: PackedStringArray = result.frames.get_animation_names()
			var start: int = maxi(0, names.find("idle"))
			_animation_list.select(start)
			_sprite.play(names[start])

	var text := "[b]%s[/b]  (%s)\n\n" % [_current.name, _current.id]
	text += "Usable as: [color=#9fe870]%s[/color]\n" % (
			", ".join(PackedStringArray(result.roles)) if not result.roles.is_empty() else "nothing yet"
	)
	for role in result.missing:
		text += "Not %s - missing %s\n" % [role, ", ".join(PackedStringArray(result.missing[role]))]
	for problem in result.problems:
		text += "[color=#ff6b6b]%s[/color]\n" % problem
	_report.text = text

### -----------------------------------------------------------------------------------------------
