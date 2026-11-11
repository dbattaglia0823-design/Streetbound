#!/usr/bin/env python3
"""Fetch and prepare strictly pinned, publicly CC0-labeled engine recordings.

Source files are pinned to Git commits AND verified against Git blob SHA-1.
The result is an audible recorded foundation to mix beneath Streetbound's
model-specific synthesized firing and exhaust notes; not an OEM sound claim.
Run: python3 tools/prepare_cc0_engine_beds.py
Needs ffmpeg, git-free Python stdlib and outbound HTTPS to GitHub.
"""
from __future__ import annotations
import array
import hashlib
import json
import math
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/audio/engines"
RATE = 22050
SECONDS = 1.25
TARGET_SAMPLES = round(RATE * SECONDS)

AUTOMOBILITY = ("FoundationGames/Automobility",
    "e43f78b12786fd0c490b4fa2356a324b57290994",
    "common/src/main/resources/assets/automobility/sounds")
BORDER = ("yashimosh/border-run",
    "38d6afa442a06bbd414f21ac05c0f1b4d08bd705", "public/sfx/engine")
BUNTINE = ("buntine/CarEngines",
    "e26b3d1fcfd6887079bb434cb9e9fef3b0fd688d", "sounds")

# Families are acoustic approximations, not claims that the recording comes
# from the depicted make/model. CC0 evidence is documented separately.
SOURCES = [
    ("i3", AUTOMOBILITY, "creative_engine.ogg", "aa37c49356b7b2b987505f198e66a35b158ddc7"),
    ("i4", AUTOMOBILITY, "copper_engine.ogg", "a3f8b760c1c3030861362e7ec67f231e5873b887"),
    ("i6", AUTOMOBILITY, "iron_engine.ogg", "6ca61feab3f47442feb8488f7e99438545dff452"),
    ("v6", AUTOMOBILITY, "stone_engine.ogg", "f693af48a11413ebad4d1ab4cc85ee1647817512"),
    ("v8_cross", BUNTINE, "engine.wav", "c9a29ce1f25dd4b7d1ae699977b964ff6d68716d"),
    ("v8_flat", BORDER, "loop_3_0.wav", "48345e4b0e579aa097be65cc45f324137e5ebb41"),
    ("v10", BORDER, "loop_5_0.wav", "60d961be63cf7b203e01b781cd29b24cbbedb81c"),
    ("v12", AUTOMOBILITY, "diamond_engine.ogg", "f2993b85c1ae01767fd1539a7759618e2d5dda07"),
    ("w12", AUTOMOBILITY, "gold_engine.ogg", "c7c75560ff8d2727464189953c853ca24f25c69"),
    ("w16", BORDER, "loop_4_0.wav", "fa9909ff69107b549145ef8d983839579fe9bd4e"),
]


def git_blob_sha(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def run(cmd: list[str], **kwargs):
    return subprocess.run(cmd, check=True, **kwargs)


def acquire(record: tuple, temp: pathlib.Path) -> pathlib.Path:
    family, source, filename, expected_sha = record
    repo, revision, folder = source
    if ".." in filename or filename.startswith("/"):
        raise ValueError("Unsafe input filename")
    url = f"https://raw.githubusercontent.com/{repo}/{revision}/{folder}/{filename}"
    dest = temp / f"{family}-{filename}"
    run(["curl", "--fail", "--location", "--silent", "--show-error",
         "--retry", "3", "--max-time", "60", url, "--output", str(dest)])
    data = dest.read_bytes()
    actual = git_blob_sha(data)
    if actual != expected_sha:
        raise ValueError(f"Source pin failed {family}: {actual} != {expected_sha}")
    if not data or len(data) > 10 * 1024 * 1024:
        raise ValueError(f"Source missing or unexpectedly large: {family}")
    return dest


def decode(source: pathlib.Path) -> list[float]:
    proc = run(["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error",
        "-i", str(source), "-ac", "1", "-ar", str(RATE),
        "-f", "s16le", "-acodec", "pcm_s16le", "-"], capture_output=True)
    raw = proc.stdout
    if len(raw) < 4000 or len(raw) % 2 != 0:
        raise ValueError(f"Unusable recorded signal: {source}")
    data = array.array("h")
    data.frombytes(raw)
    if sys.byteorder != "little":
        data.byteswap()
    return [float(v) / 32768.0 for v in data]


def soften_loop(samples: list[float]) -> list[float]:
    if len(samples) < 1100:
        raise ValueError("Recording too short to create a usable loop")
    # Most clips are engine beds; avoid an isolated starting click/stop.
    if len(samples) >= TARGET_SAMPLES + RATE // 5:
        begin = (len(samples) - TARGET_SAMPLES) // 2
        segment = samples[begin:begin + TARGET_SAMPLES]
    else:
        # Original source may itself be a short loop. Repeat it only after
        # removing its edge click, not as a sequence of hard audio cuts.
        segment = samples[:]
    dc = sum(segment) / len(segment)
    segment = [v - dc for v in segment]
    width = min(round(RATE * 0.055), len(segment) // 8)
    # Blend the *end* of the segment into its beginning over 55ms so the
    # exact loop boundary and its first derivative are non-clicking.
    for i in range(width):
        w = (i + 1.0) / width
        segment[len(segment)-width+i] = (
            segment[len(segment)-width+i] * (1.0 - w)
            + segment[i] * w
        )
    samples = (segment * math.ceil(TARGET_SAMPLES / len(segment)))[:TARGET_SAMPLES]
    # Repeat may leave an incomplete final cycle: soften that wrap too.
    for i in range(width):
        w = (i + 1.0) / width
        samples[len(samples)-width+i] = (
            samples[len(samples)-width+i] * (1.0 - w)
            + samples[i] * w
        )
    rms = math.sqrt(sum(v*v for v in samples) / len(samples))
    if rms < 0.0015:
        raise ValueError("Silent audio source")
    target = 10 ** (-17.0 / 20.0)
    peak = max(abs(v) for v in samples)
    gain = min(target / rms, 0.86 / max(peak, 0.001))
    return [max(-0.9, min(0.9, x * gain)) for x in samples]


def raw_16bit(samples: list[float]) -> bytes:
    buf = array.array("h", [round(max(-1.0,min(1.0,x))*32767) for x in samples])
    if sys.byteorder != "little":
        buf.byteswap()
    return buf.tobytes()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    report = []
    preview: list[float] = []
    with tempfile.TemporaryDirectory() as temp_root:
        temp = pathlib.Path(temp_root)
        for family, source, filename, sha in SOURCES:
            path = acquire((family,source,filename,sha),temp)
            segment = soften_loop(decode(path))
            destination = OUT / family / "recorded_texture.ogg"
            destination.parent.mkdir(parents=True,exist_ok=True)
            run(["ffmpeg","-nostdin","-hide_banner","-loglevel","error","-y",
                "-f","s16le","-ar",str(RATE),"-ac","1","-i","-",
                "-c:a","libvorbis","-q:a","4",str(destination)],
                input=raw_16bit(segment))
            if destination.stat().st_size < 800:
                raise ValueError(f"Failed export {family}")
            rms = math.sqrt(sum(v*v for v in segment)/len(segment))
            peak = max(abs(v) for v in segment)
            edge = abs(segment[-1]-segment[0])
            if edge > 0.08 or peak > 0.91:
                raise ValueError(f"Clip has unacceptable seam or clipping: {family}: {edge:.3f}")
            entry = {"family":family,"source_repo":source[0],
                "source_revision":source[1],"source_filename":filename,
                "source_blob_sha":sha,"license":"CC0-1.0",
                "output":str(destination.relative_to(ROOT)),
                "seconds":SECONDS,"rms_dbfs":round(20*math.log10(rms),1),
                "peak":round(peak,4),"seam_delta":round(edge,5),
                "bytes":destination.stat().st_size}
            report.append(entry)
            preview.extend(segment)
            preview.extend([0.0] * (RATE // 4))
            print(f"{family:9} {entry['bytes']:6} bytes  RMS={entry['rms_dbfs']}dB "
                  f"edge={edge:.5f} [recorded]")
        (OUT / "RECORDING_MANIFEST.json").write_text(
            json.dumps({"origin":"CC0 field/derived field recordings, NOT exact vehicle captures",
                "recordings":report},indent=2)+"\n",encoding="utf-8")
        # Listening review asset, NOT needed by the game. This stays in the
        # workflow artifact for humans to compare 10 recorded foundations.
        import wave
        with wave.open(str(temp / "engine_audition.wav"),"wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes(raw_16bit(preview))
        review = ROOT / "engine_audition.wav"
        review.write_bytes((temp / "engine_audition.wav").read_bytes())
    print(f"Prepared {len(report)} pinned CC0 recordings and audition WAV")


if __name__ == "__main__":
    main()
