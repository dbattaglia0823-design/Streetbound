export const JUMP_FIELDS=Object.freeze({
  at_m:[12,24000,80,'Takeoff (m from road start)'],
  length_m:[4,20,8,'Ramp length (m)'],
  width_m:[3,12,3.5,'Ramp width (m)'],
  height_m:[.25,1.5,.55,'Ramp height (m)'],
  angle_deg:[5,18,12,'Launch angle (degrees)'],
  min_mps:[8,24,15,'Minimum speed (m/s)'],
  max_mps:[10,26,20,'Maximum speed (m/s)'],
  landing_length_m:[6,42,16,'Landing length (m)'],
  landing_width_m:[4,16,4.5,'Landing width (m)']
});

function flight(height, tangent, speed){
  const g=9.81, upward=speed*tangent;
  const time=(upward+Math.sqrt(upward**2+2*g*height))/g;
  return {time, distance:speed*time, peak:height+upward**2/(2*g)};
}

export function roadJumpPreview(road){
  const jump=road.jump;
  if(road.points.length!==2||road.elevation||['gravel','dirt'].includes(road.surface))
    throw new RangeError('Use a straight, ground-level paved road for a jump');
  const [a,b]=road.points, span=Math.hypot(b.x-a.x,b.y-a.y);
  const heading={x:(b.x-a.x)/span,y:(b.y-a.y)/span};
  const lip={x:a.x+heading.x*jump.at_m,y:a.y+heading.y*jump.at_m};
  const sign=jump.reverse?-1:1, direction={x:heading.x*sign,y:heading.y*sign};
  const tangent=Math.tan(jump.angle_deg*Math.PI/180);
  const near=flight(jump.height_m,tangent,jump.min_mps);
  const far=flight(jump.height_m,tangent,jump.max_mps);
  const midpoint=(near.distance+far.distance)/2, half=jump.landing_length_m/2;
  const start=midpoint-half, end=midpoint+half;
  if(jump.min_mps>=jump.max_mps||far.time>2||far.peak>4||start<3||end>62||
      start>near.distance-.65||end<far.distance+.65||jump.landing_width_m<jump.width_m+.5)
    throw new RangeError('Landing zone must contain every permitted trajectory within jump limits');
  const before=jump.reverse?span-jump.at_m:jump.at_m;
  if(before<jump.length_m+2.6||span-before<end+2.6||jump.landing_width_m/2+2.6>road.width/2)
    throw new RangeError('Approach, landing, and vehicle clearance must fit on the road');
  return {lip,direction,start,end};
}

export function normalizeRoadJump(road,raw){
  if(raw===undefined)return undefined;
  if(!raw||typeof raw.reverse!=='boolean'||Object.keys(raw).length!==Object.keys(JUMP_FIELDS).length+1)
    throw new TypeError('Invalid jump settings');
  const jump={reverse:raw.reverse};
  for(const [key,[low,high,,label]] of Object.entries(JUMP_FIELDS)){
    const value=raw[key];
    if(!Number.isFinite(value)||value<low||value>high)
      throw new RangeError((label??key)+' must be between '+low+' and '+high);
    jump[key]=value;
  }
  roadJumpPreview({...road,jump});
  return jump;
}
