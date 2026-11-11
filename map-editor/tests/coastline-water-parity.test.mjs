import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {convertMorrowWorld} from '../morrow-coast-bridge.js';
import {buildRuntimePreview,drawRuntimeTerrain} from '../morrow-runtime-preview.js';
import {drawWorld,GAME_BIOME_COLORS} from '../world-renderer.js';

const coastline=Array.from({length:360},(_,i)=>{
  const y=i*4800/359;
  return [5190+85*Math.sin(y/380),y];
});
function sourceWorld(){
  return {
    format:'streetbound.streamed-world',version:1,size:[6400,4800],
    spawn:{position:[4400,2300],rotation:0},
    roads:[{name:'Near-shore road',kind:'rural',surface:'ASPHALT',
      width:12,lanes:2,
      anchors:[[4300,2250],[4800,2360],[4930,2450]],
      points:[[4300,2250],[4500,2280],[4800,2360],[4930,2450]]}],
    terrain:[
      {kind:'beach',color:'e3d4aa',points:[
        ...coastline.map(([x,y])=>[x-65,y]),[6400,4800],[6400,0]]},
      {kind:'ocean',color:'82b5b5',points:[
        ...coastline,[6400,4800],[6400,0]]},
      {kind:'foam',color:'c6d9c9',points:[
        ...coastline.map(([x,y])=>[x-1,y]),
        ...[...coastline].reverse().map(([x,y])=>[x+1.2,y])]}
    ],
    props:[],pois:[],junctions:[]
  };
}
function recordingCanvas(){
  const fills=[],rects=[],strokes=[];
  let points=[];
  const ctx={
    fills,rects,strokes,fillStyle:null,strokeStyle:null,lineWidth:1,
    save(){},restore(){},beginPath(){points=[];},
    moveTo(x,y){points.push([x,y]);},
    lineTo(x,y){points.push([x,y]);},
    closePath(){},
    fill(){fills.push({color:this.fillStyle,points:[...points]});},
    stroke(){strokes.push({color:this.strokeStyle,width:this.lineWidth,points:[...points]});},
    setLineDash(){},
    fillRect(x,y,w,h){rects.push({color:this.fillStyle,x,y,w,h});}
  };
  return ctx;
}

test('unedited ocean keeps every baked coastline vertex and does not draw editor proxies',()=>{
  const raw=sourceWorld();
  const {doc}=convertMorrowWorld(raw);
  const preview=buildRuntimePreview(raw);
  assert.ok(doc.regions.find(r=>r.id==='region-1').points.length<=180);
  assert.ok(raw.terrain[1].points.length>350);
  const ctx=recordingCanvas(),edits=[];
  assert.equal(drawRuntimeTerrain(ctx,preview,doc,(region)=>edits.push(region.id)),true);
  assert.deepEqual(edits,[],'unchanged source-region proxies must never repaint the ocean');
  assert.equal(ctx.fills.length,raw.terrain.length);
  assert.deepEqual(ctx.fills[1].points,raw.terrain[1].points,
    'the full high-resolution source polygon is drawn, not a simplified proxy');
  assert.deepEqual(ctx.fills.map(x=>x.color),['#e3d4aa','#82b5b5','#c6d9c9']);
});

test('editing one coastline region replaces only that original layer without moving roads',()=>{
  const raw=sourceWorld();
  const {doc}=convertMorrowWorld(raw);
  const sourceRoad=structuredClone(doc.roads[0]);
  const preview=buildRuntimePreview(raw);
  const modified={...doc,regions:doc.regions.map(r=>r.id==='region-1'
    ? {...r,points:r.points.map((p,i)=>i===0?{...p,x:p.x-40}:p)}:r)};
  const ctx=recordingCanvas(),edited=[];
  drawRuntimeTerrain(ctx,preview,modified,(region,source)=>{
    edited.push({id:region.id,index:source?.index,color:source?.color});
  });
  assert.deepEqual(edited,[{id:'region-1',index:1,color:'82b5b5'}]);
  assert.deepEqual(modified.roads[0],sourceRoad,'terrain preview cannot rescale or move roads');
});

test('main game-map canvas uses actual Godot base color, coastal polygon and baked road path',()=>{
  const raw=sourceWorld();
  const {doc}=convertMorrowWorld(raw);
  const preview=buildRuntimePreview(raw);
  const ctx=recordingCanvas();
  drawWorld(ctx,doc,{runtimePreview:preview,quality:0,junctions:false,
    showScenery:false,showMarkers:false});
  assert.equal(ctx.rects[0].color,'#a3b789','base land matches the Godot ground fill');
  assert.equal(GAME_BIOME_COLORS.ocean,'#82b5b5');
  assert.deepEqual(ctx.fills[1].points,raw.terrain[1].points);
  assert.equal(ctx.fills[1].color,'#82b5b5',
    'never substitute the dark demo ocean over a live game road');
  assert.ok(ctx.strokes.some(stroke=>stroke.width===12 &&
    stroke.points.length===raw.roads[0].points.length &&
    stroke.points.every((p,i)=>p[0]===raw.roads[0].points[i][0] &&
      p[1]===raw.roads[0].points[i][1])),
    'road draw must use Godot baked centerline in unchanged-world preview');
});

test('main canvas and minimap share the same source terrain and road projection',async()=>{
  const editor=await readFile(new URL('../world-editor.js',import.meta.url),'utf8');
  const mainCall=editor.slice(editor.indexOf('drawWorld(ctx,doc,{'),editor.indexOf('drawEditorOverlay(ctx,doc,{'));
  const miniCall=editor.slice(editor.indexOf('drawWorld(miniCtx,doc,{'),
    editor.indexOf('miniCtx.restore();',editor.indexOf('drawWorld(miniCtx,doc,{')));
  assert.match(mainCall,/runtimePreview/);
  assert.match(miniCall,/runtimePreview/);
  assert.match(miniCall,/quality:0/);
  assert.match(miniCall,/showScenery:false/,
    'overview must not redraw thousands of game props on each map interaction');
});
