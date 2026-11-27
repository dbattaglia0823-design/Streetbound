"""Compile a guarded jump and its only permissible landing strip."""
import math

from junction_bake import crossing, near

GRAVITY = 9.81
FOOTPRINT_M = 2.6
MAX_HEIGHT_M = 4.0
MAX_DISTANCE_M = 62.0
MAX_TIME_S = 2.0
LIMITS = {
    "at_m": (12, 24000),
    "length_m": (4, 20),
    "width_m": (3, 12),
    "height_m": (.25, 1.5),
    "angle_deg": (5, 18),
    "min_mps": (8, 24),
    "max_mps": (10, 26),
    "landing_length_m": (6, 42),
    "landing_width_m": (4, 16),
}


def set_jump(road, source):
    if "jump" not in source:
        return
    raw = source["jump"]
    if not isinstance(raw, dict) or raw.keys() != LIMITS.keys() | {"reverse"}:
        raise ValueError("Invalid jump settings on " + road["name"])
    for key, (low, high) in LIMITS.items():
        if type(raw[key]) not in (int, float) or not math.isfinite(raw[key]) or not low <= raw[key] <= high:
            raise ValueError(f"{road['name']}: jump {key} must be between {low} and {high}")
    if type(raw["reverse"]) is not bool or raw["min_mps"] >= raw["max_mps"]:
        raise ValueError(f"{road['name']}: invalid jump direction or speed range")
    road["jump"] = raw.copy()


def flight(height, angle_deg, speed):
    upward = speed * math.tan(math.radians(angle_deg))
    duration = (upward + math.sqrt(upward**2 + 2 * GRAVITY * height)) / GRAVITY
    return duration, speed * duration, height + upward**2 / (2 * GRAVITY)


def _inside_polygon(point, polygon):
    x, y = point
    return sum((a[1] > y) != (b[1] > y)
               and x < (b[0]-a[0])*(y-a[1])/(b[1]-a[1])+a[0]
               for a, b in zip(polygon, polygon[1:]+polygon[:1])) % 2 == 1


def _hits_rect(a, b, left, right, half_width):
    vertices = [(left,-half_width),(right,-half_width),(right,half_width),(left,half_width)]
    return (any(left <= x <= right and abs(y) <= half_width for x,y in (a,b))
            or any(crossing(a,b,c,d) is not None
                   for c,d in zip(vertices,vertices[1:]+vertices[:1])))


def bake_into(data):
    """Use finalized widths, walls, scenery and generated bridge spans."""
    candidates = [road for road in data["roads"] if "jump" in road]
    # Standalone ramps are non-solid props. Their orientation and dimensions
    # define the takeoff lip; no authored speed envelope or landing zone.
    objects = [p for p in data.get("props",[]) if p.get("kind")=="stunt_ramp"]
    # A caller may rebake the same archive after removing or resizing props.
    # Never leave stale jump records behind.
    data.pop("jumps",None)
    if not candidates and not objects:
        return
    if len(candidates) > 16:
        raise ValueError("Use at most 16 jumps per map")
    width, height = data["size"]
    placements = []
    for prop in objects:
        angle = float(prop["angle"])
        direction = [math.sin(angle),-math.cos(angle)]
        ramp_width, ramp_length = prop["size"]
        rise = ramp_length*.15
        lip = [prop["p"][i]+direction[i]*ramp_length*.5 for i in (0,1)]
        placements.append(dict(object_ramp=True,prop_id=prop["authoring_id"],road_id=-1,p=lip,
                               direction=direction,width_m=ramp_width,length_m=ramp_length,
                               height_m=rise,angle_deg=math.degrees(math.atan2(rise,ramp_length))))
    for road in candidates:
        spec = road["jump"]
        anchors = road["anchors"]
        name = road["name"]
        if len(anchors) != 2 or road.get("elevation") or road.get("grade") or road["surface"] != "ASPHALT":
            raise ValueError(f"{name}: jump needs a straight, ground-level paved road")
        a, b = anchors
        span = math.dist(a,b)
        if span < 1 or any(near(p,a,b)[0] > .12 for p in road["points"]):
            raise ValueError(f"{name}: the baked jump road must stay straight")
        tangent = [(b[i]-a[i])/span for i in (0,1)]
        origin = [a[i]+tangent[i]*spec["at_m"] for i in (0,1)]
        direction = [-v for v in tangent] if spec["reverse"] else tangent
        normal = [-direction[1],direction[0]]
        min_speed, max_speed = spec["min_mps"], spec["max_mps"]
        _, near_landing, _ = flight(spec["height_m"],spec["angle_deg"],min_speed)
        duration, far_landing, peak = flight(spec["height_m"],spec["angle_deg"],max_speed)
        landing_mid = (near_landing + far_landing) * .5
        half_length = spec["landing_length_m"] * .5
        landing_start, landing_end = landing_mid-half_length, landing_mid+half_length
        if (duration > MAX_TIME_S or peak > MAX_HEIGHT_M or landing_end > MAX_DISTANCE_M
                or landing_start < 3 or landing_start > near_landing-.65 or landing_end < far_landing+.65
                or spec["landing_width_m"] < spec["width_m"]+.5):
            raise ValueError(f"{name}: landing zone must contain every permitted trajectory within jump limits")
        left, right = -spec["length_m"]-FOOTPRINT_M, landing_end+FOOTPRINT_M
        corridor = spec["landing_width_m"]*.5 + FOOTPRINT_M
        before, after = spec["at_m"], span-spec["at_m"]
        if spec["reverse"]:
            before,after = after,before
        if min(before+left,after-right) < 0 or corridor > road["width"]*.5:
            raise ValueError(f"{name}: approach, landing, and vehicle clearance must fit on the road")

        def local(p):
            delta = [p[i]-origin[i] for i in (0,1)]
            return (sum(delta[i]*direction[i] for i in (0,1)),sum(delta[i]*normal[i] for i in (0,1)))

        corners = [[origin[i]+direction[i]*x+normal[i]*y for i in (0,1)]
                   for x in (left,right) for y in (-corridor,corridor)]
        if any(not 1 < p[0] < width-1 or not 1 < p[1] < height-1 for p in corners):
            raise ValueError(f"{name}: jump corridor reaches the map boundary")
        if any(_hits_rect(local(c),local(d),left,right,corridor) for c,d in data["walls"]):
            raise ValueError(f"{name}: jump corridor is blocked by a world wall")
        for region in data["terrain"]:
            if region["kind"] not in ("ocean","lake","water","river","reservoir") and not region.get("barrier"):
                continue
            polygon = region["points"]
            if (any(_inside_polygon(p,polygon) for p in corners)
                    or any(_hits_rect(local(c),local(d),left,right,corridor)
                           for c,d in zip(polygon,polygon[1:]+polygon[:1]))):
                raise ValueError(f"{name}: jump corridor intersects restricted terrain")
        for prop in data["props"]:
            if not prop.get("solid") and prop["kind"] not in ("guardrail","tree","oak","pine","palm"):
                continue
            if prop["kind"] == "guardrail":
                angle = prop.get("angle",0.0)
                cosine,sine = math.cos(angle),math.sin(angle)
                sx,sy = prop.get("guardrail_scale",[1.0,1.0])
                px,py = prop["p"]
                points = [(px+x*sx*cosine-y*sy*sine,py+x*sx*sine+y*sy*cosine)
                          for x,y in prop["guardrail_points"]]
                pad = float(prop["guardrail_width"]) * max(abs(sx),abs(sy)) * .5
                blocked = any(_hits_rect(local(c),local(d),left-pad,right+pad,corridor+pad)
                              for c,d in zip(points,points[1:]))
            else:
                pad = math.hypot(*prop["size"]) * .5
                x,y = local(prop["p"])
                blocked = left-pad <= x <= right+pad and abs(y) <= corridor+pad
            if blocked:
                raise ValueError(f"{name}: jump corridor overlaps {prop['kind']}")
        for other in data["roads"]:
            if other["id"] == road["id"]:
                continue
            pad = other["width"]*.5
            if any(_hits_rect(local(c),local(d),left-pad,right+pad,corridor+pad)
                   for c,d in zip(other["points"],other["points"][1:])):
                raise ValueError(f"{name}: jump corridor overlaps {other['name']}")
        placements.append(dict(spec,road_id=road["id"],p=origin,direction=direction,
                               landing_start_m=landing_start,landing_end_m=landing_end))
    data["jumps"] = placements
