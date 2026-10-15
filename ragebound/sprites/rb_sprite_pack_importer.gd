class_name RbSpritePackImporter
extends RefCounted

## Validates standardized sprite sheets and turns them into [SpriteFrames].
##
## A sprite pack is one sheet on a fixed grid plus metadata saying which row/columns hold each
## animation (see the [code]sprite_pack[/code] schema). Packs face right; left-facing versions
## are mirrored at runtime the same way the template mirrors its animations.
## [br][br]
## [method qualify] reports which roles a pack can fill (playable, enemy, miniboss, boss), so a
## new sheet becomes usable in every role its animation coverage allows without hand wiring.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

## Animations every fighting body needs, whatever its role.
const CORE_ANIMATIONS = [
	"idle", "walk", "hurt_mid", "hurt_high", "knockout_launch", "knockout_falling",
	"knockout_landed", "getting_up", "die",
]

const ATTACK_PREFIXES = ["punch_", "kick_", "attack_", "air_attack", "throw", "slam"]

## role -> {required animation names, minimum number of attack animations}
const ROLE_REQUIREMENTS = {
	"enemy": {"animations": [], "attacks": 1},
	"miniboss": {"animations": [], "attacks": 2},
	"boss": {"animations": [], "attacks": 3},
	"playable": {
		"animations": [
			"punch_1", "punch_2", "punch_3", "jump_impulse", "jump_rising", "jump_falling",
			"jump_landing", "air_attack",
		],
		"attacks": 4,
	},
}

### -----------------------------------------------------------------------------------------------


### Public Methods --------------------------------------------------------------------------------

static func is_attack(animation_name: String) -> bool:
	return ATTACK_PREFIXES.any(func(prefix): return animation_name.begins_with(prefix))


## Returns [code]{roles: Array, missing: {role: Array}, problems: Array}[/code].
## [code]problems[/code] are errors that block every role, like attacks without hit frames.
static func qualify(pack: Dictionary) -> Dictionary:
	var animations: Dictionary = pack.get("animations", {})
	var problems := []
	for animation_name in animations:
		var animation: Dictionary = animations[animation_name]
		var hit_frames: Array = animation.get("hit_frames", [])
		if is_attack(animation_name) and hit_frames.is_empty():
			problems.append("attack animation '%s' has no hit_frames" % animation_name)
		for frame in hit_frames:
			if frame >= animation.frames:
				problems.append("'%s' hit frame %s is past its %s frames" % [
						animation_name, frame, animation.frames
				])

	var attack_count := animations.keys().filter(func(name): return is_attack(name)).size()
	var missing_core := CORE_ANIMATIONS.filter(func(name): return not animations.has(name))
	var result := {"roles": [], "missing": {}, "problems": problems}
	for role in ROLE_REQUIREMENTS:
		var requirement: Dictionary = ROLE_REQUIREMENTS[role]
		var missing: Array = missing_core + requirement.animations.filter(
				func(name): return not animations.has(name)
		)
		if attack_count < requirement.attacks:
			missing.append("%s more attack animation(s)" % (requirement.attacks - attack_count))
		if missing.is_empty() and problems.is_empty():
			result.roles.append(role)
		else:
			result.missing[role] = missing
	return result


## Checks every animation fits inside the sheet.
static func check_sheet(pack: Dictionary, sheet_size: Vector2i) -> PackedStringArray:
	var problems := PackedStringArray()
	var cell := Vector2i(pack.cell.width, pack.cell.height)
	if sheet_size.x % cell.x != 0 or sheet_size.y % cell.y != 0:
		problems.append("sheet %s is not a multiple of the %s cell size" % [sheet_size, cell])
	for animation_name in pack.animations:
		var animation: Dictionary = pack.animations[animation_name]
		var last_column: int = animation.get("column", 0) + animation.frames
		if last_column * cell.x > sheet_size.x or (animation.row + 1) * cell.y > sheet_size.y:
			problems.append("'%s' runs outside the sheet" % animation_name)
	return problems


## Loads a sheet from res:// (imported) or from any file path such as user://mods (raw PNG).
static func load_sheet(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


static func build_sprite_frames(pack: Dictionary, sheet: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var cell := Vector2(pack.cell.width, pack.cell.height)
	for animation_name in pack.animations:
		var animation: Dictionary = pack.animations[animation_name]
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, animation.get("fps", 10.0))
		frames.set_animation_loop(animation_name, animation.get("loop", false))
		for index in animation.frames:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(
					Vector2(animation.get("column", 0) + index, animation.row) * cell, cell
			)
			frames.add_frame(animation_name, atlas)
	return frames


## Full import used by tools: qualify + sheet check + SpriteFrames.
## Returns [code]{frames: SpriteFrames, roles: Array, missing: Dictionary, problems: Array}[/code].
static func import_pack(pack: Dictionary) -> Dictionary:
	var result := qualify(pack)
	var sheet := load_sheet(pack.sheet)
	if sheet == null:
		result.problems.append("could not load sheet %s" % pack.sheet)
		result.roles.clear()
		result["frames"] = null
		return result

	var sheet_problems := check_sheet(pack, Vector2i(sheet.get_size()))
	if not sheet_problems.is_empty():
		result.problems.append_array(sheet_problems)
		result.roles.clear()
	result["frames"] = build_sprite_frames(pack, sheet)
	return result

### -----------------------------------------------------------------------------------------------
