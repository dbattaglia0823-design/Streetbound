"""World-level checks for built Morrow Coast art and topology."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
world = json.loads((ROOT / "worlds/morrow-coast.world.json").read_text())
roads = world["roads"]
props = world["props"]
pois = world["pois"]

coastal = [r for r in roads if r["name"] == "Coastal Meridian Highway"]
assert len(coastal) == 10, f"Expected ten continuous coastal highway segments, got {len(coastal)}"
assert all(r["kind"] == "highway" and r["lanes"] == 4 for r in coastal)
assert len({r["id"] for r in coastal}) == len(coastal)
ordered = sorted(coastal, key=lambda r: r["anchors"][0][1])
assert ordered[0]["anchors"][0][1] < 150
assert ordered[-1]["anchors"][-1][1] > 4600
for a, b in zip(ordered, ordered[1:]):
    start = a["anchors"][-1]
    end = b["anchors"][0]
    assert math.dist(start, end) < 0.1, f"Disconnected coastal highway at {start} / {end}"
    assert math.dist(a["points"][-1], b["points"][0]) < 0.2

for name in ("North Meridian Travel Stop", "Juniper Mountain Fuel", "Southern Coast Service"):
    poi = [p for p in pois if p["name"] == name]
    assert len(poi) == 1, f"Missing or duplicated roadside fuel stop: {name}"
    assert any(p.get("poi") == name and p.get("kind") == "fuel" for p in props)

corn = [p for p in props if p["kind"] == "cornfield"]
assert len(corn) >= 10, f"Expected western maize acreage, got {len(corn)}"
assert all(p["p"][0] < 1600 for p in corn)
assert any(p["kind"] == "drag_tree" for p in props)
assert sum(p["kind"] == "barrier" for p in props) >= 24

circuit = [r for r in roads if r["name"] == "Ashford Grand Circuit"]
assert len(circuit) == 4 and all(r["kind"] == "track" for r in circuit)
assert sum(len(r["anchors"]) for r in circuit) >= 22
assert len([r for r in roads if r["name"] == "Ashford Drag Strip"]) == 1
assert len([p for p in props if p["kind"] in
            {"house", "coastal_house", "shop", "building", "warehouse"}]) >= 150
assert (ROOT / "scripts/world/coast_water.gdshader").is_file()
assert "Coastal" in world["name"] or "Morrow" in world["name"]
print("MORROW COAST OVERHAUL: PASS")
print(f"Highway segments: {len(coastal)} | Corn parcels: {len(corn)} | "
      f"City/house roofs: {sum(p['kind'] in {'house','shop','building','warehouse','coastal_house'} for p in props)}")
