# Reported bugs and requests

Every problem reported while playing, oldest first. **Open** items are at the
top; the rest are fixed (the fix is described in the commit log and, where it
departs from the original game, in DIFFERENCES.md).

## Open

- **Fryhtans stuck near impassable ground** (Kerassos that cannot pick up a
  sword; a group of Kerassos; a group of Kharshuf piled on one cell). Units now
  remember targets they cannot reach and give up on them, and computer units
  refuse attack orders on unreachable targets. *Under observation*: report any
  group that still stands still for long.

## Fixed

| Report | Status |
|---|---|
| No way to start a game as a Fryhtan except in scenarios | fixed: "Play as" in the new-game menu |
| On the first screen the scrollbar overlays the buttons | fixed |
| Fort exit dialog hides the numbers; Alt+1–4 parameter selector | fixed |
| Soldiers could build any building (the original allows military ones only) | fixed |
| Several selected soldiers lose "settle in town"; right-click on a town should do | fixed |
| Safe passage zones around buildings | fixed |
| Demote button inconsistent | fixed |
| General's effect on village loyalty doubtful | checked against the original; breakdown shown in the town panel |
| Saved games not sorted by time | fixed |
| Game should start paused; pause icon not selected at start | fixed |
| Safe zone border not shown when placing a building | fixed |
| Taxes should wait so each collection costs only 10 loyalty | fixed |
| Inns displayed a link; links on and off looked alike | fixed |
| a/b counts don't fit in building icons above three digits | fixed |
| Inn produced generals only; squads | fixed (inn heroes, squads, recruiting policies) |
| Auto reward / auto retreat for all units; levels 10/20/30, 30/40/50; auto tax 40/50/60, auto grant 30/40/50 | done |
| Ruling a city should raise leadership | checked: the original counts led soldiers; soldier count fixed |
| Initial buildings ignored the safe zones | fixed |
| Money taken before the builder reached the site | fixed: paid on arrival |
| Safe zone went past the map edge; camp too close to the border | fixed: the zone must lie inside the map |
| Second caravan stop unclear | fixed: panel clarified; waypoints added |
| Factory switching products loses stock | fixed: stored goods still go to markets and caravans |
| Auto-hire took units of skill 100+ | fixed |
| Speed buttons coloured differently / of different widths | fixed |
| Super-weapon research available without the scroll | fixed |
| Space stopped working for pause | fixed |
| Generals marked by red flags, not stars | fixed |
| Fryhtans could not enter a fort | fixed |
| AI built markets and forts with nothing to serve | fixed |
| Fryhtans had no loyalty | fixed |
| G to cycle through squads | done |
| AI did not use inns; human-side AI should hire there | fixed |
| Bregma attacking one village killed by stones from another | fixed: only a village under attack throws stones |
| Soldier tooltip should name his general | done |
| "Eject all" not needed in forts | removed |
| Selling a building showed the ruin animation | fixed |
| Health bar colour by combat level | done |
| Hall of fame empty | fixed (Retire; six entries) |
| Fryhtan portraits mismatched their sprites | fixed: map sprites used |
| Fort overlapped a market | fixed: buildings keep their spacing |
| Green Fryhtan "kingdom" missing from statistics | it is a wild lair; labelled "Wild Fryhtans (independent)" |
| Killing should pay by combat level; Fryhtans gain life points | done as in the original |
| AI should wall its settlements early | done |
| AI should gather small towns with no mine into bigger ones | done |
| AI creates caravans and they vanish quickly | fixed: a new caravan's last-load day started at 0, so the AI dismissed it within a month |
| Speed buttons pushed off the top bar when many kingdoms are listed; the kingdom list there not needed | fixed: the line is clipped; in AI-vs-AI mode the kingdoms are in its tooltip and the F1 report |
| A human and a Fryhtan kingdom share a colour | fixed: eight extra colours after the original seven |
| Fryhtans standing at a full lair | fixed: a unit turned away at a door does not go back there for 20 days |
| Units should lose loyalty without a commander and desert below 30, Fryhtans too | done: leaderless loyalty drifts to 0 (as in the original); below 30 a unit may desert; Fryhtans can go over to another Fryhtan kingdom |
| A unit changes colour when its commander is killed | the original's rule (Unit::die): his men nearby may go over to the killer |
| Fryhtan kingdoms never built their special structures | fixed: the computer found builders among humans only; now a Fryhtan of the brood builds |
| Towns paying tribute to Fryhtans showed no Fryhtan flag | fixed: they fly the Fryhtan flag in the lair kingdom's colour, as in the original |
