# Project prompt

This is the brief for anyone, human or AI agent, working on this repository.

## Goal

Implement **Seven Kingdoms II: The Fryhtan Wars** in a modern engine: Godot 4.3,
GDScript. Behaviour should follow the original game. Rules are ported from the GPL
release of the original source (https://github.com/7k2/7k2). Cite the original
function in comments (for example `Firm::pay_expense`, `Town::recruit`) where a rule
comes from it.

## Constraints

- **Ship no original assets.** Graphics, sound, music and game data tables are read
  at runtime from the player's own installed copy (Steam *Seven Kingdoms 2 HD*, GOG
  or the CD version). The code reads the original formats: RES/SPR/ICN bitmaps,
  DBF tables, save and scenario (`.scn`) files.
- **Rendering is moving to 3D.** The world will be a 3D scene. The original sprites
  are a temporary stand-in, drawn as camera-facing billboards, because the project
  does not own them. Keep the simulation independent of rendering: `scripts/sim`
  must not depend on how things are drawn, so the sprites can later be replaced
  with original 3D models.
- **Read original files the way the original does.** Where a file format or
  algorithm (for example terrain generation from a seed) must match the original,
  reproduce it exactly and verify it against reference output.
- GDScript is used throughout. Hot spots can move to a C++ GDExtension if
  profiling shows the need.

## Working rules

- Keep the headless tests in `tests/` passing. Add a test for every new rule or
  fixed bug. Run them with
  `godot --headless --path . res://tests/<name>_test.tscn`.
- Test the AI by watching computer-only games (AI vs AI). Run them on random maps,
  the original premade scenarios and the community scenarios in `scenario/`
  (`tests/sim_test.tscn`, `tests/scn_batch_test.tscn`).
- Check visual changes with screenshots (`--shot=<png>`, `--demo=<name>`).
- Record each round of work in `DEVLOG.md`. Keep README's feature and
  "not yet implemented" lists current.
- When behaviour differs from the original on purpose (simplifications, balance),
  say so in the code.
- Players' reports are the priority. Fix what a playtester reports first, then go
  back to feature work.
