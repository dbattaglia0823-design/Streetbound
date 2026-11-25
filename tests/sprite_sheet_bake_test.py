"""Bake the actual native-editor sprite selections in an isolated map copy."""
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
native=json.loads((ROOT/'.runtime/sprite-sheets/source.json').read_text())
expected=json.loads((ROOT/'.runtime/sprite-sheets/expected.json').read_text())
doc=json.loads((ROOT/'map-editor/maps/morrow-coast.edits.world.json').read_text())
for index,prop in enumerate(native['props']):
    prop['id']=f'prop-sheet-regression-{index}'
    doc['props'].append(prop)
with tempfile.TemporaryDirectory(prefix='sprite-sheets-',dir=ROOT/'.runtime') as temporary:
    work=Path(temporary)
    shutil.copytree(ROOT/'tools',work/'tools',ignore=shutil.ignore_patterns('__pycache__'))
    # Race validation needs the complete live roster in the isolated builder.
    (work/'data').mkdir(exist_ok=True)
    for catalog in ('player_vehicle_catalog.json', 'player_vehicle_additions.json'):
        shutil.copy2(ROOT/'data'/catalog, work/'data'/catalog)
    source=work/'map-editor/maps/morrow-coast.edits.world.json';source.parent.mkdir(parents=True)
    source.write_text(json.dumps(doc))
    (work/'worlds').mkdir();shutil.copy2(ROOT/'worlds/morrow-coast.world.json',work/'worlds/morrow-coast.world.json')
    for prop in doc['props']:
        if not prop.get('assetPath'):continue
        image=ROOT/'assets'/prop['assetPath'];target=work/'assets'/prop['assetPath'];target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(image,target)
        for suffix in ('.sheet.json','.asset.json'):
            if image.with_suffix(suffix).is_file():shutil.copy2(image.with_suffix(suffix),target.with_suffix(suffix))
    run=subprocess.run([sys.executable,'-B',str(work/'tools/build_morrow_coast.py')],cwd=work,capture_output=True,text=True,timeout=240)
    assert run.returncode==0,run.stdout+run.stderr
    archive=json.loads((work/'worlds/morrow-coast.world.json').read_text())
    output=[]
    for raw,wanted in zip(native['props'],expected):
        index=next(i for i,p in enumerate(archive['props']) if p.get('authoring_id')==raw['id'])
        prop=archive['props'][index]
        assert prop['asset_path']==wanted['path'] and prop['asset_region']==wanted['region']
        assert prop['asset_id']==wanted['asset_id']
        assert prop['solid']==(wanted['collision']=='solid')
        assert prop['p']==[round(raw['x'],3),round(raw['y'],3)]
        assert abs(prop['angle']-math.radians(raw['rotation']))<1e-8
        assert prop['size']==[round(v*raw['scale']*raw.get(axis,1),3) for v,axis in zip(raw['assetSize'],('scaleX','scaleY'))]
        assert index in archive['chunks'][f"{int(prop['p'][0]//192)},{int(prop['p'][1]//192)}"]['props']
        output.append(prop)
    (ROOT/'.runtime/sprite-sheets/baked-props.json').write_text(json.dumps(output))
    print('SPRITE SHEET BAKE: PASS (six sheets, separate regions, sizes, rotation, collisions and streamed assignments)')
