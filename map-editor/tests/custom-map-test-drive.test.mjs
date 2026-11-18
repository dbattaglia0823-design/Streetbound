import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source=path=>readFileSync(new URL('../../'+path,import.meta.url),'utf8');
const editor=source('scripts/dev/native_world_editor.gd');
const standalone=source('scripts/dev/standalone_map_editor.gd');
const launcher=source('scripts/dev/custom_map_test_drive.gd');
const game=source('scripts/main.gd');
const world=source('scripts/world/morrow_coast.gd');
const builder=source('tools/build_custom_test_world.py');

test('custom Test Drive saves only the selected map before starting the launcher',()=>{
  assert.match(editor,/if map_switcher\.custom:[\s\S]*?map_switcher\.save_current\(self\)/);
  assert.match(editor,/set_meta\("streetbound_test_drive_map",map_switcher\.current_file\)/);
  assert.match(editor,/change_scene_to_file\("res:\/\/scenes\/custom_map_test_drive\.tscn"\)/);
});
test('custom playtesting validates and compiles the saved map into normal game geometry',()=>{
  assert.match(launcher,/Library\.load_map\(file\)/);
  assert.match(launcher,/Session\.new\(\)\._valid_source\(source\)/);
  assert.match(launcher,/OS\.execute\(python,args,output,true\)/);
  assert.match(launcher,/streetbound_test_drive_archive/);
  assert.match(launcher,/change_scene_to_file","res:\/\/scenes\/main\.tscn"/);
  assert.match(builder,/from junction_bake import build_junctions/);
  assert.match(builder,/junctions,connections,crossings=build_junctions\(/);
  assert.match(builder,/editor_races=baked_races/);
  assert.match(world,/archive_override_path/);
  assert.match(world,/editor_custom_test_drive/);
  assert.match(game,/ground = GroundScript\.new\(\) if proving_ground else CoastScript\.new\(\)/);
  assert.match(game,/TrafficFlowScript/);
  assert.match(game,/AuthoredRaceScript/);
});
test('F6 and the return button restore the selected map without modifying career',()=>{
  assert.match(game,/func _return_from_test_drive\(\)/);
  assert.match(game,/func _add_test_drive_return_button\(\)/);
  assert.match(game,/KEY_F6/);
  assert.match(game,/set_meta\("streetbound_editor_resume_map",test_drive_file\)/);
  assert.match(game,/vehicle_ownership\.persist_enabled=false/);
  assert.match(standalone,/func _resume_custom_map\(file: String\)/);
  assert.match(standalone,/map_switcher\.activate\(native_world_editor,doc,file\)/);
  assert.doesNotMatch(builder,/worlds\/morrow-coast\.world\.json[\s\S]*write_text/);
});
