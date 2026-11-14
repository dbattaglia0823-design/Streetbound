"""Check exact adopted artwork and nonuniform transforms through the real bake."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
doc=json.loads((ROOT/'.runtime/road-edit-audit/asset-source.json').read_text())
edited=next(p for p in doc['props'] if p.get('sourceAppearance') and p.get('scaleX')==.8 and p.get('scaleY')==.6)
original=edited['sourceAppearance']
with tempfile.TemporaryDirectory(prefix='streetbound-asset-') as temporary:
    work=Path(temporary)
    shutil.copytree(ROOT/'tools',work/'tools',ignore=shutil.ignore_patterns('__pycache__'))
    path=work/'map-editor/maps/morrow-coast.edits.world.json'
    path.parent.mkdir(parents=True);(work/'worlds').mkdir()
    # Reproduce a current generated world first: the checked-in archive may
    # predate edits in the separately saved source overlay.
    baseline=json.loads(json.dumps(doc))
    baseline['props']=[p for p in baseline['props'] if p['id']!=edited['id']]
    path.write_text(json.dumps(baseline))
    for prop in doc['props']:
        if prop.get('assetPath'):
            target=work/'assets'/prop['assetPath'];target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copy2(ROOT/'assets'/prop['assetPath'],target)
    command=[sys.executable,'-B',str(work/'tools/build_morrow_coast.py')]
    result=subprocess.run(command,cwd=work,capture_output=True,text=True,timeout=240)
    assert result.returncode==0,result.stdout+result.stderr
    generated=json.loads((work/'worlds/morrow-coast.world.json').read_text())
    original=next(p for p in generated['props'] if p['kind']=='house' and not p.get('authoring_id') and not p.get('poi') and not p.get('protected'))
    edited.update(x=original['p'][0],y=original['p'][1],assetSize=original['size'],sourceAppearance=original,
                  replaces={'kind':original['kind'],'seed':original['seed'],'p':original['p']})
    path.write_text(json.dumps(doc))
    result=subprocess.run(command,cwd=work,capture_output=True,text=True,timeout=240)
    assert result.returncode==0,result.stdout+result.stderr
    baked=json.loads((work/'worlds/morrow-coast.world.json').read_text())
    prop=next(p for p in baked['props'] if p.get('authoring_id')==edited['id'])
    assert prop['seed']==original['seed'] and prop['kind']==original['kind']
    assert prop.get('asset_kind')==original.get('asset_kind')
    assert prop.get('asset_path')==original.get('asset_path')
    for actual,base,axis in zip(prop['size'],original['size'],[.8,.6]):
        assert abs(actual-base*axis)<.0011,(actual,base,axis)
    assert prop['editor_scale_x']==.8 and prop['editor_scale_y']==.6
    assert prop['source_replacement']['seed']==original['seed']
    assert prop['editor_type']==edited['type']
    print('EDITOR ASSET BAKE: PASS (exact artwork, XY dimensions and reload metadata)')
