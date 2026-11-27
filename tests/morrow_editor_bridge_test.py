"""No third-party packages; checks the World Forge-to-Morrow source bridge."""
import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from morrow_editor_import import apply_edits, _authoring_props


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
    def apply(self, doc, base=None, **options):
        data = copy.deepcopy(base or fixture())
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "edits.json"
            source.write_text(json.dumps(doc), encoding="utf-8")
            extras = apply_edits(*data, filename=source, **options)
        return data, extras

    def test_asset_draw_order_bakes_without_changing_collision_or_transform(self):
        source = dict(id="prop-layer", type="house", x=500, y=600, scale=1, rotation=0)
        normal = _authoring_props({"props": [source]})[0]
        for order in (-5, -1, 1, 10):
            layered = _authoring_props({"props": [dict(source, drawOrder=order)]})[0]
            self.assertEqual(layered.pop("editor_draw_order"), order)
            self.assertEqual(layered, normal)
        self.assertEqual(_authoring_props({"props": [dict(source, drawOrder=0)]})[0], normal)
        for invalid in (-6, 11, 0.5, True, "1"):
            with self.assertRaisesRegex(ValueError, "Draw order"):
                _authoring_props({"props": [dict(source, drawOrder=invalid)]})

    def test_road_elevation_uses_explicit_profile_without_touching_legacy_grade(self):
        source = editor_doc()
        source["roads"][0]["elevation"] = {"start_layer": 0, "end_layer": 1}
        new_road = copy.deepcopy(source["roads"][1])
        new_road["id"] = "road-2"
        new_road["elevation"] = {"start_layer": -1, "end_layer": -1}
        source["roads"].append(new_road)
        base = fixture()
        base[0][1]["grade"] = 1
        (roads, *_), _ = self.apply(source, base)
        self.assertEqual(roads[0]["elevation"], source["roads"][0]["elevation"])
        self.assertEqual(roads[2]["elevation"], new_road["elevation"])
        self.assertEqual(roads[1]["grade"], 1)
        self.assertNotIn("elevation", roads[1])

    def test_explicit_district_label_survives_without_renaming_stock_terrain(self):
        doc=editor_doc()
        doc["regions"].append(dict(id="region-1",name="Industrial block",biome="grass",
            points=[dict(x=x,y=y) for x,y in [[100,300],[200,300],[200,400],[100,400]]]))
        result,_=self.apply(doc)
        self.assertEqual(result[2][0],fixture()[2][0])
        self.assertEqual(result[2][1]["editor_name"],"Industrial block")

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
        # Explicitly move both road ends so the shared node remains connected.
        # Moving only one end intentionally detaches that road in the editor.
        doc["roads"][1]["points"][0] = dict(x=510, y=215)
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

    def test_single_moved_endpoint_detaches_without_moving_neighbor(self):
        doc = editor_doc()
        doc["roads"][0]["points"][-1] = dict(x=510, y=215)
        data, _ = self.apply(doc)
        roads, nodes = data[0], data[1]
        self.assertEqual(nodes["b"], (500, 200))
        self.assertEqual(roads[1]["anchors"][0], [500, 200])
        self.assertEqual(roads[0]["anchors"][-1], [510, 215])
        self.assertNotEqual(roads[0]["end"], "b")
        self.assertEqual(nodes[roads[0]["end"]], (510, 215))

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

    def test_legacy_added_road_does_not_overwrite_new_source_road(self):
        base=fixture()
        base[0].append(dict(id=2,name="New default road",start="a",end="c",
            anchors=[[100,200],[900,200]],kind="local",surface="ASPHALT",
            width=9,lanes=2,points=[]))
        doc=editor_doc()
        doc["roads"].append(dict(id="road-2",name="My added road",roadClass="city",
            surface="asphalt",width=9,lanes=2,
            points=[dict(x=100,y=200),dict(x=900,y=200)]))
        result,_=self.apply(doc,base,legacy_source_count=2)
        self.assertEqual([r["name"] for r in result[0]],
            ["West Road","East Road","New default road","My added road"])
        current=copy.deepcopy(doc)
        current["morrowSourceRoadCount"]=3
        current["roads"][2]["id"]="road-3"
        current["roads"].insert(2,dict(doc["roads"][0],id="road-2",name="Edited new default"))
        again,_=self.apply(current,base,legacy_source_count=2)
        self.assertEqual(len(again[0]),4)
        self.assertEqual(again[0][2]["name"],"Edited new default")
        current["roads"].pop(2)
        with self.assertRaisesRegex(ValueError,"removed"):
            self.apply(current,base,legacy_source_count=2)

    def test_legacy_custom_marker_does_not_move_new_destination(self):
        base=fixture()
        base[3].append(dict(name="New fuel stop",position=[800,150],road=1))
        doc=editor_doc()
        doc["markers"].append(dict(id="marker-2",type="race_start",x=400,y=200))
        result,extras=self.apply(doc,base,legacy_source_poi_count=1)
        self.assertEqual(result[3][1]["position"],[800,150])
        self.assertEqual(len(extras),1)
        self.assertEqual(extras[0]["kind"],"race_start")
        self.assertEqual(extras[0]["p"],[400,200])

    def test_baked_widths_are_unscaled_before_the_next_bake(self):
        doc=editor_doc()
        doc["morrowRoadWidthScale"]=1.1
        for road in doc["roads"]:
            road["width"]*=1.1
        result,_=self.apply(doc)
        self.assertEqual([r["width"] for r in result[0]],[9,12])

    def test_legacy_migration_cannot_exceed_editor_road_limit(self):
        base=fixture()
        base[0].append(dict(base[0][0],id=2,name="New default"))
        doc=editor_doc()
        doc["roads"].extend(dict(doc["roads"][0],id="road-%d" % i) for i in range(2,180))
        with self.assertRaisesRegex(ValueError,"editor limit"):
            self.apply(doc,base,legacy_source_count=2)


if __name__ == "__main__":
    unittest.main()
