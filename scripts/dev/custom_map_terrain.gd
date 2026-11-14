extends Node2D
const PPM=20.0
const Ground=preload("res://scripts/world/coast_chunk.gd")
const COLORS={"grass":"#a3b789","forest":"#658768","city":"#a7ada8","beach":"#d7c89b","mountain":"#8b9992","rock":"#9d9c8d","desert":"#d6bd83","farmland":"#9eae73"}
var doc: Dictionary={}
var land_material: ShaderMaterial
var water_material: ShaderMaterial
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
   var bands: Array=[]
   for i in 9:
    var depth: float=[0.0,1.5,3.0,6.0,12.0,24.0,48.0,96.0,192.0][i]
    var shapes: Array=[points] if i==0 else Geometry2D.offset_polygon(points,-depth*PPM,Geometry2D.JOIN_ROUND)
    var ink:=Color("#649c98").lerp(Color("#244e68") if region.biome=="ocean" else Color("#2c6467"),float(i)/8)
    for shape in shapes:bands.append({"shape":shape,"color":ink})
   canvas.draw.connect(func():
    for band in bands:
     if band.shape.size()>=3:canvas.draw_colored_polygon(band.shape,band.color))
  else:
   var biome: String=region.biome
   canvas.draw.connect(func():canvas.draw_polygon(points,PackedColorArray([Color(COLORS.get(biome,"#a3b789"))]),Ground.terrain_uvs(points.size(),biome),Ground.terrain_texture()))
