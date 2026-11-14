// Shared catalog contract for both legacy Buildings/ and the map art library.
const registry=new Map();
export const PROJECT_TYPES=new Set([
  'house','building','warehouse','garage','gas_station','prop','decal',
  'oak','pine','palm','bush','planter','barrier','rock','boulder',
  'streetlight','sign'
]);
const sizes={house:[12,17],building:[22,29],warehouse:[28,37],
  garage:[20,21],gas_station:[18,17],prop:[3,3],decal:[5,5],
  oak:[7,7],pine:[7,7],palm:[6.5,6.5],bush:[2.5,2.5],
  planter:[2.8,2.8],barrier:[3,1],rock:[3,2.5],boulder:[4.5,3.4],
  streetlight:[1.3,1.3],sign:[1.6,1.4]};
const validSize=size=>Array.isArray(size)&&size.length===2&&
  size.every(v=>Number.isFinite(v)&&v>0&&v<=100);
const validRegion=region=>Array.isArray(region)&&region.length===4&&
  region.every(Number.isInteger)&&region[0]>=0&&region[1]>=0&&
  region[2]>0&&region[3]>0;
export const projectAssetId=id=>typeof id==='string'&&/^project-[a-f0-9]{24}$/.test(id);
export const projectAssetPath=path=>typeof path==='string'&&
  (path.startsWith('Buildings/')||path.startsWith('Map Building Assets/'))&&
  !/[\\:\x00-\x1f]/.test(path)&&
  !path.split('/').some(p=>!p||p==='.'||p==='..')&&/\.(png|webp|svg)$/i.test(path);
export const projectAssetUrl=path=>'/game-assets/'+path.split('/').map(encodeURIComponent).join('/');
export function setProjectAssets(assets){
  registry.clear();
  for(const item of assets||[]){
    if(!projectAssetId(item.id)||!projectAssetPath(item.path)||!PROJECT_TYPES.has(item.type)||
       !Number.isFinite(item.width)||item.width<=0||
       !Number.isFinite(item.height)||item.height<=0||
       (item.region!==undefined&&!validRegion(item.region))||
       (item.size!==undefined&&!validSize(item.size)))continue;
    registry.set(item.id,{...item,src:projectAssetUrl(item.path)+
      '?v='+encodeURIComponent(item.src?.split('?v=')[1]||'')});
  }
}
export const projectAssets=()=>[...registry.values()];
export const projectAssetById=id=>registry.get(id)||null;
export function projectArtwork(prop){
  if(!projectAssetId(prop.assetId)||!PROJECT_TYPES.has(prop.type))return null;
  const known=registry.get(prop.assetId);
  if(known&&known.type!==prop.type)return null;
  const path=known?.path||prop.assetPath;
  if(!projectAssetPath(path))return null;
  const region=known?.region||prop.assetRegion||null;
  if(region&&!validRegion(region))return null;
  // Saved map dimensions are authoritative so replacing an image does not
  // silently stretch hundreds of already-placed scenery objects.
  let size=prop.assetSize;
  if(!validSize(size)){
    if(known?.size)size=known.size;
    else if(known){
      const base=sizes[prop.type];
      const ratio=Math.min(base[0]/known.width,base[1]/known.height);
      size=[known.width*ratio,known.height*ratio].map(v=>+v.toFixed(6));
    }else return null;
  }
  return {id:prop.assetId,path,size,region,sprite:known?.sprite||prop.assetSprite||null,
    collision:known?.collision||prop.assetCollision||
      (['decal','bush','planter','oak','pine','palm','streetlight','sign'].includes(prop.type)?'none':'solid'),
    src:known?.src||projectAssetUrl(path)};
}
