# Differences from the original

This edition follows the original Seven Kingdoms II source (`refsrc/7k2`)
rule for rule; where it knowingly departs, the change is listed here. Quirks
of the original that are kept on purpose are listed at the end.

## Additions (not in the original)

### Orders and automation
- **Inn recruiting policies.** An inn can be given standing orders
  (Auto-hire: soldiers / generals / both). Every 5 days, while 1000 gold stays
  in the treasury, it hires the guests that fit and sends them on:
  - *soldiers*: men whose leadership is at most half their combat (special
    units too) go to the nearest fort or camp with room;
  - *generals*: men who lead better than they fight (leadership 40 or more)
    go to command a camp without a commander or with a weaker one.
  Units of combat 100 or more are left to the player. The computer, besides
  the original's hiring of generals and spies, hires good soldiers (combat
  40-99) for its forts when its military
  budget allows.
- **Auto reward.** Soldiers and generals (selected units, all units with a
  right-click, or the men of a fort) can be rewarded automatically, 30 gold
  for +10 loyalty, whenever their loyalty falls below a chosen level.
- **Auto retreat for every unit.** The original's automatic retreat at a share
  of hit points (Unit::auto_retreat_hit_point) applies to generals only; here
  any fighting unit can be given it. It returns to its home fort, or the
  nearest fort or camp with room. The computer's generals retreat at 30% and
  its other fighting units at 20%.
- **Automatic levels.** Auto tax at loyalty 40/50/60, auto grant (gift) below
  30/40/50, auto reward below 30/40/50 and auto retreat at 10/20/30% of hit
  points (the original offers auto tax from 60, grants up to 70 and retreat
  from 10 to 90%).
- **A factory's stored goods.** As in the original a factory keeps a raw and a
  goods store for each product and switches product (by hand, or by itself
  when its material runs out). Here markets and caravans also take the goods
  of its other products, so a switch strands nothing; in the original they
  wait until the factory switches back.
- **Caravan routes.** With a caravan selected, Shift+right-click on the
  ground adds a point it passes between its two stops (in order from stop 1
  to stop 2, back the other way); the route is drawn while it is selected.
  The original's caravans go straight between their stops.
- **Settling by right-click.** Right-clicking one of your towns settles the
  selected people of its race in it; a group of units gets a Settle button.

### Interface
- **Start screen.** One Start button for every kind of game, on tabs; "Play
  as: a human kingdom / Fryhtans" chooses the side for a new game.
- **A new game starts paused.**
- **New towns** are previewed as a transparent town with its free band and the
  links it would get, like buildings.
- **Saved games.** "Save game" keeps every save (Ctrl+S is the quicksave); the
  load list shows them all, the newest first; F9 loads the newest.
- **Tax collection waits.** The player's Collect Tax button is unavailable
  until the last collection's penalty has worn off (10 days), so each
  collection takes exactly 10 loyalty (7 under the Norman Greater Being).
  In the original the button can be pressed again at once, taking more each
  time (up to 20).
- **Placement preview.** The building is shown transparent where it would
  stand, with the link lines it would get and the 2-cell free band around it.
- **Links.** A working link is drawn solid, one switched off dashed and dim
  with a cross; an inn's links (to other inns) are not drawn, as in the
  original.
- **Fryhtan, beast and machine portraits** are their own figures: the game's
  portraits for them (I_UNITLI.RES, by the unit table) are a different set of
  creatures - Kharshuf's is "M_SKELET", the Rhinokeros's "M_MAN".
- **Fort occupants** are shown by their sprites with a figure under each;
  Alt+1-4 picks combat, leadership, loyalty or hit points.
- **Town loyalty breakdown.** The town panel lists how its target loyalty is
  made up (base, reputation, quality of life, employment, race, each linked
  camp's general).
- **Squads.** A soldier's panel shows the general leading him and the damage
  bonus; a general's how many men he leads.
- **Scenario names** written all in capitals are shown in title case.
- **Interface details**: symbols on buttons with the words as tooltips; long
  figures are set smaller to fit.

### Other
- **The computer builds markets only for buyers, forts only for subjects**:
  a market only where a town of its own would be linked to it, a fort or camp
  only within reach of a town's people (the original builds a market beside
  every busy mine and factory, and may lay out a fort for a town that has
  since gone).
- **Generals are marked by a star** over their heads (gold for the king)
  instead of a flag.
- **Mega weapons are researched.** Finding a mega weapon's plans (the
  blueprint treasure) makes it researchable at a Tower of Science; in the
  original it cannot be researched at all and the plans give it outright.
- The player profiles' code for keeping heroes and items between games,
  which no menu of the original uses, is the start screen's "Bring the heroes
  and items of your profile" option.
- Network play uses Godot's ENet instead of DirectPlay; IPX and modem play
  are gone.
- Spies may pass for independents (as in the original), and so slip in among
  an inn's guests.

## Approximations
- A first king's leadership for the succession is taken when he dies rather
  than when he came to the throne (it only differs if it changed meanwhile).
- An inn's guests have no separate hit-point record from the unit type's; a
  wounded spy who joins the guests heals a point every 15 days as in the
  original.
- The fictional heroes (up to ten a nationality) get names from the
  nationality's name lists, drawn with a fixed seed as in the original, but
  not the original's exact names.

## Quirks of the original kept on purpose
- Outside the tutorials a computer kingdom's own tribute or aid demand
  (think_demand_tribute_aid) is never sent: the amount is simply added to its
  treasury.
- When a new king of another race is crowned, the old king's race *gains* 30
  loyalty (DIFFERENT_RACE_LOYALTY_DEC is added, not subtracted).
- HeroRes::think_generate_hero counts the human kingdoms but the last one.
- A bow can only be given to a new hero who has a ranged attack judged
  against his leadership level, which is 0 when the item is chosen.
- A fort's request for soldiers from elsewhere is dropped; the computer never
  builds a Fortress; `good_relation_duration_rating` is never raised.
- Construction may be cancelled and restarted by the computer as in the
  original (now refunding half the cost).
- A player's building is laid out and paid for when the builder reaches the
  place (Unit::execute_build_firm); the computer's are still laid out at once.
