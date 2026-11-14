extends Node2D
## GDT World Forge v2: runtime renderer and geometry reader for freeform racing worlds.
## Attach to Node2D, set world_path, or call load_world(path) directly.
## This does NOT spawn cars, compute traffic AI, or generate a 3D elevation mesh.
# This packaged preview adapter intentionally has no global class_name:
# Streetbound already includes GDTRacingWorld in worlds/world_loader.gd.

@export_file("*.json") var world_path: String = ""
@export_flags_2d_physics var blocking_layer: int = 1
@export var build_collision: bool = true
@export var draw_markers: bool = false

var world_data: Dictionary = {}
var _solid_body: StaticBody2D
var _road_cache: Dictionary = {}
var _road_pieces_cache: Dictionary = {}
var _sprite_textures: Dictionary = {}

const BIOME_COLORS = {
    "grass": Color("#728e61"), "forest": Color("#456d50"), "mountain": Color("#838578"),
    "rock": Color("#9e9580"), "beach": Color("#d9c28d"), "ocean": Color("#417f9a"),
    "lake": Color("#5b9aa9"), "city": Color("#95958b"),
    "desert": Color("#bd9e71"), "farmland": Color("#9b9d68")
}
const ROAD_COLORS = {
    "asphalt": Color("#3d4550"), "concrete": Color("#777a7c"), "dirt": Color("#a18359"),
    "gravel": Color("#888476"), "track": Color("#4b505a")
}

func _ready() -> void:
    if world_path != "":
        load_world(world_path)

func load_world(path: String) -> bool:
    if not FileAccess.file_exists(path):
        push_error("World file does not exist: " + path)
        return false
    return load_world_json(FileAccess.get_file_as_string(path))

func load_world_json(source: String) -> bool:
    var decoded: Variant = JSON.parse_string(source)
    if typeof(decoded) != TYPE_DICTIONARY:
        push_error("Racing world must be a JSON object")
        return false
    if decoded.get("format", "") != "gdt.racing-world" or int(decoded.get("version", -1)) != 2:
        push_error("Unsupported racing world format; the v1 tile loader is separate")
        return false
    if typeof(decoded.get("world", null)) != TYPE_DICTIONARY:
        return false
    var info: Dictionary = decoded["world"]
    var w: int = int(info.get("width", 0))
    var h: int = int(info.get("height", 0))
    if w < 600 or h < 600 or w > 24000 or h > 24000:
        push_error("World bounds are invalid")
        return false
    for key in ["roads", "regions", "props", "markers"]:
        if typeof(decoded.get(key, null)) != TYPE_ARRAY:
            return false
    var textures: Dictionary = {}
    for asset in decoded.get("assets", []):
        if typeof(asset) != TYPE_DICTIONARY:
            return false
        var src: String = str(asset.get("src", ""))
        var comma: int = src.find(",")
        if comma < 0:
            return false
        var header: String = src.substr(0,comma)
        var data: PackedByteArray = Marshalls.base64_to_raw(src.substr(comma + 1))
        var image: Image = Image.new()
        var status: Error = ERR_FILE_UNRECOGNIZED
        if header.begins_with("data:image/png"):
            status = image.load_png_from_buffer(data)
        elif header.begins_with("data:image/webp"):
            status = image.load_webp_from_buffer(data)
        if status != OK:
            push_error("Could not load custom sprite artwork: " + str(asset.get("id", "")))
            return false
        image.convert(Image.FORMAT_RGBA8)
        textures[str(asset.get("id", ""))] = ImageTexture.create_from_image(image)
    for prop in decoded.props:
        if not prop.has("assetPath"):
            continue
        var relative: String = str(prop.assetPath)
        if not relative.begins_with("Buildings/") or ".." in relative or "\\" in relative or ":" in relative:
            return false
        var path: String = "res://assets/"+relative
        if ResourceLoader.exists(path,"Texture2D") and (FileAccess.file_exists(path+".import") or OS.has_feature("template")):
            textures[str(prop.assetId)]=load(path)
            continue
        var image := Image.new()
        var result: Error = ERR_FILE_UNRECOGNIZED
        match path.get_extension().to_lower():
            "png":result=image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
            "webp":result=image.load_webp_from_buffer(FileAccess.get_file_as_bytes(path))
            "svg":result=image.load_svg_from_string(FileAccess.get_file_as_string(path))
        if result != OK:
            push_error("Missing project building artwork: "+relative)
            return false
        textures[str(prop.assetId)] = ImageTexture.create_from_image(image)
    _sprite_textures = textures
    world_data = decoded
    _road_cache.clear()
    _road_pieces_cache.clear()
    for road in world_data.get("roads", []):
        if typeof(road) != TYPE_DICTIONARY:
            continue
        var data: Dictionary = road
        var id: String = str(data.get("id", ""))
        var path_points: PackedVector2Array = _sample_path(data.get("points", []), bool(data.get("smooth", true)))
        _road_cache[id] = path_points
        var fragments: Array[PackedVector2Array] = []
        if data.has("renderPieces"):
            # Exporter's authoritative clipped dirt/gravel fragments.
            for raw_fragment in data.get("renderPieces", []):
                if raw_fragment is Array:
                    var points: PackedVector2Array = _make_polygon(raw_fragment)
                    if points.size() >= 2:
                        fragments.append(points)
        else:
            fragments.append(path_points)
        _road_pieces_cache[id] = fragments
    _build_junctions()
    _build_blockers()
    queue_redraw()
    return true

func get_world_size() -> Vector2:
    if world_data.is_empty():
        return Vector2.ZERO
    var world: Dictionary = world_data["world"]
    return Vector2(float(world["width"]), float(world["height"]))

func get_markers(marker_type: String = "") -> Array:
    var results: Array = []
    for entry in world_data.get("markers", []):
        if marker_type == "" or str(entry.get("type", "")) == marker_type:
            results.append(entry.duplicate(true))
    return results

func marker_position(marker: Dictionary) -> Vector2:
    return Vector2(float(marker.get("x", 0)), float(marker.get("y", 0)))

func get_road_paths() -> Array:
    var result: Array = []
    for road in world_data.get("roads", []):
        var id: String = str(road.get("id", ""))
        result.append({"id": id, "surface": road.get("surface", "asphalt"),
            "roadClass": road.get("roadClass", "city"), "width": road.get("width", 36),
            "lanes": road.get("lanes", 2),
            "points": _road_cache.get(id, PackedVector2Array()),
            "traversable_segments": _road_pieces_cache.get(id, [])})
    return result

func road_near(position: Vector2) -> Dictionary:
    var roads: Array = world_data.get("roads", [])
    # Paved has first claim regardless of authoring order. Dirt paths do
    # not report grip across the deliberate gaps cut by the exporter.
    for pass_index in 2:
        for i in range(roads.size() - 1, -1, -1):
            var road: Dictionary = roads[i]
            var loose: bool = str(road.get("surface", "")) in ["dirt", "gravel"]
            if loose != (pass_index == 1):
                continue
            var id: String = str(road.get("id", ""))
            var width: float = float(road.get("width", 0))
            for path in _road_pieces_cache.get(id, []):
                for j in range(1, path.size()):
                    var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(position, path[j - 1], path[j])
                    if nearest.distance_to(position) <= width * 0.5:
                        return road.duplicate(true)
    return {}

func get_surface_at(position: Vector2) -> String:
    var near: Dictionary = road_near(position)
    if not near.is_empty():
        return str(near.get("surface", "asphalt"))
    var regions: Array = world_data.get("regions", [])
    for i in range(regions.size() - 1, -1, -1):
        var region: Dictionary = regions[i]
        if Geometry2D.is_point_in_polygon(position, _make_polygon(region.get("points", []))):
            return str(region.get("biome", "grass"))
    if world_data.is_empty():
        return "grass"
    return str((world_data["world"] as Dictionary).get("base", "grass"))

func _make_polygon(points: Array) -> PackedVector2Array:
    var packed := PackedVector2Array()
    for entry in points:
        packed.append(Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))))
    return packed

func _sample_path(points: Array, smooth: bool) -> PackedVector2Array:
    var output := PackedVector2Array()
    if points.size() < 2:
        return output
    var vectors: Array[Vector2] = []
    for entry in points:
        vectors.append(Vector2(float(entry.get("x", 0)), float(entry.get("y", 0))))
    output.append(vectors[0])
    for i in range(vectors.size() - 1):
        var p0: Vector2 = vectors[maxi(0,i - 1)]
        var p1: Vector2 = vectors[i]
        var p2: Vector2 = vectors[i + 1]
        var p3: Vector2 = vectors[mini(vectors.size() - 1,i + 2)]
        var length: float = p1.distance_to(p2)
        var steps: int = clampi(ceili(length / 11.0), 2, 80) if smooth and vectors.size() > 2 else 1
        for j in range(1,steps + 1):
            var t: float = float(j) / float(steps)
            if not smooth or vectors.size() == 2:
                output.append(p1.lerp(p2,t))
                continue
            var d01: float = maxf(0.00001,sqrt(p0.distance_to(p1)))
            var d12: float = maxf(0.00001,sqrt(length))
            var d23: float = maxf(0.00001,sqrt(p2.distance_to(p3)))
            var m1: Vector2 = (p2 - p0) * d12 / (d01 + d12)
            var m2: Vector2 = (p3 - p1) * d12 / (d12 + d23)
            var t2: float = t * t
            var t3: float = t2 * t
            output.append((2.0 * t3 - 3.0 * t2 + 1.0) * p1 +
                (t3 - 2.0 * t2 + t) * m1 +
                (-2.0 * t3 + 3.0 * t2) * p2 +
                (t3 - t2) * m2)
    return output


# Automatic, derived planar junctions for the same interpolated road centerlines
# used by the browser. World Forge v2 JSON needs no stored intersection records.
const JUNCTION_CELL := 160.0
var _junctions: Array[Dictionary] = []

func get_intersections() -> Array:
    return _junctions.duplicate(true)

func _junction_grid_key(x: int, y: int) -> String:
    return str(x) + ":" + str(y)

func _junction_cells(a: Vector2, b: Vector2, padding: float = 0.0) -> Array[String]:
    var keys: Array[String] = []
    var min_x: int = floori((minf(a.x,b.x) - padding) / JUNCTION_CELL)
    var max_x: int = floori((maxf(a.x,b.x) + padding) / JUNCTION_CELL)
    var min_y: int = floori((minf(a.y,b.y) - padding) / JUNCTION_CELL)
    var max_y: int = floori((maxf(a.y,b.y) + padding) / JUNCTION_CELL)
    for x in range(min_x,max_x + 1):
        for y in range(min_y,max_y + 1):
            keys.append(_junction_grid_key(x,y))
    return keys

func _junction_near_segments(grid: Dictionary, position: Vector2, radius: float) -> Array:
    var hits: Array = []
    var seen: Dictionary = {}
    for key in _junction_cells(position,position,radius):
        for segment in grid.get(key,[]):
            var unique: String = str(segment.get("key",""))
            if not seen.has(unique):
                seen[unique] = true
                hits.append(segment)
    return hits

func _add_raw_junction(nodes: Array, pos: Vector2, a: String, b: String,
        kind: String, width: float) -> void:
    if a == b:
        return
    for existing in nodes:
        var roads: Array = existing.get("roads",[])
        if roads.has(a) and roads.has(b) and (existing["at"] as Vector2).distance_to(pos) < maxf(12.0,width * 0.45):
            return
    nodes.append({"at":pos,"roads":[a,b],"kind":kind})

func _junction_tangent(path: PackedVector2Array, position: Vector2) -> Vector2:
    var minimum: float = INF
    var direction := Vector2.RIGHT
    for i in range(1,path.size()):
        var a: Vector2 = path[i - 1]
        var b: Vector2 = path[i]
        var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(position,a,b)
        var dist: float = position.distance_squared_to(nearest)
        if dist < minimum and a.distance_squared_to(b) > 0.00001:
            minimum = dist
            direction = (b - a).normalized()
    return direction

func _make_junction_shape(center: Vector2, arms: Array) -> PackedVector2Array:
    var corners := PackedVector2Array()
    for i in range(arms.size()):
        for j in range(i + 1,arms.size()):
            var a: Dictionary = arms[i]
            var b: Dictionary = arms[j]
            var normal_a: Vector2 = a["normal"]
            var normal_b: Vector2 = b["normal"]
            var det: float = normal_a.cross(normal_b)
            if absf(det) < 0.22:
                continue
            var half_a: float = float(a["width"]) * 0.5 + 2.5
            var half_b: float = float(b["width"]) * 0.5 + 2.5
            var limit: float = minf(185.0,maxf(float(a["width"]),float(b["width"])) * 2.0 + 22.0)
            for sign_a in [-1.0,1.0]:
                for sign_b in [-1.0,1.0]:
                    var sa: float = sign_a * half_a
                    var sb: float = sign_b * half_b
                    var local := Vector2((sa * normal_b.y - normal_a.y * sb) / det,
                        (normal_a.x * sb - sa * normal_b.x) / det)
                    corners.append(center + local.limit_length(limit))
    if corners.size() < 3:
        var widest: float = 20.0
        for arm in arms:
            widest = maxf(widest,float(arm["width"]))
        for i in range(12):
            var a: float = float(i) * TAU / 12.0
            corners.append(center + Vector2(cos(a),sin(a)) * (widest * 0.62 + 6.0))
    return Geometry2D.convex_hull(corners)

func _build_junctions() -> void:
    _junctions.clear()
    var road_array: Array = world_data.get("roads",[])
    if road_array.size() < 2:
        return
    var grid: Dictionary = {}
    var roads_by_id: Dictionary = {}
    var raw: Array = []
    # Only compare sampled segments that occupy the same 160-unit cell.
    for road in road_array:
        var id: String = str(road.get("id",""))
        roads_by_id[id] = road
        var path: PackedVector2Array = _road_cache.get(id,PackedVector2Array())
        var added: Array = []
        for i in range(1,path.size()):
            var a: Vector2 = path[i - 1]
            var b: Vector2 = path[i]
            if a.distance_squared_to(b) < 0.000001:
                continue
            var found: Dictionary = {}
            for cell in _junction_cells(a,b):
                for other in grid.get(cell,[]):
                    var identifier: String = str(other.get("key",""))
                    if found.has(identifier):
                        continue
                    found[identifier] = true
                    var hit: Variant = Geometry2D.segment_intersects_segment(a,b,other["a"],other["b"])
                    if hit is Vector2:
                        var other_road: Dictionary = roads_by_id[str(other["road"])]
                        var loose_here: bool = str(road.get("surface", "")) in ["dirt", "gravel"]
                        var loose_other: bool = str(other_road.get("surface", "")) in ["dirt", "gravel"]
                        if loose_here != loose_other:
                            continue
                        _add_raw_junction(raw,hit,id,str(other["road"]),"crossing",
                            minf(float(road.get("width",36)),float(other_road.get("width",36))))
            added.append({"a":a,"b":b,"road":id,"key":id + "-" + str(i)})
        for segment in added:
            for cell in _junction_cells(segment["a"],segment["b"]):
                var list: Array = grid.get(cell,[])
                list.append(segment)
                grid[cell] = list
    # T connections: the end of one street reaches the other street's painted
    # footprint even when the endpoint stops before its geometric centerline.
    for road in road_array:
        var id: String = str(road.get("id",""))
        var path: PackedVector2Array = _road_cache.get(id,PackedVector2Array())
        if path.size() < 2:
            continue
        for endpoint_index in [0,path.size() - 1]:
            var p: Vector2 = path[endpoint_index]
            var own_direction: Vector2 = (path[1] - path[0]).normalized() if endpoint_index == 0 else (path[-1] - path[-2]).normalized()
            var best_by_road: Dictionary = {}
            for segment in _junction_near_segments(grid,p,220.0):
                var other_id: String = str(segment["road"])
                if id == other_id:
                    continue
                var other: Dictionary = roads_by_id[other_id]
                var loose_here: bool = str(road.get("surface","")) in ["dirt","gravel"]
                var loose_other: bool = str(other.get("surface","")) in ["dirt","gravel"]
                if loose_here != loose_other:
                    continue
                var q: Vector2 = Geometry2D.get_closest_point_to_segment(p,segment["a"],segment["b"])
                var d: float = p.distance_to(q)
                var allowance: float = float(road.get("width",36)) * 0.5 + float(road.get("shoulder",5)) + float(other.get("width",36)) * 0.5 + float(other.get("shoulder",5)) + 4.0
                if d > allowance:
                    continue
                var other_path: PackedVector2Array = _road_cache.get(other_id,PackedVector2Array())
                var joined_end: bool = p.distance_to(other_path[0]) < 20.0 or p.distance_to(other_path[-1]) < 20.0
                var direction: Vector2 = ((segment["b"] as Vector2) - (segment["a"] as Vector2)).normalized()
                if not joined_end and absf(own_direction.cross(direction)) < 0.27:
                    continue
                if not best_by_road.has(other_id) or d < float(best_by_road[other_id]["distance"]):
                    best_by_road[other_id] = {"at":(p + q) * 0.5,"distance":d,
                        "kind":"endpoint" if joined_end else "tee"}
            for other_id in best_by_road.keys():
                var proposal: Dictionary = best_by_road[other_id]
                _add_raw_junction(raw,proposal["at"],id,other_id,str(proposal["kind"]),
                    minf(float(road.get("width",36)),float((roads_by_id[other_id] as Dictionary).get("width",36))))
    # Adjacent road pairs touching the same paved space become one junction,
    # rather than stacked intersection decals.
    var merged: Array = []
    for node in raw:
        var position: Vector2 = node["at"]
        var target: Dictionary = {}
        for previous in merged:
            var tolerance: float = 12.0
            for road_id in node["roads"]:
                tolerance = maxf(tolerance,minf(52.0,float((roads_by_id[road_id] as Dictionary).get("width",36)) * 0.47))
            if (previous["at"] as Vector2).distance_to(position) <= tolerance:
                target = previous
                break
        if target.is_empty():
            merged.append({"at":position,"roads":(node["roads"] as Array).duplicate(),
                "kind":node["kind"],"count":1})
        else:
            var n: int = int(target["count"])
            target["at"] = ((target["at"] as Vector2) * n + position) / float(n + 1)
            target["count"] = n + 1
            for road_id in node["roads"]:
                if not (target["roads"] as Array).has(road_id):
                    (target["roads"] as Array).append(road_id)
            if node["kind"] == "crossing":
                target["kind"] = "crossing"
    for node in merged:
        var center: Vector2 = node["at"]
        var arms: Array = []
        var preferred_surface: String = "asphalt"
        var best_priority: float = -1.0
        for road_id in node["roads"]:
            var road: Dictionary = roads_by_id[road_id]
            var tangent: Vector2 = _junction_tangent(_road_cache[road_id],center)
            var surface: String = str(road.get("surface","asphalt"))
            var priority: float = 4.0 if surface == "asphalt" else (3.0 if surface == "concrete" else (2.0 if surface == "track" else 1.0))
            priority += float(road.get("width",36)) / 10000.0
            if priority > best_priority:
                preferred_surface = surface
                best_priority = priority
            arms.append({"id":road_id,"roadClass":road.get("roadClass","city"),
                "surface":surface,"width":road.get("width",36),"markings":road.get("markings",true),
                "normal":Vector2(-tangent.y,tangent.x),"tangent":tangent})
        var poly: PackedVector2Array = _make_junction_shape(center,arms)
        _junctions.append({"at":center,"polygon":poly,"roads":node["roads"],
            "surface":preferred_surface,"approaches":arms,"kind":node["kind"]})

func _draw_junctions() -> void:
    for node in _junctions:
        var polygon: PackedVector2Array = node["polygon"]
        if polygon.size() < 3:
            continue
        draw_colored_polygon(polygon,ROAD_COLORS.get(node["surface"],ROAD_COLORS["asphalt"]))
        var arms: Array = node["approaches"]
        var allow_stops: bool = arms.size() >= 2
        for arm in arms:
            if str(arm["roadClass"]) in ["highway","track"] or str(arm["surface"]) in ["dirt","gravel"]:
                allow_stops = false
                break
        if not allow_stops:
            continue
        var center: Vector2 = node["at"]
        for arm in arms:
            if not bool(arm["markings"]) or not str(arm["roadClass"]) in ["city","service"]:
                continue
            var tangent: Vector2 = arm["tangent"]
            var normal: Vector2 = arm["normal"]
            var half_width: float = maxf(5.0,float(arm["width"]) * 0.5 - 5.0)
            for sign in [-1.0,1.0]:
                var reach: float = 5.0
                for vertex in polygon:
                    reach = maxf(reach,(vertex - center).dot(tangent) * sign)
                var bar_center: Vector2 = center + tangent * sign * (reach + 9.0)
                draw_line(bar_center - normal * half_width,
                    bar_center + normal * half_width,Color("#f2ebd4c9"),2.4,true)

func _line(path: PackedVector2Array, width: float, color: Color) -> void:
    if path.size() > 1:
        draw_polyline(path,color,maxf(width,0.5),true)

func _offset_path(path: PackedVector2Array, amount: float) -> PackedVector2Array:
    var result := PackedVector2Array()
    for i in range(path.size()):
        var previous: Vector2 = path[maxi(0,i - 1)]
        var following: Vector2 = path[mini(path.size() - 1,i + 1)]
        var direction: Vector2 = (following - previous).normalized()
        result.append(path[i] + Vector2(-direction.y,direction.x) * amount)
    return result

func _dashes(path: PackedVector2Array, width: float, color: Color) -> void:
    var cursor: float = 0.0
    for i in range(1, path.size()):
        var a: Vector2 = path[i - 1]
        var b: Vector2 = path[i]
        var length: float = a.distance_to(b)
        if length < 0.001:
            continue
        var pos: float = 0.0
        while pos < length:
            var phase: float = fposmod(cursor + pos, 31.0)
            var remaining: float = minf(length - pos,(16.0 - phase) if phase < 16.0 else (31.0 - phase))
            if phase < 16.0:
                draw_line(a.lerp(b,pos / length),a.lerp(b,(pos + remaining) / length),color,width,true)
            pos += maxf(remaining,0.0001)
        cursor += length

func _draw_road(road: Dictionary, lines: bool) -> void:
    var id: String = str(road.get("id", ""))
    for path in _road_pieces_cache.get(id, []):
        _draw_road_piece(road, lines, path)


func _draw_road_piece(road: Dictionary, lines: bool, path: PackedVector2Array) -> void:
    if path.size() < 2:
        return
    var width: float = float(road.get("width",36))
    var shoulder: float = float(road.get("shoulder",5))
    var surface: String = str(road.get("surface","asphalt"))
    if not lines:
        _line(path,width + shoulder * 2.0,Color("#a69e8c"))
        _line(path,width + 3.0,Color("#22282b"))
        _line(path,width,ROAD_COLORS.get(surface,Color("#3d4550")))
        return
    if not bool(road.get("markings",true)) or surface == "gravel" or surface == "dirt":
        return
    var lanes: int = int(road.get("lanes",2))
    if lanes == 1:
        _dashes(path,1.5,Color("#eddfb7"))
    elif str(road.get("roadClass","")) == "highway":
        _line(_offset_path(path,-1.6),1.8,Color("#f1c96b"))
        _line(_offset_path(path,1.6),1.8,Color("#f1c96b"))
    else:
        _dashes(path,1.8,Color("#f0ddad"))
    _line(_offset_path(path,-width / 2.0 + 2.8),1.6,Color("#e0e5dc"))
    _line(_offset_path(path,width / 2.0 - 2.8),1.6,Color("#e0e5dc"))

func _draw_region(region: Dictionary) -> void:
    var poly: PackedVector2Array = _make_polygon(region.get("points",[]))
    if poly.size() < 3:
        return
    var biome: String = str(region.get("biome","grass"))
    draw_colored_polygon(poly,BIOME_COLORS.get(biome,Color("#728e61")))
    if biome == "ocean" or biome == "lake":
        var shore := poly.duplicate()
        shore.append(poly[0])
        _line(shore,10.0,Color(0.75,0.93,0.89,0.42))
    if biome == "beach":
        var outline := poly.duplicate()
        outline.append(poly[0])
        _line(outline,5.0,Color("#e5d5a8"))

func _draw_prop(entry: Dictionary) -> void:
    var position := Vector2(float(entry.get("x",0)),float(entry.get("y",0)))
    var scale_value: float = float(entry.get("scale",1))
    draw_set_transform(position,deg_to_rad(float(entry.get("rotation",0))),Vector2.ONE * scale_value)
    var kind: String = str(entry.get("type","rock"))
    var asset_id: String = str(entry.get("assetId",""))
    if _sprite_textures.has(asset_id):
        var texture: Texture2D = _sprite_textures[asset_id]
        var max_side: float = 132.0 if kind in ["building","warehouse","garage","gas_station","parking"] else 65.0
        var factor: float = max_side / maxf(float(maxi(texture.get_width(),texture.get_height())),1.0)
        var dim: Vector2 = Vector2(texture.get_width(),texture.get_height()) * factor
        if entry.has("assetSize"):
            dim=Vector2(float(entry.assetSize[0]),float(entry.assetSize[1]))
        draw_texture_rect(texture,Rect2(-dim/2.0,dim),false)
        draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
        return
    if kind in ["oak","pine","palm","bush"]:
        var color := Color("#4f915a")
        if kind == "pine":
            color = Color("#326a4d")
        elif kind == "palm":
            color = Color("#4ba17a")
        elif kind == "bush":
            color = Color("#517d56")
        draw_circle(Vector2.ZERO,24 if kind != "bush" else 17,color)
        draw_circle(Vector2(-7,-7),11,color.lightened(0.2))
    elif kind in ["house","building","warehouse","garage","gas_station","parking"]:
        var dim := Vector2(66,54)
        if kind == "building":
            dim = Vector2(76,87)
        elif kind == "warehouse" or kind == "garage":
            dim = Vector2(110,75)
        elif kind == "parking":
            dim = Vector2(135,100)
        draw_rect(Rect2(-dim / 2.0,dim),Color("#cac7b3"))
        draw_rect(Rect2(-dim / 2.0 + Vector2(5,5),dim - Vector2(10,10)),
            Color("#ab6f59") if kind == "house" else Color("#86969a"))
    elif kind in ["rock","boulder"]:
        draw_circle(Vector2(5,5),24 if kind == "boulder" else 14,Color("#89918c"))
        draw_circle(Vector2(-4,-6),10 if kind == "boulder" else 5,Color("#cbc8b7"))
    elif kind == "barrier":
        draw_rect(Rect2(-28,-6,56,12),Color("#cb6254"))
    elif kind == "dock":
        draw_rect(Rect2(-20,-55,40,110),Color("#89683f"))
    elif kind == "streetlight":
        draw_circle(Vector2.ZERO,5,Color("#e7d9a5"))
    elif kind == "sign":
        draw_rect(Rect2(-15,-14,30,15),Color("#e0d8aa"))
    draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _draw() -> void:
    if world_data.is_empty():
        return
    var size: Vector2 = get_world_size()
    var world: Dictionary = world_data["world"]
    draw_rect(Rect2(Vector2.ZERO,size),BIOME_COLORS.get(str(world.get("base","grass")),Color("#728e61")))
    for region in world_data.get("regions",[]):
        _draw_region(region)
    # Draw loose footprints first, then paved roads, even if authored later.
    # Deliberately stopped dirt branches never paint over through pavement.
    for loose_pass in [true,false]:
        for road in world_data.get("roads",[]):
            if (str(road.get("surface","")) in ["dirt","gravel"]) == loose_pass:
                _draw_road(road,false)
    for loose_pass in [true,false]:
        for road in world_data.get("roads",[]):
            if (str(road.get("surface","")) in ["dirt","gravel"]) == loose_pass:
                _draw_road(road,true)
    _draw_junctions()
    for item in world_data.get("props",[]):
        _draw_prop(item)
    for region in world_data.get("regions",[]):
        if bool(region.get("barrier",false)):
            _draw_mountain_barrier(region)
    if draw_markers:
        for marker in world_data.get("markers",[]):
            draw_circle(marker_position(marker),9.0,Color("#ffd180"))

func _build_blockers() -> void:
    if is_instance_valid(_solid_body):
        _solid_body.queue_free()
    _solid_body = null
    if not build_collision or world_data.is_empty():
        return
    _solid_body = StaticBody2D.new()
    _solid_body.name = "WorldBlocking"
    _solid_body.collision_layer = blocking_layer
    _solid_body.collision_mask = 0
    add_child(_solid_body)
    for region in world_data.get("regions",[]):
        if not str(region.get("biome","")) in ["ocean","lake"] and not bool(region.get("barrier",false)):
            continue
        var poly: PackedVector2Array = _make_polygon(region.get("points",[]))
        if poly.size() < 3:
            continue
        var collision := CollisionPolygon2D.new()
        collision.build_mode = CollisionPolygon2D.BUILD_SOLIDS
        collision.polygon = poly
        _solid_body.add_child(collision)
    for item in world_data.get("props",[]):
        var kind: String = str(item.get("type",""))
        if not kind in ["oak","pine","palm","rock","boulder","house","building","warehouse","garage","gas_station","barrier"]:
            continue
        var width: float = 35.0
        var height: float = 32.0
        if kind in ["house","building","warehouse","garage","gas_station"]:
            width = 75.0
            height = 65.0
        if kind == "warehouse" or kind == "garage":
            width = 110.0
        var scale_value: float = float(item.get("scale",1.0))
        if item.has("assetSize"):
            width=float(item.assetSize[0])
            height=float(item.assetSize[1])
        var shape := RectangleShape2D.new()
        shape.size = Vector2(width,height) * scale_value
        var node := CollisionShape2D.new()
        node.shape = shape
        node.position = Vector2(float(item.get("x",0)),float(item.get("y",0)))
        node.rotation = deg_to_rad(float(item.get("rotation",0)))
        _solid_body.add_child(node)

func _draw_mountain_barrier(region: Dictionary) -> void:
    # Self-contained artwork for exported ZIPs; no Streetbound runtime required.
    var outline := _make_polygon(region.get("points",[]))
    if outline.size()<3:
        return
    var shadow := outline.duplicate()
    for i in shadow.size():
        shadow[i]+=Vector2(7,10)
    draw_colored_polygon(shadow,Color(.05,.1,.1,.20))
    var triangles := Geometry2D.triangulate_polygon(outline)
    var sun := Vector3(-.55,-.70,.65).normalized()
    for i in range(0,triangles.size(),3):
        var face := PackedVector2Array([outline[triangles[i]],outline[triangles[i+1]],outline[triangles[i+2]]])
        var peak: Vector2=(face[0]+face[1]+face[2])/3.0
        for j in 3:
            var a: Vector2=face[j]
            var b: Vector2=face[(j+1)%3]
            var normal:=Vector3(b.x-a.x,b.y-a.y,0).cross(Vector3(peak.x-a.x,peak.y-a.y,float(region.get("elevation",80)))).normalized()
            if normal.z<0:
                normal=-normal
            var light:=clampf(normal.dot(sun),0,1)
            draw_colored_polygon(PackedVector2Array([a,b,peak]),Color("899080").darkened(.49*(1-light)))
