extends Node2D
const Geometry=preload("res://scripts/world/mountain_barrier_geometry.gd")
var regions: Array[Dictionary]=[]
var cache: Dictionary={}
var collision_enabled:=false
var body: StaticBody2D
var selected_id:=""
func _ready() -> void:
	material=Geometry.shared_material();z_index=1
	body=StaticBody2D.new();body.collision_mask=2;add_child(body)
func configure(doc: Dictionary,initial: Dictionary,selected: String,enabled: bool) -> void:
	regions.clear();selected_id=selected;collision_enabled=enabled
	for region in doc.get("regions",[]):
		if not Geometry.solid(region):continue
		var unchanged:=false
		for original in initial.get("regions",[]):
			if str(original.id)==str(region.id):unchanged=JSON.stringify(original)==JSON.stringify(region);break
		if not unchanged:regions.append(region)
	if is_instance_valid(body):
		body.collision_layer=1 if enabled else 0
		for child in body.get_children():body.remove_child(child);child.queue_free()
		for region in regions:
			var collider:=CollisionPolygon2D.new();var points:=Geometry.polygon(region)
			for i in points.size():points[i]*=20.0
			collider.polygon=points;collider.set_meta("draft_terrain_id",str(region.id));body.add_child(collider)
	queue_redraw()
func _draw() -> void:
	for region in regions:
		Geometry.draw_art(self,region,cache)
		if str(region.id)==selected_id:
			var line:=Geometry.polygon(region)
			for i in line.size():line[i]*=20.0
			line.append(line[0]);draw_polyline(line,Color("#ffb653"),4,true)
