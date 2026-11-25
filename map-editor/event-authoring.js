// Pure editor actions shared by the browser inspector and Node regression tests.
// Existing job IDs remain stable; copies receive fresh IDs, never shared progress.
export const CONTRACT_DEFAULTS = Object.freeze({
  courier:{cash:550,player_xp:180,car_xp:120,underground_rep:0,wanted_level:0,time_limit_seconds:270},
  smuggling:{cash:950,player_xp:230,car_xp:175,underground_rep:3,wanted_level:1,time_limit_seconds:240},
  getaway:{cash:1350,player_xp:290,car_xp:200,underground_rep:5,wanted_level:2,time_limit_seconds:210},
  robbery:{cash:2500,player_xp:450,car_xp:300,underground_rep:8,wanted_level:3,time_limit_seconds:360}
});
export const DIFFICULTY_PRESETS = Object.freeze({
  rookie:{multiplier:0.7,level:1,heatOffset:-1},
  amateur:{multiplier:1,level:8,heatOffset:0},
  pro:{multiplier:1.45,level:20,heatOffset:1},
  elite:{multiplier:1.85,level:40,heatOffset:2}
});
export const REWARD_CAPS = Object.freeze({
  cash:10000,player_xp:1500,car_xp:1200,underground_rep:30
});
const safeId=items=>{
  const used=new Set(items.map(x=>x.id));
  let n=1;while(used.has('job_'+n))n++;
  return 'job_'+n;
};
export function createOffer(existing=[],kind='courier',destinationId='',targetId=''){
  if(existing.length>=8)throw new RangeError('A contact can offer at most eight jobs.');
  if(!CONTRACT_DEFAULTS[kind])throw new TypeError('Unknown driving job type.');
  if(!destinationId)throw new Error('Place a contract drop-off before creating a job.');
  if(kind==='robbery'&&!targetId)throw new Error('Place a robbery target first.');
  return {
    id:safeId(existing),title:'New '+kind.charAt(0).toUpperCase()+kind.slice(1)+' Contract',
    kind,difficulty:'rookie',destination_marker_id:destinationId,
    ...(kind==='robbery'?{robbery_marker_id:targetId,robbery_hold_seconds:7}:{}),
    repeatable:true,required_player_level:1,required_underground_rep:0,
    arrival_radius_m:12,...CONTRACT_DEFAULTS[kind]
  };
}
export function duplicateOffer(existing,index){
  if(existing.length>=8)throw new RangeError('A contact can offer at most eight jobs.');
  const source=existing[index];
  if(!source)throw new RangeError('Select a contract before duplicating it.');
  const copy={...source,id:safeId(existing),title:(source.title||'Contract').slice(0,73)+' Copy'};
  return [...existing.slice(0,index+1),copy,...existing.slice(index+1)];
}
export function moveOffer(existing,index,direction){
  const target=index+direction;
  if(index<0||index>=existing.length||target<0||target>=existing.length)
    return {offers:existing,index};
  const offers=[...existing];
  [offers[index],offers[target]]=[offers[target],offers[index]];
  return {offers,index:target};
}
export function presetOffer(offer,difficulty){
  const preset=DIFFICULTY_PRESETS[difficulty],base=CONTRACT_DEFAULTS[offer.kind];
  if(!preset||!base)throw new TypeError('Unsupported contract preset.');
  const next={...offer,difficulty,
    required_player_level:preset.level,
    wanted_level:Math.max(0,Math.min(5,base.wanted_level+preset.heatOffset))};
  for(const [key,limit] of Object.entries(REWARD_CAPS))
    next[key]=Math.min(limit,Math.round(base[key]*preset.multiplier));
  return next;
}
export function offerWarnings(contact,offer,markers){
  const reasons=[];
  const location=(id,kind)=>markers.find(x=>x.id===id&&x.type===kind);
  const drop=location(offer.destination_marker_id,'contract_dropoff');
  if(!drop)reasons.push('Choose a valid drop-off marker.');
  if(drop){
    const trip=Math.hypot(drop.x-contact.x,drop.y-contact.y);
    if(trip<100)reasons.push('Drop-off must be at least 100 m from the contact.');
    if(trip>15000)reasons.push('Drop-off must be within 15 km of the contact.');
  }
  if(offer.kind==='robbery'){
    const target=location(offer.robbery_marker_id,'robbery_target');
    if(!target)reasons.push('Choose a robbery target marker.');
    if(target&&Math.hypot(target.x-contact.x,target.y-contact.y)<100)
      reasons.push('Robbery target must be 100 m from the contact.');
    if(target&&drop&&Math.hypot(target.x-drop.x,target.y-drop.y)<100)
      reasons.push('Robbery target and escape drop-off must be 100 m apart.');
  }
  if(!(offer.title||'').trim())reasons.push('Enter a job title.');
  if(offer.kind==='robbery'&&!offer.robbery_marker_id)
    reasons.push('Select a robbery target for the crew.');
  if(offer.arrival_radius_m!==undefined&&
     (!Number.isInteger(offer.arrival_radius_m)||offer.arrival_radius_m<6||
      offer.arrival_radius_m>30))reasons.push('Arrival radius must be 6–30 metres.');
  if(offer.robbery_hold_seconds!==undefined&&
     (!Number.isInteger(offer.robbery_hold_seconds)||offer.robbery_hold_seconds<3||
      offer.robbery_hold_seconds>30))reasons.push('Crew wait must be 3–30 seconds.');
  return reasons;
}
export function updateRaceSettings(world,id,patch){
  if(!world.races?.some(r=>r.id===id))throw new Error('Choose an existing authored race.');
  return {...world,races:world.races.map(r=>r.id===id?{...r,...patch}:r)};
}
