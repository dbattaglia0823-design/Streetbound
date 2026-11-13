"""Deterministic, idempotent 10%-wider-road adaptation for Morrow Coast.

The existing seven-megabyte game archive is migrated at runtime in GDScript;
subsequent source rebuilds apply exactly the SAME transform on serialization.
This deliberately preserves all authored centerlines, POIs and prop positions
so the cached streaming indexes, traffic connectivity and garage entrances
remain valid without regenerating players' world layout.
"""
ROAD_WIDTH_SCALE = 1.10
JUNCTION_APRON_SCALE = 1.05
SCENERY_FACTORS = {
    "house": .94, "coastal_house": .94, "building": .94, "shop": .94,
    "warehouse": .94, "lodge": .94, "office": .94, "hotel": .94,
    "cafe": .94, "showroom": .94,
    "tree": .92, "pine": .92, "palm": .92,
    "bush": .92, "rock": .92, "planter": .92,
    "garden": .95,
}


def _outward(point, center):
    return [round(center[k] + (point[k] - center[k]) * JUNCTION_APRON_SCALE, 9)
            for k in (0, 1)]


def adapt(world):
    if abs(float(world.get("road_width_scale", 1.0)) - ROAD_WIDTH_SCALE) < 1e-8:
        return world
    for road in world["roads"]:
        road["width"] = round(float(road["width"]) * ROAD_WIDTH_SCALE, 3)
    for bridge in world.get("bridges", []):
        bridge["width"] = round(float(bridge["width"]) * ROAD_WIDTH_SCALE, 3)
    for junction in world.get("junctions", []):
        center = junction["p"]
        junction["polygon"] = [_outward(p, center) for p in junction["polygon"]]
        junction["curbs"] = [[_outward(p, center) for p in curve]
                             for curve in junction.get("curbs", [])]
        for approach in junction.get("approaches", []):
            approach["width"] = float(approach["width"]) * ROAD_WIDTH_SCALE
        junction["radius"] = float(junction["radius"]) * JUNCTION_APRON_SCALE
    # Keep parking bays, drag timing decals, garages, barriers, and vehicles
    # their exact original size. Static building/foliage assets alone get
    # proportionally smaller physical AND visual bounds.
    for prop in world["props"]:
        if prop.get("asset_path"):
            continue  # Project artwork already has an explicit matching visual/collision footprint.
        factor = SCENERY_FACTORS.get(prop["kind"], 1.0)
        if factor == 1.0:
            continue
        if "size" in prop:
            prop["size"] = [float(dimension) * factor for dimension in prop["size"]]
        if "radius" in prop:
            prop["radius"] = float(prop["radius"]) * factor
    world["road_width_scale"] = ROAD_WIDTH_SCALE
    return world
