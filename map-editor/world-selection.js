/** Selection geometry for objects visible above roads and terrain.
 * Keep selection on the actual rotated footprint, not just a tiny dot
 * at the prop origin. This module has no DOM/canvas dependency.
 */
import {BASE_SIZE} from './morrow-runtime-preview.js';
import {projectArtwork} from './world-project-assets.js';

const EDITOR_SIZE={
  oak:[96,96],pine:[56,72],palm:[72,72],bush:[40,40],
  rock:[34,32],boulder:[58,58],house:[66,54],
  building:[92,104],warehouse:[139,86],garage:[100,80],
  gas_station:[95,70],parking:[139,106],streetlight:[16,16],
  sign:[40,27],barrier:[60,18],dock:[44,130],
  parked_car:[15,32],planter:[26,26],garden:[80,24],
  field:[90,70],island:[45,45],forecourt:[60,40]
};

/** True if a click lies inside a visible (possibly rotated) object footprint. */
export function pointInRotatedFootprint(point,center,size,angle=0,padding=0){
  if(!point||!center||!size||size[0]<=0||size[1]<=0)return false;
  const dx=point.x-center.x,dy=point.y-center.y;
  const c=Math.cos(angle),s=Math.sin(angle);
  const localX=dx*c+dy*s,localY=-dx*s+dy*c;
  return Math.abs(localX)<=size[0]/2+padding &&
    Math.abs(localY)<=size[1]/2+padding;
}

export function pickEditableScenery(props,point,{gameArt=false,tolerance=0}={}){
  for(let i=props.length-1;i>=0;i--){
    const prop=props[i];
    if(prop.hidden)continue;
    const project=projectArtwork(prop);
    const base=project?.size||prop.assetSize||(gameArt?BASE_SIZE:EDITOR_SIZE)[prop.type]||[12,12];
    const factor=(Number(prop.scale)||1)*
      (!project&&!gameArt&&['building','warehouse'].includes(prop.type)?1.2:1);
    if(pointInRotatedFootprint(point,prop,
      [base[0]*factor*(prop.scaleX??1),base[1]*factor*(prop.scaleY??1)],(Number(prop.rotation)||0)*Math.PI/180,
      tolerance))return prop;
  }
  return null;
}
