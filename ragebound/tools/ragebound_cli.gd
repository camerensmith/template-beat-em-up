extends SceneTree

## Command line tools for content authors and modders.
##
## [codeblock]
## godot --headless -s res://ragebound/tools/ragebound_cli.gd -- validate [--mods res://mods,user://mods]
## godot --headless -s res://ragebound/tools/ragebound_cli.gd -- rift [--seed 7] [--rift downtown_rift] [--level 3] [--json]
## godot --headless -s res://ragebound/tools/ragebound_cli.gd -- loot [--seed 7] [--ilvl 10] [--count 10] [--table boss] [--mf 100]
## godot --headless -s res://ragebound/tools/ragebound_cli.gd -- sprite <sprite_pack_id>
## [/codeblock]
## Exits with code 1 when validation finds errors.

### Member Variables and Dependencies -------------------------------------------------------------
#--- constants ------------------------------------------------------------------------------------

const USAGE = """Ragebound content tools

  validate [--mods <roots>]       check every mod, then generate sample rifts for each template
  rift [--seed N] [--rift ID] [--level N] [--json]
                                  preview a generated rift
  loot [--seed N] [--ilvl N] [--count N] [--table ID] [--mf N]
                                  roll items or a loot table
  sprite <sprite_pack_id>         report which roles a sprite pack qualifies for

  --mods takes comma separated roots, default res://mods,user://mods"""

### -----------------------------------------------------------------------------------------------


### Built in Engine Methods -----------------------------------------------------------------------

func _init() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var command: String = args.pop_front() if not args.is_empty() else "help"
	var options := _parse_options(args)

	var registry := RbContentRegistry.new()
	var roots: Array = Array(options.get("mods", ",".join(RbContentRegistry.DEFAULT_ROOTS)).split(","))
	registry.load_mods(roots)

	var exit_code := 0
	match command:
		"validate":
			exit_code = _validate(registry)
		"rift":
			_rift(registry, options)
		"loot":
			_loot(registry, options)
		"sprite":
			exit_code = _sprite(registry, options.get("_positional", ""))
		_:
			print(USAGE)
	quit(exit_code)

### -----------------------------------------------------------------------------------------------


### Private Methods -------------------------------------------------------------------------------

func _validate(registry: RbContentRegistry) -> int:
	print(registry.get_report())
	var problems := RbRiftDirector.new(registry).check_templates()
	for problem in problems:
		print("RIFT ERROR: " + problem)
	if problems.is_empty():
		print("All rift templates generated legal runs.")
	return 0 if registry.errors.is_empty() and problems.is_empty() else 1


func _rift(registry: RbContentRegistry, options: Dictionary) -> void:
	var plan_options := {"level": int(options.get("level", "1"))}
	if options.has("rift"):
		plan_options["rift"] = options.rift
	var plan := RbRiftDirector.new(registry).generate(int(options.get("seed", "1")), plan_options)
	if options.has("json"):
		print(JSON.stringify(plan, "\t"))
	else:
		print(RbRiftDirector.describe_plan(plan))


func _loot(registry: RbContentRegistry, options: Dictionary) -> void:
	var generator := RbLootGenerator.new(registry)
	var rng := RbRng.new(int(options.get("seed", "1")))
	var item_level := int(options.get("ilvl", "10"))
	var bonuses := {"magic_find_pct": float(options.get("mf", "0"))}
	var items: Array[RbItem] = []
	for _index in int(options.get("count", "8")):
		if options.has("table"):
			for drop in generator.roll_table(options.table, item_level, rng, bonuses):
				if drop.kind == "item":
					items.append(drop.item)
				else:
					print("%s gold\n" % drop.amount)
		else:
			items.append(generator.generate_item(item_level, rng, bonuses))
	for item in items:
		print("\n".join(item.describe()) + "\n")


func _sprite(registry: RbContentRegistry, pack_id: String) -> int:
	var pack := registry.get_entry("sprite_pack", pack_id)
	if pack.is_empty():
		print("No sprite pack '%s'. Known: %s" % [pack_id, registry.get_ids("sprite_pack")])
		return 1
	var result := RbSpritePackImporter.import_pack(pack)
	print("%s can be used as: %s" % [pack.id, ", ".join(PackedStringArray(result.roles))])
	for role in result.missing:
		print("  not %s, missing: %s" % [role, ", ".join(PackedStringArray(result.missing[role]))])
	for problem in result.problems:
		print("  ERROR: " + problem)
	return 0 if result.problems.is_empty() else 1


static func _parse_options(args: Array) -> Dictionary:
	var options := {}
	var index := 0
	while index < args.size():
		var arg: String = args[index]
		if arg.begins_with("--"):
			var key := arg.trim_prefix("--")
			var has_value: bool = index + 1 < args.size() and not args[index + 1].begins_with("--")
			options[key] = args[index + 1] if has_value else "true"
			index += 2 if has_value else 1
		else:
			options["_positional"] = arg
			index += 1
	return options

### -----------------------------------------------------------------------------------------------
