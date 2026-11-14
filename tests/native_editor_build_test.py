"""Bake the native interaction-test draft using the real builder in a copy.

Run tests/native_editor_interaction_test.gd first. No playable files are modified.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
def run():
    source=ROOT/'.runtime/native-editor-audit/source.json'
    doc=json.loads(source.read_text(encoding='utf-8'))
    with tempfile.TemporaryDirectory(prefix='native-editor-bake-') as tmp:
        work=Path(tmp)
        shutil.copytree(ROOT/'tools',work/'tools',ignore=shutil.ignore_patterns('__pycache__'))
        (work/'worlds').mkdir()
        output=work/'map-editor/maps/morrow-coast.edits.world.json'
        output.parent.mkdir(parents=True)
        output.write_text(json.dumps(doc),encoding='utf-8')
        for prop in doc['props']:
            if not prop.get('assetPath'):continue
            path=Path(prop['assetPath'])
            target=work/'assets'/path
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/'assets'/path,target)
        result=subprocess.run([sys.executable,'-B',str(work/'tools/build_morrow_coast.py')],cwd=work,
            capture_output=True,text=True,timeout=240)
        assert result.returncode==0,result.stdout+result.stderr
        baked=json.loads((work/'worlds/morrow-coast.world.json').read_text(encoding='utf-8'))
        expected=[[p['x'],p['y']] for p in doc['roads'][-1]['points']]
        assert any(road['anchors']==expected for road in baked['roads']), 'Native road anchors changed during bake'
        region=doc['regions'][-1]
        expected_region=[[p['x'],p['y']] for p in region['points']]
        assert any(t['kind']==region['biome'] and t['points']==expected_region for t in baked['terrain']), 'Native terrain missing'
        assert any(m['kind']=='race_start' and m['p']==[3500,3500] for m in baked['editor_markers']), 'Native race marker missing'
        assert baked['chunks'] and baked['road_connections']
        print('NATIVE EDITOR PRODUCTION BAKE: PASS (road, chosen terrain, race marker, streaming and connections)')

if __name__=='__main__':run()
