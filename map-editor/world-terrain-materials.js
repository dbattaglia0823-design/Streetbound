import {seeded,stringSeed} from './world-geometry.js';

// Matching material families to mountain_ground.gdshader. Patterns are made
// once per biome, in world metres, and shared by the canvas and overview.
export const TERRAIN_COLORS=Object.freeze({grass:'#647d40',forest:'#405332',
  mountain:'#77796a',rock:'#77796a',highland:'#647d40',beach:'#cabb86',
  desert:'#c8a16c',ocean:'#326775',lake:'#3b635a',foam:'#bacbb0',
  farmland:'#697343',city:'#87877a',dirt:'#795b3d',gravel:'#827e70'});
export const terrainFamily=kind=>({town:'grass',meadow:'grass',sand:'beach',water:'lake',
  riverbank:'foam',field:'farmland'})[kind]||kind;
const tiles=new Map(),patterns=new WeakMap();
function makeTile(kind){
  if(tiles.has(kind))return tiles.get(kind);
  const tile=document.createElement('canvas');tile.width=tile.height=512;
  const c=tile.getContext('2d'),rand=seeded(stringSeed('streetbound-terrain-'+kind));
  c.fillStyle=TERRAIN_COLORS[kind]||TERRAIN_COLORS.grass;c.fillRect(0,0,512,512);
  // Wrapped soft patches remove seams at tile edges; there are no hard grids.
  for(let i=0;i<48;i++){
    const x=rand()*512,y=rand()*512,r=25+rand()*100;
    for(const dx of [-512,0,512])for(const dy of [-512,0,512]){
      const g=c.createRadialGradient(x+dx,y+dy,0,x+dx,y+dy,r);
      g.addColorStop(0,i%2?'rgba(20,28,12,.13)':'rgba(216,203,150,.11)');
      g.addColorStop(1,'transparent');c.fillStyle=g;c.fillRect(x+dx-r,y+dy-r,r*2,r*2);
    }
  }
  const grass=['grass','forest','highland'].includes(kind);
  for(let i=0;i<6500;i++){
    const x=rand()*512,y=rand()*512;
    c.fillStyle=i%2?'rgba(27,29,20,.14)':'rgba(229,220,175,.12)';
    c.fillRect(x,y,rand()*1.4+.4,rand()*1.2+.4);
    if(grass&&i%4===0){
      c.strokeStyle=kind==='forest'?'rgba(131,104,61,.27)':'rgba(27,59,20,.28)';
      c.lineWidth=.65;c.beginPath();c.moveTo(x-1,y+1);c.lineTo(x,y-2);
      c.lineTo(x+1,y+1);c.stroke();
    }
  }
  if(['mountain','rock'].includes(kind))for(let i=0;i<110;i++){
    const x=rand()*512,y=rand()*512,len=5+rand()*28;
    c.lineWidth=1.2;c.strokeStyle='rgba(34,35,29,.25)';c.beginPath();
    c.moveTo(x,y);c.lineTo(x+len*.55,y-len*.3);c.lineTo(x+len,y-len*.13);c.stroke();
    c.strokeStyle='rgba(215,204,172,.20)';c.beginPath();
    c.moveTo(x,y-1);c.lineTo(x+len*.55,y-len*.3-1);c.stroke();
  }
  if(['beach','desert','farmland'].includes(kind)){
    const farm=kind==='farmland',spacing=farm?16:8;
    for(let y=-spacing;y<=512+spacing;y+=spacing){
      c.lineWidth=farm?5:.7;c.strokeStyle=farm?'rgba(38,56,18,.35)':'rgba(120,91,49,.14)';
      c.beginPath();
      for(let x=0;x<=512;x+=4){const py=y+Math.sin(x/512*Math.PI*8)*1.5;
        x?c.lineTo(x,py):c.moveTo(x,py);}
      c.stroke();
    }
  }
  if(['ocean','lake','foam'].includes(kind))for(let i=0;i<160;i++){
    const x=rand()*512,y=rand()*512,len=3+rand()*13;
    c.strokeStyle=kind==='foam'?'rgba(245,245,215,.32)':'rgba(186,216,207,.20)';
    c.lineWidth=.5+rand()*.6;c.beginPath();c.moveTo(x,y);
    c.quadraticCurveTo(x+len*.5,y-1.6,x+len,y);c.stroke();
  }
  tiles.set(kind,tile);return tile;
}
export function textureTerrain(ctx,kind){
  if(typeof document==='undefined'||typeof document.createElement!=='function'||typeof DOMMatrix==='undefined'||typeof ctx.createPattern!=='function')return false;
  kind=terrainFamily(kind);
  const transform=ctx.getTransform();
  if(Math.hypot(transform.a,transform.b)<.08){
    ctx.fillStyle=TERRAIN_COLORS[kind]||TERRAIN_COLORS.grass;
  }else{
    let cache=patterns.get(ctx);if(!cache){cache=new Map();patterns.set(ctx,cache);}
    if(!cache.has(kind)){
      const pattern=ctx.createPattern(makeTile(kind),'repeat');
      pattern.setTransform(new DOMMatrix().scale(64/512));cache.set(kind,pattern);
    }
    ctx.fillStyle=cache.get(kind);
  }
  ctx.fill();return true;
}
export function textureTerrainRect(ctx,kind,x,y,w,h){
  if(typeof document==='undefined'||typeof document.createElement!=='function'||typeof DOMMatrix==='undefined')return false;
  ctx.beginPath();ctx.rect(x,y,w,h);return textureTerrain(ctx,kind);
}
