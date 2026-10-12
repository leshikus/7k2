# Seven Kingdoms II — Godot edition

A reimplementation of **Seven Kingdoms II: The Fryhtan Wars** (Enlight, 1999) in
**Godot 4.3**, written in GDScript. Game rules are ported from the GPL release of the
original source ([7k2](https://github.com/7k2/7k2)). All graphics, music and game
data are loaded **at runtime from your own installed copy** of the game (Steam
*Seven Kingdoms 2 HD* or the original). No original assets are included in this
repository.

## Running

1. Install Godot 4.3 (standard build, not .NET).
2. Run `run.bat` (Windows; set `GODOT` to your Godot executable if it is not on `PATH`),
   or `godot --path .`, or open the project in the Godot editor and press F5.
3. The start screen finds the game automatically in common Steam/GOG folders. If it
   doesn't, paste the install folder (the one containing `Resource`, `Sprite`,
   `Firm`) and press **Load**. The path is remembered.

You can also set the `SK2_PATH` environment variable.

## Scenarios

`scenario/` holds 50+ community scenarios for Seven Kingdoms II (copyright their
respective owners). They appear in the start screen's scenario list after the
original game's premade ones, and can be played or watched as AI vs AI. To use them
in the original game instead, copy them to `My Games\Seven Kingdoms 2 HD\SCENARIO`.
`docs/` has strategy guides for the original game.

## Development

`PROMPT.md` is the project prompt: the goals, constraints and working rules given to
the AI agents (and people) developing this code. `DEVLOG.md` records what was done.

## Playing

You start with a town, a fort commanded by your king, and a general with two
soldiers. Grow your kingdom the Seven Kingdoms way:

* **Win towns over.** Build a camp or fort next to an independent town and put a
  general in it. The town's resistance falls toward a target set by the general's
  leadership, their race and your reputation. Below 30, the town joins you. Gold
  grants speed this up. Attacking a town also works, but it costs reputation.
* **Run an economy.** Build a mine on a clay, copper or iron deposit, a factory
  within range of the mine, and a market within range of the factory. Workers come
  from linked towns: 70% of a town can work, and the rest farm for food. Markets
  sell goods to linked towns of any kingdom.
* **Keep people loyal.** Loyalty depends on reputation, employment, same-race
  rulers, quality of life (goods in markets), linked camps and their generals,
  food and solvency. Disloyal towns rebel, or defect to rival camps.
* **Research** at the Tower of Science (mining, manufacturing, farming, infantry
  combat and defence, siege weapons). Build catapults, ballistae, spitfires and
  cannons at the War Factory.
* **Hire heroes** at the Inn. Pray at the **Seat of Power** to summon your race's
  Greater Being.
* **Destroy Fryhtan lairs** for treasure. Their Fryhtans raid nearby kingdoms.
* **Fryhtan kingdoms** (zero to two, chosen on the start screen) breed Fryhtans
  with gold and life points, build lairs beside independent villages and
  terrorise them until they pay tribute, and raid human kingdoms. An enslaved
  village cannot join you while its lair stands.
* **Diplomacy:** declare war or propose peace. Attacking a kingdom you are not at
  war with requires Ctrl+right-click and starts a war.

### Controls

| Input | Action |
|---|---|
| Left click / drag | Select / box-select your units (Shift adds) |
| Right click | Move, attack, garrison a camp, or resume construction |
| Ctrl + right click | Attack a kingdom you are not at war with |
| B | Build menu for the selected unit |
| WASD / arrows / screen edge | Scroll |
| Mouse wheel | Zoom |
| Q / E | Turn the view a quarter turn |
| R / F | Tilt the view (locked to the original angle while sprites are used) |
| Space | Pause, `+` / `-` change speed |
| Ctrl+1–9, 1–9 | Assign / recall unit groups |
| H | Centre on your king |
| N | Toggle sound effects |
| F5 / F9 | Quicksave / quickload |
| M | Toggle music |
| Esc | Cancel / deselect / game menu |

## What is implemented

* Readers for the original formats: resource indexes, the dBase tables in
  `STD.SET`, palettes, RLE sprite and building bitmaps with nation-colour remapping,
  terrain textures, town houses, trees, raw-material sites, unit portraits, JPEG
  screens and WAV music.
* A 3D world with blended terrain (shader), hill shading, trees, fog of war and a
  diamond minimap. The original's bitmaps are drawn as camera-facing cards; at the
  original's view angle the picture matches the original 2D projection. The camera
  turns in quarter turns; free rotation and tilt are settings on `CameraRig`.
* Experimental, off by default (`--models` turns them on): low-poly 3D models for
  every unit, Fryhtan, Greater Being, siege weapon, projectile, building, town, tree
  and rock, with skeletal animations and particle effects. They are built from CC0
  packs and procedural geometry by `tools/blender/` (`assets/models/CREDITS.md`).
* All 12 human races with their infantry, special units, civilians and Greater
  Beings; 7 Fryhtan species with their lairs; computer-run Fryhtan kingdoms;
  siege weapons.
* Spies that infiltrate towns and buildings to stir unrest, sabotage and steal technology.
* Caravans trading goods between your markets and those of friendly kingdoms.
* Town walls and village archers.
* Seasonal rain and thunderstorms that slow units and strike with lightning.
* Mountains, boulders and lakes from the original rock set; building
  explosions, fires on damaged buildings and rubble; sound effects.
* Towns (population growth, loyalty, resistance, taxes, grants, recruiting,
  rebellion, surrender, militia defenders); camps and forts (garrisons, training,
  influence, sallying out); mine, factory and market production; Tower of Science,
  War Factory, Inn and Seat of Power.
* Combat with melee and ranged attacks, projectiles, experience, death animations,
  armour and technology bonuses.
* Save and load (F5/F9, pause menu, yearly autosave, "continue" on the start screen).
* The original game's 10 premade scenarios, read from your install, playable or
  watched as **AI vs AI** (also available for random maps), with their goals: kill
  or protect a named unit, conquer a town, reach a population, economy or military
  score, acquire a technology, ally with or defeat a kingdom, within a time limit.
* Computer kingdoms that expand, build economies, research, recruit, raise armies,
  clear lairs, declare war and make peace.

## Not yet implemented

The full espionage system (bribery, assassination, disguise), the campaign, items and
scrolls lying on the map (and the scenario goals that need them), the Fryhtan special buildings (a Fryhtan
kingdom you lead has lairs only), and multiplayer. Balance values are adapted where this simplified simulation
differs from the original (noted in the code).

## Project layout

```
scripts/assets/   sk2_files.gd (format readers), assets.gd (autoload: install
                  detection, tables, decoded textures, audio)
scripts/sim/      defs.gd (rules/constants), game.gd (world, time, links, fog,
                  events), unit.gd, firm.gd, town.gd, site.gd, bullet.gd,
                  nation.gd, ai.gd, world_map.gd (grid, A*), iso.gd (projection)
scripts/view/     terrain shader, fog, ground layer, trees, placement preview
scripts/ui/       start menu, HUD, minimap, selection box
scripts/models/   model_library.gd (3D models for View3D), unit_models.gd (clips, weapons)
assets/models/    generated low-poly glTF models and their credits
tools/blender/    headless Blender scripts that build assets/models from CC0 packs
scripts/main.gd   scene root: camera, input, orders, music
tests/            headless tests (require the game data)
```

## Tests

```
godot --headless --path . res://tests/sim_test.tscn -- days=1500 seed=7   # all-AI soak test
godot --headless --path . res://tests/player_test.tscn                    # scripted player actions
godot --headless --path . res://tests/save_test.tscn                      # save/load round trip
godot --path . res://tests/input_test.tscn                                # drives the UI with mouse/keyboard events
godot --headless --path . -s tests/asset_dump.gd                          # decode samples to user://dump
```

## License

The code in this repository is a derivative work of the GPL-licensed 7k2 source
and is likewise licensed under the GNU GPL v2 or later. *Seven Kingdoms* is a
trademark of Enlight Software; the game's art, sound and data remain theirs and
are only read from a legally owned installation.
