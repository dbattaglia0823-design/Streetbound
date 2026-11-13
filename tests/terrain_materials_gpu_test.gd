extends SceneTree
## Run with a real renderer: --rendering-method gl_compatibility --script tests/terrain_materials_gpu_test.gd
const Chunk=preload("res://scripts/world/coast_chunk.gd")
var panels: Array[Polygon2D]=[]
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func check(label: String,ok: bool,detail: Variant="") -> void:
	print("%s %s: %s" % ["PASS" if ok else "FAIL",label,detail])
	if not ok:failures.append(label)

func panel(at: Vector2,kind: String) -> Polygon2D:
	var p:=Polygon2D.new()
	p.position=at
	p.polygon=PackedVector2Array([Vector2.ZERO,Vector2(410,0),Vector2(410,248),Vector2(0,248)])
	p.uv=Chunk.terrain_uvs(4,kind)
	p.texture=Chunk.terrain_texture()
	p.color=Color("a3b789") # Identical authored paint must still yield different materials.
	var mat:=ShaderMaterial.new()
	mat.shader=load("res://scripts/world/mountain_ground.gdshader")
	var empty:=Image.create(1,1,false,Image.FORMAT_RGBA8)
	empty.fill(Color(0,0,0,0))
	mat.set_shader_parameter("relief",ImageTexture.create_from_image(empty))
	p.material=mat
	root.add_child(p)
	return p

func run() -> void:
	check("water_aliases_share_one_material",Chunk.TERRAIN_TAGS.water==Chunk.TERRAIN_TAGS.lake)
	check("different_surfaces_have_explicit_material_tags",Chunk.TERRAIN_TAGS.grass!=Chunk.TERRAIN_TAGS.gravel)
	if DisplayServer.get_name()=="headless":
		print("SKIP GPU pixels: run this test without --headless")
		quit(0 if failures.is_empty() else 1)
		return
	root.size=Vector2i(1280,900)
	var kinds: Array[String]=["grass","forest","rock","beach","ocean","lake","farmland","city","gravel"]
	for i in kinds.size():
		var at:=Vector2(14+(i%3)*420,35+(i/3)*295)
		panels.append(panel(at,kinds[i]))
		var label:=Label.new()
		label.position=at-Vector2(0,27)
		label.text=kinds[i].to_upper()
		label.add_theme_font_size_override("font_size",19)
		root.add_child(label)
	for i in 15:await process_frame
	await RenderingServer.frame_post_draw
	var before:=root.get_texture().get_image()
	var colors: Array[Color]=[]
	for p in panels:
		var center: Vector2=p.position+Vector2(205,124)
		colors.append(before.get_pixel(int(center.x),int(center.y)))
	check("grass_and_water_are_distinct_gpu_materials",absf(colors[0].g-colors[4].g)+absf(colors[0].b-colors[4].b)>.15,colors)
	check("forest_differs_from_open_grass",absf(colors[0].g-colors[1].g)>.04)
	check("sand_is_warmer_than_rock",colors[3].r-colors[3].b>colors[2].r-colors[2].b+.1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/terrain"))
	before.save_png("res://.runtime/terrain/materials.png")
	# Re-render identical world positions as two separate chunk polygons.
	panels[0].polygon=PackedVector2Array([Vector2.ZERO,Vector2(205,0),Vector2(205,248),Vector2(0,248)])
	var second:=panels[0].duplicate() as Polygon2D
	second.position.x+=205
	root.add_child(second)
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	var after:=root.get_texture().get_image()
	var error:=0.0
	for y in range(36,282,3):
		for x in range(15,423,3):
			var a:=before.get_pixel(x,y)
			var b:=after.get_pixel(x,y)
			error=maxf(error,absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b))
	check("chunk_partition_does_not_change_terrain_pixels",error<.01,error)
	print("TERRAIN MATERIALS GPU: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
