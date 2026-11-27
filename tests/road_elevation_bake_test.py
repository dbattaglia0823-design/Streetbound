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
