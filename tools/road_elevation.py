"""Validation for optional World Forge road elevations (metres, 2.5D)."""

import math

LAYER_HEIGHT_M = 6.0
MAX_SLOPE = .12
MIN_CROSSING_CLEARANCE_M = 4.5
LAYERS = range(-2, 3)


def set_profile(road, source):
    """Apply an authored profile. Absence and explicit 0-to-0 mean ground."""
    road.pop("elevation", None)
    if "elevation" not in source:
        return
    profile = source["elevation"]
    if not isinstance(profile, dict) or set(profile) not in ({"start_layer","end_layer"},{"start_layer","end_layer","point_layers"}):
        raise ValueError("Road elevation needs start_layer and end_layer")
    layers = [profile[k] for k in ("start_layer", "end_layer")]
    # Godot emits integral JSON numbers as floats.
    if any(type(layer) not in (int, float) or layer not in LAYERS for layer in layers):
        raise ValueError("Road layers must be integers from -2 to 2")
    if "point_layers" in profile:
        values=profile["point_layers"]
        points=source.get("points",[])
        if not isinstance(values,list) or len(values)!=len(points) or len(values)<2 or any(type(v) not in (int,float) or v not in LAYERS for v in values):
            raise ValueError("One signed layer is required per road control point")
        if values[0]!=layers[0] or values[-1]!=layers[1]:
            raise ValueError("Point layers must match the road endpoints")
        for i,(a,b) in enumerate(zip(values,values[1:])):
            p,q=points[i:i+2]
            if abs(a-b)>1 or (a!=b and math.hypot(p["x"]-q["x"],p["y"]-q["y"])<50):
                raise ValueError("Adjacent point layers need at least 50 m per layer change")
        if any(values):
            road["elevation"]={"start_layer":int(values[0]),"end_layer":int(values[-1]),"point_layers":list(map(int,values))}
        return
    if abs(layers[0] - layers[1]) > 1:
        raise ValueError("A ramp can connect only adjacent road layers")
    if any(layers):
        road["elevation"] = dict(start_layer=int(layers[0]), end_layer=int(layers[1]))


def endpoint_layer(road, end):
    return road.get("elevation", {}).get(end + "_layer", 0)


def layer_at_join(road, station):
    """A sloping road meets other roads only at either authored endpoint."""
    profile = road.get("elevation")
    if not profile:
        return 0
    start, end = profile["start_layer"], profile["end_layer"]
    if start == end or station <= .12:
        return start
    if road["_stations"][-1] - station <= .12:
        return end
    return None


def height_at_station(road, station):
    first = endpoint_layer(road, "start")
    last = endpoint_layer(road, "end")
    fraction = station / max(road["_stations"][-1], .001)
    blend=road.get("grade_smooth",0.0)
    fraction=(1-blend)*fraction+blend*fraction*fraction*(3-2*fraction)
    return (first + (last - first) * fraction) * LAYER_HEIGHT_M


def validate_profile(road, length_m):
    profile = road.get("elevation")
    if not profile:
        return
    if math.dist(road["points"][0], road["points"][-1]) < .12:
        if profile["start_layer"] != profile["end_layer"]:
            raise ValueError("An elevation ramp must have distinct endpoints")
    rise = abs(profile["start_layer"] - profile["end_layer"]) * LAYER_HEIGHT_M
    if length_m < 4 or rise*(1+.5*road.get("grade_smooth",0.0)) > MAX_SLOPE * length_m+1e-6:
        raise ValueError(f"{road['name']}: ramp needs at least {rise / MAX_SLOPE:g} m for its rise")


def expand_point_profiles(roads,nodes):
    """Keep stable source IDs, append derived sections only in the runtime archive.
    Slice the already flattened full spline, preserving its horizontal tangents.
    Original source anchors/profile are retained for editor round trips.
    """
    from copy import deepcopy
    original_count=len(roads)
    for road in roads[:original_count]:
        profile=road.get("elevation",{})
        values=profile.get("point_layers")
        if values is None:
            continue
        original=deepcopy(road)
        anchors=original["anchors"]
        path=original["points"]
        indices=[0]
        for p in anchors[1:-1]:
            candidates=range(indices[-1]+1,len(path)-1)
            idx=min(candidates,key=lambda i:math.dist(path[i],p),default=-1)
            if idx<0 or math.dist(path[idx],p)>.05:
                raise ValueError(f"{road['name']}: control point missing from baked spline")
            indices.append(idx)
        indices.append(len(path)-1)
        runs=[]
        for i,(a,b) in enumerate(zip(values,values[1:])):
            if runs and runs[-1][2]==runs[-1][3]==a==b:
                runs[-1][1]=i+1
            else:
                runs.append([i,i+1,a,b])
        if len(runs)>1 and original.get("kind")=="onramp":
            raise ValueError("Multi-grade on-ramps require a regular road")
        if len(roads)+len(runs)-1>1800:
            raise ValueError("Runtime grade-section safety limit exceeded")
        for n,(first,last,a,b) in enumerate(runs):
            section=deepcopy(original)
            section["id"]=original["id"] if n==0 else len(roads)
            section["anchors"]=anchors[first:last+1]
            section["points"]=path[indices[first]:indices[last]+1]
            section["start"]=original["start"] if first==0 else f"grade-{original['id']}-{first}"
            section["end"]=original["end"] if last==len(anchors)-1 else f"grade-{original['id']}-{last}"
            nodes[section["start"]]=section["points"][0]
            nodes[section["end"]]=section["points"][-1]
            section.pop("elevation",None)
            if a or b:
                section["elevation"]={"start_layer":a,"end_layer":b}
            length=sum(math.dist(p,q) for p,q in zip(section["points"],section["points"][1:]))
            if a!=b:
                section["grade_smooth"]=max(0.0,min(1.0,2*(MAX_SLOPE*length/(abs(a-b)*LAYER_HEIGHT_M)-1)))
            if first!=0:section.pop("junctionStart",None)
            if last!=len(anchors)-1:section.pop("junctionEnd",None)
            section["editor_grade_source_id"]=original["id"]
            if n==0:
                section["editor_grade_source"]={"anchors":anchors,"elevation":profile}
                road.clear();road.update(section)
            else:
                roads.append(section)
