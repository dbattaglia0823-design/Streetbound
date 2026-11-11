"""Author Morrow Coast in metres; bake spatial cells, safe scenery and overview.

Original world. Atlas Coast is reference only and is never read or overwritten.
Run with Python 3, no third-party dependencies.
"""
import collections
import json
import math
import random
from pathlib import Path
from mountain_field import height_m
from junction_bake import build_junctions
from morrow_editor_import import apply_edits

ROOT = Path(__file__).resolve().parents[1]
WIDTH, HEIGHT, CHUNK, CELL = 6400, 4800, 192, 64
RNG = random.Random(28114)
NODES, ROADS, PROPS, POIS, TERRAIN, WALLS = {}, [], [], [], [], []


def node(name, x, y):
    NODES[name] = (x, y)
    return name


def distance(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def near(p, a, b):
    vx, vy = b[0] - a[0], b[1] - a[1]
    t = max(0, min(1, ((p[0] - a[0]) * vx + (p[1] - a[1]) * vy) / max(vx * vx + vy * vy, 1e-9)))
    q = (a[0] + vx * t, a[1] + vy * t)
    return distance(p, q), q


def smooth(points, start_neighbor=None, end_neighbor=None):
    """Cubic Hermite handles limited at acute bends; roughly 6m samples."""
    out = []
    count = len(points)
    for i in range(count - 1):
        a, b = points[i], points[i + 1]
        before = points[i - 1] if i else (start_neighbor or a)
        after = points[i + 2] if i + 2 < count else (end_neighbor or b)
        chord = distance(a, b)
        ta = ((b[0] - before[0]) * 0.33, (b[1] - before[1]) * 0.33)
        tb = ((after[0] - a[0]) * 0.33, (after[1] - a[1]) * 0.33)
        la, lb = math.hypot(*ta), math.hypot(*tb)
        if la > chord * .7:
            ta = tuple(v * chord * .7 / la for v in ta)
        if lb > chord * .7:
            tb = tuple(v * chord * .7 / lb for v in tb)
        for j in range(max(2, math.ceil(chord / 6))):
            t = j / max(2, math.ceil(chord / 6))
            h0, h1 = 2*t**3-3*t*t+1, -2*t**3+3*t*t
            h2, h3 = t**3-2*t*t+t, t**3-t*t
            out.append([round(h0*a[k] + h1*b[k] + h2*ta[k] + h3*tb[k], 3) for k in (0, 1)])
    out.append(list(points[-1]))
    return out


def road_spline(points, previous=None, following=None, kind="local"):
    """Adaptive cubic tessellation: <=4cm chord error, shared route tangents.

    Long straights stay cheap, while hairpins get sub-metre edge samples.
    """
    output=[]
    tension=.45 if kind=="highway" else .4
    for i in range(len(points)-1):
        a,b=points[i],points[i+1]
        before=points[i-1] if i else (previous or a)
        after=points[i+2] if i+2<len(points) else (following or b)
        chord=distance(a,b)
        ta=[(b[k]-before[k])*tension for k in (0,1)]
        tb=[(after[k]-a[k])*tension for k in (0,1)]
        for tangent in [ta,tb]:
            length=math.hypot(*tangent)
            if length>chord*.85:
                tangent[:]=[v*chord*.85/length for v in tangent]
        def evaluate(t):
            h0,h1=2*t**3-3*t*t+1,-2*t**3+3*t*t
            h2,h3=t**3-2*t*t+t,t**3-t*t
            return [h0*a[k]+h1*b[k]+h2*ta[k]+h3*tb[k] for k in (0,1)]
        def flatten(t0,t1,p0,p1,depth=0):
            third=(t1-t0)/3
            error=max(near(evaluate(t0+third),p0,p1)[0],near(evaluate(t1-third),p0,p1)[0])
            if depth<16 and (distance(p0,p1)>6 or error>.035):
                middle=(t0+t1)/2
                midpoint=evaluate(middle)
                flatten(t0,middle,p0,midpoint,depth+1)
                flatten(middle,t1,midpoint,p1,depth+1)
            else:
                output.append([round(p0[0],3),round(p0[1],3)])
        flatten(0,1,list(a),list(b))
    output.append(list(points[-1]))
    return output


def road(name, start, end, via=(), kind="local", width=None, surface="ASPHALT", grade=0):
    widths = {"local": 9, "arterial": 12, "highway": 18, "rural": 8, "mountain": 7.5, "track": 14, "driveway": 8, "gravel": 6}
    points = [NODES[start], *via, NODES[end]]
    data = dict(id=len(ROADS), name=name, start=start, end=end, kind=kind, width=width or widths[kind],
                surface=surface, grade=grade, anchors=points, points=smooth(points), lanes=4 if kind == "highway" else (1 if kind == "driveway" else 2))
    ROADS.append(data)
    return data


def chain(name, ids, kind="local", **kwargs):
    for a, b in zip(ids, ids[1:]):
        road(name, a, b, kind=kind, **kwargs)


def polygon(kind, points, color):
    TERRAIN.append(dict(kind=kind, points=points, color=color))


# Geography: a sheltered eastern coast, upland reservoir and a valley river.
COAST = [(5280, 0), (5350, 400), (5200, 850), (5260, 1250), (5420, 1650), (5350, 2050),
         (5200, 2420), (5230, 2680), (5400, 3020), (5330, 3380), (5150, 3800), (5270, 4270), (5190, 4800)]
COAST = smooth(COAST)

def shore_x(y):
    for a,b in zip(COAST,COAST[1:]):
        if a[1]<=y<=b[1]:
            return a[0]+(b[0]-a[0])*(y-a[1])/(b[1]-a[1])
    return COAST[-1][0]
RIVER = smooth([(1350, 1580), (1850, 1800), (2450, 1760), (3000, 1870), (3550, 1790), (4300, 1930), (5400, 1900)])
polygon("forest", [(0,0),(4200,0),(4400,900),(3800,1600),(3000,1530),(2300,1900),(1500,1750),(600,2300),(0,2100)], "718d70")
polygon("mountain", [(0,0),(1950,0),(2300,850),(1920,1400),(1200,1700),(450,1900),(0,1700)], "9baba0")
polygon("highland", [(100,0),(1400,0),(1800,550),(1400,950),(800,1350),(200,1320)], "b3b9a4")
polygon("farmland", [(250,2400),(1900,2250),(2220,3400),(2000,4550),(200,4600)], "b4bd8a")
polygon("city", [(2350,2320),(3000,2080),(3860,2270),(4000,2970),(3680,3590),(2790,3650),(2290,3300)], "b1b6a0")
polygon("town", [(4490,2370),(4930,2310),(5200,2600),(5150,3010),(4700,3130),(4380,2800)], "bdc3a8")
for zone in TERRAIN:
    if zone["kind"] in ["forest","mountain","highland","farmland","city","town"]:
        controls=zone["points"]
        zone["points"]=smooth(controls+[controls[0]],controls[-1],controls[1])[:-1]
polygon("beach", [(x-65,y) for x,y in COAST] + [(WIDTH,HEIGHT),(WIDTH,0)], "e3d4aa")
polygon("ocean", COAST + [(WIDTH,HEIGHT),(WIDTH,0)], "82b5b5")
polygon("foam",[(x-1.0,y) for x,y in COAST]+[(x+1.2,y) for x,y in COAST[::-1]],"c6d9c9")
RIVER_LEFT, RIVER_RIGHT = [], []
for i, p in enumerate(RIVER):
    a, b = RIVER[max(0,i-1)], RIVER[min(len(RIVER)-1,i+1)]
    d = max(distance(a,b), .01)
    n = (-(b[1]-a[1])/d, (b[0]-a[0])/d)
    RIVER_LEFT.append([p[0]+n[0]*15,p[1]+n[1]*15])
    RIVER_RIGHT.append([p[0]-n[0]*15,p[1]-n[1]*15])
polygon("riverbank", RIVER_LEFT + RIVER_RIGHT[::-1], "8cafa0")
polygon("water", RIVER_LEFT + RIVER_RIGHT[::-1], "82b5b5")
LAKE = [(1350+math.cos(i*math.tau/38)*220*(1+.12*math.sin(i*1.7)), 1490+math.sin(i*math.tau/38)*155) for i in range(38)]
polygon("water", LAKE, "82b5b5")

# Named anchors, not an endless rectangular grid.
for name, x, y in [
    ("west",1100,3250),("village",1400,2920),("mill",1750,2500),("west_gate",2190,2800),
    ("sw",2500,3200),("start",2485,3080),("wm",2500,2870),("wn",2620,2500),
    ("nw",2780,2330),("dn",3020,2370),("ne",3520,2400),("en",3760,2600),
    ("em",3770,2900),("se",3540,3290),("ds",3080,3290),("sm",2830,3280),
    ("dw",2780,2820),("dc",3070,2790),("de",3400,2830),("park",3020,3050),
    ("suburb",2300,3450),("commerce",3390,3100),("port",3860,3250),
    ("hnw",2100,2060),("hn",2960,2020),("hne",3980,2110),("he",4160,2800),
    ("hse",4240,3510),("hs",3450,3620),("hsw",2200,3630),
    ("tn",4700,2390),("tw",4520,2690),("tc",4790,2670),("te",5010,2670),("ts",4780,2960),
    ("tse",5070,2940),("marina",5110,2750),("coastn",4980,1190),("coastf",4950,3500),
    ("coasts",4750,4170),("mwest",650,2280),("mstart",600,1880),("hairpin",700,1320),
    ("overlook",1010,900),("summit",1600,710),("forest",2490,970),("forest_e",3580,1110),
    ("lake_w",970,1720),("lake_e",1950,1570),("country_s",1300,4040),
    ("trackgate",3490,3770),("trackn",3490,3870),("dragn",4340,3910),("drags",4340,4550),
    ("trackw",2860,4200),("tracke",4150,4190),("tracks",3470,4510),
]: node(name,x,y)

# Keep the scenic highway within sight of the sea at the gameplay camera scale.
for key,margin in [("coastn",65),("te",22),("tse",22),("marina",18),("coastf",60),("coasts",60)]:
    _,y=NODES[key]
    NODES[key]=(shore_x(y)-margin,y)

# Separate village side streets into spaced T junctions instead of a seven-arm knot.
for name,x,y in [("village_n",1460,2800),("village_w",1290,2970),
                 ("village_s",1190,3110),("village_e",1550,2970),("harvest_gate",980,3400),("saltair_entry",4910,2965)]:
    node(name,x,y)

chain("Laurel Avenue", ["sw","start","wm","wn","nw"], "arterial")
chain("Foundry Crescent", ["nw","dn","ne","en","em","se","ds","sm","sw"], "arterial")
chain("Market Street", ["wm","dw","dc","de","em"])
road("Civic Crescent", "dn","dc", [(3100,2520)])
road("Orchard Lane", "wn","dw", [(2730,2620)])
road("Museum Walk", "dw","park", [(2800,3000)])
road("Garden Avenue", "park","ds", [(3100,3170)])
road("Canal Street", "dc","park", [(3010,2920)])
road("Eastgate Boulevard", "ne","de", [(3500,2590)])
road("Copper Lane", "de","commerce", [(3460,2960)])
road("Warehouse Way", "commerce","port", [(3630,3110)])
road("Harbor Service Road", "port","em", [(3930,3070)])
road("Station Road", "commerce","se", [(3430,3230)])
road("Willow Crescent", "sm","suburb", [(2590,3400)])
road("Orchard Crescent", "suburb","sw", [(2290,3280)])
road("Westgate Drive", "wm","west_gate", [(2350,2840)], kind="arterial")
road("Meadow Road", "west_gate","village_e", [(1970,2890),(1740,3060)], kind="rural")
road("Meadow Road", "village_e","village", kind="rural")
road("Old Mill Lane", "village","village_n", [(1430,2850)], kind="rural")
road("Old Mill Lane", "village_n","mill", [(1550,2740),(1600,2590)], kind="rural")
road("Mill Bypass", "mill","west_gate", [(2020,2560)], kind="rural")
chain("West Orchard Road",["village","village_w","village_s","west"],"rural")
road("Harvest Road", "west","harvest_gate", [(1040,3320)], kind="rural")
road("Harvest Road", "harvest_gate","country_s", [(850,3560),(1000,3820)], kind="rural")
road("South County Road", "country_s","hsw", [(1650,4240),(2050,4050)], kind="rural")
road("Farmstead Link", "village_s","hsw", [(1480,3290),(1810,3530)], kind="rural")
chain("Morrow Parkway", ["hnw","hn","hne","he","hse","hs","hsw"], "highway")
road("Morrow Parkway", "hsw","hnw", [(1970,3240),(2020,2540)], kind="highway")
road("Westgate Slip Road", "west_gate","hnw", [(2260,2530),(2200,2240)], kind="arterial")
road("Southern Slip Road", "suburb","hsw", [(2180,3520)], kind="arterial")
road("Eastgate Slip Road", "em","he", [(3970,2840)], kind="arterial")
road("Port Slip Road", "port","hse", [(4000,3390)], kind="arterial")
# Northern city traffic uses Civic Gateway and its roundabout below, rather
# than a redundant diagonal cutting across the same approach.
# The river crossings are bridges over water, not invented road junctions.
road("Juniper Valley Bridge", "mill","lake_e", [(1900,2220),(2030,1900)], kind="rural", grade=1)
road("Forest Bridge", "hn","forest", [(2790,1700),(2590,1350)], kind="arterial", grade=1)
road("Seabreeze Causeway", "hne","tn", [(4300,2100),(4530,2230)], kind="arterial")
road("Coast Connector", "he","tw", [(4340,2710)], kind="arterial")
road("Waterfront Drive", "tn","te", [(4920,2410),(5050,2520)], kind="local")
chain("Bellwether High Street", ["tn","tc","ts"], "arterial")
chain("Sailmaker Lane", ["tw","tc","te"])
chain("Waterfront Esplanade",["te","marina","tse"])
chain("Sailmaker Lane",["tse","saltair_entry","ts","tw"])
road("Pacific Scenic Highway", "forest_e","coastn", [(4150,850),(4750,900)], kind="rural")
road("Pacific Scenic Highway", "coastn","tn", [(shore_x(1530)-70,1530),(shore_x(1870)-70,1870),(4930,2160)], kind="rural")
road("Pacific Scenic Highway", "ts","coastf", [(4830,3070),(shore_x(3160)-120,3160)], kind="rural")
road("Pacific Scenic Highway", "coastf","coasts", [(shore_x(3790)-70,3790)], kind="rural")
road("South Coastal Link", "coasts","hse", [(4520,3990)], kind="arterial")
road("Juniper Approach", "village_n","mwest", [(1050,2690),(750,2490)], kind="rural")
road("Juniper Pass", "mwest","mstart", [(540,2100)], kind="mountain")
# Three linked, generously spaced switchbacks climb the west-facing escarpment.
road("Juniper Pass", "mstart","hairpin", [(510,1800),(345,1750),(265,1700),(245,1645),(290,1600),
     (570,1595),(650,1560),(670,1510),(625,1470),(365,1465),(285,1430),(275,1380),(325,1340),(590,1345)], kind="mountain",width=8.5)
road("Juniper Pass", "hairpin","overlook", [(825,1240),(855,1165),(800,1120),(585,1105),
     (520,1060),(525,1000),(590,965),(840,970)], kind="mountain",width=8.5)
road("Summit Ribbon", "overlook","summit", [(1160,760),(1370,810),(1490,720)], kind="mountain")
road("Pinecrest Road", "summit","forest", [(1900,600),(2150,740)], kind="rural")
road("Forest Canopy Road", "forest","forest_e", [(2840,1160),(3200,950)], kind="rural")
road("Reservoir Loop", "mstart","lake_w", [(750,1810)], kind="mountain")
road("Reservoir Loop", "lake_w","overlook", [(920,1430),(1080,1220)], kind="mountain")
road("Reservoir Loop", "overlook","lake_e", [(1300,1100),(1680,1250)], kind="mountain")
road("Ranger Trail", "lake_e","forest", [(2070,1370),(2300,1340)], kind="gravel", surface="GRAVEL")
# Purposeful alternatives: a broad high-country traverse and two rural loops.
# They connect existing towns/venues rather than producing disconnected spurs.
node("applecross",680,3220)
node("quarry",650,4330)
road("Ridgeline Traverse","summit","coastn",[(2200,380),(2900,420),(3600,300),(4300,420),(4800,650)],kind="rural",width=9)
road("Orchard Heritage Road","village_w","applecross",[(1080,2840),(780,2950)],kind="rural")
road("Orchard Heritage Road","applecross","west",[(720,3300),(820,3210),(940,3200)],kind="rural")
road("Quarry Rally Road","country_s","quarry",[(1050,4380),(800,4470)],kind="gravel",surface="GRAVEL")
road("Quarry Rally Road","quarry","harvest_gate",[(400,4020),(500,3620),(820,3420)],kind="gravel",surface="GRAVEL")
road("Paddock Avenue", "hs","trackgate", [(3530,3680)], kind="arterial")
road("Paddock Entry", "trackgate","trackn", kind="driveway")
road("Ashford Grand Circuit", "trackn","trackw", [(3120,3910),(2880,4020)], kind="track")
road("Ashford Grand Circuit", "trackw","tracks", [(2870,4380),(3100,4510)], kind="track")
road("Ashford Grand Circuit", "tracks","tracke", [(3730,4470),(3930,4530),(4120,4410)], kind="track")
road("Ashford Grand Circuit", "tracke","trackn", [(4050,3970),(3850,3860)], kind="track")
road("Raceworks Service Road", "trackgate","dragn", [(3870,3690),(4320,3750)], kind="local")
road("Ashford Drag Strip", "dragn","drags", kind="track", width=21)
road("Drag Return Lane", "drags","dragn", [(4440,4530),(4460,4020)], kind="local")
road("South Paddock Link", "tracks","drags", [(3790,4690),(4160,4680)], kind="local")

# A true four-arm roundabout, with a raised planted central island.
cx, cy, radius = 2950, 2240, 24
for i, name in enumerate(["rn","re","rs","rw"]):
    angle = -math.pi/2 + i*math.pi/2
    node(name, cx+math.cos(angle)*radius, cy+math.sin(angle)*radius)
for i, (a,b) in enumerate(zip(["rn","re","rs","rw"],["re","rs","rw","rn"])):
    angle = -math.pi/2 + (i+.5)*math.pi/2
    road("Civic Roundabout",a,b,[(cx+math.cos(angle)*radius,cy+math.sin(angle)*radius)],width=10)
road("Civic Gateway", "hn","rn", [(2900,2120)], kind="arterial")
road("Civic Gateway", "rs","dn", kind="arterial")
road("Library Approach", "rw","nw")
road("East Civic Link", "re","ne", [(3230,2270)])


def add_poi(name, category, anchor, direction, style="garage"):
    a = NODES[anchor]
    norm = math.hypot(*direction)
    d = (direction[0]/norm, direction[1]/norm)
    p = (a[0]+d[0]*65,a[1]+d[1]*65)
    key = "poi_" + str(len(POIS))
    node(key,*p)
    road(name+" access",anchor,key,kind="driveway")
    POIS.append(dict(name=name,category=category,position=list(p),anchor=anchor,road=len(ROADS)-1))
    PROPS.append(dict(kind="lot", p=list(p), size=[38,28], angle=math.atan2(d[1],d[0]), color="b6b7a6", solid=False, radius=0, seed=RNG.randrange(100000)))
    apron=[p[0]+d[0]*24,p[1]+d[1]*24]
    PROPS.append(dict(kind="forecourt",p=apron,size=[23,16],angle=math.atan2(d[1],d[0]),color="8b9290",solid=False,radius=0,seed=0))
    center = (p[0]+d[0]*42,p[1]+d[1]*42)
    PROPS.append(dict(kind=style,p=list(center),size=[24,30],angle=math.atan2(d[1],d[0]),color="c9b398",solid=True,radius=19.3,seed=RNG.randrange(100000),poi=name))

add_poi("Laurel Motor House", "START / GARAGE", "start", (-1,0))
add_poi("Larkspur Performance", "CUSTOMIZATION", "commerce", (-1,0), "workshop")
add_poi("Eastgate Auto Gallery", "DEALERSHIP", "en", (1,-.5), "showroom")
add_poi("Parkway Fuel & Coffee", "FUEL", "he", (1,1), "fuel")
add_poi("Willowmere Village", "VILLAGE / GARAGE", "village_e", (-.2,-1), "house")
add_poi("Juniper Lookout", "SCENIC OVERLOOK", "overlook", (-.3,-1), "cafe")
add_poi("Pinecrest Lodge", "LANDMARK", "summit", (0,-1), "lodge")
add_poi("Bellwether Marina", "MARINA", "marina", (-.1,1), "cafe")
add_poi("Saltair Motors", "COASTAL GARAGE", "saltair_entry", (.1,-1), "garage")
add_poi("Seaglass Overlook", "COASTAL OVERLOOK", "coastn", (-1,0), "cafe")
add_poi("Ashford Raceworks", "RACE PADDOCK", "trackgate", (-1,0), "workshop")
add_poi("Drag Staging", "DRAG START", "dragn", (-1,0), "fuel")
add_poi("Harvest Rest", "COUNTRY FUEL", "country_s", (-1,0), "fuel")
add_poi("Applecross Farm", "LANDMARK", "applecross", (-1,-.25), "lodge")
add_poi("Old Quarry Yard", "RALLY LANDMARK", "quarry", (-1,0), "warehouse")

# The start is the apron, facing its eastbound driveway.
SPAWN = dict(position=[POIS[0]["position"][0]-8,POIS[0]["position"][1]], rotation=math.pi/2)
DISTRICTS = [dict(name="LARKSPUR",subtitle="Gardens, markets & the old foundry",p=[3030,2850],radius=900),
             dict(name="BELLWETHER BAY",subtitle="Salt air & waterfront streets",p=[4800,2690],radius=560),
             dict(name="WILLOWMERE",subtitle="Orchards & winding county lanes",p=[1400,3150],radius=900),
             dict(name="JUNIPER RIDGE",subtitle="Forest passes & reservoir overlooks",p=[1400,1000],radius=1400),
             dict(name="ASHFORD PARK",subtitle="Grand circuit & quarter-mile straight",p=[3550,4180],radius=750)]


def keys_for(bounds, cell):
    x0,y0,x1,y1 = bounds
    for x in range(math.floor(x0/cell),math.floor(x1/cell)+1):
        for y in range(math.floor(y0/cell),math.floor(y1/cell)+1):
            yield f"{x},{y}"


# Optional versioned overlay from the browser Map Builder. Applied to authored
# control points BEFORE sampling, junction baking, scenery placement and collision
# indices. Rebuilds the entire streamed world rather than patching stale segments.
EDITOR_MARKERS = apply_edits(ROADS, NODES, TERRAIN, POIS, SPAWN, PROPS)
# Defer objects adopted from procedural scenery until the untouched native
# generators finish, or the replacement would suppress its own original.
ADOPTED_PROPS=[prop for prop in PROPS if prop.get("source_replacement")]
PROPS[:]=[prop for prop in PROPS if not prop.get("source_replacement")]

# Connected pieces of the same named route share tangent directions at their
# endpoint, so highway bends and mountain transitions don't form sharp kinks.
for r in ROADS:
    def neighboring(endpoint):
        for other in ROADS:
            if other is r or other["name"]!=r["name"]: continue
            if other["end"]==endpoint: return other["anchors"][-2]
            if other["start"]==endpoint: return other["anchors"][1]
        incident=[other for other in ROADS if endpoint in [other["start"],other["end"]] and other["kind"]!="driveway"]
        if len(incident)==2 and all(other["kind"] in ["rural","mountain","gravel"] for other in incident):
            other=next(other for other in incident if other is not r)
            return other["anchors"][-2] if other["end"]==endpoint else other["anchors"][1]
        return None
    r["points"]=road_spline(r["anchors"],neighboring(r["start"]),neighboring(r["end"]),r["kind"])
    if r["name"]=="Pacific Scenic Highway":
        # A cubic handle must never cut across a coastal inlet into the sea.
        for p in r["points"]:
            limit=shore_x(p[1])-18
            blend=max(0,4-abs(p[0]-limit))
            p[0]=round(min(p[0],limit)-blend*blend/16,3)
for r in ROADS:
    r["visual_elevation_m"]=[round(height_m(*p),1) for p in r["points"]]
SEGMENTS, GRID = [], collections.defaultdict(list)
for r in ROADS:
    for a,b in zip(r["points"],r["points"][1:]):
        index = len(SEGMENTS)
        SEGMENTS.append(dict(a=a,b=b,road=r["id"]))
        pad = r["width"]/2+12
        for key in keys_for((min(a[0],b[0])-pad,min(a[1],b[1])-pad,max(a[0],b[0])+pad,max(a[1],b[1])+pad),CELL):
            GRID[key].append(index)


def road_clear(p, radius=0):
    for key in keys_for((p[0]-radius,p[1]-radius,p[0]+radius,p[1]+radius),CELL):
        for index in GRID.get(key,[]):
            s = SEGMENTS[index]
            if near(p,s["a"],s["b"])[0] < ROADS[s["road"]]["width"]/2+radius+2.0:
                return False
    for j in JUNCTION_CLEARANCE.get(f"{int(p[0]//CELL)},{int(p[1]//CELL)}",[]):
        poly=j["polygon"]
        if in_poly(p,poly) or any(near(p,a,b)[0]<radius+.6 for a,b in zip(poly,poly[1:]+poly[:1])):
            return False
    return True


def in_poly(p, poly):
    inside = False
    for a,b in zip(poly,poly[1:]+poly[:1]):
        if (a[1]>p[1]) != (b[1]>p[1]) and p[0] < (b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]:
            inside = not inside
    return inside


# All roads share the drivable 2D plane; grade=1 denotes a water bridge,
# not an invented flyover. One bake covers endpoint T joins and crossings.
JUNCTIONS,connections,CROSSINGS=build_junctions(ROADS,NODES,SEGMENTS,GRID)

JUNCTION_CLEARANCE=collections.defaultdict(list)
for j in JUNCTIONS:
    x,y=j["p"]; pad=j["radius"]+25
    for key in keys_for((x-pad,y-pad,x+pad,y+pad),CELL):JUNCTION_CLEARANCE[key].append(j)


def land(p):
    return 60 < p[0] < WIDTH-60 and 60 < p[1] < HEIGHT-60 and not any(in_poly(p,t["points"]) for t in TERRAIN if t["kind"] in ["ocean","water"])


# Fix dedicated facilities conservatively before any decorative placement.
for prop in PROPS:
    if prop["solid"] and not road_clear(prop["p"],prop["radius"]):
        poi = next(p for p in POIS if p["name"]==prop["poi"])
        p, angle = poi["position"], prop["angle"]
        candidates = [(angle+turn,offset) for offset in [42,50,60,75] for turn in [0,math.pi/2,-math.pi/2,math.pi]]
        for facing,offset in candidates:
            candidate = [p[0]+math.cos(facing)*offset,p[1]+math.sin(facing)*offset]
            if road_clear(candidate,prop["radius"]) and land(candidate):
                prop["p"],prop["angle"] = candidate,facing
                break
        else:
            # A safe smaller pavilion still gives the location a clear identity.
            prop["size"], prop["radius"] = [12,12],8.5

PROP_GRID = collections.defaultdict(list)


def occupied(p, radius):
    for key in keys_for((p[0]-radius-35,p[1]-radius-35,p[0]+radius+35,p[1]+radius+35),64):
        for other in PROP_GRID.get(key,[]):
            if distance(p,other["p"]) < radius+other.get("radius",0)+2:
                return True
    return False


def insert_prop(prop):
    PROPS.append(prop)
    PROP_GRID[f"{int(prop['p'][0]//64)},{int(prop['p'][1]//64)}"].append(prop)


for prop in list(PROPS):
    if prop["solid"]:
        PROP_GRID[f"{int(prop['p'][0]//64)},{int(prop['p'][1]//64)}"].append(prop)

# A few parked cars occupy marked stalls, leaving the driveway/aisle open.
for lot in list(PROPS):
    if lot["kind"]!="lot": continue
    angle=lot["angle"]
    if "occupancy" in lot:
        # Authored parking keeps stable occupancy on every rebake. The
        # existing procedural lots retain their original three parked cars.
        count=max(3,min(16,int(lot["size"][0]*.84/lot["stall_width"])))
        slots=[]
        for side in (-1,1):
            for i in range(count):
                fraction=((i*37+(23 if side>0 else 0)+lot["seed"]%97)%100)/100.0
                if fraction>=lot["occupancy"]: continue
                x=lot["size"][0]*(-.42+.84*(i+.5)/count)
                y=side*lot["size"][1]*.33
                slots.append((x,y))
    else:
        slots=[(-13.2,9.8),(2.7,-9.8),(10.7,9.8)]
    for x,y in slots:
        p=[lot["p"][0]+math.cos(angle)*x-math.sin(angle)*y,lot["p"][1]+math.sin(angle)*x+math.cos(angle)*y]
        if road_clear(p,2.5) and not occupied(p,2.5):
            insert_prop(dict(kind="parked_car",p=p,size=[1.9,4.6],angle=angle,color=RNG.choice(["9eb9b4","c39b8c","c6bb95"]),radius=2.5,solid=True,seed=RNG.randrange(100000)))
    edge_x=lot["size"][0]*.46
    edge_y=lot["size"][1]*.45
    for x,y in [(-edge_x,-edge_y),(edge_x,-edge_y),(-edge_x,edge_y),(edge_x,edge_y)]:
        p=[lot["p"][0]+math.cos(angle)*x-math.sin(angle)*y,lot["p"][1]+math.sin(angle)*x+math.cos(angle)*y]
        if road_clear(p,1.5):
            insert_prop(dict(kind="planter",p=p,size=[2.8,2.8],angle=angle,color="7b9a73",radius=0,solid=False,seed=42))


def style_at(p):
    x,y = p
    if ((x-3030)/790)**2+((y-2850)/650)**2 < 1:
        if x>3480 and y>2950: return "warehouse"
        if ((x-3050)/330)**2+((y-2770)/360)**2<1: return "building"
        return "house" if x<2820 or y>3210 else "shop"
    if ((x-4800)/450)**2+((y-2690)/400)**2<1: return "coastal_house" if y<2900 else "shop"
    if distance(p,(1400,2920))<190: return "house"
    if distance(p,(1600,710))<130: return "lodge"
    return ""


sizes = {"house":(12,17),"coastal_house":(13,17),"building":(22,29),"shop":(15,23),"warehouse":(28,37),"lodge":(16,22)}
colors = ["c2a589","c6b6a2","d2c2a2","9eaf9f","b4b5b4","bda39a"]
for r in list(ROADS):
    if r["kind"] not in ["local","arterial","rural"]: continue
    traversed, target = 0.0, RNG.uniform(16,40)
    for a,b in zip(r["points"],r["points"][1:]):
        traversed += distance(a,b)
        if traversed < target: continue
        target += RNG.uniform(20,31)
        angle = math.atan2(b[1]-a[1],b[0]-a[0])
        for side in [-1,1]:
            guess = [a[0]-math.sin(angle)*side*28,a[1]+math.cos(angle)*side*28]
            kind = style_at(guess)
            if not kind: continue
            size = sizes[kind]
            radius = math.hypot(*size)/2
            offset = r["width"]/2 + radius + RNG.uniform(2.5,4.0)
            p = [a[0]-math.sin(angle)*side*offset,a[1]+math.cos(angle)*side*offset]
            if not land(p) or not road_clear(p,radius) or occupied(p,radius): continue
            insert_prop(dict(kind=kind,p=p,size=size,angle=angle,color=RNG.choice(colors),radius=radius,solid=True,seed=RNG.randrange(100000)))
            # Garden/forecourt between the building and pavement, not on a lane.
            garden = [a[0]-math.sin(angle)*side*(r["width"]/2+3),a[1]+math.cos(angle)*side*(r["width"]/2+3)]
            if road_clear(garden,2):
                insert_prop(dict(kind="garden",p=garden,size=[size[0],2],angle=angle,color="94ae7c",radius=0,solid=False,seed=RNG.randrange(100000)))

# Fields are individual planted plots with soft hedges and farm access tracks.
for x in range(350,2000,170):
    for y in range(2500,4500,160):
        p = (x+RNG.uniform(-20,20),y+RNG.uniform(-20,20))
        if road_clear(p,65) and not occupied(p,65):
            insert_prop(dict(kind="field",p=p,size=[RNG.uniform(90,125),RNG.uniform(70,115)],angle=RNG.uniform(-.12,.12),color=RNG.choice(["c4c18a","a4b67e","bab786"]),radius=0,solid=False,seed=RNG.randrange(100000)))

# Forests have clustered clearings rather than uniformly sprinkled obstacles.
for y in range(90,HEIGHT-70,15):
    for x in range(80,5350,15):
        p = (x+RNG.uniform(-6,6),y+RNG.uniform(-6,6))
        forest = y<1650 or (x<1000 and y<2600) or (x>3900 and y<1500)
        density = .72 if forest else .045
        density *= .65+.35*math.sin(x*.012)*math.cos(y*.009)
        # The upper massif opens into rock and sparse alpine pines.
        density *= max(.12,1-max(0,height_m(*p)-650)/370)
        if RNG.random()>density or not land(p) or not road_clear(p,5) or occupied(p,5): continue
        if style_at(p) and RNG.random()<.8: continue
        kind = "pine" if y<1600 else "tree"
        if y>1600 and x>4650: kind="palm"
        canopy=RNG.uniform(7,12) if forest else RNG.uniform(4,8)
        insert_prop(dict(kind=kind,p=p,size=[canopy,canopy],angle=RNG.random()*math.tau,color=RNG.choice(["668765","789663","5e8269","839d72"]),radius=.65,solid=True,seed=RNG.randrange(100000)))

# Small roadside crop plots and hedge fences make cruising roads feel tended,
# while the larger field parcels continue across the valley behind them.
for r in ROADS:
    if r["name"] not in ["Meadow Road","Farmstead Link","Harvest Road","South County Road"]: continue
    for i in range(8,len(r["points"])-1,12):
        a,b=r["points"][i],r["points"][i+1]
        angle=math.atan2(b[1]-a[1],b[0]-a[0])
        for side in [-1,1]:
            p=[a[0]-math.sin(angle)*side*(r["width"]/2+18),a[1]+math.cos(angle)*side*(r["width"]/2+18)]
            if style_at(p) or not (p[0]<2100 and p[1]>2400): continue
            valid=True
            for x in range(-22,23,6):
                for y in range(-13,14,6):
                    q=[p[0]+math.cos(angle)*x-math.sin(angle)*y,p[1]+math.sin(angle)*x+math.cos(angle)*y]
                    if not road_clear(q,1.0): valid=False;break
                if not valid: break
            if valid:
                insert_prop(dict(kind="field",p=p,size=[45,28],angle=angle,color=RNG.choice(["bec18b","aebb84","c9bf88"]),radius=0,solid=False,seed=i))

for i in range(160):
    p=(RNG.uniform(220,2100),RNG.uniform(180,1600))
    radius=RNG.uniform(2,5)
    if land(p) and road_clear(p,radius+3) and not occupied(p,radius+2):
        insert_prop(dict(kind="rock",p=p,size=[radius*2,radius*1.5],angle=RNG.random()*math.tau,color=RNG.choice(["b3b4a5","a5af9e","c3c1ab"]),radius=radius,solid=True,seed=i))

# Street furniture follows the local road tangent, with collision-free sidewalks.
for r in ROADS:
    if r["kind"] not in ["local","arterial"]: continue
    traversed = target = 0.0
    for a,b in zip(r["points"],r["points"][1:]):
        traversed += distance(a,b)
        if traversed<target: continue
        target += 55
        if not style_at(a): continue
        angle=math.atan2(b[1]-a[1],b[0]-a[0])
        p=[a[0]-math.sin(angle)*(r["width"]/2+2.6),a[1]+math.cos(angle)*(r["width"]/2+2.6)]
        if road_clear(p,.35):
            insert_prop(dict(kind="lamp",p=p,size=[1,1],angle=angle,color="d4c6a5",radius=0,solid=False,seed=0))
        tree_p=[a[0]+math.sin(angle)*(r["width"]/2+6),a[1]-math.cos(angle)*(r["width"]/2+6)]
        if road_clear(tree_p,3) and not occupied(tree_p,3):
            insert_prop(dict(kind="tree",p=tree_p,size=[5.5,5.5],angle=angle,color="83a178",radius=.5,solid=True,seed=23))

for r in ROADS:
    if r["kind"]!="mountain": continue
    for index in range(10,len(r["points"])-1,19):
        p,q=r["points"][index],r["points"][index+1]
        tangent=math.atan2(q[1]-p[1],q[0]-p[0])
        for lateral in [13,20,27]:
            candidate=[p[0]-math.sin(tangent)*lateral,p[1]+math.cos(tangent)*lateral]
            radius=RNG.uniform(2.5,4.2)
            if road_clear(candidate,radius+1) and not occupied(candidate,radius) and land(candidate):
                insert_prop(dict(kind="rock",p=candidate,size=[radius*2,radius*1.65],angle=tangent,color=RNG.choice(["b8bbab","a8b4a5","c1c1ac"]),radius=radius,solid=True,seed=index))

# Raised roundabout island; its planting is deliberately outside the ring lanes.
insert_prop(dict(kind="island",p=[cx,cy],size=[23,23],angle=0,color="8da980",radius=11.5,solid=True,seed=42))

# Laurel Motor House serves as the start-area art benchmark. Its existing
# lot/garage/driveway remain untouched: add small low-cost planted borders
# only where road and building collision clearances permit.
laurel=POIS[0]
laurel_lot=next((item for item in PROPS if item["kind"]=="lot" and
                 distance(item["p"],laurel["position"])<1.0),None)
if laurel_lot:
    angle=laurel_lot["angle"]
    for i,(x,y) in enumerate([(-21,-17),(-21,17),(-29,-17),(-29,17)]):
        p=[laurel_lot["p"][0]+math.cos(angle)*x-math.sin(angle)*y,
           laurel_lot["p"][1]+math.sin(angle)*x+math.cos(angle)*y]
        if land(p) and road_clear(p,2.0) and not occupied(p,3.5):
            insert_prop(dict(kind="garden",p=p,size=[8.0,2.4],angle=angle,
                             color="91aa7c",radius=0,solid=False,
                             seed=814+i))

# Landmarks: marina finger piers remain on the safe side of the sea boundary.
for i in range(5):
    y=2795+i*29
    p=[shore_x(y)+6,y]
    if road_clear(p,5):
        insert_prop(dict(kind="dock",p=p,size=[5,27],angle=-math.pi/2,color="b7a582",radius=0,solid=False,seed=i))

# Real-world drag distance: 402m timed strip with additional paved run-off.
for y,kind in [(3940,"start_line"),(4342,"finish_line")]:
    insert_prop(dict(kind=kind,p=[4340,y],size=[21,1.2],angle=0,color="e1d5b9",radius=0,solid=False,seed=0))
track_road=next(r for r in ROADS if r["name"]=="Ashford Grand Circuit")
p,q=track_road["points"][8],track_road["points"][9]
insert_prop(dict(kind="start_line",p=p,size=[14,1.2],angle=math.atan2(q[1]-p[1],q[0]-p[0])-math.pi/2,color="e1d5b9",radius=0,solid=False,seed=0))
for x in [3190,3240,3290]:
    p=[x,3835]
    if road_clear(p,22) and not occupied(p,22):
        insert_prop(dict(kind="grandstand",p=p,size=[35,16],angle=-.05,color="a0b5ab",radius=19.3,solid=True,seed=int(x)))

# Bridge spans are detected only over authored water. They are not graph
# intersections with other roads; endpoint/grade connectivity remains explicit.
BRIDGES=[]
for r in ROADS:
    run=[]
    for i,p in enumerate(r["points"]):
        wet=any(in_poly(p,t["points"]) for t in TERRAIN if t["kind"]=="water")
        if wet:
            if not run and i>0: run.append(r["points"][i-1])
            run.append(p)
        elif run:
            run.append(p)
            BRIDGES.append(dict(road=r["id"],points=run,width=r["width"]))
            run=[]

PROPS.extend(ADOPTED_PROPS)
# Authoring can adopt an existing generated object for direct editing.
# Match by original kind/seed/location rather than runtime array position,
# which may change when nearby roads generate different vegetation.
# Objects removed by this pass never enter the chunk spatial or collision bake.
for replacement in [p for p in PROPS if p.get("source_replacement")]:
    target=replacement["source_replacement"]
    matching=[p for p in PROPS if p is not replacement
              and not p.get("authoring_id") and p.get("kind")==target["kind"]
              and p.get("seed")==target["seed"]
              and distance(p.get("p",(0,0)),target["p"])<.025]
    if len(matching)!=1 or matching[0].get("poi"):
        raise ValueError("Adopted game scenery changed; reload current Morrow Coast before saving")
    original=matching[0]
    PROPS.remove(original)
    # Keep the native object's collision category. In particular, procedural
    # trees have a small solid trunk even though normally painted editor trees
    # are non-solid decorations.
    replacement["solid"]=bool(original.get("solid",replacement["solid"]))
    if original["kind"] in {"tree","pine","palm"}:
        replacement["radius"]=float(original.get("radius",.65))
    if replacement.get("hidden",False):
        PROPS.remove(replacement)
        continue
    if replacement["solid"] and (
        not land(replacement["p"]) or
        not road_clear(replacement["p"],replacement["radius"])):
        raise ValueError("Moved game scenery overlaps a road or unsafe world boundary")
    if replacement["solid"] and any(other is not replacement and other.get("solid")
            and distance(other["p"],replacement["p"]) <
            other.get("radius",0)+replacement["radius"]+.5
            for other in PROPS):
        raise ValueError("Moved game scenery overlaps another solid object")

# Boundaries and river banks. Gates occur only at authored bridge crossings.
for poly in [COAST,RIVER_LEFT,RIVER_RIGHT,LAKE+[LAKE[0]]]:
    for a,b in zip(poly,poly[1:]):
        if not road_clear(((a[0]+b[0])/2,(a[1]+b[1])/2),5): continue
        WALLS.append([list(a),list(b)])
WALLS += [[[25,25],[25,HEIGHT-25]],[[25,25],[COAST[0][0],25]],[[25,HEIGHT-25],[COAST[-1][0],HEIGHT-25]]]
for bridge in BRIDGES:
    pts=bridge["points"]
    for side in [-1,1]:
        edge=[]
        for i,p in enumerate(pts):
            a,b=pts[max(0,i-1)],pts[min(len(pts)-1,i+1)]
            length=max(distance(a,b),.001)
            offset=side*(bridge["width"]/2+1)
            edge.append([p[0]-(b[1]-a[1])/length*offset,p[1]+(b[0]-a[0])/length*offset])
        WALLS.extend([[a,b] for a,b in zip(edge,edge[1:])])
# Road-cut faces occupy only the uphill shoulder; rails protect the downhill edge.
# Sample shared vertex normals so adjacent facets meet without cracks.
RELIEF_FACES, MOUNTAIN_RAILS = [], []
for r in ROADS:
    if r["kind"]!="mountain": continue
    pts=r["points"]
    def roadside(i,side,offset):
        a,b=pts[max(0,i-1)],pts[min(len(pts)-1,i+1)]
        length=max(distance(a,b),.001)
        return [pts[i][0]-(b[1]-a[1])/length*side*offset,pts[i][1]+(b[0]-a[0])/length*side*offset]
    traveled=0
    for i,(p,q) in enumerate(zip(pts,pts[1:])):
        length=distance(p,q)
        if length<.01: continue
        n=[-(q[1]-p[1])/length,(q[0]-p[0])/length]
        mid=[(p[k]+q[k])/2 for k in (0,1)]
        rise=height_m(mid[0]+n[0]*30,mid[1]+n[1]*30)-height_m(mid[0]-n[0]*30,mid[1]-n[1]*30)
        side=1 if rise>=0 else -1
        toe_offset=r["width"]/2+3.2
        lip_offset=toe_offset+4+min(4,abs(rise)*.08)
        toe=[roadside(i,side,toe_offset),roadside(i+1,side,toe_offset)]
        lip=[roadside(i,side,lip_offset),roadside(i+1,side,lip_offset)]
        quad=toe+lip[::-1]
        cross=[]
        for k in range(4):
            a,b,c=quad[k],quad[(k+1)%4],quad[(k+2)%4]
            cross.append((b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]))
        convex=min(cross)*max(cross)>0.001
        if convex and all(road_clear(v,.1) and land(v) for v in toe+lip):
            RELIEF_FACES.append(dict(toe=toe,lip=lip,station=round(traveled,3),length=round(length,3),light=round(max(0,min(1,.5+.5*side*(n[0]*.65+n[1]*.76))),3),road=r["id"]))
        # A narrow vegetated fill slope drops away outside the downhill rail.
        if r["name"] in ["Juniper Pass","Summit Ribbon"]:
            bank_lip=[roadside(i,-side,toe_offset+1),roadside(i+1,-side,toe_offset+1)]
            bank_toe=[roadside(i,-side,toe_offset+6),roadside(i+1,-side,toe_offset+6)]
            quad=bank_toe+bank_lip[::-1]
            cross=[]
            for k in range(4):
                a,b,c=quad[k],quad[(k+1)%4],quad[(k+2)%4]
                cross.append((b[0]-a[0])*(c[1]-b[1])-(b[1]-a[1])*(c[0]-b[0]))
            if min(cross)*max(cross)>.001 and all(road_clear(v,.1) and land(v) for v in quad):
                RELIEF_FACES.append(dict(toe=bank_toe,lip=bank_lip,station=round(traveled,3),length=round(length,3),light=.35,kind="earth",road=r["id"]))
        rail=[roadside(i,-side,r["width"]/2+2.7),roadside(i+1,-side,r["width"]/2+2.7)]
        if all(road_clear(v,.1) and land(v) for v in rail):
            # Stay clear of junction mouths and entrances.
            if all(distance(mid,NODES[key])>22 for key in [r["start"],r["end"]]):
                MOUNTAIN_RAILS.append(dict(points=rail,post=int(traveled/6)!=int((traveled+length)/6)))
                WALLS.append(rail)
        traveled+=length
short_walls=[]
for a,b in WALLS:
    pieces=max(1,math.ceil(distance(a,b)/24))
    for i in range(pieces):
        short_walls.append([[a[k]+(b[k]-a[k])*i/pieces for k in (0,1)], [a[k]+(b[k]-a[k])*(i+1)/pieces for k in (0,1)]])
WALLS=short_walls


def intersect(a,b,c,d):
    vx,vy=b[0]-a[0],b[1]-a[1]
    wx,wy=d[0]-c[0],d[1]-c[1]
    denominator=vx*wy-vy*wx
    if abs(denominator)<1e-8: return None
    tx,ty=c[0]-a[0],c[1]-a[1]
    t=(tx*wy-ty*wx)/denominator
    u=(tx*vy-ty*vx)/denominator
    if -1e-5<=t<=1.00001 and -1e-5<=u<=1.00001: return [a[0]+t*vx,a[1]+t*vy]
    return None


# Bake chunk membership once, leaving runtime streaming as cheap index lookups.
CHUNKS=collections.defaultdict(lambda:dict(segments=[],props=[],walls=[],junctions=[],terrain=[],relief=[],rails=[]))
for i,s in enumerate(SEGMENTS):
    r=ROADS[s["road"]]; a,b=s["a"],s["b"];pad=r["width"]/2+5
    for key in keys_for((min(a[0],b[0])-pad,min(a[1],b[1])-pad,max(a[0],b[0])+pad,max(a[1],b[1])+pad),CHUNK): CHUNKS[key]["segments"].append(i)
for i,p in enumerate(PROPS):
    CHUNKS[f"{int(p['p'][0]//CHUNK)},{int(p['p'][1]//CHUNK)}"]["props"].append(i)
for i,face in enumerate(RELIEF_FACES):
    p=[sum(v[k] for v in face["toe"]+face["lip"])/4 for k in (0,1)]
    CHUNKS[f"{int(p[0]//CHUNK)},{int(p[1]//CHUNK)}"]["relief"].append(i)
for i,rail in enumerate(MOUNTAIN_RAILS):
    a,b=rail["points"]
    CHUNKS[f"{int((a[0]+b[0])*.5//CHUNK)},{int((a[1]+b[1])*.5//CHUNK)}"]["rails"].append(i)
for i,(a,b) in enumerate(WALLS):
    key=f"{int((a[0]+b[0])*.5//CHUNK)},{int((a[1]+b[1])*.5//CHUNK)}"
    CHUNKS[key]["walls"].append(i)
for i,j in enumerate(JUNCTIONS):
    p=j["p"];radius=j["radius"]+8
    for key in keys_for((p[0]-radius,p[1]-radius,p[0]+radius,p[1]+radius),CHUNK): CHUNKS[key]["junctions"].append(i)


def clip_rect(poly,x0,y0,x1,y1):
    for axis,bound,greater in [(0,x0,True),(0,x1,False),(1,y0,True),(1,y1,False)]:
        if not poly: return []
        output=[]
        for a,b in zip(poly,poly[1:]+poly[:1]):
            ia=a[axis]>=bound if greater else a[axis]<=bound
            ib=b[axis]>=bound if greater else b[axis]<=bound
            if ia: output.append(a)
            if ia!=ib:
                t=(bound-a[axis])/(b[axis]-a[axis])
                output.append([a[k]+t*(b[k]-a[k]) for k in (0,1)])
        poly=output
    return poly


for x in range(math.ceil(WIDTH/CHUNK)):
    for y in range(math.ceil(HEIGHT/CHUNK)):
        chunk=CHUNKS[f"{x},{y}"]
        for t in TERRAIN:
            clipped=clip_rect(t["points"],x*CHUNK,y*CHUNK,(x+1)*CHUNK,(y+1)*CHUNK)
            if len(clipped)>=3: chunk["terrain"].append(dict(kind=t["kind"],color=t["color"],points=clipped))

# Validation is performed on actual baked centerlines, including facilities.
adj=collections.defaultdict(set)
for a,b in connections: adj[a].add(b);adj[b].add(a)
seen={0}; pending=[0]
while pending:
    for nxt in adj[pending.pop()]-seen: seen.add(nxt);pending.append(nxt)
assert len(seen)==len(ROADS), f"Disconnected roads: {set(range(len(ROADS)))-seen}"
bad=[p for p in PROPS if p["solid"] and not road_clear(p["p"],p["radius"])]
assert not bad, f"Scenery obstructs a road: {bad[:2]}"
bad_walls=[]
for wall_index,(a,b) in enumerate(WALLS):
    indices=set()
    for key in keys_for((min(a[0],b[0])-2,min(a[1],b[1])-2,max(a[0],b[0])+2,max(a[1],b[1])+2),CELL):
        indices.update(GRID.get(key,[]))
    for index in indices:
        s=SEGMENTS[index];c,d=s["a"],s["b"]
        separation=0 if intersect(a,b,c,d) is not None else min(near(a,c,d)[0],near(b,c,d)[0],near(c,a,b)[0],near(d,a,b)[0])
        if separation<1.2:
            bad_walls.append((wall_index,ROADS[s["road"]]["name"]));break
assert not bad_walls,f"Boundary blocks vehicle centerline: {bad_walls[:5]}"
assert all(land(p["position"]) for p in POIS)
assert all(distance(NODES[r["start"]],r["points"][0])<.01 and distance(NODES[r["end"]],r["points"][-1])<.01 for r in ROADS)
length=sum(distance(a,b) for s in SEGMENTS for a,b in [(s["a"],s["b"])])
data=dict(format="streetbound.streamed-world",version=1,name="Morrow Coast",units="metres",pixels_per_metre=20,
          size=[WIDTH,HEIGHT],chunk_size=CHUNK,surface_cell=CELL,spawn=SPAWN,nodes=NODES,roads=ROADS,segments=SEGMENTS,
          props=PROPS,pois=POIS,districts=DISTRICTS,terrain=TERRAIN,walls=WALLS,junctions=JUNCTIONS,bridges=BRIDGES,
          road_connections=sorted(connections),surface_index=GRID,chunks=CHUNKS,road_crossings=CROSSINGS,
           editor_markers=EDITOR_MARKERS,
          relief_faces=RELIEF_FACES,mountain_rails=MOUNTAIN_RAILS,
          visual_relief=dict(extent=[2800,2400],sun_direction=[-.65,-.76],maximum_m=1000),
          stats=dict(road_km=round(length/1000,2),roads=len(ROADS),props=len(PROPS),junctions=len(JUNCTIONS),connected_roads=len(seen)))
destination=ROOT/"worlds"/"morrow-coast.world.json"
destination.write_text(json.dumps(data,separators=(",",":")),encoding="utf-8")

# A reviewable vector atlas uses exactly the playable road geometry.
svg=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {WIDTH} {HEIGHT}" width="1600" height="1200">',
     f'<rect width="{WIDTH}" height="{HEIGHT}" fill="#a3b789"/>']
for t in TERRAIN:
    pts=" ".join(f"{x:.1f},{y:.1f}" for x,y in t["points"])
    svg.append(f'<polygon points="{pts}" fill="#{t["color"]}"/>')
for r in ROADS:
    pts=" ".join(f"{x:.1f},{y:.1f}" for x,y in r["points"])
    svg.append(f'<polyline points="{pts}" fill="none" stroke="#e3d9be" stroke-width="{r["width"]+10}" stroke-linecap="round" stroke-linejoin="round"/>')
    svg.append(f'<polyline points="{pts}" fill="none" stroke="#67736e" stroke-width="{r["width"]}" stroke-linecap="round"/>')
for d in DISTRICTS:
    x,y=d["p"]
    svg.append(f'<text x="{x}" y="{y}" font-family="sans-serif" font-size="65" text-anchor="middle" fill="#324d45" stroke="#eee6d1" stroke-width="2" paint-order="stroke">{d["name"]}</text>')
for p in POIS:
    x,y=p["position"]
    svg.append(f'<circle cx="{x}" cy="{y}" r="18" fill="#f4dfaa" stroke="#3d6255" stroke-width="6"/>')
svg.append('<text x="230" y="4620" font-family="sans-serif" font-size="90" fill="#344f44">MORROW COAST / STREETBOUND</text></svg>')
(ROOT/"worlds"/"morrow-coast-overview.svg").write_text("\n".join(svg),encoding="utf-8")
print(json.dumps(data["stats"],indent=2))
print(f"World: {WIDTH/1000} × {HEIGHT/1000} km; {destination.stat().st_size/1024/1024:.2f} MiB")
