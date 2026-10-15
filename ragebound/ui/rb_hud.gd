extends CanvasLayer

## Ragebound overlay: message feed, run status, character sheet and floating damage numbers.
##
## Built in code so it can sit on top of any stage without editing the template's HUD scenes.
## Toggle the character sheet with the [code]character_sheet[/code] input action.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const MAX_FEED_LINES = 8
const FEED_LINE_SECONDS = 4.0
const FONT_SIZE = 28
const DAMAGE_FONT_SIZE = 44
const DAMAGE_NUMBER_OFFSET = Vector2(0, -260)

#--- private variables - order: export > normal var > onready -------------------------------------

var _feed: VBoxContainer
var _status: Label
var _sheet: PanelContainer
var _sheet_text: RichTextLabel

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_feed()
	_build_status()
	_build_sheet()

	var ragebound := get_parent()
	ragebound.message_posted.connect(_on_message_posted)
	ragebound.hit_resolved.connect(_on_hit_resolved)
	ragebound.hero_changed.connect(_refresh)
	ragebound.run_started.connect(func(_plan): _refresh())
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("character_sheet") and event.is_action_pressed("character_sheet"):
		_sheet.visible = not _sheet.visible
		if _sheet.visible:
			_refresh()
		get_viewport().set_input_as_handled()

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.anchor_top = 1.0
	_feed.anchor_bottom = 1.0
	_feed.offset_left = 40
	_feed.offset_top = -40
	_feed.offset_bottom = -40
	_feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)


func _build_status() -> void:
	_status = Label.new()
	_status.anchor_left = 1.0
	_status.anchor_right = 1.0
	_status.offset_left = -900
	_status.offset_right = -40
	_status.offset_top = 170
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_label_style(_status, FONT_SIZE, Color("#e8e8e8"))
	add_child(_status)


func _build_sheet() -> void:
	_sheet = PanelContainer.new()
	_sheet.set_anchors_preset(Control.PRESET_CENTER)
	_sheet.custom_minimum_size = Vector2(1100, 760)
	_sheet.offset_left = -550
	_sheet.offset_right = 550
	_sheet.offset_top = -380
	_sheet.offset_bottom = 380
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, 0.92)
	style.border_color = Color("#ff8a1f")
	style.set_border_width_all(3)
	style.set_content_margin_all(28)
	_sheet.add_theme_stylebox_override("panel", style)
	_sheet.visible = false

	_sheet_text = RichTextLabel.new()
	_sheet_text.bbcode_enabled = true
	_sheet_text.scroll_active = true
	_sheet_text.add_theme_font_size_override("normal_font_size", 24)
	_sheet_text.add_theme_font_size_override("bold_font_size", 26)
	_sheet.add_child(_sheet_text)
	add_child(_sheet)


func _refresh() -> void:
	var ragebound := get_parent()
	var hero: RbHero = ragebound.hero
	if hero == null:
		_status.text = ""
		return
	var registry: RbContentRegistry = ragebound.registry
	var class_name_text: String = registry.get_entry("class", hero.class_id).get("name", "?")
	var plan: Dictionary = ragebound.plan
	var lines := PackedStringArray()
	if not plan.is_empty():
		lines.append("%s  -  rift level %s" % [plan.get("name", ""), plan.get("level", 1)])
	lines.append("%s  Lv %s   XP %s/%s   %s gold" % [
			class_name_text, hero.level, hero.xp, RbProgression.xp_to_next(hero.level), hero.gold
	])
	_status.text = "\n".join(lines)

	if _sheet.visible:
		_sheet_text.text = _build_sheet_text(ragebound, hero, registry, class_name_text)


func _build_sheet_text(
		ragebound: Node, hero: RbHero, registry: RbContentRegistry, class_name_text: String
) -> String:
	var text := "[b]%s - Level %s[/b]   (unspent skill points: %s)\n\n" % [
			class_name_text, hero.level, hero.skill_points
	]
	text += "[b]Stats[/b]\n"
	for line in ragebound.get_player_stats().describe():
		text += "  %s\n" % line

	text += "\n[b]Equipped[/b]\n"
	for slot in RbContentSchema.SLOTS:
		var item: RbItem = hero.equipment.get(slot)
		if item == null:
			text += "  %-8s -\n" % slot.capitalize()
		else:
			text += "  %-8s %s  [color=#999999]%s[/color]\n" % [
					slot.capitalize(), _colored_name(item, registry),
					", ".join(RbStats.describe_all(item.get_stats())),
			]

	text += "\n[b]Skills[/b]\n"
	for skill_id in hero.skill_ranks:
		var skill := registry.get_entry("skill", skill_id)
		text += "  %s %s/%s\n" % [skill.get("name", skill_id), hero.skill_ranks[skill_id],
				skill.get("max_rank", 1)]

	text += "\n[b]Stash[/b] (%s/%s)\n" % [hero.inventory.size(), RbHero.MAX_INVENTORY]
	for index in range(hero.inventory.size() - 1, maxi(-1, hero.inventory.size() - 9), -1):
		text += "  %s\n" % _colored_name(hero.inventory[index], registry)
	return text


func _colored_name(item: RbItem, registry: RbContentRegistry) -> String:
	var color: String = registry.get_entry("rarity", item.rarity_id).get("color", "#ffffff")
	return "[color=%s]%s[/color]" % [color, item.name]


func _on_message_posted(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	_apply_label_style(label, FONT_SIZE, color)
	_feed.add_child(label)
	while _feed.get_child_count() > MAX_FEED_LINES:
		_feed.get_child(0).free()

	var tween := label.create_tween()
	tween.tween_interval(FEED_LINE_SECONDS)
	tween.tween_property(label, "modulate:a", 0.0, 0.6)
	tween.tween_callback(label.queue_free)
	_refresh()


func _on_hit_resolved(target: QuiverAttributes, damage: int, is_crit: bool) -> void:
	if target == null or not is_instance_valid(target.character_node) or damage <= 0:
		return
	var character := target.character_node
	if not character.is_inside_tree():
		return

	var label := Label.new()
	label.text = ("%s!" % damage) if is_crit else str(damage)
	var color := Color("#ffd84a") if is_crit else Color.WHITE
	_apply_label_style(label, DAMAGE_FONT_SIZE + (16 if is_crit else 0), color)
	label.z_index = 100
	label.top_level = true
	character.add_child(label)
	label.global_position = character.global_position + DAMAGE_NUMBER_OFFSET \
			+ Vector2(randf_range(-40, 40), 0)

	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position:y", label.global_position.y - 90, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)


static func _apply_label_style(label: Label, font_size: int, color: Color) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 8)

### -----------------------------------------------------------------------------------------------
