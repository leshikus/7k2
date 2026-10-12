"""Builds the 36 human unit models (civilian, infantry, special unit x 12 races).

blender -b --factory-startup -P tools/blender/humans.py -- [CODE ...]

Every unit is KayKit body parts on the shared rig, recoloured with its race palette,
plus procedural headgear and weapons. Weapons the game swaps per action are kept as
separate meshes named W_<name>; scripts/models/unit_models.gd says which to show.
Mounted special units (cavalry, elephants, chariot) are built by mounts.py using
the riders defined here (RIDERS).
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Matrix, Euler
from common import *

HEAD_SCALE = 0.68
HEIGHT = {"CIV": 1.08, "INF": 1.2, "SPU": 1.25, "RIDER": 1.2, "GOD": 2.5}

# --------------------------------------------------------------- palettes ---

RACE_COLORS = {
    "NORMAN":   {"skin": "#e8b48e", "hair": "#7a5232", "metal": "#a3acb2", "cloth": "#8b7a5e", "cloth2": "#b8a88a", "cloth_dark": "#4e4438", "leather": "#7a4e32"},
    "VIKING":   {"skin": "#efc2a0", "hair": "#d8b060", "metal": "#9aa2a6", "cloth": "#6e6450", "cloth2": "#9a8a6a", "cloth_dark": "#3e4a52", "fur": "#8a7056", "horn": "#e0d4b4"},
    "CELTIC":   {"skin": "#f0c4a2", "hair": "#b0502a", "metal": "#b49a5a", "cloth": "#5a7a3e", "cloth2": "#d8d0b8", "cloth_dark": "#5a5040", "trim": "#e0b84e"},
    "ROMAN":    {"skin": "#ddaa84", "hair": "#3a2a1c", "metal": "#b8b0a0", "cloth": "#9a8c70", "cloth2": "#d8d0c0", "cloth_dark": "#5a4a3a", "leather": "#7a4a2a", "trim": "#e0b048"},
    "GREEK":    {"skin": "#dcaa86", "hair": "#2e2218", "metal": "#c8a050", "cloth": "#d8d0c0", "cloth2": "#e8e2d4", "cloth_dark": "#6a5a48", "trim": "#d8a040"},
    "CARTH":    {"skin": "#c89070", "hair": "#20160e", "metal": "#b09060", "cloth": "#c8b890", "cloth2": "#e0d0a0", "cloth_dark": "#5a4630", "trim": "#e8c050"},
    "CHINESE":  {"skin": "#e8c49a", "hair": "#141414", "metal": "#6e7a5a", "cloth": "#5a6e48", "cloth2": "#c8b888", "cloth_dark": "#3a3a30", "leather": "#6a5030", "trim": "#d8a840"},
    "JAPANESE": {"skin": "#ecc8a0", "hair": "#121212", "metal": "#2e2e34", "cloth": "#3a3a44", "cloth2": "#c8b890", "cloth_dark": "#24242a", "leather": "#4a3426", "trim": "#e0b040"},
    "MONGOL":   {"skin": "#d8a878", "hair": "#1a1410", "metal": "#8a8a80", "cloth": "#8a6a4a", "cloth2": "#b89a6a", "cloth_dark": "#4a3a2a", "fur": "#6a5040", "leather": "#6a4628"},
    "EGYPTIAN": {"skin": "#b07048", "hair": "#141010", "metal": "#d0a850", "cloth": "#e8e0c8", "cloth2": "#3a6aa8", "cloth_dark": "#c8b890", "trim": "#e8c050"},
    "PERSIAN":  {"skin": "#c8946c", "hair": "#1a120c", "metal": "#a8a090", "cloth": "#6a4a7a", "cloth2": "#d8c8a0", "cloth_dark": "#3a2e40", "trim": "#e0b848", "leather": "#7a5030"},
    "INDIAN":   {"skin": "#a8704c", "hair": "#141010", "metal": "#c0a868", "cloth": "#e8dcc0", "cloth2": "#e0a040", "cloth_dark": "#6a4a30", "trim": "#e8c050"},
}

# ----------------------------------------------------- procedural headgear ---
# Built around the (already shrunk) head: c = centre of the skull, r = its radius.

def _head_frame(rig):
    p = rig.bone_head("head")
    r = 0.36 * HEAD_SCALE / 0.65 * 0.95
    return p + Vector((0, 0.02, r * 1.02)), r


def hg_dome(rig, role="metal", k=1.2, cut=-0.15):
    c, r = _head_frame(rig)
    return colored(sphere("dome", r * k, 10, 6, at=c + Vector((0, 0.01, 0.02)), scale=(1.0, 1.05, 1.0), cut=cut), role)


def hg_cone(rig, role="metal", h=0.62, k=1.2, base=-0.15):
    c, r = _head_frame(rig)
    return colored(cone("cone", r * k, 0.01, r * h * 2, 8, at=c + Vector((0, 0, base * r + r * h))), role)


def hg_nasal(rig, role="metal"):
    c, r = _head_frame(rig)
    return colored(box("nasal", (0.06, 0.05, r * 0.8), at=c + Vector((0, -r * 1.2, -r * 0.2))), role)


def hg_crest(rig, role="team", along=True, h=0.35, l=1.6):
    c, r = _head_frame(rig)
    size = (0.06, r * l, r * h) if along else (r * l, 0.06, r * h)
    return colored(box("crest", size, at=c + Vector((0, 0.03, r * 1.1 + r * h * 0.4))), role)


def hg_horns(rig, role="horn"):
    c, r = _head_frame(rig)
    out = []
    for s in (-1, 1):
        h = cone("horn", r * 0.26, 0.01, r * 1.3, 6, at=c + Vector((s * r * 1.35, 0, r * 0.7)),
                 rot=(0, s * math.radians(-55), 0))
        out.append(colored(h, role))
    return out


def hg_cheeks(rig, role="metal"):
    c, r = _head_frame(rig)
    return [colored(box("cheek", (0.04, r * 0.6, r * 0.7), at=c + Vector((s * r * 0.98, -r * 0.35, -r * 0.55))), role) for s in (-1, 1)]


def hg_neckguard(rig, role="metal", flare=1.6):
    c, r = _head_frame(rig)
    return colored(cone("neckguard", r * flare, r * 1.0, r * 0.45, 10, at=c + Vector((0, 0.04, -r * 0.05))), role)


def hg_kuwagata(rig, role="trim"):
    c, r = _head_frame(rig)
    return [colored(box("kuwagata", (0.035, 0.03, r * 0.9), at=c + Vector((s * r * 0.35, -r * 1.0, r * 0.95)), rot=(0, s * math.radians(25), 0)), role) for s in (-1, 1)]


def hg_tassel(rig, role="team"):
    c, r = _head_frame(rig)
    return [colored(cone("spike", 0.03, 0.005, r * 0.6, 6, at=c + Vector((0, 0, r * 1.35))), "metal"),
            colored(sphere("tassel", r * 0.2, 6, 4, at=c + Vector((0, 0, r * 1.15)), scale=(1, 1, 0.6)), role)]


def hg_fur_cap(rig, cap_role="cloth", fur_role="fur"):
    c, r = _head_frame(rig)
    return [colored(cone("cap", r * 1.0, r * 0.25, r * 1.3, 8, at=c + Vector((0, 0, r * 0.75))), cap_role),
            colored(torus("furrim", r * 1.02, r * 0.2, 10, 5, at=c + Vector((0, 0, r * 0.2))), fur_role)]


def hg_turban(rig, role="linen", top="team"):
    c, r = _head_frame(rig)
    return [colored(torus("turban1", r * 0.92, r * 0.25, 10, 5, at=c + Vector((0, 0, r * 0.35))), role),
            colored(torus("turban2", r * 0.75, r * 0.25, 10, 5, at=c + Vector((0, 0, r * 0.75))), role),
            colored(sphere("turbantop", r * 0.55, 8, 4, at=c + Vector((0, 0, r * 0.9)), scale=(1, 1, 0.8)), top)]


def hg_nemes(rig, role="team", stripe="trim"):
    c, r = _head_frame(rig)
    out = [colored(sphere("nemes", r * 1.1, 10, 6, at=c + Vector((0, 0.03, 0.02)), scale=(1.05, 1.05, 0.95), cut=-0.1), role)]
    for s in (-1, 1):
        out.append(colored(box("lappet", (r * 0.4, r * 0.3, r * 1.2), at=c + Vector((s * r * 0.85, -r * 0.2, -r * 0.9))), stripe))
    out.append(colored(box("nemestail", (r * 0.8, r * 0.3, r * 1.2), at=c + Vector((0, r * 0.9, -r * 0.8))), role))
    return out


def hg_straw_hat(rig, role="cloth2"):
    c, r = _head_frame(rig)
    return colored(cone("strawhat", r * 2.0, 0.02, r * 0.75, 12, at=c + Vector((0, 0, r * 0.9))), role)


def hg_phrygian(rig, role="cloth2"):
    c, r = _head_frame(rig)
    return [colored(sphere("cap", r * 1.08, 10, 6, at=c + Vector((0, 0.01, 0.03)), scale=(1, 1.05, 1.1), cut=-0.15), role),
            colored(cone("captip", r * 0.5, 0.02, r * 0.9, 8, at=c + Vector((0, -r * 0.45, r * 1.15)), rot=(math.radians(-50), 0, 0)), role)]


def hg_hood(rig, role="cloth"):
    c, r = _head_frame(rig)
    return colored(sphere("hood", r * 1.22, 10, 6, at=c + Vector((0, 0.05, 0.0)), scale=(1.0, 1.1, 1.08), cut=-0.45), role)


def hg_headband(rig, role="team"):
    c, r = _head_frame(rig)
    return colored(torus("band", r * 0.98, r * 0.09, 12, 4, at=c + Vector((0, 0, r * 0.35))), role)


def hg_mask(rig, role="black"):
    c, r = _head_frame(rig)
    return colored(sphere("mask", r * 1.06, 10, 6, at=c + Vector((0, -0.02, -r * 0.1)), scale=(1.0, 1.0, 0.8), cut=-0.6), role)


def hg_hair(rig, role="hair", long=False):
    c, r = _head_frame(rig)
    out = [colored(sphere("hair", r * 1.06, 10, 6, at=c + Vector((0, 0.04, 0.03)), scale=(1.0, 1.05, 1.0), cut=-0.05), role)]
    if long:
        out.append(colored(box("ponytail", (r * 0.9, r * 0.35, r * 1.2), at=c + Vector((0, r * 0.95, -r * 0.6))), role))
    return out


HEADGEAR = {
    "norman_helm": lambda g: [hg_dome(g, "metal", 1.2, -0.1), hg_cone(g, h=0.75, k=1.16, base=0.05), hg_nasal(g)],
    "viking_helm": lambda g: [hg_dome(g), hg_nasal(g)] + hg_horns(g),
    "roman_galea": lambda g: [hg_dome(g, "metal"), hg_crest(g, "team", along=False, l=1.5), hg_neckguard(g, "metal", 1.3)] + hg_cheeks(g),
    "greek_helm": lambda g: [hg_dome(g, "metal", 1.1, -0.45), hg_crest(g, "team", along=True, h=0.5, l=2.0), hg_nasal(g, "metal")] + hg_cheeks(g, "metal"),
    "carth_helm": lambda g: [hg_dome(g, "metal"), hg_cone(g, "metal", 0.4, 0.4, 0.9), hg_crest(g, "trim", along=True, h=0.25, l=1.2)],
    "chinese_helm": lambda g: [hg_dome(g, "metal_dark"), hg_neckguard(g, "leather", 1.25)] + hg_tassel(g),
    "kabuto": lambda g: [hg_dome(g, "metal", 1.1), hg_neckguard(g, "metal", 1.75)] + hg_kuwagata(g),
    "mongol_cap": lambda g: hg_fur_cap(g, "team", "fur"),
    "mongol_helm": lambda g: [hg_cone(g, "metal", 0.75, 1.06), hg_neckguard(g, "fur", 1.2)],
    "nemes": lambda g: hg_nemes(g, "team", "trim"),
    "linen_nemes": lambda g: hg_nemes(g, "linen", "cloth2"),
    "persian_cap": lambda g: hg_phrygian(g, "team"),
    "persian_civ": lambda g: hg_phrygian(g, "cloth2"),
    "turban": lambda g: hg_turban(g, "linen", "team"),
    "turban_civ": lambda g: hg_turban(g, "cloth2", "cloth2"),
    "straw_hat": lambda g: [hg_straw_hat(g)],
    "celt_band": lambda g: [hg_headband(g, "trim")] + hg_hair(g, long=True),
    "hair": lambda g: hg_hair(g),
    "long_hair": lambda g: hg_hair(g, long=True),
    "hood": lambda g: [hg_hood(g, "team")],
    "druid_hood": lambda g: [hg_hood(g, "linen")],
    "ninja": lambda g: [hg_hood(g, "black"), hg_headband(g, "team")],
    "monk": lambda g: [],
    "fur_hood": lambda g: [hg_hood(g, "fur")],
    "none": lambda g: [],
}

# --------------------------------------------------------- weapons, shields ---
# Built in the hand-slot frame (+y along the weapon, grip at the origin, +z up in
# the T-pose), then moved onto the bone.

def wp_spear(length=2.2, tip=0.22, grip=0.35):
    shaft = colored(cone("shaft", 0.035, 0.03, length, 6, at=(0, length / 2 - length * grip, 0), rot=(math.radians(-90), 0, 0)), "wood")
    head = colored(cone("tip", 0.07, 0.0, tip, 6, at=(0, length * (1 - grip) + tip / 2, 0), rot=(math.radians(-90), 0, 0)), "metal")
    return join("spear", [shaft, head])


def wp_javelin():
    return wp_spear(1.5, 0.16, 0.45)


def wp_blade(length=0.95, width=0.12, guard=0.32, curve=0.0, role="metal"):
    parts = [colored(box("grip", (0.06, 0.25, 0.06), at=(0, -0.05, 0)), "leather_dark"),
             colored(box("guard", (guard, 0.05, 0.07), at=(0, 0.1, 0)), "trim")]
    n = 4
    for i in range(n):
        y0 = 0.12 + length * i / n
        x = curve * (i / n) ** 2
        w = width * (1.0 - 0.45 * i / n)
        parts.append(colored(box("blade", (w, length / n + 0.02, 0.03), at=(x, y0 + length / n / 2, 0), rot=(0, 0, -curve * 1.6 * i / n)), role, 0.8))
    return join("blade", parts)


def wp_bow():
    # an arc in the slot's x-y plane, held in the middle
    arc = torus("bow", 0.8, 0.035, 10, 4, rot=(0, 0, math.radians(90 - 50)), arc=100 / 360)
    arc.location = (-0.62, 0, 0)
    colored(arc, "wood")
    string = colored(box("string", (0.01, 1.22, 0.01), at=(-0.62 + 0.8 * math.cos(math.radians(50)), 0, 0)), "linen")
    return join("bow", [arc, string])


def wp_tool(kind="hammer"):
    handle = colored(cone("handle", 0.03, 0.03, 0.75, 6, at=(0, 0.25, 0), rot=(math.radians(-90), 0, 0)), "wood")
    if kind == "hammer":
        head = colored(box("head", (0.12, 0.12, 0.26), at=(0, 0.6, 0)), "metal_dark")
    else:  # pick
        head = colored(cone("head", 0.05, 0.0, 0.5, 4, at=(0, 0.6, 0), rot=(0, math.radians(90), 0)), "metal_dark")
    return join(kind, [handle, head])


def wp_club():
    return colored(cone("club", 0.05, 0.1, 0.8, 6, at=(0, 0.35, 0), rot=(math.radians(-90), 0, 0)), "wood")


def wp_shuriken():
    s = box("shuriken", (0.18, 0.18, 0.02), rot=(0, 0, math.radians(45)))
    t = box("shuriken2", (0.18, 0.18, 0.02))
    return join("shuriken", [colored(s, "metal"), colored(t, "metal")])


def sh_round(radius=0.45, face="team", rim="metal", boss="metal"):
    disc = colored(cone("shield", radius, radius, 0.06, 12, at=(0, 0, 0.12)), face)
    r = colored(torus("rim", radius, 0.03, 12, 4, at=(0, 0, 0.15)), rim)
    b = colored(sphere("boss", radius * 0.25, 8, 4, at=(0, 0, 0.16), cut=0.0), boss)
    return join("shield", [disc, r, b])


def sh_rect(w=0.62, h=1.0, face="team", rim="trim", curved=True):
    parts = []
    n = 3 if curved else 1
    for i in range(n):
        x = (i - (n - 1) / 2) * w / n
        z = 0.12 + (0.06 if curved and i != (n - 1) / 2 else 0)
        parts.append(colored(box("panel", (w / n + 0.01, h, 0.05), at=(x, 0, z), rot=(0, (x / w) * -0.9 if curved else 0, 0)), face))
    parts.append(colored(sphere("boss", 0.09, 8, 4, at=(0, 0, 0.16), cut=0.0), rim))
    return join("shield", parts)


def sh_kite(face="team"):
    top = colored(box("kite", (0.55, 0.6, 0.05), at=(0, 0.15, 0.12)), face)
    bottom = colored(cone("kitetip", 0.39, 0.0, 0.55, 4, at=(0, -0.42, 0.12), rot=(math.radians(90), math.radians(45), 0), scale=(1, 1, 1)), face)
    bottom.scale = (1.0, 0.2, 1.0)
    return join("shield", [top, bottom])


def sh_oval(face="trim", rim="team"):
    s = colored(sphere("oval", 0.5, 10, 5, at=(0, 0, 0.1), scale=(0.75, 1.15, 0.12)), face)
    r = colored(box("spine", (0.06, 1.0, 0.05), at=(0, 0, 0.16)), rim)
    return join("shield", [s, r])


def kk(char, part, roles=None):
    """A KayKit prop to borrow onto the rig: (character, object name, role overrides)."""
    return ("kaykit", char, part, roles or {})


WEAPONS = {
    "sword": kk("Knight", "1H_Sword"),
    "gladius": ("proc", lambda: wp_blade(0.7, 0.13, 0.22)),
    "longsword": ("proc", lambda: wp_blade(1.05, 0.11, 0.36)),
    "sabre": ("proc", lambda: wp_blade(1.0, 0.1, 0.22, curve=0.12)),
    "khopesh": ("proc", lambda: wp_blade(0.8, 0.13, 0.15, curve=0.3, role="trim")),
    "katana": ("proc", lambda: wp_blade(1.15, 0.07, 0.12, curve=0.07)),
    "axe": kk("Barbarian", "1H_Axe"),
    "greataxe": kk("Barbarian", "2H_Axe"),
    "spear": ("proc", lambda: wp_spear()),
    "javelin": ("proc", lambda: wp_javelin()),
    "bow": ("proc", wp_bow),
    "crossbow": kk("Rogue", "2H_Crossbow"),
    "staff": kk("Mage", "2H_Staff", {"glow": "team"}),
    "knife": kk("Rogue", "Knife"),
    "shuriken": ("proc", wp_shuriken),
    "hammer": ("proc", lambda: wp_tool("hammer")),
    "pick": ("proc", lambda: wp_tool("pick")),
    "club": ("proc", wp_club),
    "sh_round": ("proc", lambda: sh_round()),
    "sh_round_wood": ("proc", lambda: sh_round(0.42, "team", "wood", "metal_dark")),
    "sh_hoplon": ("proc", lambda: sh_round(0.6, "team", "trim", "trim")),
    "sh_small": ("proc", lambda: sh_round(0.3, "team", "trim", "trim")),
    "sh_scutum": ("proc", lambda: sh_rect(0.66, 1.15, "team", "trim")),
    "sh_wicker": ("proc", lambda: sh_rect(0.55, 0.95, "cloth2", "team", curved=False)),
    "sh_kite": ("proc", lambda: sh_kite()),
    "sh_oval": ("proc", lambda: sh_oval("trim", "team")),
    "sh_badge": kk("Knight", "Badge_Shield", {"metal": "team"}),
}
LEFT_HAND = {"bow"}             # held in the left hand (shields always are)

# ------------------------------------------------------------------ bodies ---

BODIES = {
    # name: (KayKit character, part names, per-part role overrides)
    "armor": ("Knight", ["Knight_Body", "Knight_ArmLeft", "Knight_ArmRight", "Knight_LegLeft", "Knight_LegRight"]),
    "bare": ("Barbarian", ["Barbarian_Body", "Barbarian_ArmLeft", "Barbarian_ArmRight", "Barbarian_LegLeft", "Barbarian_LegRight"]),
    "robe": ("Mage", ["Mage_Body", "Mage_ArmLeft", "Mage_ArmRight", "Mage_LegLeft", "Mage_LegRight"]),
    "tunic": ("Rogue", ["Rogue_Body", "Rogue_ArmLeft", "Rogue_ArmRight", "Rogue_LegLeft", "Rogue_LegRight"]),
}
HEADS = {"plain": ("Knight", "Knight_Head"), "beard": ("Barbarian", "Barbarian_Head"),
         "rogue": ("Rogue", "Rogue_Head"), "mage": ("Mage", "Mage_Head")}
CAPES = {"knight": ("Knight", "Knight_Cape"), "rogue": ("Rogue", "Rogue_Cape"), "mage": ("Mage", "Mage_Cape")}

# ------------------------------------------------------------------- units ---
# body, head, headgear, cape, weapons {slot name: weapon}, roles (role -> role for
# the whole unit), kind (CIV/INF/SPU).

UNITS = {
    # Normans: mail, nasal helm, kite shield; crossbow for the ranged attack
    "NO_CIV": dict(race="NORMAN", body="tunic", head="plain", gear="hood", w={"Tool": "hammer"}, roles={"cloth": "team", "cloth2": "cloth"}),
    "NO_INF": dict(race="NORMAN", body="armor", head="plain", gear="norman_helm", cape="knight", w={"Sword": "sword", "Shield": "sh_kite", "Bow": "crossbow"}),
    # Vikings: horned helm, axe and round shield; axe-throwers with a cape
    "VI_CIV": dict(race="VIKING", body="bare", head="beard", gear="long_hair", w={"Tool": "axe"}, roles={"cloth": "team"}),
    "VI_INF": dict(race="VIKING", body="armor", head="beard", gear="viking_helm", cape="knight", w={"Axe": "axe", "Shield": "sh_round_wood", "Axe2": "greataxe"}),
    "VI_SPU": dict(race="VIKING", body="bare", head="beard", gear="viking_helm", cape="knight", w={"Axe": "axe", "Axe2": "greataxe", "Throw": "axe"}, roles={"cloth": "team"}),
    # Celts: no helmets, oval shields; the Deruvid druid in a white robe
    "CE_CIV": dict(race="CELTIC", body="tunic", head="beard", gear="long_hair", w={"Tool": "pick"}, roles={"cloth": "team"}),
    "CE_INF": dict(race="CELTIC", body="bare", head="beard", gear="celt_band", w={"Sword": "longsword", "Shield": "sh_oval"}, roles={"cloth": "team"}),
    "CE_SPU": dict(race="CELTIC", body="robe", head="beard", gear="druid_hood", cape="mage", w={"Staff": "staff"}, roles={"cloth": "linen", "cloth_dark": "team"}),
    # Romans: galea with a transverse crest, scutum, gladius
    "RO_CIV": dict(race="ROMAN", body="tunic", head="plain", gear="none", w={"Tool": "hammer"}, roles={"cloth": "team", "cloth2": "linen"}),
    "RO_INF": dict(race="ROMAN", body="armor", head="plain", gear="roman_galea", w={"Sword": "gladius", "Shield": "sh_scutum"}, roles={"metal": "team", "leather_dark": "metal"}),
    # Greeks: crested helm, hoplon, spear
    "GR_CIV": dict(race="GREEK", body="robe", head="beard", gear="hair", w={"Tool": "club"}, roles={"cloth": "linen", "cloth_dark": "team"}),
    "GR_INF": dict(race="GREEK", body="armor", head="beard", gear="greek_helm", w={"Spear": "spear", "Shield": "sh_hoplon"}, roles={"metal": "team", "leather_dark": "metal"}),
    # Carthaginians: tall oval shields, bow
    "CT_CIV": dict(race="CARTH", body="robe", head="beard", gear="hair", w={"Tool": "hammer"}, roles={"cloth": "team"}),
    "CT_INF": dict(race="CARTH", body="armor", head="beard", gear="carth_helm", w={"Sword": "sword", "Shield": "sh_oval", "Bow": "bow"}, roles={"metal": "team", "leather_dark": "metal"}),
    # Chinese: lamellar, crossbows; the monk fights bare-handed
    "CH_CIV": dict(race="CHINESE", body="tunic", head="plain", gear="straw_hat", w={"Tool": "hammer"}, roles={"cloth": "team"}),
    "CH_INF": dict(race="CHINESE", body="armor", head="plain", gear="chinese_helm", w={"Sword": "sabre", "Bow": "crossbow"}, roles={"metal": "metal_dark", "cloth_dark": "team"}),
    "CH_SPU": dict(race="CHINESE", body="bare", head="plain", gear="monk", w={}, roles={"cloth": "skin", "cloth_dark": "team", "fur": "team"}),
    # Japanese: kabuto and katana; the ninja in black with shuriken
    "JA_CIV": dict(race="JAPANESE", body="tunic", head="plain", gear="straw_hat", w={"Tool": "pick"}, roles={"cloth": "team"}),
    "JA_INF": dict(race="JAPANESE", body="armor", head="plain", gear="kabuto", w={"Sword": "katana", "Spear": "spear"}, roles={"cloth_dark": "team"}),
    "JA_SPU": dict(race="JAPANESE", body="tunic", head="rogue", gear="ninja", w={"Sword": "katana", "Knife": "knife", "Throw": "shuriken"}, roles={"cloth": "black", "cloth2": "team", "cloth_dark": "black", "leather": "black"}),
    # Mongols: fur caps, sabres
    "MO_CIV": dict(race="MONGOL", body="tunic", head="plain", gear="mongol_cap", w={"Tool": "club"}, roles={"cloth": "team"}),
    "MO_INF": dict(race="MONGOL", body="tunic", head="beard", gear="mongol_helm", w={"Sword": "sabre", "Sword2": "axe"}, roles={"cloth": "team", "cloth2": "fur"}),
    # Egyptians: nemes, khopesh, bow
    "EG_CIV": dict(race="EGYPTIAN", body="bare", head="plain", gear="linen_nemes", w={"Tool": "hammer"}, roles={"cloth": "skin", "cloth_dark": "team", "fur": "linen"}),
    "EG_INF": dict(race="EGYPTIAN", body="bare", head="plain", gear="nemes", w={"Sword": "khopesh", "Shield": "sh_small", "Bow": "bow"}, roles={"cloth": "skin", "cloth_dark": "team", "fur": "trim"}),
    # Persians: soft caps, wicker shields, spears and bows
    "PE_CIV": dict(race="PERSIAN", body="robe", head="beard", gear="persian_civ", w={"Tool": "club"}, roles={"cloth": "team"}),
    "PE_INF": dict(race="PERSIAN", body="tunic", head="beard", gear="persian_cap", w={"Spear": "spear", "Shield": "sh_wicker", "Bow": "bow"}, roles={"cloth": "team", "cloth2": "trim"}),
    # Indians: turbans, talwar and bow
    "IN_CIV": dict(race="INDIAN", body="bare", head="beard", gear="turban_civ", w={"Tool": "pick"}, roles={"cloth": "skin", "cloth_dark": "team", "fur": "linen"}),
    "IN_INF": dict(race="INDIAN", body="bare", head="beard", gear="turban", w={"Sword": "sabre", "Shield": "sh_small", "Bow": "bow"}, roles={"cloth": "skin", "cloth_dark": "team", "fur": "trim"}),
}

# Riders of mounted special units (mounts.py seats them).
RIDERS = {
    "NO_SPU": dict(race="NORMAN", body="armor", head="plain", gear="norman_helm", cape="knight", w={"Sword": "longsword", "Shield": "sh_kite"}),
    "RO_SPU": dict(race="ROMAN", body="armor", head="plain", gear="roman_galea", cape="knight", w={"Sword": "gladius", "Spear": "javelin", "Throw": "javelin"}),
    "GR_SPU": dict(race="GREEK", body="armor", head="beard", gear="greek_helm", cape="knight", w={"Spear": "spear", "Shield": "sh_round"}),
    "CT_SPU": dict(race="CARTH", body="tunic", head="beard", gear="carth_helm", w={"Spear": "spear"}, roles={"cloth": "team"}),
    "MO_SPU": dict(race="MONGOL", body="tunic", head="beard", gear="mongol_helm", w={"Sword": "sabre", "Bow": "bow", "Throw": "javelin"}, roles={"cloth": "team", "cloth2": "fur"}),
    "EG_SPU": dict(race="EGYPTIAN", body="bare", head="plain", gear="nemes", w={"Spear": "spear", "Throw": "javelin"}, roles={"cloth": "skin", "cloth_dark": "team", "fur": "trim"}),
    "PE_SPU": dict(race="PERSIAN", body="armor", head="beard", gear="persian_cap", cape="knight", w={"Sword": "sabre", "Throw": "javelin"}),
    "IN_SPU": dict(race="INDIAN", body="bare", head="beard", gear="turban", w={"Spear": "spear", "Throw": "javelin"}, roles={"cloth": "skin", "cloth_dark": "team", "fur": "trim"}),
}


def _weapon(rig, slot_name, kind, mat):
    spec = WEAPONS[kind]
    left = kind.startswith("sh_") or kind in LEFT_HAND
    bone = "handslot.l" if left else "handslot.r"
    if spec[0] == "kaykit":
        _, char, part, roles = spec
        rig.borrow(char, [part])
        o = rig.parts.pop(part)
        remap_to_palette(o, mat, roles)
        if o.parent_bone != bone:
            m = rig.bone_matrix(bone) @ (rig.bone_matrix(o.parent_bone).inverted() @ o.matrix_world)
            o.parent_bone = bone
            o.matrix_world = m
    else:
        o = spec[1]()
        bpy.context.view_layer.update()
        o.data.materials.clear()
        o.data.materials.append(mat)
        if left and not kind.startswith("sh_"):
            o.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ o.matrix_world
        o.matrix_world = rig.bone_matrix(bone) @ o.matrix_world
        rig.attach(o, bone, "W_" + slot_name)
    # KayKit props are sized for chibi characters; shrink them about the grip
    k = 0.72 if spec[0] == "kaykit" else 0.88
    if kind.startswith("sh_"):
        k = 0.85 if spec[0] == "kaykit" else 0.95
    bpy.context.view_layer.update()
    pivot = rig.bone_head(bone)
    o.matrix_world = Matrix.Translation(pivot) @ Matrix.Scale(k, 4) @ Matrix.Translation(-pivot) @ o.matrix_world
    o.name = "W_" + slot_name
    o["procedural"] = True
    rig.parts["W_" + slot_name] = o
    return o


def build_character(code, u, kind):
    reset()
    char, parts = BODIES[u["body"]]
    rig = Rig(char)
    keep = list(parts)
    rig.keep_only(keep)
    hchar, hpart = HEADS[u.get("head", "plain")]
    rig.borrow(hchar, [hpart])
    if u.get("cape"):
        cchar, cpart = CAPES[u["cape"]]
        rig.borrow(cchar, [cpart])
    rig.scale_head(HEAD_SCALE)
    pal = make_palette("pal_" + u["race"], RACE_COLORS[u["race"]])
    mat = palette_material(pal)
    roles = dict(u.get("roles", {}))
    cape_roles = {r: "team" for r in ("cloth", "cloth2", "linen", "team", "leather_dark")}
    rig.to_palette(mat, roles, {"Knight_Cape": cape_roles, "Rogue_Cape": cape_roles, "Mage_Cape": cape_roles})
    for g in HEADGEAR[u.get("gear", "none")](rig):
        g.data.materials.clear()
        g.data.materials.append(mat)
        rig.attach(g, "head")
    bpy.context.view_layer.update()
    for o, bone in u.get("extras", lambda g: [])(rig):
        o.data.materials.clear()
        o.data.materials.append(mat)
        rig.attach(o, bone, "x%d" % len(rig.parts))
    weapons = []
    for slot, w in u.get("w", {}).items():
        weapons.append(_weapon(rig, slot, w, mat).name)
    rig.bake_rigid()
    rig.join_body(keep_separate=tuple(weapons))
    s = HEIGHT[kind] / rig.height()
    rig.arm.scale = (s, s, s)
    return rig


# ------------------------------------------------------------ Greater Beings ---

def wings(rig, role="white", span=1.0, bat=False):
    c = rig.bone_head("chest") + Vector((0, 0.25, 0.2))
    out = []
    for s in (-1, 1):
        for i in range(3):
            o = sphere("feather", 0.5 * span * (1 - 0.18 * i), 8, 4, at=c + Vector((s * (0.45 + 0.3 * i) * span, 0.12, 0.25 - 0.2 * i)),
                       scale=(1.0, 0.08, 0.45 if not bat else 0.6))
            o.rotation_euler = (0, s * math.radians(-25 - 12 * i), 0)
            out.append((colored(o, role if i < 2 else "linen"), "chest"))
    return out


def halo(rig, role="glow", r=0.42, disc=False):
    c, rr = _head_frame(rig)
    if disc:
        o = cone("sundisc", r * 1.5, r * 1.5, 0.04, 16, at=c + Vector((0, rr * 1.1, rr * 0.3)), rot=(math.radians(90), 0, 0))
    else:
        o = torus("halo", r, 0.04, 14, 4, at=c + Vector((0, 0, rr * 1.6)))
    return [(colored(o, role), "head")]


def monkey(rig):
    import fryhtans
    return fryhtans.tail(rig, "fur", 1.1, 0.07, 5, -0.4) + fryhtans.snout(rig, "skin", 0.18, 0.3, -0.1)


GOD_COLORS = {"glow": "#fff4a0", "white": "#f4f2ea", "trim": "#f0c040"}

GODS = {
    "NO_GOD": dict(race="NORMAN", body="armor", head="plain", gear="none", cape="knight", w={"Sword": "longsword"}, extras=lambda g: wings(g) + halo(g), roles={"metal": "white"}),
    "VI_GOD": dict(race="VIKING", body="armor", head="beard", gear="viking_helm", cape="knight", w={"Hammer": "hammer"}, extras=lambda g: []),
    "CE_GOD": dict(race="CELTIC", body="robe", head="beard", gear="druid_hood", cape="mage", w={"Staff": "staff"}, extras=lambda g: halo(g, "plant", 0.5), roles={"cloth": "plant", "cloth_dark": "linen"}),
    "RO_GOD": dict(race="ROMAN", body="armor", head="plain", gear="roman_galea", cape="knight", w={"Spear": "spear", "Shield": "sh_round"}, extras=lambda g: [], roles={"metal": "trim"}),
    "GR_GOD": dict(race="GREEK", body="robe", head="plain", gear="greek_helm", w={"Spear": "spear", "Shield": "sh_hoplon"}, extras=lambda g: [], roles={"cloth": "white", "cloth_dark": "trim"}),
    "CA_GOD": dict(race="CARTH", body="robe", head="beard", gear="none", cape="mage", w={"Staff": "staff"}, extras=lambda g: _gtail(g), roles={"cloth": "flesh"}),
    "JA_GOD": dict(race="JAPANESE", body="robe", head="plain", gear="none", w={}, extras=lambda g: halo(g, "glow", 0.6, disc=True), roles={"cloth": "white", "cloth_dark": "team"}),
    "MO_GOD": dict(race="MONGOL", body="robe", head="beard", gear="mongol_cap", cape="mage", w={"Bow": "bow"}, extras=lambda g: wings(g, "cloth2", 1.2), roles={"cloth": "metal"}),
    "EG_GOD": dict(race="EGYPTIAN", body="robe", head="plain", gear="nemes", w={}, extras=lambda g: wings(g, "trim", 1.3), roles={"cloth": "white", "cloth_dark": "cloth2"}),
    "PE_GOD": dict(race="PERSIAN", body="robe", head="beard", gear="persian_cap", w={"Sword": "sabre"}, extras=lambda g: halo(g, "glow", 0.6, disc=True), roles={"cloth": "trim"}),
    "IN_GOD": dict(race="INDIAN", body="bare", head="beard", gear="none", w={"Club": "club"}, extras=lambda g: monkey(g), roles={"cloth": "skin", "cloth_dark": "team", "skin": "fur"}),
}


def _gtail(g):
    import fryhtans
    return fryhtans.horns(g, "horn", 1.4, 0.7, 1.0)


def build_gods(codes=()):
    for code, u in GODS.items():
        if codes and code not in codes:
            continue
        RACE_COLORS[u["race"] + "_GOD"] = dict(RACE_COLORS[u["race"]], **GOD_COLORS)
        u = dict(u, race=u["race"] + "_GOD")
        rig = build_character(code, u, "GOD")
        export_unit(code, rig, "gods")


def export_unit(code, rig, sub="units"):
    path = os.path.join(OUT, sub, code + ".glb")
    export_glb(path, [rig.arm] + list(rig.parts.values()))
    print("BUILT", code, path)


def main(codes):
    for code, u in UNITS.items():
        if codes and code not in codes:
            continue
        rig = build_character(code, u, code[3:])
        export_unit(code, rig)
    if not codes or any(c.endswith("_GOD") for c in codes):
        build_gods([c for c in codes if c.endswith("_GOD")])


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    main(args)
