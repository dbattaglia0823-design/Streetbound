"""Bake an unmarked lake-crossing road in a temporary copy of the real world."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]


def main():
    doc=json.loads((ROOT/'map-editor/maps/morrow-coast.edits.world.json').read_text(encoding='utf-8'))
    source=next(r for r in doc['roads'] if r['id']=='road-52')
    doc['roads'].append(dict(id=f"road-{len(doc['roads'])}",name='QA automatic lake bridge',
        roadClass='country',surface='asphalt',width=10,lanes=2,shoulder=2,smooth=True,markings=True,
        points=[source['points'][0],dict(x=900,y=1490),dict(x=1660,y=1490),source['points'][-1]]))
    with tempfile.TemporaryDirectory(prefix='streetbound-automatic-bridges-') as temporary:
        work=Path(temporary)
        shutil.copytree(ROOT/'tools',work/'tools',ignore=shutil.ignore_patterns('__pycache__'))
        (work/'worlds').mkdir();(work/'map-editor/maps').mkdir(parents=True)
        for prop in doc.get('props',[]):
            if prop.get('assetPath'):
                target=work/'assets'/prop['assetPath'];target.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(ROOT/'assets'/prop['assetPath'],target)
        (work/'map-editor/maps/morrow-coast.edits.world.json').write_text(json.dumps(doc),encoding='utf-8')
        result=subprocess.run([sys.executable,'-B',str(work/'tools/build_morrow_coast.py')],cwd=work,
                              capture_output=True,text=True,timeout=240)
        assert result.returncode==0,result.stdout+result.stderr
        world=json.loads((work/'worlds/morrow-coast.world.json').read_text(encoding='utf-8'))
        road=next(r for r in world['roads'] if r['name']=='QA automatic lake bridge')
        bridges=[b for b in world['bridges'] if b['road']==road['id']]
        assert bridges,'New road over the lake did not automatically gain a bridge'
        assert all(abs(b['width']-road['width'])<.001 for b in bridges),'Bridge width does not match adapted pavement'
        assert world['bridge_generation']==1 and world['bridge_wall_indices']
        for i in world['bridge_wall_indices']:
            assert any(i in cell['walls'] for cell in world['chunks'].values()),'Bridge rail has no collision chunk'
        for i in range(len(world['bridges'])):
            assert any(i in cell.get('bridges',[]) for cell in world['chunks'].values()),'Bridge has no render chunk'
        print(f"AUTOMATIC BRIDGE PRODUCTION BAKE: PASS ({len(bridges)} new spans, correct width, rails and streaming)")


if __name__=='__main__':main()
