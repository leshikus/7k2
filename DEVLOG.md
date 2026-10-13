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

## Fryhtan special buildings and the remaining technologies (13 Oct 2026)

Ported from `of_lair.cpp`, `of_mtrn.cpp`, `of_anim.cpp`, `of_alch.cpp`,
`of_incu.cpp`, `of_mfort.cpp`, `of_lish.cpp` and `of_magi.cpp`
(`scripts/sim/special_firms.gd`).

- **Fryhtan technology**: each species has its own techs (TECH classes PLANT …
  GREMJERM), bought at once at a lair of that species for life points
  (`FirmLair::buy_tech`). The price is complexity × 10 life points (× 20 in the
  original, halved for this economy).
- **Special buildings**, each unlocked by its tech: Lishorr (damage by tech level
  and weather, camouflaged as a plant with Camouflage Ability until it fires),
  Wilde Lishorr (goes wild and spreads in February and July), Bheema Hyfe and
  Tarmes Mownd (breed insects), Keraal (tamed beasts come for hire every two
  weeks), Alchemist Tor (life ↔ gold at 2:1, minerals → 0.2 life or 0.4 gold when
  built on a deposit, Advanced Alchemy doubles the rate), Vapngart (grows Cobrez,
  Peltez and Nemezez), Mage Tor (Damage Building, Freeze Units, Wound Units,
  Teleport Unit; a 100-point charge that refills a day at a time, paid in life
  points plus extra per cell beyond range).
- **Fortress**: four Grokkens standing together turn into one (hit points grow
  with the tech level); up to four Fryhtans posted inside shoot at enemies within
  8 cells, a Grokken as if 25 combat levels higher. Camouflaged Fortress hides it
  as a rock.
- **Independent lairs** can be bought by a Fryhtan kingdom with a commanded lair
  next to them (`grant_to_non_own_lair`, at least 2000 gold).
- **Human techs**: the Porcupine (`ou_cart.cpp`: explodes beside its target,
  sets off nearby carts, camouflaged from version 2) and the Unicorn; per-race
  training-centre (Special Unit Structure) and Berserker techs, researchable only
  for races you have towns of. The training centre needs the first; the special
  unit's power attack needs the second (`Unit::can_attack_with`).
- **Offensive buildings** (OFF_BLD1–4) researched at the Tower of Science.
  Teledamnum, Preuser and Archimedetron cast with the Mage Tor rules for gold;
  Testudo shoots on its own. Computer-owned ones fire by themselves.
- **Weapon versions**: war machines and Fryhtan units keep the tech level they
  were built at and use that level's attack set (`get_weapon_version`).
- **AI**: computer Fryhtans buy techs, build special buildings, breed, hire,
  convert, make fortresses and take independent lairs once their brood is strong.
  Computer kingdoms research the new techs and build an offensive building by a
  fort. Their Towers of Science were often idle, because research was assigned
  after several early returns; now it is assigned first.
- `--autostart --race=GITH --demo=specials` starts a Grokken kingdom with every
  special building; without `--race` it shows the human offensive buildings.
- New test `special_firms_test` (45 checks) and tool `tests/tools/fryhtan_watch`.

## The campaign (13 Oct 2026)

A port of `CampaignEastWest` (`ocampgn*.cpp`, `oc_east*.cpp`, `oc_easte.cpp`,
`oc_pl*.cpp`, `ostate.cpp`), in `scripts/campaign/`.

- **Texts** (`campaign_text.gd`): the install's `Campaign/EAST.STG`, `EAST.EVT` and
  `EAST.PLT` are read as ResourceIdx files; letters split at `~` into the
  heading, the letter and the replies; `%s`/`%d` are filled in.
- **Provinces** (`state_map.gd`): twelve regions on a 100 × 100 map around random
  capitals, with neighbours and border flags. The original weighs distances with
  random strengths; additive weights keep each province in one piece.
- **Story** (`campaign.gd`): nations (Western Empire, Eastern Empire, two or three
  Fryhtan kingdoms named from MNAMEA/B/C, later a new kingdom and rebels), all 23
  events and the result handling of all 28 stages, following the original
  branch by branch: Fryhtan takeovers, betrayal of a province, peace offers,
  the hero who takes the throne, Fryhtan civil wars and joint attacks, offers of
  help from the East, surrender of a Fryhtan kingdom (its troops may fight for
  you, then may revolt), the new kingdom, independent provinces, ultimate
  victory. A lost battle that the original replays restores the random state
  first. Technologies are unveiled per stage (`unveil_new_tech`); the king and
  up to four royal generals carry their names and skills between battles.
  Random points that come to nothing are run again, as in the original; after
  40 fruitless runs the campaign moves on by force.
- **Battles** (`campaign_battle.gd`): every stage's map is built with ports of
  `create_nation_town`, `create_monster_lair`, `create_slave_town`,
  `create_economic_firm`, `create_military_firm`, `create_troop`, `create_lair`,
  `create_monster_special_firm`, `create_offensive_structure`,
  `create_rebel_nation` and the resource levels and campaign "situations". Stage
  hooks run each day: rebellions, generals defecting to found kingdoms, Fryhtan
  reinforcements at the map edge and into lairs, armies without a base marching
  on your towns, the hero of stage 6 (losing him loses the battle). The 16
  plots (A1–A7, C1–C4, D1–D5) are ported; AI diplomacy messages are replaced by
  their outcome (an alliance offered, a kingdom surrendering).
- **Goals**: "defeat all but one ally" in every battle, plus the stage's own:
  Fryhtan battling score, military and economic score, destroy a kingdom, take
  the plans of a mega weapon, total score, ten generals of leadership 90,
  population. Goals now report which condition ended the game.
- **Mega weapons**: Mega Cannon, Mega Unicorn and Mega Saw are not researchable;
  a fallen king drops their plans, and a War Factory builds them once known.
- **Fryhtan battling score** also grows by 0.1 per blow struck at a Fryhtan
  (`BaseObj::being_attack_hit`), as campaign goals expect.
- **Screen** (`ui/campaign_screen.gd`): the province map in the kingdoms'
  colours (click to choose a province to attack), reports and letters with
  reply buttons, the battle briefing, and the end-of-battle panel leading back.
  A campaign battle can be saved and loaded like any game. The campaign itself
  is saved to `user://saves/campaign.json` after every step; "Continue the
  campaign" appears on the start screen.
- Simplified: wagons of settlers arrive as villagers; armies are not formed
  into teams; the province attack animation is an arrow on the map.
- `--campaign` opens a new campaign; `--campaign --campaign-battle` goes
  straight to its first battle. New test `campaign_test`: every stage's battle
  built and run for 40 days, the event chain to the end, save and load.

## Network play (13 Oct 2026)

Lockstep multiplayer as the original plays it (`remote.cpp`), in
`scripts/net/net.gd` (autoload `Net`), over Godot's ENet.

- **Commands**: every action a player takes is a command,
  `Net.cmd(target, "method", [args])`. The target is a unit, building or town
  (by id), a nation, the game, or the static `Espionage` / `SpecialFirms`.
  Alone, a command runs at once, so single-player play is unchanged. All HUD
  actions and the map orders in `main.gd` go through it. Multi-step actions
  became single methods on the simulation: `Firm.fill_from_towns`,
  `release_all_soldiers`, `queue_spy`, `Unit.promote` / `demote` /
  `order_move_free` / `use_item_cmd`, `Town.collect_tax_cmd`,
  `Game.cmd_place_building`, `offer_peace`, `set_speed`, `set_paused`.
- **Lockstep**: a turn is 4 frames. Commands issued during turn t run at turn
  t+2 on every machine. Clients send their commands to the host; the host
  sends each turn's bundle (in player order) to all; a machine runs a turn
  only when it has the bundle, so faster machines wait. If a player leaves, the
  host stops waiting for them and adds `mp_drop_player` to the next bundle: the
  computer takes over that kingdom on every machine at the same turn.
- **Checksums**: every 25 turns each machine sends a hash of positions, hit
  points, populations, treasuries and the random state to the host, which
  warns everyone if they differ.
- **Determinism audit**: the simulation draws random numbers only from the
  game's seeded generator. A burning building's flames drew from it only when
  the building was on screen; flames now use a separate generator for
  pictures. A plot shuffle used the global generator. Everything that depends
  on the local player (fog, sounds, messages, selection) leaves the simulation
  untouched. A finished player's game keeps running in step.
- **Lobby**: "Network game" on the start screen (address, port, Host, Join,
  Leave), a player list with nationalities, and Start for the host with the
  map settings. Kingdoms are created for each player in the host's order, then
  computer kingdoms and Fryhtans. Peace between players is offered and then
  accepted in the Diplomacy window. Enter opens a chat line. Speed and pause
  are the host's. Network games cannot be saved.
- The start screen now scrolls when the window is too short.
- `tests/net_test`: the host launches a second Godot process as the client.
  Both issue orders: moves, recruits, filling a fort, a declaration of war and
  a speed change. The two simulations must end identical: 4,000 frames (400
  days) with computer kingdoms passed, with no drift reported along the way.
  `drop=N` has the client leave at frame N, and the computer must take over
  its kingdom.

## Reports and the Hall of Fame (13 Oct 2026)

- **Reports window** (`ui/reports.gd`, after `or_*.cpp`). It has pages for
  Kingdoms (the five ranking scores and the total), Towns, Economy,
  Military, Technology, Trade and News (the last 300 messages).
- **Money by kind**: `Nation.add_cash(v, kind)` books income and expenses by kind,
  as the original's INCOME_* / EXPENSE_* types do: taxes, sale of goods,
  exports, tribute, treasure, conversion; buildings, construction, training,
  hiring, weapons, spies, grants, imports, walls, caravans. The totals of this
  year and last are kept and saved.
- **Hall of Fame** (`sim/hall_of_fame.gd`, after `ogamhall.cpp` / `ogamend.cpp`).
  A finished game of one player scores its total ranking score times a
  difficulty rating derived from the start settings, divided by 100. The ten best
  human and Fryhtan games are kept in `user://hall_of_fame.json` and shown from
  the start screen.
- `--autostart --demo=reports --report=N` opens a report page after 120 days.
  New test `reports_test`.

## Tutorial (13 Oct 2026)

The learning campaigns of `otutor.cpp` / `otutor3.cpp`, in `scripts/tutorial/`.

- The eight lessons that ship with the game (TUT_LIST.RES): Human Training
  One, Two and Three with their practice games, and Fryhtan Training One with
  its game. The other four entries have no map in the install.
- **Maps**: the `.tut` files in the install's Tutorial folder are saved games
  in the scenario format; `ScenarioFile` and `ScenarioLoader` load them
  unchanged.
- **Texts**: TUT_TEXT.RES holds each lesson's blocks. Each block has an
  optional `Button :` line and a `Title: * NN` line naming its objective. The
  B-entries hold the hints the original pinned to objects on the map; they are
  shown under the text here.
- **Objectives**: the conditions of `update_tutorial_objective_finish_count`
  are ported as a table per lesson. A step can wait for: selecting the lesson's
  fort, town or lair (named by the map's goals, in their original order);
  pressing a button (the original's button codes mapped to this interface's
  actions); a building finished; an attack on a town; units heading home; a
  spy in a selected town or camp; the diplomacy window; one of the map's goals;
  or Continue. Steps that rely on parts of the original's interface this port
  lacks (trade treaties, cloning a caravan, the blessing icon) wait for
  Continue instead.
- **Box** (`ui/tutorial_panel.gd`): the step's pages with ◀ ▶, the hints,
  Continue when the step waits for it, "Show me" to look at the step's object,
  Hide (T toggles it). Lessons 1, 2, 4 and 9 build and train ten times faster,
  as the original's `set_fast_build`.
- A **Return** action sends selected soldiers or Fryhtans back into the nearest
  fort, camp or lair with room (the original's RETCAMP / F_RETCMP).
- Start screen: Tutorial list with the lesson's description, and "Learn".
  `--tutorial=N` starts lesson N. New test `tutorial_test`.

## Scenario editor (13 Oct 2026)

After `oseditor.cpp` / `osedit_*.cpp` (`ui/scenario_editor.gd`): an editor mode
of the game in which the simulation does not run. Its pages:
- **Place**: for each kingdom, the independents and wild Fryhtans, or nature.
- **Selected**: edit or remove the selected object.
- **Kingdoms**: the player's kingdom, names, treasury, technologies, new
  kingdoms.
- **Diplomacy**: the relations between kingdoms.
- **Goals**: 19 kinds of victory and defeat conditions, by number, kingdom or
  selected object, with time limits and "all goals".
- **Scenario**: name, briefing, save, save and play.

Scenarios are saved as saved games with a name and briefing in
`user://scenarios/`. They are listed with the premade scenarios and start on
day 0 with fresh fog. `--editor` opens it. New test `editor_test`.

## Waypoints, rally points and tips (13 Oct 2026)

- **Waypoints** (`owaypnt.cpp`): Shift+right-click queues a further place to
  go after the current move.
- **Rally points** (`send_to_rally_point`): a "Rally point" action on buildings
  that make units sets where the units gather; right-click clears it. Units
  from war factories, training centres, colleges, inns, Seats of Power,
  breeding grounds, the Keraal and the Vapngart walk there. Rally points are
  saved.
- **Tips** (`otips.cpp`): a tip from the install's TIPS.RES (human, Fryhtan or
  campaign section) at the start of a game, with Next tip and "Don't show
  tips". The original's P (pause) and K (find the king) keys work as aliases.
- The help file (HELP.RES) only positions tooltips on the original's screen
  layout; this interface has its own tooltips.
- New test `waypoint_test`.


## Completeness pass against the original modules (13 Oct 2026)

A module-by-module check of `src/*.cpp` against the port found these missing or
simplified, now ported:
- **Credits** (`ogamcred.cpp`): a Credits button on the start screen shows the
  install's CREDIT.RES over Credits1.jpg (the HD release's index offsets cut
  names in half, so the text is read whole). `--credits` opens it.
- **Report hotkeys** from HELP.RES: F1 Kingdoms, F2 Towns, F3 Economy, F4 Trade,
  F5 Military, F6 Technology, F7 Espionage, F8 Ranking. Quick save moved from F5
  to Ctrl+S (F9 still loads).
- **Help texts** (`ohelp.cpp`): HELP.RES also holds 160 texts keyed by button
  help code. Action buttons now show the original text for the button they
  stand for (`ui/help_text.gd`), followed by our own note.
- **Special Blessing** (`of_basew.cpp`): with full prayer points (400) the Seat
  of Power's Bless button draws one of the original's 23 wishes by rarity:
  research breakthroughs, veteran soldiers, spies, Fryhtans and heroes, items,
  gold, food, a new deposit with a mine, defections of units, forts and towns,
  spies exposed, healing, loyalty and combat. A wish with no effect halves the
  points; otherwise they are used up. Tutorial lesson 9 step 21 waits for it.
  Under fast build the Seat gains its full productivity a day, as the original.
- **Diplomacy** (`otalkres.cpp`, `otalkmsg.cpp`, `oai_talk.cpp`, `oai_dipl.cpp`):
  all 19 messages (trade, friendly and alliance treaties and their ending,
  military aid, embargo, cease-fire, request for war, buying food, declaring
  war, tribute and aid offered or demanded, technology exchange, purchase of a
  kingdom, surrender). The computer answers by the original's rules on its
  feelings for the sender (ai_relation_level), trade worth, military and
  overall ranks and its personality; it also starts talks itself (cease-fires,
  trade treaties, alliances, friendly treaties, ending treaties with kingdoms
  it dislikes, food purchases, technology exchanges). Messages to a human ruler
  wait in the Diplomacy window for Accept or Reject. A **trade treaty** now
  gates caravan trade with foreign markets (UnitCaravan::can_set_stop);
  alliances bring one. Tutorial lesson 5 step 15 waits for a trade proposal.
- **Caravans**: Set destination (a market of yours or of a treaty partner),
  goods to load (the pick-up selection; none ticked = automatic), and Clone
  caravan (`duplicate_caravan`, lesson 5 step 26).
- **Random events** (`oevent.cpp`): the 13 events (breakthrough, lost scroll,
  rats, plague deaths of a general or soldier, sickness in a fort, a stranger
  or a wagon of settlers joining, a cache of artifacts, plague in a town,
  accidents wrecking a factory, mine or inn), every 200 to 1000 days by the
  new "Random events" setting (default Low, as the original).
- **Ground fire and splash damage** (`obullet.cpp`, `ow_fire.cpp`): attacks
  carry the table's BUL_RADIUS and FL_RADIUS. Heavy shells hurt everyone within
  their radius (full damage falling to half at the edge), sparing the
  shooter's men; fire bombs set cells alight, which burn trees and hurt whoever
  stands there until they die down (rain shortens them). As in the shipped
  game's settings, fire does not spread.
- **Plant growth** (`ow_plant.cpp`): the shipped game never sets plant_limit,
  so trees neither seed nor spread; daily, a sample grows a stage and crowded
  trees die. New maps are thinned once as World::plant_init does.
- **Rebellions** (`orebel.cpp`, Town::think_rebel): a disloyal town no longer
  turns independent as a whole; 30-60% of its people walk out as a rebel band
  under a general, hostile to their old kingdom, which attacks a town or
  building of it or settles in a town of its race. A leaderless band surrenders
  to the most reputable kingdom. Bands are saved.
- **War points** (`owarpt.cpp`): flashing crosses on the minimap where your
  units or buildings are under attack.
- Stage 6's hero now has the original's combat of 200 to 300.

New tests: `wish_test`, `diplomacy_test`, `events_test`, `fire_test`,
`rebel_test`; `caravan_test` and `input_test` extended.

Still simplified (noted in the code): wagons of settlers are villagers;
hit points do not scale with combat level; kingdoms can talk from the start
(the original requires contact); trade treaties in premade scenario files are
assumed for friendly kingdoms, as the files' relation records are not read.

## The remaining simplifications, and the options (13 Oct 2026)

Closing the gaps listed above and the rest of a full review of `src/*.cpp`:
- **Hit points by combat level** (Skill::actual_max_hit_points): a living unit
  has its table's hit points times its combat level over 100; war machines,
  caravans and Greater Beings keep the default level of 100. Blows lose the
  target's armour and are divided by ATTACK_SLOW_DOWN (3), as
  BaseObj::being_attack_hit. Starting armies follow Battle::create_unit (king
  combat and leadership 100, seven fort soldiers at 20, generals 30-100); the
  old doubled hit points of kings are gone.
- **Contact between kingdoms** (NationRelation::has_contact): computer
  kingdoms know each other, and the human rulers of a network game; a human
  ruler meets a kingdom when exploring reveals its town or building (sent as
  a command, so network games agree). Diplomacy needs contact.
- **Scenario files' trade treaties and contacts** are now read from the
  NationRelation records (244 bytes each, before the status array).
- **Wagons and new towns** (ou_wagon.cpp, Town::recruit, Unit::settle_town,
  Town::process_construction): "Send out wagon" sends up to ten villagers in a
  wagon; any human unit but the king, or a wagon, can "Build a town" (200
  gold); the town is built a percent every other frame and its builders move
  in. Wagons settle into towns of their race. Random events and the campaign
  bring real wagons. Computer kingdoms split towns near their population limit
  (Town::think_split_town).
- **Options** (ooptmenu.cpp) in the game menu: sound and music volume, help
  (none, brief, detailed), display news (major only / all, News::is_major),
  show unit identities, **show unit paths** (no, main map, world map, both;
  marching dashes from square to square), inside information (computer
  kingdoms' details, their units' paths, and an "AI" report page after
  or_ai.cpp), scrolling speed. With worshippers at a Japanese Seat of Power the
  paths of units marching on you show in red.
- **The map** (oworld_m.cpp): Terrain, Political (again: the kingdoms' zones
  of power, World::set_power) and Trade maps, the Nation and Object filters,
  and Hide Buildings (coloured squares with names on the main view).
- **Formations** (oformat.cpp): a troop with a general can take one of the
  seven formations (vanguard, line, circle, arc, staggered, square,
  sandwich); it keeps it wherever it stops, and the number pad sets its facing.
  The shapes are simpler patterns than the original's placement code.
- **Player profiles** (oprofile.cpp): "Change player" on the start screen; each
  player has his own saved games and campaign, and his king bears his name.
- The help file's screen-area entries now give the tooltips of the report
  tabs, the top bar and the map buttons.

New tests: `wagon_test`, `options_test`.
