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
