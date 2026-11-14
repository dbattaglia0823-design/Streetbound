"""Exact clipping, streaming membership and renderer/baker geometry agreement."""
import copy
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from road_bridges import WaterMask,apply,distance,rail_paths


class AutomaticBridgesTests(unittest.TestCase):
    def test_shared_crossing_fixtures(self):
        for case in json.loads((ROOT/'tests/fixtures/road_bridges.json').read_text()):
            with self.subTest(case=case['name']):
                mask=WaterMask(case['terrain'])
                wet=mask.intervals(case['path'])
                self.assertEqual(len(wet),len(case['wet']))
                for a,b in zip(wet,case['wet']):
                    self.assertAlmostEqual(a[0],b[0],places=4);self.assertAlmostEqual(a[1],b[1],places=4)
                spans=mask.spans(dict(id=0,points=case['path'],width=10,kind='rural'))
                self.assertEqual(len(spans),len(wet))
                for span in spans:
                    self.assertGreaterEqual(span['start'],0);self.assertGreater(span['end'],span['start'])
                    self.assertGreaterEqual(len(span['points']),2)
                    self.assertAlmostEqual(sum(distance(a,b) for a,b in zip(span['points'],span['points'][1:])),span['end']-span['start'],places=4)

    def test_streaming_and_rail_clearance(self):
        world=dict(size=[1200,400],chunk_size=192,terrain=[dict(kind='water',points=[[300,0],[700,0],[700,300],[300,300]])],
                   roads=[dict(id=0,points=[[100,150],[1000,150]],width=12,kind='rural')],walls=[],chunks={},junctions=[])
        apply(world)
        self.assertEqual(len(world['bridges']),1)
        self.assertTrue(all(world['chunks'][f'{x},0']['bridges']==[0] for x in range(1,4)))
        self.assertTrue(world['bridge_wall_indices'])
        self.assertTrue(all(abs(wall[0][1]-150)>6 for wall in world['walls']))
        self.assertEqual({id for chunk in world['chunks'].values() for id in chunk['walls']},set(world['bridge_wall_indices']))
        snapshot=copy.deepcopy(world)
        apply(world)
        self.assertEqual(world,snapshot,'Rebuilding the bridge added duplicate collision rails')
        bridge=world['bridges'][0]
        junction=dict(polygon=[[480,130],[520,130],[520,170],[480,170]])
        for a,b in rail_paths(bridge,[junction]):
            self.assertFalse(480<(a[0]+b[0])*.5<520,'A rail blocks the intersecting road mouth')

    def test_current_game_and_godot_runtime_agree(self):
        path=ROOT/'.runtime/bridges-audit/runtime-spans.json'
        if not path.exists():self.skipTest('Run automatic_bridges_test.gd to compare real Godot geometry')
        runtime=json.loads(path.read_text())
        raw=json.loads((ROOT/'worlds/morrow-coast.world.json').read_text())
        from road_widths import adapt
        adapt(raw)
        mask=WaterMask(raw['terrain'])
        spans=[span for road in raw['roads'] for span in mask.spans(road)]
        self.assertEqual(len(spans),len(runtime))
        for a,b in zip(spans,runtime):
            self.assertEqual(a['road'],int(b['road']))
            self.assertAlmostEqual(a['start'],b['start'],delta=.025)
            self.assertAlmostEqual(a['end'],b['end'],delta=.025)
            self.assertAlmostEqual(a['width'],b['width'],delta=.002)


if __name__=='__main__':unittest.main()
