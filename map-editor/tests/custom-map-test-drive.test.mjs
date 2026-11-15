import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const source = path => readFileSync(new URL('../../'+path,import.meta.url),'utf8');
const editor=source('scripts/dev/native_world_editor.gd');
const standalone=source('scripts/dev/standalone_map_editor.gd');
const drive=source('scripts/dev/custom_map_test_drive.gd');
const world=source('scripts/dev/custom_map_drive_world.gd');
const renderer=source('scripts/dev/native_world_editor_gizmos.gd');

test('custom Test Drive saves the selected map and launches its own scene',()=>{
  assert.match(editor,/if map_switcher\.custom:[\s\S]*?map_switcher\.save_current\(self\)/);
  assert.match(editor,/set_meta\("streetbound_test_drive_map",map_switcher\.current_file\)/);
  assert.match(editor,/change_scene_to_file\("res:\/\/scenes\/custom_map_test_drive\.tscn"\)/);
  assert.doesNotMatch(editor,/Test Drive currently opens Morrow Coast/);
});
test('playtest loads and validates only its selected saved custom-map document',()=>{
  assert.match(drive,/Library\.load_map\(source_file\)/);
  assert.match(world,/EditSession\.new\(\)/);
  assert.match(world,/validator\._valid_source\(source\)/);
  assert.match(world,/bool\(source\.get\("customMap",false\)\)/);
  assert.match(drive,/Vehicle\.instantiate\(\)/);
  assert.match(drive,/player\.surface_provider = world/);
  assert.match(world,/EditSession\.road_path\(road\)/);
  assert.match(world,/drawing\.runtime_playtest = true/);
  assert.match(renderer,/if runtime_playtest:\s*return/);
});
test('F6 and the return button reopen the saved map without career writes',()=>{
  assert.match(drive,/button\.pressed\.connect\(_return_to_editor\)/);
  assert.match(drive,/KEY_F6/);
  assert.match(drive,/set_meta\("streetbound_editor_resume_map",source_file\)/);
  assert.match(standalone,/func _resume_custom_map\(file: String\)/);
  assert.match(standalone,/map_switcher\.activate\(native_world_editor,doc,file\)/);
  assert.doesNotMatch(drive,/Ownership|Progression|SaveGame/);
});
