"""Compile the same fixture used by the editor and Godot lane-graph tests."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT / "tools"))
from build_custom_test_world import make_archive


def fixture():
    return json.loads((ROOT / "tests/fixtures/road-elevation.world.json").read_text(encoding="utf-8"))


class ElevationBakeTests(unittest.TestCase):
    def test_stacked_roads_share_coordinates_without_connections(self):
        archive = make_archive(fixture())
        connections = {tuple(pair) for pair in archive["road_connections"]}
        for pair in [(0,1),(0,2),(1,2),(1,8),(2,4),(2,8),(3,9)]:
            self.assertNotIn(pair,connections)
        self.assertTrue({(0,6),(1,3),(1,4),(2,7),(4,5)} <= connections)
        self.assertNotIn("elevation",archive["roads"][0])
        self.assertEqual(archive["roads"][4]["elevation"],{"start_layer":1,"end_layer":0})
        stacked = [j for j in archive["junctions"] if j["p"] == [500,450]]
        self.assertEqual([(j["road_layer"],j["roads"]) for j in stacked],[(1,[1,3])])

    def test_directional_merge_does_not_connect_to_overlapping_deck(self):
        source = fixture()
        ground = copy.deepcopy(source["roads"][0])
        deck = copy.deepcopy(source["roads"][1])
        deck["points"] = [{"x":700,"y":250},{"x":700,"y":600}]
        ramp = copy.deepcopy(ground)
        ramp.update(id="road-2", name="Directional Ramp", roadClass="onramp",
                    lanes=1, width=8, points=[{"x":520,"y":480},{"x":700,"y":400}])
        source["roads"] = [ground,deck,ramp]
        archive = make_archive(source)
        merges = [j for j in archive["junctions"] if j["control"] == "merge"]
        self.assertEqual(len(merges),1)
        self.assertEqual(merges[0]["ramp_road"],2)
        self.assertEqual(merges[0]["main_road"],0)
        self.assertEqual(merges[0].get("road_layer",0),0)
        self.assertEqual(set(merges[0]["roads"]),{0,2})
        connections = {tuple(pair) for pair in archive["road_connections"]}
        self.assertNotIn((0,1),connections)
        self.assertNotIn((1,2),connections)

    def test_elevated_merge_retains_direction_and_layer(self):
        source = fixture()
        ground = copy.deepcopy(source["roads"][0])
        deck = copy.deepcopy(ground)
        deck.update(id="road-1", name="Elevated Highway", roadClass="highway",
                    width=16, lanes=4, elevation={"start_layer":1,"end_layer":1})
        ramp = copy.deepcopy(deck)
        ramp.update(id="road-2", name="Elevated Merge Ramp", roadClass="onramp",
                    width=8, lanes=1, points=[{"x":520,"y":480},{"x":700,"y":400}])
        source["roads"] = [ground,deck,ramp]
        archive = make_archive(source)
        merges = [j for j in archive["junctions"] if j["control"] == "merge"]
        self.assertEqual(len(merges),1)
        self.assertEqual(merges[0]["road_layer"],1)
        self.assertEqual(merges[0]["main_road"],1)
        self.assertEqual(merges[0]["ramp_road"],2)
        self.assertEqual(merges[0]["merge_side"],1)
        self.assertEqual(set(merges[0]["roads"]),{1,2})
        connections = {tuple(pair) for pair in archive["road_connections"]}
        self.assertNotIn((0,2),connections)

    def test_ground_legacy_and_explicit_ground_compile_identically(self):
        source = fixture()
        for road in source["roads"]:
            road.pop("elevation",None)
        explicit = copy.deepcopy(source)
        explicit["roads"][0]["elevation"] = {"start_layer":0,"end_layer":0}
        self.assertEqual(make_archive(source),make_archive(explicit))

    def test_shallow_grade_separation_is_rejected(self):
        source = fixture()
        cross = copy.deepcopy(source["roads"][5])
        cross["points"] = [{"x": 340, "y": 685}, {"x": 650, "y": 685}]
        cross["name"] = "Crossing Across Ramp"
        source["roads"].append(cross)
        with self.assertRaisesRegex(ValueError,"Crossing Across Ramp.*4.5 m vertical clearance"):
            make_archive(source)

    def test_open_cut_rejects_water_but_covered_tunnel_keeps_roof(self):
        source = fixture()
        lake = dict(id="region-lake",name="Portal lake",biome="lake",elevation=0,
                    points=[{"x":480,"y":190},{"x":520,"y":190},
                            {"x":520,"y":230},{"x":480,"y":230}])
        source["regions"].append(lake)
        with self.assertRaisesRegex(ValueError,"open terrain cut intersects water"):
            make_archive(source)
        lake["points"] = [{"x":480,"y":300},{"x":520,"y":300},
                          {"x":520,"y":345},{"x":480,"y":345}]
        archive = make_archive(source)
        self.assertEqual(archive["roads"][2]["elevation"],{"start_layer":-1,"end_layer":-1})

    def test_objective_layers_survive_bake_and_invalid_layers_fail(self):
        source = fixture()
        source["races"] = [dict(id="race-grade",name="Grade trial",mode="sprint",
                                points=[dict(x=500,y=400,road_layer=1),
                                        dict(x=500,y=450,road_layer=-1)])]
        source["markers"].extend([
            dict(id="marker-grade-drop",type="contract_dropoff",name="Tunnel drop",
                 x=500,y=400,rotation=0,properties={"road_layer":-1}),
            dict(id="marker-grade-pickup",type="contract",name="Bridge pickup",
                 x=500,y=550,rotation=0,properties={"road_layer":1,
                    "contract_kind":"courier","destination_marker_id":"marker-grade-drop"})])
        archive = make_archive(source)
        self.assertEqual([p["road_layer"] for p in archive["editor_races"][0]["points"]],[1,-1])
        self.assertEqual([m["properties"]["road_layer"] for m in archive["editor_game_markers"] if m["id"].startswith("marker-grade")],[-1,1])
        bad=copy.deepcopy(source)
        bad["races"][0]["points"][0]["road_layer"]=True
        with self.assertRaisesRegex(ValueError,"checkpoint road layer"):
            make_archive(bad)
        bad=copy.deepcopy(source)
        bad["markers"][-1]["properties"]["road_layer"]=3
        with self.assertRaisesRegex(ValueError,"marker road layer"):
            make_archive(bad)

    def test_bad_profiles_fail_before_archive_output(self):
        source = fixture()
        for profile in [None, {"start_layer":True,"end_layer":1},
                        {"start_layer":0,"end_layer":2}, {"start_layer":2.1,"end_layer":2}]:
            with self.subTest(profile=profile):
                source["roads"][1]["elevation"] = profile
                with self.assertRaises(ValueError):
                    make_archive(source)
        source = fixture()
        source["roads"][4]["points"][-1]["y"] = 640
        with self.assertRaisesRegex(ValueError,"at least 50 m"):
            make_archive(source)


if __name__ == "__main__":
    unittest.main()
