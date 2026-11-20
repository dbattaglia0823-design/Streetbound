extends SceneTree
## Editor building clicks must follow visible alpha, not transparent image
## padding that overlaps the next narrow building. Physics bounds are separate.
const Select=preload("res://scripts/dev/building_selection_footprint.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool, detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if condition else "FAIL",label,str(detail)])
	if not condition:failures.append(label)

func _run() -> void:
	var image:=Image.create(100,100,false,Image.FORMAT_RGBA8)
	image.fill(Color(0,0,0,0))
	for y in range(10,90):
		for x in range(65,78):
			image.set_pixel(x,y,Color(1,1,1,1))
	var texture:=ImageTexture.create_from_image(image)
	var full:=Vector2(20.0,30.0)
	var visible: Rect2=Select.selection_rect(texture,full)
	check("thin_roof_does_not_select_transparent_wide_canvas",
		visible.size.x<4.0 and visible.size.y>20.0 and visible.position.x>2.0,visible)
	check("click_on_visible_thin_roof_is_valid",
		Select.hit_gap(Vector2(4.2,0),Vector2.ZERO,0,full,texture)<.01)
	check("click_on_transparent_canvas_is_rejected",
		Select.hit_gap(Vector2(-4,0),Vector2.ZERO,0,full,texture)>5)
	check("thin_facade_transform_rotates_selectable_pixels",
		Select.hit_gap(Vector2(0,4.2),Vector2.ZERO,PI*.5,full,texture)<.05 and
		Select.hit_gap(Vector2(0,-4),Vector2.ZERO,PI*.5,full,texture)>5)
	check("full_footprint_is_preserved_for_unchanged_collision",
		full==Vector2(20,30))
	check("nonbuilding_props_keep_existing_selection",
		not Select.is_building_kind("tree") and Select.is_building_kind("shop") and
		Select.is_building_kind("building"))
	var actual:=load("res://assets/Map Building Assets/Buildings/ConnectedBuilding1.png") as Texture2D
	if actual!=null:
		var real_rect: Rect2=Select.selection_rect(actual,full)
		check("real_connected_building_selection_is_bounded",
			real_rect.size.x>0 and real_rect.size.x<=full.x and real_rect.size.y>0 and real_rect.size.y<=full.y,
			real_rect)
	# The same texture should remain memoized between frequent selection clicks.
	check("cached_selection_bounds_repeat_identically",
		Select.selection_rect(texture,full)==visible)
	print("BUILDING SELECTION FOOTPRINT: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
