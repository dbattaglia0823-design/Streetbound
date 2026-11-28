"""Validated, recursive project map-art catalog shared by both editors and world baker.

Legacy assets/Buildings paths remain valid. New artwork lives under
assets/Map Building Assets/<category>/ and may use sidecar *.asset.json metadata
metadata. Sprite sheets are not supported. Paths are never accepted outside these roots.
"""
import hashlib
import json
import re
import struct
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
EXTENSIONS = {'.png', '.webp', '.svg'}
LEGACY = 'Buildings'
LIBRARY = 'Map Building Assets'
ALLOWED_KINDS = {'house', 'building', 'warehouse', 'garage', 'gas_station',
                 'industrial_prop', 'road_prop', 'ground_decal',
                 'oak', 'pine', 'palm', 'bush', 'rock', 'boulder'}


def asset_id(path):
    return 'project-' + hashlib.sha256(path.encode('utf-8')).hexdigest()[:24]


def building_file(relative, root=ROOT):
    """Backward-compatible name used by the authoritative world importer."""
    if not isinstance(relative, str) or '\\' in relative or ':' in relative:
        raise ValueError('Invalid project artwork path')
    parts = relative.split('/')
    if len(parts) < 2 or parts[0] not in {LEGACY, LIBRARY} or any(
            p in ('', '..', '.') for p in parts):
        raise ValueError('Project artwork must be inside an approved asset folder')
    target = (root / 'assets' / relative).resolve()
    allowed_root = (root / 'assets' / parts[0]).resolve()
    if not target.is_relative_to(allowed_root) or target.suffix.lower() not in EXTENSIONS:
        raise ValueError('Unsupported project artwork: ' + relative)
    if not target.is_file() and parts[0] == LEGACY:
        # The older published Morrow maps retain Buildings/... references.
        # Resolve these safely after the user moved the complete folder.
        migrated = (root / 'assets' / LIBRARY / relative).resolve()
        relocated_root = (root / 'assets' / LIBRARY / LEGACY).resolve()
        if migrated.is_relative_to(relocated_root) and migrated.is_file():
            target = migrated
    if not target.is_file():
        raise ValueError('Missing project artwork: ' + relative)
    if any(p.casefold() == 'sprite sheets' for p in parts) or target.with_suffix('.sheet.json').is_file():
        raise ValueError('Sprite sheet artwork is retired: ' + relative)
    return target


def dimensions(path):
    with path.open('rb') as stream:
        data = stream.read(64)
    if data[:8] == b'\x89PNG\r\n\x1a\n':
        return struct.unpack('>II', data[16:24])
    if data[:4] == b'RIFF' and data[8:12] == b'WEBP':
        if data[12:16] == b'VP8X':
            return (1 + int.from_bytes(data[24:27], 'little'),
                    1 + int.from_bytes(data[27:30], 'little'))
        if data[12:16] == b'VP8L':
            bits = int.from_bytes(data[21:25], 'little')
            return ((bits & 16383) + 1, ((bits >> 14) & 16383) + 1)
        if data[12:16] == b'VP8 ' and data[23:26] == b'\x9d\x01\x2a':
            return (int.from_bytes(data[26:28], 'little') & 16383,
                    int.from_bytes(data[28:30], 'little') & 16383)
    if path.suffix.lower() == '.svg':
        element = ET.parse(path).getroot()
        box = element.get('viewBox', '').replace(',', ' ').split()
        if len(box) == 4:
            return float(box[2]), float(box[3])
        return (float(element.get('width', '0').removesuffix('px')),
                float(element.get('height', '0').removesuffix('px')))
    raise ValueError('Unreadable asset image')


def _read_meta(path):
    if not path.is_file():
        return {}
    if path.stat().st_size > 100_000:
        raise ValueError('Asset metadata exceeds 100 KB')
    data = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(data, dict):
        raise ValueError('Asset metadata must be a JSON object')
    return data


def _default_type(relative):
    folders = relative.lower().replace('\\', '/')
    filename = Path(relative).stem.lower()
    if 'ground decal' in folders or 'decal' in folders:
        return 'ground_decal'
    if any(word in folders for word in ('road', 'infrastructure', 'traffic', 'barrier')):
        return 'road_prop'
    if any(word in folders for word in ('industrial', 'construction', 'pallet',
                                        'dumpster', 'cargo', 'container')):
        return 'industrial_prop'
    if 'house' in filename and 'warehouse' not in filename:
        return 'house'
    if 'warehouse' in filename:
        return 'warehouse'
    if 'garage' in filename:
        return 'garage'
    if 'gas station' in filename:
        return 'gas_station'
    if relative.startswith(LEGACY + '/') or 'building' in folders:
        return 'building'
    return 'industrial_prop'


def _size(meta):
    raw = meta.get('worldSize')
    if raw is None:
        return None
    if (not isinstance(raw, list) or len(raw) != 2 or
            any(type(v) not in (int, float) or not 0 < v <= 100 for v in raw)):
        raise ValueError('worldSize must contain two positive metre dimensions')
    return [float(v) for v in raw]


def _entry(relative, width, height, mtime, meta, label=None, region=None):
    kind = meta.get('type', _default_type(relative))
    if kind not in ALLOWED_KINDS:
        raise ValueError('Unsupported asset type')
    collision = meta.get('collision', 'none' if kind == 'ground_decal' else 'solid')
    if collision not in ('solid', 'none'):
        raise ValueError('Asset collision must be solid or none')
    name = label or meta.get('name') or Path(relative).stem
    if not isinstance(name, str) or not name.strip() or len(name) > 100:
        raise ValueError('Invalid asset name')
    source_name = name
    name = re.sub(r'(?<=[a-z])(?=[A-Z])', ' ', name).replace('_', ' ').replace('-', ' ')
    source_id = relative + ('#' + source_name if region else '')
    result = dict(id=asset_id(source_id), path=relative, name=name, type=kind,
                  category=relative.split('/')[1] if relative.startswith(LIBRARY + '/') else 'Buildings',
                  width=width, height=height, collision=collision,
                  src='/game-assets/' + quote(relative, safe='/') + '?v=' + str(mtime))
    size = _size(meta)
    if size:
        result['worldSize'] = size
    if region:
        result['region'] = region
    return result


def catalog(root=ROOT):
    result = []
    for base in (LEGACY, LIBRARY):
        folder = root / 'assets' / base
        if not folder.exists():
            continue
        for path in sorted(folder.rglob('*'), key=lambda p: p.as_posix().casefold()):
            if path.suffix.lower() not in EXTENSIONS or not path.is_file():
                continue
            relative = path.relative_to(root / 'assets').as_posix()
            try:
                building_file(relative, root)
                width, height = dimensions(path)
                if not (0 < width <= 16384 and 0 < height <= 16384):
                    continue
                meta = _read_meta(path.with_suffix('.asset.json'))
                result.append(_entry(relative, width, height,
                                     path.stat().st_mtime_ns, meta))
            except (ValueError, OSError, ET.ParseError, struct.error,
                    json.JSONDecodeError):
                continue
    return result


def resolve_asset(relative, identifier, root=ROOT):
    """Validate a saved ID against actual source artwork and sprite region."""
    actual = building_file(relative, root)
    canonical = actual.relative_to(root / 'assets').as_posix()
    for entry in catalog(root):
        if entry['path'] == canonical and entry['id'] == identifier:
            return entry
        # A legacy saved ID continues to resolve even after moving the file.
        if (canonical != relative and entry['path'] == canonical and
                not entry.get('region') and identifier == asset_id(relative)):
            return {**entry, 'path': relative, 'id': identifier}
    raise ValueError('Unknown or moved project asset: ' + relative)
