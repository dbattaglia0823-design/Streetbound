"""Bake at-grade junction mouths, rounded corners, priority and paint exclusions.

Endpoint T joins and centerline crossings use the same geometry when their
road layers agree. Legacy water bridge grades do not affect connectivity.
"""
import bisect
import math

from road_elevation import (
    MIN_CROSSING_CLEARANCE_M, height_at_station, layer_at_join, validate_profile,
)

PRIORITY = {'highway':5,'track':5,'arterial':4,'rural':3,'mountain':3,
            'local':2,'gravel':1,'driveway':0,'alley':0,'onramp':3}


def distance(a,b):
    return math.hypot(a[0]-b[0],a[1]-b[1])


def near(p,a,b):
    d=[b[k]-a[k] for k in (0,1)]
    t=max(0,min(1,sum((p[k]-a[k])*d[k] for k in (0,1))/max(sum(v*v for v in d),1e-12)))
    q=[a[k]+t*d[k] for k in (0,1)]
    return distance(p,q),t


def crossing(a,b,c,d):
    v=[b[k]-a[k] for k in (0,1)]; w=[d[k]-c[k] for k in (0,1)]
    det=v[0]*w[1]-v[1]*w[0]
    if abs(det)<1e-8:return None
    delta=[c[k]-a[k] for k in (0,1)]
    t=(delta[0]*w[1]-delta[1]*w[0])/det
    u=(delta[0]*v[1]-delta[1]*v[0])/det
    if -1e-6<=t<=1.000001 and -1e-6<=u<=1.000001:
        return [a[k]+t*v[k] for k in (0,1)]


def unit(a,b):
    length=max(distance(a,b),1e-9)
    return [(b[k]-a[k])/length for k in (0,1)]


def sample(road,station):
    s=max(0,min(road['_stations'][-1],station))
    i=min(len(road['points'])-2,max(0,bisect.bisect_right(road['_stations'],s)-1))
    a,b=road['points'][i:i+2]
    t=(s-road['_stations'][i])/max(distance(a,b),1e-9)
    return [a[k]+t*(b[k]-a[k]) for k in (0,1)]


def project(road,p):
    best=(float('inf'),0)
    for i,(a,b) in enumerate(zip(road['points'],road['points'][1:])):
        d,t=near(p,a,b)
        if d<best[0]:best=d,road['_stations'][i]+t*distance(a,b)
    return best


def clean_polygon(points):
    result=[]
    for p in points:
        if not result or distance(result[-1],p)>.001:result.append(p)
    if len(result)>1 and distance(result[0],result[-1])<.001:result.pop()
    return result


def simple_polygon(points):
    for i,a in enumerate(points):
        b=points[(i+1)%len(points)]
        for k in range(i+2,len(points)):
            if i==0 and k==len(points)-1:continue
            c,d=points[k],points[(k+1)%len(points)]
            p=crossing(a,b,c,d)
            if p is not None and min(distance(p,q) for q in [a,b,c,d])>.001:return False
    return True


def rounded_hull(points):
    points=sorted(set(tuple(p) for p in points))
    def cross(a,b,c):return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    lower=[]; upper=[]
    for p in points:
        while len(lower)>1 and cross(lower[-2],lower[-1],p)<=0:lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper)>1 and cross(upper[-2],upper[-1],p)<=0:upper.pop()
        upper.append(p)
    hull=lower[:-1]+upper[:-1]
    rounded=[]
    for i,p in enumerate(hull):
        before,after=hull[i-1],hull[(i+1)%len(hull)]
        cut=min(2,distance(before,p)*.15,distance(p,after)*.15)
        a=[p[k]+(before[k]-p[k])*cut/max(distance(before,p),.001) for k in (0,1)]
        b=[p[k]+(after[k]-p[k])*cut/max(distance(after,p),.001) for k in (0,1)]
        for step in range(6):
            t=step/5
            rounded.append([(1-t)**2*a[k]+2*t*(1-t)*p[k]+t*t*b[k] for k in (0,1)])
    return rounded


def endpoint_mode(road, end):
    mode=road.get('junctionEnd' if end else 'junctionStart','auto')
    return ('merge' if end and road['kind']=='onramp' else 'auto') if mode=='auto' else mode


def ramp_merge(roads, arms):
    """A single forward ramp end merging into an uninterrupted through road.
    Reject wrong-side, perpendicular and ambiguous joins at bake time."""
    ramps=[]
    for a in arms:
        road=roads[a['road']]
        end=a['side']==-1
        if endpoint_mode(road,end)=='merge' and abs(a['origin_station']-(road['_stations'][-1] if end else 0))<.15:
            ramps.append(a)
    if not ramps:
        return None
    if len(ramps)!=1 or len(arms)!=3:
        raise ValueError('On-ramp end must join the interior of one through road')
    ramp=ramps[0]
    main=[a for a in arms if a is not ramp]
    if any(roads[a['road']]['kind'] not in ('highway','arterial','rural','local') or roads[a['road']]['surface'] in ('GRAVEL','DIRT') for a in main):
        raise ValueError('On-ramp needs a paved through road')
    if sum(main[0]['direction'][k]*main[1]['direction'][k] for k in (0,1))>-.85:
        raise ValueError('On-ramp needs two opposing through-road approaches')
    incoming=[-v for v in ramp['direction']]
    # In screen coordinates positive cross means the branch is on the right.
    candidates=[a for a in main if a['direction'][0]*ramp['direction'][1]-a['direction'][1]*ramp['direction'][0]>.087]
    if not candidates:
        raise ValueError('On-ramp must approach from the right')
    target=max(candidates,key=lambda a:sum(incoming[k]*a['direction'][k] for k in (0,1)))
    direction=target['direction']
    dot=sum(incoming[k]*direction[k] for k in (0,1))
    side=direction[0]*ramp['direction'][1]-direction[1]*ramp['direction'][0]
    explicit=roads[ramp['road']].get('junctionEnd' if ramp['side']==-1 else 'junctionStart')=='merge'
    if dot<(-.001 if explicit else .7071) or side<.087:
        raise ValueError('On-ramp must approach from the right without doubling back')
    opposite=next(a for a in main if a is not target)
    return dict(ramp_road=ramp['road'],ramp_side=ramp['side'],main_road=target['road'],merge_side=target['side'],
                through_road=opposite['road'],through_side=opposite['side'])


def build_junctions(roads,nodes,segments,grid):
    for road in roads:
        stations=[0.0]
        for a,b in zip(road['points'],road['points'][1:]):stations.append(stations[-1]+distance(a,b))
        road['_stations']=stations
        validate_profile(road, stations[-1])
        road['marking_gaps']=[]
    events=[]; cells={}; connections=set(); crossings=[]
    def event(p,ids,layer):
        cell=(int(p[0]//8),int(p[1]//8))
        for x in range(cell[0]-1,cell[0]+2):
            for y in range(cell[1]-1,cell[1]+2):
                for index in cells.get((x,y),[]):
                    if events[index]['layer']==layer and distance(events[index]['p'],p)<3:
                        events[index]['roads'].update(ids)
                        return
        cells.setdefault(cell,[]).append(len(events))
        events.append(dict(p=list(p),roads=set(ids),layer=layer))

    def join_layer(road_id,p):
        road=roads[road_id]
        return layer_at_join(road,project(road,p)[1]) if 'elevation' in road else 0

    for name,p in nodes.items():
        by_layer={}
        for road in roads:
            for end,station in [('start',0),('end',road['_stations'][-1])]:
                if road[end]==name:
                    by_layer.setdefault(layer_at_join(road,station),set()).add(road['id'])
        for layer,ids in by_layer.items():
            if len(ids)>=2:event(p,ids,layer)
    def check_clearance(ids,p):
        heights = [height_at_station(roads[road_id],project(roads[road_id],p)[1])
                   for road_id in ids]
        if abs(heights[0]-heights[1]) < MIN_CROSSING_CLEARANCE_M:
            names = " / ".join(roads[road_id]["name"] for road_id in ids)
            raise ValueError(f"{names}: grade-separated crossing at "
                             f"{p[0]:.1f}, {p[1]:.1f} needs at least "
                             f"{MIN_CROSSING_CLEARANCE_M:g} m vertical clearance")

    tested=set()
    for indices in grid.values():
        for i in indices:
            for j in indices:
                if j<=i or (i,j) in tested:continue
                tested.add((i,j))
                a,b=segments[i],segments[j]
                if a['road']==b['road']:continue
                p=crossing(a['a'],a['b'],b['a'],b['b'])
                if p is not None:
                    ids=[a['road'],b['road']]
                    layer=join_layer(ids[0],p)
                    other=join_layer(ids[1],p)
                    if layer is None or layer!=other:
                        check_clearance(ids,p)
                        continue
                    crossings.append(dict(p=p,roads=ids))
                    event(p,ids,layer)
    # Catch endpoints touching the interior of a road within authored precision.
    for road in roads:
        for p,station in [(road['points'][0],0),(road['points'][-1],road['_stations'][-1])]:
            layer=layer_at_join(road,station)
            key=f'{int(p[0]//64)},{int(p[1]//64)}'
            ids={road['id']}
            for index in grid.get(key,[]):
                seg=segments[index]
                if (seg['road']!=road['id'] and near(p,seg['a'],seg['b'])[0]<.12
                        and join_layer(seg['road'],p)==layer):
                    ids.add(seg['road'])
            if len(ids)>1:event(p,ids,layer)
    result=[]; merged_ramps=set()
    for e in events:
        ids=sorted(e['roads']); center=e['p']
        for a in ids:
            for b in ids:
                if a<b:connections.add((a,b))
        base=max(roads[i]['width'] for i in ids)*.5+6
        arms=[]
        for road_id in ids:
            road=roads[road_id]; _,station=project(road,center)
            for side in [-1,1]:
                available=station if side<0 else road['_stations'][-1]-station
                if available<.5:continue
                out=unit(center,sample(road,station+side*min(5,available)))
                arms.append(dict(road=road_id,side=side,origin_station=station,
                                 direction=out,available=available,width=road['width']))
        merge=ramp_merge(roads,arms)
        if merge:merged_ramps.add((merge['ramp_road'],merge['ramp_side']==-1))
        # Coincident route pieces describe one physical approach.
        unique=[]
        for arm in sorted(arms,key=lambda a:-a['width']):
            if not any(sum(arm['direction'][k]*b['direction'][k] for k in (0,1))>.998 for b in unique):unique.append(arm)
        arms=unique
        if len(arms)<2:continue
        dot=sum(arms[0]['direction'][k]*arms[1]['direction'][k] for k in (0,1))
        if len(arms)==2 and dot<-.94 and abs(arms[0]['width']-arms[1]['width'])<.1:
            continue  # smooth continuation, not a traffic junction
        for arm in arms:
            clearance=base
            for other in arms:
                if other is arm:continue
                cosine=sum(arm['direction'][k]*other['direction'][k] for k in (0,1))
                sine=abs(arm['direction'][0]*other['direction'][1]-arm['direction'][1]*other['direction'][0])
                if cosine>0 and sine>.025:
                    clearance=max(clearance,(other['width']*.5+arm['width']*.5*cosine)/sine+3)
            arm['setback']=min(40,clearance,arm['available']*.70)
            road=roads[arm['road']]
            arm['station']=max(0,min(road['_stations'][-1],arm['origin_station']+arm['side']*arm['setback']))
            arm['p']=sample(road,arm['station'])
            arm['direction']=unit(sample(road,arm['station']-arm['side']*.4),sample(road,arm['station']+arm['side']*.4))
            arm['angle']=math.atan2(arm['p'][1]-center[1],arm['p'][0]-center[0])
            arm['control']='none'
        arms.sort(key=lambda a:a['angle'])
        ranks=[PRIORITY[roads[a['road']]['kind']] for a in arms]
        roundabout=any(roads[a['road']]['name']=='Civic Roundabout' for a in arms)
        control='none'
        if merge:
            control='merge'
            for arm in arms:arm['control']='yield' if arm['road']==merge['ramp_road'] else 'none'
        elif len(arms)>=3:
            if roundabout:
                control='roundabout'
                for arm in arms:
                    if roads[arm['road']]['name']!='Civic Roundabout':arm['control']='yield'
            else:
                pairs=[]
                for i,a in enumerate(arms):
                    for j,b in enumerate(arms[i+1:],i+1):
                        dot=sum(a['direction'][k]*b['direction'][k] for k in (0,1))
                        same=roads[a['road']]['name']==roads[b['road']]['name']
                        if dot<-.45 or (same and dot<.3):
                            score=min(ranks[i],ranks[j])*100+(25 if same else 0)-dot*10
                            pairs.append((score,i,j))
                # Equal-rank urban crossroads get an explicit all-way stop.
                all_way=len(arms)>=4 and len(set(ranks))==1 and max(ranks)<=4
                if pairs and not all_way:
                    _,i,j=max(pairs)
                    for k,arm in enumerate(arms):
                        if k not in [i,j]:arm['control']='stop'
                    control='priority'
                else:
                    for arm in arms:arm['control']='stop'
                    control='all_way_stop'
        polygon=[]; curbs=[]
        for i,a in enumerate(arms):
            b=arms[(i+1)%len(arms)]
            da,db=a['direction'],b['direction']
            na,nb=[-da[1],da[0]],[-db[1],db[0]]
            right=[a['p'][k]-na[k]*a['width']*.5 for k in (0,1)]
            start=[a['p'][k]+na[k]*a['width']*.5 for k in (0,1)]
            end=[b['p'][k]-nb[k]*b['width']*.5 for k in (0,1)]
            polygon.append(right)
            det=da[0]*db[1]-da[1]*db[0]
            corner=[]
            if abs(det)>.08:
                delta=[end[k]-start[k] for k in (0,1)]
                t=(delta[0]*db[1]-delta[1]*db[0])/det
                handle=[start[k]+da[k]*t for k in (0,1)]
                if distance(handle,center)>max(55,base*3):handle=[(start[k]+end[k])*.5 for k in (0,1)]
                for step in range(9):
                    t=step/8
                    corner.append([(1-t)**2*start[k]+2*t*(1-t)*handle[k]+t*t*end[k] for k in (0,1)])
            else:corner=[start,end]
            polygon.extend(corner)
            curbs.append(corner)
        polygon=clean_polygon(polygon)
        if not simple_polygon(polygon):
            # Curved acute approaches can overlap their own tangent mouths.
            # Use a rounded compound apron, with kerbs only outside road lanes.
            polygon=rounded_hull(polygon)
            curbs=[]; run=[]
            for a,b in zip(polygon,polygon[1:]+polygon[:1]):
                count=max(1,math.ceil(distance(a,b)))
                for step in range(count):
                    p=[a[k]+(b[k]-a[k])*step/count for k in (0,1)]
                    clear=all(project(roads[road_id],p)[0]>roads[road_id]['width']*.5+.15 for road_id in ids)
                    if clear:run.append(p)
                    else:
                        if len(run)>1:curbs.append(run)
                        run=[]
            if len(run)>1:curbs.append(run)
        for arm in arms:
            road=roads[arm['road']]
            s=arm['origin_station']; end=arm['station']
            road['marking_gaps'].append([max(0,min(s,end)-.5),min(road['_stations'][-1],max(s,end)+.5)])
            for key in ['available','origin_station','angle']:arm.pop(key,None)
        radius=max(distance(center,p) for p in polygon)+2
        junction=dict(p=center,roads=ids,approaches=arms,polygon=polygon,curbs=curbs,
                      radius=radius,control=control,kind='merge' if merge else ('crossroads' if len(arms)>=4 else ('t_junction' if len(arms)==3 else 'bend')),**(merge or {}))
        if e['layer']:
            junction['road_layer']=e['layer']
        result.append(junction)
    for road in roads:
        for end in (False,True):
            if endpoint_mode(road,end)=='merge' and (road['id'],end) not in merged_ramps:
                raise ValueError('On-ramp endpoint needs a valid three-arm merge: '+road['name'])
    for road in roads:
        merged=[]
        for a,b in sorted(road['marking_gaps']):
            if merged and a<=merged[-1][1]:merged[-1][1]=max(b,merged[-1][1])
            else:merged.append([a,b])
        road['marking_gaps']=merged
        road.pop('_stations')
    return result,connections,crossings
