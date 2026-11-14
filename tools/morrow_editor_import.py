"""Apply a validated World Forge Morrow Coast authoring overlay during rebake.

The editor works on human-readable road anchors. ALL derived runtime data
(road samples, junctions, collisions, indices, traffic) must be rebaked after
edits; copying the editor JSON over the streamed-world file is NEVER safe.

No third-party dependencies. This module is deliberately strict about unknown
road IDs, deleted original roads and disconnected endpoints to avoid quietly
corrupting the entire streamed map.
"""
import json
import math
import re
from project_asset_catalog import building_file, asset_id
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EDIT_PATH = ROOT / "map-editor" / "maps" / "morrow-coast.edits.world.json"
BASE_WIDTH, BASE_HEIGHT = 6400, 4800
MAX_WIDTH, MAX_HEIGHT = 9600, 7200


def validate_world_bounds(width, height):
    """Only add space on the east (+X) and south (+Y); never translate content."""
    if (type(width) is not int or type(height) is not int
            or not BASE_WIDTH <= width <= MAX_WIDTH
            or not BASE_HEIGHT <= height <= MAX_HEIGHT):
        raise ValueError(
            f"Original Morrow Coast is 6400x4800, and may grow to at most {MAX_WIDTH}x{MAX_HEIGHT}; "
            "shrinking the original world or moving its origin is not allowed")
    return width, height


def world_bounds_from_overlay(filename=EDIT_PATH):
    """Read only dimension metadata before building the rest of the world.

    Map topology, collision and RNG generation still run from source after
    bounds are validated. No size change means the old deterministic build.
    """
    filename = Path(filename)
    if not filename.exists():
        return BASE_WIDTH, BASE_HEIGHT
    if filename.stat().st_size > 8_000_000:
        raise ValueError("Morrow editing source exceeds 8 MB")
    doc = json.loads(filename.read_text(encoding="utf-8"))
    if doc.get("format") != "gdt.racing-world" or doc.get("version") != 2 or doc.get("name") != "Morrow Coast":
        raise ValueError("Invalid Morrow Coast source map")
    world = doc.get("world", {})
    return validate_world_bounds(world.get("width"),world.get("height"))
KIND_TO_CLASS = {
    "local": "city", "arterial": "city", "highway": "highway",
    "rural": "country", "mountain": "mountain", "track": "track",
    "driveway": "service", "gravel": "service",
}
CLASS_TO_KIND = {
    "city": "local", "highway": "highway", "country": "rural",
    "mountain": "mountain", "track": "track", "service": "driveway",
}
PALETTES = {
    "grass": "a3b789", "forest": "718d70", "mountain": "9baba0",
    "rock": "9baba0", "beach": "e3d4aa", "ocean": "82b5b5",
    "lake": "82b5b5", "city": "b1b6a0", "desert": "d2bb91",
    "farmland": "b4bd8a",
}
LOOSE = {"DIRT", "GRAVEL"}


def length(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def points(raw, width=BASE_WIDTH, height=BASE_HEIGHT):
    if not isinstance(raw, list) or not (2 <= len(raw) <= 180):
        raise ValueError("A road needs 2-180 control points")
    result = []
    for item in raw:
        if not isinstance(item, dict):
            raise ValueError("Road geometry requires x/y coordinates")
        x, y = item.get("x"), item.get("y")
        if not all(isinstance(v, (int, float)) and math.isfinite(v) for v in (x, y)):
            raise ValueError("Nonfinite map coordinate")
        if not (0 <= x <= width and 0 <= y <= height):
            raise ValueError("Map coordinate outside Morrow Coast")
        result.append([round(float(x), 3), round(float(y), 3)])
    if all(length(result[0], v) < 1.0 for v in result[1:]):
        raise ValueError("Zero-length road")
    return result


def _thin_polygon(items, maximum=180, width=BASE_WIDTH, height=BASE_HEIGHT):
    # Mirrors the browser editor's in-bounds preview. Original source
    # remains high resolution when the user did not change the proxy polygon.
    coords = [(min(float(width), max(0.0, float(v[0]))),
               min(float(height), max(0.0, float(v[1])))) for v in items]
    if len(coords) > 1 and length(coords[0], coords[-1]) < 0.001:
        coords.pop()
    if len(coords) <= maximum:
        return [[float(v) for v in p] for p in coords]
    return [[float(v) for v in coords[i * len(coords) // maximum]]
            for i in range(maximum)]


def _polygon_points(raw, width=BASE_WIDTH, height=BASE_HEIGHT):
    if not isinstance(raw, list) or not 3 <= len(raw) <= 180:
        raise ValueError("Terrain polygon requires 3-180 points")
    result = []
    for p in raw:
        if not isinstance(p, dict):
            raise ValueError("Invalid terrain point")
        x, y = p.get("x"), p.get("y")
        if not all(isinstance(v, (float, int)) and math.isfinite(v) for v in (x, y)):
            raise ValueError("Invalid terrain coordinate")
        if not 0 <= x <= width or not 0 <= y <= height:
            raise ValueError("Terrain coordinate outside world")
        result.append([round(float(x), 3), round(float(y), 3)])
    return result


def _near_node(nodes, point, tolerance=3.0):
    matches = [(length(coord, point), key) for key, coord in nodes.items()
               if length(coord, point) <= tolerance]
    return min(matches)[1] if matches else None


# Strict source-type mapping: only validated editor props are added to the
# procedural world, never arbitrary runtime objects or client-provided flags.
EDITOR_PROP_STYLES = {
    "oak": ("tree", (7.0, 7.0), False),
    "pine": ("pine", (7.0, 7.0), False),
    "palm": ("palm", (6.5, 6.5), False),
    "bush": ("bush", (2.5, 2.5), False),
    "rock": ("rock", (3.0, 2.5), True),
    "boulder": ("rock", (4.5, 3.4), True),
    "house": ("house", (12.0, 17.0), True),
    "building": ("building", (22.0, 29.0), True),
    "warehouse": ("warehouse", (28.0, 37.0), True),
    "garage": ("garage", (20.0, 21.0), True),
    "gas_station": ("fuel", (18.0, 17.0), True),
    "streetlight": ("lamp", (1.3, 1.3), False),
    "sign": ("sign", (1.6, 1.4), False),
    "barrier": ("barrier", (3.0, 1.0), True),
    "parking": ("lot", (38.0, 28.0), False),
    "dock": ("dock", (3.0, 11.0), False),
    "parked_car": ("parked_car", (1.9, 4.6), True),
    "planter": ("planter", (2.8, 2.8), False),
    "garden": ("garden", (8.0, 2.4), False),
    "field": ("field", (90.0, 70.0), False),
    "island": ("island", (23.0, 23.0), True),
    "drag_prep": ("drag_prep", (8.5, 22.0), False),
    "drag_tree": ("drag_tree", (3.0, 10.0), False),
    "drag_lane_mark": ("drag_lane_mark", (.35, 12.0), False),
    "drag_scoreboard": ("drag_scoreboard", (4.0, 10.0), False),
    "grandstand": ("grandstand", (36.0, 17.0), True),
    "start_line": ("start_line", (14.0, 1.2), False),
    "finish_line": ("finish_line", (14.0, 1.2), False),
    "forecourt": ("forecourt", (23.0, 16.0), False),
}


def _authoring_props(doc, width=BASE_WIDTH, height=BASE_HEIGHT):
    """Convert a bounded list of editor scenery to stable runtime props."""
    import zlib

    items = doc.get("props", [])
    if not isinstance(items, list) or len(items) > 4000:
        raise ValueError("At most 4000 editor-authored props may be baked")
    ids = set()
    result = []
    for raw in items:
        if not isinstance(raw, dict):
            raise ValueError("Invalid authoring prop")
        item_id = raw.get("id")
        if not isinstance(item_id, str) or not re.fullmatch(r"prop-[a-zA-Z0-9_-]{1,50}", item_id):
            raise ValueError("Invalid stable editor prop ID")
        if item_id in ids:
            raise ValueError("Duplicate editor prop ID")
        ids.add(item_id)
        type_name = raw.get("type")
        if type_name not in EDITOR_PROP_STYLES:
            raise ValueError("Unsupported production scenery type: " + str(type_name))
        x, y, scale, rotation = (raw.get("x"), raw.get("y"),
                                 raw.get("scale"), raw.get("rotation"))
        if any(type(value) not in (int, float) or not math.isfinite(value)
               for value in (x, y, scale, rotation)):
            raise ValueError("Non-finite editor scenery properties")
        if not 3 <= x <= width-3 or not 3 <= y <= height-3:
            raise ValueError("Scenery outside safe Morrow Coast bounds")
        if not .2 <= scale <= 5 or not -360 <= rotation <= 360:
            raise ValueError("Editor prop scale or rotation out of range")
        game_art = raw.get("assetId", "")
        available = {
            "oak": {"tree", "pine", "palm"},
            "pine": {"tree", "pine", "palm"},
            "palm": {"tree", "pine", "palm"},
            "house": {"house", "coastal_house"},
            "building": {"shop", "garage"},
            "warehouse": {"shop", "garage"},
            "garage": {"shop", "garage"},
            "gas_station": {"shop", "garage"},
            "rock": {"rock"},
            "boulder": {"rock"},
        }
        project_path = raw.get("assetPath") if str(game_art).startswith("project-") else None
        if project_path is not None:
            building_file(project_path,ROOT)
            if game_art!=asset_id(project_path) or type_name not in {"house","building","warehouse","garage","gas_station"}:
                raise ValueError("Invalid project building artwork reference")
            asset_size=raw.get("assetSize")
            if not isinstance(asset_size,list) or len(asset_size)!=2 or any(type(v) not in (int,float) or not math.isfinite(v) or not 0<v<=100 for v in asset_size):
                raise ValueError("Invalid project building footprint")
        elif game_art:
            if (not isinstance(game_art, str) or not game_art.startswith("game-")
                    or game_art[5:] not in available.get(type_name, set())):
                raise ValueError("Only compatible game-folder atlas artwork is supported for Morrow props")
        kind, base_size, solid = EDITOR_PROP_STYLES[type_name]
        if project_path is not None:base_size=asset_size
        elif raw.get('replaces') and raw.get('assetSize') is not None:
            base_size=raw['assetSize']
            if not isinstance(base_size,list) or len(base_size)!=2 or any(type(v) not in (int,float) or not math.isfinite(v) or not 0<v<=1000 for v in base_size):
                raise ValueError('Invalid original scenery footprint')
        axes=[raw.get('scaleX',1),raw.get('scaleY',1)]
        if any(type(v) not in (int,float) or not math.isfinite(v) or not .2<=v<=5 for v in axes):
            raise ValueError('Invalid scenery axis scale')
        size = [round(v * scale * axis, 3) for v,axis in zip(base_size,axes)]
        radius = math.hypot(*size) / 2.0 if solid else 0.0
        seed = zlib.crc32(item_id.encode("utf-8")) & 0x7fffffff
        entry = dict(kind=kind,p=[round(x,3),round(y,3)],
                     size=size,angle=math.radians(rotation),
                     color="9dac94" if kind in {"tree","pine","palm","bush"} else "bdb9a7",
                     radius=radius,solid=solid,seed=seed,
                     authoring_id=item_id,editor_type=type_name,
                     editor_scale=scale,editor_name=str(raw.get("name", ""))[:80])
        entry.update(editor_scale_x=axes[0],editor_scale_y=axes[1],editor_base_size=list(base_size))
        if project_path is not None:
            entry["asset_path"]=project_path
            entry["asset_size"]=asset_size
            entry["asset_id"]=game_art
        elif game_art:
            entry["asset_kind"] = game_art[5:]
            entry["asset_id"] = game_art
        if raw.get("replaces") is not None:
            source = raw["replaces"]
            editable_types = {
                "tree": {"oak", "pine", "palm"}, "pine": {"oak", "pine", "palm"},
                "palm": {"oak", "pine", "palm"}, "rock": {"rock", "boulder"},
                "house": {"house"}, "coastal_house": {"house"},
                "lodge": {"house"},
                "shop": {"building", "warehouse", "garage", "gas_station"},
                "building": {"building", "warehouse", "garage", "gas_station"},
                "warehouse": {"building", "warehouse", "garage", "gas_station"},
                "garage": {"building", "warehouse", "garage", "gas_station"},
                "workshop": {"building", "warehouse", "garage", "gas_station"},
                "cafe": {"building"}, "office": {"building"},
                "hotel": {"building"},
                "showroom": {"building", "warehouse", "garage", "gas_station"},
                "fuel": {"building", "warehouse", "garage", "gas_station"},
                "bush": {"bush"},
                "lamp": {"streetlight"}, "sign": {"sign"},
                "barrier": {"barrier"}, "dock": {"dock"},
                "lot": {"parking"}, "forecourt": {"forecourt"},
                "parked_car": {"parked_car"}, "planter": {"planter"},
                "garden": {"garden"}, "field": {"field"},
                "island": {"island"},
                "drag_prep": {"drag_prep"},
                "drag_tree": {"drag_tree"},
                "drag_lane_mark": {"drag_lane_mark"},
                "drag_scoreboard": {"drag_scoreboard"},
                "grandstand": {"grandstand"},
                "start_line": {"start_line"},
                "finish_line": {"finish_line"},
            }
            if not isinstance(source, dict) or type_name not in editable_types.get(source.get("kind"), set()):
                raise ValueError("Replacement is not compatible with its source game scenery")
            src_seed, src_p = source.get("seed"), source.get("p")
            if (type(src_seed) is not int or not 0 <= src_seed <= 2147483647
                    or not isinstance(src_p, list) or len(src_p) != 2
                    or any(type(v) not in (int,float) or not math.isfinite(v) for v in src_p)
                    or not 0 <= src_p[0] <= width or not 0 <= src_p[1] <= height):
                raise ValueError("Invalid original scenery identity")
            entry["source_replacement"] = {
                "kind": source["kind"], "seed": src_seed,
                "p": [round(float(v),3) for v in src_p]
            }
            if raw.get("hidden") is not None and type(raw.get("hidden")) is not bool:
                raise ValueError("Invalid scenery visibility")
            entry["hidden"] = raw.get("hidden", False)
        if type_name == "parking":
            for field, raw_field, minimum, maximum, default in (
                ("stall_width", "stallWidth", 2.6, 5.2, 3.2),
                ("occupancy", "occupancy", 0.0, 1.0, .4),
                ("entrance_width", "entranceWidth", 6.0, 10.0, 8.0),
            ):
                value = raw.get(raw_field, default)
                if type(value) not in (int, float) or not math.isfinite(value) or not minimum <= value <= maximum:
                    raise ValueError("Invalid parking configuration: " + raw_field)
                entry[field] = round(float(value), 3)
        result.append(entry)
    return result


def apply_edits(roads, nodes, terrain, pois, spawn, props, filename=EDIT_PATH,
                width=BASE_WIDTH, height=BASE_HEIGHT, legacy_source_count=None,
                legacy_source_poi_count=None):
    """Mutate the source-builder collections once, before tessellation/props.

    This never reads or writes the 7.5 MB production JSON directly.
    Returns extra gameplay marker definitions for traffic spawn preferences.
    """
    filename = Path(filename)
    if not filename.is_file():
        return []
    if filename.stat().st_size > 8_000_000:
        raise ValueError("Morrow edit overlay exceeds 8 MB")
    doc = json.loads(filename.read_text(encoding="utf-8"))
    if doc.get("format") != "gdt.racing-world" or doc.get("version") != 2:
        raise ValueError("Invalid Morrow editor version: expected World Forge v2")
    doc_width, doc_height = validate_world_bounds(
        doc.get("world", {}).get("width"), doc.get("world", {}).get("height"))
    if (doc_width,doc_height)!=(width,height):
        raise ValueError("Map bounds mismatch between editor and production generator")
    source_count = len(roads)
    width_scale = doc.get("morrowRoadWidthScale", 1.0)
    if type(width_scale) not in (int,float) or width_scale not in (1.0,1.1):
        raise ValueError("Unsupported baked road-width scale.")
    basis_count = doc.get("morrowSourceRoadCount", legacy_source_count if legacy_source_count is not None else source_count)
    if type(basis_count) is not int or not 0 <= basis_count <= source_count:
        raise ValueError("Unsupported Morrow source-road layout. Reopen the game map.")
    poi_basis = doc.get("morrowSourcePoiCount", legacy_source_poi_count if legacy_source_poi_count is not None else len(pois))
    if type(poi_basis) is not int or not 0 <= poi_basis <= len(pois):
        raise ValueError("Unsupported Morrow destination layout. Reopen the game map.")
    road_edits = doc.get("roads")
    if not isinstance(road_edits, list) or len(road_edits) > 180:
        raise ValueError("Invalid Morrow road count")
    numbered = {}
    for entry in road_edits:
        match = re.fullmatch(r"road-(\d+)", str(entry.get("id", "")))
        if not match:
            raise ValueError("Road must retain stable road-<id> identifiers")
        index = int(match.group(1))
        # Old archives predate the coastal extension. Keep their added roads
        # after the new source records instead of treating a user's road-120
        # as the newly introduced north-coast highway. The persisted legacy
        # overlay remains valid; new imports carry the current basis count.
        if index >= basis_count:
            index += source_count - basis_count
        if index in numbered:
            raise ValueError("Duplicate road ID")
        numbered[index] = entry
    if any(i not in numbered for i in range(basis_count)):
        raise ValueError("A source Morrow Coast road was removed. Restore it: deleting a baked road requires a dedicated migration.")
    all_ids = set(numbered) | set(range(source_count))
    if len(all_ids) > 180:
        raise ValueError("Morrow roads exceed the editor limit after source-layout migration.")
    if sorted(all_ids) != list(range(len(all_ids))):
        raise ValueError("New Morrow Coast roads must have consecutive IDs; do not renumber originals.")

    proposed_nodes = {}
    edited = 0
    for index in range(source_count):
        if index not in numbered:
            continue  # Newly introduced defaults absent from a legacy overlay.
        road = roads[index]
        entry = numbered[index]
        fresh = points(entry["points"], width, height)
        baseline = [list(p) for p in road["anchors"]]
        unchanged = (len(fresh) == len(baseline) and
                     all(length(a, b) < 0.005 for a, b in zip(fresh, baseline)))
        if unchanged:
            # Some authored coastal nodes are calculated with full float
            # precision. The browser can round visually, but untouched
            # road anchors must retain the EXACT source coordinates.
            fresh = baseline
        else:
            edited += 1
        road["anchors"] = fresh
        road["name"] = str(entry.get("name", road["name"]))[:80]
        for name, old, new in ((road["start"], baseline[0], fresh[0]),
                               (road["end"], baseline[-1], fresh[-1])):
            if length(old, new) <= 0.05:
                continue
            # A split keeps the former endpoint for the second half. Likewise,
            # removing an endpoint detaches this road when its neighbors stay put.
            following = any(length(points(candidate["points"],width,height)[0],new)<.05 and
                            length(points(candidate["points"],width,height)[-1],old)<.05
                            for candidate_index,candidate in numbered.items() if candidate_index>=source_count)
            neighbor_stays = any(other["id"]!=index and
                any(other[end]==name and other["id"] in numbered and
                    length(points(numbered[other["id"]]["points"],width,height)[0 if end=="start" else -1],old)<.05
                    for end in ("start","end")) for other in roads)
            if following or neighbor_stays:
                detached=f"editor-detached-{index}-{'start' if name==road['start'] else 'end'}"
                road["start" if name==road["start"] else "end"]=detached
                nodes[detached]=tuple(new)
                continue
            previous = proposed_nodes.get(name)
            if previous is not None and length(previous, new) > 1.0:
                raise ValueError("Conflicting edits for shared road endpoint " + name + "; snap the endpoints first")
            proposed_nodes[name] = new
        road_width = entry.get("width", road["width"])
        lanes = entry.get("lanes", road["lanes"])
        if not isinstance(road_width, (int, float)) or not 6 <= road_width <= 160 or not isinstance(lanes, int) or not 1 <= lanes <= 6:
            raise ValueError("Invalid road width or lane count at road " + str(index))
        road["width"] = round(float(road_width) / width_scale, 9)
        road["lanes"] = int(lanes)
        klass = str(entry.get("roadClass", KIND_TO_CLASS.get(road["kind"])))
        if klass != KIND_TO_CLASS.get(road["kind"]):
            road["kind"] = CLASS_TO_KIND.get(klass, road["kind"])
        surf = str(entry.get("surface", road["surface"].lower())).upper()
        if surf not in {"ASPHALT", "CONCRETE", "TRACK", "DIRT", "GRAVEL"}:
            raise ValueError("Unknown road surface " + surf)
        road["surface"] = "ASPHALT" if surf in {"ASPHALT", "CONCRETE", "TRACK"} else surf
    for name, pos in proposed_nodes.items():
        nodes[name] = tuple(pos)
    for road in roads:
        road["anchors"][0] = list(nodes[road["start"]])
        road["anchors"][-1] = list(nodes[road["end"]])

    for index in range(source_count, len(all_ids)):
        entry = numbered[index]
        new_points = points(entry["points"], width, height)
        surf = str(entry.get("surface", "asphalt")).upper()
        if surf not in {"ASPHALT", "CONCRETE", "TRACK", "DIRT", "GRAVEL"}:
            raise ValueError("Unknown new-road surface " + surf)
        kind = CLASS_TO_KIND.get(str(entry.get("roadClass", "city")), "local")
        road_width = entry.get("width", 9.0)
        if type(road_width) not in (int,float) or not 6 <= road_width <= 160:
            raise ValueError("Invalid new-road width")
        if surf == "GRAVEL":
            kind = "gravel"
        loose = surf in LOOSE
        endpoint_names = []
        for end_idx, p in enumerate((new_points[0], new_points[-1])):
            near_name = _near_node(nodes, p)
            if near_name is not None:
                # Geometry nearest checks at crossings still allow T branches
                # against interior roads with a new synthetic endpoint.
                connected = any((r["start"] == near_name or r["end"] == near_name)
                                and (r["surface"] in LOOSE) == loose for r in roads)
                if not connected:
                    near_name = None
            if near_name is None:
                near_name = "editor_%d_%s" % (index, "start" if end_idx == 0 else "end")
                nodes[near_name] = tuple(p)
            endpoint_names.append(near_name)
        roads.append(dict(id=index, name=str(entry.get("name", "Editor Road"))[:80],
                          start=endpoint_names[0], end=endpoint_names[1],
                          kind=kind, width=round(float(road_width) / width_scale, 9),
                          surface="ASPHALT" if surf in {"ASPHALT", "CONCRETE", "TRACK"} else surf,
                          grade=0, anchors=new_points, points=[],
                          lanes=int(entry.get("lanes", 2))))
    # Terrain changes are applied ONLY when they differ from the sampled
    # source projection. This protects high-detail coastlines on an untouched
    # import, where the browser preview can display only 180 handles.
    base_terrain_count=len(terrain)
    for entry in doc.get("regions", []):
        match = re.fullmatch(r"region-(\d+)", str(entry.get("id", "")))
        if match is None:
            raise ValueError("Terrain must keep stable region-<id> identifiers")
        index = int(match.group(1))
        biome = str(entry.get("biome", "grass"))
        barrier=entry.get("barrier",False)
        elevation=entry.get("elevation",0)
        if type(barrier) is not bool or type(elevation) not in (int,float) or not math.isfinite(elevation) or not 0<=elevation<=2000:
            raise ValueError("Invalid mountain barrier or elevation setting")
        if barrier and (biome not in {"mountain","rock"} or elevation<5):
            raise ValueError("Solid mountain barriers need mountain/rock terrain and height of at least 5 metres")
        if index < base_terrain_count:
            original = _thin_polygon(terrain[index]["points"],width=width,height=height)
            new = _polygon_points(entry["points"],width,height)
            unchanged = len(original) == len(new) and all(length(a, b) < 0.02 for a, b in zip(original, new))
            source_kind=terrain[index]["kind"]
            source_biome="lake" if source_kind=="water" else "grass" if source_kind in {"town","highland"} else source_kind
            if not unchanged:
                terrain[index]["points"] = new
            if not unchanged or biome!=source_biome:
                terrain[index]["kind"] = "water" if biome == "lake" else biome
                terrain[index]["color"] = PALETTES.get(biome, terrain[index]["color"])
            target=terrain[index]
        else:
            target=dict(kind="water" if biome == "lake" else biome,
                                color=PALETTES.get(biome, PALETTES["grass"]),
                                points=_polygon_points(entry["points"],width,height),authoring_id=str(entry["id"]))
            terrain.append(target)
        if elevation>0:target["elevation"]=float(elevation)
        if barrier:
            from mountain_barriers import validate_polygon
            validate_polygon(target["points"])
            target["barrier"]=True;target["authoring_id"]=str(entry["id"])

    extra = []
    for marker in doc.get("markers", []):
        tag = str(marker.get("id", ""))
        marker_index = re.fullmatch(r"marker-(\d+)", tag)
        if marker_index and int(marker_index.group(1)) > poi_basis:
            marker = dict(marker, id="marker-%d" % (int(marker_index.group(1)) + len(pois) - poi_basis))
            tag = marker["id"]
        if tag == "marker-0":
            xy = (float(marker["x"]), float(marker["y"]))
            if length(xy, spawn["position"]) > 0.05:
                spawn["position"] = list(xy)
            angle = math.radians(float(marker.get("rotation", 0)))
            if abs(angle - spawn["rotation"]) > 0.0001:
                spawn["rotation"] = angle
            continue
        match = re.fullmatch(r"marker-(\d+)", tag)
        if match and 1 <= int(match.group(1)) <= len(pois):
            i = int(match.group(1)) - 1
            old = pois[i]["position"]
            target = (float(marker["x"]), float(marker["y"]))
            if length(old, target) > 0.05:
                shift = [target[k] - old[k] for k in (0, 1)]
                pois[i]["position"] = list(target)
                nodes["poi_%d" % i] = tuple(target)
                for r in roads:
                    if r["end"] == "poi_%d" % i:
                        r["anchors"][-1] = list(target)
                for prop in props:
                    if prop.get("poi") == pois[i]["name"] or (not prop["solid"] and
                        length(prop["p"], old) < 70 and prop["kind"] in ["lot", "forecourt"]):
                        prop["p"] = [round(prop["p"][k] + shift[k], 3) for k in (0, 1)]
        elif marker.get("type") in {"traffic_spawn", "race_start", "checkpoint", "finish"}:
            extra.append(dict(kind=marker["type"],name=str(marker.get("name", ""))[:80],
                              p=[float(marker["x"]), float(marker["y"])]))
    # Props participate in the same procedural occupancy, clearance
    # assertions and streamed chunk indexes as native Morrow scenery.
    authored = _authoring_props(doc,width,height)
    props.extend(authored)
    print(f"Morrow Coast editor overlay applied: {edited} roads edited, "
          f"{len(roads)-source_count} roads added, {len(proposed_nodes)} shared nodes moved")
    return extra
