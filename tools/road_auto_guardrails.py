"""Compile road-linked guardrails into ordinary solid guardrail path props.

Percentages refer to baked centreline length, left/right to stored direction.
Use exact baked roads and junctions; never persist derived geometry in the source.
"""
from bisect import bisect_right
from collections import defaultdict
import math

WIDTH = .65
CELL = 64
CLEARANCE = 3.0


def ground(road):
    profile = road.get("elevation", {})
    return all(v == 0 for v in profile.get("point_layers",
        [profile.get("start_layer", 0), profile.get("end_layer", 0)]))


def set_auto_guardrails(road, source):
    if "autoGuardrails" not in source:
        return
    settings = source["autoGuardrails"]
    if not isinstance(settings, dict) or set(settings) - {"left", "right"} or not ground(source):
        raise ValueError("Invalid road-linked guardrail sides or elevation")
    for side, interval in settings.items():
        if (not isinstance(interval, list) or len(interval) != 2 or
                any(type(v) not in (int, float) or not math.isfinite(v) or not 0 <= v <= 100 for v in interval)
                or interval[0] >= interval[1]):
            raise ValueError("Invalid road-linked guardrail range")
    if settings:
        road["autoGuardrails"] = settings


def point_segment(p, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]
    t = max(0, min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/max(1e-12, dx*dx+dy*dy)))
    return math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)


def cells(a, b, pad):
    for x in range(math.floor((min(a[0],b[0])-pad)/CELL), math.floor((max(a[0],b[0])+pad)/CELL)+1):
        for y in range(math.floor((min(a[1],b[1])-pad)/CELL), math.floor((max(a[1],b[1])+pad)/CELL)+1):
            yield x,y


def props_for(roads, junctions, width, height, width_scale=1.1):
    if not any(r.get("autoGuardrails") for r in roads):
        return []
    grid = defaultdict(list)
    for road in roads:
        profile = road.get("elevation", {})
        layers = profile.get("point_layers",[profile.get("start_layer",0),profile.get("end_layer",0)])
        if all(v>0 for v in layers) or all(v<0 for v in layers):
            continue
        pad = float(road["width"])*width_scale/2 + CLEARANCE + WIDTH
        for a,b in zip(road["points"], road["points"][1:]):
            for cell in cells(a,b,pad+2):
                grid[cell].append((road["id"],a,b,pad))
    junction_grid=defaultdict(list)
    for j in junctions:
        if j.get("road_layer",0)!=0:
            continue
        pad=float(j["radius"])*width_scale+3
        for cell in cells(j["p"],j["p"],pad+2):
            junction_grid[cell].append((j["p"],pad))
    output=[]
    for road in roads:
        settings=road.get("autoGuardrails",{})
        if not settings:
            continue
        if not ground(road):
            raise ValueError("Road-linked guardrails require ground level")
        path=[road["points"][0]]
        for p in road["points"][1:]:
            if math.dist(p,path[-1])>.001:
                path.append(p)
        if len(path)<2:
            continue
        stations=[0.]
        for a,b in zip(path,path[1:]):
            stations.append(stations[-1]+math.dist(a,b))
        length=stations[-1]
        def at(s):
            i=max(0,min(len(path)-2,bisect_right(stations,s)-1))
            t=max(0,min(1,(s-stations[i])/(stations[i+1]-stations[i])))
            return tuple(a+(b-a)*t for a,b in zip(path[i],path[i+1]))
        for side,interval in settings.items():
            start,end=(length*v/100 for v in interval)
            count=max(1, math.ceil((end-start)/1.5))
            run=[]
            serial=0
            def flush():
                nonlocal run,serial
                if len(run)>1:
                    x0,y0=map(min,zip(*run))
                    x1,y1=map(max,zip(*run))
                    x,y=(x0+x1)/2,(y0+y1)/2
                    output.append(dict(id=f"prop-auto-rail-{road['id']}-{side}-{serial}",name="Road-linked guardrail",type="guardrail",
                        assetId="",x=x,y=y,rotation=0,scale=1,
                        assetSize=[x1-x0+WIDTH,y1-y0+WIDTH],guardrailWidth=WIDTH,
                        guardrailPoints=[[a-x,b-y] for a,b in run]))
                    serial+=1
                run=[]
            for i in range(count+1):
                s=start+(end-start)*i/count
                a,b=at(max(0,s-.5)),at(min(length,s+.5))
                dx,dy=b[0]-a[0],b[1]-a[1]
                magnitude=math.hypot(dx,dy)
                if magnitude<1e-6:
                    flush()
                    continue
                center=at(s)
                offset=(road["width"]*width_scale/2+1.5)*(1 if side=="left" else -1)
                p=(center[0]+dy/magnitude*offset,center[1]-dx/magnitude*offset)
                cell=(math.floor(p[0]/CELL),math.floor(p[1]/CELL))
                safe=3<=p[0]<=width-3 and 3<=p[1]<=height-3
                # A 1.5 m sampling step plus a 1 m margin keeps the continuous
                # segments outside all nearby road corridors, including T joins.
                if safe:
                    safe=not any(math.dist(p,c)<pad+1 for c,pad in junction_grid[cell])
                if safe:
                    safe=not any(point_segment(p,a,b)<pad+1 for rid,a,b,pad in grid[cell] if rid!=road["id"])
                # Avoid cutting across the selected pavement on tight inside bends.
                if safe:
                    safe=not any(point_segment(p,a,b)<road["width"]*width_scale/2+WIDTH/2 for rid,a,b,pad in grid[cell] if rid==road["id"])
                if not safe:
                    flush()
                elif not run or math.dist(p,run[-1])>=.5:
                    if run and math.dist(p,run[-1])>4:
                        flush()
                    run.append(p)
                    if len(run)==100:
                        last=run[-1]
                        flush()
                        run=[last]
            flush()
    return output


def with_auto_props(doc, roads, junctions, width, height, width_scale=1.1):
    generated=props_for(roads,junctions,width,height,width_scale)
    if not generated:
        return doc
    return {**doc,"props":[*doc.get("props",[]),*generated]}
