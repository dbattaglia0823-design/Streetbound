extends RefCounted
## Uniform, world-aligned visual relief. Kept separate from collision height.
const N:=129
const MAX_M:=1200.0

static func valid(raw: Variant) -> bool:
	if not raw is Dictionary or raw.get("size",0)!=N:return false
	var values: Variant=raw.get("values")
	if not values is Array or values.size()!=N*N:return false
	for v in values:
		if not (v is int or v is float) or not is_finite(float(v)) or float(v)<-MAX_M or float(v)>MAX_M:return false
	return true

static func blank() -> Dictionary:
	var values: Array=[]
	values.resize(N*N);values.fill(0.0)
	return {"size":N,"values":values}

static func texture(field: Dictionary) -> ImageTexture:
	if not valid(field):return null
	var image:=Image.create(N,N,false,Image.FORMAT_RF)
	for y in N:
		for x in N:image.set_pixel(x,y,Color(float(field.values[y*N+x]),0,0))
	return ImageTexture.create_from_image(image)

static func bind_material(material: ShaderMaterial,field_texture: Texture2D,extent: Vector2) -> void:
	material.set_shader_parameter("authored_height_enabled",field_texture!=null)
	if field_texture!=null:
		material.set_shader_parameter("authored_height",field_texture)
		material.set_shader_parameter("authored_height_extent",extent)

static func apply(field: Dictionary,extent: Vector2,center: Vector2,radius: float,amount: float,mode: String,level: float=0.0) -> Dictionary:
	var result: Dictionary=field.duplicate(true) if valid(field) else blank()
	var before: Array=result.values.duplicate()
	var step:=extent/float(N-1)
	radius=maxf(radius,maxf(step.x,step.y)*.75)
	for y in N:
		for x in N:
			var distance: float=(Vector2(x,y)*step).distance_to(center)
			if distance>=radius:continue
			var w:=1.0-distance/radius
			w=w*w*(3-2*w)
			var i:=y*N+x
			var old:=float(before[i])
			var target:=old
			match mode:
				"raise":target=old+amount*w
				"lower":target=old-amount*w
				"flatten":target=lerpf(old,level,clampf(amount/100.0,0,1)*w)
				"smooth":
					var sum:=0.0;var count:=0
					for dy in range(-1,2):
						for dx in range(-1,2):
							sum+=float(before[clampi(y+dy,0,N-1)*N+clampi(x+dx,0,N-1)]);count+=1
					target=lerpf(old,sum/float(count),clampf(amount/100.0,0,1)*w)
			result.values[i]=snappedf(clampf(target,-MAX_M,MAX_M),.1)
	return result

static func grade_road(field: Dictionary,extent: Vector2,path: PackedVector2Array,radius: float,level: float) -> Dictionary:
	var result: Dictionary=field.duplicate(true) if valid(field) else blank()
	var step:=extent/float(N-1)
	radius=maxf(radius,maxf(step.x,step.y))
	for y in N:
		for x in N:
			var p:=Vector2(x,y)*step
			var distance:=radius
			for i in range(1,path.size()):
				distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,path[i-1],path[i])))
			if distance>=radius:continue
			var w:=1.0-distance/radius
			w=smoothstep(0.0,1.0,w)
			var i:=y*N+x
			result.values[i]=snappedf(lerpf(float(result.values[i]),level,w),.1)
	return result

static func import_image(image: Image,minimum: float,maximum: float) -> Dictionary:
	if image==null or image.is_empty() or image.get_width()>8192 or image.get_height()>8192 or minimum>maximum or minimum < -MAX_M or maximum>MAX_M:return {}
	var sample:=image.duplicate() as Image
	sample.resize(N,N,Image.INTERPOLATE_BILINEAR)
	var result:=blank()
	for y in N:
		for x in N:result.values[y*N+x]=snappedf(lerpf(minimum,maximum,sample.get_pixel(x,y).get_luminance()),.1)
	return result
