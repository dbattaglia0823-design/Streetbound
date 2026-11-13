const registry=new Map();
const types=new Set(['house','building','warehouse','garage','gas_station']);
const sizes={house:[12,17],building:[22,29],warehouse:[28,37],garage:[20,21],gas_station:[18,17]};
export const projectAssetId=id=>typeof id==='string'&&/^project-[a-f0-9]{24}$/.test(id);
export const projectAssetPath=path=>typeof path==='string'&&path.startsWith('Buildings/')&&
  !/[\\:\x00-\x1f]/.test(path)&&!path.split('/').some(p=>!p||p==='.'||p==='..')&&/\.(png|webp|svg)$/i.test(path);
export const projectAssetUrl=path=>'/game-assets/'+path.split('/').map(encodeURIComponent).join('/');
export function setProjectAssets(assets){
  registry.clear();
  for(const item of assets||[])if(projectAssetId(item.id)&&projectAssetPath(item.path)&&types.has(item.type)&&
    Number.isFinite(item.width)&&item.width>0&&Number.isFinite(item.height)&&item.height>0)
    registry.set(item.id,{...item,src:projectAssetUrl(item.path)+'?v='+encodeURIComponent(item.src?.split('?v=')[1]||'')});
}
export const projectAssets=()=>[...registry.values()];
export function projectArtwork(prop){
  if(!projectAssetId(prop.assetId)||!types.has(prop.type))return null;
  const known=registry.get(prop.assetId);
  const path=known?.path||prop.assetPath;
  if(!projectAssetPath(path))return null;
  let size=prop.assetSize;
  // Retain placed dimensions across catalog refreshes and file replacements.
  if(!Array.isArray(size)||size.length!==2||!size.every(v=>Number.isFinite(v)&&v>0&&v<=100)){
    if(!known)return null;
    const base=sizes[prop.type],ratio=Math.min(base[0]/known.width,base[1]/known.height);
    size=[known.width*ratio,known.height*ratio].map(v=>+v.toFixed(6));
  }
  return {id:prop.assetId,path,size,src:known?.src||projectAssetUrl(path)};
}
