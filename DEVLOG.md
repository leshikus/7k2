# Development log

## Overnight session (12–13 Oct 2026)

Everything below was checked with the headless test suite and with screenshots
of the running game.

### Graphics fixes
- **Selection outlines now match the art.** The original shifts every bitmap at
  load time ("modify offset_x/y for 7k2" in the source). That correction was
  missing, so buildings, units, trees, deposits and houses were drawn up to 96 px
  off their footprints.
- **Towns** draw like `Town::draw`: houses are centred on their layout slots,
  plants in town slots stand on the slot point, and the ground uses
  `TOWN_ADJ_OFFSET`. Larger towns pick the multi-house layouts.
- **Flags**: towns fly the animated race pennant in the owner's colour, and
  buildings under construction show corner flags. The made-up banners are gone.
- **Construction** is drawn solid and darkened (40%→90% brightness), as in
  `FirmRes::calc_color_remap_table`, instead of translucent.
- **Unit shadows** use palette index 0 as a translucent shadow.

### New features
- **Save and load**: F5/F9, Save/Load in the pause menu, a yearly autosave, and
  "Load saved game" / "Continue from autosave" on the start screen.
- **Sound effects** from `A_WAVE1/A_WAVE2.RES` via the `SOUNDRES` table: attacks,
  deaths, unit select and acknowledge, building select. Volume falls off with
  distance from the screen centre. N toggles them.
- **Mountains, boulders and lakes** from the original rock set, placed by the
  original generator's rules. They block movement and building.
- **Destruction effects**: explosion, rubble sized to the building, and fires on
  buildings below 30% hit points (`FIRM_DIE.FRM`).
- **Fryhtan kingdoms** (computer-controlled, 0–2 on the start screen). They breed
  in lairs with gold and life points, earn life points by killing, build lairs
  next to villages and terrorise them into paying tribute, and raid human
  kingdoms. An enslaved village cannot join a human kingdom while its lair stands.
- **Special unit training centres** for all 12 races (Estable, Sacred Grove,
  Shao Lin Temple, Ninja Dojo …). Each trains the race's special unit from town
  volunteers.
- **Town walls and archers**: every town has its race's fence, and it can build
  a wall (500) and then a fortified wall (1000) with jobless labour. Walls absorb
  attacks, show damage frames, and shield the town from enemy influence. Villagers
  shoot arrows at hostile units nearby.
- Right-click on the minimap moves the selected units. Double-click selects all
  your units of that type on screen. Building and town thumbnails appear in the
  info panel.
- **Greater Being powers** (ou_god.cpp): Mars raises leadership, Athena makes
  troops invulnerable, Baal-Hammon brings an earthquake, Tengri turns enemy
  units, Hanuman summons a tornado, Mithra reveals the land, and Amaterasu
  freezes enemies (my substitute: the original power targets spies, which
  aren't implemented). Use the "Cast power" button. **Blessings** while
  worshipped: Norman taxes, Egyptian growth, Chinese markets, Carthaginian food,
  Mongol influence, Greek walls. The AI casts powers too.
- **Blend sprites** (spell effects, the tornado, some missiles) use the original
  log-alpha blending instead of showing as dithered blocks.

- **Weather** after oweather.cpp: seasonal cloud spells, rain that slows units
  by each sprite's RAIN_SLOW value, thunderstorms with lightning strikes
  (LIGHTN_DMG damage), a rain overlay, and the install's rain and thunder sounds.
  The shipped game has snow disabled (`Weather::snow_scale` returns 0), so there
  is no snow here either. The current weather shows in the top bar.

- **Caravans and trade**: hire a caravan at a market (100 gold, up to 3 per
  market). It runs to the nearest market it isn't linked to, your own or one of
  a kingdom at peace with you. It unloads goods that market lacks and brings back
  goods in return. Foreign deliveries earn both kingdoms money, and caravans can
  be raided. The AI hires caravans too.

- **Espionage (simplified)**: the Espionage College trains spies from town
  volunteers. Right-click a spy on an enemy or independent town or building to
  infiltrate it. Spies in towns stir unrest (loyalty or resistance falls); spies
  in buildings can sabotage, or steal a technology from a Tower of Science
  (skill 70+). Their chance of being caught falls with skill. Manage them from
  the **Spies** button. The AI sends spies against kingdoms it is at war with.

### Balance and AI
- Fryhtan lairs no longer breed past their capacity, so raiders no longer pile
  up outside. Raids are rarer and hit kingdoms rather than independent villages.
- The human AI closes money-losing mine chains when in debt, waits before going
  on the offensive against Fryhtans, and keeps towns above 25 people.
- Soldiers attacking a building fight back against units that attack them, then
  return to the siege. Nearby allies join in.

### Tests (all passing)
- `tests/input_test.tscn` drives the game with real mouse and keyboard events:
  select, move, build, box-select, garrison, recruit, double-click, minimap
  orders, F5/F9.
- `tests/player_test.tscn`: town capture, economy chain, training centre, lair
  assault.
- `tests/save_test.tscn`: an exact save/load round trip, then continued play.
- `tests/sim_test.tscn`: an all-AI soak test, e.g. 5000 days on a 160×160 map
  with 6 kingdoms (about 2.3 ms per simulation frame).
- `tests/god_test.tscn`: every Greater Being power has its effect.
- `tests/spy_test.tscn`: train, infiltrate, sabotage, steal a technology.
- `tests/caravan_test.tscn`: a caravan delivers goods to a foreign market.
- `tests/weather_test.tscn`: rain frequency over three years and rain slowdown.
- `tests/fryhtan_test.tscn`, `tests/sound_check.tscn`.

## Premade scenarios and AI vs AI

### Scenarios from the original game
- The 10 premade scenarios in `Scenario/Premade` are original saved games.
  `scripts/sim/scenario_file.gd` reads them; `scripts/sim/scenario_loader.gd`
  builds the game from them.
- Each section is found by its book mark (0x1000+n). Unit, firm, town and
  nation records use the packed field layouts of the FileIOVisitor templates
  in ogfile3.cpp: 233, 296, 402 and 3180 bytes. Camp, fort and lair garrisons
  come from the raw FirmCamp data (45-byte Soldier entries).
- The terrain is not stored; the original regenerates it from the saved seed.
  The port does the same: the plasma height map, remove_odd() and the terrain
  height bands, drawing from the game's own random-number generator (MSVC
  evaluates the arguments of `generate(misc.random(2), 5, misc.rand())` right
  to left). The output matches a Python reference on all 10 maps.
- Loaded from each scenario:
  - kingdoms: race, colour, gold, food, relations, and which one the player
    controls (Fryhtan kingdoms included);
  - towns: name, population, loyalty, resistance, walls;
  - buildings: the exact FBUILD variant, damage and construction state,
    overseers, soldiers and builders;
  - units: heroes and kings;
  - raw-material sites, rocks, ponds and trees;
  - the explored area.
- Not loaded: items, scrolls and gold on the ground, spies (their true side is
  in the spy array), and the scenario's own goals.
- Fryhtan and siege towers that scenarios contain (Lishorr, Wilde Lishorr,
  Mage Tor, the offensive buildings) shoot at enemies in range.
- Menu: pick a scenario (with its description and picture) and press
  **Play scenario**. Command line: `--scenario=rome [--spectate]`.

### AI vs AI
- The **Watch AI vs AI** checkbox works for scenarios and random maps. Every
  kingdom is computer-controlled and the map is revealed.
- The top bar lists the surviving kingdoms. With nothing selected, the side
  panel shows a scoreboard: towns, population, buildings, units, gold, wars.
- Event messages use neutral wording, and the game ends when one kingdom is
  left.
- `tests/sim_test.tscn -- scn=rome days=4000 verbose=1` runs a scenario
  headless.

### Fixes found by playing all 10 scenarios computer-only for 4000 days
- A kingdom with no towns and no buildings for 60 days disbands
  (NationBase::defeated). Without this, a few wandering soldiers kept a dead
  kingdom alive and games never ended.
- AI in debt now closes upkeep-heavy towers, espionage colleges and training
  centres. Jaws previously ran to -39,000 gold.
- Empty towns are removed even when dead defenders were still listed, or when
  a spy or special unit took the last villager.
- Computer kingdoms keep at least 20 villagers when training special units,
  war machines and spies; Plasma's winner used to recruit its towns empty.
- Fryhtan AI turns surplus gold into life points at the Alchemist Tor rate
  (2 gold per point), so tribute is no longer hoarded. In Lishorrs the brood
  grew from 5 to 27.
- Results: Rome, Hashshashin, Gallic, Lost Tribe and Plasma end with one
  winner; Jaws ends in a Fryhtan victory; Mongol Horde ends in a strong
  Chinese-Indian peace; Isis leaves two Fryhtan kingdoms.

## Playtest fixes (12 Oct 2026, evening)

- **Sprite facing.** The SW, W and NW frames in the sprite files face the other way
  (their shadows fall to the right); the original draws them mirrored. We now flip
  them, so units walking west no longer walk backwards.
- **Fort doors.** Units leave and appear on the right-down face of a building
  (`Firm.door()`), where the art has its doors.
- **Town walls** under construction show as a see-through wall that firms up as it is built.
- **Right-click on buttons.** "Collect tax" cycles an auto-tax loyalty level
  (60/70/80/90/100/off), "Grant gold" an auto-grant level (below 30/40/50/60/70/off).
  Fort occupants are listed as buttons: left-click sends one out and selects him,
  right-click on a general makes him commander.
- **Fill from towns** drafts villagers straight into the fort without the loyalty
  cost of a town recruit (FirmCamp's recruit). The town button is now "Recruit peasant".
- **Citizen combat level.** Every villager leaving a town starts at combat 10.
- **Playing as Fryhtans.** The species are listed under Nationality. You start with a
  lair, your leader and a brood; lairs breed for gold and life points, and Fryhtan
  units build new lairs (300 gold, 200 life points).
- **Upkeep.** As in Firm::pay_expense, a building the treasury cannot pay for loses a
  hit point a day instead of driving the kingdom into debt. The AI closes at most one
  useless building a month and keeps towers and forts unless deeply in debt. This
  stopped Carthage in Jaws selling off its 17 Testudos in the first months.

## Rendering moved to 3D (12 Oct 2026, night)

The world is now a 3D scene (`scripts/view3d/`). The original sprites are only a
stand-in, since the project does not own them.

- **Simulation and drawing are separated.** Every object's `_draw()` became
  `render(cv)`, which draws onto whatever canvas it is given. The 2D nodes stay
  in the tree but hidden. `View3D` replays their `render()` into a
  `DrawRecorder` each frame.
- **Cards and decals.** Bitmaps become camera-facing `Sprite3D` cards standing on
  the object's ground anchor, drawn without depth test and sorted by that anchor,
  which reproduces the original draw order. Ground art (foundations, deposits,
  lakes, rubble) becomes flat decals. Lines, bars and labels go to a screen
  overlay (`View3DOverlay`).
- **Terrain and fog.** The terrain is a plane using the 2D terrain shader. Fog is a
  last full-screen pass that darkens each pixel by the fog of the ground under it,
  as the 2D fog layer did.
- **Pixel-identical at the original angle.** Screenshots of the same game match
  the 2D renderer on 100% of pixels (within 8 levels): fogged, revealed, terrain
  and objects.
- **Camera.** `CameraRig` keeps the 2D camera's API (`iso_pos`, `zoom`, `offset`).
  It is a free orbit camera, limited for now: `yaw_step` = 90° (Q/E) and pitch
  locked at 30° (R/F within `pitch_min`..`pitch_max`). `--free-camera` lifts the
  limits for testing; `--yaw=<deg>` starts turned.
  - `CameraRig.direction_map()` remaps unit facings so sprites face their way of
    travel after a turn.
- **Picking.** Mouse rays hit the ground plane. Units are picked by their
  projected figure, everything else by the ground location. The input test
  drives the real scene and passes. Headless tests now set a 1280×800 window.
- **Model hook.** `View3D.model_provider` takes any object with `make(obj)` and
  `sync(obj, model)`. `main.gd` loads `res://scripts/models/model_library.gd`
  when it exists. Objects with a model skip their cards; overlays still come
  from `render()`.

## Low-poly 3D models (12 Oct 2026)

Plan: `docs/3D_MODELS_PLAN.md`. Every sprite the game draws in the world now has a
low-poly 3D replacement, built by headless Blender scripts from CC0 packs and
procedural geometry. Licences are listed in `assets/models/CREDITS.md`. The game
is meant to be sold, so only CC0 sources are used.

- **Pipeline.** Blender 4.2 LTS runs headless with the scripts in `tools/blender/`.
  `sources.py fetch` downloads the CC0 packs to `../sk2assets/src` and checks
  each OpenGameArt page still says CC0. `build_all.py` rebuilds all ~250 models
  into `assets/models/` (about 25 MB). Nothing is edited by hand.
- **One rig, many skins.** All humanoids (36 human units, 8 riders, 11 Greater
  Beings, 6 humanoid Fryhtans and the gorilla) are KayKit's 41-bone rig. Each is
  assembled from KayKit body parts with heads shrunk 32% from chibi proportions,
  plus procedural race headgear (nasal helms, galeas with crests, kabuto, nemes,
  turbans, fur caps …), weapons and shields. Meshes are re-UV'd onto a 32-role
  palette, so a race is one 512×128 texture; the palette's alpha channel marks the
  nation-colour cells.
- **Shared animations.** `anims/humanoid.glb` holds 95 KayKit clips plus 11
  generated `Ride_*` clips (seated straddling legs + upper-body attack).
  `UnitModels` maps each sprite action (S, M, A1–A3, D) to a clip and shows or
  hides weapons per action (e.g. Normans swap sword and shield for a crossbow on
  A2). Attack clips are time-scaled to the sprite action's length, so the hit lands
  on the frame the simulation delivers it. Walk speed matches ground speed.
- **Mounts and carts.** Quaternius' farm-animal rig gives five horse coats, two
  elephants (reshaped cow with trunk, ears, tusks, caparison, howdah), the
  rhinoceros and Chi Lin. Riders sit on a bone attachment at the saddle point
  stored in `mounts/mounts.json`. The chariot, caravan and wagon are rigid carts
  with spinning wheels, pulled by animated horses.
- **Fryhtans and animals.** New skins on the humanoid rig: Kharshuf (plant-man),
  Bregma (brain-blob on tentacles), Kerassos (horned), Minotauros (bull head,
  tail, great axe), Grokken (bulked rock giant throwing boulders), Ezpinez (gold
  insect knight), Exovum (white raptor). Bheema (bee) and Tarmes (crab rig) use
  Quaternius' cute-monster rigs; the Jaguara uses the cat rig with pounce and death
  clips keyed in Blender.
- **Siege weapons** (12, including the Fryhtan bio-weapons): rigid models whose
  catapult arm, cannon barrel recoil and mega-saw are animated in code against the
  attack's progress. **Projectiles** (arrows, javelins, bolts, axes, stones,
  cannonballs, fireballs, spit, shuriken, sparks) fly an arc and point along it.
- **Buildings.** 9 firm types × 4 architectural styles (NE timber and stone, ME
  Mediterranean, EA pagoda, MA domes), 12 race stables and Seats of Power
  (cathedral, classical temple, pagoda, domed temple, stepped pyramid), 24 town
  houses, 12 town walls (fence, wall, fortified × style), Fryhtan lairs, hive,
  mound and the other Fryhtan buildings. Each is scaled to its footprint
  (`buildings/footprints.json`) and rises from the ground while being built.
  Towns fill every house slot of the original layout with a cluster of houses.
- **Nature.** The original's 15 tree species (purple bush, bamboo, flowering,
  autumn, willow, cypress, palm …) at three growth stages, bushes, boulders and
  mountains stretched to each rock's footprint.
- **Effects.** Building explosions, fires and smoke, spell flashes and Hanuman's
  tornado are `CPUParticles3D` (the Compatibility renderer).
- **Look.** Models use a self-lit shader with a fixed sun (the scene has no
  lights, like the pre-lit sprites). Models load in background threads at start.
- **Tests.** `tests/model_gallery.tscn` renders any set of units in any action
  from the game camera (`codes=… act=S|M|A1|…|cycle shot=…`). All headless tests
  and the input test pass.

Mineral deposits are 3D piles too (`make_site`). Still drawn from the original art: ground decals (building foundations,
lakes, rubble), the lightning bolt and rain overlays, and the
HUD's portraits and icons.

## Scenario goals, items and scrolls (13 Oct 2026)

- **Scenario goals** are read from each scenario's EndCondition records and checked
  daily (`scripts/sim/goals.gd`); the kingdom panel shows each goal's progress.
- **Treasure on the map** (`scripts/sim/treasure.gd`, osite.cpp/ositedrw.cpp): Scrolls
  of Power, gold heaps (`COINS-1..8` by site number), items and weapon blueprints,
  placed by scenarios or scattered on random maps; any unit that steps on one takes
  it. A kingdom knows its own god; a scroll lets it build that race's Seat of Power.
  A dying king drops a scroll his kingdom knows.
- **Items** (`scripts/sim/items.gd`, the 29 of oitemres.cpp): attack, armour, speed,
  combat and leadership bonuses, absorbing and invincibility, freezing, Fryhtan banes,
  recharging potions, and manual items aimed at a unit, a town or a place. The
  computer sends idle units to treasure near its bases.
- **Walking pace.** A move step that reaches a cell carries on toward the next, so
  units no longer stall for a frame at every cell boundary (it showed as a hitch in
  the walk cycle). Mirrored facings (SW, W, NW) were checked frame by frame
  against their E-side twins (`tests/tools/walk_strip`, `walk_film`, `walk_probe`).

## Espionage (13 Oct 2026)

Ported from ospy.cpp, ospya.cpp, ospy2.cpp and of_campb.cpp (`scripts/sim/espionage.gd`):

- **Disguise.** A spy in the field can pass for any kingdom (`Unit.cloak_id`); others
  judge it by its colours (`Game.is_hostile` uses `seen_nation()`), its owner sees a
  diamond of its true colour over its head. No change with an enemy within 5 cells;
  attacking drops the disguise. Ordered into a kingdom's town or fort, a spy puts on
  its colours automatically. **Camouflage** (with the tech) hides it for a while.
- **Places.** Towns and forts/camps (the original has no spies among workers).
  Spies **sow dissent** (towns lose loyalty or resistance at skill/4/population a
  month; the men of the spy's race in a fort lose loyalty) or **sleep** (almost never
  caught). Once a month each place tries to catch one active intruder; its owner's
  own spies there are the counter-spies (`SpyArray::catch_spy`).
- **Loyalty** for soldiers and generals (`Soldier::target_loyalty`,
  `Unit::update_loyalty`), shown in the panels; men below 30 may desert.
- **Missions** from the place's panel, with their success chances: bribe a general
  or soldier with 500–4000 gold (a refused bribe costs the spy); a bribed man stays as
  a sleeper, walks out as your spy when released, and a bribed general can **capture**
  the fort (soldiers who will not follow him walk out); **assassinate** the
  commander; **steal technology**; **create an incident** that drives two kingdoms
  to war; read the **secret report**.
- The eight **spying technologies** (Agitation, Counter-spy, Information Theft,
  Bribing, Assassination, Technology Theft, Camouflage, Incident) are researched at
  the Tower of Science and gate or strengthen these missions.
- **Computer kingdoms** build a college, keep a spy at home, send spies into the
  independent villages they want or the forts and towns of their enemy, and bribe,
  capture, assassinate, steal and stage incidents by the original's `think_*` rules.
- Sabotage is gone: 7k2 disabled it (`Spy::can_sabotage` returns 0).
- Tests: `tests/spy_test` (45 checks); `tests/tools/spy_watch` plays a computer-only
  game and tallies spy events.
