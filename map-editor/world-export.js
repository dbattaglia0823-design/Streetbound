import {createZip} from '../package/zip.js';
import {normalizeWorld,serializeWorld} from './world-model.js';
import {sampleRoad} from './world-geometry.js';
import {buildRoadJunctions} from './world-junctions.js';
export const worldSlug = name => String(name||'world').toLowerCase().replace(/[^a-z0-9_-]+/g,'-').replace(/^-+|-+$/g,'').slice(0,55)||'world';
/** Samples preserve continuous road centerlines for player navigation and racing AI.
 * Derived junctions include exact crossings and overlapping/T/end connections,
 * with shared IDs, geometry, and road-pair links. Routing is still game-owned.
 */
export function buildRoadNetwork(doc){
  const world=normalizeWorld(doc);
  const roads=world.roads.map(r=>({id:r.id,name:r.name,roadClass:r.roadClass,surface:r.surface,
    width:r.width,lanes:r.lanes,shoulder:r.shoulder,
    centerline:sampleRoad(r.points,r.smooth,22).map(p=>[Math.round(p.x*100)/100,Math.round(p.y*100)/100])}));
  const round=v=>Math.round(v*100)/100;
  const junctions=buildRoadJunctions(world.roads).map(j=>({
    id:j.id,at:[round(j.x),round(j.y)],kind:j.kind,
    roadIds:j.roads,radius:round(j.radius),surface:j.surface,
    polygon:j.polygon.map(p=>[round(p.x),round(p.y)])
  }));
  const connections=junctions.flatMap(j=>{
    const pairs=[];
    for(let i=0;i<j.roadIds.length;i++)for(let k=i+1;k<j.roadIds.length;k++){
      pairs.push({roads:[j.roadIds[i],j.roadIds[k]],at:j.at,kind:j.kind,junctionId:j.id});
    }
    return pairs;
  });
  return {format:'gdt.racing-road-network',version:1,source:world.name,worldSize:world.world,
    roads,junctions,connections,verifiedNavigation:false};
}
export function buildWorldZip(doc,loader){
  const world=normalizeWorld(doc);
  if(typeof loader!=='string'||!loader.includes('extends Node2D')||!loader.includes('load_world'))throw new TypeError('Godot world adapter source missing');
  const name=worldSlug(world.name),path='worlds/'+name+'.world.json',roads='navigation/'+name+'.roads.json';
  const files=new Map([
    [path,serializeWorld(world)],
    [roads,JSON.stringify(buildRoadNetwork(world),null,2)+'\n'],
    ['runtime/world_loader.gd',loader],
    ['manifest.json',JSON.stringify({format:'gdt-racing-world-package',version:1,targetEngine:'Godot 4.3+',worldFile:path,roadNetwork:roads,adapter:'runtime/world_loader.gd',worldFormat:world.format,worldVersion:world.version,gameplayIntegrated:false},null,2)+'\n'],
    ['CODEX_IMPORT.md',[
      '# Freeform Racing World / Godot 4',
      '',
      '1. Copy worlds/, navigation/, and runtime/ into res:// in the target Godot 4 project.',
      '2. Add a Node2D, attach runtime/world_loader.gd, set world_path to res://'+path+'.',
      '3. The loader draws vector terrain, continuous Catmull-Rom road strokes, stylized props, and static blockers for water and solid buildings.',
      '4. Use get_markers(), get_road_paths(), get_surface_at(Vector2), and road_near(Vector2) in your game.',
      '5. navigation/*.roads.json includes sampled road centerlines, polygons and IDs for all derived cross/T/end junctions and road-pair connections. Use these hints for turn routing, not as a ready-to-use traffic solver.',
      '6. Connect markers to your existing car spawn, races, traffic, garages, and trigger systems. Do not assume the file creates those systems.',
      '7. Crossings are at-grade by default. Model intentional overpasses/underpasses and traffic controls in your game before relying on automatic turn connections. Verify road widths and corner geometry in Godot, and implement surface-dependent grip.',
      '8. Keep world geometry and player save state separate. No existing saves or v1 maps are modified.',
      '',
      'Limitations: stylized vector placeholders are not a final high-resolution art pack. No generated 3D elevation mesh, streaming/chunk system, route/turn permission solver, automatic traffic AI, traffic lights, or physics-based road bank is included.',
      'For the classic tile editor, use web/map-builder/legacy.html.',
      ''
    ].join('\n')]
  ]);
  return {files,bytes:createZip(files,{maxFileSize:8_000_000}),manifest:JSON.parse(files.get('manifest.json'))};
}
