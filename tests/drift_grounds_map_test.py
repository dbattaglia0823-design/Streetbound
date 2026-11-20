"""Regression checks for the small purpose-built drift practice world.

Use the actual source and production world baker, not a drawn mockup.
"""
from collections import defaultdict, deque
import json
import math
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_custom_test_world import make_archive
from publish_custom_world import _production_checks

MAP=ROOT/"map-editor/maps/drift-grounds.world.json"
SOLID_KINDS={"house":(12,17),"building":(22,29),"warehouse":(28,37),
             "garage":(20,21),"gas_station":(18,17),"parked_car":(1.9,4.6)}
TRACK_ROADS={"Tandem Outer Circuit","Outer Drift Skidpad","Inner Donut Ring",
             "Technical S Transitions","Infield Reverse Transitions"}


def point_to_segment(p,a,b):
    dx,dy=b[0]-a[0],b[1]-a[1]
    length2=dx*dx+dy*dy
    if length2<1e-8:
        return math.dist(p,a)
    fraction=min(1,max(0,((p[0]-a[0])*dx+(p[1]-a[1])*dy)/length2))
    return math.hypot(p[0]-a[0]-fraction*dx,p[1]-a[1]-fraction*dy)


def distance_to_road(p,road):
    coords=road["points"]
    return min(point_to_segment(p,a,b) for a,b in zip(coords,coords[1:]))


class DriftGrounds(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source=json.loads(MAP.read_text(encoding="utf-8"))
        cls.baked=make_archive(cls.source)

    def test_three_practice_zones_and_small_footprint(self):
        d=self.source
        self.assertTrue(d["customMap"])
        self.assertEqual(d["format"],"gdt.racing-world")
        self.assertEqual(d["version"],2)
        self.assertEqual((d["world"]["width"],d["world"]["height"]),(820,700))
        self.assertEqual(len(d["roads"]),8)
        self.assertEqual(len(d["races"]),3)
        self.assertTrue(TRACK_ROADS.issubset({r["name"] for r in d["roads"]}))
        self.assertEqual(len([p for p in d["props"] if p["type"]=="guardrail"]),5)
        self.assertEqual(len([p for p in d["markers"] if p["type"]=="traffic_spawn"]),0)
        self.assertGreater(len(d["props"]),100)
        self.assertEqual(len(d["regions"]),7)

    def test_open_and_closed_driving_areas_survive_real_bake(self):
        b=self.baked
        self.assertEqual(b["format"],"streetbound.streamed-world")
        self.assertEqual(len(b["roads"]),8)
        self.assertGreater(len(b["segments"]),120)
        self.assertGreaterEqual(len(b["junctions"]),5)
        self.assertGreater(len(b["chunks"]),8)
        self.assertEqual(len(b["editor_races"]),3)
        self.assertEqual(len(b["editor_game_markers"]),5)
        self.assertEqual(b["spawn"]["position"],[345,210])
        self.assertEqual(len(b["props"]),len(self.source["props"]))
        self.assertEqual(_production_checks(self.source,b,ROOT),[])
        for title in ("Outer Drift Skidpad","Inner Donut Ring","Tandem Outer Circuit"):
            r=next(r for r in b["roads"] if r["name"]==title)
            self.assertLess(math.dist(r["points"][0],r["points"][-1]),.05,title)

    def test_track_and_practice_areas_share_one_connected_network(self):
        graph=defaultdict(set)
        for a,b in self.baked["road_connections"]:
            graph[a].add(b)
            graph[b].add(a)
        reached={0}
        queue=deque([0])
        while queue:
            for neighbor in graph[queue.popleft()]:
                if neighbor not in reached:
                    reached.add(neighbor)
                    queue.append(neighbor)
        self.assertEqual(reached,set(range(8)),
                         "Every drift facility must be drivable from the spawn.")

    def test_spawn_and_all_time_trial_checkpoints_are_on_real_pavement(self):
        b=self.baked
        self.assertEqual(len([m for m in self.source["markers"]
                              if m["type"]=="player_spawn"]),1)
        for race in self.source["races"]:
            for p in race["points"]:
                xy=(p["x"],p["y"])
                self.assertTrue(any(distance_to_road(xy,road)<=float(road["width"])/2-1
                                    for road in b["roads"]),
                                (race["name"],xy))
            self.assertEqual(race["enemy_starts"],[],
                             "Drift practice should not require starting traffic.")

    def test_solid_paddock_buildings_do_not_obstruct_any_track(self):
        for p in self.source["props"]:
            if p["type"] not in SOLID_KINDS:
                continue
            w,h=SOLID_KINDS[p["type"]]
            # Deliberately conservative collision clearance test:
            # half the diagonal fits every rotated rectangle.
            radius=math.hypot(w,h)*p["scale"]/2
            for road in self.baked["roads"]:
                distance=distance_to_road([p["x"],p["y"]],road)
                self.assertGreaterEqual(distance-radius-road["width"]/2,2.5,
                                        (p["name"],road["name"],distance))

    def test_safety_rails_follow_paths_outside_running_surface(self):
        for p in self.source["props"]:
            if p["type"]!="guardrail":
                continue
            self.assertAlmostEqual(p["guardrailWidth"],.65)
            points=[[p["x"]+x,p["y"]+y] for x,y in p["guardrailPoints"]]
            self.assertGreaterEqual(len(points),2)
            for at in points:
                self.assertTrue(1<=at[0]<=819 and 1<=at[1]<=699)
                gap=min(distance_to_road(at,r)-r["width"]/2
                        for r in self.baked["roads"])
                self.assertGreaterEqual(gap,6.0,(p["name"],at,gap))

    def test_unique_identity_and_no_extraneous_active_world_change(self):
        source=self.source
        all_entities=[item for collection in ("roads","regions","props","markers","races")
                      for item in source[collection]]
        self.assertEqual(len({e["id"] for e in all_entities}),len(all_entities))
        active=json.loads((ROOT/"worlds/active-world.json").read_text())
        self.assertEqual(active["mode"],"morrow",
                         "Starter map is not automatically published as the game world.")


if __name__=="__main__":
    unittest.main()
