"""Production T-junction regression, in a separate copy of the map."""
import json,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
doc=json.loads((ROOT/'.runtime/road-edit-audit/junction-source.json').read_text())
with tempfile.TemporaryDirectory(prefix='streetbound-junction-') as temporary:
    work=Path(temporary);shutil.copytree(ROOT/'tools',work/'tools',ignore=shutil.ignore_patterns('__pycache__'))
    # Race validation needs the complete live roster in the isolated builder.
    (work/'data').mkdir(exist_ok=True)
    for catalog in ('player_vehicle_catalog.json', 'player_vehicle_additions.json'):
        shutil.copy2(ROOT/'data'/catalog, work/'data'/catalog)
    path=work/'map-editor/maps/morrow-coast.edits.world.json';path.parent.mkdir(parents=True);(work/'worlds').mkdir()
    path.write_text(json.dumps(doc))
    for prop in doc['props']:
        if prop.get('assetPath'):
            target=work/'assets'/prop['assetPath'];target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'assets'/prop['assetPath'],target)
    result=subprocess.run([sys.executable,'-B',str(work/'tools/build_morrow_coast.py')],cwd=work,capture_output=True,text=True,timeout=240)
    assert result.returncode==0,result.stdout+result.stderr
    baked=json.loads((work/'worlds/morrow-coast.world.json').read_text())
    branch=baked['roads'][-1]['id']
    assert any(0 in j['roads'] and branch in j['roads'] and len(j['approaches'])>=3 for j in baked['junctions']), 'Missing saved T-junction'
    assert any(set(c)=={0,branch} for c in baked['road_connections']), 'Junction missing from navigation graph'
    print('EDITOR JUNCTION BAKE: PASS (mid-road connection, automatic junction and navigation)')
