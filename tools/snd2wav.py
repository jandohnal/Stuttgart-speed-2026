"""Convert NFS5 sound banks (BIGF .viv archives with EA BNKl banks, or loose .bnk) to WAV and
describe the engine sound sets for the game.

Format: docs/formats/bnk.md. Codec and header layout follow vgmstream (EA BNK / EA-XA ADPCM).
For every bank writes <out>/<archive>/<bank>/<n>.wav plus index.json (sample rate, samples,
loop points, codec); the other files of an archive (engine tables .ect/.elt/.cct/.clt, .h,
default.cfg) are copied next to the banks as they are. For an engine set (sd*.viv) it also
writes <out>/<set>/engine.json: the loops of the engine tables, grouped into "load" (on throttle,
*lt tables) and "coast" (off throttle and idle, *ct tables), two layers each (the two sample
groups of a table, played together), with the engine speed each loop was recorded at.

The engine tables (CRDl) are only partly decoded: bytes 0x20..0x27 list two groups of four bank
indices (index + 1, 0 = none); the crossfade grid after them is not used yet. The recorded speed
comes from the loop's MIDI root note (PT tag 0x07): firing frequency = note frequency, a four
stroke engine fires cylinders / 2 times per turn, so rpm = frequency * 60 / (cylinders / 2).

Usage:
    python3 tools/snd2wav.py sources/GameData/Sounds decomposed/GameData/Sounds
    python3 tools/snd2wav.py sources/GameData/Sounds/sd1a.viv decomposed/GameData/Sounds [--cylinders 4]
"""
import argparse
import json
import os
import struct
import wave

from archives import read_bigf
from common import source_files

DEFAULT_RATE = 22050
# PT header tags (one byte tag, one byte size, big-endian value); 0xFC-0xFE start a sub-header.
# Codec (0xA0): none = EA-XA ADPCM, 0x08 = PCM 16 bit LE, 0x09 = PCM 8 bit signed.
PT_TAGS = {0x80: "version", 0x82: "channels", 0x83: "codec1", 0x84: "sample_rate", 0x85: "samples",
           0x86: "loop_start", 0x87: "loop_end", 0x88: "data_offset", 0x92: "bytes_per_sample", 0xA0: "codec2"}
EA_XA_TABLE = (0, 240, 460, 392, 0, 0, -208, -220)
ENGINE_TABLES = {"load": ("elt", "clt"), "coast": ("ect", "cct")}  # exterior first, cockpit second


def read_pt(data, pos):
    """Parse a PT header at pos: {field: value} plus raw {tag: value} of unknown tags."""
    if data[pos:pos + 4] != b"PT\0\0":
        raise ValueError(f"no PT header at {pos:#x}")
    pos += 4
    info, raw = {}, {}
    while pos < len(data):
        tag = data[pos]
        pos += 1
        if tag == 0xFF:
            break
        if tag in (0xFC, 0xFD, 0xFE):
            continue
        size = data[pos]
        value = int.from_bytes(data[pos + 1:pos + 1 + size], "big")
        pos += 1 + size
        if tag in PT_TAGS:
            info[PT_TAGS[tag]] = value
        else:
            raw[f"{tag:#04x}"] = value
    info["raw"] = raw
    return info


def read_bnk(data):
    """Sounds of an EA BNKl (v4) bank: [(index, PT info)], PT offsets are relative to their table entry."""
    if data[:4] != b"BNKl":
        raise ValueError("not a little-endian EA bank")
    version, count = struct.unpack_from("<HH", data, 4)
    sounds = []
    for i in range(count):
        entry = 0x10 + 4 * i
        rel = struct.unpack_from("<I", data, entry)[0]
        if rel in (0, 0xFFFFFFFF):
            continue
        sounds.append((i, read_pt(data, entry + rel)))
    return version, sounds


def decode_ea_xa(data, offset, samples):
    """EA-XA ADPCM v2 (mono): 15-byte frames of 28 samples (header: coef index << 4 | shift - 8),
    or 0xEE frames with two history samples and 28 raw big-endian PCM samples."""
    out, hist1, hist2, pos = [], 0, 0, offset
    while len(out) < samples and pos < len(data):
        info = data[pos]
        if info == 0xEE:
            hist1, hist2 = struct.unpack_from(">hh", data, pos + 1)
            frame = list(struct.unpack_from(">28h", data, pos + 5))
            out += frame
            hist2, hist1 = frame[-2], frame[-1]
            pos += 61
            continue
        coef1, coef2 = EA_XA_TABLE[info >> 4], EA_XA_TABLE[(info >> 4) + 4]
        shift = (info & 0x0F) + 8
        for i in range(28):
            byte = data[pos + 1 + i // 2]
            nibble = (byte >> 4) if i % 2 == 0 else (byte & 0x0F)
            value = nibble << 28
            if value & 0x80000000:
                value -= 1 << 32
            sample = ((value >> shift) + coef1 * hist1 + coef2 * hist2 + 128) >> 8
            sample = max(-32768, min(32767, sample))
            hist2, hist1 = hist1, sample
            out.append(sample)
        pos += 15
    return out[:samples]


def decode(data, info):
    """PCM samples of one sound, or None for an unknown codec."""
    codec = info.get("codec2", info.get("codec1"))
    if info.get("channels", 1) != 1:
        return None, f"channels {info.get('channels')}"
    if codec is None or codec == 0x0A:
        return decode_ea_xa(data, info["data_offset"], info["samples"]), "ea-xa"
    n, offset = info["samples"], info["data_offset"]
    if codec == 0x08 or info.get("bytes_per_sample") == 2:
        n = min(n, (len(data) - offset) // 2)
        return list(struct.unpack_from(f"<{n}h", data, offset)), "pcm16le"
    if codec == 0x09:  # signed 8 bit (the low quality "...16" sets: 16 kHz)
        n = min(n, len(data) - offset)
        return [b * 256 for b in struct.unpack_from(f"<{n}b", data, offset)], "pcm8"
    return None, f"codec {codec:#x}"


def write_wav(path, rate, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def convert_bank(data, out_dir):
    """Decode one bank into out_dir; returns (written, skipped reasons)."""
    os.makedirs(out_dir, exist_ok=True)
    version, sounds = read_bnk(data)
    entries, skipped = [], {}
    for index, info in sounds:
        pcm, codec = decode(data, info)
        if pcm is None:
            skipped[codec] = skipped.get(codec, 0) + 1
            continue
        rate = info.get("sample_rate", DEFAULT_RATE)
        name = f"{index:03d}.wav"
        write_wav(os.path.join(out_dir, name), rate, pcm)
        peak = max((abs(s) for s in pcm), default=0)
        entry = {"index": index, "file": name, "codec": codec, "rate": rate, "samples": len(pcm),
                 "seconds": round(len(pcm) / rate, 3), "peak": peak}
        if "loop_start" in info:
            entry["loop_start"] = info["loop_start"]
            entry["loop_end"] = info.get("loop_end", len(pcm) - 1)
        if info["raw"]:
            entry["tags"] = info["raw"]
        entries.append(entry)
    with open(os.path.join(out_dir, "index.json"), "w") as fh:
        json.dump({"bank_version": version, "sounds": entries}, fh, indent=1)
    return len(entries), skipped


def note_hz(note):
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def table_slots(data):
    """An engine table's two groups of four bank indices (None where empty)."""
    if data[:4] != b"CRDl":
        raise ValueError("not a CRDl table")
    ids = [b + 1 if b else None for b in data[0x20:0x28]]
    return [ids[0:4], ids[4:8]]


def describe_engine(set_dir, cylinders=4):
    """Write <set>/engine.json from the converted set (tables and index.json); returns it."""
    name = os.path.basename(os.path.normpath(set_dir))
    index = {e["index"]: e for e in json.load(open(os.path.join(set_dir, name, "index.json")))["sounds"]}
    fires_per_turn = cylinders / 2.0
    out = {"set": name, "cylinders": cylinders, "view": "exterior", "groups": {}}
    for group, (exterior, _cockpit) in ENGINE_TABLES.items():
        layers = []
        for slots in table_slots(open(os.path.join(set_dir, f"{name}.{exterior}"), "rb").read()):
            loops = []
            for i in slots:
                e = index.get(i)
                if e is None or "0x07" not in e.get("tags", {}):
                    continue
                note = e["tags"]["0x07"]
                loops.append({"index": i, "file": f"{name}/{e['file']}", "note": note,
                              "rpm": round(note_hz(note) * 60.0 / fires_per_turn),
                              "rate": e["rate"], "samples": e["samples"],
                              "loop_start": e.get("loop_start", 0), "loop_end": e.get("loop_end", e["samples"] - 1)})
            if loops:
                layers.append(sorted(loops, key=lambda x: x["rpm"]))
        out["groups"][group] = layers
    with open(os.path.join(set_dir, "engine.json"), "w") as fh:
        json.dump(out, fh, indent=1)
    return out


def convert(src, out_root, cylinders=4):
    """Convert one .viv or .bnk file; returns (banks, sounds, skipped)."""
    stem = os.path.splitext(os.path.basename(src))[0]
    data = open(src, "rb").read()
    banks = sounds = 0
    skipped = {}
    if data[:4] == b"BIGF":
        folder = os.path.join(out_root, stem)
        os.makedirs(folder, exist_ok=True)
        for name, payload in read_bigf(data).items():
            if payload[:4] == b"BNKl":
                n, s = convert_bank(payload, os.path.join(folder, os.path.splitext(name)[0]))
                banks += 1
                sounds += n
                for k, v in s.items():
                    skipped[k] = skipped.get(k, 0) + v
            else:
                with open(os.path.join(folder, name), "wb") as fh:
                    fh.write(payload)
        if os.path.exists(os.path.join(folder, f"{stem}.elt")):
            describe_engine(folder, cylinders)
    elif data[:4] == b"BNKl":
        n, skipped = convert_bank(data, os.path.join(out_root, stem))
        banks, sounds = 1, n
    return banks, sounds, skipped


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("src", help="a .viv / .bnk file or a folder of them")
    ap.add_argument("out")
    ap.add_argument("--cylinders", type=int, default=4, help="for the engine speed of the loops")
    a = ap.parse_args()
    files = [path for path, _ in source_files(a.src, [".viv", ".bnk"], recursive=False)]
    total_banks = total_sounds = 0
    total_skipped = {}
    for f in files:
        try:
            banks, sounds, skipped = convert(f, a.out, a.cylinders)
        except ValueError as e:
            print(f"{f}: {e}")
            continue
        total_banks += banks
        total_sounds += sounds
        for k, v in skipped.items():
            total_skipped[k] = total_skipped.get(k, 0) + v
        print(f"{f}: {banks} banks, {sounds} sounds" + (f", skipped {skipped}" if skipped else ""))
    print(f"total: {len(files)} files, {total_banks} banks, {total_sounds} sounds, skipped {total_skipped}")


if __name__ == "__main__":
    main()
