"""No third-party packages; checks the World Forge-to-Morrow source bridge."""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from morrow_editor_import import apply_edits


def fixture():
    roads = [
        dict(id=0, name="West Road", start="a", end="b",
             anchors=[[100, 200], [500, 200]], kind="local",
             surface="ASPHALT", width=9.0, lanes=2, points=[]),
        dict(id=1, name="East Road", start="b", end="c",
             anchors=[[500, 200], [900, 200]], kind="arterial",
             surface="ASPHALT", width=12.0, lanes=2, points=[]),
    ]
    nodes = {"a": (100, 200), "b": (500, 200),
             "c": (900, 200), "poi_0": (100, 150)}
    terrain = [dict(kind="ocean", color="82b5b5",
                    points=[[1400, 200], [1600, 200],
                            [1600, 1100], [1400, 1100]])]
    pois = [dict(name="Garage", position=[100, 150], road=0)]
    spawn = dict(position=[100, 150], rotation=0)
    props = [dict(kind="garage", p=[100, 150], poi="Garage",
                  solid=True, radius=10)]
    return roads, nodes, terrain, pois, spawn, props


def editor_doc():
    return dict(format="gdt.racing-world", version=2, name="Morrow Coast",
                world=dict(width=6400, height=4800),
                roads=[
                    dict(id="road-0", name="West Road", roadClass="city",
                         surface="asphalt", width=9, lanes=2,
                         points=[dict(x=100, y=200), dict(x=500, y=200)]),
                    dict(id="road-1", name="East Road", roadClass="city",
                         surface="asphalt", width=12, lanes=2,
                         points=[dict(x=500, y=200), dict(x=900, y=200)]),
                ],
                regions=[dict(id="region-0", name="Ocean", biome="ocean",
                              points=[dict(x=x, y=y) for x, y in
                                      [[1400, 200], [1600, 200],
                                       [1600, 1100], [1400, 1100]]])],
                markers=[dict(id="marker-0", type="player_spawn", x=100, y=150,
                              rotation=0)])


class SourceBridgeTests(unittest.TestCase):
    def apply(self, doc, base=None):
        data = copy.deepcopy(base or fixture())
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "edits.json"
            source.write_text(json.dumps(doc), encoding="utf-8")
            extras = apply_edits(*data, filename=source)
        return data, extras

    def test_unchanged_round_trip_does_not_reduce_coastal_data(self):
        original = fixture()
        result, markers = self.apply(editor_doc(), original)
        self.assertEqual(result[0], original[0])
        self.assertEqual(result[2], original[2])
        self.assertEqual(result[4], original[4])
        self.assertEqual(markers, [])

    def test_shared_node_move_propagates_and_adds_connected_road(self):
        doc = editor_doc()
        doc["roads"][0]["points"][-1] = dict(x=510, y=215)
        doc["roads"][0]["width"] = 11
        doc["roads"].append(
            dict(id="road-2", name="New Link", roadClass="country",
                 surface="asphalt", width=8, lanes=2,
                 points=[dict(x=900, y=200), dict(x=1000, y=550)]))
        data, _ = self.apply(doc)
        roads, nodes = data[0], data[1]
        self.assertEqual(nodes["b"], (510, 215))
        self.assertEqual(roads[0]["anchors"][-1], [510, 215])
        self.assertEqual(roads[1]["anchors"][0], [510, 215])
        self.assertEqual(roads[0]["width"], 11)
        self.assertEqual(roads[1]["kind"], "arterial")
        self.assertEqual(len(roads), 3)
        self.assertEqual(roads[2]["start"], "c")
        self.assertEqual(roads[2]["kind"], "rural")

    def test_move_landmark_and_add_traffic_marker(self):
        doc = editor_doc()
        doc["markers"].append(dict(id="marker-1", type="garage", x=120, y=190))
        doc["markers"].append(dict(id="marker-2", type="traffic_spawn",
                                   name="Traffic Gate", x=600, y=200))
        data, extras = self.apply(doc)
        self.assertEqual(data[3][0]["position"], [120, 190])
        self.assertEqual(data[1]["poi_0"], (120, 190))
        self.assertEqual(data[5][0]["p"], [120, 190])
        self.assertEqual(extras[0]["kind"], "traffic_spawn")

    def test_terrain_edits_are_explicit(self):
        doc = editor_doc()
        doc["regions"][0]["points"][0] = dict(x=1450, y=200)
        data, _ = self.apply(doc)
        self.assertEqual(data[2][0]["points"][0], [1450, 200])
        self.assertEqual(data[2][0]["kind"], "ocean")

    def test_deleted_original_source_road_is_blocked(self):
        doc = editor_doc()
        doc["roads"].pop()
        with self.assertRaisesRegex(ValueError, "removed"):
            self.apply(doc)

    def test_reject_invalid_world_and_road_id(self):
        doc = editor_doc()
        doc["world"]["width"] = 6300
        with self.assertRaisesRegex(ValueError, "6400x4800"):
            self.apply(doc)
        doc = editor_doc()
        doc["roads"][0]["id"] = "road-new"
        with self.assertRaisesRegex(ValueError, "stable"):
            self.apply(doc)

    def test_missing_overlay_is_noop(self):
        data = fixture()
        with tempfile.TemporaryDirectory() as tmp:
            markers = apply_edits(*data, filename=Path(tmp) / "missing.json")
        self.assertEqual(markers, [])
        self.assertEqual(data, fixture())


if __name__ == "__main__":
    unittest.main()
