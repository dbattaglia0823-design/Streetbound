#!/usr/bin/env python3
"""Prove native guardrail paths survive the Morrow production scenery importer.

Guardrail bodies are built by Godot from the preserved path. They must NOT
become giant rectangular scenery collision around their overall bounding box.
"""
import copy
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from morrow_editor_import import _authoring_props  # noqa: E402
from road_auto_guardrails import props_for, set_auto_guardrails

SAMPLE = {
    "id": "prop-guardrail-fixture-1",
    "name": "Solid roadside guardrail",
    "type": "guardrail",
    "assetId": "",
    "x": 200.0,
    "y": 300.0,
    "rotation": 0,
    "scale": 1.0,
    "assetSize": [120.65, 40.65],
    "guardrailWidth": 0.65,
    "guardrailPoints": [[-60.0, -20.0], [0.0, -20.0], [60.0, 20.0]],
}


def bake(source):
    return _authoring_props({"props": [source]}, 800, 800)


def expect_invalid(source, reason):
    try:
        bake(source)
    except (ValueError, TypeError):
        return
    raise AssertionError(f"Invalid guardrail was accepted: {reason}")


def main():
    rail = bake(SAMPLE)[0]
    assert rail["kind"] == "guardrail"
    assert rail["authoring_id"] == SAMPLE["id"]
    assert rail["guardrail_points"] == SAMPLE["guardrailPoints"]
    assert rail["guardrail_width"] == 0.65
    assert rail["guardrail_scale"] == [1, 1]
    assert rail["radius"] == 0 and rail["solid"] is False, (
        "Guardrails use per-path hitboxes, not the huge prop bounding box"
    )
    assert len(bake(SAMPLE)) == 1
    scaled = copy.deepcopy(SAMPLE)
    scaled.update(scale=1.5, scaleX=0.8, scaleY=1.2, rotation=35)
    transformed = bake(scaled)[0]
    assert transformed["guardrail_scale"] == [1.5 * 0.8, 1.5 * 1.2]
    assert math.isclose(transformed["angle"], math.radians(35))
    for name, patch in (
        ("too wide", {"guardrailWidth": 4.0}),
        ("too narrow", {"guardrailWidth": 0.2}),
        ("outside bounds", {"x": -10}),
        ("nonfinite point", {"guardrailPoints": [[-60, -20], [float("nan"), 0]]}),
        ("duplicate points", {"guardrailPoints": [[0, 0], [0.1, 0.1]]}),
        ("only one point", {"guardrailPoints": [[0, 0]]}),
    ):
        candidate = copy.deepcopy(SAMPLE)
        candidate.update(patch)
        expect_invalid(candidate, name)
    road=dict(id=0,width=10,points=[[100,300],[700,300]])
    set_auto_guardrails(road,{"autoGuardrails":{"left":[10,90],"right":[0,25]}})
    crossing=dict(id=1,width=10,points=[[400,100],[400,500]])
    j=dict(p=[400,300],radius=12)
    auto=props_for([road,crossing],[j],800,800)
    assert auto and len(_authoring_props({"props":auto},800,800))==len(auto)
    left=[p for p in auto if "-left-" in p["id"]]
    right=[p for p in auto if "-right-" in p["id"]]
    assert left and right
    for p in left+right:
        pts=[(p["x"]+x,p["y"]+y) for x,y in p["guardrailPoints"]]
        assert all(abs(x-400)>12 for x,y in pts)
        assert all(y<300 and 160<=x<=640 for x,y in pts) if p in left else all(y>300 and 100<=x<=250 for x,y in pts)
        assert not any(min(a[0],b[0])<400<max(a[0],b[0]) for a,b in zip(pts,pts[1:]))
    assert len(props_for([dict(road,autoGuardrails={})],[j],800,800))==0
    elevated=dict(crossing,elevation={"start_layer":1,"end_layer":1})
    assert any(abs(p["x"]+x-400)<2 for p in props_for([road,elevated],[],800,800) for x,y in p["guardrailPoints"])
    print("GUARDRAIL PRODUCTION BAKE: PASS (geometry, scale, independent collision, invalid paths)")


if __name__ == "__main__":
    main()
