"""Reproduce real road+house saves from the existing archive, without retargeting
the edited house to a newly generated test world."""
import json,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
import map_editor_server as server
doc=json.loads((ROOT/'.runtime/basic-editor-test/source.json').read_text())
house=next(p for p in doc['props'] if p.get('sourceAppearance') and p.get('scaleX')==.9)
with tempfile.TemporaryDirectory(prefix='streetbound-basic-') as tmp:
    work=Path(tmp);shutil.copytree(ROOT/'tools',work/'tools',ignore=shutil.ignore_patterns('__pycache__'))
    # Race validation needs the complete live roster in the isolated builder.
    (work/'data').mkdir(exist_ok=True)
    for catalog in ('player_vehicle_catalog.json', 'player_vehicle_additions.json'):
        shutil.copy2(ROOT/'data'/catalog, work/'data'/catalog)
    path=work/'map-editor/maps/morrow-coast.edits.world.json';path.parent.mkdir(parents=True);(work/'worlds').mkdir()
    shutil.copy2(ROOT/'map-editor/maps/morrow-coast.edits.world.json',path)
    shutil.copy2(ROOT/'worlds/morrow-coast.world.json',work/'worlds/morrow-coast.world.json')
    server.ROOT=work;server.EDIT=path;server.BAKED=work/'worlds/morrow-coast.world.json'
    server.OVERVIEW=work/'map-editor/maps/morrow-coast.overview.svg';server.BUILDER=work/'tools/build_morrow_coast.py'
    for prop in doc['props']:
        if prop.get('assetPath'):
            target=work/'assets'/prop['assetPath'];target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'assets'/prop['assetPath'],target)
    def bake():
        response=server.transactional_rebuild(doc,server.digest(server.BAKED))
        assert response['ok'],response
        return json.loads((work/'worlds/morrow-coast.world.json').read_text())
    for repeat in range(2):
        baked=bake()
        prop=next(p for p in baked['props'] if p.get('authoring_id')==house['id'])
        assert prop['p']==[round(house['x'],3),round(house['y'],3)]
        assert prop['kind']==house['sourceAppearance']['kind'] and prop['seed']==house['sourceAppearance']['seed']
        assert prop['size']==[round(house['assetSize'][0]*.9,3),round(house['assetSize'][1]*1.1,3)]
        assert baked['roads'][0]['anchors']==[[p['x'],p['y']] for p in doc['roads'][0]['points']]
        assert abs(baked['roads'][0]['width']-12/doc.get('morrowRoadWidthScale',1)*1.1)<.001
        assert any('separate' in warning for warning in baked['editor_warnings'])
        assert any('overlaps a road' in warning for warning in baked['editor_warnings'])
        house['x']+=.5
    print('BASIC EDITOR SAVE: PASS (actual archived house, reshaped road, separate road, repeated bake)')
