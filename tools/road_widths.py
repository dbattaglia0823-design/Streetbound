"""Deterministic, idempotent wider-road adaptation for Morrow Coast.

The existing seven-megabyte game archive is migrated at runtime in GDScript;
subsequent source rebuilds apply exactly the SAME transform on serialization.
This deliberately preserves all authored centerlines, POIs and prop positions
so the cached streaming indexes, traffic connectivity and garage entrances
remain valid without regenerating players' world layout.
"""
LEGACY_WIDTH_SCALE = 1.10
ROAD_WIDTH_SCALE = 1.265
JUNCTION_APRON_SCALE = 1.2075
SCENERY_FACTORS = {
    "house": .94, "coastal_house": .94, "building": .94, "shop": .94,
    "warehouse": .94, "lodge": .94, "office": .94, "hotel": .94,
    "cafe": .94, "showroom": .94,
    "tree": .92, "pine": .92, "palm": .92,
    "bush": .92, "rock": .92, "planter": .92,
    "garden": .95,
}


def _outward(point, center, ratio):
    return [round(center[k] + (point[k] - center[k]) * ratio, 9)
            for k in (0, 1)]


def adapt(world):
    if world.get("editor_custom_test_drive"):
        return world
    previous = float(world.get("road_width_scale", 1.0))
    if abs(previous - ROAD_WIDTH_SCALE) < 1e-8:
        return world
    ratio = ROAD_WIDTH_SCALE / previous
    apron_ratio = JUNCTION_APRON_SCALE / (1.05 if abs(previous - LEGACY_WIDTH_SCALE) < 1e-8 else 1.0)
    for road in world["roads"]:
        road["width"] = round(float(road["width"]) * ratio, 3)
    for bridge in world.get("bridges", []):
        bridge["width"] = round(float(bridge["width"]) * ratio, 3)
    for junction in world.get("junctions", []):
        center = junction["p"]
        junction["polygon"] = [_outward(p, center, apron_ratio) for p in junction["polygon"]]
        junction["curbs"] = [[_outward(p, center, apron_ratio) for p in curve]
                             for curve in junction.get("curbs", [])]
        for approach in junction.get("approaches", []):
            approach["width"] = float(approach["width"]) * ratio
        junction["radius"] = float(junction["radius"]) * apron_ratio
    # Keep parking bays, drag timing decals, garages, barriers, and vehicles
    # their exact original size. Static building/foliage assets alone get
    # proportionally smaller physical AND visual bounds.
    for prop in world["props"]:
        if previous >= LEGACY_WIDTH_SCALE or prop.get("asset_path") or prop.get("authoring_id"):
            continue  # Project artwork already has an explicit matching visual/collision footprint.
        factor = SCENERY_FACTORS.get(prop["kind"], 1.0)
        if factor == 1.0:
            continue
        if "size" in prop:
            prop["size"] = [float(dimension) * factor for dimension in prop["size"]]
        if "radius" in prop:
            prop["radius"] = float(prop["radius"]) * factor
    _reindex_roads(world)
    world["road_width_scale"] = ROAD_WIDTH_SCALE
    return world


def _reindex_roads(world):
    """Refresh widened segment coverage without changing any other memberships."""
    if not all(key in world for key in ("surface_index", "chunks", "segments")):
        return
    from math import floor
    surface, chunks = world["surface_index"], world["chunks"]
    surface.clear()
    for chunk in chunks.values():
        chunk["segments"] = []
    for index, segment in enumerate(world["segments"]):
        a, b = segment["a"], segment["b"]
        radius = world["roads"][segment["road"]]["width"] * .5
        for size, pad, is_surface in ((world["surface_cell"], radius+12, True),
                                       (world["chunk_size"], radius+8, False)):
            low = [floor((min(a[k], b[k])-pad)/size) for k in (0,1)]
            high = [floor((max(a[k], b[k])+pad)/size) for k in (0,1)]
            for x in range(low[0], high[0]+1):
                for y in range(low[1], high[1]+1):
                    key = f"{x},{y}"
                    if is_surface:
                        surface.setdefault(key, []).append(index)
                    elif key in chunks:
                        chunks[key]["segments"].append(index)
