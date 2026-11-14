"""Validate explicit solid mountain regions without changing decorative biomes."""
import math
from road_bridges import bounds, overlaps, inside, cut_parameters, distance, lerp


def validate_polygon(points):
    if len(points)<3 or len(points)>180:
        raise ValueError('Mountain barrier needs 3–180 outline points')
    for i,(a,b) in enumerate(zip(points,points[1:]+points[:1])):
        if distance(a,b)<.01:raise ValueError('Mountain barrier has duplicate outline points')
        for j in range(i+2,len(points)):
            if i==0 and j==len(points)-1:continue
            c,d=points[j],points[(j+1)%len(points)]
            dx,dy=b[0]-a[0],b[1]-a[1];wx,wy=d[0]-c[0],d[1]-c[1]
            den=dx*wy-dy*wx
            if abs(den)<1e-9:continue
            rx,ry=c[0]-a[0],c[1]-a[1]
            t,u=(rx*wy-ry*wx)/den,(rx*dy-ry*dx)/den
            if 0<=t<=1 and 0<=u<=1:raise ValueError('Mountain barrier outline crosses itself')
    area=abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(points,points[1:]+points[:1])))*.5
    if area<25:raise ValueError('Mountain barrier must cover at least 25 square metres')


def nearest(p,a,b):
    delta=[b[k]-a[k] for k in (0,1)]
    t=max(0,min(1,sum((p[k]-a[k])*delta[k] for k in (0,1))/max(1e-9,distance(a,b)**2)))
    return distance(p,lerp(a,b,t))


def validate_barriers(roads,terrain,pois,spawn,width_scale=1.0):
    for region in terrain:
        if not region.get('barrier'):continue
        points=region['points'];validate_polygon(points)
        box=bounds(points);edges=list(zip(points,points[1:]+points[:1]))
        title=region.get('authoring_id','Mountain barrier')
        if inside(spawn['position'],points):raise ValueError(f'{title} covers the player start')
        for poi in pois:
            if inside(poi['position'],points):raise ValueError(f"{title} covers {poi['name']}")
        for road in roads:
            radius=road['width']*width_scale*.5+2
            padded=(box[0]-radius,box[1]-radius,box[2]+radius,box[3]+radius)
            for a,b in zip(road['points'],road['points'][1:]):
                if not overlaps(bounds([a,b]),padded):continue
                blocked=inside(a,points) or inside(b,points)
                if not blocked:
                    for c,d in edges:
                        cuts=cut_parameters(a,b,[(c,d)])
                        if len(cuts)>2 or min(nearest(a,c,d),nearest(b,c,d),nearest(c,a,b),nearest(d,a,b))<radius:
                            blocked=True;break
                if blocked:raise ValueError(f"{title} blocks {road['name']}. Leave room for the road or move the mountain outline.")
