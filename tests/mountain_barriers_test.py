"""Mountain source validation and two real production saves in isolation."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from mountain_barriers import validate_polygon,validate_barriers


class MountainBarrierTests(unittest.TestCase):
    def test_unsafe_geometry_and_roads_are_rejected(self):
        with self.assertRaises(ValueError):validate_polygon([[0,0],[100,100],[0,100],[100,0]])
        region=dict(kind='mountain',barrier=True,elevation=80,points=[[0,0],[100,0],[100,100],[0,100]])
        with self.assertRaisesRegex(ValueError,'blocks Test road'):
            validate_barriers([dict(points=[[-100,50],[200,50]],width=10,name='Test road')],[region],[],dict(position=[200,200]))
        with self.assertRaisesRegex(ValueError,'player start'):
            validate_barriers([],[region],[],dict(position=[50,50]))
        validate_barriers([dict(points=[[-100,150],[200,150]],width=10,name='Test road')],[region],[],dict(position=[200,200]))

    def test_two_saved_bakes_preserve_solid_height_outline_and_sparse_id(self):
        doc=json.loads((ROOT/'map-editor/maps/morrow-coast.edits.world.json').read_text(encoding='utf-8'))
        doc['regions'].append(dict(id='region-200',name='West mountain boundary',biome='mountain',elevation=110,barrier=True,
            points=[dict(x=0,y=2800),dict(x=170,y=2800),dict(x=210,y=3150),dict(x=160,y=3600),dict(x=0,y=3600)]))
        with tempfile.TemporaryDirectory(prefix='streetbound-mountain-barriers-') as temporary:
            work=Path(temporary)
            shutil.copytree(ROOT/'tools',work/'tools',ignore=shutil.ignore_patterns('__pycache__'))
            (work/'worlds').mkdir();overlay=work/'map-editor/maps/morrow-coast.edits.world.json';overlay.parent.mkdir(parents=True)
            for prop in doc.get('props',[]):
                if prop.get('assetPath'):
                    target=work/'assets'/prop['assetPath'];target.parent.mkdir(parents=True,exist_ok=True)
                    shutil.copy2(ROOT/'assets'/prop['assetPath'],target)
            overlay.write_text(json.dumps(doc),encoding='utf-8')
            archive=work/'worlds/morrow-coast.world.json'
            def bake():
                result=subprocess.run([sys.executable,'-B',str(work/'tools/build_morrow_coast.py')],cwd=work,capture_output=True,text=True,timeout=240)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                world=json.loads(archive.read_text(encoding='utf-8'))
                index=next(i for i,t in enumerate(world['terrain']) if t.get('authoring_id')=='region-200')
                mountain=world['terrain'][index]
                self.assertTrue(mountain['barrier']);self.assertEqual(mountain['elevation'],110)
                self.assertEqual(mountain['points'],[[p['x'],p['y']] for p in doc['regions'][-1]['points']])
                self.assertGreater(sum(index in cell.get('mountains',[]) for cell in world['chunks'].values()),4)
                self.assertTrue(any(t.get('barrier') for cell in world['chunks'].values() for t in cell['terrain']))
                return world
            first=bake()
            code="""import {readFileSync,writeFileSync} from 'node:fs';
import {convertMorrowWorld} from %s;
const {doc}=convertMorrowWorld(JSON.parse(readFileSync(process.argv[1],'utf8')));
writeFileSync(process.argv[2],JSON.stringify(doc));"""%json.dumps((ROOT/'map-editor/morrow-coast-bridge.js').as_uri())
            result=subprocess.run(['node','--input-type=module','-e',code,str(archive),str(overlay)],capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            reopened=json.loads(overlay.read_text())
            self.assertTrue(next(r for r in reopened['regions'] if r['id']=='region-200')['barrier'])
            second=bake()
            self.assertEqual(first['roads'],second['roads'])
            self.assertEqual(first['terrain'],second['terrain'])
            print('MOUNTAIN BARRIER PRODUCTION ROUNDTRIP: PASS (two saves, sparse ID, height, outline and chunk membership)')


if __name__=='__main__':unittest.main()
