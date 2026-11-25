"""Bake the native editor's actual shaped roads in an isolated Morrow copy."""
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
native = json.loads((ROOT/'.runtime/road-shapes/source.json').read_text())
doc = json.loads((ROOT/'map-editor/maps/morrow-coast.edits.world.json').read_text())
first = len(doc['roads'])
for index, road in enumerate(native['roads']):
    road['id'] = f'road-{first+index}'
    road['name'] = f'Shape tool regression {index}'
    doc['roads'].append(road)

with tempfile.TemporaryDirectory(prefix='road-shapes-', dir=ROOT/'.runtime') as temporary:
    work = Path(temporary)
    shutil.copytree(ROOT/'tools', work/'tools', ignore=shutil.ignore_patterns('__pycache__'))
    # Race validation needs the complete live roster in the isolated builder.
    (work/'data').mkdir(exist_ok=True)
    for catalog in ('player_vehicle_catalog.json', 'player_vehicle_additions.json'):
        shutil.copy2(ROOT/'data'/catalog, work/'data'/catalog)
    overlay = work/'map-editor/maps/morrow-coast.edits.world.json'
    overlay.parent.mkdir(parents=True)
    (work/'worlds').mkdir()
    overlay.write_text(json.dumps(doc))
    shutil.copy2(ROOT/'worlds/morrow-coast.world.json', work/'worlds/morrow-coast.world.json')
    for prop in doc.get('props', []):
        if prop.get('assetPath'):
            target = work/'assets'/prop['assetPath']
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT/'assets'/prop['assetPath'], target)
    result = subprocess.run([sys.executable, '-B', str(work/'tools/build_morrow_coast.py')],
                            cwd=work, capture_output=True, text=True, timeout=240)
    assert result.returncode == 0, result.stdout+result.stderr
    archive = json.loads((work/'worlds/morrow-coast.world.json').read_text())
    shaped = [next(r for r in archive['roads'] if r['name'] == source['name']) for source in native['roads']]
    for index, source in enumerate(native['roads']):
        baked = shaped[index]
        expected = [[round(p['x'], 3), round(p['y'], 3)] for p in source['points']]
        assert baked['anchors'] == expected, (index, baked['anchors'], expected)
        assert any(any(archive['segments'][s]['road'] == baked['id'] for s in c['segments']) for c in archive['chunks'].values()), 'Road missing from chunk index'
    circle = shaped[2]
    assert circle['start'] == circle['end'], 'Circular road must have a continuous traffic seam'
    assert circle['points'][0] == circle['points'][-1]
    assert max(abs(math.dist(p, (1400, 950))-80) for p in circle['points']) < .02
    initial = [circle['points'][1][k]-circle['points'][0][k] for k in (0, 1)]
    final = [circle['points'][-1][k]-circle['points'][-2][k] for k in (0, 1)]
    assert sum(a*b for a, b in zip(initial, final))/math.hypot(*initial)/math.hypot(*final) > .99
    assert any(circle['id'] in j['roads'] and shaped[3]['id'] in j['roads'] for j in archive['junctions']), 'Roundabout entry lacks a junction'
    print('ROAD SHAPE BAKE: PASS (curves, circle radius, smooth seam, junction and streamed chunks)')
