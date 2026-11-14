"""Production split regression; never overwrites the playable map."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
ROOT=Path(__file__).resolve().parents[1]
doc=json.loads((ROOT/'.runtime/road-edit-audit/source.json').read_text())
original=json.loads((ROOT/'worlds/morrow-coast.world.json').read_text())['roads'][0]
with tempfile.TemporaryDirectory(prefix='streetbound-split-') as temporary:
    work=Path(temporary);shutil.copytree(ROOT/'tools',work/'tools',ignore=shutil.ignore_patterns('__pycache__'))
    overlay=work/'map-editor/maps/morrow-coast.edits.world.json';overlay.parent.mkdir(parents=True);(work/'worlds').mkdir()
    overlay.write_text(json.dumps(doc))
    for prop in doc.get('props',[]):
        if prop.get('assetPath'):
            target=work/'assets'/prop['assetPath'];target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'assets'/prop['assetPath'],target)
    result=subprocess.run([sys.executable,'-B',str(work/'tools/build_morrow_coast.py')],cwd=work,capture_output=True,text=True,timeout=240)
    assert result.returncode==0,result.stdout+result.stderr
    data=json.loads((work/'worlds/morrow-coast.world.json').read_text())
    a,b=data['roads'][0],data['roads'][-1]
    assert a['anchors'][0]==original['anchors'][0] and b['anchors'][-1]==original['anchors'][-1]
    assert a['anchors'][-1]==b['anchors'][0] and a['end']==b['start']
    assert data['nodes'][original['end']]==original['anchors'][-1], 'Splitting moved the former shared endpoint'
    print('ROAD SPLIT PRODUCTION BAKE: PASS (endpoints, new road, shared join and graph)')
