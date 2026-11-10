"""Source-authored environment props must rebake safely and roundtrip."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from morrow_editor_import import _authoring_props


class EnvironmentPropsTests(unittest.TestCase):
    def test_deterministic_lot_lights_and_vegetation(self):
        entries = [
            {"id":"prop-1","type":"parking","name":"Motor House extra lot",
             "x":860,"y":725,"scale":1,"rotation":0,"assetId":""},
            {"id":"prop-2","type":"streetlight","x":924,"y":738,
             "scale":.75,"rotation":30,"assetId":""},
            {"id":"prop-3","type":"bush","x":890,"y":770,
             "scale":1.1,"rotation":0,"assetId":""}
        ]
        first=_authoring_props({"props":entries})
        second=_authoring_props({"props":entries})
        self.assertEqual(first,second)
        self.assertEqual([v["kind"] for v in first],["lot","lamp","bush"])
        self.assertEqual(first[0]["authoring_id"],"prop-1")
        self.assertFalse(first[0]["solid"])
        self.assertEqual(first[0]["stall_width"],3.2)
        self.assertEqual(first[0]["occupancy"],.4)
        self.assertEqual(first[0]["entrance_width"],8.0)
        self.assertEqual(first[1]["editor_scale"],.75)

    def test_parking_options_preserve_size_and_validate_occupancy(self):
        base={"id":"prop-35","type":"parking","x":880,"y":760,
              "scale":1.25,"rotation":90,"stallWidth":2.8,
              "occupancy":.75,"entranceWidth":9}
        lot=_authoring_props({"props":[base]})[0]
        self.assertEqual(lot["stall_width"],2.8)
        self.assertEqual(lot["occupancy"],.75)
        self.assertEqual(lot["entrance_width"],9.0)
        self.assertEqual(lot["size"],[47.5,35.0])
        for key,value in [("stallWidth",1),("occupancy",1.5),
                          ("entranceWidth",12),("stallWidth",float("nan")),
                          ("occupancy",True)]:
            with self.assertRaises(ValueError):
                _authoring_props({"props":[{**base,key:value}]})

    def test_solid_buildings_use_real_collision_footprints(self):
        result=_authoring_props({"props":[
          {"id":"prop-15","type":"warehouse","x":900,"y":850,
           "scale":1,"rotation":90}
        ]})[0]
        self.assertTrue(result["solid"])
        self.assertGreater(result["radius"],12)
        self.assertEqual(result["size"],[28,37])

    def test_invalid_types_and_shapes_fail(self):
        base={"id":"prop-1","x":800,"y":900,
              "scale":1,"rotation":0,"type":"parking"}
        for change in [{"type":"remote-script"},{"scale":100},
                       {"x":-50},{"assetId":"arbitrary"},{"rotation":float("nan")}]:
            item={**base,**change}
            with self.assertRaises(ValueError):
                _authoring_props({"props":[item]})
        with self.assertRaises(ValueError):
            _authoring_props({"props":[base,base]})

    def test_do_not_allow_huge_authoring_payload(self):
        entries=[{"id":f"prop-{i}","type":"streetlight","x":500+i,"y":600,
            "scale":1,"rotation":0} for i in range(201)]
        with self.assertRaises(ValueError):
            _authoring_props({"props":entries})


if __name__ == "__main__":
    unittest.main()
