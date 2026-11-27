"""Validate physical roadway migration without touching any car."""
import copy
import json
import math
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from road_widths import adapt, ROAD_WIDTH_SCALE, SCENERY_FACTORS, junction_clearance_polygon

ROOT = Path(__file__).resolve().parents[1]
data = json.loads((ROOT / "worlds" / "morrow-coast.world.json").read_text(encoding="utf-8"))
adapt(data)  # Legacy checked-in maps receive this same migration at load.
assert math.isclose(data["road_width_scale"], 1.265)
assert len(data["roads"]) > 60
assert all(r["width"] > 0 for r in data["roads"])
by_kind = {}
for r in data["roads"]:
    by_kind.setdefault(r["kind"], []).append(r["width"])
for kind, width in {"local": 9*1.265, "arterial": 12*1.265,
                    "highway": 18*1.265, "track": 14*1.265}.items():
    assert any(abs(x-width) < .005 for x in by_kind[kind]), (kind, by_kind[kind][:4])
assert all(math.isclose(bridge["width"], data["roads"][bridge["road"]]["width"], abs_tol=.01)
           for bridge in data["bridges"])
assert all(math.isclose(arm["width"], data["roads"][arm["road"]]["width"], abs_tol=.01)
           for j in data["junctions"] for arm in j["approaches"])
before=copy.deepcopy(data)
adapt(data)
assert data == before, "Widening the newly baked archive twice corrupts geometry"
assert SCENERY_FACTORS["building"] < 1
assert "parked_car" not in SCENERY_FACTORS
assert "garage" not in SCENERY_FACTORS
assert "lot" not in SCENERY_FACTORS
assert "forecourt" not in SCENERY_FACTORS
# A synthetic source example ensures both the input and output preserve
# vehicles and garage dimensions while changing static scenery footprints.
fixture = {"roads":[{"width":10.0}], "bridges":[{"width":10.0}],
           "junctions":[{"p":[0.0,0.0],"polygon":[[10.0,0.0],[0.0,10.0]],
                         "curbs":[[[10.0,0.0],[0.0,10.0]]],
                         "approaches":[{"width":10.0}], "radius":12.0}],
           "props":[{"kind":"building","size":[20.0,30.0],"radius":18.0},
                    {"kind":"parked_car","size":[2.0,5.0],"radius":3.0},
                    {"kind":"garage","size":[30.0,25.0],"radius":20.0},
                    {"kind":"house","authoring_id":"prop-test","size":[19.0,11.0],"radius":12.0}]}
reserved_polygon = junction_clearance_polygon(fixture["junctions"][0])
adapt(fixture)
assert fixture["junctions"][0]["polygon"] == reserved_polygon
assert fixture["roads"][0]["width"] == 12.65
assert fixture["bridges"][0]["width"] == 12.65
assert fixture["junctions"][0]["approaches"][0]["width"] == fixture["roads"][0]["width"]
assert all(math.isclose(a, b) for a, b in zip(fixture["props"][0]["size"], [18.8,28.2]))
assert fixture["props"][1]["size"] == [2.0,5.0]
assert fixture["props"][2]["size"] == [30.0,25.0]
assert fixture["props"][3]["size"] == [19.0,11.0]
adapt(fixture)
assert fixture["roads"][0]["width"] == 12.65
# Migration of a previously 10%-widened archive must not shrink its scenery
# twice, and must update coverage into newly touched cells.
legacy = {"road_width_scale":1.1,"roads":[{"width":110.0}],
          "bridges":[],"junctions":[],"props":[{"kind":"building","size":[18.8,28.2]}],
          "segments":[{"a":[130,100],"b":[130,110],"road":0}],
          "surface_cell":64,"chunk_size":192,"surface_index":{},
          "chunks":{"0,0":{"segments":[],"props":[0]},"1,0":{"segments":[],"props":[]}}}
adapt(legacy)
assert math.isclose(legacy["roads"][0]["width"],126.5)
assert legacy["props"][0]["size"] == [18.8,28.2]
assert legacy["chunks"]["1,0"]["segments"] == [0]
assert legacy["chunks"]["0,0"]["props"] == [0]
assert legacy["surface_index"]["3,1"] == [0]
snapshot=copy.deepcopy(legacy)
adapt(legacy)
assert legacy == snapshot
custom={"editor_custom_test_drive":True,"road_width_scale":1.1,"roads":[{"width":9}]}
adapt(custom)
assert custom["roads"][0]["width"] == 9
print("MORROW ROAD WIDTH REBAKE: PASS")
