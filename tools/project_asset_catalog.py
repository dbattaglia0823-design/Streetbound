"""Discover Streetbound map artwork, including classified sprite-sheet regions.

The folder hierarchy is authoritative for category defaults.  Optional JSON
sidecars can override type/size/collision and define sheet regions or a grid.
Existing assets/Buildings references remain valid for saved maps.
"""
import hashlib
import json
import re
import struct
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
EXTENSIONS = {".png", ".webp", ".svg"}
PREFIXES = ("Map Building Assets/", "Buildings/")
SOLID_TYPES = {"house", "building", "warehouse", "garage", "gas_station", "prop",
               "barrier", "rock", "boulder"}
VALID_TYPES = SOLID_TYPES | {"decal", "oak", "pine", "palm", "bush", "planter",
                             "streetlight", "sign"}
SIZE_DEFAULTS = {
    "house": (12.0, 17.0), "building": (22.0, 29.0),
    "warehouse": (28.0, 37.0), "garage": (20.0, 21.0),
    "gas_station": (18.0, 17.0), "prop": (3.0, 3.0),
    "decal": (5.0, 5.0), "oak": (7.0, 7.0),
    "pine": (7.0, 7.0), "palm": (6.5, 6.5),
    "bush": (2.5, 2.5), "planter": (2.8, 2.8),
    "barrier": (3.0, 1.0), "rock": (3.0, 2.5),
    "boulder": (4.5, 3.4), "streetlight": (1.3, 1.3),
    "sign": (1.6, 1.4),
}


def asset_id(path, sprite=None):
    """The old path-only SHA remains stable for legacy placed objects."""
    key = path if sprite is None else path + "#" + sprite
    return "project-" + hashlib.sha256(key.encode("utf-8")).hexdigest()[:24]


def building_file(relative, root=ROOT):
    """Historical API name, now validates both production artwork roots."""
    if not isinstance(relative, str) or "\\" in relative or ":" in relative:
        raise ValueError("Invalid project artwork path")
    parts = relative.split("/")
    if not any(relative.startswith(prefix) for prefix in PREFIXES) or any(
            part in ("", ".", "..") for part in parts):
        raise ValueError("Project artwork must be inside a map asset folder")
    target = (root / "assets" / relative).resolve()
    parent = (root / "assets").resolve()
    if (not target.is_relative_to(parent) or
            target.suffix.lower() not in EXTENSIONS or not target.is_file()):
        raise ValueError("Missing or unsupported project artwork: " + relative)
    return target


def dimensions(path):
    with path.open("rb") as stream:
        data = stream.read(64)
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        if data[12:16] == b"VP8X":
            return (1 + int.from_bytes(data[24:27], "little"),
                    1 + int.from_bytes(data[27:30], "little"))
        if data[12:16] == b"VP8L":
            bits = int.from_bytes(data[21:25], "little")
            return ((bits & 16383) + 1, ((bits >> 14) & 16383) + 1)
        if data[12:16] == b"VP8 " and data[23:26] == b"\x9d\x01\x2a":
            return (int.from_bytes(data[26:28], "little") & 16383,
                    int.from_bytes(data[28:30], "little") & 16383)
    if path.suffix.lower() == ".svg":
        element = ET.parse(path).getroot()
        box = element.get("viewBox", "").replace(",", " ").split()
        if len(box) == 4:
            return float(box[2]), float(box[3])
        return (float(element.get("width", "0").removesuffix("px")),
                float(element.get("height", "0").removesuffix("px")))
    raise ValueError("Unreadable project image")


def _defaults(relative):
    parts = relative.lower().split("/")
    name = parts[-1]
    folders = " ".join(parts[:-1])
    if relative.startswith("Buildings/") or "buildings" in parts:
        kind = ("house" if "house" in name and "warehouse" not in name else
                "warehouse" if "warehouse" in name else
                "garage" if "garage" in name else
                "gas_station" if "gas station" in name else "building")
    elif "ground decals" in folders or "decals" in folders:
        kind = "decal"
    elif "vegetation" in folders or "nature" in folders:
        kind = ("pine" if "pine" in name else "palm" if "palm" in name else
                "oak" if "tree" in name else "bush")
    else:
        kind = "prop"
    # The first category is displayed in both map editor asset browsers.
    category = (parts[1] if parts[0] == "map building assets" and len(parts) > 2
                else "Buildings")
    family = " ".join(parts[1:-1])
    base = SIZE_DEFAULTS[kind]
    if "shipping container" in family:
        base = (12.0, 2.6)
    elif "pallet" in family or "crate" in family:
        base = (1.5, 1.3)
    elif "dumpster" in family or "bin" in family:
        base = (2.5, 1.7)
    elif "equipment" in family:
        base = (3.5, 2.8)
    elif "construction" in family and kind == "prop":
        base = (5.0, 3.0)
    return kind, category.title(), base


def _size(value, default, width, height):
    if value is None:
        ratio = min(default[0] / width, default[1] / height)
        return [round(width * ratio, 6), round(height * ratio, 6)]
    if (not isinstance(value, list) or len(value) != 2 or
            any(type(n) not in (float, int) or not 0 < n <= 100 for n in value)):
        raise ValueError("Invalid map asset footprint; expected [width_m, height_m]")
    return list(value)


def _rect(value, width, height):
    if (not isinstance(value, list) or len(value) != 4 or
            any(type(n) is not int for n in value)):
        raise ValueError("Sprite rectangle must be four integer coordinates")
    x, y, w, h = value
    if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > width or y + h > height:
        raise ValueError("Sprite rectangle is outside the source image")
    return value


def _sidecar(path):
    sidecar = path.with_name(path.stem + ".sprites.json")
    if not sidecar.is_file():
        return {}
    if sidecar.stat().st_size > 512_000:
        raise ValueError("Sprite manifest is too large")
    data = json.loads(sidecar.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Sprite manifest must be a JSON object")
    return data


def _entries_for(path, root):
    relative = path.relative_to(root / "assets").as_posix()
    building_file(relative, root)
    width, height = dimensions(path)
    if not (0 < width <= 16384 and 0 < height <= 16384):
        raise ValueError("Invalid image dimensions")
    manifest = _sidecar(path)
    kind, category, default_size = _defaults(relative)
    kind = manifest.get("type", kind)
    if kind not in VALID_TYPES:
        raise ValueError("Unsupported map asset type")
    category = str(manifest.get("category", category))[:80]
    collision = manifest.get("collision", "solid" if kind in SOLID_TYPES else "none")
    if collision not in ("solid", "none"):
        raise ValueError("Collision must be solid or none")
    source = "/game-assets/" + quote(relative, safe="/") + "?v=" + str(path.stat().st_mtime_ns)
    name = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", path.stem).replace("_", " ").replace("-", " ")
    common = dict(path=relative, type=kind, category=category,
                  collision=collision, src=source)
    sprite_items = manifest.get("sprites")
    grid = manifest.get("grid")
    if grid is not None and sprite_items is not None:
        raise ValueError("Use sprites or grid, not both")
    if grid is not None:
        if not isinstance(grid, dict):
            raise ValueError("Grid definition must be an object")
        cols, rows = grid.get("columns"), grid.get("rows")
        if type(cols) is not int or type(rows) is not int or not 1 <= cols <= 32 or not 1 <= rows <= 32:
            raise ValueError("Invalid sprite grid dimensions")
        if width % cols or height % rows:
            raise ValueError("Grid does not divide the image evenly")
        names = grid.get("names", [])
        if not isinstance(names, list):
            raise ValueError("Grid names must be an array")
        sprite_items = []
        for row in range(rows):
            for col in range(cols):
                index = row * cols + col
                sprite_items.append({
                    "name": names[index] if index < len(names) else f"{name} {index + 1}",
                    "rect": [col * (width // cols), row * (height // rows),
                             width // cols, height // rows],
                    "key": str(index + 1)
                })
    if sprite_items is None:
        return [dict(**common, id=asset_id(relative), name=name,
                     width=width, height=height,
                     size=_size(manifest.get("size"), default_size, width, height))]
    if not isinstance(sprite_items, list) or not 1 <= len(sprite_items) <= 256:
        raise ValueError("Sprite sheet needs 1–256 sprite definitions")
    result, seen = [], set()
    for index, sprite in enumerate(sprite_items):
        if not isinstance(sprite, dict):
            raise ValueError("Sprite must be an object")
        key = str(sprite.get("key", index + 1))
        if not re.fullmatch(r"[a-zA-Z0-9_-]{1,50}", key) or key in seen:
            raise ValueError("Invalid or duplicated sprite key")
        seen.add(key)
        rect = _rect(sprite.get("rect"), width, height)
        sub_kind = sprite.get("type", kind)
        if sub_kind not in VALID_TYPES:
            raise ValueError("Unsupported sprite type")
        sub_collision = sprite.get("collision", collision)
        if sub_collision not in ("solid", "none"):
            raise ValueError("Unsupported sprite collision")
        result.append(dict(**common, id=asset_id(relative, key),
                           name=str(sprite.get("name") or f"{name} {index + 1}")[:80],
                           type=sub_kind, collision=sub_collision,
                           sprite=key, region=rect, width=rect[2], height=rect[3],
                           size=_size(sprite.get("size", manifest.get("size")),
                                      default_size, rect[2], rect[3])))
    return result


def catalog(root=ROOT):
    result = []
    for subfolder in ("Map Building Assets", "Buildings"):
        folder = root / "assets" / subfolder
        if not folder.is_dir():
            continue
        for path in sorted(folder.rglob("*"), key=lambda p: p.as_posix().casefold()):
            if path.suffix.lower() not in EXTENSIONS or not path.is_file():
                continue
            try:
                result.extend(_entries_for(path, root))
            except (ValueError, OSError, ET.ParseError, json.JSONDecodeError,
                    struct.error, UnicodeDecodeError):
                continue  # One corrupt asset must not hide all other artwork.
    return result


def validated_asset(relative, identifier, root=ROOT):
    """Resolve the exact allowlisted image *and* sprite; never trust client metadata."""
    path = building_file(relative, root)
    for entry in _entries_for(path, root):
        if entry["id"] == identifier:
            return entry
    raise ValueError("Unknown or stale map asset reference: " + str(identifier))
