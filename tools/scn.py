"""Text files of the original tracks: scenes (<track>_*.scn) and object properties (animdefs.txt).

Format: docs/formats/scn.md. Coordinates stay in the original (left-handed) space; converters
mirror them with crp.to_gltf.
"""
import os
import re

from common import find_file

COLLIDE_TYPES = {"ksmackable": "smackable", "kbox": "box", "kcylinder": "cylinder", "0": "none"}
GATE_TYPES = {2: "start", 1: "finish"}


def read_triggers(path):
    """TRIGGER_ELEMENT blocks: [{type, position, basis (forward, up, right: 9 floats), line (6 floats)}]."""
    lines = [ln.split() for ln in open(path, encoding="latin1") if ln.strip()]
    out = []
    for i, ln in enumerate(lines):
        if ln[0] != "TRIGGER_ELEMENT" or i + 4 >= len(lines):
            continue
        out.append({"type": int(lines[i + 3][0]), "position": [float(x) for x in lines[i + 1]],
                    "basis": [float(x) for x in lines[i + 2]], "line": [float(x) for x in lines[i + 4]]})
    return out


def start_finish(track_path):
    """{"start": trigger, "finish": trigger} from <track>_fstart.scn next to the .crp (driving forward)."""
    path = os.path.splitext(track_path)[0] + "_fstart.scn"
    if not os.path.exists(path):
        return {}
    gates = {}
    for trigger in read_triggers(path):
        kind = GATE_TYPES.get(trigger["type"])
        if kind and kind not in gates:
            gates[kind] = trigger
    return gates


def read_animdefs(folder):
    """Object properties per tag from animdefs.txt: {tag: {"collide", "mass", "drivethrough"}}.

    Only the top-level keys of each SECTION:ANIM are read; the first section of a tag wins."""
    path = find_file(folder, "animdefs.txt")
    if path is None:
        return {}
    text = re.sub(r"//[^\n]*", "", open(path, encoding="latin1").read())
    defs = {}
    for m in re.finditer(r"SECTION:ANIM\s*\{", text):
        depth, j = 1, m.end()
        while depth and j < len(text):
            depth += {"{": 1, "}": -1}.get(text[j], 0)
            j += 1
        body = text[m.end():j - 1]
        while True:  # drop nested sections, keep the top-level keys
            flat = re.sub(r"SECTION:\w+\s*\{[^{}]*\}", "", body)
            if flat == body:
                break
            body = flat
        props = {k.lower(): v.strip() for k, v in re.findall(r"(\w+)\s*=\s*([^;]+);", body)}
        tag = props.get("tag")
        if not tag or tag in defs:
            continue
        defs[tag] = {"collide": COLLIDE_TYPES.get(props.get("collidetype", "0").lower(), "static"),
                     "mass": float(props.get("mass", 0) or 0),
                     "drivethrough": props.get("drivethrough", props.get("drivethru", "0")) == "1"}
    return defs
