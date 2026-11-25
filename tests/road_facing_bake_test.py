"""Bake real editor placements without modifying the user's playable world."""
import json
import math
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
native = json.loads((ROOT/'.runtime/road-facing/source.json').read_text())
doc = json.loads((ROOT/'map-editor/maps/morrow-coast.edits.world.json').read_text())
first = len(doc['roads'])
for index, road in enumerate(native['roads']):
    road['id'] = f'road-{first+index}'
    road['name'] = f'Frontage test road {index}'
    doc['roads'].append(road)
for index, prop in enumerate(native['props']):
    prop['id'] = f'prop-frontage-test-{index}'
    doc['props'].append(prop)

with tempfile.TemporaryDirectory(prefix='road-facing-', dir=ROOT/'.runtime') as temporary:
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
    for prop in doc['props']:
        if prop.get('assetPath'):
            target = work/'assets'/prop['assetPath']
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT/'assets'/prop['assetPath'], target)
    result = subprocess.run([sys.executable, '-B', str(work/'tools/build_morrow_coast.py')],
                            cwd=work, capture_output=True, text=True, timeout=240)
    assert result.returncode == 0, result.stdout+result.stderr
    archive = json.loads((work/'worlds/morrow-coast.world.json').read_text())
    for source in native['props']:
        index = next(i for i, p in enumerate(archive['props']) if p.get('authoring_id') == source['id'])
        baked = archive['props'][index]
        assert baked['p'] == [round(source['x'], 3), round(source['y'], 3)]
        assert abs(baked['angle']-math.radians(source['rotation'])) < 1e-8
        assert baked.get('editor_road_facing', True) == source.get('roadFacing', True)
        assert baked.get('editor_road_front', 90) == source.get('roadFront', 90)
        assert baked['size'] == [round(s*source['scale']*source.get(axis, 1), 3)
                                 for s, axis in zip((12, 17), ('scaleX', 'scaleY'))]
        assert index in archive['chunks'][f"{int(source['x']//192)},{int(source['y']//192)}"]['props']
        assert baked['solid'], 'Visible house must retain its matching collision footprint'
    print('ROAD-FACING BAKE: PASS (per-asset preferences, transforms, scaled collision footprints and streamed positions)')
