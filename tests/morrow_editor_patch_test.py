"""Regression for safe Morrow Coast editor-patch application."""
import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from morrow_editor_patch import apply_road_patch


class MorrowPatchTests(unittest.TestCase):
    def setUp(self):
        self.nodes={"a":(100,100),"b":(900,100),"c":(100,600),"d":(900,600)}
        self.roads=[
            dict(id=0,name="Test Main",start="a",end="b",kind="arterial",
                 surface="ASPHALT",width=12,lanes=2,anchors=[(100,100),(900,100)]),
            dict(id=1,name="Gravel Bypass",start="c",end="d",kind="gravel",
                 surface="GRAVEL",width=6,lanes=2,anchors=[(100,600),(900,600)])
        ]
        self.temp=tempfile.TemporaryDirectory()
        self.path=Path(self.temp.name)/"patch.json"

    def tearDown(self):
        self.temp.cleanup()

    def write(self,changes=None,additions=None,road_count=2):
        self.path.write_text(json.dumps({
            "format":"streetbound.morrow-editor-patch","version":1,
            "baseline":{"road_count":road_count,"world_name":"Morrow Coast"},
            "updated_roads":changes or [],"new_roads":additions or []
        }),encoding="utf-8")

    def test_no_file_is_no_op(self):
        self.assertEqual(apply_road_patch(self.path,self.roads,self.nodes,1000,1000),
                         {"updated":0,"added":0})

    def test_curve_and_width_update_are_applied(self):
        self.write(changes=[dict(road_id=0,name="Test Main",
            anchors=[[100,100],[300,120],[600,130],[900,100]],width=15,
            lanes=2,kind="arterial",surface="ASPHALT")])
        result=apply_road_patch(self.path,self.roads,self.nodes,1000,1000)
        self.assertEqual(result["updated"],1)
        self.assertEqual(len(self.roads[0]["anchors"]),4)
        self.assertEqual(self.roads[0]["width"],15)
        self.assertEqual(self.nodes["a"],(100,100))

    def test_corrupt_or_stale_patches_cannot_mutate_source(self):
        self.write(changes=[dict(road_id=0,name="Test Main",
            anchors=[[110,100],[900,100]],width=12,
            lanes=2,kind="arterial",surface="ASPHALT")])
        before=[dict(r) for r in self.roads]
        with self.assertRaisesRegex(ValueError,"endpoints"):
            apply_road_patch(self.path,self.roads,self.nodes,1000,1000)
        self.assertEqual(self.roads,before)
        self.write(road_count=99)
        with self.assertRaisesRegex(ValueError,"stale"):
            apply_road_patch(self.path,self.roads,self.nodes,1000,1000)

    def test_added_link_receives_unique_nodes_and_index(self):
        self.write(additions=[dict(name="New Link",anchors=[[300,100],[300,600]],
                                  width=8,lanes=2,kind="local",surface="ASPHALT")])
        stats=apply_road_patch(self.path,self.roads,self.nodes,1000,1000)
        self.assertEqual(stats["added"],1)
        self.assertEqual(self.roads[-1]["id"],2)
        self.assertIn("editor_0_start",self.nodes)
        self.assertEqual(self.roads[-1]["kind"],"local")

    def test_added_road_outside_world_is_rejected(self):
        self.write(additions=[dict(name="Invalid",anchors=[[300,100],[1300,600]],
                                  width=8,lanes=2,kind="local",surface="ASPHALT")])
        with self.assertRaisesRegex(ValueError,"outside"):
            apply_road_patch(self.path,self.roads,self.nodes,1000,1000)
        self.assertEqual(len(self.roads),2)


if __name__=="__main__":
    unittest.main()
