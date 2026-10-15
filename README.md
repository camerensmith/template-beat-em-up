# RAGEBOUND
A side-scrolling combat ARPG that happens to play like *Streets of Rage*: beat-'em-up combat,
Diablo-style classes and loot, Mortal Kombat-style depth, and procedurally assembled rifts, all
fully moddable. Built on the Downtown Beatdown template (original README below).

**Read the design, architecture and modding guide: [docs/RAGEBOUND.md](docs/RAGEBOUND.md)**

| | |
| --- | --- |
| `mods/base_game/` | All game content as data: 10 classes, skills, enemies, bosses, elites, items, affixes, uniques, sets, loot tables, stage segments, encounters, rifts, mutators |
| `ragebound/` | Mod registry and schemas, loot, stats and combat math, rift director, hero progression, gameplay hooks, HUD, sprite pack importer, tools and tests |
| `examples/mods/` | A community pack showing new content, overrides and patches |

```sh
# tests and content validation (open the project in the editor once first)
godot --headless -s res://ragebound/tests/run_tests.gd
godot --headless -s res://ragebound/tools/ragebound_cli.gd -- validate
godot --headless -s res://ragebound/tools/ragebound_cli.gd -- rift --seed 7 --level 3
```

In game, press **Tab** / **I** / gamepad **Back** to open the character sheet.

---

# Downtown Beatdown: Beat-em-up game template
An open source 2D beat-em-up game template for Godot 4, to make games like *Streets of Rage*.
Created by [Quiver](https://quiver.dev).

## Trailer
[![Downtown Beatdown Trailer](https://image.mux.com/V79F1t5LueA43ChEhn5nbAV013mD2JmFnPATeb402389Q/animated.gif?start=8&end=14)](https://quiver.dev/assets/game-templates/downtown-beatdown-beat-em-up-godot-4-template/#lg=1&slide=0)

(click to watch the full trailer!)

## Features
- Customizable player and enemy characters
- Configurable attacks
- Detailed environments with background and foreground elements
- Day and night effects
- Level blocking to constrain fights to particular areas
- Customizable enemy AI
- Custom inspectors and debugging tools
- Fully open source!
- Free assets!

## Topics covered
- Advanced animations using ```AnimationPlayer``` and ```AnimationTree```
- State machines
- Custom inspectors
- Custom overlays

## Documentation
Coming soon!

## Requirements
* Godot 4.0 RC6 or higher

## Installation instructions
* This project uses [Git Large File Storage](https://git-lfs.github.com/) (LFS) to store asset binaries. To initialize it make sure you have LFS installed, then simply run ```git lfs install```
* Clone this repository from Github
* Open the Godot project file in Godot 4 (Beta or higher) and run it to play the demo!

## Questions/Bugs/Suggestions
For bugs and feature requests, feel free to file an issue here or comment on this template's [project page](https://quiver.dev/assets/game-templates/downtown-beatdown-beat-em-up-godot-4-template/).

## Share with the community!
If you manage to incorporate this template into your next project, please share with the [Quiver community](https://quiver.dev/)!

## More game templates
Want more game templates? Check out our growing collection [here](https://quiver.dev/assets/game-templates/).
