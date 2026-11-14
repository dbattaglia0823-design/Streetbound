/** Decorative, unlit fixtures. This module never changes traffic permissions. */
export function junctionFixtures(junctions,roads=[]){
  const result=[];
  for(const j of junctions)for(const arm of j.approaches||[]){
    if(arm.p&&arm.direction){result.push({p:{x:arm.p[0],y:arm.p[1]},d:{x:arm.direction[0],y:arm.direction[1]},width:arm.width});continue;}
    if(!arm.tangent)continue;
    const road=roads.find(r=>r.id===arm.id),ends=road?.points;
    const near=p=>Math.hypot(p.x-j.x,p.y-j.y)<(arm.width/2+(road?.shoulder||0)+8);
    const sides=ends&&near(ends[0])&&!near(ends.at(-1))?[1]:
      ends&&near(ends.at(-1))&&!near(ends[0])?[-1]:[-1,1];
    for(const side of sides){const d={x:arm.tangent.x*side,y:arm.tangent.y*side};
      result.push({p:{x:j.x+d.x*(j.radius+2),y:j.y+d.y*(j.radius+2)},d,width:arm.width});}
  }return result;
}
export function drawJunctionFixtures(ctx,junctions,roads=[]){
  for(const {p,d,width} of junctionFixtures(junctions,roads)){
    const n={x:-d.y,y:d.x},x=p.x+d.x*1.5-n.x*(width/2+2.1),y=p.y+d.y*1.5-n.y*(width/2+2.1);
    ctx.save();ctx.translate(x,y);ctx.rotate(Math.atan2(d.y,d.x));
    ctx.fillStyle='#586a69';ctx.fillRect(-.1,0,.2,1.4);
    ctx.fillStyle='#273435';ctx.fillRect(-.45,.25,.9,2.3);
    for(let i=0;i<3;i++){ctx.beginPath();ctx.arc(0,.75+i*.65,.25,0,Math.PI*2);ctx.fillStyle='#101a1c';ctx.fill();}
    ctx.restore();
  }
}
