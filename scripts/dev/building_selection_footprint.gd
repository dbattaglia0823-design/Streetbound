extends RefCounted
## Editor-only footprint picking. Building sprites may contain large transparent
## margins; neither the drawn selection outline nor click picking should use
## those margins as selectable geometry. This NEVER changes baked collisions,
## snapping dimensions or the saved world/asset footprint.
const ALPHA_THRESHOLD := 0.18
const SAMPLE_GRID := 160
static var _bounds_by_texture: Dictionary = {}

static func is_building_kind(kind: String) -> bool:
	return kind in ["house","coastal_house","lodge","shop","building","office",
		"hotel","cafe","warehouse","garage","workshop","showroom","fuel",
		"gas_station"]

static func _opaque_bounds(texture: Texture2D) -> Rect2:
	if texture == null:
		return Rect2(0,0,1,1)
	var key: int = texture.get_instance_id()
	if _bounds_by_texture.has(key):
		return _bounds_by_texture[key]
	var whole:=Rect2(0,0,1,1)
	var image: Image=texture.get_image()
	if image==null or image.is_empty() or image.get_width()<1 or image.get_height()<1:
		_bounds_by_texture[key]=whole
		return whole
	if image.is_compressed() and image.decompress()!=OK:
		_bounds_by_texture[key]=whole
		return whole
	var w: int=image.get_width()
	var h: int=image.get_height()
	var step_x:=maxi(1,ceili(float(w)/float(SAMPLE_GRID)))
	var step_y:=maxi(1,ceili(float(h)/float(SAMPLE_GRID)))
	var left:=w
	var top:=h
	var right:=-1
	var bottom:=-1
	# Ignore faint drop shadows. Sample at bounded cost, then add one
	# sample of padding so thin opaque roof edges remain easy to click.
	for py in range(0,h,step_y):
		for px in range(0,w,step_x):
			if image.get_pixel(px,py).a<ALPHA_THRESHOLD:
				continue
			left=mini(left,px)
			top=mini(top,py)
			right=maxi(right,px)
			bottom=maxi(bottom,py)
	var bounds:=whole
	if right>=left and bottom>=top:
		var minimum:=Vector2(maxi(0,left-step_x),maxi(0,top-step_y))
		var maximum:=Vector2(mini(w,right+step_x+1),mini(h,bottom+step_y+1))
		bounds=Rect2(Vector2(minimum.x/float(w),minimum.y/float(h)),
			Vector2((maximum.x-minimum.x)/float(w),(maximum.y-minimum.y)/float(h)))
	_bounds_by_texture[key]=bounds
	return bounds

static func selection_rect(texture: Texture2D, full_size: Vector2) -> Rect2:
	var bounds:=_opaque_bounds(texture)
	# The full asset image is drawn centered at the source position.
	# Its visible sub-rectangle can be offset, not just narrower.
	return Rect2((bounds.position-Vector2(.5,.5))*full_size,
		bounds.size*full_size)

static func hit_gap(point: Vector2, center: Vector2, angle: float,
		full_size: Vector2, texture: Texture2D) -> float:
	if full_size.x<=0.0 or full_size.y<=0.0:
		return INF
	var bounds:=selection_rect(texture,full_size)
	var local: Vector2=(point-center).rotated(-angle)
	var closest: Vector2=local.clamp(bounds.position,bounds.end)
	return local.distance_to(closest)
