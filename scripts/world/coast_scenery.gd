extends Node2D
const Art = preload("res://scripts/world/coast_art.gd")
const PPM := 20.0
var prop_list: Array[Dictionary] = []
var origin_m := Vector2.ZERO
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material = preload("res://scripts/world/scenery_cutout.tres")
func point(raw: Array) -> Vector2:
	return (Vector2(float(raw[0]),float(raw[1]))-origin_m)*PPM
func _draw() -> void:
	for prop in prop_list:
		_draw_prop(prop)
	draw_set_transform(Vector2.ZERO)

func _rounded(rect: Rect2, color: Color, radius := 12.0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, rect)

func _draw_prop(prop: Dictionary) -> void:
	var center := point(prop.p)
	var size := Vector2(float(prop.size[0]),float(prop.size[1]))*PPM
	var color := Color(prop.color)
	var kind: String = prop.kind
	var seed_value := int(prop.seed)
	draw_set_transform(center,float(prop.angle))
	var sprite: Texture2D = Art.sprite(kind,seed_value)
	if sprite!=null:
		var tint := Color.WHITE
		if kind in ["house","building","warehouse"]:
			tint = Color(1.0,0.98,0.94) if seed_value%2==0 else Color(0.94,0.98,1.0)
		draw_texture_rect(sprite,Rect2(-size/2,size),false,tint)
		if prop.has("poi"):
			draw_set_transform(center)
			draw_string(ThemeDB.fallback_font,Vector2(-size.x*.4,-size.y*.3),str(prop.poi).to_upper(),HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("fff0d4"))
		return
	if kind in ["tree","pine","palm"]:
		var radius := size.x*.5
		# Top-down overlapping canopies; subtle warm footing, no hard cast shadow.
		draw_circle(Vector2(0,4),radius*1.02,Color("7c956c"))
		if kind == "palm":
			for i in 7:
				var direction := Vector2.from_angle(float(i)*TAU/7)
				draw_line(Vector2.ZERO,direction*radius,color,22,true)
				draw_line(direction*radius*.4,direction.rotated(.32)*radius*.8,color.lightened(.08),10,true)
		else:
			for i in 5:
				var offset := Vector2.from_angle(float(i)*TAU/5)*radius*.33
				draw_circle(offset,radius*.7,color.lightened(float(i%3)*.035))
			draw_circle(Vector2(-radius*.22,-radius*.19),radius*.58,color.lightened(.1))
		return
	if kind == "field":
		_rounded(Rect2(-size/2,size),color,50)
		for side in [-1.0,1.0]:
			draw_line(Vector2(-size.x*.48,side*size.y*.47),Vector2(size.x*.48,side*size.y*.47),Color("8d9f76"),7,true)
			for post in range(int(size.x/80)):
				var p := Vector2(-size.x*.46+post*80,side*size.y*.47)
				draw_circle(p,4,Color("aeaa87"))
		for row in range(int(size.y/100)):
			var y := -size.y/2+55+row*100
			draw_line(Vector2(-size.x/2+35,y),Vector2(size.x/2-35,y),color.darkened(.09),13,true)
		return
	if kind in ["start_line","finish_line"]:
		for row in 2:
			for column in int(size.x/12):
				var p := Vector2(-size.x/2+column*12,-size.y/2+row*12)
				draw_rect(Rect2(p,Vector2(12,12)),Color("e6dec7") if (column+row)%2==0 else Color("536764"))
		return
	if kind == "grandstand":
		_rounded(Rect2(-size/2,size),Color("c2c5b4"),12)
		for row in 5:
			var y := -size.y*.4+row*size.y*.18
			draw_line(Vector2(-size.x*.46,y),Vector2(size.x*.46,y),color.lightened(row*.02),18,true)
		_rounded(Rect2(Vector2(-size.x*.5,-size.y*.5),Vector2(size.x,size.y*.22)),Color("7b9b94"),9)
		return
	if kind == "garden":
		_rounded(Rect2(-size/2,size),color,22)
		for i in 4:
			var p := Vector2(-size.x*.35+i*size.x*.23,0)
			draw_circle(p,14,Color("c7b984") if i%2==0 else Color("aeb984"))
		return
	if kind == "planter":
		_rounded(Rect2(-size/2,size),Color("b8b5a0"),10)
		draw_circle(Vector2.ZERO,size.x*.39,color)
		for i in 5:
			draw_circle(Vector2.from_angle(i*TAU/5)*size.x*.25,5,Color("d5bf9c"))
		return
	if kind == "forecourt":
		_rounded(Rect2(-size/2,size),Color("8b9290"),18)
		return
	if kind == "lot":
		_rounded(Rect2(-size/2,size),Color("d0c9b7"),45)
		_rounded(Rect2(-size/2+Vector2.ONE*18,size-Vector2.ONE*36),Color("8b9290"),32)
		for side in [-1.0,1.0]:
			for i in 8:
				var x := -size.x*.4+i*size.x*.105
				draw_line(Vector2(x,side*size.y*.44),Vector2(x,side*size.y*.22),Color("ded8bf"),3,true)
		return
	if kind == "parked_car":
		_rounded(Rect2(-size/2,size),color.darkened(.18),9)
		_rounded(Rect2(-size/2+Vector2(3,5),size-Vector2(6,10)),color,8)
		_rounded(Rect2(Vector2(-size.x*.37,-size.y*.17),Vector2(size.x*.74,size.y*.42)),Color("708e93"),7)
		_rounded(Rect2(Vector2(-size.x*.31,-size.y*.02),Vector2(size.x*.62,size.y*.18)),color.lightened(.08),5)
		draw_line(Vector2(-size.x*.3,-size.y*.42),Vector2(size.x*.3,-size.y*.42),Color("e5dcc2"),3)
		return
	if kind == "rock":
		_rounded(Rect2(-size/2,size),color.darkened(.07),size.y*.4)
		_rounded(Rect2(-size*.35,size*.68),color.lightened(.09),size.y*.28)
		return
	if kind == "island":
		draw_circle(Vector2.ZERO,size.x/2+7,Color("ded2ba"))
		draw_circle(Vector2.ZERO,size.x/2,color)
		for i in 9:
			var p := Vector2.from_angle(i*TAU/9)*size.x*.33
			draw_circle(p,19,Color("d7bc94"))
			draw_circle(p*.3,22,Color("6d916c"))
		return
	if kind == "dock":
		_rounded(Rect2(-size/2,size),color,7)
		for i in range(int(size.y/16)):
			draw_line(Vector2(-size.x/2,-size.y/2+i*16),Vector2(size.x/2,-size.y/2+i*16),color.darkened(.12),2)
		# Small moored boat, a soft rounded hull and warm canvas cabin.
		_rounded(Rect2(Vector2(size.x*.7,-size.y*.1),Vector2(50,155)),Color("e6e0c9"),24)
		_rounded(Rect2(Vector2(size.x*.7+10,0),Vector2(30,60)),Color("6b939a"),10)
		return
	if kind == "lamp":
		draw_line(Vector2.ZERO,Vector2(18,0),Color("7a827a"),4,true)
		draw_circle(Vector2(19,0),7,Color("dfd2a9"))
		return
	# Buildings are modular roof illustrations. Palette and layout distinguish
	# town houses, shops, downtown blocks, warehouses and destination facilities.
	_rounded(Rect2(-size/2-Vector2.ONE*9,size+Vector2.ONE*18),Color("b1b59f"),17)
	_rounded(Rect2(-size/2,size),color.darkened(.16),14)
	var inset := Vector2(10,10)
	_rounded(Rect2(-size/2+inset,size-inset*2),color,12)
	if kind in ["house","coastal_house","lodge"]:
		var roof := color.darkened(.10) if kind=="house" else color.lightened(.04)
		_rounded(Rect2(-size/2+Vector2(9,13),size-Vector2(18,26)),roof,11)
		draw_line(Vector2(-size.x*.39,0),Vector2(size.x*.39,0),roof.lightened(.16),9,true)
		for side in [-1.0,1.0]:
			for i in 3:
				var p := Vector2(-size.x*.28+i*size.x*.28,side*size.y*.39)
				_rounded(Rect2(p-Vector2(13,8),Vector2(26,16)),Color("cfdbd4"),3)
		_rounded(Rect2(Vector2(size.x*.2,-size.y*.25),Vector2(25,32)),Color("baaa96"),4)
		for i in range(int(size.y/24)):
			var y := -size.y*.4+float(i)*22
			draw_line(Vector2(-size.x*.4,y),Vector2(size.x*.4,y),Color(0.3,0.3,0.25,.035),2)
	else:
		var roof := color.lightened(.07)
		_rounded(Rect2(-size/2+Vector2.ONE*15,size-Vector2.ONE*30),roof,8)
		var cols := maxi(2,int(size.x/90))
		for i in cols:
			var p := Vector2(-size.x*.32+i*size.x*.64/maxf(cols-1,1),-size.y*.28)
			_rounded(Rect2(p,Vector2(33,45)),Color("93b0af"),5)
		if kind in ["garage","workshop","warehouse","fuel"]:
			for i in 3:
				var y := -size.y*.32+i*size.y*.28
				_rounded(Rect2(Vector2(-size.x/2-4,y),Vector2(24,size.y*.20)),Color("8eaaa5"),4)
			_rounded(Rect2(Vector2(size.x*.12,-size.y*.1),Vector2(48,55)),Color("b5bcb0"),6)
			for i in 5:
				draw_line(Vector2(size.x*.12+8,-size.y*.1+8+i*9),Vector2(size.x*.12+40,-size.y*.1+8+i*9),Color("98a79e"),3)
		else:
			for side in [-1.0,1.0]:
				_rounded(Rect2(Vector2(-size.x*.34,side*size.y*.43),Vector2(size.x*.68,12)),Color("759a9b"),3)
	# Small service apron on the front-facing edge, outside the solid footprint.
	if kind in ["garage","workshop","showroom","fuel","cafe"]:
		_rounded(Rect2(Vector2(-size.x/2-55,-size.y*.3),Vector2(48,size.y*.6)),Color("c4c0ad"),9)
		var stripe := Color("c88e73") if kind in ["garage","workshop"] else Color("89a49b")
		draw_line(Vector2(-size.x/2,-size.y*.36),Vector2(-size.x/2,size.y*.36),stripe,10,true)
	if prop.has("poi"):
		draw_set_transform(center)
		var text_position := Vector2(-size.x*.4,-size.y*.3)
		draw_string(ThemeDB.fallback_font,text_position,str(prop.poi).to_upper(),HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("f1e5cc"))
