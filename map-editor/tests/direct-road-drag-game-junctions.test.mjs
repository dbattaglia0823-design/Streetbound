import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createWorld,createEntity} from '../world-model.js';
import {translateEntity} from '../world-edit-tools.js';

const source=path=>readFile(new URL(path,import.meta.url),'utf8');
const point=(x,y)=>({x,y});
const settings={roadClass:'city',surface:'asphalt',lanes:2,width:36,
  shoulder:4,smooth:false,markings:true};

test('whole-road translation preserves every relative control point and original world',()=>{
  let doc=createWorld({width:1500,height:1100});
  doc=createEntity(doc,'roads',{...settings,name:'Street',
    points:[point(100,200),point(250,280),point(400,270)]});
  const before=structuredClone(doc);
  const moved=translateEntity(doc,doc.roads[0].id,80,-35);
  assert.deepEqual(moved.roads[0].points,
    [point(180,165),point(330,245),point(480,235)]);
  assert.deepEqual(doc,before,'source remains available for one-step undo');
  assert.equal(moved.roads[0].id,doc.roads[0].id);
});
test('whole-region translation clamps map edges without changing terrain shape',()=>{
  let doc=createWorld({width:600,height:600});
  doc=createEntity(doc,'regions',{name:'Field',biome:'grass',elevation:0,
    points:[point(300,200),point(450,200),point(450,340),point(300,340)]});
  const moved=translateEntity(doc,doc.regions[0].id,300,400);
  assert.deepEqual(moved.regions[0].points,
    [point(450,460),point(600,460),point(600,600),point(450,600)]);
});
test('clicking a road or region body starts full shape drag but handles still reshape',async()=>{
  const editor=await source('../world-editor.js');
  assert.match(editor,/hit\.kind==='handle'\)\{/);
  assert.match(editor,/found&&\['roads','regions'\]\.includes\(found\.type\)&&hit\.kind==='entity'/);
  assert.match(editor,/gesture=\{mode:'shape',before:doc,id:hit\.id,start:p\}/);
  assert.match(editor,/translateEntity\(gesture\.before,gesture\.id,p\.x-gesture\.start\.x,p\.y-gesture\.start\.y\)/);
  assert.match(editor,/makeSnapshot\(current\.before/);
});
test('renderer avoids fake convex junction fills and uses exact saved game pavement',async()=>{
  const [renderer,automation]=await Promise.all([
    source('../world-renderer.js'),source('../world-automation-preview.js')]);
  assert.doesNotMatch(renderer,/for\(const junction of buildRoadJunctions\(roads\)\)\s*\{[\s\S]{0,300}junction\.polygon/);
  assert.match(renderer,/ctx\.clip\('evenodd'\)/);
  assert.match(renderer,/j\.polygon\.map\(\(\[x,y\]\)=>\(\{x,y\}\)\)/);
  assert.match(renderer,/j\.roads\.every\(unchanged\)/);
  assert.doesNotMatch(automation,/j\.polygon\[0\]/);
});
