"""Deterministic automatic water crossings; mirrors road_bridge_geometry.gd.

All geometry is in metres. Derived data never changes road topology or props.
"""
import math
from collections import defaultdict

WATER = {"water", "lake", "ocean", "river"}
COSMETIC = {"foam", "riverbank"}
CELL, APPROACH, VERSION = 128.0, 3.0, 1


def bounds(points):
    return (min(p[0] for p in points), min(p[1] for p in points),
            max(p[0] for p in points), max(p[1] for p in points))


def overlaps(a, b):
    return a[0] <= b[2] and b[0] <= a[2] and a[1] <= b[3] and b[1] <= a[3]


def cells(rect, size=CELL):
    for y in range(math.floor(rect[1]/size), math.floor(rect[3]/size)+1):
        for x in range(math.floor(rect[0]/size), math.floor(rect[2]/size)+1):
            yield x, y


def inside(p, polygon):
    result = False
    for a, b in zip(polygon, polygon[1:]+polygon[:1]):
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < (b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]:
            result = not result
    return result


def cross(a, b): return a[0]*b[1]-a[1]*b[0]
def sub(a, b): return a[0]-b[0], a[1]-b[1]
def lerp(a, b, t): return [a[k]+(b[k]-a[k])*t for k in (0, 1)]
def distance(a, b): return math.dist(a, b)


def cut_parameters(a, b, edges):
    delta = sub(b, a)
    cuts = [0.0, 1.0]
    for c, d in edges:
        direction = sub(d, c)
        denominator = cross(delta, direction)
        if abs(denominator) < 1e-8: continue
        relative = sub(c, a)
        t, u = cross(relative, direction)/denominator, cross(relative, delta)/denominator
        if 0 < t < 1 and -1e-6 <= u <= 1+1e-6: cuts.append(t)
    return sorted(cuts)


class WaterMask:
    def __init__(self, terrain):
        self.layers, self.water_bounds, self.edges = [], [], []
        self.grid, self.interior = defaultdict(list), {}
        seen = False
        for raw in terrain:
            kind = raw.get("kind", raw.get("biome", ""))
            seen = seen or kind in WATER
            if not seen or kind in COSMETIC: continue
            points = raw["points"]
            if len(points) < 3: continue
            box = bounds(points)
            layer = len(self.layers)
            self.layers.append((points, box, kind in WATER))
            if kind in WATER: self.water_bounds.append(box)
            for a, b in zip(points, points[1:]+points[:1]):
                if distance(a, b) < 1e-4: continue
                index = len(self.edges)
                self.edges.append((a, b, layer))
                for key in cells(bounds([a, b])): self.grid[key].append(index)

    def _wet(self, p):
        key = math.floor(p[0]/CELL), math.floor(p[1]/CELL)
        for i in range(len(self.layers)-1, -1, -1):
            points, box, wet = self.layers[i]
            if not box[0] <= p[0] <= box[2] or not box[1] <= p[1] <= box[3] or not inside(p, points): continue
            if not wet: return False
            for index in self.grid.get(key, []):
                a, b, layer = self.edges[index]
                if layer != i: continue
                delta = sub(b, a)
                t = max(0, min(1, sum((p[k]-a[k])*delta[k] for k in (0, 1))/max(1e-12, distance(a, b)**2)))
                if distance(p, lerp(a, b, t)) < 1e-4: return False
            return True
        return False

    def is_water(self, p):
        key = math.floor(p[0]/CELL), math.floor(p[1]/CELL)
        if key in self.grid: return self._wet(p)
        if key not in self.interior: self.interior[key] = self._wet(((key[0]+.5)*CELL, (key[1]+.5)*CELL))
        return self.interior[key]

    def intervals(self, path):
        result, station = [], 0.0
        for a, b in zip(path, path[1:]):
            length = distance(a, b)
            if length < 1e-5: continue
            box = bounds([a, b])
            if not any(overlaps(box, water) for water in self.water_bounds):
                station += length
                continue
            candidates = {i for key in cells(box) for i in self.grid.get(key, [])}
            cuts = cut_parameters(a, b, [self.edges[i][:2] for i in candidates])
            for start, finish in zip(cuts, cuts[1:]):
                if (finish-start)*length < 1e-4 or not self.is_water(lerp(a, b, (start+finish)*.5)): continue
                span = [station+start*length, station+finish*length]
                if result and span[0]-result[-1][1] < .001: result[-1][1] = span[1]
                else: result.append(span)
            station += length
        return result

    def spans(self, road):
        path = road["points"]
        length = sum(distance(a, b) for a, b in zip(path, path[1:]))
        runs = []
        for a, b in self.intervals(path):
            if b-a < .25: continue
            start, finish = max(0, a-APPROACH), min(length, b+APPROACH)
            if runs and start <= runs[-1]["end"]+.001: runs[-1].update(end=finish, wet_end=b)
            else: runs.append(dict(start=start, end=finish, wet_start=a, wet_end=b))
        for run in runs:
            run.update(road=road["id"], width=road["width"], kind=road.get("kind", "rural"),
                       points=slice_path(path, run["start"], run["end"]))
        return runs


def slice_path(path, start, finish):
    result, station = [], 0.0
    for a, b in zip(path, path[1:]):
        length = distance(a, b)
        if length > 1e-5 and station+length > start+1e-5 and station < finish-1e-5:
            p, q = (lerp(a, b, max(0, min(1, (value-station)/length))) for value in (start, finish))
            if not result: result.append(p)
            if distance(result[-1], q) > 1e-5: result.append(q)
        station += length
    return result


def offset_path(path, amount):
    def unit(delta):
        length = math.hypot(*delta)
        return (delta[0]/length, delta[1]/length) if length > 1e-9 else (0, 0)
    result = []
    closed = len(path) > 3 and distance(path[0], path[-1]) < .001
    for i, p in enumerate(path):
        before = unit(sub(p, path[max(0, i-1)]))
        after = unit(sub(path[min(i+1, len(path)-1)], p))
        if i == 0: before = unit(sub(p, path[-2])) if closed else after
        if i == len(path)-1: after = unit(sub(path[1], p)) if closed else before
        normal = unit((-(before[1]+after[1]), before[0]+after[0]))
        side = -after[1], after[0]
        if math.hypot(*normal) < .5: normal = side
        miter = max(.55, normal[0]*side[0]+normal[1]*side[1])
        result.append([p[k]+normal[k]*amount/miter for k in (0, 1)])
    return result


def rail_paths(bridge, junctions=()):
    offset = bridge["width"]*.5+(3.8 if bridge.get("kind") in {"local", "arterial"} else 1.4)
    result = []
    for side in (-1, 1):
        path = offset_path(bridge["points"], side*offset)
        for a, b in zip(path, path[1:]):
            masks = [j["polygon"] for j in junctions if overlaps(bounds([a, b]), bounds(j["polygon"]))]
            cuts = cut_parameters(a, b, [(c, d) for poly in masks for c, d in zip(poly, poly[1:]+poly[:1])])
            for start, finish in zip(cuts, cuts[1:]):
                if (finish-start)*distance(a, b) < 1e-4 or any(inside(lerp(a, b, (start+finish)*.5), poly) for poly in masks): continue
                result.append([lerp(a, b, start), lerp(a, b, finish)])
    return result


def apply(world):
    # A repeated derivation replaces its own walls instead of accumulating them.
    removed=set(world.get("bridge_wall_indices",[])) if world.get("bridge_generation")==VERSION else set()
    if removed:
        remap={old:new for new,old in enumerate(i for i in range(len(world["walls"])) if i not in removed)}
        world["walls"]=[wall for i,wall in enumerate(world["walls"]) if i not in removed]
        for section in world["chunks"].values():section["walls"]=[remap[i] for i in section["walls"] if i in remap]
    mask = WaterMask(world["terrain"])
    world["bridges"] = [span for road in world["roads"] for span in mask.spans(road)]
    world["bridge_generation"], world["bridge_wall_indices"] = VERSION, []
    chunk_m = world["chunk_size"]
    maximum = [math.ceil(v/chunk_m) for v in world["size"]]
    def memberships(box):
        for x, y in cells(box, chunk_m):
            if 0 <= x < maximum[0] and 0 <= y < maximum[1]: yield f"{x},{y}"
    def chunk(key):
        return world["chunks"].setdefault(key, dict(segments=[], props=[], walls=[], junctions=[], terrain=[], relief=[], rails=[], bridges=[]))
    for section in world["chunks"].values(): section["bridges"] = []
    for i, bridge in enumerate(world["bridges"]):
        padding = bridge["width"]*.5+(3.8 if bridge["kind"] in {"local", "arterial"} else 1.4)+7
        box = bounds(bridge["points"])
        for key in memberships((box[0]-padding, box[1]-padding, box[2]+padding, box[3]+padding)):
            chunk(key)["bridges"].append(i)
        for a, b in rail_paths(bridge, world.get("junctions", [])):
            count = max(1, math.ceil(distance(a, b)/12))
            for step in range(count):
                p, q = lerp(a, b, step/count), lerp(a, b, (step+1)/count)
                index = len(world["walls"])
                world["walls"].append([p, q]); world["bridge_wall_indices"].append(index)
                box = bounds([p, q])
                for key in memberships((box[0]-.15, box[1]-.15, box[2]+.15, box[3]+.15)):
                    chunk(key)["walls"].append(index)
    return world
