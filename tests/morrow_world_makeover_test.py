"""Checks that the rebuilt Morrow Coast gameplay world contains actual
authored layout improvements, not merely a map-editor illustration.
Run only AFTER tools/build_morrow_coast.py has generated its JSON.
"""
import json
import math
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
WORLD=ROOT/"worlds/morrow-coast.world.json"

class WorldMakeover(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data=json.loads(WORLD.read_text(encoding="utf-8"))
        cls.roads=cls.data["roads"]
        cls.props=cls.data["props"]
        cls.pois=cls.data["pois"]

    def test_continuous_four_lane_coastal_highway(self):
        coast=[r for r in self.roads if r["name"]=="Coastal Meridian Highway"]
        self.assertGreaterEqual(len(coast),7)
        self.assertTrue(all(r["kind"]=="highway" and r["lanes"]==4
                            and r["width"]>=18 for r in coast))
        start_nodes={r["start"] for r in coast}
        end_nodes={r["end"] for r in coast}
        self.assertEqual(len(coast)+1,len(start_nodes|end_nodes))
        self.assertLess(min(p[1] for r in coast for p in r["anchors"]),170)
        self.assertGreater(max(p[1] for r in coast for p in r["anchors"]),4550)
        self.assertTrue(any("Interchange" in r["name"] for r in self.roads))

    def test_mixed_use_frontages_more_dense_and_preserve_garage(self):
        infill=[p for p in self.props if p.get("urban_infill")]
        self.assertGreater(len(infill),15)
        self.assertTrue(all(p["kind"] in {"house","shop","building","warehouse"}
                            for p in infill))
        self.assertTrue(all(2250 < p["p"][1] < 3600 for p in infill))
        self.assertTrue(any(p["name"]=="Laurel Motor House" for p in self.pois))
        first=next(p for p in self.pois if p["name"]=="Laurel Motor House")
        self.assertLess(math.dist(first["position"],[2420,3080]),.01)

    def test_western_cornfields_and_race_facilities(self):
        crops=[p for p in self.props if p.get("crop")=="corn"]
        self.assertGreater(len(crops),10)
        self.assertTrue(all(p["kind"]=="field" for p in crops))
        self.assertGreater(sum(p["p"][0]<2150 for p in crops),10)
        for kind,n in (("drag_tree",2),("timing_board",2),("track_barrier",10)):
            self.assertGreaterEqual(sum(p["kind"]==kind for p in self.props),n)
        marks=[p for p in self.props if p["kind"] in {"start_line","finish_line"}
               and abs(p["p"][0]-4340)<.01]
        self.assertGreaterEqual(len(marks),2)
        self.assertAlmostEqual(max(p["p"][1] for p in marks)-
                               min(p["p"][1] for p in marks),402,delta=1.5)
        circuits=[r for r in self.roads if r["name"]=="Ashford Grand Circuit"]
        self.assertEqual(len(circuits),4)
        self.assertTrue(all(r["kind"]=="track" for r in circuits))

    def test_isolated_fuel_stations_link_into_road_network(self):
        for name in ("Pinecrest Fuel & Market","Orchard Crossroads Fuel",
                     "Southern Coast Fuel","Quarry Road Service"):
            self.assertIn(name,[p["name"] for p in self.pois])
            self.assertTrue(any(r["name"]==name+" access" for r in self.roads))
        self.assertEqual(self.data["stats"]["connected_roads"],len(self.roads))

    def test_high_quality_art_is_part_of_game_renderer(self):
        shader=ROOT/"scripts/world/coast_water.gdshader"
        self.assertTrue(shader.exists())
        text=shader.read_text(encoding="utf-8")
        self.assertIn("world_metres",text)
        self.assertIn("TIME",text)
        city=(ROOT/"scripts/world/coast_art.gd").read_text(encoding="utf-8")
        self.assertEqual(city.count("preload(\"res://assets/Buildings/ChatGPT Image"),10)
        self.assertEqual(city.count("preload(\"res://assets/Buildings/Dealerships/"),10)
        field=(ROOT/"scripts/world/coast_scenery.gd").read_text(encoding="utf-8")
        self.assertIn("func _cornfield(",field)
        self.assertIn('"drag_tree"',field)
        self.assertIn('"timing_board"',field)

if __name__=="__main__":
    unittest.main()
