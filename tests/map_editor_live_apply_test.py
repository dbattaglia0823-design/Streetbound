"""End-to-end: import actual game source, adopt a procedural tree, live apply
and hide it through the production Python map builder, then restore fixtures.
"""
import json
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from map_editor_server import BAKED, EDIT, OVERVIEW, digest, transactional_rebuild


def main():
    source=Path("/tmp/morrow-edit-roundtrip.json")
    if not source.exists():
        raise AssertionError("Generate the World Forge source in the preceding CI step")
    doc=json.loads(source.read_text(encoding="utf-8"))
    raw=json.loads(BAKED.read_text(encoding="utf-8"))
    item=next((p for p in raw["props"]
               if p["kind"] in {"tree","pine"} and p.get("solid")
               and "authoring_id" not in p
               and all(200 < v < boundary-200 for v,boundary in zip(p["p"],[6400,4800]))
               and isinstance(p.get("seed"),int)),None)
    if item is None:
        raise AssertionError("Cannot find an existing game tree to edit")
    source_id="prop-990001"
    game_prop={
        "id":source_id, "name":"Adopted native game tree",
        "type":"oak" if item["kind"]=="tree" else "pine",
        "x":float(item["p"][0]),"y":float(item["p"][1]),"scale":1,
        "rotation":float(item["angle"])*180/3.141592653589793,
        "assetId":"game-pine", "hidden":False,
        "replaces":{"kind":item["kind"],"seed":item["seed"],"p":item["p"]},
    }
    doc["props"].append(game_prop)
    originals={path:path.read_bytes() if path.exists() else None
               for path in (BAKED,EDIT,OVERVIEW)}
    try:
        output=transactional_rebuild(doc,digest(BAKED))
        assert output["ok"]
        changed=json.loads(BAKED.read_text(encoding="utf-8"))
        adopted=[p for p in changed["props"] if p.get("authoring_id")==source_id]
        assert len(adopted)==1,"Adopted object missing from playable world"
        assert adopted[0]["asset_kind"]=="pine","Runtime artwork override not baked"
        assert adopted[0]["solid"],"The original tree-trunk collider was lost"
        assert not any(p.get("kind")==item["kind"] and p.get("seed")==item["seed"]
                       and p.get("p")==item["p"] and not p.get("authoring_id")
                       for p in changed["props"]),"Original object duplicated"
        doc["props"][-1]["hidden"]=True
        result=transactional_rebuild(doc,digest(BAKED))
        assert result["ok"]
        hidden=json.loads(BAKED.read_text(encoding="utf-8"))
        assert not any(p.get("authoring_id")==source_id for p in hidden["props"])
        assert not any(p.get("kind")==item["kind"] and p.get("seed")==item["seed"]
                       and p.get("p")==item["p"] and not p.get("authoring_id")
                       for p in hidden["props"]),"Hidden original still exists"
        print("LIVE MAP APPLY: adopted, retextured, replaced, collision kept, hidden: PASS")
    finally:
        for path,previous in originals.items():
            if previous is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(previous)


if __name__=="__main__":
    main()
