"""CC0 source packs used to build the models, and where to find them.

`python tools/blender/sources.py fetch` downloads them into the source cache
(SK2_ASSET_SRC, default ../sk2assets/src next to the repo). Only the built .glb
files are committed; the packs themselves stay outside the repository.
"""
import os, sys, subprocess, urllib.request, urllib.parse, zipfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.environ.get("SK2_ASSET_SRC", os.path.join(os.path.dirname(REPO), "sk2assets", "src"))

KAYKIT = {  # GitHub repositories of Kay Lousberg, all CC0
    "kaykit_adventurers": "KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0",
    "kaykit_skeletons": "KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0",
    "kaykit_hexagon": "KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0",
}
KAYKIT_DIR = {
    "kaykit_adventurers": "KayKit-Character-Pack-Adventures-1.0/addons/kaykit_character_pack_adventures",
    "kaykit_skeletons": "KayKit-Character-Pack-Skeletons-1.0/addons/kaykit_character_pack_skeletons",
    "kaykit_hexagon": "KayKit-Medieval-Hexagon-Pack-1.0/addons/kaykit_medieval_hexagon_pack",
}
OGA = [  # opengameart.org/content/<slug>, all by Quaternius, all CC0
    "lowpoly-animated-monsters", "textured-cute-monster-pack", "animated-animales-low-poly",
    "5-low-poly-animals", "lowpoly-animated-farm-animal-pack", "stylized-nature-megakit",
    "lowpoly-nature-pack", "medieval-village-megakit", "fantasy-props-megakit",
    "lowpoly-medieval-buildings", "low-poly-medieval-weapons", "lowpoly-medieval-village-pack",
    "fantasy-low-poly-trees-and-bushes", "universal-animation-library", "animated-human-low-poly",
]


def path(pack, *parts):
    """Path of a file inside a source pack."""
    if pack in KAYKIT_DIR:
        return os.path.join(SRC, KAYKIT_DIR[pack], *parts)
    return os.path.join(SRC, "oga", pack, "x", *parts)


def fetch():
    os.makedirs(os.path.join(SRC, "oga"), exist_ok=True)
    for name, repo in KAYKIT.items():
        d = os.path.join(SRC, repo.split("/")[1])
        if not os.path.isdir(d):
            subprocess.check_call(["git", "clone", "-q", "--depth", "1", "https://github.com/%s.git" % repo, d])
    import re
    for slug in OGA:
        d = os.path.join(SRC, "oga", slug)
        if os.path.isdir(os.path.join(d, "x")):
            continue
        os.makedirs(d, exist_ok=True)
        page = urllib.request.urlopen("https://opengameart.org/content/" + slug).read().decode("utf-8", "replace")
        if ">CC0<" not in page:
            raise SystemExit("%s is no longer listed as CC0; check it before use" % slug)
        for url in sorted(set(re.findall(r'https://opengameart.org/sites/default/files/[^"]+\.zip', page))):
            z = os.path.join(d, urllib.parse.unquote(url.rsplit("/", 1)[1]))
            urllib.request.urlretrieve(url, z)
            zipfile.ZipFile(z).extractall(os.path.join(d, "x"))


if __name__ == "__main__" and sys.argv[1:] == ["fetch"]:
    fetch()
