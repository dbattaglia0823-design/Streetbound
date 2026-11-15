"""Editor race definitions must reach the real game archive unchanged."""
import json,shutil,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from authored_races import authored_races
doc=json.loads((ROOT/'.runtime/race-editor-test/source.json').read_text())
expected=doc['races'][0]
with tempfile.TemporaryDirectory(prefix='streetbound-race-') as tmp:
    work=Path(tmp);shutil.copytree(ROOT/'tools',work/'tools',ignore=shutil.ignore_patterns('__pycache__'))
    path=work/'map-editor/maps/morrow-coast.edits.world.json';path.parent.mkdir(parents=True);(work/'worlds').mkdir()
    path.write_text(json.dumps(doc))
    for prop in doc['props']:
        if prop.get('assetPath'):
            target=work/'assets'/prop['assetPath'];target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/'assets'/prop['assetPath'],target)
    result=subprocess.run([sys.executable,'-B',str(work/'tools/build_morrow_coast.py')],cwd=work,capture_output=True,text=True,timeout=240)
    assert result.returncode==0,result.stdout+result.stderr
    baked=json.loads((work/'worlds/morrow-coast.world.json').read_text())
    race=next(r for r in baked['editor_races'] if r['id']==expected['id'])
    assert race==expected,(race,expected)
    assert any(m.get('race',{}).get('id')==expected['id'] for m in baked['editor_markers'])
    (ROOT/'.runtime/race-editor-test/baked-races.json').write_text(json.dumps(baked['editor_races']))
    print('RACE EDITOR BAKE: PASS (race title, circuit, laps, checkpoints and game archive)')
for patch in [{'points':[{'x':0,'y':0}]},{'laps':1.5},{'checkpoint_radius':float('nan')},{'mode':'invalid'}]:
    invalid=json.loads(json.dumps(doc));invalid['races'][0].update(patch)
    try:authored_races(invalid,doc['world']['width'],doc['world']['height'])
    except ValueError:pass
    else:raise AssertionError('Invalid race was accepted: '+str(patch))
print('RACE EDITOR VALIDATION: PASS')
