"""Bake a saved custom World Builder map into the production streamed-world format.

This never touches the shipped Morrow Coast files. The temporary archive is
written only under the caller-supplied user-data directory. Junction geometry,
turn restrictions, road marks and lane routing use the SAME junction baker as
the normal game. No in-game approximation of intersections.
"""
import argparse
import hashlib
from collections import defaultdict
import json
import math
from pathlib import Path
import sys

from junction_bake import build_junctions
from road_auto_guardrails import set_auto_guardrails, with_auto_props
from gameplay_authoring import validate as validate_gameplay, apply as apply_gameplay
from road_jumps import set_jump, bake_into as bake_jumps
from road_elevation import set_profile, expand_point_profiles
from elevation_map_audit import audit_elevated_objectives
from mountain_barriers import validate_open_cuts
from authored_races import authored_races
from authored_markers import validate_markers
from morrow_editor_import import _authoring_props, _polygon_points, CLASS_TO_KIND, PALETTES, set_road_draw_order
from road_shape_geometry import circle_path

CHUNK = 192
CELL = 64
MAX_SOURCE_BYTES = 8_000_000


def distance(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def path_of(anchors):
    """Adaptive Hermite interpolation from the production road-spline builder."""
    circular = circle_path(anchors)
    if circular is not None:
        return circular
    output = []
    for i in range(len(anchors) - 1):
        a, b = anchors[i], anchors[i + 1]
        before = anchors[i - 1] if i else a
        after = anchors[i + 2] if i + 2 < len(anchors) else b
        chord = distance(a, b)
        ta = [(b[k] - before[k]) * .4 for k in range(2)]
        tb = [(after[k] - a[k]) * .4 for k in range(2)]
        for tangent in (ta, tb):
            length = math.hypot(*tangent)
            if length > chord * .85:
                tangent[:] = [v * chord * .85 / length for v in tangent]
        def evaluate(t):
            h0, h1 = 2 * t**3 - 3 * t**2 + 1, -2 * t**3 + 3 * t**2
            h2, h3 = t**3 - 2 * t**2 + t, t**3 - t**2
            return [h0*a[k] + h1*b[k] + h2*ta[k] + h3*tb[k] for k in range(2)]
        def flatten(t0, t1, p0, p1, depth=0):
            third = (t1 - t0) / 3
            def deviation(at):
                q = evaluate(at)
                direction = [p1[k] - p0[k] for k in range(2)]
                dot = sum((q[k] - p0[k])*direction[k] for k in range(2))
                t = max(0, min(1, dot / max(1e-9, sum(v*v for v in direction))))
                return distance(q, [p0[k] + t*direction[k] for k in range(2)])
            error = max(deviation(t0+third), deviation(t1-third))
            if depth < 16 and (distance(p0, p1) > 6 or error > .035):
                mid = (t0+t1)/2
                midpoint = evaluate(mid)
                flatten(t0, mid, p0, midpoint, depth+1)
                flatten(mid, t1, midpoint, p1, depth+1)
            else:
                output.append([round(float(v), 3) for v in p0])
        flatten(0, 1, a, b)
    output.append(list(anchors[-1]))
    return output


def cells(rect, step):
    x0, y0, x1, y1 = rect
    for x in range(math.floor(x0 / step), math.floor(x1 / step)+1):
        for y in range(math.floor(y0 / step), math.floor(y1 / step)+1):
            yield f"{x},{y}"


def clip_rect(polygon, x0, y0, x1, y1):
    poly = [list(p) for p in polygon]
    for axis, bound, greater in ((0, x0, True), (0, x1, False), (1, y0, True), (1, y1, False)):
        if not poly:
            break
        out = []
        for a, b in zip(poly, poly[1:]+poly[:1]):
            inside_a = a[axis] >= bound if greater else a[axis] <= bound
            inside_b = b[axis] >= bound if greater else b[axis] <= bound
            if inside_a:
                out.append(a)
            if inside_a != inside_b:
                t = (bound-a[axis])/(b[axis]-a[axis])
                out.append([a[k]+t*(b[k]-a[k]) for k in range(2)])
        poly = out
    return poly


def _gameplay_payload(doc,roads,width,height):
    baked_races=authored_races(doc,width,height)
    dealers=doc.get("dealerships",[])
    markers=validate_markers(doc.get("markers",[]),baked_races,dealers,width,height)
    marker_spawn=next((m for m in markers if m.get("type")=="player_spawn"),None)
    if marker_spawn:
        spawn=dict(position=[float(marker_spawn["x"]),float(marker_spawn["y"])],
                   rotation=math.radians(float(marker_spawn.get("rotation",0))))
    elif (ground_road := next((road for road in roads if "elevation" not in road), None)) is not None:
        path=ground_road["points"]
        mid=max(0,(len(path)-2)//2)
        a,b=path[mid:mid+2]
        spawn=dict(position=[(a[0]+b[0])*.5,(a[1]+b[1])*.5],
                   rotation=math.atan2(b[0]-a[0],a[1]-b[1]))
    else:
        spawn=dict(position=[width*.5,height*.5],rotation=0.0)
    # Preserve all original source marker payloads; translate only the common
    # POI fields used by the normal atlas.
    pois=[]
    for marker in markers:
        if str(marker.get("type",""))=="player_spawn":
            continue
        pois.append(dict(name=str(marker.get("name",marker.get("type","Marker"))),
                         category=str(marker.get("type","MARKER")).upper(),
                         position=[float(marker["x"]),float(marker["y"])],road=-1))
    for race in doc.get("races",[]):
        if not race.get("points"):
            continue
        at=race["points"][0]
        pois.append(dict(name=str(race.get("name","Street Race")),
                         category="RACE",position=[float(at["x"]),float(at["y"])],
                         road=-1))
    return dict(spawn=spawn,pois=pois,editor_markers=markers,editor_races=baked_races,editor_dealerships=dealers,editor_game_markers=markers)


def make_archive(doc):
    if doc.get("format") != "gdt.racing-world" or doc.get("version") != 2 or doc.get("customMap") is not True:
        raise ValueError("Not a saved custom World Builder map")
    world = doc.get("world", {})
    width, height = world.get("width"), world.get("height")
    # Godot JSON.parse_string can serialize original integer dimensions as
    # floating-point values. Accept only finite integral quantities.
    if any(type(v) not in (int,float) or not math.isfinite(v) or
           v!=int(v) or not 600<=v<=24000 for v in (width,height)):
        raise ValueError("Invalid custom world dimensions")
    width,height=int(width),int(height)
    gameplay_zones,junction_controls=validate_gameplay(doc,width,height)
    rain = doc.get("rain_intensity", 0.0)
    if type(rain) not in (int,float) or not math.isfinite(rain) or not 0.0 <= rain <= 1.0:
        raise ValueError("Rain intensity must be between 0 and 1")
    source_roads = doc.get("roads", [])
    if not isinstance(source_roads, list) or len(source_roads) > 360:
        raise ValueError("Invalid custom road list")
    nodes, roads, segments = {}, [], []
    grid = defaultdict(list)
    endpoint_index = defaultdict(list)
    for index, item in enumerate(source_roads):
        anchors = [[float(p["x"]),float(p["y"])] for p in item["points"]]
        if len(anchors) < 2 or len(anchors) > 100 or any(
            not all(math.isfinite(v) and 0 <= v <= (width if k == 0 else height)
                    for k, v in enumerate(p)) for p in anchors
        ):
            raise ValueError("Invalid custom road control points")
        names = []
        for end, p in enumerate((anchors[0], anchors[-1])):
            cell = (math.floor(p[0]),math.floor(p[1]))
            candidates = [entry for dx in (-1,0,1) for dy in (-1,0,1)
                          for entry in endpoint_index.get((cell[0]+dx,cell[1]+dy),())]
            # Earliest matching authored endpoint wins, exactly as before.
            key = next((name for _,coord,name in sorted(candidates) if distance(coord,p)<.12), None)
            if key is None:
                key = f"custom-node-{index}-{end}"
                nodes[key] = p
                endpoint_index[cell].append((index*2+end,p,key))
            names.append(key)
        road_points = path_of(anchors)
        kind = CLASS_TO_KIND.get(item.get("roadClass","city"),"local")
        surface = str(item.get("surface","asphalt")).upper()
        if surface not in ("ASPHALT","CONCRETE","TRACK","GRAVEL","DIRT"):
            raise ValueError("Unknown road surface")
        if kind == "onramp" and (surface not in ("ASPHALT","CONCRETE") or item.get("lanes",2) not in (1,2)):
            raise ValueError("Ramp must be paved and have one or two lanes")
        if surface == "TRACK":
            kind = "track"
        elif surface == "GRAVEL" and kind != "alley":
            kind = "gravel"
        road_width = float(item.get("width",10))
        lanes = int(item.get("lanes",2))
        if not 6 <= road_width <= 160 or not 1 <= lanes <= 6 or len(road_points)<2:
            raise ValueError("Invalid road dimensions")
        roads.append(dict(id=index,name=str(item.get("name","Editor Road"))[:80],
            start=names[0],end=names[1],kind=kind,grade=0,
            lanes=lanes,width=road_width,surface=surface if surface in ("GRAVEL","DIRT") else "ASPHALT",
            anchors=anchors,points=road_points))
        for key in ("junctionStart","junctionEnd"):
            if item.get(key,"auto") not in ("auto","intersection","merge"):
                raise ValueError("Invalid road junction mode")
            if key in item: roads[-1][key]=item[key]
        set_road_draw_order(roads[-1], item)
        set_profile(roads[-1], item)
        set_auto_guardrails(roads[-1], item)
        set_jump(roads[-1], item)
    expand_point_profiles(roads,nodes)
    for road in roads:
        index=road["id"];road_width=road["width"];road_points=road["points"]
        for a,b in zip(road_points,road_points[1:]):
            if distance(a,b)<.001:
                continue
            sid=len(segments)
            segments.append(dict(a=a,b=b,road=index))
            padding=road_width/2+5
            bounds=(min(a[0],b[0])-padding,min(a[1],b[1])-padding,
                    max(a[0],b[0])+padding,max(a[1],b[1])+padding)
            for key in cells(bounds,CELL):
                grid[key].append(sid)

    junctions,connections,crossings=build_junctions(roads,nodes,segments,grid)
    apply_gameplay(junctions,junction_controls,roads)
    terrain=[]
    base=str(world.get("base","grass"))
    terrain.append(dict(kind=base,color=PALETTES.get(base,"a3b789"),
                        points=[[0,0],[width,0],[width,height],[0,height]]))
    for raw in doc.get("regions",[]):
        kind=str(raw.get("biome","grass"))
        source_points=raw.get("points",[])
        if not isinstance(source_points,list) or len(source_points)<3:
            raise ValueError("Invalid terrain region")
        region=dict(kind=kind,color=PALETTES.get(kind,"a3b789"),editor_name=str(raw.get("name",""))[:120],
                    points=_polygon_points(source_points,width,height,rounded=False))
        for key in ("barrier","elevation"):
            if key in raw:region[key]=raw[key]
        order=raw.get("drawOrder",0)
        if type(order) not in (int,float) or not math.isfinite(order) or int(order)!=order or not -5<=order<=10:
            raise ValueError("Invalid terrain draw order")
        if order:region["editor_draw_order"]=int(order)
        terrain.append(region)
    props=[p for p in _authoring_props(with_auto_props(doc,roads,junctions,width,height),width,height) if not p.get("hidden")]
    gameplay=_gameplay_payload(doc,roads,width,height)
    chunks=defaultdict(lambda:dict(segments=[],props=[],walls=[],junctions=[],terrain=[],
                                  relief=[],rails=[],mountains=[],bridges=[]))
    for index,segment in enumerate(segments):
        road=roads[segment["road"]]
        a,b=segment["a"],segment["b"]
        pad=road["width"]*.5+5
        for key in cells((min(a[0],b[0])-pad,min(a[1],b[1])-pad,
                          max(a[0],b[0])+pad,max(a[1],b[1])+pad),CHUNK):
            chunks[key]["segments"].append(index)
    for index,prop in enumerate(props):
        p=prop["p"]
        radius=math.hypot(*prop["size"])*.5+2 if prop["kind"] in ("sidewalk","guardrail") else 0
        for key in cells((p[0]-radius,p[1]-radius,p[0]+radius,p[1]+radius),CHUNK):
            chunks[key]["props"].append(index)
    for i,junction in enumerate(junctions):
        x,y=junction["p"]
        radius=float(junction["radius"])+8
        for key in cells((x-radius,y-radius,x+radius,y+radius),CHUNK):
            chunks[key]["junctions"].append(i)
    for t in terrain[:1]+sorted(terrain[1:],key=lambda t:t.get("editor_draw_order",0)):
        xs=[p[0] for p in t["points"]]
        ys=[p[1] for p in t["points"]]
        for x in range(max(0,math.floor(min(xs)/CHUNK)),min(math.ceil(width/CHUNK),math.floor(max(xs)/CHUNK)+1)):
            for y in range(max(0,math.floor(min(ys)/CHUNK)),min(math.ceil(height/CHUNK),math.floor(max(ys)/CHUNK)+1)):
                polygon=clip_rect(t["points"],x*CHUNK,y*CHUNK,min(width,(x+1)*CHUNK),min(height,(y+1)*CHUNK))
                if len(polygon)>=3:
                    entry=dict(kind=t["kind"],color=t["color"],points=polygon)
                    for field in ("barrier","elevation","editor_draw_order"):
                        if field in t:entry[field]=t[field]
                    chunks[f"{x},{y}"]["terrain"].append(entry)
    # Streaming disables collision on chunks outside the active player ring.
    # Long boundary walls assigned to their midpoint chunk would disappear
    # near the map's corners. Divide every edge by chunk instead.
    walls=[]
    corners=[[0,0],[width,0],[width,height],[0,height]]
    for a,b in zip(corners,corners[1:]+corners[:1]):
        length=distance(a,b)
        steps=max(1,math.ceil(length/CHUNK))
        for step in range(steps):
            u=step/steps
            v=(step+1)/steps
            start=[a[k]+(b[k]-a[k])*u for k in range(2)]
            finish=[a[k]+(b[k]-a[k])*v for k in range(2)]
            mid=[(start[k]+finish[k])*.5 for k in range(2)]
            index=len(walls)
            walls.append([start,finish])
            x=min(math.ceil(width/CHUNK)-1,max(0,int(mid[0]//CHUNK)))
            y=min(math.ceil(height/CHUNK)-1,max(0,int(mid[1]//CHUNK)))
            chunks[f"{x},{y}"]["walls"].append(index)
    result=dict(format="streetbound.streamed-world",version=1,units="metres",
                name=str(doc.get("name","Custom Test Drive")),pixels_per_metre=20,
                editor_custom_test_drive=True,road_width_scale=1.10,
                rain_intensity=float(rain),
                size=[width,height],original_extent=[width,height],
                chunk_size=CHUNK,surface_cell=CELL,
                nodes=nodes,roads=roads,segments=segments,props=props,
                districts=[],terrain=terrain,walls=walls,junctions=junctions,bridges=[],
                road_connections=[list(pair) for pair in sorted(connections)],surface_index=dict(grid),
                chunks=dict(chunks),road_crossings=crossings,relief_faces=[],
                mountain_rails=[],editor_world_id=Path(doc.get("_source_filename","custom-map.world.json")).name,
                editor_warnings=[],visual_relief=dict(extent=[width,height],
                    sun_direction=[-.65,-.76],maximum_m=1000),
                stats=dict(roads=len(roads),props=len(props),junctions=len(junctions)))
    result.update(gameplay)
    if gameplay_zones:result["gameplay_zones"]=gameplay_zones
    if "terrainHeight" in doc:
        field=doc["terrainHeight"]
        if not isinstance(field,dict) or field.get("size")!=129 or not isinstance(field.get("values"),list) or len(field["values"])!=129*129 or any(type(v) not in (int,float) or not math.isfinite(v) or abs(v)>1200 for v in field["values"]):
            raise ValueError("Invalid authored terrain height field")
        result["terrainHeight"]=field
    validate_open_cuts(result)
    result['editor_warnings'].extend(audit_elevated_objectives(result))
    bake_jumps(result)
    return result


def scenery_rebuild(archive, doc):
    """Reuse previously validated road, terrain, junction and wall geometry.

    Only call when the entire non-scenery source and compiler fingerprint
    match. Revalidate all scenery and jump corridors; regenerate positional
    prop indices because changing array order would otherwise break streaming.
    """
    width,height=archive["size"]
    props=[p for p in _authoring_props(with_auto_props(doc,archive["roads"],archive["junctions"],width,height),width,height) if not p.get("hidden")]
    archive["props"]=props
    chunks=archive["chunks"]
    for key in list(chunks):
        chunks[key]["props"]=[]
        if not any(chunks[key].values()):
            del chunks[key]
    for index,prop in enumerate(props):
        p=prop["p"]
        radius=math.hypot(*prop["size"])*.5+2 if prop["kind"] in ("sidewalk","guardrail") else 0
        for key in cells((p[0]-radius,p[1]-radius,p[0]+radius,p[1]+radius),CHUNK):
            chunks.setdefault(key,dict(segments=[],props=[],walls=[],junctions=[],terrain=[],
                                       relief=[],rails=[],mountains=[],bridges=[]))["props"].append(index)
    archive["stats"]["props"]=len(props)
    rain=doc.get("rain_intensity",0.0)
    if isinstance(rain,bool) or not isinstance(rain,(int,float)) or not math.isfinite(rain) or not 0<=rain<=1:
        raise ValueError("Invalid rain intensity")
    zones,_=validate_gameplay(doc,width,height)
    archive["rain_intensity"]=float(rain)
    archive["name"]=str(doc.get("name","Custom Test Drive"))
    archive.update(_gameplay_payload(doc,archive["roads"],width,height))
    archive.pop("gameplay_zones",None)
    if zones:archive["gameplay_zones"]=zones
    validate_open_cuts(archive)
    archive["editor_warnings"]=audit_elevated_objectives(archive)
    archive.pop("jumps",None)
    bake_jumps(archive)
    return archive


def geometry_cache_key(doc):
    digest=hashlib.sha256()
    geometry={key:value for key,value in doc.items() if key not in {"props","assets","markers","races","dealerships","rain_intensity","gameplayZones","editorLayers","name"}}
    digest.update(json.dumps(geometry,sort_keys=True,separators=(",",":"),allow_nan=False).encode())
    # Any compiler source change invalidates this optional local cache.
    for path in sorted(Path(__file__).resolve().parent.glob("*.py")):
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def _atomic_json(destination, value):
    destination.parent.mkdir(parents=True,exist_ok=True)
    temporary=destination.with_suffix(destination.suffix+".tmp")
    temporary.write_text(json.dumps(value,separators=(",",":"),allow_nan=False),encoding="utf-8")
    temporary.replace(destination)


def exact_source_key(doc, geometry_key):
    # A complete revision key is stricter than the existing geometry key.
    # Include resource metadata used by source asset resolution as well.
    digest=hashlib.sha256(geometry_key.encode())
    digest.update(json.dumps(doc,sort_keys=True,separators=(",",":"),allow_nan=False).encode())
    root=Path(__file__).resolve().parent.parent
    for folder in (root/"assets"/"Buildings",root/"assets"/"Map Building Assets"):
        if folder.is_dir():
            for path in sorted(folder.rglob("*")):
                if path.is_file():
                    stat=path.stat()
                    digest.update(str(path.relative_to(root)).encode())
                    digest.update(f"{stat.st_size}:{stat.st_mtime_ns}".encode())
    return digest.hexdigest()


def build_file(source_path, output_path, cache_path=None):
    source=Path(source_path)
    destination=Path(output_path)
    if not source.is_file() or source.stat().st_size>MAX_SOURCE_BYTES:
        raise ValueError("Missing or oversized saved custom map")
    doc=json.loads(source.read_text(encoding="utf-8"))
    doc["_source_filename"]=source.name
    result=None
    cache=Path(cache_path) if cache_path else None
    key=geometry_cache_key(doc) if cache else None
    exact_key=exact_source_key(doc,key) if cache else None
    if cache and cache.is_file() and cache.stat().st_size<128_000_000:
        try:
            prior=json.loads(cache.read_text(encoding="utf-8"))
            if prior["key"]==key:
                archive=prior["archive"]
                encoded=json.dumps(archive,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
                if hashlib.sha256(encoded).hexdigest()==prior["checksum"] and archive.get("format")=="streetbound.streamed-world":
                    if prior.get("exact_key")==exact_key:
                        result=archive
                        print("Reused checksum-verified complete Test Drive archive.")
                    else:
                        result=scenery_rebuild(archive,doc)
                        print("Reused validated geometry; updated scenery and streaming membership.")
        except (OSError,ValueError,TypeError,KeyError,IndexError,AttributeError):
            # A damaged cache or changed scenery cannot bypass a full bake.
            result=None
    if result is None:
        result=make_archive(doc)
    _atomic_json(destination,result)
    if cache:
        try:
            encoded=json.dumps(result,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
            if len(encoded)<120_000_000:
                _atomic_json(cache,{"key":key,"exact_key":exact_key,"checksum":hashlib.sha256(encoded).hexdigest(),"archive":result})
        except (OSError,ValueError,TypeError):
            # An unavailable cache must not invalidate a successful bake.
            pass
    return result


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source",required=True)
    parser.add_argument("--output",required=True)
    parser.add_argument("--cache",help="Optional local Test Drive geometry cache; omit for authoritative publish builds")
    args=parser.parse_args()
    try:
        result=build_file(args.source,args.output,args.cache)
        print(json.dumps(result["stats"]))
    except (OSError,ValueError,TypeError,KeyError,IndexError,AssertionError) as error:
        print("TEST DRIVE BAKE FAILED:",error,file=sys.stderr)
        sys.exit(1)
