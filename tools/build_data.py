"""Convert the original game's data for Stuttgart Speed in one go (macOS, Linux, Windows).

Runs every converter the game needs, sources/ -> decomposed/, and then checks that the files the
game loads exist. Run it again after a change to a converter; it overwrites its own output and
leaves other files in decomposed/ alone (advanced/ maps, screenshots, and the textures of a track
that has them improved by hand, with the converted ones in original/).

Usage (from anywhere; on Windows `py` instead of `python3`):
    python3 tools/build_data.py --install <folder of the installed game>   # first time
    python3 tools/build_data.py                                            # sources/ is there

--install copies GameData, FEData and Porsche.exe from the installation to sources/.
--jobs N limits the converters running at once (default: number of processor cores).
"""
import argparse
import concurrent.futures
import os
import shutil
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(REPO, "tools")
INSTALL_ITEMS = ["GameData", "FEData", "Porsche.exe"]
# Checked after the conversion: what the game cannot run without, with one car and one track as a
# sample of every kind of output.
EXPECTED = [
    "GameData/Simulation/cars.json",
    "GameData/Simulation/AICarData/ais.json",
    "GameData/Simulation/AI/trafcfg.json",
    "GameData/CarModel/356a/356a.gltf",
    "GameData/CarModel/356a/356a_damage.json",
    "GameData/CarModel/356a/356a_styles.json",
    "GameData/Track/farmland/farmland.gltf",
    "GameData/Track/farmland/farmland_road.json",
    "GameData/Track/farmland/farmland_objects.json",
    "GameData/Track/farmland/farmland_lights.json",
    "GameData/Track/farmland/farmland_ai.json",
    "GameData/Track/farmland/farmland_emitters.json",
    "GameData/Render/flares.json",
    "GameData/Render/particles.json",
    "GameData/Render/common/index.json",
    "GameData/Render/particle/index.json",
    "GameData/Sounds/SND_coll/index.json",
    "FEData/Data/car_colors.json",
    "FEData/Data/parts.json",
    "FEData/TrackArt/farmland/index.json",
]


def find_item(folder, name):
    """The entry of `folder` called `name`, in any letter case (a copy from a CD may differ)."""
    for entry in os.listdir(folder):
        if entry.lower() == name.lower():
            return os.path.join(folder, entry)
    return None


def copy_install(install, sources):
    """Copies the game's data to sources/ under the names the tools expect."""
    if not os.path.isdir(install):
        sys.exit("Not a folder: %s" % install)
    missing = [n for n in INSTALL_ITEMS if find_item(install, n) is None]
    if missing:
        sys.exit("%s is not the game's installation, missing: %s" % (install, ", ".join(missing)))
    os.makedirs(sources, exist_ok=True)
    for name in INSTALL_ITEMS:
        src, dst = find_item(install, name), os.path.join(sources, name)
        print("copy %s -> %s" % (src, dst), flush=True)
        if os.path.isdir(src):
            shutil.copytree(src, dst, dirs_exist_ok=True)
        else:
            shutil.copy2(src, dst)


def crp_stems(folder):
    return sorted(f[:-4] for f in os.listdir(folder) if f.lower().endswith(".crp"))


def stages(src, dst):
    """Groups of commands; a group runs in parallel and finishes before the next one starts."""
    game, fe = os.path.join(src, "GameData"), os.path.join(src, "FEData")
    out_game, out_fe = os.path.join(dst, "GameData"), os.path.join(dst, "FEData")
    cars, tracks = os.path.join(game, "CarModel"), os.path.join(game, "Track")
    out_cars, out_tracks = os.path.join(out_game, "CarModel"), os.path.join(out_game, "Track")
    sim = os.path.join(game, "Simulation")
    out_sim = os.path.join(out_game, "Simulation")
    render, out_render = os.path.join(game, "Render"), os.path.join(out_game, "Render")
    first = [
        ["sim_dump", os.path.join(sim, "CarData"), os.path.join(out_sim, "cars.json")],
        ["fsh2png", src, dst],
        ["snd2wav", os.path.join(game, "Sounds"), os.path.join(out_game, "Sounds")],
        ["car_colors", os.path.join(fe, "Data", "nfs5.car"), os.path.join(out_fe, "Data", "car_colors.json")],
        ["flare", os.path.join(render, "flare.dat"), os.path.join(out_render, "flares.json")],
        ["particles", os.path.join(render, "particle.ini"), os.path.join(out_render, "particles.json")],
        ["ais2json", sim, out_sim],
        ["ai_csv2json", os.path.join(sim, "AI"), os.path.join(out_sim, "AI")],
    ]
    models = [["crp2gltf", os.path.join(cars, s + ".crp"), os.path.join(out_cars, s, s + ".gltf")]
              for s in crp_stems(cars)]
    models += [["track2gltf", os.path.join(tracks, s + ".crp"), os.path.join(out_tracks, s, s + ".gltf")]
               for s in crp_stems(tracks)]
    last = [
        ["parts", fe, os.path.join(out_fe, "Data", "parts.json")],  # needs cars.json
        ["ai_lines", tracks, out_tracks],  # needs _road.json
        ["emitters", tracks, out_tracks],  # needs the converted tracks
    ]
    return [first, models, last]


def run(command, env):
    tool = command[0]
    args = [sys.executable, os.path.join(TOOLS, tool + ".py")] + command[1:]
    result = subprocess.run(args, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return command, result.returncode, result.stdout.decode("utf-8", "replace")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--install", help="folder of the installed game, copied to sources/ first")
    ap.add_argument("--sources", default="sources")
    ap.add_argument("--out", default="decomposed")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 1)
    a = ap.parse_args()

    if a.install:
        a.install = os.path.abspath(a.install)
    os.chdir(REPO)  # the tools record their relative input paths in decomposed/
    if a.install:
        copy_install(a.install, a.sources)
    missing = [n for n in INSTALL_ITEMS if not os.path.exists(os.path.join(a.sources, n))]
    if missing:
        sys.exit("%s lacks %s; run with --install <folder of the installed game>" % (a.sources, ", ".join(missing)))

    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONDONTWRITEBYTECODE="1")
    failed = []
    with concurrent.futures.ThreadPoolExecutor(a.jobs) as pool:
        for stage in stages(a.sources, a.out):
            for command, code, output in pool.map(lambda c: run(c, env), stage):
                label = " ".join([command[0], os.path.basename(command[1])])
                print("%-4s %s" % ("ok" if code == 0 else "FAIL", label), flush=True)
                if code != 0:
                    print(output)
                    failed.append(label)
    absent = [f for f in EXPECTED if not os.path.exists(os.path.join(a.out, f))]
    for f in absent:
        print("MISSING %s" % f)
    if failed or absent:
        sys.exit("Failed: %d converters, %d files missing" % (len(failed), len(absent)))
    print("Done, data in %s" % a.out)


if __name__ == "__main__":
    main()
