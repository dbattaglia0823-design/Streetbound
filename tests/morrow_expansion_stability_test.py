"""Live production growth regression: never relocate or regenerate old Morrow.
Runs after CI generated the unchanged base map. Backup + restore every artifact.
"""
import copy
import json
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from morrow_editor_import import validate_world_bounds
from map_editor_server import BAKED, OVERVIEW, EDIT

def grow(overlay,width,height):
    payload=copy.deepcopy(overlay)
    payload["world"]["width"]=width
    payload["world"]["height"]=height
    EDIT.parent.mkdir(parents=True,exist_ok=True)
    EDIT.write_text(json.dumps(payload),encoding="utf-8")
    run=subprocess.run([sys.executable,str(ROOT/"tools"/"build_morrow_coast.py")],
                       cwd=ROOT,capture_output=True,text=True,timeout=240)
    if run.returncode:
        raise AssertionError(f"Growth failed: {run.stderr[-3000:]}")
    return json.loads(BAKED.read_text(encoding="utf-8"))

def invariant(old,new,old_size):
    assert new["size"][0]>=old["size"][0] and new["size"][1]>=old["size"][1]
    for field in ("roads","nodes","segments","pois","spawn","districts",
                  "junctions","road_connections","road_crossings"):
        if old[field] != new[field]:
            if field == "roads":
                left,right=old[field],new[field]
                for i,(a,b) in enumerate(zip(left,right)):
                    if a!=b:
                        differing=[key for key in a if a.get(key)!=b.get(key)]
                        raise AssertionError(
                            f"Existing road {i} changed when growing: "
                            f"{a.get('name')} fields={differing}; "
                            f"old={{{', '.join(repr(k)+': '+repr(a.get(k))[:350] for k in differing)}}}, "
                            f"new={{{', '.join(repr(k)+': '+repr(b.get(k))[:350] for k in differing)}}}")
                raise AssertionError(f"Existing roads length changed: "
                    f"{len(left)} -> {len(right)}")
            raise AssertionError(f"Existing {field} changed when growing!")
    baseline_masks=[t for t in old["terrain"] if not t.get("generated_extension")]
    assert new["terrain"][:len(baseline_masks)]==baseline_masks,\
        "Original authored terrain masks changed"
    assert new["props"][:len(old["props"])]==old["props"],\
        "Pre-existing buildings or vegetation were regenerated!"
    for p in new["props"][len(old["props"]):]:
        if not p.get("authoring_id"):
            assert p["p"][1]>=4800, "New procedural scenery leaked into original world"
    assert new["original_extent"] == [6400,4800]

def run_test():
    validate_world_bounds(6400,4800)
    validate_world_bounds(9600,7200)
    for invalid in [(6300,4800),(6400,4700),(9601,4800),(6400,7201),
                    (6400.2,4800),(True,4800)]:
        try:
            validate_world_bounds(*invalid)
        except ValueError: pass
        else: raise AssertionError("Accepted unsafe expansion dimensions")
    overlay_path=Path("/tmp/morrow-edit-roundtrip.json")
    if not overlay_path.exists():
        raise AssertionError("The prior CI source-roundtrip step must run first")
    source=json.loads(overlay_path.read_text(encoding="utf-8"))
    originals={path:path.read_bytes() if path.exists() else None
               for path in (BAKED,OVERVIEW,EDIT)}
    try:
        baseline=json.loads(BAKED.read_text(encoding="utf-8"))
        assert baseline["size"]==[6400,4800],baseline["size"]
        first=grow(source,7200,5600)
        invariant(baseline,first,[6400,4800])
        assert any(t.get("generated_extension") for t in first["terrain"])
        assert any(p["p"][1]>=4800 for p in first["props"])
        second=grow(source,8200,6400)
        invariant(baseline,second,[6400,4800])
        assert second["props"][:len(first["props"])]==first["props"],\
            "A second expansion shuffled previously-generated objects"
        print("MORROW EXPANSION: PASS: original roads, terrain, buildings, seeds, POIs, "+
              "and scenery positions all identical after TWO expansions")
    finally:
        for path,data in originals.items():
            if data is None:path.unlink(missing_ok=True)
            else:path.write_bytes(data)

if __name__=="__main__":
    run_test()
