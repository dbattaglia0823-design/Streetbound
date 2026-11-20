"""Compact Boroughs starter: dense, accessible, fully playable custom map."""
from pathlib import Path
import json
import math
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_custom_test_world import make_archive
from publish_custom_world import _production_checks

MAP=ROOT/"map-editor/maps/compact-boroughs.world.json"
BUILDING_SIZES={"house":(12,17),"building":(22,29),"garage":(20,21),
                "warehouse":(28,37),"gas_station":(18,17)}


class CompactBoroughsMap(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc=json.loads(MAP.read_text(encoding="utf-8"))
        cls.archive=make_archive(cls.doc)

    def test_valid_compact_source_and_three_areas(self):
        d=self.doc
        self.assertTrue(d["customMap"])
        self.assertEqual(d["format"],"gdt.racing-world")
        self.assertEqual(d["version"],2)
        self.assertEqual((d["world"]["width"],d["world"]["height"]),(960,720))
        self.assertEqual(len(d["roads"]),9)
        self.assertEqual(len(d["races"]),2)
        self.assertGreaterEqual(len(d["props"]),300)
        self.assertGreaterEqual(len([p for p in d["props"] if p["type"] in BUILDING_SIZES]),200)
        self.assertTrue(any(p["type"]=="guardrail" for p in d["props"]))
        for area in ("Old Town","Market District","Motor Row","Dockside"):
            self.assertTrue(any(area in p["name"] for p in d["props"]),area)

    def test_genuinely_drivable_world_and_valid_publisher_spawn(self):
        baked=self.archive
        self.assertEqual(baked["format"],"streetbound.streamed-world")
        self.assertEqual(len(baked["roads"]),9)
        self.assertGreaterEqual(len(baked["junctions"]),12)
        self.assertTrue(baked["road_connections"])
        self.assertEqual(len(baked["editor_races"]),2)
        self.assertEqual(len(baked["editor_game_markers"]),8)
        self.assertEqual(baked["spawn"]["position"],[402,250])
        self.assertGreaterEqual(len(baked["chunks"]),12)
        self.assertGreaterEqual(len(baked["props"]),300)
        self.assertGreaterEqual(len(baked["terrain"]),7)
        self.assertEqual(_production_checks(self.doc,baked,ROOT),[])

    def test_buildings_clear_road_edges(self):
        # Exact axis-aligned road centrelines in this deliberate small grid.
        xs=((70,16),(280,16),(500,20),(715,16),(880,16))
        ys=((70,16),(250,20),(430,16),(650,16))
        for p in self.doc["props"]:
            if p["type"] not in BUILDING_SIZES:
                continue
            w,h=BUILDING_SIZES[p["type"]]
            w*=p["scale"];h*=p["scale"]
            theta=math.radians(p["rotation"])
            ex=(abs(w*math.cos(theta))+abs(h*math.sin(theta)))/2
            ey=(abs(h*math.cos(theta))+abs(w*math.sin(theta)))/2
            nearest=min(
                *(abs(p["x"]-x)-ex-width/2 for x,width in xs),
                *(abs(p["y"]-y)-ey-width/2 for y,width in ys))
            self.assertGreaterEqual(nearest,3.8,(p["id"],p["name"],nearest))

    def test_no_unintentionally_empty_playable_sections(self):
        # Each 160x120 m sector of the main urban rectangle needs buildings,
        # a street, a park, or a named waterfront section—not bare unused land.
        props=self.doc["props"]
        roads=self.doc["roads"]
        for y0 in range(0,720,120):
            for x0 in range(0,960,160):
                cx,cy=x0+80,y0+60
                if cx>=880:  # Waterfront / protected beach and water strip
                    continue
                nearby=sum(x0<=p["x"]<x0+160 and y0<=p["y"]<y0+120 for p in props)
                crosses_road=any(
                    (min(pt["x"] for pt in r["points"])<=cx<=max(pt["x"] for pt in r["points"]) and
                     min(pt["y"] for pt in r["points"])-16<=cy<=max(pt["y"] for pt in r["points"])+16)
                    for r in roads)
                self.assertTrue(nearby>=3 or crosses_road,
                                f"empty sector at ({x0},{y0})")

    def test_one_spawn_and_event_ids_are_stable(self):
        markers=self.doc["markers"]
        self.assertEqual(len([m for m in markers if m["type"]=="player_spawn"]),1)
        ids=[entity["id"] for collection in ("roads","regions","props","markers","races")
             for entity in self.doc[collection]]
        self.assertEqual(len(ids),len(set(ids)))
        self.assertEqual(len(self.archive["editor_races"]),2)


if __name__=="__main__":
    unittest.main()
