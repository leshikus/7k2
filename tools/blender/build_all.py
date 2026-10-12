"""Rebuilds every 3D model of the game from the CC0 source packs.

    python tools/blender/build_all.py [--blender <path to blender.exe>] [step ...]

Steps (default: all, in this order): anims humans mounts riders fryhtans props
buildings nature. Each step runs a fresh headless Blender. Sources are fetched first
(sources.py fetch) when missing. Output: assets/models/.
"""
import os, sys, subprocess, glob, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
STEPS = [
    ("anims", "anims.py", []),
    ("humans", "humans.py", []),
    ("mounts", "mounts.py", []),
    ("fryhtans", "fryhtans.py", []),
    ("props", "props.py", []),
    ("buildings", "buildings.py", []),
    ("nature", "nature.py", []),
]


def find_blender(args):
    if "--blender" in args:
        return args[args.index("--blender") + 1]
    env = os.environ.get("BLENDER")
    if env:
        return env
    for cand in glob.glob(os.path.join(os.path.expanduser("~"), "tools", "blender", "blender-4.2*", "blender*")) + [shutil.which("blender") or ""]:
        if cand and os.path.isfile(cand):
            return cand
    raise SystemExit("Blender 4.2 not found; pass --blender <path> or set BLENDER")


def main():
    args = sys.argv[1:]
    blender = find_blender(args)
    wanted = [a for a in args if not a.startswith("--") and a != (args[args.index("--blender") + 1] if "--blender" in args else None)]
    sys.path.insert(0, HERE)
    import sources
    if not os.path.isdir(sources.SRC) or not os.listdir(sources.SRC):
        sources.fetch()
    for name, script, extra in STEPS:
        if wanted and name not in wanted:
            continue
        print("==", name)
        r = subprocess.run([blender, "-b", "--factory-startup", "-P", os.path.join(HERE, script), "--"] + extra)
        if r.returncode != 0:
            raise SystemExit("%s failed" % name)


if __name__ == "__main__":
    main()
