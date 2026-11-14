extends Node2D
const PPM=20.0
const Ground=preload("res://scripts/world/coast_chunk.gd")
const COLORS={"grass":"#a3b789","forest":"#658768","city":"#a7ada8","beach":"#d7c89b","mountain":"#8b9992","rock":"#9d9c8d","desert":"#d6bd83","farmland":"#9eae73"}
var doc: Dictionary={}
var land_material: ShaderMaterial
var water_material: ShaderMaterial
var water_cache: Dictionary={}
func update_map(source: Dictionary) -> void:
 doc=source.duplicate(true)
 if land_material==null:
  land_material=ShaderMaterial.new();land_material.shader=preload("res://scripts/world/mountain_ground.gdshader")
  var blank:=Image.create(1,1,false,Image.FORMAT_RGBA8);blank.fill(Color(0,0,0,0))
  land_material.set_shader_parameter("relief",ImageTexture.create_from_image(blank))
  water_material=ShaderMaterial.new();water_material.shader=preload("res://scripts/dev/custom_water.gdshader")
 for child in get_children():remove_child(child);child.queue_free()
 var extent:=Vector2(doc.world.width,doc.world.height)
 var base={"biome":doc.world.get("base","grass"),"points":[{"x":0,"y":0},{"x":extent.x,"y":0},{"x":extent.x,"y":extent.y},{"x":0,"y":extent.y}]}
 for region in [base]+doc.regions:
  var points:=PackedVector2Array()
  for p in region.points:points.append(Vector2(p.x,p.y)*PPM)
  if points.size()<3 or Geometry2D.triangulate_polygon(points).is_empty():continue
  var canvas:=Node2D.new();var water: bool=region.biome in ["lake","ocean"]
  canvas.material=water_material if water else land_material;add_child(canvas)
  if water:
   var holes: Array=[];var following:=false
   for later in doc.regions:
    if later==region:following=true;continue
    if following and later.biome not in ["lake","ocean"]:holes.append(later.points)
   var key:=JSON.stringify([region,holes])
   if not water_cache.has(key):
    if water_cache.size()>32:water_cache.clear()
    var shader:=water_material.duplicate() as ShaderMaterial
    var field:=shore_field(region.points,holes)
    shader.set_shader_parameter("shore_distance",field.texture)
    shader.set_shader_parameter("shore_bounds",Vector4(field.bounds.position.x,field.bounds.position.y,field.bounds.size.x,field.bounds.size.y))
    shader.set_shader_parameter("distance_scale",field.scale)
    shader.set_shader_parameter("ocean",region.biome=="ocean")
    water_cache[key]=shader
   canvas.material=water_cache[key]
   canvas.draw.connect(func():canvas.draw_colored_polygon(points,Color.WHITE))
  else:
   var biome: String=region.biome
   canvas.draw.connect(func():canvas.draw_polygon(points,PackedColorArray([Color(COLORS.get(biome,"#a3b789"))]),Ground.terrain_uvs(points.size(),biome),Ground.terrain_texture()))

func shore_field(points: Array,holes: Array) -> Dictionary:
 var bounds:=Rect2(Vector2(points[0].x,points[0].y),Vector2.ZERO)
 for p in points:bounds=bounds.expand(Vector2(p.x,p.y))
 var cell:=maxf(bounds.size.x,bounds.size.y)/128.0
 bounds=bounds.grow(cell*2)
 var width:=maxi(4,ceili(bounds.size.x/cell));var height:=maxi(4,ceili(bounds.size.y/cell))
 bounds.size=Vector2(width,height)*cell
 var distances:=PackedFloat32Array();distances.resize(width*height);distances.fill(0)
 fill_mask(distances,width,height,bounds.position,cell,points,100000.0)
 for hole in holes:fill_mask(distances,width,height,bounds.position,cell,hole,0)
 for y in range(1,height-1):
  for x in range(1,width-1):
   var i:=y*width+x
   distances[i]=minf(distances[i],minf(minf(distances[i-1],distances[i-width])+1,minf(distances[i-width-1],distances[i-width+1])+1.4142))
 for y in range(height-2,0,-1):
  for x in range(width-2,0,-1):
   var i:=y*width+x
   distances[i]=minf(distances[i],minf(minf(distances[i+1],distances[i+width])+1,minf(distances[i+width-1],distances[i+width+1])+1.4142))
 var image:=Image.create(width,height,false,Image.FORMAT_RF)
 for y in height:
  for x in width:image.set_pixel(x,y,Color(maxf(0,distances[y*width+x]-.5)*cell,0,0))
 return {"texture":ImageTexture.create_from_image(image),"bounds":bounds,"scale":1.0}

func fill_mask(distances: PackedFloat32Array,width: int,height: int,origin: Vector2,cell: float,points: Array,value: float) -> void:
 for y in height:
  var at: float=origin.y+(y+.5)*cell;var intersections: Array[float]=[]
  for i in points.size():
   var a: Dictionary=points[i];var b: Dictionary=points[(i+1)%points.size()]
   if (a.y>at)!=(b.y>at):intersections.append(float(a.x)+(at-float(a.y))*(float(b.x)-float(a.x))/(float(b.y)-float(a.y)))
  intersections.sort()
  for i in range(0,intersections.size()-1,2):
   for x in range(maxi(0,ceili((intersections[i]-origin.x)/cell-.5)),mini(width,ceili((intersections[i+1]-origin.x)/cell-.5))):distances[y*width+x]=value
