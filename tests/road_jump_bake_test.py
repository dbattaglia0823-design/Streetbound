import copy
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT / "tools"))
from build_custom_test_world import make_archive, scenery_rebuild
from road_jumps import bake_into, flight


def fixture():
    return json.loads((ROOT/"tests/fixtures/road-jumps.world.json").read_text(encoding="utf-8"))


class JumpBakeTests(unittest.TestCase):
    def test_standalone_objects_bake_without_road_or_landing_parameters(self):
        doc=fixture()
        del doc["roads"][0]["jump"]
        doc["props"].append(dict(id="prop-ramp",type="stunt_ramp",name="Stunt ramp",x=350,y=320,rotation=90,scale=1,assetId=""))
        data=make_archive(doc)
        jump,=data["jumps"]
        self.assertTrue(jump["object_ramp"])
        self.assertEqual(jump["prop_id"],"prop-ramp")
        self.assertAlmostEqual(jump["p"][0],354)
        self.assertAlmostEqual(jump["p"][1],320)
        self.assertAlmostEqual(jump["direction"][0],1)
        self.assertAlmostEqual(jump["height_m"],1.2)
        self.assertNotIn("max_mps",jump)
        self.assertNotIn("landing_start_m",jump)
        self.assertFalse(next(p for p in data["props"] if p.get("authoring_id")=="prop-ramp")["solid"])

    def test_scaled_rotated_ramp_and_cached_rebuild_use_final_prop_size(self):
        doc=fixture()
        del doc["roads"][0]["jump"]
        ramp=dict(id="prop-wide-ramp",type="stunt_ramp",name="Wide ramp",x=350,y=320,
                  rotation=90,scale=2,scaleX=3,scaleY=1.5,assetId="")
        doc["props"].append(ramp)
        data=make_archive(doc)
        prop=next(p for p in data["props"] if p.get("authoring_id")==ramp["id"])
        jump,=data["jumps"]
        self.assertEqual(prop["size"],[30,24])
        self.assertEqual([jump["width_m"],jump["length_m"]],prop["size"])
        self.assertAlmostEqual(jump["p"][0],362)
        self.assertAlmostEqual(jump["height_m"],3.6)
        ramp.update(scaleX=5,scaleY=2,rotation=0)
        rebuilt=scenery_rebuild(data,doc)
        jump,=rebuilt["jumps"]
        self.assertEqual([jump["width_m"],jump["length_m"]],[50,32])
        self.assertEqual(jump["p"],[350,304])
        doc["props"].remove(ramp)
        self.assertNotIn("jumps",scenery_rebuild(rebuilt,doc))

    def test_baked_landing_contains_speed_envelope(self):
        data = make_archive(fixture())
        jump, = data["jumps"]
        self.assertEqual(jump["direction"],[1.0,0.0])
        self.assertEqual(jump["p"],[200.0,400.0])
        for speed in (15,17.5,20):
            _, distance, peak = flight(jump["height_m"],jump["angle_deg"],speed)
            self.assertGreater(distance,jump["landing_start_m"])
            self.assertLess(distance,jump["landing_end_m"])
            self.assertLess(peak,4.0)

    def test_reverse_jump_and_missing_legacy_data(self):
        source = fixture()
        source["roads"][0]["jump"]["reverse"] = True
        jump, = make_archive(source)["jumps"]
        self.assertEqual(jump["direction"],[-1.0,0.0])
        del source["roads"][0]["jump"]
        self.assertNotIn("jumps",make_archive(source))

    def test_rejects_escalated_speed_and_unsupported_landing(self):
        for settings in ({"max_mps":55}, {"landing_length_m":6}, {"at_m":795},
                         {"landing_width_m":14}, {"angle_deg":18,"max_mps":26}):
            with self.subTest(settings=settings):
                doc = fixture()
                doc["roads"][0]["jump"].update(settings)
                with self.assertRaises(ValueError):
                    make_archive(doc)
        doc = fixture()
        doc["roads"][0]["elevation"] = {"start_layer":1,"end_layer":1}
        with self.assertRaisesRegex(ValueError,"ground-level paved road"):
            make_archive(doc)

    def test_rejects_overlapping_deck_and_prohibited_world_space(self):
        doc = fixture()
        doc["roads"][0]["jump"]["at_m"]=388
        with self.assertRaisesRegex(ValueError,"overlaps Overpass"):
            make_archive(doc)
        valid=make_archive(fixture())
        obstacles=[
            ("props",dict(kind="house",p=[217,400],size=[9,9],solid=True),"house"),
            ("props",dict(kind="guardrail",p=[208,400],solid=False,guardrail_width=.65,
                          guardrail_points=[[-8,0],[8,0]],angle=1.57),"guardrail"),
            ("walls",[[208,390],[208,410]],"world wall"),
            ("terrain",dict(kind="lake",points=[[210,394],[220,394],[220,406],[210,406]]),"restricted terrain")
        ]
        for collection, obstacle, error in obstacles:
            with self.subTest(obstacle=error):
                data = copy.deepcopy(valid)
                data[collection].append(obstacle)
                with self.assertRaisesRegex(ValueError,error):
                    bake_into(data)


if __name__ == "__main__":
    unittest.main()
