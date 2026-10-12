# Low-poly 3D models: plan

Goal: replace every original sprite with a low-poly 3D model that we own or that is
public domain, so the game can be sold. The simulation stays as it is. The 3D view
(`scripts/view3d/`) shows a model when one exists for an object and the sprite card
otherwise. Models can therefore arrive one group at a time.

## Licensing rule

Only **CC0** (public domain) third-party assets, or assets made here. The game will be
sold, so CC-BY-NC, "personal use", Mixamo, Sketchfab "standard" and similar licences
are out. CC-BY would be allowed with credit, but we avoid it to keep things simple.
Every imported file is listed in `assets/models/CREDITS.md` with its pack, author,
URL and licence. Original game art is used only as a visual reference, from
`tests/tools/ref_sheet.tscn` output written outside the repo, and is never traced
or committed.

| Source (all CC0) | Used for |
|---|---|
| KayKit Adventurers + Skeletons (Kay Lousberg, GitHub) | the shared humanoid rig and its 76 animations; body parts, weapons and shields |
| KayKit Medieval Hexagon pack | building parts: roofs, towers, mill wheels, props |
| Quaternius Medieval Village MegaKit | modular walls, roofs, doors and windows for the four building styles |
| Quaternius Stylized Nature MegaKit, Nature packs | trees, bushes, rocks, plants |
| Quaternius Farm Animals (horse), Animals Vol.2 (cat, wolf) | horse rig for cavalry, chariots and quadruped Fryhtan animals; jaguar |
| Quaternius Fantasy Props MegaKit, Medieval Weapons | weapons, barrels, crates, carts |
| Quaternius Universal Animation Library (Standard) | extra humanoid clips if KayKit lacks one |

## Tools

* **Blender 4.2 LTS, headless** (`tools/blender/*.py`, run with
  `blender -b -P script.py -- args`). Every model is *built by a script* from the
  CC0 parts plus procedural geometry, recoloured, and exported as `.glb`. Nothing is
  edited by hand, so the whole set can be rebuilt (`tools/blender/build_all.py`), and
  a change to a shared part (the rig, a palette) reaches every model.
* **Godot 4.3** imports the `.glb` files. `scripts/models/model_library.gd` maps
  sprite and firm codes to scenes and actions to animation clips.
* **Preview renders**: `tools/blender/preview.py` renders each model from the game's
  camera angle next to the original sprite's reference sheet for side-by-side review.

## Conventions

* 1 world unit = 1 location; y up; a model faces +z (the original's "south").
* Heights: civilian 1.1, infantry 1.2, cavalry 1.6, elephant 2.2, Greater Beings 3+.
  Buildings fill their footprint (`loc_w` × `loc_h` from FIRM tables).
* Low poly: humanoids ≤ 1.5k triangles, cavalry ≤ 3k, buildings ≤ 6k, trees ≤ 400.
  One shared 256×256 palette texture per family (flat colour cells, the KayKit
  style), so recolouring a race is a texture swap and draw calls batch.
* **Nation colour**: every model has a `team` material (tabards, banners, shields,
  roof trims). `ModelLibrary` sets its colour per nation, much as the original
  remaps palette indices.
* **Animations** are named by the sprite actions: `S` (stand/idle), `M` (move),
  `A1`, `A2` and `A3` (attacks, in UNITATTK order), `D` (die), and `I` (idle
  variant). The view scales each clip to the sprite action's duration
  (`action_len` × frame time), so hits and projectile launches land on the frame the
  simulation expects. `D` ends in a lying pose that is held until the body fades.

## Stages

1. **Pipeline and scaffolding**: Blender install, CC0 source packs, credits,
   reference sheets, `build_all.py`, `ModelLibrary` with the hook into View3D, and a
   model gallery scene (`tests/model_gallery.tscn`) with screenshots.
2. **Humans (36 units)**: civilian, infantry and special unit for 12 races on the
   one rig, each race with its own palette, headgear, armour pieces and weapons.
   Generals and kings get plumes and capes. Attack clips are mapped per unit
   (sword chop or stab, spear, bow shot, javelin or axe throw, monk kicks and
   punches, ninja shuriken).
3. **Mounted and large units**: horse rig (Norman, Roman, Greek, Mongol and Persian
   cavalry), the Egyptian chariot, Carthaginian and Indian elephants, the wagon and
   caravan.
4. **Fryhtans (7) and animals (5)**: the humanoid Fryhtans (Kharshuf, Kerassos,
   Minotauros, Grokken, Ezpinez, Exovum) get new meshes skinned to the humanoid rig,
   so they share its animations ("same skeleton, different skin"), with
   proportions changed through bone scale. The Bregma is a tentacled blob with a
   small custom rig. The Bheema (bee) and Tarmes (termite) get insect rigs. The
   Jaguara uses the cat rig, the Goril the humanoid rig (hunched), and the
   Rhinokeros the horse rig.
5. **Siege and Fryhtan bio-weapons (11)**: catapult, ballista, spitfire, cannon,
   porcupine, unicorn, mega cannon, mega unicorn, mega saw, nemezez, cobrez, peltez.
   Rigid parts are animated by node transforms (arm swing, recoil, wheels).
6. **Greater Beings (12)**: large flying figures on the humanoid rig with wings,
   halos and glow.
7. **Buildings**: four architectural styles (NE northern-European, ME
   Mediterranean, EA east-Asian, MA middle-eastern) × camp, fort, mine, factory,
   market, inn, tower of science, war factory and espionage college; the race-specific
   stables and Seats of Power; town houses per race; walls and fences; Fryhtan lairs
   and the other Fryhtan buildings. Construction stages: scaffold, then the model
   rising, then complete. Damage: fire and smoke particles, rubble.
8. **Nature and map objects**: trees per terrain, bushes, rocks, mountains,
   mineral deposits, rubble; drawn with MultiMeshInstance3D.
9. **Projectiles and effects**: arrows, javelins, axes, stones, fireballs and
   cannonballs as meshes; explosions, lightning, tornado, rain and spell effects as
   GPU particles.
10. **Finish**: remove the sprite cards for covered objects, free the camera
    (rotation and tilt), add LOD and animation culling, run performance tests with
    1,000 units, and update the README and DEVLOG.

Each stage ends with gallery screenshots, an in-game screenshot, the headless tests
passing, and a DEVLOG entry.

## Status (12 Oct 2026)

| Stage | State |
|---|---|
| 1 Pipeline | done: `tools/blender/` (sources, common, build_all), `ModelLibrary`, gallery test |
| 2 Humans | done: 36 units, 8 riders; first pass on looks |
| 3 Mounts | done: 5 horses, 2 elephants, chariot, caravan, wagon |
| 4 Fryhtans, animals | done: 7 Fryhtans, gorilla, jaguar, bee, termite, rhinoceros |
| 5 Siege | done: 12 weapons with code-animated parts |
| 6 Greater Beings | done: 12 |
| 7 Buildings | done: 9 firms × 4 styles, 24 race buildings, houses, town walls, Fryhtan buildings. Damage states are only fire and smoke so far |
| 8 Nature | done: 15 tree species × 3 sizes, bushes, rocks, mountains, mineral deposits (`make_site`) |
| 9 Effects | done: explosions, fires, spells, tornado (particles), projectiles. Lightning and rain are still 2D overlays |
| 10 Finish | free camera is on by default (done by the other session). Open: MultiMesh trees and LOD for big maps, art polish (proportions, more unit variety, damaged-building models), HUD portraits rendered from the models |
