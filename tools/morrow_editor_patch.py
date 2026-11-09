"""Validate/replay non-destructive Morrow Coast road patches BEFORE baking indexes.

The editable browser map never overwrites worlds/morrow-coast.world.json.
A patch changes original road control points/width only when existing
shared endpoints remain untouched; added roads are explicit and validated.
All collisions, junctions, bridges, props, chunks and traffic lanes are then
recomputed by build_morrow_coast.py from the adjusted source roads.
"""
import json
import math
from pathlib import Path

FORMAT = "streetbound.morrow-editor-patch"
KINDS = {"local", "arterial", "highway", "rural", "mountain",
         "track", "driveway", "gravel"}
SURFACES = {"ASPHALT", "GRAVEL"}


def _points(raw, width, height):
    if not isinstance(raw, list) or not 2 <= len(raw) <= 100:
        raise ValueError("Road needs 2 to 100 control points")
    result = []
    for p in raw:
        if not isinstance(p, list) or len(p) != 2:
            raise ValueError("Invalid road control point")
        if not all(isinstance(v, (int, float)) and math.isfinite(v) for v in p):
            raise ValueError("Non-finite road coordinate")
        if not 0 <= p[0] <= width or not 0 <= p[1] <= height:
            raise ValueError("Road point outside Morrow Coast")
        if result and math.dist(result[-1], p) < 0.05:
            raise ValueError("Repeated road handle or zero-length segment")
        result.append([float(p[0]), float(p[1])])
    if math.dist(result[0], result[-1]) < 0.1 and len(result) == 2:
        raise ValueError("Zero-length road")
    return result


def apply_road_patch(path, roads, nodes, width, height):
    path = Path(path)
    if not path.is_file():
        return {"updated": 0, "added": 0}
    patch = json.loads(path.read_text(encoding="utf-8"))
    if patch.get("format") != FORMAT or patch.get("version") != 1:
        raise ValueError("Invalid Morrow road patch format/version")
    expected = int(patch.get("baseline", {}).get("road_count", -1))
    if expected != len(roads):
        raise ValueError(f"Morrow patch is stale: expected {expected} original roads, actual {len(roads)}")
    if patch.get("baseline", {}).get("world_name") != "Morrow Coast":
        raise ValueError("Patch targets a different world")
    changed = patch.get("updated_roads", [])
    added = patch.get("new_roads", [])
    if not isinstance(changed, list) or not isinstance(added, list) or len(added) > 40:
        raise ValueError("Invalid road modification count")
    # Apply atomically after validating all entries. An invalid patch must
    # never partially overwrite the in-memory base road list.
    working = [dict(r, anchors=list(r["anchors"])) for r in roads]
    seen = set()
    for item in changed:
        rid = item.get("road_id")
        if type(rid) is not int or rid < 0 or rid >= expected or rid in seen:
            raise ValueError("Invalid or duplicated baseline road ID")
        seen.add(rid)
        road = working[rid]
        if item.get("name") != road["name"]:
            raise ValueError("Patch road names no longer match source")
        anchors = _points(item.get("anchors"), width, height)
        if math.dist(anchors[0], nodes[road["start"]]) > 0.2 or math.dist(anchors[-1], nodes[road["end"]]) > 0.2:
            raise ValueError(f"Shared endpoints of {road['name']} cannot be moved by this patch")
        w = item.get("width")
        lanes = item.get("lanes")
        kind, surface = item.get("kind"), item.get("surface")
        if type(w) not in (int, float) or not math.isfinite(w) or not 6 <= w <= 32:
            raise ValueError("Invalid road width")
        if type(lanes) is not int or not 1 <= lanes <= 6:
            raise ValueError("Invalid lane count")
        if kind not in KINDS or surface not in SURFACES:
            raise ValueError("Invalid road kind/surface")
        road.update(anchors=anchors, width=float(w), lanes=lanes, kind=kind, surface=surface)
    extra = []
    extra_nodes = {}
    for i, item in enumerate(added):
        anchors = _points(item.get("anchors"), width, height)
        w, lanes = item.get("width"), item.get("lanes")
        kind, surface = item.get("kind"), item.get("surface")
        if type(w) not in (int, float) or not math.isfinite(w) or not 6 <= w <= 32:
            raise ValueError("Invalid added road width")
        if type(lanes) is not int or not 1 <= lanes <= 6:
            raise ValueError("Invalid added road lane count")
        if kind not in KINDS or surface not in SURFACES:
            raise ValueError("Invalid added road kind/surface")
        start, end = f"editor_{i}_start", f"editor_{i}_end"
        if start in nodes or end in nodes:
            raise ValueError("Editor-generated node name already exists")
        extra_nodes[start] = tuple(anchors[0])
        extra_nodes[end] = tuple(anchors[-1])
        name = str(item.get("name") or f"Editor road {i+1}")[:80]
        extra.append(dict(id=len(roads)+i, name=name,
                          start=start, end=end, kind=kind, surface=surface,
                          width=float(w), grade=0, anchors=anchors, points=anchors[:],
                          lanes=lanes))
    # No changes until the entire document has passed validation.
    roads[:] = working + extra
    nodes.update(extra_nodes)
    return {"updated": len(changed), "added": len(added)}
