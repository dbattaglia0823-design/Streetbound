extends Node2D
## Static cartography cache. Moving the view translates this node; redraws occur
## only on zoom changes or when a detailed view leaves its padded cache area.
var model: RefCounted
var center := Vector2.ZERO
var viewport_size := Vector2(960,700)
var ppm := 0.15
var miniature := false
var cache_area := Rect2()
var redraw_count := 0
var drawn_props := 0
var label_boxes: Array[Rect2] = []
var road_label_count := 0
var font: Font = ThemeDB.fallback_font
const ROAD_COLORS = {"highway":Color("d7b876"),"arterial":Color("f4e5c3"),"local":Color("f3efdf"),"rural":Color("e9e2c7"),"mountain":Color("e6d5b1"),"track":Color("c78c79"),"gravel":Color("b9aa8b"),"driveway":Color("e1d9c5")}
const ICON_COLORS = {"garage":Color("385b59"),"workshop":Color("647a69"),"dealer":Color("b88d58"),"fuel":Color("bd845f"),"race":Color("986e64"),"marina":Color("568b9c"),"view":Color("6e8e71")}
const Relief = preload("res://assets/scenery/mountain-relief-map.png")
const Mirror = preload("res://scripts/world/coast_map_world_mirror.gd")
var world: MorrowCoast
var mirror: Node2D
var mirror_enabled := false

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mirror=Node2D.new()
	mirror.set_script(Mirror)
	mirror.world=world
	add_child(mirror)

func point(p: Vector2) -> Vector2:
	return (p-center)*ppm+viewport_size*.5

func mapped(path: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in path: result.append(point(p))
	return result

func configure(next_center: Vector2, scale_value: float, dimensions: Vector2) -> void:
	center=next_center
	ppm=scale_value
	viewport_size=dimensions
	var overview := not miniature and ppm<.35
	cache_area=Rect2(-Vector2.ONE*100,model.extent+Vector2.ONE*200) if overview else Rect2(center-viewport_size*.5/ppm,viewport_size/ppm).grow(120/ppm)
	position=Vector2.ZERO
	# No saved image: regenerate visible cells from current startup world
	# data. Both views use this identical mirror and therefore agree.
	mirror_enabled=mirror.configure(center,ppm,viewport_size,model.extent)
	queue_redraw()

func label(value: String, at: Vector2, size: int, color: Color, angle := 0.0) -> bool:
	var dimensions := font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,size)
	var rect := Rect2(at-Vector2(dimensions.x*.5,dimensions.y*.7),dimensions).grow(4)
	if absf(angle)>.05:
		rect=Rect2(at-Vector2(dimensions.x*.5,dimensions.x*.17+size*.5),Vector2(dimensions.x,dimensions.x*.34+size))
	for existing in label_boxes:
		if rect.intersects(existing): return false
	label_boxes.append(rect)
	draw_set_transform(at,angle)
	var start := Vector2(-dimensions.x*.5,size*.33)
	draw_string_outline(font,start,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,3,Color("eeeada"))
	draw_string(font,start,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
	draw_set_transform(Vector2.ZERO)
	return true

func road_width(road: Dictionary) -> float:
	var minimum := 3.7 if road.kind=="highway" else (2.6 if road.kind=="arterial" else 1.25)
	return maxf(float(road.width)*ppm,minimum)

func _draw() -> void:
	if model==null: return
	redraw_count+=1
	drawn_props=0
	road_label_count=0
	label_boxes.clear()
	if mirror_enabled:
		_draw_map_labels()
		return
	var overview := not miniature and ppm<.35
	var bounds := Rect2(point(cache_area.position),cache_area.size*ppm)
	draw_rect(bounds,Color("c0caaa"))
	var terrain_entries: Array[Dictionary] = model.terrain_in(cache_area,overview)
	for terrain in terrain_entries:
		var color: Color = terrain.color
		match terrain.kind:
			"city","town": color=Color("d0ccb8")
			"forest": color=Color("9cb199")
			"mountain": color=Color("b7c0ad")
			"highland": color=Color("c8cbb5")
			"ocean","water": color=Color("8fb9bc")
			"beach": color=Color("e6d7b1")
		var polygon := mapped(terrain.path)
		if polygon.size()>2: draw_colored_polygon(polygon,color)
		if terrain.kind=="contour" and overview:
			polygon.append(polygon[0])
			draw_polyline(polygon,Color("a7b49e"),.65,true)
	# Shared hillshade makes the atlas describe the same massif as the drive.
	draw_texture_rect(Relief,Rect2(point(Vector2.ZERO),Vector2(2800,2400)*ppm),false,Color(1,1,1,.75))
	# Water stays level and readable beneath bridges and shoreline routes.
	for terrain in terrain_entries:
		if terrain.kind in ["ocean","water"]:
			draw_colored_polygon(mapped(terrain.path),Color("8fb9bc"))
	# Parcels, footprints, gardens and optional individual tree crowns.
	for index in model.props_in(cache_area):
		var prop: Dictionary = model.data.props[index]
		var p: Vector2 = model.v(prop.p)
		if not cache_area.grow(50).has_point(p): continue
		var kind := str(prop.kind)
		var pos := point(p)
		var dimensions: Vector2 = model.v(prop.size)*ppm
		if kind in ["tree","pine","palm"]:
			if overview and index%11!=0: continue
			# Forest density reads at this scale without drawing every canopy.
			if miniature and index%4!=0: continue
			draw_circle(pos,maxf(0.65,dimensions.x*.43),Color("7f9c7e") if kind!="pine" else Color("789581"))
			drawn_props+=1
			continue
		if kind in ["lamp","start_line","finish_line"]: continue
		draw_set_transform(pos,float(prop.angle))
		var rect := Rect2(-dimensions*.5,dimensions)
		if kind=="field":
			draw_rect(rect,Color(prop.color).lightened(.07))
			draw_rect(rect,Color("a4ae87"),false,.6)
			if ppm>.4:
				for row in range(int(dimensions.y/5)):
					var y := -dimensions.y*.5+row*5
					draw_line(Vector2(-dimensions.x*.47,y),Vector2(dimensions.x*.47,y),Color("b3b88d"),.6)
		elif kind in ["garden","planter","island"]:
			draw_rect(rect,Color("9bb18b"))
		elif kind in ["lot","forecourt"]:
			draw_rect(rect,Color("b1b9b3"))
			if ppm>.4 and kind=="lot":
				for i in 8:
					var x := -dimensions.x*.4+i*dimensions.x*.105
					for side in [-1.0,1.0]: draw_line(Vector2(x,side*dimensions.y*.4),Vector2(x,side*dimensions.y*.23),Color("e7e6d5"),.8)
		elif kind=="rock":
			if not overview: draw_circle(Vector2.ZERO,maxf(1,dimensions.x*.4),Color("a2ab9b"))
		elif kind=="dock": draw_rect(rect,Color("b59e7d"))
		elif kind=="parked_car":
			if ppm>.55: draw_rect(rect,Color("829c9c"))
		else:
			draw_rect(rect,Color("8b958d").lightened(.05))
			draw_rect(rect.grow(-maxf(.4,ppm*.6)),Color("d8c3a6") if kind in ["house","coastal_house","lodge"] else Color("b9b9a9"))
			if ppm>.5:
				draw_line(Vector2(0,-dimensions.y*.4),Vector2(0,dimensions.y*.4),Color("9d9d8d"),.7)
		draw_set_transform(Vector2.ZERO)
		drawn_props+=1
	# Roads draw over parcels. True widths emerge naturally as you zoom in.
	for stage in 2:
		for entry in model.roads:
			if not cache_area.intersects(entry.bounds): continue
			var road: Dictionary = entry.source
			var path := mapped(entry.path)
			var width := road_width(road)
			draw_polyline(path,Color("667d76") if stage==0 else ROAD_COLORS.get(road.kind,Color("ede7d3")),width+1.6 if stage==0 else width,true)
	for junction in model.data.junctions:
		var p: Vector2 = model.v(junction.p)
		if cache_area.has_point(p): draw_colored_polygon(mapped(model.path_of(junction.polygon)),Color("ece5ce"))
	for bridge in model.data.bridges:
		var path := mapped(model.path_of(bridge.points))
		if cache_area.grow(60).has_point(model.v(bridge.points[0])):
			draw_polyline(path,Color("607f80"),maxf(4,float(bridge.width)*ppm+3),true)
			draw_polyline(path,Color("e9dfc7"),maxf(2,float(bridge.width)*ppm),true)
	_draw_map_labels()

func _draw_map_labels() -> void:
	var overview := not miniature and ppm < .35
	# Region names reserve space before street/landmark labels.
	if not miniature:
		for district in model.data.districts:
			var p: Vector2 = model.v(district.p)
			if cache_area.has_point(p): label(str(district.name),point(p)+Vector2(0,-52),19,Color("3f5f51"))
	# Landmarks get distinct pictograms; names use collision-aware callouts.
	for poi in model.data.pois:
		var p: Vector2 = model.v(poi.position)
		if not cache_area.has_point(p): continue
		var pos := point(p)
		var category: String = model.poi_type(poi)
		icon(pos,category,7.0 if miniature else 8.0)
		var name := str(poi.name)
		for offset in [Vector2(0,-19),Vector2(0,24),Vector2(0,-35),Vector2(0,39)]:
			if label(name,pos+offset,11 if miniature else 12,Color("314e49")): break
	# One label per named street, selecting the longest visible piece.
	var chosen: Dictionary = {}
	for entry in model.roads:
		var road: Dictionary = entry.source
		if not cache_area.intersects(entry.bounds) or road.kind=="driveway": continue
		if overview and not road.kind in ["highway","arterial","mountain"]: continue
		if not chosen.has(road.name) or float(chosen[road.name].length)<float(entry.length): chosen[road.name]=entry
	for name in chosen:
		var entry: Dictionary = chosen[name]
		var path: PackedVector2Array = entry.path
		for fraction in [.5,.28,.72]:
			var index := mini(path.size()-2,maxi(1,int(path.size()*fraction)))
			if not cache_area.has_point(path[index]): continue
			var angle := (path[index+1]-path[index-1]).angle()
			if angle>PI/2: angle-=PI
			if angle<-PI/2: angle+=PI
			if miniature and road_label_count>=3: break
			if label(name,point(path[index])+Vector2(0,-8),10 if miniature else 12,Color("5a6b60"),angle):
				road_label_count+=1
				break
	draw_set_transform(Vector2.ZERO)

func icon(at: Vector2, category: String, radius: float) -> void:
	draw_circle(at,radius+1.7,Color("f5edd9"))
	draw_circle(at,radius,ICON_COLORS.get(category,Color("54776a")))
	var ink := Color("faf2df")
	match category:
		"garage":
			draw_polyline(PackedVector2Array([at+Vector2(-4,0),at+Vector2(0,-4),at+Vector2(4,0)]),ink,1.4,true)
			draw_rect(Rect2(at+Vector2(-3,-.5),Vector2(6,5)),ink,false,1.2)
		"fuel":
			draw_rect(Rect2(at+Vector2(-3,-4),Vector2(4.5,8)),ink,false,1.3)
			draw_line(at+Vector2(2,-2),at+Vector2(4,2),ink,1.2,true)
		"race":
			draw_line(at+Vector2(-3,5),at+Vector2(-3,-4),ink,1.2,true)
			for x in 3:
				for y in 2:
					if (x+y)%2==0: draw_rect(Rect2(at+Vector2(-2+x*2,-4+y*2),Vector2(2,2)),ink)
		"marina":
			draw_line(at+Vector2(0,-4),at+Vector2(0,3),ink,1.2,true)
			draw_arc(at,4,.1,PI-.1,12,ink,1.2,true)
		"view":
			draw_polyline(PackedVector2Array([at+Vector2(-5,3),at+Vector2(-1,-3),at+Vector2(1,0),at+Vector2(3,-2),at+Vector2(5,3)]),ink,1.3,true)
		"dealer": draw_colored_polygon(PackedVector2Array([at+Vector2(0,-4),at+Vector2(4,0),at+Vector2(0,4),at+Vector2(-4,0)]),ink)
		_: draw_line(at+Vector2(-3,3),at+Vector2(3,-3),ink,2,true)
