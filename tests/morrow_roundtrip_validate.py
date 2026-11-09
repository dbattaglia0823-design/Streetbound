"""Cross-language invariant: importing then exporting the real Morrow map
must not modify its high-detail terrain, road anchors or POI source data."""
import copy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from morrow_editor_import import apply_edits


def main(source_file):
    raw = json.loads((ROOT / "worlds/morrow-coast.world.json").read_text())
    roads = copy.deepcopy(raw["roads"])
    nodes = copy.deepcopy(raw["nodes"])
    terrain = copy.deepcopy(raw["terrain"])
    pois = copy.deepcopy(raw["pois"])
    spawn = copy.deepcopy(raw["spawn"])
    props = copy.deepcopy(raw["props"])
    original = (copy.deepcopy(roads), copy.deepcopy(nodes),
                copy.deepcopy(terrain), copy.deepcopy(pois),
                copy.deepcopy(spawn), copy.deepcopy(props))
    added = apply_edits(roads, nodes, terrain, pois, spawn, props,
                        filename=source_file)
    assert not added, "Read-only round trip should not create new gameplay markers"
    changed = []
    for name, left, right in zip(
            ["roads", "nodes", "terrain", "pois", "spawn", "props"],
            original, [roads, nodes, terrain, pois, spawn, props]):
        if left != right:
            changed.append(name)
    assert not changed, (
        "Unedited Map Builder round trip changed " + ", ".join(changed) +
        ". Refusing to silently bake altered Morrow geometry."
    )
    print("Morrow Coast no-edit authoring round trip: PASS ("
          f"{len(roads)} roads, {len(terrain)} terrain masks, "
          f"{len(props)} original generated props preserved)")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python tests/morrow_roundtrip_validate.py <editor snapshot.json>")
    main(Path(sys.argv[1]))
