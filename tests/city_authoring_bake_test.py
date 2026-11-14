"""Bake sidewalks in an isolated world and verify streamed assignments."""
import json,math,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from building_footprints import overlaps
a={'kind':'house','p':[0,0],'size':[10,20],'angle':0,'radius':12}
b={**a,'p':[10,0]}
assert not overlaps(a,b),'Touching building walls must be allowed'
assert overlaps(a,{**b,'p':[9,0]}),'Penetrating building footprints must be rejected'
assert not overlaps({**a,'angle':math.pi/2},{**b,'angle':math.pi/2,'p':[0,10]})
doc=json.loads((ROOT/'.runtime/road-edit-audit/city-source.json').read_text())
with tempfile.TemporaryDirectory(prefix='streetbound-city-') as tmp:
    work=Path(tmp);shutil.copytree(ROOT/'tools',work/'tools',ignore=shutil.ignore_patterns('__pycache__'))
    path=work/'map-editor/maps/morrow-coast.edits.world.json';path.parent.mkdir(parents=True);(work/'worlds').mkdir()
    path.write_text(json.dumps(doc))
    for p in doc['props']:
        if p.get('assetPath'):
            target=work/'assets'/p['assetPath'];target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'assets'/p['assetPath'],target)
    result=subprocess.run([sys.executable,'-B',str(work/'tools/build_morrow_coast.py')],cwd=work,capture_output=True,text=True,timeout=240)
    assert result.returncode==0,result.stdout+result.stderr
    baked=json.loads((work/'worlds/morrow-coast.world.json').read_text())
    index=next(i for i,p in enumerate(baked['props']) if p['kind']=='sidewalk')
    p=baked['props'][index]
    assert p['sidewalk_width']==3 and len(p['sidewalk_points'])==3 and not p['solid']
    assert p['size']==[303,303]
    for x,y in [(3000,3000),(3300,3000),(3300,3300)]:
        assert index in baked['chunks'][f'{int(x//192)},{int(y//192)}']['props'],'Sidewalk missing from crossed chunk'
    (ROOT/'.runtime/road-edit-audit/city-bake.world.json').write_text(json.dumps(baked))
    print('CITY AUTHORING BAKE: PASS (wall clearance, full path, traffic isolation and streamed cells)')
