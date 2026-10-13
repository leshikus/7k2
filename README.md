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
  combat and defence, siege weapons, your races' training centres and berserk
  attacks, the four offensive buildings). Build catapults, ballistae, spitfires,
  cannons, Porcupines (exploding carts) and Unicorns at the War Factory. Each
  weapon fights at the tech level it was built at.
* **Offensive buildings**: the Teledamnum (thunderbolt), Preuser (freezing blast),
  Testudo (tower) and Archimedetron (death ray), each fired from its panel for gold
  once charged.
* **Hire heroes** at the Inn. Pray at the **Seat of Power** to summon your race's
  Greater Being; find another race's **Scroll of Power** to build its Seat and
  summon its Greater Being too.
* **Items and treasure** lie on the map: heaps of gold, weapon blueprints, and 29
  items a soldier or Fryhtan can carry (Excalibur, Boots of Hermes, Ring of Life,
  Staff of Invincibility, Judas Ring, Telecordial …). Some work by themselves,
  others are used or switched on from the unit panel; a fallen unit drops its item.
* **Destroy Fryhtan lairs** for treasure. Their Fryhtans raid nearby kingdoms.
* **Fryhtan kingdoms** (zero to two, chosen on the start screen) breed Fryhtans
  with gold and life points, build lairs beside independent villages and
  terrorise them until they pay tribute, and raid human kingdoms. An enslaved
  village cannot join you while its lair stands.
* **Lead a Fryhtan kingdom** yourself: buy your species' technologies at its
  lairs with life points, and build its special buildings: Lishorr (camouflaged
  shooting plants), Wilde Lishorr (spreads wild), Bheema Hyfe and Tarmes Mownd
  (insects), Keraal (beasts for hire), Alchemist Tor (gold, life points and
  minerals converted), Vapngart (living war machines), Mage Tor (damage buildings,
  freeze, wound, teleport), and the Fortress four Grokkens turn into. Buy
  independent lairs next to your own.
* **The campaign — the Fryhtan Wars.** Lead the Western Empire of your nationality
  through the original campaign (difficulty 1–5). A map of twelve provinces is shared
  with the Eastern Empire and two or three Fryhtan kingdoms. Reports and letters,
  some asking for your decision, move provinces between kingdoms and lead to 28 kinds
  of battle, each on a map of its own: Fryhtan invasions, a hero's debut, joint
  attacks with Fryhtan or human allies, the hunt for a mega weapon, uprisings,
  training leaders, growing population, and the last battle against the East. Battles
  get random twists (rebels who join you, Viking Seats of Power, hidden spies,
  invisible Fryhtans …). Technologies are unveiled stage by stage, and your king and
  royal generals carry on from battle to battle. Texts come from your install.
* **Tutorial**: the original's eight learning campaigns (Human Training One to
  Three and their practice games, Fryhtan Training One and its game), on their maps
  from your install. They are taught step by step with the original texts: each step
  waits until you do what it asks (select your fort, fill it, send your soldiers out,
  build a mine, hire a caravan, train a spy …) or press Continue. T shows or hides
  the lesson's box.
* **Scenario editor** (start screen): on a new map with the chosen settings, time
  stands still while you place towns, buildings, armies, generals, kings, spies,
  heroes, Greater Beings, Fryhtans and their buildings, trees, rocks, lakes,
  deposits, treasure, items and Scrolls of Power. You can edit or remove the selected
  object (owner, population, loyalty, resistance, walls, combat, leadership, rank,
  item), set up the kingdoms (yours, names, gold, food, life points, reputation,
  technologies, new kingdoms), diplomacy, and victory and defeat goals. Saved
  scenarios appear in the start screen's scenario list.
* **Rally points**: the buildings that make units (War Factory, training centre,
  Espionage College, Inn, Seat of Power, Fryhtan breeding grounds, Keraal, Vapngart)
  can send what they make to a chosen spot. A tip from the original's TIPS.RES
  greets each game (it can be switched off).
* **Reports** (top bar): rankings of the kingdoms by population, military, economy,
  reputation and Fryhtans slain; your towns; income and expenses by kind for this
  year and last; your forts and armies; technologies; markets and caravans; and the
  news so far.
* **Hall of Fame**: a finished game's total score times the difficulty rating of
  its settings; the ten best human and Fryhtan rulers are listed on the start screen.
* **Diplomacy:** the original's 19 messages: trade, friendly and alliance treaties
  (and ending them), cease-fires, declarations of war, requests for military aid,
  embargoes or war on a third kingdom, buying food, tribute and aid offered or
  demanded, technology exchanges, buying a kingdom outright, and surrender. Computer
  kingdoms answer by the original's rules and send their own proposals, which wait
  in the Diplomacy window for your answer. Caravans trade only with kingdoms you
  have a trade treaty with. Attacking a kingdom you are not at war with requires
  Ctrl+right-click and starts a war.
* **Special Blessing**: with full prayer points the Seat of Power grants one of 23
  random wishes, as in the original.
* **Random events** (start screen setting): plagues, accidents, breakthroughs, new
  arrivals and finds every few hundred days.
* **Rebellions**: the malcontents of a disloyal town walk out as a rebel band that
  attacks your towns and buildings or settles elsewhere.
* **Caravans**: choose a caravan's destination market and the goods it loads, or
  clone it onto the same route.
* **Wagons and new towns**: send villagers out in a wagon, settle them in another
  town, or have any unit but the king build a new town.
* **Options** (game menu): volumes, help detail, major or all news, unit
  identities, unit paths on the main view and the world map, inside information,
  scrolling speed. The map has Terrain, Political (with zones of power) and Trade
  modes, kingdom and object filters, and Hide Buildings. A troop led by a general
  can take one of seven formations (number pad: facing).
* **Player profiles**: each player has his own saved games and campaign.
* **Network games** for up to seven players. One player hosts from the start screen:
  "Network game", Host, with the map settings above. The others enter the host's
  address and press Join. Each picks a nationality, Fryhtans included. The host
  starts the game; computer kingdoms fill the remaining places. The games run in
  lockstep, as in the original: every machine simulates the same world and only
  the players' orders travel, a turn of four frames later. The host sets the speed.
  Players can offer each other peace, which the other accepts in the Diplomacy
  window, and talk with Enter. If a player leaves, the computer takes over their
  kingdom. Network games cannot be saved.

### Controls

| Input | Action |
|---|---|
| Left click / drag | Select / box-select your units (Shift adds) |
| Right click | Move, attack, garrison a camp, or resume construction |
| Shift + right click | Add a waypoint: the units go there after their current move |
| Ctrl + right click | Attack a kingdom you are not at war with |
| Arrows / screen edge | Scroll (Options: speed, and Comfort or Speed scrolling) |
| Mouse wheel | Zoom |
| `[` / `]`, Ctrl+Up/Down | Turn the view a quarter turn / tilt it |
| Space, P | Pause; `+` / `-` change speed |
| Ctrl+1–9, 1–9 | Assign / recall unit groups |
| Tab | Stop the selected units |
| Number pad | Face a general's troop that way (formations) |
| A, C, G, K, R, W, Y, Z | Find an artifact, a caravan, a general, the king, a royal, a wagon, a spy, a Greater Being (Z again: cast) |
| B, D, E, F, H, I, M, N, T, U, V | Find a factory (B with bees selected: only the bees; Shift+B: drop them), Seat of Power, college, fort or lair, training ground, inn, market, offensive building, tower of science, mine, war factory |
| J | Find a natural resource |
| Page Up / Down, Home / End | The previous / next object of the selected kind, of any kingdom / of the same |
| Q | Change the map mode |
| O | Options |
| S / Ctrl+S, L / F9 | Quicksave / quickload |
| X | Clear the messages |
| F1–F8 | Reports: Kingdoms, Towns, Economy, Trade, Military, Technology, Espionage, Ranking |
| , / . | The tutorial's previous / next text |
| Enter | Message to the other players (network game) |
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
  Beings; 7 Fryhtan species with their lairs, technologies and special buildings;
  computer-run Fryhtan kingdoms; siege weapons and offensive buildings.
* Espionage: spies disguise themselves in another kingdom's colours, slip into towns,
  forts and camps, sow dissent or lie low, bribe generals and soldiers (a bought
  general hands his fort over), assassinate commanders, steal technology, stage
  incidents that start wars, read a kingdom's secret reports and camouflage
  themselves; your own spies at home hunt intruders. Eight spying technologies at the
  Tower of Science. Soldiers and generals have loyalty, and disloyal men desert.
* Caravans trading goods between your markets and those of friendly kingdoms.
* Town walls and village archers.
* Seasonal rain and thunderstorms that slow units and strike with lightning.
* Mountains, boulders and lakes from the original rock set; trees that grow and
  thin out; building explosions, fires on damaged buildings and rubble; ground
  fires from fire bombs; blast damage around heavy shells; sound effects.
* The original's help texts on action buttons, its credits, and battle markers on
  the minimap.
* Towns (population growth, loyalty, resistance, taxes, grants, recruiting,
  rebellion, surrender, militia defenders); camps and forts (garrisons, training,
  influence, sallying out); mine, factory and market production; Tower of Science,
  War Factory, Inn and Seat of Power; Training Grounds and the Espionage College,
  where trainees learn inside until you mobilize them.
* Buttons show symbols instead of words; hover for the words and the help text.
* The original's game settings: difficulty levels, rivals, treasure, aggressiveness,
  explored map and fog of war, resources, independent towns and their resistance,
  emerging towns and kingdoms, random events and goals, with its difficulty rating.
* Combat with the original's formulas: hit points by combat level, damage with
  piercing, leadership and technology bonuses, armour effectiveness and blow
  direction, guarding, heroes' special abilities, monthly training under a
  general, and forts and camps sending men to defend what is attacked.
* Greater Beings' aimed powers, natural earthquakes and tornadoes.
* Save and load (Ctrl+S/F9, pause menu, yearly autosave, "continue" on the start screen).
* The original game's 10 premade scenarios, read from your install, playable or
  watched as **AI vs AI** (also available for random maps), with their goals: kill
  or protect a named unit, conquer a town, reach a population, economy or military
  score, acquire a technology, an item or a scroll, ally with or defeat a kingdom,
  within a time limit.
* Computer kingdoms that expand, build economies, research, recruit, raise armies,
  clear lairs, declare war and make peace.

## Differences from the original

Every module of the original game has a counterpart here (see DEVLOG.md for the
review). The original's player profiles carry code for keeping heroes and items
between games that no menu of the original uses; here it is the start screen's "Bring the heroes and items of your profile" option.
Network play uses Godot's ENet instead of DirectPlay; IPX and modem play are gone.

## Project layout

```
scripts/assets/   sk2_files.gd (format readers), assets.gd (autoload: install
                  detection, tables, decoded textures, audio)
scripts/sim/      defs.gd (rules/constants), game.gd (world, time, links, fog,
                  events), unit.gd, firm.gd, town.gd, site.gd, bullet.gd,
                  nation.gd, ai.gd, world_map.gd (grid, A*), iso.gd (projection)
scripts/view/     terrain shader, fog, ground layer, trees, placement preview
scripts/ui/       start menu, HUD, minimap, selection box, campaign screen
scripts/campaign/ the Fryhtan Wars campaign: story, provinces, battles, texts
scripts/net/      net.gd (autoload): lobby and lockstep network play
scripts/tutorial/ tutorial.gd: the learning campaigns' lessons and objectives
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
godot --headless --path . res://tests/campaign_test.tscn                  # every campaign stage, the event chain
godot --headless --path . res://tests/net_test.tscn -- frames=4000        # two processes in lockstep
godot --headless --path . -s tests/asset_dump.gd                          # decode samples to user://dump
```

## License

The code in this repository is a derivative work of the GPL-licensed 7k2 source
and is likewise licensed under the GNU GPL v2 or later. *Seven Kingdoms* is a
trademark of Enlight Software; the game's art, sound and data remain theirs and
are only read from a legally owned installation.
