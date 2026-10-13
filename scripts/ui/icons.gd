class_name Icons
extends RefCounted
## Buttons show a picture instead of words: a Unicode symbol (rendered with the
## system's symbol and emoji fonts) chosen from the button's label. The label
## itself becomes the button's tooltip; numbers in it (costs, chances) stay on
## the button beside the symbol.

## [substring, icon], first match wins (case-insensitive); verbs before names.
const RULES := [
	# selection, toggles
	["Mobilize all", "⇶"], ["Mobilize ", "🚶"], ["Cancel", "✖"], ["Stop converting", "⏹"], ["Stop", "⏹"],
	["No formation", "⁘"], ["Formation: Vanguard", "⏶"], ["Formation: Line", "☰"], ["Formation: Circle", "◯"],
	["Formation: Arc", "◠"], ["Formation: Staggered", "⁙"], ["Formation: Square", "▦"], ["Formation: Sandwich", "≣"],
	# building and towns
	["Build...", "🔨"], ["Build a town", "🏘"], ["wall", "🧱"], ["Demolish", "💥"], ["Eject all", "⏏"],
	["Fill from towns", "👥"], ["Send out wagon", "🛒"], ["Send out", "⚔"], ["Collect tax", "💰"], ["Grant gold", "🎁"],
	["Recruit peasant", "🚶"], ["Settle in town", "🏠"], ["Rally point", "🚩"], ["Set destination", "🚩"],
	["Hire caravan", "🐪"], ["Clone caravan", "🐫"], ["Return", "↩"],
	# ranks and items
	["Promote", "★"], ["Demote", "☆"], ["Drop item", "⬇"], ["Activate ", "✨"], ["Use ", "✋"], ["Detonate", "💣"],
	# gods
	["Invoke Greater Being", "⛩"], ["Cast power", "⚡"], ["Special Blessing", "🌟"],
	# spies
	["Train ", "🎓"], ["Disguise", "🎭"], ["Camouflage", "🌿"], ["Mission:", "🗣"], ["Recall spy", "↩"],
	["Secret report", "📜"], ["Bribe", "🤝"], ["Offer ", "💵"], ["Assassinate", "🗡"], ["Steal tech", "🔓"],
	["Incident", "🔥"], ["Capture", "🏴"],
	# Fryhtans
	["Take over", "🏴"], ["Lair", "🕳"], ["Fortress", "🏯"], ["Send out brood", "⚔"], ["Breed ", "🥚"], ["Grow ", "🥚"],
	["Learn ", "📖"], ["Hire ", "🍺"],
	# buildings (the build menu)
	["War Factory", "⚙"], ["Tower of Science", "🔬"], ["Espionage College", "🕵"], ["Seat of Power", "⛩"],
	["Fort", "🏰"], ["Camp", "⛺"], ["Mine", "⛏"], ["Factory", "🏭"], ["Market", "🏪"], ["Inn", "🍺"],
	["Training", "🐎"], ["Stable", "🐎"], ["Estable", "🐎"],
	# research and war machines
	["Mining", "⛏"], ["Manufactur", "🏭"], ["Farming", "🌾"], ["Production", "⚙"], ["Close Combat", "⚔"],
	["Range Attack", "🏹"], ["Defense", "🛡"], ["Catapult", "☄"], ["Ballista", "🏹"], ["SpitFire", "🔥"],
	["Cannon", "💣"], ["Unicorn", "🦄"], ["Explosive", "💣"], ["Spy", "🕵"], ["Tech", "🔬"],
	# alchemy and spells
	["Gold", "🪙"], ["Fire", "🔥"], ["Lightning", "⚡"], ["Freeze", "❄"], ["Heal", "✚"], ["Teleport", "🌀"],
]

const MARKS := ["✓", "▶", "☑", "☐", "▾"]


static func for_label(text: String) -> String:
	var low := text.to_lower()
	for r in RULES:
		if low.contains(String(r[0]).to_lower()):
			return r[1]
	# anything else: its initial in a circle (Ⓐ..Ⓩ)
	var body := _strip_marks(text).replace("★", "").strip_edges()
	if body != "":
		var c := body.unicode_at(0)
		if c >= 97 and c <= 122:
			c -= 32
		if c >= 65 and c <= 90:
			return String.chr(0x24B6 + c - 65)
	return "•"


## What the button shows: marks it had (✓ ▶ ☐ ☑), the symbol and the numbers.
static func caption(text: String, icon := "") -> String:
	var out := ""
	for m in ["▶", "☑", "☐"]:
		if text.begins_with(m):
			out += m + " "
	out += icon if icon != "" else for_label(text)
	var nums := _numbers(text)
	if nums != "":
		out += " " + nums
	if text.contains("✓"):
		out += " ✓"
	return out


## The figures of a label: "(300)", "(80 gold, 20 life)" -> "300", "80/20";
## "Assassinate: 45%" -> "45%".
static func _numbers(text: String) -> String:
	var rx := RegEx.new()
	rx.compile("\\d+%?")
	var parts: Array = []
	for m in rx.search_all(text):
		parts.append(m.get_string())
	return "/".join(parts.slice(0, 2))


static func _strip_marks(text: String) -> String:
	var s := text
	for m in MARKS:
		s = s.replace(m, "")
	return s
